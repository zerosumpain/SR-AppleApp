import SwiftUI

// MARK: - "Do it for me"
//
// A note's suggested step, carried out with one tap and no further questions
// — today, a diary entry in your own iCloud calendar, which Undo deletes. The
// site checks every plan against the note's own words before it writes
// (SR-Main `act/plan.ts`); the phone shows what will happen and asks nothing.
//
// Wire (additive — an older server sends none of it):
//
//   Note+detail  "act": { "kind"?, "status": ready|open|done|undone|sent, "label", "doneAt"?,
//                         "draft"?: { to, subject, body, gmailUrl }, "undoable"? } | null
//   POST api/native/daydream/act  { "id", "op": "do" | "undo" | "send" }   ("send": a draft's second tap)
//        → { "ok": true, "status", "label", "calendar" }
//        | { "ok": false, "reason" }
//        | { "ok": false, "reason", "needsCalendar": true, "calendars": [String] }
//   POST api/native/daydream/act  { "op": "calendar", "calendar" } → { "ok": true }  (asked once)

/// What "Do it for me" would do for a note, or did.
struct DaydreamAct: Decodable, Hashable {
    /// `sent` is a draft that went — no undo.
    enum Status: String { case ready, open, done, undone, sent }

    /// A guided kind stops at a draft for a second tap.
    struct Draft: Decodable, Hashable {
        let to: String
        let subject: String
        let body: String
        let gmailUrl: String
    }

    let status: Status
    let label: String
    let draft: Draft?
    /// Whether Undo is possible now (a reminder that fired, a sent email: no).
    let undoable: Bool

    init(status: Status, label: String, draft: Draft? = nil, undoable: Bool = true) {
        self.status = status
        self.label = label
        self.draft = draft
        self.undoable = undoable
    }

    enum CodingKeys: String, CodingKey { case status, label, draft, undoable }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw = c.lenient(String.self, .status), let status = Status(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .status, in: c, debugDescription: "an act needs a known status")
        }
        self.status = status
        label = c.lenient(String.self, .label) ?? ""
        draft = c.lenient(Draft.self, .draft)
        // An older server sends no `undoable`: a done diary entry could always be undone.
        undoable = c.lenient(Bool.self, .undoable) ?? (status == .done)
    }

    /// Offered as a choice: something to do, or something taken back.
    var canDo: Bool { status == .ready || status == .open || status == .undone }
}

struct DaydreamActRequest: Encodable, Equatable {
    let id: String?
    let op: String
    let calendar: String?
}

struct DaydreamActReply: Decodable {
    let ok: Bool?
    let status: String?
    let label: String?
    let reason: String?
    let needsCalendar: Bool?
    let calendars: [String]?
}

/// Calendars to choose from, once — `sheet(item:)` wants an identity.
struct DaydreamCalendarChoice: Identifiable {
    let noteId: String
    let calendars: [String]
    var id: String { noteId }
}

@MainActor
final class DaydreamActions: ObservableObject {
    static let shared = DaydreamActions()

    /// What was done (or undone) on this phone, over what the note arrived with.
    @Published private(set) var local: [String: DaydreamAct] = [:]
    @Published private(set) var busy: Set<String> = []
    /// The site's reason, when it would not or could not.
    @Published private(set) var message: [String: String] = [:]
    /// Set when the site asks which calendar to use — once.
    @Published var choosing: DaydreamCalendarChoice?

    private let client = SiteClient.shared

    func act(for note: DaydreamNote) -> DaydreamAct? { local[note.id] ?? note.act }
    func isBusy(_ note: DaydreamNote) -> Bool { busy.contains(note.id) }

    func run(_ op: String, for note: DaydreamNote) async {
        guard !busy.contains(note.id) else { return }
        busy.insert(note.id)
        message[note.id] = nil
        defer { busy.remove(note.id) }
        guard let reply = await post(DaydreamActRequest(id: note.id, op: op, calendar: nil)) else {
            message[note.id] = "Not done — the site could not be reached. Try again."
            return
        }
        if reply.needsCalendar == true {
            let names = reply.calendars ?? []
            if names.isEmpty { message[note.id] = "Your calendar could not be reached to choose one. Try again in a minute." }
            else { choosing = DaydreamCalendarChoice(noteId: note.id, calendars: names) }
            return
        }
        guard reply.ok == true else {
            message[note.id] = reply.reason ?? "That did not work."
            return
        }
        let status = DaydreamAct.Status(rawValue: reply.status ?? "") ?? .done
        // A fresh draft's text arrives with the next read of the page; until
        // then the card says what was drafted and offers to open it.
        let draft = status == .undone ? nil : (local[note.id]?.draft ?? note.act?.draft)
        local[note.id] = DaydreamAct(status: status, label: reply.label ?? note.act?.label ?? "", draft: draft,
                                     undoable: status == .done)
        if status == .done || status == .sent { SRHaptic.ok() }
        if op == "do", status == .done, draft == nil {
            // The site's copy now carries the draft to read; let it show.
            await DaydreamStore.shared.load()
            if DaydreamStore.shared.notes.first(where: { $0.id == note.id })?.act?.draft != nil { local[note.id] = nil }
        }
    }

    /// The one-time choice, then the action that asked for it.
    func choose(_ calendar: String, thenDo note: DaydreamNote) async {
        choosing = nil
        guard let reply = await post(DaydreamActRequest(id: nil, op: "calendar", calendar: calendar)), reply.ok == true else {
            message[note.id] = "That calendar was not kept. Try again."
            return
        }
        await run("do", for: note)
    }

    private func post(_ request: DaydreamActRequest) async -> DaydreamActReply? {
        guard let body = try? JSONEncoder().encode(request),
              let data = try? await client.post("api/native/daydream/act", body: body) else { return nil }
        return try? JSONDecoder().decode(DaydreamActReply.self, from: data)
    }
}

/// "Done — Added “Chase the bike dispatch” to your Home calendar on Sat 10 Oct · Undo",
/// or a draft to read with Send / Edit in Gmail / Discard.
struct DaydreamActBanner: View {
    let act: DaydreamAct
    let busy: Bool
    let onOp: (String) -> Void
    @Environment(\.openURL) private var openURL

    private var drafted: Bool { act.status == .done && act.draft != nil }
    private var tone: Color { act.status == .undone ? SR.inkMuted : drafted ? SR.accent : SR.good }
    private var heading: String {
        switch act.status {
        case .undone: return "UNDONE"
        case .sent: return "SENT"
        default: return drafted ? "DRAFTED" : "DONE"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading)
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(tone)
            Text(act.status == .undone ? "Taken back: \(act.label)" : act.label)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            if drafted, let draft = act.draft {
                VStack(alignment: .leading, spacing: 4) {
                    Text("To \(draft.to)").font(SR.Text.mono()).foregroundStyle(SR.inkSecondary)
                    Text(draft.subject).font(SR.Text.bodyMedium(15)).foregroundStyle(SR.ink)
                    Text(draft.body)
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SR.line, lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("daydream-act-draft")
                HStack(spacing: 10) {
                    Button { onOp("send") } label: { SRButtonLabel(title: busy ? "Sending…" : "Send it") }
                        .srButton(.prominent)
                        .disabled(busy)
                        .accessibilityIdentifier("daydream-act-send")
                    if let url = URL(string: draft.gmailUrl) {
                        Button { openURL(url) } label: { SRButtonLabel(title: "Edit in Gmail") }
                            .srButton()
                    }
                    Button { onOp("undo") } label: { SRButtonLabel(title: "Discard") }
                        .srButton()
                        .disabled(busy)
                        .accessibilityIdentifier("daydream-act-discard")
                }
                .controlSize(.small)
            } else if act.status == .done, act.undoable {
                Button {
                    SRHaptic.tap()
                    onOp("undo")
                } label: {
                    Text((busy ? "Undoing…" : "Undo").uppercased())
                        .font(SR.Text.label(12))
                        .tracking(1.1)
                        .foregroundStyle(SR.accentInk)
                        .frame(minHeight: SR.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityIdentifier("daydream-act-undo")
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle().fill(act.status == .undone ? SR.line : tone).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daydream-act-done")
    }
}

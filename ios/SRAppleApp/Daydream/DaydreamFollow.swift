import SwiftUI
import UIKit

// MARK: - "Take it further"
//
// What jkai can do with a note beyond rating it or the one "Do it for me"
// step: dig deeper, put it on the build backlog and accept its brief, a quick
// prototype, a Watch instead of a build, a message you send yourself, a Home
// Assistant refresh. Each offer says what it will use before the tap — the
// cost is ChatGPT subscription quota, not cash (SR-Main `act/follow.ts`).
//
// Nothing here sends, pays, books or cancels for you. A number or address is
// only ever one the note's sources show, found by the site's code.
//
// Wire (additive — an older server sends none of it):
//
//   Note+detail  "follow": { "bookingUrl"?, "offers": [{ kind, state, label, cost, href? }],
//                            "brief"?: { outcome, acceptance[], effort, risk, readiness, acceptedAt? },
//                            "watchDraft"?, "message"?: { text, subject, whatsapp, mailto?, email?,
//                              draft?: { to, status: drafted|sent|discarded, gmailUrl } },
//                            "home"?: { found: [{ id, name }], refreshed[], refreshedAt? } }
//                "replaces": [{ id, title }]
//   POST api/native/daydream/follow  { "id", "op", "description"?, "entities"? }
//        → { "ok": true, "message", "href"? } | { "ok": false, "reason" }

struct DaydreamFollow: Decodable, Hashable {
    enum Kind: String, CaseIterable { case research, promote, build, prototype, watch, message, home }
    enum State: String { case offer, drafted, done, stopped }

    struct Offer: Decodable, Hashable, Identifiable {
        let kind: Kind
        let state: State
        let label: String
        let cost: String
        let href: String?
        var id: String { kind.rawValue }

        enum CodingKeys: String, CodingKey { case kind, state, label, cost, href }
        init(kind: Kind, state: State, label: String, cost: String, href: String? = nil) {
            self.kind = kind; self.state = state; self.label = label; self.cost = cost; self.href = href
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let k = c.lenient(String.self, .kind).flatMap(Kind.init(rawValue:)),
                  let s = c.lenient(String.self, .state).flatMap(State.init(rawValue:)) else {
                throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "an offer this build does not know")
            }
            kind = k
            state = s
            label = c.lenient(String.self, .label) ?? ""
            cost = c.lenient(String.self, .cost) ?? ""
            href = c.lenient(String.self, .href).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    struct Brief: Decodable, Hashable {
        let outcome: String
        let acceptance: [String]
        let effort: String
        let risk: String
        let readiness: String
        let acceptedAt: String?

        enum CodingKeys: String, CodingKey { case outcome, acceptance, effort, risk, readiness, acceptedAt }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            outcome = c.lenient(String.self, .outcome) ?? ""
            acceptance = c.lossy(String.self, .acceptance)
            effort = c.lenient(String.self, .effort) ?? ""
            risk = c.lenient(String.self, .risk) ?? ""
            readiness = c.lenient(String.self, .readiness) ?? ""
            acceptedAt = c.lenient(String.self, .acceptedAt)
        }

        /// "Effort S · risk low · ready — clear".
        var meta: String {
            [effort.isEmpty ? nil : "Effort \(effort)", risk.isEmpty ? nil : "risk \(risk)", readiness.isEmpty ? nil : readiness]
                .compactMap { $0 }.joined(separator: " · ")
        }
    }

    struct Message: Decodable, Hashable {
        struct GmailDraft: Decodable, Hashable {
            let to: String
            let status: String
            let gmailUrl: String
        }
        let text: String
        let subject: String
        let whatsapp: String
        let mailto: String?
        let email: String?
        let draft: GmailDraft?

        enum CodingKeys: String, CodingKey { case text, subject, whatsapp, mailto, email, draft }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let text = c.lenient(String.self, .text), !text.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .text, in: c, debugDescription: "a message needs text")
            }
            self.text = text
            subject = c.lenient(String.self, .subject) ?? ""
            whatsapp = c.lenient(String.self, .whatsapp) ?? ""
            mailto = c.lenient(String.self, .mailto)
            email = c.lenient(String.self, .email)
            draft = c.lenient(GmailDraft.self, .draft)
        }

        /// Whether the WhatsApp link already carries the number.
        var hasNumber: Bool { whatsapp.hasPrefix("https://wa.me/") && !whatsapp.hasPrefix("https://wa.me/?") }
    }

    struct Device: Decodable, Hashable, Identifiable {
        let id: String
        let name: String
    }

    struct Home: Decodable, Hashable {
        let found: [Device]
        let refreshed: [String]
        let refreshedAt: String?

        enum CodingKeys: String, CodingKey { case found, refreshed, refreshedAt }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            found = c.lossy(Device.self, .found)
            refreshed = c.lossy(String.self, .refreshed)
            refreshedAt = c.lenient(String.self, .refreshedAt)
        }
    }

    let bookingUrl: String?
    let offers: [Offer]
    let brief: Brief?
    let watchDraft: String?
    let message: Message?
    let home: Home?

    enum CodingKeys: String, CodingKey { case bookingUrl, offers, brief, watchDraft, message, home }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookingUrl = c.lenient(String.self, .bookingUrl).flatMap { $0.hasPrefix("http") ? $0 : nil }
        // An offer this build does not know is dropped alone.
        offers = c.lossy(Offer.self, .offers)
        brief = c.lenient(Brief.self, .brief)
        watchDraft = c.lenient(String.self, .watchDraft)
        message = c.lenient(Message.self, .message)
        home = c.lenient(Home.self, .home)
    }

    var isEmpty: Bool { offers.isEmpty && bookingUrl == nil && message == nil }
    var pending: [Offer] { offers.filter { $0.state == .offer } }
    var settled: [Offer] { offers.filter { $0.state == .done || $0.state == .stopped } }
    /// A drafted brief waiting for the accept tap.
    var briefToRead: Brief? { offers.contains { $0.kind == .build && $0.state == .drafted } ? brief.flatMap { $0.acceptedAt == nil ? $0 : nil } : nil }
}

/// An older note on the same subject this one replaced.
struct DaydreamReplaced: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
}

struct DaydreamFollowRequest: Encodable, Equatable {
    let id: String
    let op: String
    let description: String?
    let entities: [String]?
}

struct DaydreamFollowReply: Decodable {
    let ok: Bool?
    let message: String?
    let href: String?
    let reason: String?
}

@MainActor
final class DaydreamFollowActions: ObservableObject {
    static let shared = DaydreamFollowActions()

    /// The op in flight, per note.
    @Published private(set) var busy: [String: String] = [:]
    /// What the site said back, per note; `bad` when it would not.
    @Published private(set) var said: [String: (text: String, bad: Bool, href: String?)] = [:]

    private let client = SiteClient.shared

    func isBusy(_ note: DaydreamNote) -> Bool { busy[note.id] != nil }
    func busyOp(_ note: DaydreamNote) -> String? { busy[note.id] }

    /// Run one tap, then re-read the page so the card shows where it went.
    @discardableResult
    func run(_ op: String, for note: DaydreamNote, description: String? = nil, entities: [String]? = nil) async -> Bool {
        guard busy[note.id] == nil else { return false }
        busy[note.id] = op
        said[note.id] = nil
        defer { busy[note.id] = nil }
        let request = DaydreamFollowRequest(id: note.id, op: op, description: description, entities: entities)
        guard let body = try? JSONEncoder().encode(request),
              let data = try? await client.post("api/native/daydream/follow", body: body),
              let reply = try? JSONDecoder().decode(DaydreamFollowReply.self, from: data) else {
            said[note.id] = ("Not done — the site could not be reached. Try again.", true, nil)
            return false
        }
        guard reply.ok == true else {
            said[note.id] = (reply.reason ?? "That did not work.", true, nil)
            return false
        }
        SRHaptic.ok()
        said[note.id] = (reply.message ?? "Done.", false, reply.href)
        await DaydreamStore.shared.load()
        return true
    }
}

/// The "Take it further" block on a note card.
struct DaydreamFollowSection: View {
    let note: DaydreamNote
    let follow: DaydreamFollow
    @ObservedObject private var actions = DaydreamFollowActions.shared
    @Environment(\.openURL) private var openURL
    /// Which guided panel is open before its tap.
    @State private var open: DaydreamFollow.Kind?
    @State private var watchText = ""
    @State private var picked: Set<String> = []
    @State private var copied = false

    private var busy: Bool { actions.isBusy(note) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TAKE IT FURTHER")
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
                .accessibilityAddTraits(.isHeader)
            if let booking = follow.bookingUrl, let url = URL(string: booking) {
                Button { openURL(url) } label: {
                    Label("Open the booking page · \(url.host ?? booking)", systemImage: "safari")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.accentInk)
                        .frame(minHeight: SR.tapTarget, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("daydream-follow-booking")
            }
            ForEach(follow.pending) { offer in offerRow(offer) }
            ForEach(follow.settled) { offer in settledRow(offer) }
            if let brief = follow.briefToRead { briefPanel(brief) }
            if open == .prototype { prototypePanel }
            if open == .watch { watchPanel }
            if let message = follow.message { messagePanel(message) }
            if let home = follow.home { homePanel(home) }
            if let said = actions.said[note.id] {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(said.text)
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(said.bad ? SR.warn : SR.good)
                        .fixedSize(horizontal: false, vertical: true)
                    if let href = said.href { openLink(href) }
                }
                .accessibilityIdentifier("daydream-follow-said")
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daydream-follow")
    }

    // MARK: - Offers

    private func offerRow(_ offer: DaydreamFollow.Offer) -> some View {
        Button { tap(offer) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon(offer.kind))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SR.accentInk)
                    .frame(width: 24, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(working(offer) ?? offer.label)
                        .font(SR.Text.bodyMedium(16))
                        .foregroundStyle(SR.ink)
                    Text(offer.cost)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: SR.tapTarget, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(open == offer.kind ? SR.accentInk : SR.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier("daydream-follow-\(offer.kind.rawValue)")
    }

    private func settledRow(_ offer: DaydreamFollow.Offer) -> some View {
        HStack(spacing: 10) {
            Image(systemName: offer.state == .stopped ? "stop.circle" : "checkmark.circle.fill")
                .foregroundStyle(offer.state == .stopped ? SR.inkMuted : SR.good)
                .accessibilityHidden(true)
            Text(offer.label)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(offer.state == .stopped ? SR.inkSecondary : SR.ink)
            Spacer(minLength: 6)
            if let href = offer.href { openLink(href) }
            if offer.kind == .watch, offer.state == .done {
                textButton(actions.busyOp(note) == "unwatch" ? "Stopping…" : "Stop") { go("unwatch") }
                    .accessibilityIdentifier("daydream-follow-unwatch")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daydream-follow-done-\(offer.kind.rawValue)")
    }

    private func tap(_ offer: DaydreamFollow.Offer) {
        SRHaptic.tap()
        switch offer.kind {
        case .research: go("research")
        case .promote: go("promote")
        case .build: go("draft_brief")
        case .message: go("message")
        case .home: go("home_check")
        case .watch:
            watchText = follow.watchDraft ?? ""
            open = open == .watch ? nil : .watch
        case .prototype:
            open = open == .prototype ? nil : .prototype
        }
    }

    private func go(_ op: String, description: String? = nil, entities: [String]? = nil) {
        let note = self.note
        Task {
            if await actions.run(op, for: note, description: description, entities: entities) { open = nil }
        }
    }

    // MARK: - Guided panels

    private func briefPanel(_ brief: DaydreamFollow.Brief) -> some View {
        panel("THE BRIEF IT WOULD BUILD FROM", id: "daydream-follow-brief") {
            if !brief.outcome.isEmpty {
                Text(brief.outcome).font(SR.Text.body(15)).foregroundStyle(SR.ink).fixedSize(horizontal: false, vertical: true)
            }
            if !brief.acceptance.isEmpty {
                Text("Done when:").font(SR.Text.bodyMedium(14)).foregroundStyle(SR.ink)
                ForEach(Array(brief.acceptance.enumerated()), id: \.offset) { _, line in
                    Text("– \(line)").font(SR.Text.secondary(14)).foregroundStyle(SR.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !brief.meta.isEmpty { Text(brief.meta).font(SR.Text.mono()).foregroundStyle(SR.inkMuted) }
            Text("Accepting queues it for the overnight builder — one a night, about 3.4M tokens of the subscription.")
                .font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { go("accept_build") } label: { SRButtonLabel(title: actions.busyOp(note) == "accept_build" ? "Accepting…" : "Accept for build") }
                    .srButton(.prominent)
                    .disabled(busy)
                    .accessibilityIdentifier("daydream-follow-accept")
                Button { go("draft_brief") } label: { SRButtonLabel(title: actions.busyOp(note) == "draft_brief" ? "Redrafting…" : "Redraft") }
                    .srButton()
                    .disabled(busy)
            }
            .controlSize(.small)
        }
    }

    private var prototypePanel: some View {
        panel("START A PROTOTYPE NOW?", id: "daydream-follow-prototype-panel") {
            Text("A one-page sketch, built in the sandbox — no site code, no pull request. It stops at 45 minutes or 1.5M tokens, and you get a preview link.")
                .font(SR.Text.secondary(14)).foregroundStyle(SR.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { go("prototype") } label: { SRButtonLabel(title: actions.busyOp(note) == "prototype" ? "Starting…" : "Start the prototype") }
                    .srButton(.prominent)
                    .disabled(busy)
                    .accessibilityIdentifier("daydream-follow-prototype-start")
                Button { open = nil } label: { SRButtonLabel(title: "Cancel") }.srButton()
            }
            .controlSize(.small)
        }
    }

    private var watchPanel: some View {
        panel("WHAT SHOULD IT WATCH FOR?", id: "daydream-follow-watch-panel") {
            TextField("Tell me when…", text: $watchText, axis: .vertical)
                .lineLimit(3...6)
                .font(SR.Text.body(15))
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SR.line, lineWidth: 1))
                .accessibilityIdentifier("daydream-follow-watch-text")
            Text("It checks every 6 hours unless you say otherwise. Setting it up takes about a minute.")
                .font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { go("watch", description: watchText) } label: { SRButtonLabel(title: actions.busyOp(note) == "watch" ? "Setting it up…" : "Start watching") }
                    .srButton(.prominent)
                    .disabled(busy || watchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 12)
                    .accessibilityIdentifier("daydream-follow-watch-start")
                Button { open = nil } label: { SRButtonLabel(title: "Cancel") }.srButton()
            }
            .controlSize(.small)
        }
    }

    private func messagePanel(_ message: DaydreamFollow.Message) -> some View {
        panel("MESSAGE — YOU SEND IT", id: "daydream-follow-message") {
            Text(message.text)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SR.line, lineWidth: 1))
            if let draft = message.draft {
                Text(draft.status == "sent" ? "Sent to \(draft.to)" : draft.status == "discarded" ? "Gmail draft discarded" : "In your Gmail drafts, to \(draft.to)")
                    .font(SR.Text.mono()).foregroundStyle(SR.inkSecondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { messageButtons(message) }
                VStack(alignment: .leading, spacing: 8) { messageButtons(message) }
            }
            .controlSize(.small)
            if let draft = message.draft, draft.status == "drafted" {
                HStack(spacing: 10) {
                    Button { go("gmail_send") } label: { SRButtonLabel(title: actions.busyOp(note) == "gmail_send" ? "Sending…" : "Send it") }
                        .srButton(.prominent)
                        .disabled(busy)
                        .accessibilityIdentifier("daydream-follow-gmail-send")
                    if let url = URL(string: draft.gmailUrl) {
                        Button { openURL(url) } label: { SRButtonLabel(title: "Edit in Gmail") }.srButton()
                    }
                    Button { go("gmail_discard") } label: { SRButtonLabel(title: "Discard") }
                        .srButton()
                        .disabled(busy)
                }
                .controlSize(.small)
            }
            HStack(spacing: 16) {
                textButton(copied ? "Copied" : "Copy the text") {
                    UIPasteboard.general.string = message.text
                    copied = true
                    SRHaptic.ok()
                }
                textButton(actions.busyOp(note) == "message" ? "Redrafting…" : "Redraft") { go("message") }
            }
            if !message.hasNumber && message.email == nil {
                Text("None of its sources gives a number or address, so WhatsApp asks you who it is for.")
                    .font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func messageButtons(_ message: DaydreamFollow.Message) -> some View {
        if let url = URL(string: message.whatsapp) {
            Button { openURL(url) } label: { SRButtonLabel(title: "Open in WhatsApp") }
                .srButton()
                .accessibilityIdentifier("daydream-follow-whatsapp")
        }
        if let mailto = message.mailto, let url = URL(string: mailto) {
            Button { openURL(url) } label: { SRButtonLabel(title: "Open in Mail") }
                .srButton()
                .accessibilityIdentifier("daydream-follow-mail")
        }
        if message.email != nil, message.draft == nil || message.draft?.status == "discarded" {
            Button { go("gmail_draft") } label: { SRButtonLabel(title: actions.busyOp(note) == "gmail_draft" ? "Drafting…" : "Draft it in Gmail") }
                .srButton()
                .disabled(busy)
                .accessibilityIdentifier("daydream-follow-gmail-draft")
        }
    }

    @ViewBuilder
    private func homePanel(_ home: DaydreamFollow.Home) -> some View {
        if home.refreshedAt != nil {
            HStack(spacing: 10) {
                Text("Refreshed \(home.refreshed.count) device\(home.refreshed.count == 1 ? "" : "s").")
                    .font(SR.Text.secondary(14)).foregroundStyle(SR.inkSecondary)
                textButton("Look again") { go("home_check") }
            }
        } else {
            panel(home.found.isEmpty ? "NOTHING IS UNAVAILABLE NOW" : "UNAVAILABLE NOW — PICK UP TO FIVE", id: "daydream-follow-home") {
                ForEach(home.found) { device in
                    Toggle(isOn: Binding(
                        get: { picked.contains(device.id) },
                        set: { on in
                            if on, picked.count < 5 { picked.insert(device.id) } else if !on { picked.remove(device.id) }
                        }
                    )) {
                        Text(device.name).font(SR.Text.body(15)).foregroundStyle(SR.ink)
                    }
                    .tint(SR.accent)
                }
                if !home.found.isEmpty {
                    Text("Asks Home Assistant to update each one and reload its integration. Nothing is switched on, off or unlocked.")
                        .font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    if !home.found.isEmpty {
                        Button { go("home_refresh", entities: Array(picked)) } label: {
                            SRButtonLabel(title: actions.busyOp(note) == "home_refresh" ? "Refreshing…" : picked.isEmpty ? "Refresh" : "Refresh \(picked.count)")
                        }
                        .srButton(.prominent)
                        .disabled(busy || picked.isEmpty)
                        .accessibilityIdentifier("daydream-follow-home-refresh")
                    }
                    textButton("Look again") { go("home_check") }
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Pieces

    private func panel<Content: View>(_ heading: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.accentInk)
            content()
        }
        .padding(.vertical, 10)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SR.accentInk.opacity(0.06))
        .overlay(alignment: .leading) { Rectangle().fill(SR.accentInk).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(SR.Text.label(12))
                .tracking(1.1)
                .foregroundStyle(SR.accentInk)
                .frame(minHeight: SR.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    /// A site path opens on the website; anything else as given.
    private func openLink(_ href: String) -> some View {
        textButton("Open") {
            let url: URL? = href.hasPrefix("/") ? SiteClient.shared.webURL(href) : URL(string: href)
            if let url { openURL(url) }
        }
    }

    private func working(_ offer: DaydreamFollow.Offer) -> String? {
        guard let op = actions.busyOp(note) else { return nil }
        let mine: [DaydreamFollow.Kind: String] = [.research: "research", .promote: "promote", .build: "draft_brief", .message: "message", .home: "home_check"]
        guard mine[offer.kind] == op else { return nil }
        return offer.kind == .build ? "Drafting the brief…" : offer.kind == .home ? "Looking…" : offer.kind == .message ? "Drafting…" : "Starting…"
    }

    private func icon(_ kind: DaydreamFollow.Kind) -> String {
        switch kind {
        case .research: return "doc.text.magnifyingglass"
        case .promote: return "tray.and.arrow.down"
        case .build: return "hammer"
        case .prototype: return "cube.transparent"
        case .watch: return "eye"
        case .message: return "bubble.left.and.text.bubble.right"
        case .home: return "house"
        }
    }
}

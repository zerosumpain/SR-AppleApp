import Foundation
import SwiftUI

// MARK: - Past its date
//
// The site flags a note nobody has answered once the day it is likely to
// matter has gone: the date it is about, the loop's own estimate, or three
// days for a note with neither (SR-Main `think/shelf.ts`). The phone shows
// the flag on the card, with the same two answers as the web, and a line on
// the Daydream page with the count — most flagged notes are older than the
// forty the page holds, so the count is the site's and "Show them" fetches
// them on their own.
//
// Wire contract (SR-Main, `/api/native/*`, the site credential):
//
//   GET  api/native/daydream?detail=1&limit=40      → { …, "stale": 136 }   (key optional)
//   GET  api/native/daydream?detail=1&stale=1&limit=80 → only the flagged notes
//        each flagged note carries "stale": { "until", "basis", "why" }
//   POST api/native/daydream/shelf  { "id", "op": "file" }      → { "ok", "filed" }
//                                   { "all": true, "op": "file" } → { "ok", "filed" }
//                                   { "id", "op": "keep" }      → { "ok", "until" }
//
// Filing is not a verdict: the kind's weight does not move. "Still relevant"
// keeps the note off the flag for a fortnight.

/// Why a note is probably past its date.
struct DaydreamStale: Decodable, Hashable {
    /// `yyyy-MM-dd`, the last day it was likely to matter.
    let until: String
    /// `date`, `stated` or `age`.
    let basis: String
    /// One sentence, the site's words.
    let why: String

    init(until: String, basis: String, why: String) {
        self.until = until
        self.basis = basis
        self.why = why
    }

    enum CodingKeys: String, CodingKey { case until, basis, why }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let why = c.lenient(String.self, .why), !why.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .why, in: c, debugDescription: "a flag needs a reason")
        }
        self.why = why
        until = c.lenient(String.self, .until) ?? ""
        basis = c.lenient(String.self, .basis) ?? ""
    }
}

/// The body of `POST api/native/daydream/shelf`.
struct DaydreamShelfRequest: Encodable, Equatable {
    let id: String?
    let all: Bool?
    let op: String

    static func file(_ id: String) -> Self { Self(id: id, all: nil, op: "file") }
    static func keep(_ id: String) -> Self { Self(id: id, all: nil, op: "keep") }
    static let fileAll = Self(id: nil, all: true, op: "file")
}

/// What filing and keeping did, shared by every card and the page.
///
/// Not optimistic: a filed note leaves the list only once the site says so,
/// because filing a hundred notes is not something to show and then take back.
@MainActor
final class DaydreamShelf: ObservableObject {
    static let shared = DaydreamShelf()

    /// The site's count of notes past their date. `nil` from an older server.
    /// A fresh count already leaves out what was filed or kept here.
    @Published var count: Int? { didSet { moved = [] } }
    /// Flagged notes filed or kept here since the count was read.
    @Published private var moved: Set<String> = []
    /// The flagged notes, for "Show them".
    @Published private(set) var notes: [DaydreamNote] = []
    @Published private(set) var loadingNotes = false
    /// Filed here; gone from every list until the next read agrees.
    @Published private(set) var filed: Set<String> = []
    /// Kept here ("Still relevant"); the flag is gone from the card.
    @Published private(set) var kept: Set<String> = []
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var filingAll = false
    /// The last refusal, in words, by note id ("" for "File them all").
    @Published private(set) var message: [String: String] = [:]

    static let listLimit = 80
    private let client = SiteClient.shared

    func isStale(_ note: DaydreamNote) -> Bool {
        note.stale != nil && !kept.contains(note.id) && !filed.contains(note.id)
    }

    func isFiled(_ note: DaydreamNote) -> Bool { filed.contains(note.id) }
    func isBusy(_ note: DaydreamNote) -> Bool { busy.contains(note.id) || filingAll }

    /// The count, less what was filed or kept here since the last read.
    var remaining: Int? {
        count.map { max(0, $0 - moved.count) }
    }

    /// The flagged notes on their own, for the "past their date" list.
    func loadNotes() async {
        guard AccessStore.ownerSite, !loadingNotes else { return }
        loadingNotes = true
        defer { loadingNotes = false }
        do {
            let feed: DaydreamFeed = try await client.send("api/native/daydream?detail=1&stale=1&limit=\(Self.listLimit)")
            notes = feed.notes.filter { $0.stale != nil }
            if let stale = feed.stale { count = stale }
        } catch let error as URLError where error.code == .cancelled {
        } catch is CancellationError {
        } catch {
            message[""] = "The list did not load. Pull to try again."
        }
    }

    func file(_ note: DaydreamNote) async {
        guard !busy.contains(note.id) else { return }
        if await send(.file(note.id), key: note.id) != nil {
            SRHaptic.ok()
            withAnimation(.easeOut(duration: 0.3)) {
                _ = filed.insert(note.id)
                if note.stale != nil { _ = moved.insert(note.id) }
            }
        }
    }

    func keep(_ note: DaydreamNote) async {
        guard !busy.contains(note.id) else { return }
        if await send(.keep(note.id), key: note.id) != nil {
            SRHaptic.tap()
            withAnimation(.easeOut(duration: 0.3)) {
                _ = kept.insert(note.id)
                if note.stale != nil { _ = moved.insert(note.id) }
            }
        }
    }

    /// Every note the site flags right now — not just the ones this phone
    /// holds. Then both lists are read again, so the counts are the site's.
    func fileAll() async {
        guard !filingAll else { return }
        filingAll = true
        defer { filingAll = false }
        guard await send(.fileAll, key: "") != nil else { return }
        SRHaptic.ok()
        withAnimation(.easeOut(duration: 0.3)) {
            for note in notes { filed.insert(note.id) }
            for note in DaydreamStore.shared.notes where note.stale != nil { filed.insert(note.id) }
            count = 0
        }
        await DaydreamStore.shared.load()
    }

    private func send(_ request: DaydreamShelfRequest, key: String) async -> Reply? {
        busy.insert(key)
        message[key] = nil
        defer { busy.remove(key) }
        do {
            let body = try JSONEncoder().encode(request)
            let data = try await client.post("api/native/daydream/shelf", body: body)
            let reply = (try? JSONDecoder().decode(Reply.self, from: data)) ?? Reply(ok: true, error: nil)
            if reply.ok == false { throw SiteError.message(reply.error ?? "The site did not keep that.") }
            return reply
        } catch {
            message[key] = "Not saved. Try again."
            return nil
        }
    }

    private struct Reply: Decodable { let ok: Bool?; let error: String? }
}

// MARK: - Views

/// Inside a card: "Probably past its date", the site's reason, and the two
/// answers.
struct DaydreamStaleBanner: View {
    let note: DaydreamNote
    let stale: DaydreamStale
    @ObservedObject private var shelf = DaydreamShelf.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text("PROBABLY PAST ITS DATE")
                    .font(SR.Text.label())
                    .tracking(1.2)
            }
            .foregroundStyle(SR.warn)
            Text(stale.why)
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    Task { await shelf.file(note) }
                } label: {
                    SRButtonLabel(title: shelf.isBusy(note) ? "Filing…" : "File it", icon: "archivebox")
                }
                .srButton(.prominent)
                .accessibilityIdentifier("daydream-file-it")
                Button {
                    Task { await shelf.keep(note) }
                } label: {
                    SRButtonLabel(title: "Still relevant", icon: "clock.arrow.circlepath")
                }
                .srButton()
                .accessibilityIdentifier("daydream-still-relevant")
            }
            .disabled(shelf.isBusy(note))
            if let message = shelf.message[note.id] {
                Text(message)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.error)
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SR.warn.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle().fill(SR.warn).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daydream-stale")
    }
}

/// On the Daydream page: how many notes are past their date, the way in to
/// them, and "File them all". Hidden when there are none, and from an older
/// server that sends no count.
struct DaydreamPastDateLine: View {
    /// False on the list itself, which needs no way in to itself.
    var showsLink = true
    @ObservedObject private var shelf = DaydreamShelf.shared
    @State private var confirming = false

    var body: some View {
        if let remaining = shelf.remaining, remaining > 0 {
            SRCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 12, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("PAST THEIR DATE")
                            .font(SR.Text.label())
                            .tracking(1.2)
                    }
                    .foregroundStyle(SR.warn)
                    Text(remaining == 1
                         ? "One note looks past its date and is still unanswered."
                         : "\(remaining) notes look past their date and are still unanswered.")
                        .font(SR.Text.body(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        if showsLink {
                            NavigationLink {
                                DaydreamPastDateScreen()
                            } label: {
                                SRButtonLabel(title: "Show them", icon: "list.bullet")
                            }
                            .srButton()
                            .accessibilityIdentifier("daydream-past-date-show")
                        }
                        Button {
                            SRHaptic.tap()
                            confirming = true
                        } label: {
                            SRButtonLabel(title: shelf.filingAll ? "Filing…" : (remaining == 1 ? "File it" : "File them all"), icon: "archivebox")
                        }
                        .srButton(.prominent)
                        .disabled(shelf.filingAll)
                        .accessibilityIdentifier("daydream-file-all")
                    }
                    if let message = shelf.message[""] {
                        Text(message)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.error)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("daydream-past-date")
            .confirmationDialog(
                remaining == 1 ? "File the note past its date?" : "File all \(remaining) notes past their date?",
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button(remaining == 1 ? "File it" : "File them all") {
                    Task { await shelf.fileAll() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They leave the Inbox. Filing is not a “Not for me” — what jkai learns does not change.")
            }
        }
    }
}

/// The flagged notes on their own, each with its card.
struct DaydreamPastDateScreen: View {
    @ObservedObject private var shelf = DaydreamShelf.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                Text("Notes nobody has answered whose date has gone. File them, or keep the ones that still matter.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                DaydreamPastDateLine(showsLink: false)
                let showing = shelf.notes.filter { shelf.isStale($0) }
                if showing.isEmpty {
                    if shelf.loadingNotes {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        SREmpty(title: "Nothing past its date", icon: "checkmark.circle",
                                message: "Every note still waiting is recent, or has a date still to come.")
                    }
                } else {
                    ForEach(showing) { note in
                        DaydreamNoteCard(note: note)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("daydream-past-date-screen")
        .srGround(.quiet)
        .navigationTitle("Past their date")
        .navigationBarTitleDisplayMode(.inline)
        .task { await shelf.loadNotes() }
        .srRefreshable { await shelf.loadNotes() }
    }
}

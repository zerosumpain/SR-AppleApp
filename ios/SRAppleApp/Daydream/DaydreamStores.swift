import Foundation
import Combine
import SwiftUI

/// The reader's verdicts on notes, shared by every screen that shows one.
///
/// One instance for the app, not one per screen: a health-plan note can sit on
/// Today AND on the Health tab, and a thumbs-up given on one must already be
/// showing on the other.
///
/// Optimistic. The chosen verdict shows the moment it is tapped; if the POST
/// fails it goes back to what it was and the row says, quietly, that it did
/// not save. No banner — a lost thumbs-up is not worth interrupting anybody.
@MainActor
final class NoticedFeedback: ObservableObject {
    static let shared = NoticedFeedback()

    /// Verdicts given on this phone, over whatever the note arrived with.
    @Published private(set) var chosen: [String: DaydreamVerdict] = [:]
    /// Notes whose last verdict did not reach the site.
    @Published private(set) var failed: Set<String> = []
    @Published private(set) var sending: Set<String> = []
    /// Notes rated here whose moment on screen is over.
    @Published private(set) var settled: Set<String> = []

    /// How long a rated note stays, showing what was chosen, before it goes.
    var settleDelay: Duration = .seconds(3)

    private let client = SiteClient.shared

    func verdict(for note: DaydreamNote) -> DaydreamVerdict? {
        chosen[note.id] ?? note.feedback
    }

    /// Whether a note still belongs on screen: not yet rated, or rated here a
    /// moment ago and still showing the answer. A note that arrives already
    /// rated (on the site, or on this phone before a relaunch) is done.
    func isShowing(_ note: DaydreamNote) -> Bool {
        if settled.contains(note.id) { return false }
        if chosen[note.id] != nil { return true }
        return note.feedback == nil
    }

    func didFail(_ note: DaydreamNote) -> Bool { failed.contains(note.id) }

    /// Record a verdict. Choosing the verdict already standing is a no-op —
    /// the contract has no "clear", so a second tap must not pretend to undo.
    func record(_ verdict: DaydreamVerdict, for note: DaydreamNote) async {
        let previous = self.verdict(for: note)
        guard previous != verdict, !sending.contains(note.id) else { return }
        chosen[note.id] = verdict
        failed.remove(note.id)
        sending.insert(note.id)
        defer { sending.remove(note.id) }
        do {
            let body = try JSONEncoder().encode(DaydreamFeedbackRequest(id: note.id, verdict: verdict))
            let reply = try await client.post("api/native/daydream/feedback", body: body)
            // `{ "ok": false }` with a 200 is still a refusal.
            if let answer = try? JSONDecoder().decode(FeedbackReply.self, from: reply), answer.ok == false {
                throw SiteError.message("The site did not keep that.")
            }
        } catch {
            chosen[note.id] = previous
            failed.insert(note.id)
            return
        }
        settleSoon(note.id, verdict: verdict)
    }

    /// Take the note away once the reader has seen the answer land — unless
    /// they changed it in the meantime, in which case that later answer's own
    /// timer does it.
    private func settleSoon(_ id: String, verdict: DaydreamVerdict) {
        let delay = settleDelay
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.chosen[id] == verdict else { return }
            withAnimation(.easeOut(duration: 0.35)) { _ = self.settled.insert(id) }
        }
    }

    private struct FeedbackReply: Decodable { let ok: Bool? }
}

/// The Health tab's notes: `api/native/daydream?scope=health&limit=5`.
///
/// Silent by design. The Health tab has an answer for a health service that is
/// down; it does not need a second error card for a list of observations. A
/// failed call is an empty list, and an empty list is no section at all.
@MainActor
final class HealthNoticedStore: ObservableObject {
    @Published private(set) var notes: [DaydreamNote] = []
    private var loading = false

    private let client = SiteClient.shared

    func load() async {
        guard AccessStore.ownerSite, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let feed: DaydreamFeed = try await client.send("api/native/daydream?scope=health&limit=5")
            notes = Array(feed.notes.prefix(5))
        } catch let error as URLError where error.code == .cancelled {
            // The tab went away mid-request. Not an answer; keep what was there.
        } catch is CancellationError {
        } catch {
            notes = []
        }
    }
}

/// Every note the phone has seen lately, for Today's Daydream tile and the
/// Daydream page in More: `api/native/daydream?limit=20`.
///
/// One instance, because the tile and the page must agree on how many are
/// new. Today's own payload seeds it (two notes, no second request), and
/// the page reads the longer list when it opens. Notes are merged by id, not
/// replaced: Today's five-minute re-read carries only the latest two, and
/// must not shrink a list the page already fetched.
@MainActor
final class DaydreamStore: ObservableObject {
    static let shared = DaydreamStore()

    @Published private(set) var notes: [DaydreamNote] = []
    @Published private(set) var loading = false
    /// Whether the page's own read has answered at least once.
    @Published private(set) var loaded = false

    static let pageLimit = 20
    private let client = SiteClient.shared

    /// Newest first, one row per id; a later copy of a note wins (it carries
    /// the latest verdict).
    static func merge(_ held: [DaydreamNote], _ incoming: [DaydreamNote]) -> [DaydreamNote] {
        var byId: [String: DaydreamNote] = [:]
        for note in held { byId[note.id] = note }
        for note in incoming { byId[note.id] = note }
        return byId.values.sorted { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt > rhs.createdAt
        }
    }

    func seed(_ feed: DaydreamFeed?) {
        guard let feed, !feed.notes.isEmpty else { return }
        notes = Self.merge(notes, feed.notes)
    }

    /// Silent, like the Health tab's: a failed read keeps what Today seeded.
    func load() async {
        guard AccessStore.ownerSite, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let feed: DaydreamFeed = try await client.send("api/native/daydream?limit=\(Self.pageLimit)")
            notes = Self.merge(notes, feed.notes)
        } catch let error as URLError where error.code == .cancelled {
        } catch is CancellationError {
        } catch {
        }
        loaded = true
    }
}

import Foundation
import Combine

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

    private let client = SiteClient.shared

    func verdict(for note: DaydreamNote) -> DaydreamVerdict? {
        chosen[note.id] ?? note.feedback
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
        guard client.isPaired, !loading else { return }
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

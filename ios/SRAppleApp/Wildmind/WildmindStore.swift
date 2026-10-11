import Foundation
import SwiftUI

/// The valley, for the Wildmind page in More: `GET api/native/wildmind`.
///
/// One instance, so leaving the page and coming back draws the last answer at
/// once instead of a spinner, and the terrain is not fetched twice.
///
/// **The terrain is kept by version.** It is the heavy half of the answer
/// (about 25 KB against 2 KB for everything else), and it only changes when
/// somebody sees a new tile. The store sends the version it holds as `?have=`
/// and the site leaves the grid out when it matches.
///
/// **Polled only while the page is on screen** — the screen runs `poll()` in
/// its own task, which SwiftUI cancels when the page goes — at the web
/// chapter's cadence: every ten seconds while they are awake, thirty while
/// resting, paused or between lives, a minute when the valley is not
/// answering.
///
/// **Never a crash, rarely a blank.** A failed poll keeps the last good answer
/// and, two minutes on, calls it stale, as the site would. A site without the
/// native route (a 404 — the route ships in SR-Main first) is read from the
/// public landing chapter instead, for the words without the map.
@MainActor
final class WildmindStore: ObservableObject {
    static let shared = WildmindStore()

    /// What the page can show.
    enum Phase: Equatable {
        /// Nothing asked yet, or the first ask is out.
        case loading
        /// An answer to draw (`answer` is set).
        case ready
        /// The site does not have the native route yet, and the public
        /// chapter did not answer either.
        case notOnSite
        /// The site refused this phone (a member's, or viewing as one).
        case refused(String)
        /// The first ask failed and there is nothing older to show.
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    /// The last good answer. Kept through failures.
    @Published private(set) var answer: WildmindAnswer?
    /// The decoded grid the answer's snapshot is drawn on, or `nil` when there
    /// is no map (offline, the public fallback, a grid that did not add up).
    @Published private(set) var grid: WildmindGrid?
    /// The words came from the public chapter: no map, and say so.
    @Published private(set) var fromPublicChapter = false
    /// The last poll failed, and what is shown is older than it looks.
    @Published private(set) var lastAskFailed = false

    private var lastGood: Date?
    /// The ask that is out, if one is. A second caller waits for it rather
    /// than returning at once: a poll restarted by the scene going inactive
    /// and back (Control Center, the app switcher) would otherwise skip its
    /// first ask and sleep a whole cadence with the spinner up, and a pull to
    /// refresh during a poll would do nothing at all.
    private var inflight: Task<Void, Never>?
    private let client = SiteClient.shared

    /// The state the page reads: the site's, or "stale" once the last good
    /// answer is over two minutes old and the site has stopped answering.
    var state: WildmindState {
        guard let answer else { return .offline }
        if lastAskFailed, let lastGood, Date().timeIntervalSince(lastGood) > 120,
           answer.snapshot != nil {
            return .stale
        }
        return answer.state
    }

    /// How long to wait before the next ask.
    var cadence: Duration {
        switch phase {
        case .ready: return .seconds(state.cadence)
        case .loading, .failed: return .seconds(30)
        case .notOnSite, .refused: return .seconds(60)
        }
    }

    /// Ask now and then on the cadence until the task is cancelled — when the
    /// page goes, or the app leaves the foreground.
    func poll() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: cadence)
        }
    }

    /// Ask once, or wait for the ask already out. The ask itself runs in its
    /// own task, so a poll cancelled mid-flight lets it land (one short GET)
    /// and the poll that replaces it picks up the answer.
    func load() async {
        if let inflight {
            await inflight.value
            return
        }
        let ask = Task { await self.fetch() }
        inflight = ask
        await ask.value
        inflight = nil
    }

    private func fetch() async {
        var path = "api/native/wildmind"
        if let held = grid?.version, Self.isSafeVersion(held) {
            path += "?have=\(held)"
        }
        do {
            let reply: WildmindAnswer = try await client.send(path)
            adopt(reply)
        } catch let error as URLError where error.code == .cancelled {
            // The page went away mid-ask. Not an answer; keep what is there.
        } catch is CancellationError {
        } catch let error as SiteError where error.status == 404 {
            await loadPublicChapter()
        } catch let error as SiteError where error.status == 403 {
            answer = nil
            grid = nil
            phase = .refused(error.localizedDescription)
        } catch {
            failed(error)
        }
    }

    /// The version as the site will accept it back (`/^[A-Za-z0-9._:-]{1,64}$/`),
    /// so it can go in the query as it is. Anything else is not sent, and the
    /// site sends the whole grid.
    nonisolated static func isSafeVersion(_ version: String) -> Bool {
        guard !version.isEmpty, version.count <= 64 else { return false }
        return version.unicodeScalars.allSatisfy { scalar in
            (scalar.value < 128 && CharacterSet.alphanumerics.contains(scalar)) || "._:-".unicodeScalars.contains(scalar)
        }
    }

    private func adopt(_ reply: WildmindAnswer) {
        let version = reply.snapshot?.terrainVersion
        if let terrain = reply.terrain, let version {
            // A grid that does not add up is no map, not a wrong one.
            grid = WildmindGrid(terrain: terrain, version: version)
        } else if reply.snapshot == nil {
            grid = nil
        } else if let held = grid, held.version != version {
            // The site left the grid out but the snapshot is on another
            // version. Keep drawing the old one for now — the people are
            // where they were a moment ago — and, with its version cleared,
            // ask for the whole grid next time rather than for a version the
            // site no longer has.
            grid = WildmindGrid(version: "", w: held.w, h: held.h, originX: held.originX, originZ: held.originZ,
                                step: held.step, ground: held.ground, heights: held.heights, regions: held.regions)
        }
        answer = reply
        fromPublicChapter = false
        lastAskFailed = false
        lastGood = Date()
        phase = .ready
    }

    /// The public landing chapter, for its words: no grid, no coordinates.
    private func loadPublicChapter() async {
        do {
            let chapter: WildmindPublicChapter = try await client.send("api/landing/wildmind")
            answer = WildmindAnswer(state: chapter.state, snapshot: chapter.snapshot, terrain: nil)
            grid = nil
            fromPublicChapter = true
            lastAskFailed = false
            lastGood = Date()
            phase = .ready
        } catch let error as URLError where error.code == .cancelled {
        } catch is CancellationError {
        } catch {
            if answer == nil { phase = .notOnSite } else { lastAskFailed = true }
        }
    }

    private func failed(_ error: Error) {
        if answer != nil {
            // Keep drawing the last good valley; `state` turns it stale.
            lastAskFailed = true
            objectWillChange.send()
        } else {
            phase = .failed(error.localizedDescription)
        }
    }
}

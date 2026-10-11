import Foundation
import SwiftUI

// MARK: - Loading the owner lane
//
// Talk, Chronicle and Inventions read SR-Main's owner-only Wildmind routes
// (`WildmindOwnerModels.swift`). Every screen says plainly which of these it
// is in, and none of them is a spinner that never ends: a request that does
// not answer times out (the site client's 30 s) into "didn't answer".

/// Where an owner screen is.
enum WildmindLoadPhase: Equatable {
    /// The first ask is out.
    case loading
    case ready
    /// The site answered, but the valley did not (`{state:"offline"}` or 503).
    case offline
    /// The site has no such route yet: SR-Main is older than the app (404).
    case notOnSite
    /// The valley has nobody by that id (chronicle 404 `no-such-person`).
    case missing
    /// The site refused this phone (a member's, or viewing as one).
    case refused(String)
    case failed(String)

    /// The phase an error means, or nil for a cancelled ask (not an answer).
    static func of(_ error: Error) -> WildmindLoadPhase? {
        if let error = error as? URLError, error.code == .cancelled { return nil }
        if error is CancellationError { return nil }
        if let error = error as? SiteError {
            switch error {
            case .expired: return .failed(error.localizedDescription)
            case .status(404, "no-such-person"): return .missing
            default: break
            }
            switch error.status {
            case 404?: return .notOnSite
            case 403?: return .refused(error.localizedDescription)
            case 502?, 503?, 504?: return .offline
            default: break
            }
        }
        return .failed(error.localizedDescription)
    }
}

/// An owner answer that may be SR-Main's `{state:"offline"}`.
protocol WildmindOwnerReply: Decodable {
    var offline: Bool { get }
}

extension WildmindChronicle: WildmindOwnerReply {}
extension WildmindInventions: WildmindOwnerReply {}

/// One owner route, read whole: Chronicle (per person) and Inventions.
@MainActor
final class WildmindFeed<Value: WildmindOwnerReply>: ObservableObject {
    @Published private(set) var phase: WildmindLoadPhase = .loading
    @Published private(set) var value: Value?
    /// The last ask failed or the valley went quiet; what is shown is older.
    @Published private(set) var stale = false

    let path: String
    private var inflight: Task<Void, Never>?

    init(path: String) {
        self.path = path
    }

    /// Ask now and then every `every` until the task is cancelled.
    func poll(every: Duration) async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: every)
        }
    }

    /// Ask once, or wait for the ask already out.
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
        do {
            let reply: Value = try await SiteClient.shared.send(path)
            if reply.offline {
                if value == nil { phase = .offline } else { stale = true }
                return
            }
            value = reply
            stale = false
            phase = .ready
        } catch {
            guard let next = WildmindLoadPhase.of(error) else { return }
            switch next {
            case .notOnSite, .refused, .missing:
                value = nil
                phase = next
            default:
                if value == nil { phase = next } else { stale = true }
            }
        }
    }
}

/// The owner routes' feeds, one each, so going back and forth draws the last
/// answer at once.
@MainActor
enum WildmindFeeds {
    static let inventions = WildmindFeed<WildmindInventions>(path: "api/native/wildmind/inventions")
    private static let chronicleMain = WildmindFeed<WildmindChronicle>(path: "api/native/wildmind/chronicle?id=main")
    private static let chronicleCompanion = WildmindFeed<WildmindChronicle>(path: "api/native/wildmind/chronicle?id=companion")

    static func chronicle(_ person: WildmindTalkFilter.Who) -> WildmindFeed<WildmindChronicle> {
        person == .companion ? chronicleCompanion : chronicleMain
    }
}

// MARK: - Talk

/// Talk: what JKai and Wren said, thought and wrote, John's whispers among
/// them, and the whisper composer's state.
///
/// Entries are held OLDEST FIRST, as the thread reads, merged by log id from
/// pages the site sends newest first: the newest page on open, older pages
/// with `before` as John scrolls up, newer entries with `since` while the
/// screen is up. A changed valley seed is a new valley, and the thread starts
/// again from its newest page.
///
/// `since` asks after the newest id a page has brought, never after the
/// whisper shown at the foot straight after sending (`WildmindTalkThread`).
///
/// Polled only while the screen is up: `/talk` every fifteen seconds, and
/// `/whispers` with it — every three seconds for a minute after a whisper
/// goes, when a change there (heard, dropped) also fetches the newer talk at
/// once, so JKai's answer turns up under the whisper.
@MainActor
final class WildmindTalkStore: ObservableObject {
    static let shared = WildmindTalkStore()

    static let pageSize = 60
    static let normalCadence: TimeInterval = 15

    @Published private(set) var phase: WildmindLoadPhase = .loading
    /// The entries held and the `since` cursor.
    @Published private(set) var thread = WildmindTalkThread()
    /// Oldest first.
    var entries: [WildmindTalkEntry] { thread.entries }
    @Published private(set) var valley: WildmindValley?
    /// Older entries remain on the site.
    @Published private(set) var hasOlder = false
    @Published private(set) var loadingOlder = false
    /// The last refresh failed; the thread shown is older than it looks.
    @Published private(set) var stale = false
    /// Which kinds and whose. Changing it starts the thread again.
    @Published private(set) var filter = WildmindTalkFilter()
    /// John's recent whispers and what became of them.
    @Published private(set) var whispers: WildmindWhispers?
    /// The composer's state.
    @Published private(set) var flow = WildmindWhisperFlow()
    /// The last 202: whether JKai was asleep, what it pushed out.
    @Published private(set) var lastAccepted: WildmindWhisperAccepted?
    /// A refusal that means nobody can hear a whisper just now (dead,
    /// paused, between lives), and when it came. It holds for half a minute.
    @Published private(set) var blocked: (failure: WildmindWhisperFailure, at: Date)?
    /// Moves on when entries arrive at the foot of the thread, for following.
    @Published private(set) var footTick = 0

    private let client = SiteClient.shared
    private var inflight: Task<Void, Never>?
    private var inflightFilter: WildmindTalkFilter?

    // MARK: Reading

    /// Poll until cancelled (the screen goes, or the app leaves the front).
    ///
    /// Wakes every second and asks only what is due, so a whisper sent in the
    /// middle of a long wait starts the three-second watch at once rather
    /// than after the wait.
    func poll() async {
        await refresh()
        _ = await refreshWhispers()
        var lastTalk = Date()
        var lastWhispers = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { break }
            let now = Date()
            var talkDue = now.timeIntervalSince(lastTalk) >= Self.normalCadence
            if now.timeIntervalSince(lastWhispers) >= flow.pollInterval(now: now, normal: Self.normalCadence) {
                lastWhispers = now
                // A whisper heard or dropped: its answer is in the newer talk.
                if await refreshWhispers() { talkDue = true }
            }
            if talkDue {
                await refresh()
                lastTalk = Date()
            }
        }
    }

    /// Pull to refresh: the newer talk and the whispers.
    func refreshAll() async {
        await refresh()
        _ = await refreshWhispers()
    }

    /// Newer entries, or the newest page when nothing is held. One at a time.
    func refresh() async {
        if let inflight {
            let askedFor = inflightFilter
            await inflight.value
            // That ask was for this filter, so its answer is this one's too;
            // if the filter changed meanwhile, ask again for the new one.
            if askedFor != filter { await fetchNewer() }
            return
        }
        let ask = Task { await self.fetchNewer() }
        inflight = ask
        inflightFilter = filter
        await ask.value
        inflight = nil
    }

    func setFilter(_ next: WildmindTalkFilter) {
        guard next != filter else { return }
        filter = next
        forget()
        hasOlder = false
        phase = .loading
        Task { await self.refresh() }
    }

    /// Open Talk to whisper: if the filter would hide John's whisper (only
    /// thoughts, only diaries, only Wren), show everything again.
    func showWhispers() {
        guard !filter.showsWhispers else { return }
        setFilter(WildmindTalkFilter())
    }

    /// The composer's last refusal has been seen (John is typing again, or
    /// has come back to the page): stop showing it, keep its key.
    func acknowledgeFailure() {
        guard flow.phase != .idle else { return }
        var next = flow
        next.acknowledge()
        if next != flow { flow = next }
    }

    /// Drop the thread, its cursor and any whisper waiting for a page.
    private func forget() {
        thread.forget()
    }

    private func fetchNewer() async {
        let since = thread.cursor
        let filter = self.filter
        do {
            let page: WildmindTalkPage = try await client.send(filter.path(since: since, limit: Self.pageSize))
            guard filter == self.filter else { return }
            if page.offline {
                if entries.isEmpty && phase != .ready { phase = .offline } else { stale = true }
                return
            }
            let newValley = page.valley?.seed != nil && valley?.seed != nil && page.valley?.seed != valley?.seed
            if since == nil || newValley || page.more {
                // A new valley, or more newer than one page: start from the
                // newest page rather than leave a gap.
                if since != nil {
                    let fresh: WildmindTalkPage = try await client.send(filter.path(limit: Self.pageSize))
                    guard filter == self.filter, !fresh.offline else { return }
                    adopt(fresh, replacing: true)
                } else {
                    adopt(page, replacing: true)
                }
            } else {
                adopt(page, replacing: false)
            }
        } catch {
            guard let next = WildmindLoadPhase.of(error) else { return }
            switch next {
            case .notOnSite, .refused:
                forget()
                phase = next
            default:
                if entries.isEmpty && phase != .ready { phase = next } else { stale = true }
            }
        }
    }

    private func adopt(_ page: WildmindTalkPage, replacing: Bool) {
        let before = entries.last?.id
        let newValley = page.valley?.seed != nil && valley?.seed != nil && page.valley?.seed != valley?.seed
        thread.adopt(page.entries, replacing: replacing, newValley: newValley)
        if replacing { hasOlder = page.more }
        valley = page.valley ?? valley
        stale = false
        phase = .ready
        if entries.last?.id != before { footTick &+= 1 }
    }

    /// The page before the oldest entry held.
    func loadOlder() async {
        guard hasOlder, !loadingOlder, let oldest = entries.first?.id else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        let filter = self.filter
        do {
            let page: WildmindTalkPage = try await client.send(filter.path(before: oldest, limit: Self.pageSize))
            guard filter == self.filter, !page.offline else { return }
            if let seed = page.valley?.seed, let held = valley?.seed, seed != held {
                // The valley changed under us: start again from its newest page.
                forget()
                await refresh()
                return
            }
            thread.adoptOlder(page.entries)
            hasOlder = page.more
        } catch {
            stale = WildmindLoadPhase.of(error) != nil
        }
    }

    /// `/whispers`. True when a whisper's status or answer changed.
    @discardableResult
    func refreshWhispers() async -> Bool {
        do {
            let reply: WildmindWhispers = try await client.send("api/native/wildmind/whispers?limit=50")
            guard !reply.offline else { return false }
            let changed = whispers?.whispers != reply.whispers
            whispers = reply
            return changed
        } catch {
            return false
        }
    }

    // MARK: Whispering

    /// The whisper this talk entry is, with its status, if it is a recent one.
    func whisper(for entry: WildmindTalkEntry) -> WildmindWhisper? {
        guard entry.kind == .whisper else { return nil }
        return whispers?.whisper(entry.id)
    }

    /// The whisper this thought answered, if it answered one.
    func answered(by entry: WildmindTalkEntry) -> WildmindWhisper? {
        guard entry.kind == .thought else { return nil }
        return whispers?.whispers.first { $0.answer?.logId == entry.id }
    }

    /// Why a whisper cannot go now, or nil when it can. `valleyState` and
    /// `mainAlive` come from the map page's last answer.
    func sendBlock(valleyState: WildmindState?, mainAlive: Bool?, now: Date = Date()) -> WildmindWhisperFailure? {
        switch phase {
        case .offline: return .offline
        case .notOnSite: return .notOnSite
        case .refused: return .refused
        default: break
        }
        if let blocked, now.timeIntervalSince(blocked.at) < 30 { return blocked.failure }
        if mainAlive == false { return .dead }
        switch valleyState {
        case .paused?: return .halted
        case .betweenLives?: return .betweenLives
        default: return nil
        }
    }

    /// Send a whisper to JKai. True when the site accepted it.
    func send(_ raw: String) async -> Bool {
        guard let start = flow.begin(raw, now: Date()) else { return false }
        let text = start.text
        let key = start.key
        do {
            let body = try JSONSerialization.data(withJSONObject: ["text": text])
            let (data, http) = try await client.exchange(
                "api/native/wildmind/whisper", method: "POST", body: body, headers: ["Idempotency-Key": key]
            )
            if (200..<300).contains(http.statusCode) {
                guard let reply = try? JSONDecoder().decode(WildmindWhisperAccepted.self, from: data) else {
                    // Something landed, but not an answer this build reads:
                    // keep the key, so sending again is answered once.
                    flow.failed(.network, now: Date())
                    return false
                }
                flow.accepted(reply, now: Date())
                lastAccepted = reply
                blocked = nil
                showSent(reply, text: text)
                Task { await self.refreshWhispers() }
                return true
            }
            struct Refusal: Decodable { let error: String? }
            let said = (try? JSONDecoder().decode(Refusal.self, from: data))?.error
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            let failure = WildmindWhisperFailure.from(status: http.statusCode, error: said, retryAfter: retryAfter)
            flow.failed(failure, now: Date())
            if failure.blocksSending { blocked = (failure, Date()) }
            if let wait = flow.coolingSeconds(now: Date()) {
                // Wake the composer when it may send again.
                Task {
                    try? await Task.sleep(for: .seconds(Double(wait) + 0.2))
                    self.objectWillChange.send()
                }
            }
        } catch SiteError.expired {
            flow.failed(.expired, now: Date())
        } catch {
            // No answer reached the phone: it may have landed. The key is
            // kept, so sending the same words again is answered once.
            flow.failed(.network, now: Date())
        }
        return false
    }

    /// The whisper at the foot of the thread at once, before the next page
    /// brings it — when the filter shows whispers at all.
    ///
    /// It goes into `entries` only: the `since` cursor stays at the newest id
    /// a page brought, so the next ask still fetches what was said between
    /// that page and this whisper.
    private func showSent(_ reply: WildmindWhisperAccepted, text: String) {
        guard filter.showsWhispers else { return }
        let entry = WildmindTalkEntry(
            id: reply.logId, minute: nil, when: reply.when ?? valley?.clock, who: "main", name: "JKai",
            kind: .whisper, text: text
        )
        thread.showSent(entry)
        if phase != .ready { phase = .ready }
        footTick &+= 1
    }
}

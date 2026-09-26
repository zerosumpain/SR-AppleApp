import Foundation

// Tap Duel's timing, as pure values — so every rule that decides who won is a
// unit test rather than something only two phones side by side can show.
//
// ## Two clocks
//
// The server fixes `goAt` in its own epoch milliseconds and sends it AHEAD, so
// each phone must turn green at that instant on ITS OWN clock. The phone's
// clock here is the MONOTONIC one (`CACurrentMediaTime()`, seconds since boot,
// passed in as milliseconds), not `Date()`: the wall clock can be stepped by
// NTP mid-round, and a green that jumps by the size of the correction is a
// round decided by the network time daemon. Touches (`UITouch.timestamp`) and
// display frames (`CADisplayLink.targetTimestamp`) are stamped on the same
// monotonic base, so the reaction time never crosses clocks at all.
//
// ## The offset
//
// `offset = serverNow − localNow`. A frame's `serverNow` was stamped BEFORE it
// arrived, so `serverNow − localReceipt` UNDER-states the true offset by the
// frame's one-way latency — every sample is a lower bound, and the largest is
// the one from the lowest-latency delivery. A request/response sample also has
// an upper bound (`serverNow − localSent`: the server cannot have stamped it
// before it was asked). The estimate is the intersection of those intervals
// over the recent samples — the midpoint when there is an upper bound, the
// tightest lower bound when there is not. That is "keep the lowest-latency
// sample", generalised so a pushed frame and a round trip can both count.
//
// A replayed stream frame (stamped minutes ago) is a very low lower bound and
// simply loses. Samples that contradict each other — a phone that slept, a
// server restart — reset the estimate to the newest sample rather than
// freezing on an impossible interval.

/// The server-to-phone clock offset, from the samples every payload carries.
struct GameClock: Equatable {
    struct Sample: Equatable {
        /// `serverNow − localReceived`: never above the true offset.
        let low: Double
        /// `serverNow − localSent`, when the phone asked; never below it.
        let high: Double?
    }

    /// How many recent samples count. Enough to find a quick delivery among
    /// slow ones; few enough that a drifting clock is followed.
    static let window = 16

    private(set) var samples: [Sample] = []

    /// Server ms minus local monotonic ms. Nil before the first sample.
    var offsetMs: Double? {
        guard let newest = samples.last else { return nil }
        let low = samples.map(\.low).max() ?? newest.low
        let highs = samples.compactMap(\.high)
        guard let high = highs.min() else { return low }
        if low <= high { return (low + high) / 2 }
        // Contradictory: something moved. Trust only the newest sample.
        if let newestHigh = newest.high { return (newest.low + newestHigh) / 2 }
        return newest.low
    }

    /// The uncertainty either side of `offsetMs`, when there is an upper bound.
    var uncertaintyMs: Double? {
        let low = samples.map(\.low).max()
        guard let low, let high = samples.compactMap(\.high).min(), low <= high else { return nil }
        return (high - low) / 2
    }

    /// A pushed frame: only when it arrived is known.
    mutating func record(serverNow: Double, receivedAt local: Double) {
        append(Sample(low: serverNow - local, high: nil))
    }

    /// A round trip: when the phone asked, and when the answer came back.
    mutating func record(serverNow: Double, sentAt: Double, receivedAt: Double) {
        let sent = min(sentAt, receivedAt)
        append(Sample(low: serverNow - receivedAt, high: serverNow - sent))
    }

    /// A server instant on the phone's monotonic clock (ms). Nil without a sample.
    func local(_ server: Double) -> Double? {
        offsetMs.map { server - $0 }
    }

    /// The phone's monotonic instant on the server's clock (ms).
    func server(_ local: Double) -> Double? {
        offsetMs.map { local + $0 }
    }

    private mutating func append(_ sample: Sample) {
        guard sample.low.isFinite else { return }
        // A newest sample that cannot be squared with the rest means the clocks
        // moved (a sleep, a restart); the old ones describe a world that is gone.
        if let high = samples.compactMap(\.high).min(), sample.low > high { samples.removeAll() }
        if let high = sample.high, let low = samples.map(\.low).max(), low > high { samples.removeAll() }
        samples.append(sample)
        if samples.count > Self.window { samples.removeFirst(samples.count - Self.window) }
    }
}

/// What the armed screen shows at an instant.
enum TapSignal: Equatable {
    /// Ink: "Wait…".
    case wait
    /// A decoy's amber flash: "Not yet".
    case decoy
    /// Green: "TAP!".
    case go
}

enum TapTiming {
    /// Under this, a "reaction" is anticipation — the server calls it a false
    /// start, and the phone's haptic agrees rather than cheering it.
    static let anticipationMs = 100

    /// The signal at a server instant. Pure: the round plus a time.
    static func signal(for round: GameRound, atServer now: Double) -> TapSignal {
        if now >= round.goAt { return .go }
        for decoy in round.decoys where now >= decoy.at && now < decoy.at + decoy.ms {
            return .decoy
        }
        return .wait
    }

    /// Whole milliseconds from green SHOWN to the tap LANDING, both monotonic
    /// seconds (`CADisplayLink.targetTimestamp`, `UITouch.timestamp`).
    static func reactionMs(shown: Double, tapped: Double) -> Int {
        Int(((tapped - shown) * 1000).rounded())
    }

    /// Judge one tap. Early when green had not been shown — including during
    /// a decoy, and a touch that landed before the green frame reached the
    /// glass even though the frame had been scheduled.
    static func judge(tappedAt tap: Double, shownAt: Double?) -> TapOutcome {
        guard let shownAt, tap >= shownAt else { return .early }
        return .reaction(reactionMs(shown: shownAt, tapped: tap))
    }
}

/// One tap, judged on the phone.
enum TapOutcome: Equatable {
    case early
    case reaction(Int)

    /// What to POST. `{action:"tap", round, early:true}` or
    /// `{action:"tap", round, reactionMs, early:false}`.
    func body(round: Int) -> GameActionBody {
        switch self {
        case .early: return GameActionBody(action: "tap", round: round, early: true)
        case .reaction(let ms): return GameActionBody(action: "tap", round: round, reactionMs: ms, early: false)
        }
    }

    /// A good tap: shown and not anticipated.
    var counts: Bool {
        if case .reaction(let ms) = self { return ms >= TapTiming.anticipationMs }
        return false
    }
}

/// One tap per round, and never one for a round the phone is not armed in.
struct TapLedger: Equatable {
    private(set) var tapped: Set<Int> = []

    /// Claims the round's tap. False if it was already spent.
    mutating func claim(round: Int) -> Bool {
        tapped.insert(round).inserted
    }

    func hasTapped(round: Int) -> Bool { tapped.contains(round) }
}

/// Whole seconds left on a server deadline, for the 3-2-1.
enum GameCountdown {
    static func secondsLeft(until end: Double, atServer now: Double) -> Int {
        max(0, Int(((end - now) / 1000).rounded(.up)))
    }
}

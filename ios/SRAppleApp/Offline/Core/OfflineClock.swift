import Foundation

// Two clocks, one game.
//
// The host's clock is the game's clock: its monotonic uptime, in seconds. A
// guest learns how far its own uptime is from the host's by pinging: it notes
// when it asked (`sentAt`), the host answers with its time (`hostNow`), and it
// notes when the answer came back (`receivedAt`). If the trip was symmetric
// the host stamped its answer halfway, so
//
//     offset = hostNow − (sentAt + receivedAt) / 2
//
// and the error is at most half the round trip. Bluetooth trips vary a lot,
// so the estimate keeps the recent sample with the SHORTEST round trip — the
// one with the least room for error — rather than averaging slow ones in.
//
// Monotonic, not `Date()`: the wall clock can be stepped mid-round, and the
// uptime is the same base as `UITouch.timestamp`, `CACurrentMediaTime()` and
// a display link's frame time, so a reaction measured on one phone never
// crosses clocks at all.

/// This phone's monotonic seconds. The same base as `CACurrentMediaTime()`.
enum OfflineUptime {
    static func now() -> Double { ProcessInfo.processInfo.systemUptime }
}

/// The guest's estimate of `host − local`, from ping round trips.
struct OfflineClockEstimator: Equatable {
    struct Sample: Equatable {
        let roundTrip: Double
        let offset: Double
    }

    /// Enough samples to find one quick trip among slow ones; few enough that
    /// a drifting clock is followed.
    static let window = 12

    private(set) var samples: [Sample] = []

    /// One answered ping. A negative trip (clocks are monotonic, so only a
    /// bug makes one) is ignored.
    mutating func record(sentAt: Double, receivedAt: Double, hostNow: Double) {
        let trip = receivedAt - sentAt
        guard trip >= 0, trip.isFinite, hostNow.isFinite else { return }
        samples.append(Sample(roundTrip: trip, offset: hostNow - (sentAt + receivedAt) / 2))
        if samples.count > Self.window { samples.removeFirst(samples.count - Self.window) }
    }

    private var best: Sample? { samples.min { $0.roundTrip < $1.roundTrip } }

    /// `host − local` in seconds, nil before the first answer.
    var offset: Double? { best?.offset }

    /// The best round trip, in seconds — half of it is the worst-case error.
    var roundTrip: Double? { best?.roundTrip }

    /// Whether to keep pinging quickly: until a handful of samples are in.
    var settling: Bool { samples.count < 5 }
}

/// The host's clock as a view sees it: a fixed offset from this phone's
/// uptime. On the host the offset is zero.
struct OfflineHostClock: Equatable {
    /// `host − local`, seconds.
    var offset: Double

    static let host = OfflineHostClock(offset: 0)

    /// Host time now.
    func now() -> Double { OfflineUptime.now() + offset }

    /// A local uptime instant (a touch's timestamp, a frame's) on the host's clock.
    func host(fromLocal local: Double) -> Double { local + offset }

    /// A host instant (a scheduled stimulus) on this phone's uptime clock.
    func local(fromHost host: Double) -> Double { host - offset }

    /// Whole seconds until a host instant, never negative: a countdown's 3-2-1.
    func secondsLeft(until hostTime: Double) -> Int {
        max(0, Int((hostTime - now()).rounded(.up)))
    }
}

/// Measuring a reaction on the phone that reacted.
///
/// The host schedules a stimulus at a host time; each phone shows it when its
/// own estimate of the host clock reaches that time, notes the LOCAL uptime of
/// the frame that first showed it, and measures the tap against that frame.
/// Network latency never enters the figure; only the phone's honesty does.
enum OfflineReaction {
    /// Under this a "reaction" is anticipation — nobody sees and moves in
    /// under a tenth of a second. Matches Tap Duel's rule.
    static let anticipationMs = 100

    /// Whole milliseconds from the stimulus shown to the touch, both local
    /// uptime seconds. Nil when the touch came before the stimulus showed.
    static func ms(shownAt: Double?, touchedAt: Double) -> Int? {
        guard let shownAt, touchedAt >= shownAt else { return nil }
        return Int(((touchedAt - shownAt) * 1000).rounded())
    }

    /// Whether a reported time is a believable reaction rather than a guess.
    static func counts(_ ms: Int) -> Bool { ms >= anticipationMs }
}

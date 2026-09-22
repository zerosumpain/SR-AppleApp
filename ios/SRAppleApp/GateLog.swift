import Foundation

/// The record of the gate opening and closing, and the arithmetic that makes it
/// worth keeping.
///
/// A gate that turns GPS on and off by itself is a thing you have to be able to
/// watch. Without a log there is no way to tell the difference between "it slept
/// for nine hours and saved a fortune" and "it stopped recording at nine in the
/// morning and nobody noticed" — and those two look identical from the outside,
/// which is precisely the failure this design is most exposed to.
///
/// So every transition is written down with what caused it, and the history
/// screen reads this back. The wake-quality figure it produces is also the
/// evidence for the one lever most worth tuning: if most wakes end in a blip,
/// the anchor is too tight.

enum GateState: String, Codable, Equatable {
    /// GPS running at the configured accuracy.
    case tracking
    /// GPS off. A geofence, significant-change and (optionally) visit
    /// monitoring are what bring the app back.
    case armed

    var label: String { self == .tracking ? "GPS on" : "Asleep" }
}

/// Where the geofence was dropped, kept across launches so a relaunch does not
/// silently start paying for continuous GPS again.
struct GateAnchor: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var radius: Double
    var at: Date
}

/// One transition.
struct GateEvent: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, Equatable {
        /// Sharing turned on; GPS running.
        case started
        /// Sharing turned off.
        case stopped
        /// GPS switched off and the geofence armed.
        case armed
        /// Something woke us. Says nothing yet about what happens next.
        case woke
        /// The motion history said somebody is going somewhere. GPS back on.
        case resumed
        /// The motion history said it was a blip. Back to sleep.
        case slept
        /// The gate WANTED to sleep and could not. Always the interesting row:
        /// it means the app is still paying, and says why.
        case blocked

        var label: String {
            switch self {
            case .started: return "Sharing on"
            case .stopped: return "Sharing off"
            case .armed: return "GPS off"
            case .woke: return "Woken"
            case .resumed: return "GPS on"
            case .slept: return "Back to sleep"
            case .blocked: return "Stayed on"
            }
        }

        /// Whether this row represents the app starting to spend.
        var spends: Bool { self == .started || self == .resumed || self == .blocked }
    }

    var id = UUID()
    var at: Date
    var kind: Kind
    var reason: String
    var detail: String?
    /// The battery level when it happened, so the log can be read beside the
    /// drain figure rather than in isolation.
    var battery: Double?
    var stateAfter: GateState

    /// Two weeks of ordinary use. Bounded because this rides in the same
    /// atomically-written file as the upload queue, so an unbounded log would
    /// make every location save more expensive than the location.
    static let maxStored = 500

    /// Same rule as `PersistedState` and `LocationSettings`: every field decoded
    /// with a default, so a log written by an older build cannot take the state
    /// file — queue included — down with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        at = try c.decodeIfPresent(Date.self, forKey: .at) ?? Date()
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .woke
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        battery = try c.decodeIfPresent(Double.self, forKey: .battery)
        stateAfter = try c.decodeIfPresent(GateState.self, forKey: .stateAfter) ?? .tracking
    }

    init(at: Date, kind: Kind, reason: String, detail: String? = nil,
         battery: Double? = nil, stateAfter: GateState) {
        self.at = at
        self.kind = kind
        self.reason = reason
        self.detail = detail
        self.battery = battery
        self.stateAfter = stateAfter
    }
}

/// What the log adds up to.
///
/// Pure arithmetic over stored events, which is what makes it testable — the
/// state machine itself needs a phone, this does not.
enum GateMaths {

    /// How long GPS was on and how long it was asleep, inside a window.
    ///
    /// The state entering the window comes from the last event BEFORE it, not
    /// from the first event inside it. Getting that backwards would report a
    /// night's sleep as unmeasured and flatter the duty cycle badly.
    ///
    /// Time before the log's very first event is not counted at all. We do not
    /// know what the app was doing then and inventing it would be the same
    /// mistake `BatteryMaths` refuses to make with a long gap.
    static func spans(_ events: [GateEvent], since: Date, now: Date) -> (tracking: TimeInterval, armed: TimeInterval) {
        let ordered = events.sorted { $0.at < $1.at }
        guard let first = ordered.first, now > since else { return (0, 0) }

        var cursor = max(since, first.at)
        guard cursor < now else { return (0, 0) }
        var state = (ordered.last { $0.at <= cursor } ?? first).stateAfter
        var tracking: TimeInterval = 0
        var armed: TimeInterval = 0

        for event in ordered where event.at > cursor {
            guard event.at <= now else { break }
            let seconds = event.at.timeIntervalSince(cursor)
            if state == .tracking { tracking += seconds } else { armed += seconds }
            cursor = event.at
            state = event.stateAfter
        }
        if now > cursor {
            let seconds = now.timeIntervalSince(cursor)
            if state == .tracking { tracking += seconds } else { armed += seconds }
        }
        return (tracking, armed)
    }

    /// The share of measured time GPS was actually on. nil rather than 0 when
    /// there is nothing to measure — absence is not a duty cycle of zero.
    static func dutyCycle(_ events: [GateEvent], since: Date, now: Date) -> Double? {
        let (tracking, armed) = spans(events, since: since, now: now)
        let total = tracking + armed
        guard total > 0 else { return nil }
        return tracking / total
    }

    static func count(_ events: [GateEvent], kind: GateEvent.Kind, since: Date) -> Int {
        events.filter { $0.kind == kind && $0.at >= since }.count
    }

    /// Of the wakes in this window, what fraction were worth waking for.
    ///
    /// The single most useful number on the history screen. A low figure means
    /// the anchor is exiting itself and the phone is being woken by noise, which
    /// is fixed by widening the anchor rather than by anything else on the
    /// settings page.
    static func wakeQuality(_ events: [GateEvent], since: Date) -> (wakes: Int, real: Int, share: Double?) {
        let wakes = count(events, kind: .woke, since: since)
        let real = count(events, kind: .resumed, since: since)
        guard wakes > 0 else { return (wakes, real, nil) }
        return (wakes, real, min(1, Double(real) / Double(wakes)))
    }

    /// Wakes in the last hour, which is what the collector widens the anchor on.
    static func wakes(_ events: [GateEvent], since: Date) -> Int {
        count(events, kind: .woke, since: since)
    }
}

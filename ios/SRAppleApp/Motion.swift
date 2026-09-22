import Foundation
import CoreMotion

/// Reading movement off the motion coprocessor, so GPS is not what decides
/// whether GPS is needed.
///
/// ## Why this exists
///
/// The old design was circular: `MovementPolicy` worked out that you were
/// moving from `location.speed` and distance travelled, both of which need the
/// expensive sensor to already be running. So the app paid for GPS all day in
/// order to discover that you had been sitting at a desk since nine.
///
/// ## The part that makes it work
///
/// Core Motion's live callbacks arrive ONLY while the app is running, so motion
/// cannot wake a suspended app — which looks fatal, because the whole point is
/// to let iOS suspend us.
///
/// It isn't, because the coprocessor **records continuously in hardware whether
/// or not this app exists**. `queryActivityStarting(from:to:)` and
/// `queryPedometerData(from:to:)` read up to seven days of that log back. We do
/// not need to be running to collect it; we only need to be running to ask. So a
/// cheap geofence wakes the app, and the app then asks what happened during the
/// stretch it slept through. The step test is evaluated retrospectively, which
/// is both free and more reliable than sampling it live.
///
/// ## What it costs
///
/// A query is a read of a log that was going to be written anyway. There is no
/// sensor to spin up and nothing to keep warm, which is the entire argument for
/// doing it this way rather than leaving the radio on.
enum MotionKind: String, Codable, CaseIterable, Equatable {
    case stationary, walking, running, cycling, automotive, unknown

    var label: String {
        switch self {
        case .stationary: return "Still"
        case .walking: return "Walking"
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .automotive: return "Driving"
        case .unknown: return "Unclassified"
        }
    }

    /// Movement that means somebody has actually gone somewhere, as opposed to
    /// crossing a room.
    var isTravel: Bool { self == .automotive || self == .cycling || self == .running }
}

/// Core Motion rates every classification it hands over. Low confidence is
/// common and frequently wrong — acting on it is most of what produces a wake
/// storm, so the floor is a setting rather than a constant.
enum MotionConfidence: String, Codable, CaseIterable, Identifiable, Comparable {
    case low, medium, high
    var id: String { rawValue }

    var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    var label: String {
        switch self {
        case .low: return "Any"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var cost: String {
        switch self {
        case .low: return "Acts on every classification, including the ones Core Motion is unsure about. Wakes most often and gets it wrong most often."
        case .medium: return "Ignores the guesses. The sensible default."
        case .high: return "Only acts on movement Core Motion is certain about. Fewest wakes, and it will miss a slow start."
        }
    }

    static func < (a: MotionConfidence, b: MotionConfidence) -> Bool { a.rank < b.rank }
}

/// One classified stretch of time. Our own type rather than `CMMotionActivity`,
/// for two reasons: `CMMotionActivity` cannot be constructed in a test, and it
/// carries a start with no end — the end is the next one's start, which is a
/// conversion worth doing once at the boundary rather than at every read.
struct MotionInterval: Equatable {
    var start: Date
    var end: Date
    var kind: MotionKind
    var confidence: MotionConfidence

    var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Everything the coprocessor can tell us about a stretch we were not awake for.
struct MotionEvidence: Equatable {
    var from: Date
    var to: Date
    var intervals: [MotionInterval] = []
    /// Steps across the whole window.
    var steps: Int = 0
    /// Steps in the most recent `stepBurstWindow` only — the "how many steps in
    /// the last two minutes" test, which is a different question from the total
    /// and the one that catches somebody who has just set off.
    var burstSteps: Int = 0
    var burstSeconds: TimeInterval = 0
    /// False when Core Motion could not answer: no coprocessor, permission
    /// refused, or a query error. The gate FAILS OPEN on this — see
    /// `MotionAssessment`.
    var available: Bool = true
    var note: String?

    var seconds: TimeInterval { max(0, to.timeIntervalSince(from)) }
}

/// What to do about it.
enum MotionVerdict: Equatable {
    /// Somebody is going somewhere. Start GPS.
    case travelling(MotionKind, String)
    /// A blip. Record one coarse point, re-anchor, go back to sleep.
    case blip(String)
    /// Core Motion could not say. Start GPS anyway — see below.
    case unreadable(String)

    /// Whether this turns the expensive sensor back on.
    ///
    /// `unreadable` counts. An app that goes quiet because a permission was
    /// refused is the worst outcome available here: it looks like it is working
    /// and records nothing. Paying for GPS is the cheaper mistake.
    var wakesGPS: Bool {
        if case .blip = self { return false }
        return true
    }

    var reason: String {
        switch self {
        case let .travelling(_, reason): return reason
        case let .blip(reason): return reason
        case let .unreadable(reason): return reason
        }
    }
}

/// The decision, as a pure function over evidence and settings.
///
/// Pure on purpose: Core Motion returns nothing useful in a simulator, so this
/// is the only part of the gate that can be tested in CI — which makes it the
/// part worth having all the judgement in.
enum MotionAssessment {

    static func verdict(_ evidence: MotionEvidence, settings: MotionSettings) -> MotionVerdict {
        guard evidence.available else {
            return .unreadable(evidence.note ?? "Motion unreadable — GPS on to be safe")
        }

        let confident = evidence.intervals
            .filter { $0.confidence >= settings.confidenceFloor }
            .sorted { $0.end < $1.end }

        // 1. The most recent thing you were doing, if it was travel. No minimum
        //    duration, because a geofence exit by car happens within seconds of
        //    setting off — requiring a minute of driving here would send the app
        //    back to sleep at exactly the moment it is most wanted.
        if let latest = confident.last, latest.kind.isTravel {
            if latest.kind == .automotive || latest.kind == .cycling {
                if settings.vehicleAlwaysWakes {
                    return .travelling(latest.kind, "\(latest.kind.label) now")
                }
            } else {
                return .travelling(latest.kind, "\(latest.kind.label) now")
            }
        }

        // 2. Travel anywhere in the window, totalled. Catches a journey that has
        //    already finished — you drove here, so the anchor is wrong.
        let travel = seconds(confident, where: { $0.kind.isTravel })
        if travel >= settings.travelMinimum {
            return .travelling(.automotive, "\(minutes(travel)) of travel in the window")
        }

        // 3. Sustained walking. This is the "five minutes of consistent steps"
        //    test, asked of the activity log rather than of a step counter,
        //    because the log already knows the difference between walking and
        //    standing up to make tea.
        let walking = seconds(confident, where: { $0.kind == .walking })
        if walking >= settings.sustainedWalk {
            return .travelling(.walking, "Walking for \(minutes(walking))")
        }

        // 4. The burst. A step count over a short recent window, which catches
        //    somebody who has only just set off and has not accumulated enough
        //    classified walking to pass rule 3 yet.
        if settings.stepBurst > 0, evidence.burstSteps >= settings.stepBurst {
            return .travelling(.walking, "\(evidence.burstSteps) steps in \(minutes(evidence.burstSeconds))")
        }

        // 5. Nothing that counts.
        if evidence.intervals.isEmpty && evidence.steps == 0 {
            return .blip("Nothing recorded — back to sleep")
        }
        return .blip("Only \(evidence.steps) steps and no sustained movement")
    }

    private static func seconds(_ intervals: [MotionInterval], where match: (MotionInterval) -> Bool) -> TimeInterval {
        intervals.filter(match).reduce(0) { $0 + $1.seconds }
    }

    private static func minutes(_ seconds: TimeInterval) -> String {
        seconds < 90 ? "\(Int(seconds.rounded()))s" : "\(Int((seconds / 60).rounded())) min"
    }
}

/// The Core Motion side. Device-only: `isActivityAvailable()` is false in the
/// simulator, so everything here returns "unreadable" in CI and the gate fails
/// open, which is the behaviour we want anyway.
///
/// Main-actor, and the queries are handed `OperationQueue.main`, so nothing
/// crosses a thread boundary. The handlers reduce `CMMotionActivity` and
/// `CMPedometerData` — neither of which is `Sendable` — to our own value types
/// BEFORE resuming the continuation, so no Core Motion object escapes.
@MainActor final class MotionGate {
    private let activity = CMMotionActivityManager()
    private let pedometer = CMPedometer()

    var available: Bool { CMMotionActivityManager.isActivityAvailable() }
    var stepsAvailable: Bool { CMPedometer.isStepCountingAvailable() }
    var authorisation: CMAuthorizationStatus { CMMotionActivityManager.authorizationStatus() }

    /// Whether the gate can be armed at all. Deliberately permissive about
    /// `.notDetermined`: the permission sheet appears on the first query, and
    /// refusing to arm before it has been asked would mean it was never asked.
    var usable: Bool {
        guard available else { return false }
        switch authorisation {
        case .denied, .restricted: return false
        default: return true
        }
    }

    var refusalReason: String? {
        if !available { return "This iPhone has no motion coprocessor" }
        switch authorisation {
        case .denied: return "Motion & Fitness is off for this app in iOS Settings"
        case .restricted: return "Motion & Fitness is restricted on this iPhone"
        default: return nil
        }
    }

    /// Ask for Motion & Fitness while the app is in the FOREGROUND.
    ///
    /// Core Motion has no request API — the permission sheet appears on the
    /// first query. That is a trap for this design, because the first query
    /// would otherwise be the one made on a background wake, and iOS will not
    /// put a permission sheet in front of a suspended app. The query would fail
    /// quietly, the verdict would be a blip, the app would go back to sleep, and
    /// the permission would never be asked for at all.
    ///
    /// So this is that first query, made deliberately, at the moment somebody
    /// turns the gate on and is looking at the screen.
    @discardableResult
    func primePermission() async -> Bool {
        guard available else { return false }
        let now = Date()
        _ = await intervals(from: now.addingTimeInterval(-60), to: now)
        return usable
    }

    /// Read back the stretch we slept through.
    func evidence(from: Date, to: Date, burstWindow: TimeInterval) async -> MotionEvidence {
        var evidence = MotionEvidence(from: from, to: to)
        guard from < to else {
            evidence.available = false
            evidence.note = "No window to look at"
            return evidence
        }
        guard available else {
            evidence.available = false
            evidence.note = refusalReason ?? "Motion unavailable"
            return evidence
        }
        if let refusal = refusalReason {
            evidence.available = false
            evidence.note = refusal
            return evidence
        }

        evidence.intervals = await intervals(from: from, to: to)
        if stepsAvailable {
            evidence.steps = await steps(from: from, to: to) ?? 0
            let burstFrom = max(from, to.addingTimeInterval(-burstWindow))
            evidence.burstSeconds = to.timeIntervalSince(burstFrom)
            evidence.burstSteps = await steps(from: burstFrom, to: to) ?? 0
        }
        // A window with no classification and no step data at all is not
        // "you were still", it is "nothing answered". Say so rather than
        // letting an empty answer read as a confident one.
        if evidence.intervals.isEmpty && !stepsAvailable {
            evidence.available = false
            evidence.note = "No motion history for that window"
        }
        return evidence
    }

    private func intervals(from: Date, to: Date) async -> [MotionInterval] {
        await withCheckedContinuation { continuation in
            activity.queryActivityStarting(from: from, to: to, to: .main) { activities, _ in
                guard let activities, !activities.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }
                // Core Motion gives a start and no end: a classification runs
                // until the next one begins, and the last runs to `to`.
                var built: [MotionInterval] = []
                for (index, entry) in activities.enumerated() {
                    let stop = index + 1 < activities.count ? activities[index + 1].startDate : to
                    built.append(MotionInterval(start: entry.startDate,
                                                end: stop,
                                                kind: Self.kind(of: entry),
                                                confidence: Self.confidence(of: entry)))
                }
                continuation.resume(returning: built)
            }
        }
    }

    private func steps(from: Date, to: Date) async -> Int? {
        await withCheckedContinuation { continuation in
            // Unlike the activity query there is no queue argument, so this
            // handler lands wherever Core Motion feels like. Reduce to an Int
            // before resuming — `CMPedometerData` must not escape the handler.
            pedometer.queryPedometerData(from: from, to: to) { data, _ in
                continuation.resume(returning: data?.numberOfSteps.intValue)
            }
        }
    }

    /// Several flags can be true at once. Ordered by how much a false negative
    /// would cost: missing that somebody is in a car matters far more than
    /// mislabelling a walk.
    nonisolated static func kind(of entry: CMMotionActivity) -> MotionKind {
        if entry.automotive { return .automotive }
        if entry.cycling { return .cycling }
        if entry.running { return .running }
        if entry.walking { return .walking }
        if entry.stationary { return .stationary }
        return .unknown
    }

    nonisolated static func confidence(of entry: CMMotionActivity) -> MotionConfidence {
        switch entry.confidence {
        case .high: return .high
        case .medium: return .medium
        default: return .low
        }
    }
}

import Foundation
import Combine
import CoreLocation

struct WorkoutEventRecord: Codable, Equatable { var type: String; var start: String; var end: String }
struct HealthRecord: Codable, Identifiable {
    var id: String
    var kind: String
    var start: String
    var end: String
    var value: Double?
    var unit: String?
    var source: String
    var stage: String?
    var activity: String?
    var distance: Double?
    var energy: Double?
    /// The phone's IANA zone when this was collected, so /health can write
    /// the local date the webhook used to (spec E12).
    var tz: String?
    // Workout depth (kind "workout").
    var indoor: Bool?
    var elevation: Double?
    var mets: Double?
    var temperature: Double?
    var humidity: Double?
    var effort: Double?
    var events: [WorkoutEventRecord]?
    // A chunk of a workout's route or series (kinds "workout_route" / "workout_series").
    var workout: String?
    var metric: String?
    var chunk: Int?
    var points: [[Double?]]?
}
struct LocationRecord: Codable, Identifiable {
    var id: String = UUID().uuidString
    var recorded: String
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var speed: Double
    var moving: Bool
}
struct UploadBatch: Codable, Identifiable {
    var id = UUID()
    var health: [HealthRecord] = []
    var locations: [LocationRecord] = []
    var deleted: [String] = []
    enum CodingKeys: String, CodingKey { case health, locations, deleted }
}
struct Profile: Codable { var id: String; var name: String; var sharing: Bool }
struct FamilyMember: Codable, Identifiable {
    var id: String
    var name: String
    var sharing: Bool
    var location: LocationRecord?
}
struct FamilyResponse: Codable { var members: [FamilyMember] }
struct HealthResponse: Codable { var records: [HealthRecord] }
func parseTimestamp(_ text: String) -> Date? {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return format.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}
func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

/// The complete outbox and HealthKit anchors are replaced atomically together.
struct PersistedState: Codable {
    var batches: [UploadBatch] = []
    var anchors: [String: Data] = [:]
    var healthEnabled: [String] = []
    var sharing = false
    var pendingSharing: Bool?
    var lastUpload: Date?
    var historyStart = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    /// Everything the settings screen controls. Decoded with a default so an
    /// existing install upgrades without losing its queue — a new non-optional
    /// field with no default makes the whole state file undecodable, which here
    /// would throw away unsent health records.
    var location = LocationSettings()
    /// Bounded ring of battery readings. See Battery.swift for what they can
    /// honestly be used to say.
    var battery: [BatterySample] = []
    /// What the recorded points actually achieved, so the drain has something
    /// to be weighed against.
    var pointsRecorded = 0
    var accuracySum: Double = 0
    var countingSince: Date?
    /// Whether GPS is running or the motion gate has it asleep, and where the
    /// geofence that will wake it was dropped. Persisted because a relaunch —
    /// including the background relaunch a geofence exit itself causes — would
    /// otherwise start continuous GPS again, which is the cost the gate exists
    /// to avoid.
    var gateState: GateState = .tracking
    var anchor: GateAnchor?
    /// Every time the gate opened or closed, and why. A gate that manages GPS
    /// by itself has to be watchable: "slept all night and saved a fortune" and
    /// "stopped recording at nine and nobody noticed" look identical without it.
    var gateEvents: [GateEvent] = []
    /// 0 = toggles are per-kind (pre-catalogue); 1 = toggles are groups, but
    /// workouts collected before the catalogue still lack their series, route
    /// and events; 2 = workouts re-read with depth, after the reader granted the
    /// new permissions. Fresh state (a new install, or `clear()` on re-pair)
    /// starts at the current version: it has nothing old to migrate. A file on
    /// disk without the key decodes as 0 (below).
    static let currentCatalogueVersion = 2
    var catalogueVersion = PersistedState.currentCatalogueVersion
    /// Where each hourly-statistics kind resumes. Re-reads the last 48 hours
    /// every pass, because a Watch can sync a day late.
    var hourlyFrom: [String: Date] = [:]
    /// Workouts whose route watchOS has not saved yet (it lands after the
    /// workout), by workout UUID → workout end. Retried for 7 days.
    var pendingRoutes: [String: Date] = [:]

    /// Decode every field as OPTIONAL-with-a-default.
    ///
    /// Swift's synthesised `Codable` does NOT fall back to a property's default
    /// value when a key is missing — it throws `keyNotFound` unless the property
    /// is `Optional`. So adding `location`, `battery` and the counters made every
    /// EXISTING state file undecodable, and this file is the upload queue: an
    /// upgrade would have silently discarded unsent health records, HealthKit
    /// anchors and the sharing flag, then started again from empty.
    ///
    /// Caught by `testExistingStateDecodesWithoutTheNewFields`, which is why it
    /// was written. Anything added below must be decoded the same way.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        batches = try c.decodeIfPresent([UploadBatch].self, forKey: .batches) ?? []
        anchors = try c.decodeIfPresent([String: Data].self, forKey: .anchors) ?? [:]
        healthEnabled = try c.decodeIfPresent([String].self, forKey: .healthEnabled) ?? []
        sharing = try c.decodeIfPresent(Bool.self, forKey: .sharing) ?? false
        pendingSharing = try c.decodeIfPresent(Bool.self, forKey: .pendingSharing)
        lastUpload = try c.decodeIfPresent(Date.self, forKey: .lastUpload)
        historyStart = try c.decodeIfPresent(Date.self, forKey: .historyStart)
            ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        location = try c.decodeIfPresent(LocationSettings.self, forKey: .location) ?? LocationSettings()
        battery = try c.decodeIfPresent([BatterySample].self, forKey: .battery) ?? []
        pointsRecorded = try c.decodeIfPresent(Int.self, forKey: .pointsRecorded) ?? 0
        accuracySum = try c.decodeIfPresent(Double.self, forKey: .accuracySum) ?? 0
        countingSince = try c.decodeIfPresent(Date.self, forKey: .countingSince)
        gateState = try c.decodeIfPresent(GateState.self, forKey: .gateState) ?? .tracking
        anchor = try c.decodeIfPresent(GateAnchor.self, forKey: .anchor)
        gateEvents = try c.decodeIfPresent([GateEvent].self, forKey: .gateEvents) ?? []
        catalogueVersion = try c.decodeIfPresent(Int.self, forKey: .catalogueVersion) ?? 0
        hourlyFrom = try c.decodeIfPresent([String: Date].self, forKey: .hourlyFrom) ?? [:]
        pendingRoutes = try c.decodeIfPresent([String: Date].self, forKey: .pendingRoutes) ?? [:]
    }

    /// The memberwise init the rest of the app uses, which writing `init(from:)`
    /// suppresses.
    init() {}
}
@MainActor final class Outbox: ObservableObject {
    @Published private(set) var state: PersistedState
    private let url: URL
    init(url: URL? = nil) throws {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.url = url ?? directory.appendingPathComponent("sync-state.json")
        try FileManager.default.createDirectory(at: self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: self.url.path) {
            state = try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: self.url))
        } else { state = PersistedState() }
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        var dir = self.url.deletingLastPathComponent(); try dir.setResourceValues(resource)
    }
    func change(_ transform: (inout PersistedState) throws -> Void) throws {
        var next = state; try transform(&next)
        let count = next.batches.reduce(0) { $0 + $1.health.count + $1.locations.count + $1.deleted.count }
        guard count <= 50000 else { throw CompanionError.message("Offline queue is full. Connect and sync before collecting more data.") }
        let data = try JSONEncoder().encode(next)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        state = next
    }
    func clear() throws { try change { $0 = PersistedState() } }
}

/// Upload cadence is separate from Core Location's sensor/update frequency.
///
/// Every threshold in here used to be a literal. They come from settings now,
/// and the defaults reproduce those literals exactly, so an install that never
/// opens the settings screen behaves as it always did.
struct MovementPolicy {
    private(set) var moving = false
    private var lastMovement: Date?
    private var lastRecorded: Date?
    var settings: LocationSettings

    init(settings: LocationSettings = LocationSettings()) {
        self.settings = settings
    }

    mutating func shouldRecord(at time: Date, speed: Double, distance: Double, accuracy: Double) -> Bool {
        guard accuracy >= 0, accuracy <= settings.accuracyCeiling else { return false }
        let wasMoving = moving
        if speed >= settings.movingSpeed || distance > max(30, accuracy * 2) { moving = true; lastMovement = time }
        else if let lastMovement, time.timeIntervalSince(lastMovement) >= settings.stopThreshold { moving = false }
        let interval: TimeInterval = moving ? settings.movingInterval : settings.stationaryInterval
        guard lastRecorded == nil || wasMoving != moving || time.timeIntervalSince(lastRecorded!) >= interval else { return false }
        lastRecorded = time
        return true
    }
}

// MARK: - Location settings
//
// Every constant that used to be hard-coded in `LocationCollector` and
// `MovementPolicy`. They are here, and persisted, because the honest way to find
// the right trade-off is to change one and watch what it costs — which needs the
// setting and the measurement in the same place.

/// How hard the phone works to know where it is.
///
/// `Best` runs the full GPS chip continuously and is the single most expensive
/// thing this app can do. Family location does not need it: ten metres is the
/// difference between "at the shops" and "at the shops".
enum LocationAccuracy: String, Codable, CaseIterable, Identifiable {
    case best, tenMetres, hundredMetres, kilometre
    var id: String { rawValue }

    var label: String {
        switch self {
        case .best: return "Best"
        case .tenMetres: return "10 m"
        case .hundredMetres: return "100 m"
        case .kilometre: return "1 km"
        }
    }

    /// What it costs, in words, because a menu of four values is not a frame.
    var cost: String {
        switch self {
        case .best: return "Full GPS. Most accurate, most battery."
        case .tenMetres: return "GPS with a looser fix. Enough to place somebody on a street."
        case .hundredMetres: return "Mostly wifi and cell. Enough to place somebody in an area."
        case .kilometre: return "Cell towers only. Barely costs anything."
        }
    }

    var coreLocationValue: CLLocationAccuracy {
        switch self {
        case .best: return kCLLocationAccuracyBest
        case .tenMetres: return kCLLocationAccuracyNearestTenMeters
        case .hundredMetres: return kCLLocationAccuracyHundredMeters
        case .kilometre: return kCLLocationAccuracyKilometer
        }
    }
}

/// What iOS is told the phone is doing, which decides how aggressively it may
/// optimise. `.other` is the least optimisable value there is — it tells the
/// system nothing, so it assumes the worst and keeps the radio warm.
enum LocationActivity: String, Codable, CaseIterable, Identifiable {
    case other, fitness, automotive, otherNavigation
    var id: String { rawValue }

    var label: String {
        switch self {
        case .other: return "Unspecified"
        case .fitness: return "On foot"
        case .automotive: return "Driving"
        case .otherNavigation: return "Other vehicle"
        }
    }

    var cost: String {
        switch self {
        case .other: return "Tells iOS nothing, so it cannot optimise. The current default."
        case .fitness: return "Lets iOS pause updates when you stop walking."
        case .automotive: return "Tuned for road speeds; pauses when parked."
        case .otherNavigation: return "For trains and boats."
        }
    }

    var coreLocationValue: CLActivityType {
        switch self {
        case .other: return .other
        case .fitness: return .fitness
        case .automotive: return .automotiveNavigation
        case .otherNavigation: return .otherNavigation
        }
    }
}

/// The levers on the motion gate.
///
/// Everything here is off by default, and that is deliberate: the shipped
/// `LocationSettings()` has to keep reproducing exactly what the app did before
/// this existed, or an upgrade silently changes how a family location app
/// behaves. The two cheaper presets turn it on; "Accurate" does not.
struct MotionSettings: Codable, Equatable {
    /// The master switch. Off means the app behaves exactly as it did before —
    /// continuous GPS, no sleeping, no geofence.
    var enabled = false

    // MARK: Going to sleep

    /// How long the phone has to be still before GPS is switched off. Longer
    /// than `stopThreshold` on purpose: dropping to cheap settings and dropping
    /// the sensor entirely are different sizes of decision.
    var sleepAfter: TimeInterval = 300
    /// The geofence's minimum radius. The actual radius is derived from the
    /// accuracy of the fix that placed it — an anchor smaller than the error in
    /// its own fix exits itself, and that is where a wake storm comes from.
    var anchorRadius: Double = 150
    /// The ceiling on that derivation, including the widening below.
    var maxAnchorRadius: Double = 1000
    /// More wakes than this in an hour and the anchor is widened automatically.
    /// The history screen shows the wake count that triggers it, so the lever
    /// and the evidence for moving it are two taps apart.
    var maxWakesPerHour = 6

    // MARK: Waking up

    /// How far back to read the motion log on waking. Short on purpose: the
    /// question is "is somebody moving NOW", and a window of hours would
    /// accumulate enough walking to answer yes every single time.
    var historyWindow: TimeInterval = 900
    /// Ignore classifications below this confidence. Low confidence is common
    /// and frequently wrong, and acting on it is most of a wake storm.
    var confidenceFloor: MotionConfidence = .medium
    /// Any driving or cycling in the most recent classification turns GPS on
    /// immediately, with no minimum duration — a geofence exit by car happens
    /// seconds after setting off, and that is exactly when location matters.
    var vehicleAlwaysWakes = true
    /// Travel totalled across the whole window that counts even once it has
    /// stopped. Catches "you drove here", where the anchor is now wrong.
    var travelMinimum: TimeInterval = 60
    /// Sustained walking that counts as going somewhere rather than crossing a
    /// room. This is the five-minutes-of-consistent-steps test, asked of the
    /// activity log rather than a step counter.
    var sustainedWalk: TimeInterval = 300
    /// Steps inside the recent burst window that count on their own. Catches
    /// somebody who has just set off and has not accumulated enough classified
    /// walking yet. Zero turns the test off.
    var stepBurst = 150
    var stepBurstWindow: TimeInterval = 120

    // MARK: What to keep

    /// Cheap and it wakes a suspended app on arriving and leaving. Costs
    /// essentially nothing; the reason it is a toggle at all is that it also
    /// produces wakes, and a wake budget is the thing being tuned.
    var visitMonitoring = true
    /// Record the one coarse fix taken to re-anchor after a blip, so a long
    /// sleep is not a hole in the record. It is already being paid for.
    var coarseOnBlip = true

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MotionSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        sleepAfter = try c.decodeIfPresent(TimeInterval.self, forKey: .sleepAfter) ?? d.sleepAfter
        anchorRadius = try c.decodeIfPresent(Double.self, forKey: .anchorRadius) ?? d.anchorRadius
        maxAnchorRadius = try c.decodeIfPresent(Double.self, forKey: .maxAnchorRadius) ?? d.maxAnchorRadius
        maxWakesPerHour = try c.decodeIfPresent(Int.self, forKey: .maxWakesPerHour) ?? d.maxWakesPerHour
        historyWindow = try c.decodeIfPresent(TimeInterval.self, forKey: .historyWindow) ?? d.historyWindow
        confidenceFloor = try c.decodeIfPresent(MotionConfidence.self, forKey: .confidenceFloor) ?? d.confidenceFloor
        vehicleAlwaysWakes = try c.decodeIfPresent(Bool.self, forKey: .vehicleAlwaysWakes) ?? d.vehicleAlwaysWakes
        travelMinimum = try c.decodeIfPresent(TimeInterval.self, forKey: .travelMinimum) ?? d.travelMinimum
        sustainedWalk = try c.decodeIfPresent(TimeInterval.self, forKey: .sustainedWalk) ?? d.sustainedWalk
        stepBurst = try c.decodeIfPresent(Int.self, forKey: .stepBurst) ?? d.stepBurst
        stepBurstWindow = try c.decodeIfPresent(TimeInterval.self, forKey: .stepBurstWindow) ?? d.stepBurstWindow
        visitMonitoring = try c.decodeIfPresent(Bool.self, forKey: .visitMonitoring) ?? d.visitMonitoring
        coarseOnBlip = try c.decodeIfPresent(Bool.self, forKey: .coarseOnBlip) ?? d.coarseOnBlip
    }

    init(enabled: Bool = false,
         sleepAfter: TimeInterval = 300,
         anchorRadius: Double = 150,
         maxAnchorRadius: Double = 1000,
         maxWakesPerHour: Int = 6,
         historyWindow: TimeInterval = 900,
         confidenceFloor: MotionConfidence = .medium,
         vehicleAlwaysWakes: Bool = true,
         travelMinimum: TimeInterval = 60,
         sustainedWalk: TimeInterval = 300,
         stepBurst: Int = 150,
         stepBurstWindow: TimeInterval = 120,
         visitMonitoring: Bool = true,
         coarseOnBlip: Bool = true) {
        self.enabled = enabled
        self.sleepAfter = sleepAfter
        self.anchorRadius = anchorRadius
        self.maxAnchorRadius = maxAnchorRadius
        self.maxWakesPerHour = maxWakesPerHour
        self.historyWindow = historyWindow
        self.confidenceFloor = confidenceFloor
        self.vehicleAlwaysWakes = vehicleAlwaysWakes
        self.travelMinimum = travelMinimum
        self.sustainedWalk = sustainedWalk
        self.stepBurst = stepBurst
        self.stepBurstWindow = stepBurstWindow
        self.visitMonitoring = visitMonitoring
        self.coarseOnBlip = coarseOnBlip
    }
}

struct LocationSettings: Codable, Equatable {
    /// Accuracy asked for while moving, and while stopped. Two values because
    /// the whole point is that standing still does not need a GPS fix.
    var movingAccuracy: LocationAccuracy = .best
    var stationaryAccuracy: LocationAccuracy = .hundredMetres
    /// Metres of movement before Core Location reports at all.
    var movingDistanceFilter: Double = 10
    var stationaryDistanceFilter: Double = 30
    /// How often a point is RECORDED. Separate from how often the sensor reports.
    var movingInterval: TimeInterval = 30
    var stationaryInterval: TimeInterval = 600
    /// Still for this long and the phone is considered stopped.
    var stopThreshold: TimeInterval = 180
    /// Above this speed (m/s) the phone is considered moving.
    var movingSpeed: Double = 0.8
    /// Fixes looser than this many metres are discarded rather than recorded.
    var accuracyCeiling: Double = 100
    /// The timer that asks for a fix while the app is running. This is the
    /// biggest single lever in here and the least obvious: at 60 seconds it
    /// forces a fresh fix every minute even when stationary and only recording
    /// every ten. Zero turns it off entirely and leaves Core Location to report
    /// when it has something.
    var heartbeatInterval: TimeInterval = 60
    var activity: LocationActivity = .other
    /// Let iOS stop the radio when it decides nothing is happening.
    var pausesAutomatically = true
    /// The cheap fallback that wakes a suspended app when you change city.
    var significantChangeMonitoring = true
    /// Let movement decide when GPS is needed, instead of running GPS to find
    /// out. Off in the shipped default; on in the two cheaper presets.
    var motion = MotionSettings()

    /// Named starting points. A row of sliders with no frame is the failure
    /// /health names for a header figure — these say what a combination IS.
    enum Preset: String, CaseIterable, Identifiable {
        case saver, balanced, accurate
        var id: String { rawValue }

        var label: String {
            switch self {
            case .saver: return "Battery saver"
            case .balanced: return "Balanced"
            case .accurate: return "Accurate"
            }
        }

        var detail: String {
            switch self {
            case .saver:
                return "Cell and wifi only, no heartbeat, iOS free to pause. GPS sleeps after three minutes still and needs real, sustained movement to come back. Expect a position within a few hundred metres, minutes old."
            case .balanced:
                return "GPS to ten metres while moving, cheap fixes when stopped, heartbeat every five minutes. GPS sleeps after five minutes still and wakes on movement the motion chip already recorded."
            case .accurate:
                return "Full GPS while moving and a fix every minute, running all day whether you move or not. What the app shipped with, and the most expensive thing it can do."
            }
        }

        var settings: LocationSettings {
            switch self {
            case .saver:
                return LocationSettings(
                    movingAccuracy: .hundredMetres, stationaryAccuracy: .kilometre,
                    movingDistanceFilter: 100, stationaryDistanceFilter: 500,
                    movingInterval: 300, stationaryInterval: 1800,
                    stopThreshold: 300, movingSpeed: 1.2, accuracyCeiling: 500,
                    heartbeatInterval: 0, activity: .fitness,
                    pausesAutomatically: true, significantChangeMonitoring: true,
                    // Sleeps quickly and is hard to wake: a wider anchor, a
                    // higher step bar and only movement Core Motion is sure
                    // about. The trade is latency — you will be a minute or two
                    // late noticing somebody has set off.
                    motion: MotionSettings(
                        enabled: true, sleepAfter: 180, anchorRadius: 250,
                        maxWakesPerHour: 4, confidenceFloor: .high,
                        sustainedWalk: 300, stepBurst: 250))
            case .balanced:
                return LocationSettings(
                    movingAccuracy: .tenMetres, stationaryAccuracy: .hundredMetres,
                    movingDistanceFilter: 25, stationaryDistanceFilter: 100,
                    movingInterval: 60, stationaryInterval: 900,
                    stopThreshold: 240, movingSpeed: 0.8, accuracyCeiling: 150,
                    heartbeatInterval: 300, activity: .fitness,
                    pausesAutomatically: true, significantChangeMonitoring: true,
                    motion: MotionSettings(enabled: true))
            case .accurate:
                // Exactly what the app did before this screen existed. The
                // default stays here so upgrading changes nothing on its own —
                // a battery setting that silently moves is worse than none.
                return LocationSettings()
            }
        }
    }

    /// Which preset this matches, or nil once a value has been changed by hand.
    var matchingPreset: Preset? {
        Preset.allCases.first { $0.settings == self }
    }

    /// Same reasoning as `PersistedState.init(from:)`: a field added here later
    /// must not make a stored settings blob undecodable, which would take the
    /// whole state file — queue included — down with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LocationSettings()
        movingAccuracy = try c.decodeIfPresent(LocationAccuracy.self, forKey: .movingAccuracy) ?? d.movingAccuracy
        stationaryAccuracy = try c.decodeIfPresent(LocationAccuracy.self, forKey: .stationaryAccuracy) ?? d.stationaryAccuracy
        movingDistanceFilter = try c.decodeIfPresent(Double.self, forKey: .movingDistanceFilter) ?? d.movingDistanceFilter
        stationaryDistanceFilter = try c.decodeIfPresent(Double.self, forKey: .stationaryDistanceFilter) ?? d.stationaryDistanceFilter
        movingInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .movingInterval) ?? d.movingInterval
        stationaryInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .stationaryInterval) ?? d.stationaryInterval
        stopThreshold = try c.decodeIfPresent(TimeInterval.self, forKey: .stopThreshold) ?? d.stopThreshold
        movingSpeed = try c.decodeIfPresent(Double.self, forKey: .movingSpeed) ?? d.movingSpeed
        accuracyCeiling = try c.decodeIfPresent(Double.self, forKey: .accuracyCeiling) ?? d.accuracyCeiling
        heartbeatInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .heartbeatInterval) ?? d.heartbeatInterval
        activity = try c.decodeIfPresent(LocationActivity.self, forKey: .activity) ?? d.activity
        pausesAutomatically = try c.decodeIfPresent(Bool.self, forKey: .pausesAutomatically) ?? d.pausesAutomatically
        significantChangeMonitoring = try c.decodeIfPresent(Bool.self, forKey: .significantChangeMonitoring) ?? d.significantChangeMonitoring
        motion = try c.decodeIfPresent(MotionSettings.self, forKey: .motion) ?? d.motion
    }

    init(movingAccuracy: LocationAccuracy = .best,
         stationaryAccuracy: LocationAccuracy = .hundredMetres,
         movingDistanceFilter: Double = 10,
         stationaryDistanceFilter: Double = 30,
         movingInterval: TimeInterval = 30,
         stationaryInterval: TimeInterval = 600,
         stopThreshold: TimeInterval = 180,
         movingSpeed: Double = 0.8,
         accuracyCeiling: Double = 100,
         heartbeatInterval: TimeInterval = 60,
         activity: LocationActivity = .other,
         pausesAutomatically: Bool = true,
         significantChangeMonitoring: Bool = true,
         motion: MotionSettings = MotionSettings()) {
        self.movingAccuracy = movingAccuracy
        self.stationaryAccuracy = stationaryAccuracy
        self.movingDistanceFilter = movingDistanceFilter
        self.stationaryDistanceFilter = stationaryDistanceFilter
        self.movingInterval = movingInterval
        self.stationaryInterval = stationaryInterval
        self.stopThreshold = stopThreshold
        self.movingSpeed = movingSpeed
        self.accuracyCeiling = accuracyCeiling
        self.heartbeatInterval = heartbeatInterval
        self.activity = activity
        self.pausesAutomatically = pausesAutomatically
        self.significantChangeMonitoring = significantChangeMonitoring
        self.motion = motion
    }
}

import Foundation
import Combine
import CoreLocation

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
                return "Cell and wifi only, no heartbeat, iOS free to pause. Expect a position within a few hundred metres, minutes old."
            case .balanced:
                return "GPS to ten metres while moving, cheap fixes when stopped, heartbeat every five minutes."
            case .accurate:
                return "Full GPS while moving and a fix every minute. What the app shipped with, and what is draining the battery now."
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
                    pausesAutomatically: true, significantChangeMonitoring: true)
            case .balanced:
                return LocationSettings(
                    movingAccuracy: .tenMetres, stationaryAccuracy: .hundredMetres,
                    movingDistanceFilter: 25, stationaryDistanceFilter: 100,
                    movingInterval: 60, stationaryInterval: 900,
                    stopThreshold: 240, movingSpeed: 0.8, accuracyCeiling: 150,
                    heartbeatInterval: 300, activity: .fitness,
                    pausesAutomatically: true, significantChangeMonitoring: true)
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
}

import Foundation
import CoreLocation

/// A place the household has flagged "track closely after leaving" — Home by
/// default. Sent down by the site inside the household view, and registered
/// with iOS as a geofence, which is one of the three things that can wake a
/// suspended app.
struct WatchedPlace: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let lat: Double
    let lon: Double
    let radiusM: Double

    /// Below ~100 m iOS geofences fire late or not at all: the exit is
    /// decided on cell and wifi, not GPS, so a tight circle is a coin toss.
    static let minimumRadius: Double = 100
    /// iOS allows twenty regions per app and the motion gate owns one.
    static let maximum = 15

    var regionID: String { Outing.regionPrefix + id }

    var region: CLCircularRegion {
        let r = CLCircularRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                 radius: max(radiusM, Self.minimumRadius),
                                 identifier: regionID)
        r.notifyOnExit = true
        r.notifyOnEntry = true
        return r
    }
}

/// Close tracking after leaving a watched place: every fix the GPS gives, about
/// one a second, whatever the phone is doing — on foot, on a bike, in a car or
/// on a train (John's call, 2026-09-26: 1 Hz for every mode).
///
/// It ends on its own. Leaving a place and then sitting in a café for an hour
/// must not run the GPS flat out for that hour, so:
///
/// - **Still for five minutes** — within 50 m of where the phone last moved.
///   Long enough to ride out traffic lights, a level crossing or a train
///   sitting at a platform; short enough that a meeting or a coffee drops back
///   to the motion gate quickly.
/// - **Back inside a watched place.**
/// - **Four hours**, as a ceiling. A forgotten phone in a car park should not
///   spend its whole battery proving it has not moved.
/// - **Battery at 15% and not charging** — the family would rather have a
///   phone that still answers than a better line.
struct OutingState: Codable, Equatable {
    var placeID: String
    var placeLabel: String
    var startedAt: Date
    /// When the phone last moved more than `Outing.stillRadius` from `anchor`.
    var lastMovedAt: Date
    var anchorLat: Double?
    var anchorLon: Double?
}

enum Outing {
    static let regionPrefix = "sr.watch."
    static let stillFor: TimeInterval = 300
    static let stillRadius: Double = 50
    static let maxDuration: TimeInterval = 4 * 3600
    static let lowBattery: Double = 0.15
    /// Points are held and sent together this often — one upload and one write
    /// of the state file per half-minute rather than one a second.
    static let commitEvery: TimeInterval = 30
    /// A fix looser than this at 1 Hz is noise drawn as a line.
    static let accuracyCeiling: Double = 50

    enum End: Equatable {
        case still, tooLong, lowBattery
        var reason: String {
            switch self {
            case .still: return "Still for \(Int(Outing.stillFor / 60)) min"
            case .tooLong: return "Four hours of close tracking"
            case .lowBattery: return "Battery low"
            }
        }
    }

    /// Fold one fix into the outing: movement beyond the still radius moves
    /// the anchor and restarts the stillness clock. PURE.
    static func moved(_ state: OutingState, lat: Double, lon: Double, at: Date) -> OutingState {
        var next = state
        guard let aLat = state.anchorLat, let aLon = state.anchorLon else {
            next.anchorLat = lat; next.anchorLon = lon; next.lastMovedAt = at
            return next
        }
        let d = CLLocation(latitude: aLat, longitude: aLon).distance(from: CLLocation(latitude: lat, longitude: lon))
        if d > stillRadius {
            next.anchorLat = lat; next.anchorLon = lon; next.lastMovedAt = at
        }
        return next
    }

    /// Whether close tracking should stop now, and why. PURE.
    static func shouldEnd(_ state: OutingState, now: Date, battery: Double?, charging: Bool) -> End? {
        if let battery, battery >= 0, battery <= lowBattery, !charging { return .lowBattery }
        if now.timeIntervalSince(state.startedAt) >= maxDuration { return .tooLong }
        if now.timeIntervalSince(state.lastMovedAt) >= stillFor { return .still }
        return nil
    }

    /// The watched places to register: nearest first when there are more than
    /// iOS will hold, so the ones that matter today are the ones watched. PURE.
    static func toRegister(_ places: [WatchedPlace], near: CLLocation?) -> [WatchedPlace] {
        guard places.count > WatchedPlace.maximum, let near else { return Array(places.prefix(WatchedPlace.maximum)) }
        return Array(places.sorted {
            CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: near) <
                CLLocation(latitude: $1.lat, longitude: $1.lon).distance(from: near)
        }.prefix(WatchedPlace.maximum))
    }
}

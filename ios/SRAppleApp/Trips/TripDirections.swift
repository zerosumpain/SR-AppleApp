import Foundation
import MapKit
import UIKit

/// Getting to the next stop — without rebuilding anybody's navigation.
///
/// A WALKING leg becomes a route the app already knows how to follow
/// (`FollowRouteScreen`: the line, you on it, off-route warnings, a pack that
/// works offline). Anything else is handed to an app that does transit and
/// driving properly: Apple Maps with the right directions mode, or Citymapper
/// when it is installed. Live timetables, platforms and disruption are theirs.
enum TripDirections {
    /// Citymapper's URL scheme. Listed in `LSApplicationQueriesSchemes`, or
    /// `canOpenURL` would always say no.
    static let citymapperScheme = "citymapper"

    /// Whether a leg is walked in-app.
    static func followsInApp(_ leg: PlannedLeg) -> Bool { leg.mode == .walk }

    /// The leg as a route `FollowRouteScreen` can walk.
    static func route(for leg: PlannedLeg, from: PlannedStop, to: PlannedStop, tripId: String, date: String) -> PlannedRouteDetail? {
        var points = (leg.line ?? []).map { RoutePoint(lat: $0.lat, lng: $0.lng, ele: nil) }
        if points.count < 2, let a = from.location, let b = to.location {
            points = [RoutePoint(lat: a.lat, lng: a.lng, ele: nil), RoutePoint(lat: b.lat, lng: b.lng, ele: nil)]
        }
        guard points.count >= 2 else { return nil }
        return PlannedRouteDetail(
            tripLegId: "trip:\(tripId):\(date):\(leg.fromStopId)>\(leg.toStopId)",
            name: "To \(to.title)",
            distanceM: leg.distanceM ?? RouteNav.cumulative(points.map(\.coordinate)).last ?? 0,
            durationS: leg.durationSec,
            route: points
        )
    }

    /// Apple Maps, directions to the stop in the leg's mode. Transit where
    /// Apple has it; where it does not, Maps says so itself.
    @MainActor
    static func openInMaps(_ stop: PlannedStop, mode: TravelMode) {
        guard let at = stop.location else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: at.lat, longitude: at.lng)))
        item.name = stop.title
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: directionsMode(mode)])
    }

    static func directionsMode(_ mode: TravelMode) -> String {
        switch mode {
        case .walk: return MKLaunchOptionsDirectionsModeWalking
        case .drive: return MKLaunchOptionsDirectionsModeDriving
        case .transit: return MKLaunchOptionsDirectionsModeTransit
        // Maps has no cycling launch mode to ask for: its default opens on
        // the person's own preferred mode, which for a cyclist is cycling.
        case .cycle: return MKLaunchOptionsDirectionsModeDefault
        }
    }

    /// Citymapper's directions link, from where you are to the stop.
    static func citymapperURL(to stop: PlannedStop) -> URL? {
        guard let at = stop.location else { return nil }
        var c = URLComponents()
        c.scheme = citymapperScheme
        c.host = "directions"
        c.queryItems = [
            URLQueryItem(name: "endcoord", value: String(format: "%.6f,%.6f", at.lat, at.lng)),
            URLQueryItem(name: "endname", value: stop.title),
        ]
        return c.url
    }

    @MainActor
    static var hasCitymapper: Bool {
        guard let probe = URL(string: "\(citymapperScheme)://") else { return false }
        return UIApplication.shared.canOpenURL(probe)
    }

    @MainActor
    static func openInCitymapper(_ stop: PlannedStop) {
        guard let url = citymapperURL(to: stop) else { return }
        UIApplication.shared.open(url)
    }
}

extension PlannedRouteDetail {
    /// `source` of a route made from a trip leg: walked and recorded, but not
    /// a saved route Health would know the id of (`FollowSession`, `LiveShare`).
    static let tripSource = "trip"

    /// A trip leg as a route to follow. Every saved-route field the leg has
    /// no answer for is empty.
    init(tripLegId: String, name: String, distanceM: Double, durationS: Double?, route: [RoutePoint]) {
        id = tripLegId
        self.name = name
        sport = "walk"
        source = Self.tripSource
        self.distanceM = distanceM
        ascentM = nil
        descentM = nil
        self.durationS = durationS
        score = nil
        createdAt = nil
        notes = nil
        self.route = route
        targetDistanceM = nil
        waypoints = []
    }
}

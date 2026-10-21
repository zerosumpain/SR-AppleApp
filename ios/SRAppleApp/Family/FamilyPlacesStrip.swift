import Foundation
import CoreLocation

/// The places along the top of the Family tab: Home, wherever somebody is now,
/// and the family's saved places — the "favourite locations" John asked for
/// in place of a row of icons that repeated the bottom bar (2026-10-21).
///
/// Choosing one frames the map on it; "Everyone" frames the family again.
/// Nothing here is new data: the occupied places are `HouseholdView.places()`,
/// the saved ones the view's watch list (the places whose leaving switches a
/// phone to close tracking, Home among them).
struct FamilyFavourite: Equatable, Identifiable {
    let id: String
    let name: String
    let isHome: Bool
    /// Who is there now.
    let people: [String]
    /// What the map frames: the people there, or the saved place's centre.
    let points: [Point]

    struct Point: Equatable {
        let lat: Double
        let lon: Double
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    }

    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }
}

enum FamilyFavourites {
    /// The strip's id for "everyone".
    static let everyone = "everyone"
    /// No more than this many places: a strip, not a second list.
    static let limit = 8

    /// Home first, then the places people are at (most people first), then the
    /// saved places nobody is at. A group that is a journey — everyone in it
    /// moving — or the site's unnamed "Out" is not a place to choose. PURE.
    static func make(_ view: HouseholdView) -> [FamilyFavourite] {
        var out: [FamilyFavourite] = []
        for place in view.places() where !place.isMoving && place.name != "Out" {
            let points = place.people.compactMap { p in p.position.map { FamilyFavourite.Point(lat: $0.lat, lon: $0.lon) } }
            // Home with nobody placed by a position still has its saved centre.
            let saved = (view.watch ?? []).first { $0.label.lowercased() == place.name.lowercased() }
            let framed = points.isEmpty ? saved.map { [FamilyFavourite.Point(lat: $0.lat, lon: $0.lon)] } ?? [] : points
            guard !framed.isEmpty else { continue }
            out.append(FamilyFavourite(id: place.name.lowercased(), name: place.name, isHome: place.isHome,
                                       people: place.people.map(\.subject), points: framed))
        }
        for place in view.watch ?? [] where !out.contains(where: { $0.id == place.label.lowercased() }) {
            let isHome = place.label.lowercased() == "home"
            out.append(FamilyFavourite(id: place.label.lowercased(), name: place.label, isHome: isHome,
                                       people: [], points: [FamilyFavourite.Point(lat: place.lat, lon: place.lon)]))
        }
        // Stable: Home, then occupied by headcount, then the rest as they came.
        let ordered = out.enumerated().sorted { a, b in
            if a.element.isHome != b.element.isHome { return a.element.isHome }
            if a.element.people.count != b.element.people.count { return a.element.people.count > b.element.people.count }
            return a.offset < b.offset
        }.map(\.element)
        return Array(ordered.prefix(limit))
    }

    /// The chips: "Everyone", then each place with how many are there.
    static func chips(_ places: [FamilyFavourite], total: Int) -> [SRChip] {
        [SRChip(id: everyone, title: "Everyone", icon: "person.2.fill", count: total)]
            + places.map { place in
                SRChip(id: place.id, title: place.name,
                       icon: place.isHome ? "house.fill" : "mappin.circle.fill",
                       count: place.people.count)
            }
    }
}

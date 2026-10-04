import SwiftUI
import MapKit

/// Landgrab's weekly board, from the site (`GET /api/native/family/landgrab`).
///
/// A guest on the steps page: it loads on its own, after the step board has
/// been asked for and never in its way, and it has no error state of its own.
/// Not family (403), not on the site yet (404), signed out (401) or nobody on
/// the board → no section at all. Anything else (Health down, offline) keeps
/// whatever was last shown, or nothing.
@MainActor
final class LandgrabStore: ObservableObject {
    static let shared = LandgrabStore()

    /// The site's weeks request: this week and five before it.
    static let path = "api/native/family/landgrab?weeks=6"

    @Published private(set) var board: LandgrabBoard?
    @Published private(set) var loaded = false
    private var loading = false

    /// Whether the steps page draws the section.
    var visible: Bool { Landgrab.shows(board) }

    func load() async {
        guard SiteClient.shared.isPaired, !loading else { return }
        loading = true
        defer { loading = false; loaded = true }
        do {
            let fetched: LandgrabBoard = try await SiteClient.shared.send(Self.path)
            board = fetched
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            if Self.hides(error) { board = nil }
        }
    }

    /// The answers that mean "this person has no Landgrab board", as opposed
    /// to "the board could not be read just now".
    static func hides(_ error: Error) -> Bool {
        guard let status = (error as? SiteError)?.status else { return false }
        return status == 401 || status == 403 || status == 404
    }

    /// "View as", sign-out, leaving the demo: the board was somebody else's.
    func reset() {
        board = nil
        loaded = false
    }
}

/// One week's changes for the map, with everything the map draws worked out
/// once per week: the hex outlines as map coordinates, each person's colour,
/// each change's hexes, trace and camera region. Up to 4,000 hexes, so none
/// of this may happen in a view's `body`.
struct LandgrabMapLayer {
    struct Hex: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let colour: Color
    }

    let hexes: [Hex]
    let hexesByChange: [String: Set<Int>]
    let traces: [String: [CLLocationCoordinate2D]]
    let weekRegion: MKCoordinateRegion?
    let changeRegions: [String: MKCoordinateRegion]

    init(_ plan: LandgrabMapPlan) {
        hexes = plan.shapes.map { Hex(id: $0.id, coordinates: $0.points.map(Self.coordinate), colour: Color(landgrab: $0.colour)) }
        hexesByChange = plan.hexesByChange
        traces = plan.traces.mapValues { $0.map(Self.coordinate) }
        weekRegion = plan.weekRegion.map(Self.region)
        changeRegions = plan.changeRegions.mapValues(Self.region)
    }

    /// The wire's `[lat, lon]` — latitude FIRST, the opposite of GeoJSON.
    static func coordinate(_ point: LandgrabPoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }

    static func region(_ region: LandgrabRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: region.centreLat, longitude: region.centreLon),
            span: MKCoordinateSpan(latitudeDelta: region.latSpan, longitudeDelta: region.lonSpan)
        )
    }
}

/// What changed in one week (`GET /api/native/family/landgrab/changes?week=`),
/// for the map screen. One per screen; weeks already read are kept for the
/// screen's life, so flicking back through the picker costs nothing.
@MainActor
final class LandgrabChangesStore: ObservableObject {
    struct Week {
        let changes: LandgrabChanges
        let layer: LandgrabMapLayer
        /// The list, in the order it is shown.
        let ordered: [LandgrabChange]
    }

    /// The Monday on screen ("2026-09-28").
    @Published private(set) var week: String?
    @Published private(set) var shown: Week?
    @Published private(set) var loading = false
    @Published var message: String?

    private var cache: [String: Week] = [:]

    static func path(week: String) -> String { "api/native/family/landgrab/changes?week=\(week)" }

    func load(week: String, force: Bool = false) async {
        self.week = week
        if !force, let cached = cache[week] {
            shown = cached
            message = nil
            loading = false
            return
        }
        if cache[week] == nil { shown = nil }
        loading = true
        defer { if self.week == week { loading = false } }
        do {
            let fetched: LandgrabChanges = try await SiteClient.shared.send(Self.path(week: week))
            let built = Self.build(fetched)
            cache[week] = built
            // A slow answer for a week the picker has already left is kept,
            // not shown.
            guard self.week == week else { return }
            shown = built
            message = nil
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            guard self.week == week else { return }
            message = Self.sentence(for: error)
        }
    }

    static func build(_ changes: LandgrabChanges) -> Week {
        Week(changes: changes, layer: LandgrabMapLayer(LandgrabMapPlan(changes)), ordered: Landgrab.ordered(changes.changes))
    }

    static func sentence(for error: Error) -> String {
        switch (error as? SiteError)?.status {
        case 403?: return "Landgrab is for the family."
        case 404?: return "Landgrab isn't on the site yet."
        case 400?: return "That week is out of range."
        case 502?, 503?: return "Landgrab can't be read right now. Try again in a minute."
        default: return error.localizedDescription
        }
    }
}

extension Color {
    init(landgrab colour: LandgrabRGB) {
        self.init(.sRGB, red: colour.red, green: colour.green, blue: colour.blue, opacity: 1)
    }
}

/// A person's colour, resolved, and the ink or cream that reads on it.
struct LandgrabPaint {
    let fill: Color
    let onFill: Color

    init(_ hex: String?, id: String) {
        let rgb = LandgrabColour.resolve(hex, id: id)
        fill = Color(landgrab: rgb)
        // The FIXED pair, not `SR.ink`/`SR.paper`: the fill does not change
        // with the phone's appearance, so neither may what is written on it.
        onFill = LandgrabColour.writesInInk(on: rgb) ? SR.band : SR.cream
    }
}

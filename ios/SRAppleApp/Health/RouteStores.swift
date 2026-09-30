import Foundation
import CoreLocation
import Combine

enum RoutePath {
    static let list = "api/native/health/routes"
    static let plan = "api/native/health/routes/plan"
    static let interpret = "api/native/health/routes/interpret"

    static func route(_ id: String) -> String { "api/native/health/routes/\(TrailPath.escape(id))" }
    static func suggest(sport: String) -> String { "\(plan)?sport=\(TrailPath.escape(sport))" }

    static func nearby(lat: Double, lng: Double, sport: String) -> String {
        "api/native/health/routes/discover?lat=\(lat)&lng=\(lng)&sport=\(TrailPath.escape(sport))"
    }

    static func published(osmId: Int, sport: String) -> String {
        "api/native/health/routes/discover?osmId=\(osmId)&sport=\(TrailPath.escape(sport))"
    }
}

/// Saved routes, newest first.
@MainActor
final class RoutesStore: ObservableObject {
    @Published private(set) var rows: [PlannedRouteSummary] = []
    @Published private(set) var state: TrailLoad = .idle

    private let client = SiteClient.shared

    func load() async {
        guard AccessStore.ownerSite, state != .loading else { return }
        state = .loading
        do {
            let page: RoutesPage = try await client.send(RoutePath.list)
            rows = page.routes
            state = .loaded
        } catch {
            state = rows.isEmpty ? TrailLoad.from(error) : .loaded
        }
    }

    func delete(_ id: String) async {
        let before = rows
        rows.removeAll { $0.id == id }
        do {
            try await client.call(RoutePath.route(id), method: "DELETE")
            RouteCache.remove(id)
            OfflineMaps.shared.delete(id)
        } catch {
            // Put it back: a row that vanished and is still on the server
            // would reappear on the next refresh looking like a ghost.
            rows = before
        }
    }
}

@MainActor
final class PlannedRouteStore: ObservableObject {
    @Published private(set) var detail: PlannedRouteDetail?
    @Published private(set) var state: TrailLoad = .idle

    private let client = SiteClient.shared

    /// Whether what is on screen came from the phone's own copy.
    @Published private(set) var fromCache = false

    func load(_ id: String) async {
        guard state != .loading else { return }
        if detail == nil, let kept = RouteCache.load(id) {
            detail = kept
            fromCache = true
        }
        state = .loading
        do {
            let data = try await client.bytes(RoutePath.route(id))
            let fetched = try JSONDecoder().decode(PlannedRouteDetail.self, from: data)
            RouteCache.store(data, id: id)
            detail = fetched
            fromCache = false
            state = .loaded
        } catch {
            state = detail == nil ? TrailLoad.from(error) : .loaded
        }
    }
}

/// The plan form, and what came back from it.
///
/// The form is the request; the typed sentence only fills the form. Nothing is
/// planned until Plan is pressed, so a misread sentence costs a glance, not an
/// openrouteservice call.
@MainActor
final class RoutePlanner: ObservableObject {
    enum Shape: String, CaseIterable, Identifiable {
        case loop, toPlace
        var id: String { rawValue }
        var label: String { self == .loop ? "Loop" : "A to B" }
    }

    enum Climb: String, CaseIterable, Identifiable {
        case any, flat, rolling, hilly
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        /// Metres of climb per km, as the web form's presets.
        var gainPerKm: Double? {
            switch self {
            case .any: return nil
            case .flat: return 5
            case .rolling: return 15
            case .hilly: return 30
            }
        }

        static func nearest(_ perKm: Double) -> Climb {
            if perKm < 10 { return .flat }
            if perKm < 22 { return .rolling }
            return .hilly
        }
    }

    // The form.
    @Published var sport: RouteSport = .walk
    @Published var shape: Shape = .loop
    @Published var distanceKm: Double = 5
    @Published var climb: Climb = .any
    @Published var steady = false
    @Published var allowOutAndBack = false
    @Published var start: CLLocationCoordinate2D?
    @Published var startLabel = "Your location"
    @Published var finish: CLLocationCoordinate2D?
    @Published var finishLabel: String?
    @Published var request = ""

    // What came back.
    @Published private(set) var suggestion: String?
    @Published private(set) var reading: [String] = []
    @Published private(set) var plan: RoutePlan?
    @Published var chosen: Int = 1
    @Published private(set) var busy: Busy?
    @Published var error: String?

    enum Busy: Equatable { case locating, reading, planning, saving }

    private let client = SiteClient.shared

    var canPlan: Bool {
        start != nil && busy == nil && (shape == .loop || finish != nil)
    }

    var chosenCandidate: RouteCandidate? {
        plan?.candidates.first { $0.rank == chosen } ?? plan?.candidates.first
    }

    // MARK: Where from

    func locate() async {
        guard start == nil else { return }
        busy = .locating
        defer { if busy == .locating { busy = nil } }
        if let here = await OneFix.current() {
            start = here
            startLabel = "Your location"
        } else if start == nil {
            error = "Could not find where you are. Long-press the map to set a start."
        }
    }

    /// Health's suggested distance for this sport, from the last eight weeks.
    func suggest() async {
        do {
            let s: RouteSuggestion = try await client.send(RoutePath.suggest(sport: sport.rawValue))
            distanceKm = max(0.5, (s.distanceM / 100).rounded() / 10)
            suggestion = s.rationale.first
        } catch {
            suggestion = nil
        }
    }

    // MARK: Words to form

    func interpret() async {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        busy = .reading
        defer { busy = nil }
        error = nil
        struct Body: Encodable {
            struct Focus: Encodable { let lat: Double; let lng: Double }
            let text: String
            let focus: Focus?
        }
        let focus = start.map { Body.Focus(lat: $0.latitude, lng: $0.longitude) }
        do {
            let body = try JSONEncoder().encode(Body(text: text, focus: focus))
            let read: RouteInterpretation = try await client.send(RoutePath.interpret, method: "POST", body: body)
            apply(read)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func apply(_ read: RouteInterpretation) {
        let p = read.parsed
        if let raw = p.sport, let s = RouteSport(rawValue: raw) { sport = s }
        if let km = p.targetKm, km > 0 { distanceKm = min(max(km, 0.5), 100) }
        if let perKm = p.climbPerKm { climb = Climb.nearest(perKm) }
        if let prefer = p.prefer { steady = prefer == "steady" }
        if let back = p.allowOutAndBack { allowOutAndBack = back }
        if let place = read.start {
            start = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)
            startLabel = place.label
        }
        if let place = read.finish {
            finish = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)
            finishLabel = place.label
            shape = .toPlace
        } else if p.mode == "loop" {
            shape = .loop
        } else if p.mode == "point" {
            shape = .toPlace
        }
        reading = read.interpretation
    }

    // MARK: Plan and save

    func makeRequest() -> RoutePlanRequest? {
        guard let start else { return nil }
        let toPlace = shape == .toPlace ? finish : nil
        if shape == .toPlace, toPlace == nil { return nil }
        return RoutePlanRequest(
            startLat: start.latitude,
            startLng: start.longitude,
            finishLat: toPlace?.latitude,
            finishLng: toPlace?.longitude,
            sport: sport.rawValue,
            // A to B is as long as the ground between them; a target would
            // only fight the router.
            targetDistanceM: toPlace == nil ? (distanceKm * 1000).rounded() : nil,
            targetGainPerKm: climb.gainPerKm,
            prefer: climb == .any ? nil : (steady ? "steady" : "any"),
            allowOutAndBack: allowOutAndBack ? true : nil
        )
    }

    func planRoute() async {
        guard let body = makeRequest(), busy == nil else { return }
        busy = .planning
        defer { busy = nil }
        error = nil
        do {
            let data = try JSONEncoder().encode(body)
            let result: RoutePlan = try await client.send(RoutePath.plan, method: "POST", body: data, timeout: 75)
            plan = result
            chosen = result.candidates.first?.rank ?? 1
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clearPlan() {
        plan = nil
    }

    /// Save the chosen candidate. Returns the new route's ref to push to.
    func save(name: String) async -> RouteRef? {
        guard let c = chosenCandidate, let plan, busy == nil else { return nil }
        busy = .saving
        defer { busy = nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? defaultName(for: c) : trimmed
        let save = RouteSaveRequest(
            name: title,
            sport: sport.rawValue,
            route: c.route.map(\.json),
            distanceM: c.distanceM,
            ascentM: c.ascentM,
            descentM: c.descentM,
            durationS: c.durationS,
            score: c.score,
            scoreBreakdown: c.breakdown,
            targetDistanceM: plan.targetDistanceM,
            source: "planned"
        )
        do {
            let saved: RouteSaved = try await client.send(
                RoutePath.list, method: "POST", body: try JSONEncoder().encode(save)
            )
            return RouteRef(id: saved.id, name: title)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func defaultName(for c: RouteCandidate) -> String {
        let kind = shape == .loop ? "loop" : "route"
        return "\(TrailFormat.km(c.distanceM)) km \(sport.label.lowercased()) \(kind)"
    }
}

/// Published routes near a point, and saving one of them.
@MainActor
final class NearbyRoutesStore: ObservableObject {
    @Published private(set) var rows: [DiscoveredRoute] = []
    @Published private(set) var state: TrailLoad = .idle
    @Published private(set) var saving: Int?
    @Published var error: String?

    private let client = SiteClient.shared

    func load(near point: CLLocationCoordinate2D, sport: RouteSport) async {
        state = .loading
        do {
            let page: DiscoveredPage = try await client.send(
                RoutePath.nearby(lat: point.latitude, lng: point.longitude, sport: sport.rawValue), timeout: 45
            )
            rows = page.routes
            state = .loaded
        } catch {
            state = TrailLoad.from(error)
        }
    }

    func save(_ route: DiscoveredRoute, sport: RouteSport) async -> RouteRef? {
        saving = route.osmId
        defer { saving = nil }
        do {
            let d: DiscoveredDetail = try await client.send(
                RoutePath.published(osmId: route.osmId, sport: sport.rawValue), timeout: 45
            )
            let body = RouteSaveRequest(
                name: d.name, sport: sport.rawValue, route: d.route.map(\.json),
                distanceM: d.distanceM, ascentM: d.ascentM, descentM: nil,
                durationS: d.difficulty?.estimatedTimeS, score: nil, scoreBreakdown: nil,
                targetDistanceM: nil, source: "imported"
            )
            let saved: RouteSaved = try await client.send(
                RoutePath.list, method: "POST", body: try JSONEncoder().encode(body)
            )
            return RouteRef(id: saved.id, name: d.name)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}

/// One location fix, for the planner's start. `CLLocationUpdate` asks for
/// When-In-Use by itself and needs no delegate; ten seconds is the most a
/// form should wait before telling you to place the pin by hand.
enum OneFix {
    static func current(timeout: Duration = .seconds(10)) async -> CLLocationCoordinate2D? {
        // The demo has no location and must not ask for one.
        if SRDemo.isOn { return CLLocationCoordinate2D(latitude: 40.7812, longitude: -73.9665) }
        return await withTaskGroup(of: CLLocationCoordinate2D?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let loc = update.location, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 200 {
                            return loc.coordinate
                        }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

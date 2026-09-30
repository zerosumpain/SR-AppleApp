import Foundation

// `-SRDemo` answers for /api/native/health/routes/* — the planner, saved
// routes and published routes nearby. SYNTHETIC: loops drawn round Central
// Park, never a real route (this repository is public).

extension SRDemoFixtures {

    static let demoRouteId = "7d3c6a10-2b41-4c1e-9a52-5f0e8b1d2c3a"
    static let demoRouteImportedId = "0e9b8a71-6c5d-4e3f-8a21-b0c9d8e7f6a5"

    static func routesRoute(method: String, parts: [String], query: [String: String], body: Data?) -> String? {
        // parts: ["api", "native", "health", "routes", ...]
        let rest = Array(parts.dropFirst(4))
        switch (method, rest.first) {
        case ("GET", nil):
            return routesList
        case ("POST", nil):
            return "{\"id\": \(s(demoRouteId))}"
        case ("GET", "plan"?):
            return #"{"configured": true, "distanceM": 8000, "source": "training-load", "rationale": ["About your usual walk over the last eight weeks."]}"#
        case ("POST", "plan"?):
            return routePlan(body: body)
        case ("POST", "interpret"?):
            return #"{"parsed": {"sport": "walk", "mode": "loop", "targetKm": 8, "climbPerKm": 15, "prefer": "steady", "allowOutAndBack": false}, "start": null, "finish": null, "interpretation": ["Sport: walk.", "Distance: 8.0 km.", "Climb: about 15 m/km.", "Steady climbing."]}"#
        case ("GET", "discover"?):
            if let id = query["osmId"], let osmId = Int(id) { return discoveredDetail(osmId) }
            return discoveredList
        case ("GET", let id?):
            return routeDetail(id: id)
        case ("DELETE", _?):
            return #"{"deleted": true}"#
        default:
            return nil
        }
    }

    /// A loop round the park's centre with a gentle, invented profile.
    static func routeLoop(scale: Double, points: Int = 90, phase: Double = 0) -> [(Double, Double, Double)] {
        let centre = (lat: 40.7812, lng: -73.9665)
        var out: [(Double, Double, Double)] = []
        for i in 0...points {
            let t = Double(i) / Double(points) * 2 * Double.pi
            let wobble = 1 + 0.07 * sin(t * 4 + phase) + 0.03 * cos(t * 9)
            let lat = centre.lat + cos(t) * 0.0135 * scale * wobble
            let lng = centre.lng + sin(t) * 0.0105 * scale * wobble + cos(t) * 0.004 * scale
            let ele = 30 + 12 * sin(t * 2 + phase) + 4 * sin(t * 7)
            out.append((lat, lng, ele))
        }
        return out
    }

    static func routeJSON3(_ points: [(Double, Double, Double)]) -> String {
        list(points.map { "[\(coord($0.0)), \(coord($0.1)), \(String(format: "%.1f", $0.2))]" })
    }

    static var routesList: String {
        """
        {"routes": [
          {"id": \(s(demoRouteId)), "name": "Reservoir and the Ramble", "sport": "walk", "source": "planned",
           "distanceM": 8040, "ascentM": 96, "descentM": 95, "durationS": 6120, "score": 0.84,
           "createdAt": "2026-09-28T07:10:00.000Z", "notes": null,
           "bounds": {"n": 40.796, "s": 40.767, "e": -73.953, "w": -73.980}},
          {"id": \(s(demoRouteImportedId)), "name": "Park Drive loop", "sport": "run", "source": "imported",
           "distanceM": 9820, "ascentM": 71, "descentM": null, "durationS": 3480, "score": null,
           "createdAt": "2026-09-20T18:02:00.000Z", "notes": null,
           "bounds": {"n": 40.798, "s": 40.765, "e": -73.950, "w": -73.982}}
        ]}
        """
    }

    static func routeDetail(id: String) -> String? {
        guard id == demoRouteId || id == demoRouteImportedId else { return nil }
        let planned = id == demoRouteId
        return """
        {"id": \(s(id)), "name": \(s(planned ? "Reservoir and the Ramble" : "Park Drive loop")),
         "sport": \(s(planned ? "walk" : "run")), "source": \(s(planned ? "planned" : "imported")),
         "distanceM": \(planned ? 8040 : 9820), "ascentM": \(planned ? 96 : 71), "descentM": null,
         "durationS": \(planned ? 6120 : 3480), "score": \(planned ? "0.84" : "null"),
         "createdAt": "2026-09-28T07:10:00.000Z", "notes": null,
         "bounds": {"n": 40.796, "s": 40.767, "e": -73.953, "w": -73.980},
         "route": \(routeJSON3(routeLoop(scale: planned ? 1.0 : 1.15, points: 160))),
         "targetDistanceM": \(planned ? "8000" : "null"),
         "waypoints": [{"id": "w1", "name": "Water fountain", "icon": "water", "lat": 40.7853, "lng": -73.9621, "note": null}]}
        """
    }

    static func routePlan(body: Data?) -> String {
        let fields = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let target = (fields?["targetDistanceM"] as? Double) ?? 8000
        let options: [(rank: Int, scale: Double, phase: Double, score: Double, km: Double, up: Int, notes: [String])] = [
            (1, 1.0, 0.0, 0.84, target / 1000, 96, ["Little doubling back.", "Climbing spread evenly."]),
            (2, 0.9, 1.4, 0.77, target / 1000 * 0.94, 71, ["One short out-and-back to the fountain."]),
            (3, 1.1, 2.6, 0.69, target / 1000 * 1.08, 118, ["Most of the climb in one hill.", "Crosses the drive twice."]),
        ]
        let candidates = options.map { o -> String in
            """
            {"rank": \(o.rank), "score": \(o.score), "notes": \(list(o.notes.map { s($0) })),
             "distanceM": \(Int(o.km * 1000)), "durationS": \(Int(o.km * 760)), "ascentM": \(o.up), "descentM": \(o.up),
             "route": \(routeJSON3(routeLoop(scale: o.scale, points: 120, phase: o.phase))),
             "breakdown": {"total": \(o.score), "distanceScore": 0.93, "notes": \(list(o.notes.map { s($0) }))}}
            """
        }
        return """
        {"candidates": \(list(candidates)), "targetDistanceM": \(Int(target)), "targetSource": "requested",
         "rationale": ["You asked for \(TrailFormat.km(target)) km."]}
        """
    }

    static let discoveredList = """
    {"routes": [
      {"osmId": 1001, "name": "Central Park Loop", "network": "lwn", "distanceKm": 9.8, "operator": null, "ref": null},
      {"osmId": 1002, "name": "Reservoir Running Track", "network": "lwn", "distanceKm": 2.5, "operator": "Parks", "ref": "RT"}
    ]}
    """

    static func discoveredDetail(_ osmId: Int) -> String {
        """
        {"osmId": \(osmId), "name": "Central Park Loop", "distanceM": 9820, "ascentM": 71,
         "difficulty": {"band": "moderate", "estimatedTimeS": 7200},
         "route": \(routeJSON3(routeLoop(scale: 1.15, points: 120)))}
        """
    }
}

// MARK: - Live route walks

extension SRDemoFixtures {
    static let demoLiveWalkId = "route-demoWalk1"

    static func routeSessionRoute(method: String, parts: [String]) -> String? {
        // parts: ["api", "native", "route-session", ...]
        let rest = Array(parts.dropFirst(3))
        switch (method, rest.count, rest.last) {
        case ("POST", 0, _):
            return #"{"id": "route-demoMine", "followers": 2, "shareUrl": "https://strangeramblings.com/follow/demo-link-not-real-000000000000000000000"}"#
        case ("GET", 0, _):
            return "{\"sessions\": [\(liveWalk(full: false))]}"
        case ("GET", 1, _):
            return rest[0] == demoLiveWalkId ? liveWalk(full: true) : nil
        case ("POST", 2, "fixes"?):
            return #"{"ok": true, "ended": false}"#
        case ("POST", 2, "end"?):
            return #"{"ok": true}"#
        default:
            return nil
        }
    }

    /// Alex, two fifths of the way round the park loop.
    static func liveWalk(full: Bool) -> String {
        let loop = routeLoop(scale: 1.0, points: 160)
        let walked = Array(loop.prefix(65))
        let t0 = 1_790_000_000.0
        let route = full ? list(loop.map { "[\(coord($0.0)), \(coord($0.1))]" }) : list([loop.first!, loop.last!].map { "[\(coord($0.0)), \(coord($0.1))]" })
        let trail = full ? list(walked.enumerated().map { "[\(coord($0.element.0)), \(coord($0.element.1)), \(Int(t0) + $0.offset * 20)]" }) : "[]"
        return """
        {"id": \(s(demoLiveWalkId)), "name": "Alex", "routeName": "Reservoir and the Ramble", "sport": "walk",
         "route": \(route), "trail": \(trail), "totalM": 8040,
         "progress": {"alongM": 3260, "remainingM": 4780, "offRouteM": 6, "offRoute": false, "timeLeftS": 3480},
         "startedAt": "2026-09-30T08:10:00.000Z", "lastFixAt": "2026-09-30T08:52:00.000Z", "endedAt": null, "endReason": null}
        """
    }
}

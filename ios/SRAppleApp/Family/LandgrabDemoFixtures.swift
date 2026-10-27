import Foundation

// MARK: - Demo Landgrab
//
// `-SRDemo` answers for `/api/native/family/landgrab`,
// `/api/native/family/landgrab/changes` and
// `/api/native/family/landgrab/explored`. Synthetic throughout — the
// repository is public. The ground is a grid of 48 m hexes laid over Central
// Park, New York (as the demo's other tracks are), never anywhere the family
// walks; the family view's trip "today" is on Boston Common.
//
// This week: Sam ran a loop round the reservoir and took everything inside
// it, some of it Alex's; Alex walked down the west side; Robin rode the north
// end; and a few hexes went to Kit with no outing to explain them. Last week
// was Alex's; the week before that was quiet. The weekly board's figures for
// this week and last are COUNTED from the same hexes the map draws, so the
// screenshot of the board and the one of the map agree.

extension SRDemoFixtures {
    static func landgrabRoute(method: String, parts: [String], query: [String: String], clock: DemoClock) -> String? {
        guard method == "GET" else { return nil }
        // parts: ["api", "native", "family", "landgrab", ...]
        switch parts.count {
        case 4:
            return landgrabWeeks(clock, count: min(12, max(1, Int(query["weeks"] ?? "") ?? 6)))
        case 5 where parts[4] == "explored":
            return LandgrabDemo.explored(clock)
        case 5 where parts[4] == "changes":
            let mondays = LandgrabDemo.mondays(clock.now, count: 12)
            guard let week = query["week"], let index = mondays.firstIndex(of: week) else {
                return nil
            }
            return LandgrabDemo.changes(variant: index, week: week, clock: clock).json
        default:
            return nil
        }
    }

    static func landgrabWeeks(_ clock: DemoClock, count: Int) -> String {
        let mondays = LandgrabDemo.mondays(clock.now, count: count)
        let weeks = mondays.enumerated().map { index, monday -> String in
            let people = LandgrabDemo.board(variant: index, week: monday, clock: clock)
                .map { p in
                    "{\"id\":\(s(p.id)),\"name\":\(s(p.name)),\"me\":\(b(p.me)),\"won\":\(p.won),\"taken\":\(p.taken),"
                        + "\"lost\":\(p.lost),\"net\":\(p.won - p.lost),\"held\":\(p.held),\"rank\":0,\"colour\":\(s(p.colour))}"
                }
            return "{\"start\":\(s(monday)),\"end\":\(s(LandgrabDemo.sunday(monday))),\"current\":\(b(index == 0)),"
                + "\"people\":\(list(people))}"
        }
        return "{\"updatedAt\":\(s(clock.iso(minutesAgo: 12))),\"weeks\":\(list(weeks))}"
    }
}

/// The demo's made-up ground.
enum LandgrabDemo {
    struct Person {
        let id: String
        let name: String
        let colour: String
        var me = false
    }

    static let alex = Person(id: "f_alex", name: "Alex", colour: "#c2410c", me: true)
    static let sam = Person(id: "f_sam", name: "Sam", colour: "#1d4ed8")
    static let robin = Person(id: "f_robin", name: "Robin", colour: "#15803d")
    static let kit = Person(id: "f_kit", name: "Kit", colour: "#fde047")
    static let people = [alex, sam, robin, kit]

    /// Somewhere near the middle of Central Park.
    static let origin = (lat: 40.7830, lon: -73.9650)
    static let metresPerLat = 111_132.0
    static var metresPerLon: Double { 111_320.0 * cos(origin.lat * Double.pi / 180) }
    /// Centre to corner, for a hex 48 m across its flats.
    static let hexRadius = 48.0 / sqrt(3.0)

    // MARK: Weeks

    /// This week's Monday and the ones before it, newest first.
    static func mondays(_ now: Date, count: Int) -> [String] {
        guard let monday = Landgrab.day(Landgrab.monday(of: now)) else { return [] }
        return (0..<count).compactMap { back in
            Landgrab.calendar.date(byAdding: .day, value: -7 * back, to: monday).map(Landgrab.ymd)
        }
    }

    static func sunday(_ monday: String) -> String {
        guard let day = Landgrab.day(monday), let end = Landgrab.calendar.date(byAdding: .day, value: 6, to: day) else { return monday }
        return Landgrab.ymd(end)
    }

    struct Row {
        let id: String
        let name: String
        let me: Bool
        let colour: String
        let won: Int
        let taken: Int
        let lost: Int
        let held: Int
    }

    /// The weekly board. This week and last are counted from the map's hexes.
    static func board(variant: Int, week: String, clock: SRDemoFixtures.DemoClock) -> [Row] {
        let base = ["f_alex": 412, "f_sam": 377, "f_robin": 240, "f_kit": 96]
        if variant <= 1 {
            let hexes = changes(variant: variant, week: week, clock: clock).hexes
            return people.map { p in
                let won = hexes.filter { $0.owner == p.id }
                let taken = won.filter { $0.previous != nil }.count
                let lost = hexes.filter { $0.previous == p.id }.count
                return Row(id: p.id, name: p.name, me: p.me, colour: p.colour, won: won.count, taken: taken,
                           lost: lost, held: (base[p.id] ?? 0) + won.count - lost)
            }
        }
        // Older weeks: small, settled figures; the third week back is quiet.
        let quiet = variant == 2
        let pattern: [String: (Int, Int, Int)] = [
            "f_alex": (14 + variant, 6, 3), "f_sam": (9, 4, 5 + variant % 3),
            "f_robin": (6 - variant % 2, 2, 4), "f_kit": (variant % 4, 0, 1),
        ]
        return people.map { p in
            let (won, taken, lost) = quiet ? (0, 0, 0) : (pattern[p.id] ?? (0, 0, 0))
            return Row(id: p.id, name: p.name, me: p.me, colour: p.colour, won: won, taken: taken,
                       lost: lost, held: base[p.id] ?? 0)
        }
    }

    // MARK: Changes

    struct Hex {
        let id: Int
        let polygon: [(Double, Double)]
        let owner: String
        let previous: String?
    }

    struct Change {
        let id: String
        let person: String
        let minutesAgo: Double
        let type: String?
        let kind: String
        let distanceM: Double?
        let durationS: Double?
        let loop: Bool
        let trace: [(Double, Double)]
        var hexIds: [Int] = []
        var attributed: Bool { !trace.isEmpty || type != nil }
    }

    struct Week {
        let week: String
        let current: Bool
        let hexes: [Hex]
        let changes: [Change]
        let json: String
    }

    /// One week of changes. Variant 0 is this week, 1 last week, the rest are
    /// quiet.
    static func changes(variant: Int, week: String, clock: SRDemoFixtures.DemoClock) -> Week {
        let (hexes, plans) = layout(variant: min(variant, 2))
        return Week(week: week, current: variant == 0, hexes: hexes, changes: plans,
                    json: json(week: week, current: variant == 0, hexes: hexes, changes: plans, clock: clock))
    }

    /// The ground never moves between requests, only the clock does — so it
    /// is laid once per variant and kept. The demo's URLProtocol answers on
    /// background threads, hence the lock.
    private static var laid: [Int: ([Hex], [Change])] = [:]
    private static let lock = NSLock()

    private static func layout(variant: Int) -> ([Hex], [Change]) {
        lock.lock()
        defer { lock.unlock() }
        if let done = laid[variant] { return done }
        let done = lay(variant: variant)
        laid[variant] = done
        return done
    }

    private struct Claim {
        let change: Int
        /// A cheap box test first: the grid is thousands of hexes, and most
        /// are nowhere near anything.
        let box: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)
        let test: (Double, Double) -> Bool
        let previous: (Int) -> String?

        func claims(_ lat: Double, _ lon: Double) -> Bool {
            lat >= box.minLat && lat <= box.maxLat && lon >= box.minLon && lon <= box.maxLon && test(lat, lon)
        }
    }

    /// The box round `points`, grown by `metres`.
    private static func box(_ points: [(Double, Double)], metres: Double) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        let lats = points.map(\.0), lons = points.map(\.1)
        let dLat = metres / metresPerLat, dLon = metres / metresPerLon
        return ((lats.min() ?? 0) - dLat, (lats.max() ?? 0) + dLat, (lons.min() ?? 0) - dLon, (lons.max() ?? 0) + dLon)
    }

    private static func lay(variant: Int) -> ([Hex], [Change]) {
        var plans: [Change] = []
        var claims: [Claim] = []
        switch variant {
        case 0:
            let centre = (40.7853, -73.9625)
            let loop = ellipse(centre: centre, latRadius: 0.0026, lonRadius: 0.0032, points: 60)
            plans.append(Change(id: "workout:demo-sam-run", person: sam.id, minutesAgo: 95, type: "run", kind: "workout",
                                distanceM: 2_480, durationS: 840, loop: true, trace: loop))
            claims.append(Claim(change: 0, box: box(loop, metres: 10),
                                test: { inside($0, $1, ellipseCentre: centre, latRadius: 0.0026, lonRadius: 0.0032) },
                                previous: { id in [alex.id, nil, robin.id][id % 3] }))
            let walk = line(from: (40.7738, -73.9745), to: (40.7808, -73.9693), points: 34, wobble: 0.00018)
            plans.append(Change(id: "workout:demo-alex-walk", person: alex.id, minutesAgo: 320, type: "walk", kind: "workout",
                                distanceM: 3_410, durationS: 2_520, loop: false, trace: walk))
            claims.append(Claim(change: 1, box: box(walk, metres: 40), test: { near($0, $1, walk, within: 34) },
                                previous: { id in id % 2 == 0 ? sam.id : nil }))
            let ride = line(from: (40.7905, -73.9585), to: (40.7968, -73.9528), points: 30, wobble: 0.00022)
            plans.append(Change(id: "trail:demo-robin-ride", person: robin.id, minutesAgo: 1_480, type: "ride", kind: "trail",
                                distanceM: 6_120, durationS: 1_380, loop: false, trace: ride))
            claims.append(Claim(change: 2, box: box(ride, metres: 40), test: { near($0, $1, ride, within: 34) },
                                previous: { id in id % 4 == 0 ? kit.id : nil }))
            let spot = [(40.7768, -73.9688)]
            plans.append(Change(id: "unattributed:demo-kit", person: kit.id, minutesAgo: 2_100, type: nil, kind: "workout",
                                distanceM: nil, durationS: nil, loop: false, trace: []))
            claims.append(Claim(change: 3, box: box(spot, metres: 75), test: { near($0, $1, spot, within: 70) },
                                previous: { _ in sam.id }))
        case 1:
            let walk = line(from: (40.7790, -73.9700), to: (40.7870, -73.9660), points: 30, wobble: 0.00015)
            plans.append(Change(id: "workout:demo-alex-walk-last", person: alex.id, minutesAgo: 8_000, type: "walk", kind: "workout",
                                distanceM: 2_950, durationS: 2_160, loop: false, trace: walk))
            claims.append(Claim(change: 0, box: box(walk, metres: 40), test: { near($0, $1, walk, within: 34) },
                                previous: { id in id % 3 == 0 ? sam.id : nil }))
        default:
            break
        }

        // Lay the grid and hand each hex to the first change that claims it.
        var hexes: [Hex] = []
        if !claims.isEmpty {
            let rows = 70, cols = 60
            for row in -rows...rows {
                for col in -cols...cols {
                    let centre = hexCentre(q: col, r: row)
                    guard let claim = claims.first(where: { $0.claims(centre.0, centre.1) }) else { continue }
                    let id = hexes.count
                    let owner = plans[claim.change].person
                    // A previous owner of themselves is no change at all.
                    let previous = claim.previous(id).flatMap { $0 == owner ? nil : $0 }
                    hexes.append(Hex(id: id, polygon: hexCorners(centre), owner: owner, previous: previous))
                    plans[claim.change].hexIds.append(id)
                }
            }
        }
        return (hexes, plans)
    }

    private static func json(week: String, current: Bool, hexes: [Hex], changes: [Change], clock: SRDemoFixtures.DemoClock) -> String {
        typealias F = SRDemoFixtures
        let byId = Dictionary(uniqueKeysWithValues: hexes.map { ($0.id, $0) })
        let pair = { (p: (Double, Double)) in "[\(F.coord(p.0)),\(F.coord(p.1))]" }
        let hexJSON = hexes.map { hex in
            "{\"id\":\(hex.id),\"polygon\":[\(hex.polygon.map(pair).joined(separator: ","))],\"owner\":\(F.s(hex.owner)),\"previous\":\(F.s(hex.previous))}"
        }
        let changeJSON = changes.filter { !$0.hexIds.isEmpty }.sorted { $0.minutesAgo < $1.minutesAgo }.map { change -> String in
            var from: [String?: Int] = [:]
            for id in change.hexIds { from[byId[id]?.previous, default: 0] += 1 }
            let fromJSON = from.sorted { $0.value > $1.value }.map { "{\"id\":\(F.s($0.key)),\"hexes\":\($0.value)}" }
            let taken = change.hexIds.filter { byId[$0]?.previous != nil }.count
            let activity: String
            if change.attributed {
                let started = clock.iso(minutesAgo: change.minutesAgo + (change.durationS ?? 0) / 60)
                activity = "{\"kind\":\(F.s(change.kind)),\"type\":\(F.s(change.type)),\"startedAt\":\(F.s(started)),"
                    + "\"endedAt\":\(F.s(clock.iso(minutesAgo: change.minutesAgo))),\"distanceM\":\(F.n(change.distanceM)),"
                    + "\"durationS\":\(F.n(change.durationS)),\"loop\":\(F.b(change.loop)),"
                    + "\"trace\":[\(change.trace.map(pair).joined(separator: ","))]}"
            } else {
                activity = "null"
            }
            return "{\"id\":\(F.s(change.id)),\"personId\":\(F.s(change.person)),\"at\":\(F.s(clock.iso(minutesAgo: change.minutesAgo))),"
                + "\"won\":\(change.hexIds.count),\"taken\":\(taken),\"from\":[\(fromJSON.joined(separator: ","))],"
                + "\"hexIds\":[\(change.hexIds.map(String.init).joined(separator: ","))],\"activity\":\(activity)}"
        }
        let corners = hexes.flatMap(\.polygon)
        let bounds: String
        if let minLat = corners.map(\.0).min(), let maxLat = corners.map(\.0).max(),
           let minLon = corners.map(\.1).min(), let maxLon = corners.map(\.1).max() {
            bounds = "{\"minLat\":\(F.coord(minLat)),\"minLon\":\(F.coord(minLon)),\"maxLat\":\(F.coord(maxLat)),\"maxLon\":\(F.coord(maxLon))}"
        } else {
            bounds = "null"
        }
        // Where the map opens, as the site sends it: the middle of the park's
        // ground and a radius that holds it (the real one is two miles).
        let focus: String
        if let minLat = corners.map(\.0).min(), let maxLat = corners.map(\.0).max(),
           let minLon = corners.map(\.1).min(), let maxLon = corners.map(\.1).max() {
            focus = "{\"lat\":\(F.coord((minLat + maxLat) / 2)),\"lon\":\(F.coord((minLon + maxLon) / 2)),\"radiusM\":1600}"
        } else {
            focus = "null"
        }
        let peopleJSON = people.map { "{\"id\":\(F.s($0.id)),\"name\":\(F.s($0.name)),\"colour\":\(F.s($0.colour))}" }
        return "{\"week\":{\"start\":\(F.s(week)),\"end\":\(F.s(sunday(week))),\"current\":\(F.b(current))},"
            + "\"bounds\":\(bounds),\"focus\":\(focus),\"people\":[\(peopleJSON.joined(separator: ","))],"
            + "\"hexes\":[\(hexJSON.joined(separator: ","))],\"changes\":[\(changeJSON.joined(separator: ","))],\"truncated\":false}"
    }

    // MARK: Explored (the family view)

    /// The family's ground, all time: the park and the streets round it at
    /// home, and a trip to Boston Common whose newest ground is today's — so
    /// the map opens away from home, as it does on a real trip. The figures
    /// are made up to read well together, not counted from the shapes.
    static func explored(_ clock: SRDemoFixtures.DemoClock) -> String {
        typealias F = SRDemoFixtures
        let today = Landgrab.ymd(clock.now)
        let yesterday = Landgrab.ymd(clock.date(minutesAgo: 24 * 60))
        let monday = Landgrab.monday(of: clock.now)
        let home: [[(Double, Double)]] = [
            ellipse(centre: (40.7853, -73.9625), latRadius: 0.0034, lonRadius: 0.0040, points: 48),
            ribbon(line(from: (40.7738, -73.9745), to: (40.7808, -73.9693), points: 20, wobble: 0.00018), widthM: 130),
            ribbon(line(from: (40.7905, -73.9585), to: (40.7968, -73.9528), points: 20, wobble: 0.00022), widthM: 130),
            ribbon(line(from: (40.7680, -73.9810), to: (40.7760, -73.9590), points: 24, wobble: 0.0003), widthM: 160),
        ]
        let awayToday: [[(Double, Double)]] = [
            ellipse(centre: (42.3550, -71.0656), latRadius: 0.0018, lonRadius: 0.0024, points: 32),
            ribbon(line(from: (42.3520, -71.0710), to: (42.3590, -71.0600), points: 20, wobble: 0.0002), widthM: 140),
        ]
        let awayBefore: [[(Double, Double)]] = [
            ribbon(line(from: (42.3600, -71.0590), to: (42.3650, -71.0540), points: 14, wobble: 0.0002), widthM: 140),
        ]
        func polygons(_ shapes: [[(Double, Double)]]) -> String {
            let items = shapes.map { shape in
                let ring = LandgrabPolyline.encode(shape.map { LandgrabPoint(lat: $0.0, lon: $0.1) })
                return "{\"outer\":\(F.s(ring)),\"holes\":[]}"
            }
            return "[\(items.joined(separator: ","))]"
        }
        func figure(_ cells: Int, _ km2: Double) -> String { "{\"cells\":\(cells),\"km2\":\(F.n(km2))}" }
        let weekCells = monday == today ? 410 : 590
        let weekKm2 = monday == today ? 1.31 : 1.88
        let parts: [(Person, Int, Double, Int, Int)] = [
            (alex, 5_100, 11.9, 3_900, 260), (sam, 3_480, 8.1, 2_310, 150), (robin, 1_890, 4.4, 1_190, 0), (kit, 515, 1.2, 460, 0),
        ]
        let people = parts.map { p, cells, km2, firsts, todayCells in
            "{\"id\":\(F.s(p.id)),\"name\":\(F.s(p.name)),\"me\":\(F.b(p.me)),\"colour\":\(F.s(p.colour)),"
                + "\"cells\":\(cells),\"km2\":\(F.n(km2)),\"firsts\":\(firsts),\"today\":\(todayCells)}"
        }
        let bounds = { (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) in
            "{\"minLat\":\(F.coord(minLat)),\"minLon\":\(F.coord(minLon)),\"maxLat\":\(F.coord(maxLat)),\"maxLon\":\(F.coord(maxLon))}"
        }
        let places = [
            "{\"lat\":40.781,\"lon\":-73.967,\"cells\":7290,\"km2\":16.5,\"bounds\":\(bounds(40.7660, -73.9830, 40.7990, -73.9500)),"
                + "\"first\":\"2025-01-04\",\"last\":\(F.s(Landgrab.ymd(clock.date(minutesAgo: 9 * 24 * 60)))),\"home\":true}",
            "{\"lat\":42.357,\"lon\":-71.064,\"cells\":590,\"km2\":1.88,\"bounds\":\(bounds(42.3500, -71.0730, 42.3670, -71.0520)),"
                + "\"first\":\(F.s(yesterday)),\"last\":\(F.s(today)),\"home\":false}",
        ]
        let body: [String] = [
            "{\"family\":\"The family\",\"updatedAt\":\(F.s(clock.iso(minutesAgo: 12))),\"since\":\"2025-01-04\",",
            "\"today\":\(F.s(today)),\"weekStart\":\(F.s(monday)),",
            "\"total\":\(figure(7_910, 18.4)),\"todayNew\":\(figure(410, 1.31)),\"weekNew\":\(figure(weekCells, weekKm2)),",
            "\"people\":[\(people.joined(separator: ","))],\"places\":[\(places.joined(separator: ","))],",
            "\"otherPlaces\":{\"count\":2,\"cells\":30,\"km2\":0.07},",
            "\"shape\":{\"zoom\":19,\"vertices\":0,\"truncated\":false,\"polygons\":\(polygons(home + awayToday + awayBefore))},",
            "\"fresh\":{\"day\":\(F.s(today)),\"cells\":410,\"km2\":1.31,",
            "\"shape\":{\"zoom\":19,\"vertices\":0,\"truncated\":false,\"polygons\":\(polygons(awayToday))}},",
            "\"focus\":{\"lat\":40.78530,\"lon\":-73.96250,\"radiusM\":1600}}",
        ]
        return body.joined()
    }

    /// A path drawn `widthM` wide: one side out, the other back.
    static func ribbon(_ path: [(Double, Double)], widthM: Double) -> [(Double, Double)] {
        guard path.count > 1 else { return path }
        let half = widthM / 2
        var left: [(Double, Double)] = []
        var right: [(Double, Double)] = []
        for (i, p) in path.enumerated() {
            let a = path[max(0, i - 1)], b = path[min(path.count - 1, i + 1)]
            let dx = (b.1 - a.1) * metresPerLon, dy = (b.0 - a.0) * metresPerLat
            let length = max(1e-9, hypot(dx, dy))
            let nx = -dy / length * half, ny = dx / length * half
            left.append((p.0 + ny / metresPerLat, p.1 + nx / metresPerLon))
            right.append((p.0 - ny / metresPerLat, p.1 - nx / metresPerLon))
        }
        return left + right.reversed()
    }

    // MARK: Geometry (flat-earth near the origin; it is a park, not a continent)

    /// Pointy-top axial hex → its centre.
    static func hexCentre(q: Int, r: Int) -> (Double, Double) {
        let x = hexRadius * sqrt(3.0) * (Double(q) + Double(r) / 2)
        let y = hexRadius * 1.5 * Double(r)
        return (origin.lat + y / metresPerLat, origin.lon + x / metresPerLon)
    }

    static func hexCorners(_ centre: (Double, Double)) -> [(Double, Double)] {
        (0..<6).map { i in
            let angle = (60.0 * Double(i) + 30.0) * Double.pi / 180
            return (centre.0 + hexRadius * sin(angle) / metresPerLat, centre.1 + hexRadius * cos(angle) / metresPerLon)
        }
    }

    static func ellipse(centre: (Double, Double), latRadius: Double, lonRadius: Double, points: Int) -> [(Double, Double)] {
        (0...points).map { i in
            let t = Double(i) / Double(points) * 2 * Double.pi
            let wobble = 1 + 0.04 * sin(t * 5)
            return (centre.0 + latRadius * cos(t) * wobble, centre.1 + lonRadius * sin(t) * wobble)
        }
    }

    static func line(from a: (Double, Double), to b: (Double, Double), points: Int, wobble: Double) -> [(Double, Double)] {
        (0...points).map { i in
            let t = Double(i) / Double(points)
            let bend = wobble * sin(t * Double.pi * 3)
            return (a.0 + (b.0 - a.0) * t + bend, a.1 + (b.1 - a.1) * t - bend)
        }
    }

    static func inside(_ lat: Double, _ lon: Double, ellipseCentre c: (Double, Double), latRadius: Double, lonRadius: Double) -> Bool {
        let dy = (lat - c.0) / latRadius, dx = (lon - c.1) / lonRadius
        return dx * dx + dy * dy <= 1
    }

    /// Within `within` metres of the polyline.
    static func near(_ lat: Double, _ lon: Double, _ path: [(Double, Double)], within: Double) -> Bool {
        func metres(_ p: (Double, Double)) -> (Double, Double) {
            ((p.1 - origin.lon) * metresPerLon, (p.0 - origin.lat) * metresPerLat)
        }
        let p = metres((lat, lon))
        guard let first = path.first else { return false }
        if path.count == 1 {
            let a = metres(first)
            return hypot(p.0 - a.0, p.1 - a.1) <= within
        }
        for (a, b) in zip(path, path.dropFirst()) {
            let a = metres(a), b = metres(b)
            let dx = b.0 - a.0, dy = b.1 - a.1
            let length = dx * dx + dy * dy
            let t = length == 0 ? 0 : max(0, min(1, ((p.0 - a.0) * dx + (p.1 - a.1) * dy) / length))
            if hypot(p.0 - (a.0 + t * dx), p.1 - (a.1 + t * dy)) <= within { return true }
        }
        return false
    }
}

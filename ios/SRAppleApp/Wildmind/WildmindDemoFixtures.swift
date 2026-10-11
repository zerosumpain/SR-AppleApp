import Foundation

// MARK: - Demo Wildmind
//
// `-SRDemo` (and the App Review demo) answers `GET /api/native/wildmind` with
// a small valley made up here, never a recording: the repository is public,
// and a game with nothing in it is still a game worth showing. It is drawn
// by arithmetic rather than stored, so the fixture is a few dozen lines and
// the same on every run — a sea along the west, a lake in the north with a
// stream down to the shore, a marsh under the lake, two woods, fells in the
// north-east, and the explored patch an irregular blob round the camp.
//
// JKai and Wren are the names the public site uses for the two people; the
// places are invented. Day five of the third life, spring, a cloudy
// afternoon: JKai walking up to the lake from the camp, Wren at work by the
// hearth. `?have=` with the current version is answered without the grid, as
// the site does.

enum WildmindDemo {
    static let w = 46
    static let h = 40
    static let originX = -20
    static let originZ = -16
    static let terrains = [
        "deep_sea", "shallow_sea", "deep_fresh", "shallow_fresh", "sand", "grass", "forest", "marsh",
        "rock", "path", "farmland", "snow", "tundra", "volcanic", "jungle",
    ]

    /// The planes, generated once.
    static let planes: (t: [UInt8], height: [UInt8]) = generate()

    static var explored: Int { planes.t.reduce(0) { $0 + ($1 == 0 ? 0 : 1) } }
    static var version: String { "demo.\(explored).0" }

    /// A terrain's byte in `t`: its index in `terrains`, plus one.
    private static func code(_ name: String) -> UInt8 {
        UInt8((terrains.firstIndex(of: name) ?? 5) + 1)
    }

    /// World tiles for a point given in cells, so the people and places
    /// below can be written where they sit on the drawing.
    static func world(_ cx: Double, _ cy: Double) -> (x: Double, z: Double) {
        (Double(originX) + cx - 0.5, Double(originZ) + cy - 0.5)
    }

    private static func generate() -> (t: [UInt8], height: [UInt8]) {
        var t = [UInt8](repeating: 0, count: w * h)
        var height = [UInt8](repeating: 0, count: w * h)
        for j in 0..<h {
            for i in 0..<w {
                let x = Double(i) + 0.5
                let y = Double(j) + 0.5
                // The explored patch: an ellipse round the camp with a wavy
                // edge, and a reach west to the shore.
                let ex = (x - 23) / 21.5
                let ey = (y - 20) / 18.5
                let wobble = 0.12 * sin(x * 0.55) + 0.1 * cos(y * 0.7)
                guard ex * ex + ey * ey < 1 + wobble else { continue }

                // Ground.
                let coast = 7 + 2.4 * sin(y * 0.28) + 1.2 * cos(y * 0.61)
                let lake = pow((x - 30) / 5.2, 2) + pow((y - 10) / 3.6, 2)
                let stream = abs(y - (13 + 4 * sin((x - 8) * 0.17))) < 0.75 && x > coast && x < 26
                let woodA = pow((x - 15) / 7, 2) + pow((y - 29) / 5.5, 2) + 0.15 * sin(x * 1.3 + y)
                let woodB = pow((x - 37) / 5, 2) + pow((y - 29) / 6, 2) + 0.15 * cos(x + y * 1.1)
                let fells = (x - 41) * (x - 41) / 60 + (y - 5) * (y - 5) / 40
                let path = abs(y - (19 - (x - 21) * 0.62)) < 0.6 && x > 21 && x < 27.5

                var name: String
                var lift: Double
                if x < coast - 2.2 {
                    name = "deep_sea"; lift = -1.6
                } else if x < coast {
                    name = "shallow_sea"; lift = -0.6
                } else if x < coast + 1.6 {
                    name = "sand"; lift = 0.2
                } else if lake < 0.55 {
                    name = "deep_fresh"; lift = -0.8
                } else if lake < 1 {
                    name = "shallow_fresh"; lift = 0.1
                } else if lake < 2.1 && y > 10 {
                    name = "marsh"; lift = 0.25
                } else if stream {
                    name = "shallow_fresh"; lift = 0.15
                } else if path {
                    name = "path"; lift = 0.6
                } else if fells < 1 {
                    name = fells < 0.35 ? "snow" : "rock"; lift = 0
                } else if woodA < 1 || woodB < 1 {
                    name = "forest"; lift = 0
                } else {
                    name = "grass"; lift = 0
                }
                // Height: a gentle rise from the shore, the fells, a knoll in
                // the first wood.
                var level = 0.3 + 0.045 * (x - coast)
                level += 4.4 * exp(-((x - 42) * (x - 42) + (y - 4) * (y - 4)) / 45)
                level += 1.3 * exp(-((x - 15) * (x - 15) + (y - 30) * (y - 30)) / 30)
                level += 0.2 * sin(x * 0.9) * cos(y * 0.8)
                if lift != 0 { level = lift }
                let k = j * w + i
                t[k] = code(name)
                height[k] = UInt8(max(1, min(255, ((level + 2) * 10).rounded())))
            }
        }
        return (t, height)
    }

    // MARK: The answer

    /// The JSON for `GET api/native/wildmind`, with the terrain unless the
    /// caller already holds this version.
    static func answer(have: String?) -> String {
        let version = self.version
        let terrain = have == version ? "null" : terrainJSON()
        return """
        {"state":"live","ageSeconds":2,"snapshot":\(snapshotJSON(version: version)),"terrain":\(terrain)}
        """
    }

    private static func q(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func n(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func point(_ cx: Double, _ cy: Double) -> String {
        let p = world(cx, cy)
        return "[\(n(p.x)),\(n(p.z))]"
    }

    /// The four named places, in cells.
    static let places: [(name: String, kind: String, cx: Double, cy: Double)] = [
        ("Heron Lake", "l", 30, 10),
        ("Raven Fells", "l", 37, 7),
        ("Tusker Wood", "h", 15, 29),
        ("Long Strand", "l", 9, 25),
    ]

    private static func terrainJSON() -> String {
        let regions = places.map { place -> String in
            let p = world(place.cx, place.cy)
            return #"{"n":\#(q(place.name)),"k":"\#(place.kind)","x":\#(n(p.x.rounded())),"z":\#(n(p.z.rounded()))}"#
        }
        return """
        {"origin":[\(originX),\(originZ)],"step":1,"w":\(w),"h":\(h),\
        "terrains":[\(terrains.map(q).joined(separator: ","))],\
        "t":"\(Data(planes.t).base64EncodedString())",\
        "height":"\(Data(planes.height).base64EncodedString())",\
        "regions":[\(regions.joined(separator: ","))]}
        """
    }

    private static func snapshotJSON(version: String) -> String {
        let jkai = world(25.6, 15.4)
        let wren = world(22.4, 20.6)
        let trail = [(20.6, 19.8), (21.4, 19.2), (22.3, 18.5), (23.2, 17.6), (24.1, 16.8), (24.9, 16.0)]
            .map { point($0.0, $0.1) }.joined(separator: ",")
        let wrenTrail = [(21.2, 18.4), (21.6, 19.3), (22.0, 20.1)].map { point($0.0, $0.1) }.joined(separator: ",")
        return """
        {"v":1,"status":"running","terrainVersion":\(q(version)),\
        "time":{"day":5,"season":"spring","dayOfSeason":5,"hour":15.5,"daylight":0.86,"weather":"cloudy","tempC":11},\
        "people":[\
        {"id":"main","name":"JKai","x":\(n(jkai.x)),"z":\(n(jkai.z)),"heading":0.7,"activity":"walking","doing":"walking",\
        "alive":true,"thinking":false,"near":"Heron Lake","trail":[\(trail)],"morale":"good"},\
        {"id":"companion","name":"Wren","x":\(n(wren.x)),"z":\(n(wren.z)),"heading":-2.1,"activity":"working","doing":"at work",\
        "alive":true,"thinking":true,"near":null,"trail":[\(wrenTrail)],"morale":"getting-by"}],\
        "species":["rabbit","deer","boar","duck","wolf"],\
        "animals":[[1,\(xz(27.5, 25.2))],[1,\(xz(28.6, 26.1))],[0,\(xz(13.6, 12.8))],[0,\(xz(15.0, 12.2))],\
        [2,\(xz(36.4, 31.2))],[3,\(xz(29.2, 9.4))],[3,\(xz(31.0, 10.6))],[4,\(xz(12.0, 31.0))]],\
        "structures":[[\(xz(21.0, 19.0)),1,0,"shelter"],[\(xz(23.0, 19.6)),1,0,"store"],\
        [\(xz(21.9, 17.7)),1,1,"fire"],[\(xz(19.4, 20.8)),0,0,"pen"]],\
        "fires":[[\(xz(21.9, 17.7))]],\
        "stats":{"generation":3,"earlierLives":[{"n":2,"days":2.9,"cause":"starvation"},{"n":1,"days":32.3,"cause":"cold"}],\
        "invented":2,"latest":[{"name":"Reed basket","kind":"container","day":4,"by":"companion"},\
        {"name":"Fire drill","kind":"tool","day":2,"by":"main"}],\
        "refused":3,"placesFound":\(places.count),"exploredTiles":\(explored),\
        "built":{"shelter":1,"store":1,"fire":1,"pen":0,"other":0},"tamed":0,\
        "milestones":{"met":true,"partners":false,"shelter":true,"fire":true,"store":true,"pen":false},\
        "choices":{"thought":41,"habit":63},\
        "models":{"mind":"claude-haiku-5-5","designer":"claude-sonnet-5-5"}}}
        """
    }

    /// `x,z` in world tiles for a point in cells, for a tuple row.
    private static func xz(_ cx: Double, _ cy: Double) -> String {
        let p = world(cx, cy)
        return "\(n(p.x)),\(n(p.z))"
    }
}

extension SRDemoFixtures {
    /// `GET api/native/wildmind`, and the owner lane under it — talk,
    /// chronicle, inventions, whispers and `POST whisper` — from
    /// `WildmindDemoLane`. Anything else under it is a 404.
    static func wildmindRoute(method: String, parts: [String], query: [String: String], body: Data?, now: Date) -> String? {
        if parts.count == 3 {
            guard method == "GET" else { return nil }
            return WildmindDemo.answer(have: query["have"])
        }
        guard parts.count == 4 else { return nil }
        return WildmindDemoLane.shared.route(method: method, route: parts[3], query: query, body: body, now: now)
    }
}

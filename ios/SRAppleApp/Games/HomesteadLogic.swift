import Foundation

// Homestead's wire pieces and the geometry the phone needs to draw and tap the
// island — see docs/specs/2026-10-22-family-games-homestead.md.
//
// The server owns every rule. The phone never decides whether a spot is legal:
// it draws what `legal` lists and maps a tap back to one of those ids. What it
// does work out itself is geometry — where a hex, a corner or a side sits on
// screen — from the one coordinate scheme both sides share:
//
// - hexes are axial `(q, r)`, pointy-top, `r` growing downward: `"q,r"`;
// - every corner is the top (`N`) or bottom (`S`) corner of exactly one hex:
//   `"q,r,N"` / `"q,r,S"`;
// - every side is the `NE`, `NW` or `W` side of exactly one hex: `"q,r,NE"`.
//
// A corner or side id may name a SEA hex (a coastal corner is owned by the hex
// beyond the shore), so a spot is checked against the board's own corner and
// side sets, never against "its hex exists".
//
// Foundation only, on purpose: this file has no SwiftUI, so its geometry can be
// compiled and exercised anywhere.

// MARK: - Names

/// The five resources, always in this order.
enum HomesteadResource: String, CaseIterable, Identifiable, Hashable, Codable {
    case timber, clay, wool, grain, stone

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// The SF Symbol drawn beside it, so colour is never the only cue.
    var symbol: String {
        switch self {
        case .timber: return "tree.fill"
        case .clay: return "square.stack.3d.up.fill"
        case .wool: return "cloud.fill"
        case .grain: return "laurel.leading"
        case .stone: return "mountain.2.fill"
        }
    }
    /// The tile that makes it.
    var tile: HomesteadTile {
        switch self {
        case .timber: return .woods
        case .clay: return .claypit
        case .wool: return .meadow
        case .grain: return .fields
        case .stone: return .quarry
        }
    }
}

/// What a hex is.
enum HomesteadTile: String, Equatable, Hashable {
    case woods, claypit, meadow, fields, quarry, dunes
    /// A tile this version of the app has not heard of: drawn as dunes.
    case unknown

    static func from(_ raw: String?) -> HomesteadTile {
        guard let raw else { return .unknown }
        return HomesteadTile(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .woods: return "woods"
        case .claypit: return "clay pit"
        case .meadow: return "meadow"
        case .fields: return "fields"
        case .quarry: return "quarry"
        case .dunes, .unknown: return "dunes"
        }
    }

    var resource: HomesteadResource? {
        switch self {
        case .woods: return .timber
        case .claypit: return .clay
        case .meadow: return .wool
        case .fields: return .grain
        case .quarry: return .stone
        case .dunes, .unknown: return nil
        }
    }

    var symbol: String { resource?.symbol ?? "sun.max.fill" }
}

/// What can be built.
enum HomesteadPiece: String, CaseIterable, Identifiable, Hashable {
    case road, cottage, town

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// The key of its price in `costs`.
    var costKey: String { rawValue }
    var points: Int {
        switch self {
        case .road: return 0
        case .cottage: return 1
        case .town: return 2
        }
    }
}

/// The almanac deck.
enum HomesteadCard: Hashable, Identifiable {
    case ranger, heirloom, pathfinders, harvest, market
    /// A card this version of the app does not know: listed, never playable here.
    case other(String)

    init(raw: String) {
        switch raw {
        case "ranger": self = .ranger
        case "heirloom": self = .heirloom
        case "pathfinders": self = .pathfinders
        case "harvest": self = .harvest
        case "market": self = .market
        default: self = .other(raw)
        }
    }

    var raw: String {
        switch self {
        case .ranger: return "ranger"
        case .heirloom: return "heirloom"
        case .pathfinders: return "pathfinders"
        case .harvest: return "harvest"
        case .market: return "market"
        case .other(let raw): return raw
        }
    }

    var id: String { raw }

    var title: String {
        switch self {
        case .ranger: return "Ranger"
        case .heirloom: return "Heirloom"
        case .pathfinders: return "Pathfinders"
        case .harvest: return "Harvest"
        case .market: return "Market day"
        case .other(let raw): return raw.capitalized
        }
    }

    /// What it does, in a sentence a child can read.
    var line: String {
        switch self {
        case .ranger: return "Move the fox and take a card from someone next to it."
        case .heirloom: return "Worth 1 point. Keep it secret: everyone sees it at the end."
        case .pathfinders: return "Build two roads for free."
        case .harvest: return "Take any two resources from the bank."
        case .market: return "Name a resource. Everyone else gives you all of theirs."
        case .other: return "This app does not know that card yet."
        }
    }

    var symbol: String {
        switch self {
        case .ranger: return "figure.hiking"
        case .heirloom: return "seal.fill"
        case .pathfinders: return "signpost.right.and.left.fill"
        case .harvest: return "basket.fill"
        case .market: return "storefront.fill"
        case .other: return "questionmark.square"
        }
    }
}

/// A seat's colour (by seat: red, blue, amber, green, purple), each with its
/// own shape mark for colour-blind players.
enum HomesteadColour: String, CaseIterable, Hashable {
    case red, blue, amber, green, purple

    var label: String { rawValue.capitalized }

    /// The mark drawn on a player's pieces and beside their name.
    var mark: HomesteadMark {
        switch self {
        case .red: return .circle
        case .blue: return .square
        case .amber: return .triangle
        case .green: return .diamond
        case .purple: return .cross
        }
    }
}

enum HomesteadMark: String, Hashable {
    case circle, square, triangle, diamond, cross

    var spoken: String { rawValue }
}

// MARK: - Coordinates

/// One hex, axial.
struct HexCoord: Hashable, Comparable {
    let q: Int
    let r: Int

    init(_ q: Int, _ r: Int) {
        self.q = q
        self.r = r
    }

    init?(id: String) {
        let parts = id.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let q = HomesteadIds.int(parts[0]), let r = HomesteadIds.int(parts[1]) else { return nil }
        self.q = q
        self.r = r
    }

    var id: String { "\(q),\(r)" }

    /// Axial distance from `0,0`.
    var ring: Int { (abs(q) + abs(r) + abs(q + r)) / 2 }

    /// E, W, NE, NW, SE, SW.
    var neighbours: [HexCoord] {
        [HexCoord(q + 1, r), HexCoord(q - 1, r), HexCoord(q + 1, r - 1),
         HexCoord(q, r - 1), HexCoord(q, r + 1), HexCoord(q - 1, r + 1)]
    }

    /// The six corners, clockwise from the top.
    var corners: [HomesteadVertex] {
        [HomesteadVertex(q, r, .n), HomesteadVertex(q + 1, r - 1, .s), HomesteadVertex(q, r + 1, .n),
         HomesteadVertex(q, r, .s), HomesteadVertex(q - 1, r + 1, .n), HomesteadVertex(q, r - 1, .s)]
    }

    /// The six sides, clockwise from the upper right.
    var sides: [HomesteadEdge] {
        [HomesteadEdge(q, r, .ne), HomesteadEdge(q + 1, r, .w), HomesteadEdge(q, r + 1, .nw),
         HomesteadEdge(q - 1, r + 1, .ne), HomesteadEdge(q, r, .w), HomesteadEdge(q, r, .nw)]
    }

    static func < (a: HexCoord, b: HexCoord) -> Bool { a.r != b.r ? a.r < b.r : a.q < b.q }
}

/// A corner: the top or bottom corner of hex `(q, r)`.
struct HomesteadVertex: Hashable {
    enum Dir: String { case n = "N", s = "S" }

    let q: Int
    let r: Int
    let dir: Dir

    init(_ q: Int, _ r: Int, _ dir: Dir) {
        self.q = q
        self.r = r
        self.dir = dir
    }

    init?(id: String) {
        let parts = id.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 3, let q = HomesteadIds.int(parts[0]), let r = HomesteadIds.int(parts[1]),
              let dir = Dir(rawValue: String(parts[2])) else { return nil }
        self.init(q, r, dir)
    }

    var id: String { "\(q),\(r),\(dir.rawValue)" }

    /// The three corners one side away.
    var neighbours: [HomesteadVertex] {
        switch dir {
        case .n: return [HomesteadVertex(q, r - 1, .s), HomesteadVertex(q + 1, r - 1, .s), HomesteadVertex(q + 1, r - 2, .s)]
        case .s: return [HomesteadVertex(q, r + 1, .n), HomesteadVertex(q - 1, r + 1, .n), HomesteadVertex(q - 1, r + 2, .n)]
        }
    }

    /// The three hexes that meet here (land or sea).
    var hexes: [HexCoord] {
        switch dir {
        case .n: return [HexCoord(q, r), HexCoord(q, r - 1), HexCoord(q + 1, r - 1)]
        case .s: return [HexCoord(q, r), HexCoord(q, r + 1), HexCoord(q - 1, r + 1)]
        }
    }

    /// The three sides that end here.
    var edges: [HomesteadEdge] {
        switch dir {
        case .n: return [HomesteadEdge(q, r, .ne), HomesteadEdge(q, r, .nw), HomesteadEdge(q + 1, r - 1, .w)]
        case .s: return [HomesteadEdge(q - 1, r + 1, .ne), HomesteadEdge(q, r + 1, .nw), HomesteadEdge(q, r + 1, .w)]
        }
    }
}

/// A side: the NE, NW or W side of hex `(q, r)`.
struct HomesteadEdge: Hashable {
    enum Dir: String { case ne = "NE", nw = "NW", w = "W" }

    let q: Int
    let r: Int
    let dir: Dir

    init(_ q: Int, _ r: Int, _ dir: Dir) {
        self.q = q
        self.r = r
        self.dir = dir
    }

    init?(id: String) {
        let parts = id.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 3, let q = HomesteadIds.int(parts[0]), let r = HomesteadIds.int(parts[1]),
              let dir = Dir(rawValue: String(parts[2])) else { return nil }
        self.init(q, r, dir)
    }

    var id: String { "\(q),\(r),\(dir.rawValue)" }

    /// Its two corners.
    var ends: (HomesteadVertex, HomesteadVertex) {
        switch dir {
        case .ne: return (HomesteadVertex(q, r, .n), HomesteadVertex(q + 1, r - 1, .s))
        case .nw: return (HomesteadVertex(q, r - 1, .s), HomesteadVertex(q, r, .n))
        case .w: return (HomesteadVertex(q - 1, r + 1, .n), HomesteadVertex(q, r - 1, .s))
        }
    }

    /// The two hexes either side of it (land or sea).
    var hexes: [HexCoord] {
        switch dir {
        case .ne: return [HexCoord(q, r), HexCoord(q + 1, r - 1)]
        case .nw: return [HexCoord(q, r), HexCoord(q, r - 1)]
        case .w: return [HexCoord(q, r), HexCoord(q - 1, r)]
        }
    }
}

enum HomesteadIds {
    /// Canonical base-10 integers only: no `+`, no spaces, no `-0`.
    static func int(_ part: Substring) -> Int? {
        let text = String(part)
        guard !text.isEmpty, text != "-0" else { return nil }
        var digits = Substring(text)
        if digits.first == "-" { digits = digits.dropFirst() }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        if digits.count > 1, digits.first == "0" { return nil }
        return Int(text)
    }
}

// MARK: - Pixels

/// Board space: `s` = a hex's circumradius, y down.
enum HomesteadPixels {
    static let root3 = 3.0.squareRoot()

    static func centre(_ hex: HexCoord, size s: Double) -> CGPoint {
        CGPoint(x: s * root3 * (Double(hex.q) + Double(hex.r) / 2), y: s * 1.5 * Double(hex.r))
    }

    static func point(_ v: HomesteadVertex, size s: Double) -> CGPoint {
        let c = centre(HexCoord(v.q, v.r), size: s)
        return CGPoint(x: c.x, y: c.y + (v.dir == .n ? -s : s))
    }

    static func midpoint(_ e: HomesteadEdge, size s: Double) -> CGPoint {
        let (a, b) = e.ends
        let pa = point(a, size: s)
        let pb = point(b, size: s)
        return CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
    }

    /// The six corners of a hex, clockwise from the top, for its outline.
    static func outline(_ hex: HexCoord, size s: Double) -> [CGPoint] {
        hex.corners.map { point($0, size: s) }
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - Island shapes

/// The two island sizes, as the server makes them. The app draws whatever
/// hexes the room sends; these are for tests and fixtures.
enum HomesteadIsland: String, CaseIterable {
    case standard, large

    var hexes: [HexCoord] {
        var out: [HexCoord] = []
        let reach = self == .standard ? 2 : 3
        for r in -reach...reach {
            for q in -reach...reach {
                let hex = HexCoord(q, r)
                guard hex.ring <= reach else { continue }
                if self == .large, Self.isCorner(hex) { continue }
                out.append(hex)
            }
        }
        return out
    }

    /// The six corner hexes of the distance-3 shape: a ±3 pair with a 0.
    private static func isCorner(_ hex: HexCoord) -> Bool {
        let cube = [hex.q, hex.r, -hex.q - hex.r]
        return hex.ring == 3 && cube.contains(0)
    }

    static func from(_ raw: String?) -> HomesteadIsland? {
        guard let raw else { return nil }
        return HomesteadIsland(rawValue: raw)
    }

    var label: String { self == .standard ? "Standard island" : "Large island" }
}

// MARK: - The board

struct HomesteadHex: Decodable, Equatable, Identifiable {
    let id: String
    let coord: HexCoord
    let tile: HomesteadTile
    /// The number token; nil on dunes.
    let token: Int?
    /// Chances in 36 of the token rolling.
    let pips: Int

    var resource: HomesteadResource? { tile.resource }
    /// A 6 or an 8: the busiest hexes, drawn bolder.
    var hot: Bool { token == 6 || token == 8 }

    init(coord: HexCoord, tile: HomesteadTile, token: Int?, pips: Int? = nil) {
        self.coord = coord
        self.id = coord.id
        self.tile = tile
        self.token = token
        self.pips = pips ?? HomesteadText.pips(token)
    }

    private enum CodingKeys: String, CodingKey { case id, q, r, kind, token, pips }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawId = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil
        if let q = (try? c.decodeIfPresent(Int.self, forKey: .q)) ?? nil,
           let r = (try? c.decodeIfPresent(Int.self, forKey: .r)) ?? nil {
            coord = HexCoord(q, r)
        } else if let rawId, let parsed = HexCoord(id: rawId) {
            coord = parsed
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "A hex needs q and r.")
        }
        id = coord.id
        tile = HomesteadTile.from((try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil)
        token = (try? c.decodeIfPresent(Int.self, forKey: .token)) ?? nil
        pips = (try? c.decodeIfPresent(Int.self, forKey: .pips)) ?? HomesteadText.pips(token)
    }

    /// "fields 8", "dunes".
    var spoken: String {
        guard let token, tile != .dunes, tile != .unknown else { return tile.label }
        return "\(tile.label) \(token)"
    }
}

struct HomesteadHarbour: Decodable, Equatable {
    let edge: String
    /// "any" or a resource.
    let kind: String
    let rate: Int

    var resource: HomesteadResource? { HomesteadResource(rawValue: kind) }
    /// "3:1", "2:1 wool".
    var label: String {
        if let resource { return "\(rate):1 \(resource.rawValue)" }
        return "\(rate):1"
    }

    init(edge: String, kind: String, rate: Int) {
        self.edge = edge
        self.kind = kind
        self.rate = rate
    }

    private enum CodingKeys: String, CodingKey { case edge, kind, rate }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        edge = try c.decode(String.self, forKey: .edge)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "any"
        rate = (try? c.decodeIfPresent(Int.self, forKey: .rate)) ?? (kind == "any" ? 3 : 2)
    }
}

/// The island as sent, with the corners and sides derived from its hexes.
struct HomesteadBoard: Decodable, Equatable {
    let hexes: [HomesteadHex]
    let harbours: [HomesteadHarbour]

    /// Every corner of a land hex, by id.
    let vertexIds: Set<String>
    /// Every side of a land hex, by id.
    let edgeIds: Set<String>
    /// Sides of exactly one land hex.
    let coastIds: Set<String>
    private let byId: [String: HomesteadHex]

    static let empty = HomesteadBoard(hexes: [], harbours: [])

    init(hexes: [HomesteadHex], harbours: [HomesteadHarbour]) {
        self.hexes = hexes
        self.harbours = harbours
        var vertices = Set<String>()
        var sideCount: [String: Int] = [:]
        var index: [String: HomesteadHex] = [:]
        for hex in hexes {
            index[hex.id] = hex
            for corner in hex.coord.corners { vertices.insert(corner.id) }
            for side in hex.coord.sides { sideCount[side.id, default: 0] += 1 }
        }
        vertexIds = vertices
        edgeIds = Set(sideCount.keys)
        coastIds = Set(sideCount.filter { $0.value == 1 }.map(\.key))
        byId = index
    }

    private enum CodingKeys: String, CodingKey { case hexes, harbours }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let hexes = (try? c.decodeIfPresent([Lenient<HomesteadHex>].self, forKey: .hexes))?.compactMap(\.value) ?? []
        let harbours = (try? c.decodeIfPresent([Lenient<HomesteadHarbour>].self, forKey: .harbours))?.compactMap(\.value) ?? []
        self.init(hexes: hexes, harbours: harbours)
    }

    static func == (a: HomesteadBoard, b: HomesteadBoard) -> Bool {
        a.hexes == b.hexes && a.harbours == b.harbours
    }

    func hex(_ id: String) -> HomesteadHex? { byId[id] }
    func hex(at coord: HexCoord) -> HomesteadHex? { byId[coord.id] }

    /// Land hexes touching a corner.
    func land(around v: HomesteadVertex) -> [HomesteadHex] { v.hexes.compactMap { hex(at: $0) } }

    /// Land hexes either side of a side.
    func land(beside e: HomesteadEdge) -> [HomesteadHex] { e.hexes.compactMap { hex(at: $0) } }

    func isVertex(_ id: String) -> Bool { vertexIds.contains(id) }
    func isEdge(_ id: String) -> Bool { edgeIds.contains(id) }

    /// The harbour a corner trades at, if any.
    func harbour(at vertexId: String) -> HomesteadHarbour? {
        harbours.first { harbour in
            guard let edge = HomesteadEdge(id: harbour.edge) else { return false }
            let (a, b) = edge.ends
            return a.id == vertexId || b.id == vertexId
        }
    }

    /// The land hex a coastal side belongs to (for which way the pier faces).
    func shoreHex(of edge: HomesteadEdge) -> HomesteadHex? { land(beside: edge).first }

    /// The board-space box around every hex, corners included.
    func bounds(size s: Double) -> CGRect {
        guard !hexes.isEmpty else { return CGRect(x: -s, y: -s, width: 2 * s, height: 2 * s) }
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for hex in hexes {
            for p in HomesteadPixels.outline(hex.coord, size: s) {
                minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
                minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// One element of an array that may not decode, so a single odd entry from a
/// newer site drops out instead of blanking the whole list.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

// MARK: - Counts of resources

/// A hand, a price, a bank: resource → count. Unknown keys are ignored.
struct HomesteadCounts: Equatable, Hashable {
    private(set) var values: [HomesteadResource: Int]

    init(_ values: [HomesteadResource: Int] = [:]) {
        self.values = values.filter { $0.value != 0 }
    }

    static let none = HomesteadCounts()

    subscript(_ r: HomesteadResource) -> Int {
        get { values[r] ?? 0 }
        set { values[r] = newValue == 0 ? nil : newValue }
    }

    var total: Int { values.values.reduce(0, +) }
    var isEmpty: Bool { values.values.allSatisfy { $0 == 0 } }

    /// Every count of `need` is covered.
    func covers(_ need: HomesteadCounts) -> Bool {
        HomesteadResource.allCases.allSatisfy { self[$0] >= need[$0] }
    }

    /// The wire's `{ "timber": 1, … }`, without zeros.
    var wire: [String: Int] {
        var out: [String: Int] = [:]
        for r in HomesteadResource.allCases where self[r] > 0 { out[r.rawValue] = self[r] }
        return out
    }

    /// "1 timber, 1 clay"; `empty` when nothing.
    func text(empty: String = "nothing") -> String {
        let parts = HomesteadResource.allCases.filter { self[$0] > 0 }.map { "\(self[$0]) \($0.rawValue)" }
        return parts.isEmpty ? empty : parts.joined(separator: ", ")
    }

    static func from(_ raw: [String: Int]?) -> HomesteadCounts {
        var out = HomesteadCounts()
        for (key, value) in raw ?? [:] {
            if let r = HomesteadResource(rawValue: key) { out[r] = value }
        }
        return out
    }
}

extension HomesteadCounts: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let ints = try? c.decode([String: Int].self) {
            self = HomesteadCounts.from(ints)
        } else if let doubles = try? c.decode([String: Double].self) {
            self = HomesteadCounts.from(doubles.mapValues { Int($0) })
        } else {
            self = .none
        }
    }
}

// MARK: - The room's Homestead side

enum HomesteadPhase: String, Equatable {
    case lobby, countdown, playing, finished, closed, unknown

    static func from(_ raw: String?) -> HomesteadPhase {
        guard let raw else { return .unknown }
        return HomesteadPhase(rawValue: raw) ?? .unknown
    }
}

enum HomesteadStep: String, Equatable {
    case setup, roll, discard, fox, main, roads, unknown

    static func from(_ raw: String?) -> HomesteadStep? {
        guard let raw else { return nil }
        return HomesteadStep(rawValue: raw) ?? .unknown
    }
}

struct HomesteadBuilding: Decodable, Equatable {
    let at: String
    let owner: String
    let piece: HomesteadPiece

    init(at: String, owner: String, piece: HomesteadPiece) {
        self.at = at
        self.owner = owner
        self.piece = piece
    }

    private enum CodingKeys: String, CodingKey { case at, owner, piece }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decode(String.self, forKey: .at)
        owner = try c.decode(String.self, forKey: .owner)
        piece = HomesteadPiece(rawValue: (try? c.decodeIfPresent(String.self, forKey: .piece)) ?? "cottage") ?? .cottage
    }
}

struct HomesteadRoad: Decodable, Equatable {
    let at: String
    let owner: String
}

struct HomesteadDice: Decodable, Equatable {
    let a: Int
    let b: Int
    let total: Int
    let by: String?
    let at: Double

    private enum CodingKeys: String, CodingKey { case a, b, total, by, at }

    init(a: Int, b: Int, by: String?, at: Double) {
        self.a = a; self.b = b; self.total = a + b; self.by = by; self.at = at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        a = min(6, max(1, (try? c.decodeIfPresent(Int.self, forKey: .a)) ?? 1))
        b = min(6, max(1, (try? c.decodeIfPresent(Int.self, forKey: .b)) ?? 1))
        total = (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? (a + b)
        by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? nil
        at = (try? c.decodeIfPresent(Double.self, forKey: .at)) ?? 0
    }
}

struct HomesteadSetup: Decodable, Equatable {
    let round: Int
    /// What the active player places next.
    let need: HomesteadPiece
    /// The cottage just placed, which the road must touch.
    let cottage: String?

    private enum CodingKeys: String, CodingKey { case round, need, cottage }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        round = (try? c.decodeIfPresent(Int.self, forKey: .round)) ?? 1
        need = HomesteadPiece(rawValue: (try? c.decodeIfPresent(String.self, forKey: .need)) ?? "cottage") ?? .cottage
        cottage = (try? c.decodeIfPresent(String.self, forKey: .cottage)) ?? nil
    }
}

struct HomesteadHeldCard: Decodable, Equatable, Hashable {
    let kind: HomesteadCard
    /// Bought this turn: not playable until the next.
    let new: Bool

    private enum CodingKeys: String, CodingKey { case kind, new }

    init(kind: HomesteadCard, new: Bool) {
        self.kind = kind
        self.new = new
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = HomesteadCard(raw: (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "")
        new = (try? c.decodeIfPresent(Bool.self, forKey: .new)) ?? false
    }
}

/// My own side: only ever mine.
struct HomesteadMe: Decodable, Equatable {
    let hand: HomesteadCounts
    let cards: [HomesteadHeldCard]
    /// My total, heirlooms included.
    let vp: Int
    let playedCardThisTurn: Bool
    /// What one of each costs me at the bank (2, 3 or 4).
    let rates: [HomesteadResource: Int]

    private enum CodingKeys: String, CodingKey { case hand, cards, vp, playedCardThisTurn, rates }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hand = (try? c.decodeIfPresent(HomesteadCounts.self, forKey: .hand)) ?? .none
        cards = (try? c.decodeIfPresent([Lenient<HomesteadHeldCard>].self, forKey: .cards))?.compactMap(\.value) ?? []
        vp = (try? c.decodeIfPresent(Int.self, forKey: .vp)) ?? 0
        playedCardThisTurn = (try? c.decodeIfPresent(Bool.self, forKey: .playedCardThisTurn)) ?? false
        let raw = (try? c.decodeIfPresent([String: Int].self, forKey: .rates)) ?? [:]
        var rates: [HomesteadResource: Int] = [:]
        for r in HomesteadResource.allCases { rates[r] = raw[r.rawValue] ?? 4 }
        self.rates = rates
    }

    func rate(_ r: HomesteadResource) -> Int { rates[r] ?? 4 }

    var heirlooms: Int { cards.filter { $0.kind == .heirloom }.count }
}

/// Where I may act right now: the server's list, already allowing for cost,
/// pieces, step and turn.
struct HomesteadLegal: Decodable, Equatable {
    var road: [String] = []
    var cottage: [String] = []
    var town: [String] = []
    var fox: [String] = []
    /// Fox hex → who could be robbed there.
    var victims: [String: [String]] = [:]
    var canRoll = false
    var canBuy = false
    var canEnd = false
    var playable: [HomesteadCard] = []
    var canTrade = false

    static let nothing = HomesteadLegal()

    init() {}

    private enum CodingKeys: String, CodingKey { case road, cottage, town, fox, victims, canRoll, canBuy, canEnd, playable, canTrade }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        road = (try? c.decodeIfPresent([String].self, forKey: .road)) ?? []
        cottage = (try? c.decodeIfPresent([String].self, forKey: .cottage)) ?? []
        town = (try? c.decodeIfPresent([String].self, forKey: .town)) ?? []
        fox = (try? c.decodeIfPresent([String].self, forKey: .fox)) ?? []
        victims = (try? c.decodeIfPresent([String: [String]].self, forKey: .victims)) ?? [:]
        canRoll = (try? c.decodeIfPresent(Bool.self, forKey: .canRoll)) ?? false
        canBuy = (try? c.decodeIfPresent(Bool.self, forKey: .canBuy)) ?? false
        canEnd = (try? c.decodeIfPresent(Bool.self, forKey: .canEnd)) ?? false
        playable = ((try? c.decodeIfPresent([String].self, forKey: .playable)) ?? []).map(HomesteadCard.init(raw:))
        canTrade = (try? c.decodeIfPresent(Bool.self, forKey: .canTrade)) ?? false
    }

    func spots(for piece: HomesteadPiece) -> [String] {
        switch piece {
        case .road: return road
        case .cottage: return cottage
        case .town: return town
        }
    }
}

/// A player as Homestead sends them (the shared `GamePlayer` keeps the rest).
struct HomesteadPlayer: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let status: String
    let isHost: Bool
    let seat: Int?
    let colour: HomesteadColour?
    let handCount: Int
    let cardCount: Int
    let rangersPlayed: Int
    let publicVp: Int
    let trail: Int
    let longestTrail: Bool
    let chiefRanger: Bool
    /// Pieces left to place.
    let pieces: [HomesteadPiece: Int]
    let away: Bool
    /// Revealed once finished.
    let heirlooms: Int?
    let vp: Int?

    var joined: Bool { status == "joined" }
    var seated: Bool { seat != nil }

    private enum CodingKeys: String, CodingKey {
        case id, name, status, isHost, seat, colour, handCount, cardCount, rangersPlayed, publicVp, trail
        case longestTrail, chiefRanger, pieces, away, heirlooms, vp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "joined"
        isHost = (try? c.decodeIfPresent(Bool.self, forKey: .isHost)) ?? false
        seat = (try? c.decodeIfPresent(Int.self, forKey: .seat)) ?? nil
        let rawColour = (try? c.decodeIfPresent(String.self, forKey: .colour)) ?? nil
        colour = rawColour.flatMap(HomesteadColour.init(rawValue:))
            ?? seat.flatMap { HomesteadColour.allCases.indices.contains($0) ? HomesteadColour.allCases[$0] : nil }
        handCount = (try? c.decodeIfPresent(Int.self, forKey: .handCount)) ?? 0
        cardCount = (try? c.decodeIfPresent(Int.self, forKey: .cardCount)) ?? 0
        rangersPlayed = (try? c.decodeIfPresent(Int.self, forKey: .rangersPlayed)) ?? 0
        publicVp = (try? c.decodeIfPresent(Int.self, forKey: .publicVp)) ?? 0
        trail = (try? c.decodeIfPresent(Int.self, forKey: .trail)) ?? 0
        longestTrail = (try? c.decodeIfPresent(Bool.self, forKey: .longestTrail)) ?? false
        chiefRanger = (try? c.decodeIfPresent(Bool.self, forKey: .chiefRanger)) ?? false
        let raw = (try? c.decodeIfPresent([String: Int].self, forKey: .pieces)) ?? [:]
        var pieces: [HomesteadPiece: Int] = [:]
        for piece in HomesteadPiece.allCases { pieces[piece] = raw[piece.rawValue] ?? 0 }
        self.pieces = pieces
        away = (try? c.decodeIfPresent(Bool.self, forKey: .away)) ?? false
        heirlooms = (try? c.decodeIfPresent(Int.self, forKey: .heirlooms)) ?? nil
        vp = (try? c.decodeIfPresent(Int.self, forKey: .vp)) ?? nil
    }
}

enum HomesteadOfferStatus: String, Equatable {
    case open, done, cancelled, void
    case unknown

    static func from(_ raw: String?) -> HomesteadOfferStatus {
        guard let raw else { return .unknown }
        return HomesteadOfferStatus(rawValue: raw) ?? .unknown
    }
}

struct HomesteadOffer: Decodable, Equatable, Identifiable {
    let id: String
    let from: String
    /// Nil = everyone.
    let to: [String]?
    /// What `from` gives.
    let give: HomesteadCounts
    /// What `from` wants back.
    let want: HomesteadCounts
    let status: HomesteadOfferStatus
    let refusedBy: [String]
    /// A counter names the offer it answers.
    let counterTo: String?
    let acceptedBy: String?
    let at: Double

    var isOpen: Bool { status == .open }
    var isCounter: Bool { counterTo != nil }

    func isTo(_ id: String) -> Bool { id != from && (to?.contains(id) ?? true) }

    private enum CodingKeys: String, CodingKey { case id, from, to, give, want, status, refusedBy, counterTo, acceptedBy, at }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        from = try c.decode(String.self, forKey: .from)
        to = (try? c.decodeIfPresent([String].self, forKey: .to)) ?? nil
        give = (try? c.decodeIfPresent(HomesteadCounts.self, forKey: .give)) ?? .none
        want = (try? c.decodeIfPresent(HomesteadCounts.self, forKey: .want)) ?? .none
        status = HomesteadOfferStatus.from((try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil)
        refusedBy = (try? c.decodeIfPresent([String].self, forKey: .refusedBy)) ?? []
        counterTo = (try? c.decodeIfPresent(String.self, forKey: .counterTo)) ?? nil
        acceptedBy = (try? c.decodeIfPresent(String.self, forKey: .acceptedBy)) ?? nil
        at = (try? c.decodeIfPresent(Double.self, forKey: .at)) ?? 0
    }
}

struct HomesteadTradeHint: Decodable, Equatable, Hashable {
    let give: HomesteadResource
    let count: Int
    let get: HomesteadResource
    /// What it would help build: road | cottage | town | card.
    let forWhat: String?

    private enum CodingKeys: String, CodingKey { case give, count, get, forWhat = "for" }
}

struct HomesteadHints: Decodable, Equatable {
    /// road | cottage | town | card.
    let affordable: [String]
    let trades: [HomesteadTradeHint]
    let tip: String?

    private enum CodingKeys: String, CodingKey { case affordable, trades, tip }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        affordable = (try? c.decodeIfPresent([String].self, forKey: .affordable)) ?? []
        trades = (try? c.decodeIfPresent([Lenient<HomesteadTradeHint>].self, forKey: .trades))?.compactMap(\.value) ?? []
        tip = (try? c.decodeIfPresent(String.self, forKey: .tip)) ?? nil
    }
}

struct HomesteadLogEntry: Decodable, Equatable, Identifiable {
    let n: Int
    let at: Double
    /// setup | roll | produce | … — any string: a newer site's kind still reads.
    let kind: String
    let by: String?
    let text: String
    let auto: Bool

    var id: Int { n }

    private enum CodingKeys: String, CodingKey { case n, at, kind, by, text, auto }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = (try? c.decodeIfPresent(Int.self, forKey: .n)) ?? 0
        at = (try? c.decodeIfPresent(Double.self, forKey: .at)) ?? 0
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "note"
        by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? nil
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        auto = (try? c.decodeIfPresent(Bool.self, forKey: .auto)) ?? false
    }

    var symbol: String {
        switch kind {
        case "roll": return "dice.fill"
        case "produce": return "leaf.fill"
        case "discard": return "tray.and.arrow.up.fill"
        case "fox", "steal": return "pawprint.fill"
        case "build", "setup": return "house.fill"
        case "buy", "play": return "book.closed.fill"
        case "bank", "trade", "offer": return "arrow.left.arrow.right"
        case "award": return "rosette"
        case "turn": return "arrow.turn.down.right"
        case "away", "leave": return "moon.zzz.fill"
        case "finish": return "flag.checkered"
        default: return "circle.fill"
        }
    }
}

struct HomesteadResult: Decodable, Equatable {
    let winnerId: String?
    /// points | left | abandoned.
    let reason: String
}

struct HomesteadStanding: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let place: Int
    let vp: Int
    let heirlooms: Int
    let cottages: Int
    let towns: Int
    let trail: Int
    let longestTrail: Bool
    let chiefRanger: Bool
    let result: String
    let left: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, place, score, vp, heirlooms, cottages, towns, trail, longestTrail, chiefRanger, result, left
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        place = (try? c.decodeIfPresent(Int.self, forKey: .place)) ?? 0
        vp = (try? c.decodeIfPresent(Int.self, forKey: .vp)) ?? (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        heirlooms = (try? c.decodeIfPresent(Int.self, forKey: .heirlooms)) ?? 0
        cottages = (try? c.decodeIfPresent(Int.self, forKey: .cottages)) ?? 0
        towns = (try? c.decodeIfPresent(Int.self, forKey: .towns)) ?? 0
        trail = (try? c.decodeIfPresent(Int.self, forKey: .trail)) ?? 0
        longestTrail = (try? c.decodeIfPresent(Bool.self, forKey: .longestTrail)) ?? false
        chiefRanger = (try? c.decodeIfPresent(Bool.self, forKey: .chiefRanger)) ?? false
        result = (try? c.decodeIfPresent(String.self, forKey: .result)) ?? "lost"
        left = (try? c.decodeIfPresent(Bool.self, forKey: .left)) ?? false
    }
}

/// The room's Homestead side, decoded from the same JSON as `GameRoom`.
struct HomesteadState: Decodable, Equatable {
    let phase: HomesteadPhase
    /// Nil outside `playing`.
    let step: HomesteadStep?
    let meId: String
    let difficulty: String
    /// live | async.
    let pace: String
    let deadlineHours: Int?
    let vpTarget: Int
    let island: HomesteadIsland?
    /// The rules in a sentence, from the server.
    let rule: String?
    let turn: Int
    let activeId: String?
    let phaseEndsAt: Double?
    let board: HomesteadBoard
    let fox: String?
    let buildings: [HomesteadBuilding]
    let roads: [HomesteadRoad]
    let seats: [String]
    let dice: HomesteadDice?
    let setup: HomesteadSetup?
    let freeRoads: Int
    let discardOwed: [String: Int]
    let me: HomesteadMe?
    let legal: HomesteadLegal
    let players: [HomesteadPlayer]
    let bank: HomesteadCounts
    let deckCount: Int
    let costs: [String: HomesteadCounts]
    let showCosts: Bool
    let offers: [HomesteadOffer]
    let hints: HomesteadHints?
    let log: [HomesteadLogEntry]
    let result: HomesteadResult?
    let standings: [HomesteadStanding]?
    let winnerIds: [String]

    private enum CodingKeys: String, CodingKey {
        case phase, step, meId, difficulty, pace, deadlineHours, vpTarget, island, rule, turn, activeId, phaseEndsAt
        case board, fox, buildings, roads, seats, dice, setup, freeRoads, discardOwed, me, legal, players, bank
        case deckCount, costs, showCosts, offers, hints, log, result, standings, winnerIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = HomesteadPhase.from((try? c.decodeIfPresent(String.self, forKey: .phase)) ?? nil)
        step = HomesteadStep.from((try? c.decodeIfPresent(String.self, forKey: .step)) ?? nil)
        meId = (try? c.decodeIfPresent(String.self, forKey: .meId)) ?? ""
        difficulty = (try? c.decodeIfPresent(String.self, forKey: .difficulty)) ?? "medium"
        pace = (try? c.decodeIfPresent(String.self, forKey: .pace)) ?? "live"
        deadlineHours = (try? c.decodeIfPresent(Int.self, forKey: .deadlineHours)) ?? nil
        vpTarget = (try? c.decodeIfPresent(Int.self, forKey: .vpTarget)) ?? 10
        island = HomesteadIsland.from((try? c.decodeIfPresent(String.self, forKey: .island)) ?? nil)
        rule = (try? c.decodeIfPresent(String.self, forKey: .rule)) ?? nil
        turn = (try? c.decodeIfPresent(Int.self, forKey: .turn)) ?? 0
        activeId = (try? c.decodeIfPresent(String.self, forKey: .activeId)) ?? nil
        phaseEndsAt = (try? c.decodeIfPresent(Double.self, forKey: .phaseEndsAt)) ?? nil
        board = (try? c.decodeIfPresent(HomesteadBoard.self, forKey: .board)) ?? .empty
        fox = (try? c.decodeIfPresent(String.self, forKey: .fox)) ?? nil
        buildings = (try? c.decodeIfPresent([Lenient<HomesteadBuilding>].self, forKey: .buildings))?.compactMap(\.value) ?? []
        roads = (try? c.decodeIfPresent([Lenient<HomesteadRoad>].self, forKey: .roads))?.compactMap(\.value) ?? []
        seats = (try? c.decodeIfPresent([String].self, forKey: .seats)) ?? []
        dice = (try? c.decodeIfPresent(HomesteadDice.self, forKey: .dice)) ?? nil
        setup = (try? c.decodeIfPresent(HomesteadSetup.self, forKey: .setup)) ?? nil
        freeRoads = (try? c.decodeIfPresent(Int.self, forKey: .freeRoads)) ?? 0
        discardOwed = (try? c.decodeIfPresent([String: Int].self, forKey: .discardOwed)) ?? [:]
        me = (try? c.decodeIfPresent(HomesteadMe.self, forKey: .me)) ?? nil
        legal = (try? c.decodeIfPresent(HomesteadLegal.self, forKey: .legal)) ?? .nothing
        players = (try? c.decodeIfPresent([Lenient<HomesteadPlayer>].self, forKey: .players))?.compactMap(\.value) ?? []
        bank = (try? c.decodeIfPresent(HomesteadCounts.self, forKey: .bank)) ?? .none
        deckCount = (try? c.decodeIfPresent(Int.self, forKey: .deckCount)) ?? 0
        costs = (try? c.decodeIfPresent([String: HomesteadCounts].self, forKey: .costs)) ?? HomesteadText.defaultCosts
        showCosts = (try? c.decodeIfPresent(Bool.self, forKey: .showCosts)) ?? true
        offers = (try? c.decodeIfPresent([Lenient<HomesteadOffer>].self, forKey: .offers))?.compactMap(\.value) ?? []
        hints = (try? c.decodeIfPresent(HomesteadHints.self, forKey: .hints)) ?? nil
        log = (try? c.decodeIfPresent([Lenient<HomesteadLogEntry>].self, forKey: .log))?.compactMap(\.value) ?? []
        result = (try? c.decodeIfPresent(HomesteadResult.self, forKey: .result)) ?? nil
        standings = (try? c.decodeIfPresent([Lenient<HomesteadStanding>].self, forKey: .standings))?.compactMap(\.value)
        winnerIds = (try? c.decodeIfPresent([String].self, forKey: .winnerIds)) ?? []
    }

    // MARK: Reading it

    func player(_ id: String?) -> HomesteadPlayer? {
        guard let id else { return nil }
        return players.first { $0.id == id }
    }

    var myself: HomesteadPlayer? { player(meId) }
    var isAsync: Bool { pace == "async" }
    var isMyTurn: Bool { phase == .playing && activeId == meId && !meId.isEmpty }
    var hard: Bool { difficulty == "hard" }
    /// Players at the table, in seat order.
    var seated: [HomesteadPlayer] {
        let order = Dictionary(uniqueKeysWithValues: seats.enumerated().map { ($1, $0) })
        return players.filter { $0.seat != nil }.sorted { (order[$0.id] ?? $0.seat ?? 0) < (order[$1.id] ?? $1.seat ?? 0) }
    }

    func colour(of id: String) -> HomesteadColour? { player(id)?.colour }

    func cost(_ key: String) -> HomesteadCounts { costs[key] ?? HomesteadText.defaultCosts[key] ?? .none }

    /// What I still owe in a discard; 0 when nothing.
    var myDiscard: Int { discardOwed[meId] ?? 0 }

    func building(at vertexId: String) -> HomesteadBuilding? { buildings.first { $0.at == vertexId } }

    var openOffers: [HomesteadOffer] { offers.filter(\.isOpen) }

    /// What I may do about one offer.
    func role(in offer: HomesteadOffer) -> HomesteadOfferRole {
        HomesteadOfferRole(offer: offer, meId: meId, activeId: activeId, step: step, offers: offers,
                           hand: me?.hand ?? .none)
    }

    /// The people the room is waiting on right now.
    var waitingOn: [String] {
        guard phase == .playing else { return [] }
        if step == .discard { return discardOwed.filter { $0.value > 0 }.map(\.key).sorted() }
        return activeId.map { [$0] } ?? []
    }
}

// MARK: - Offers, from where I sit

struct HomesteadOfferRole: Equatable {
    var canAccept = false
    var canCounter = false
    var canRefuse = false
    var canCancel = false
    /// Mine, and open.
    var mine = false
    /// I said no already.
    var refused = false
    /// I could accept but do not hold the cards it asks of me.
    var short = false

    init(offer: HomesteadOffer, meId: String, activeId: String?, step: HomesteadStep?, offers: [HomesteadOffer],
         hand: HomesteadCounts) {
        guard offer.isOpen, !meId.isEmpty, step == .main else { return }
        refused = offer.refusedBy.contains(meId)
        if offer.from == meId {
            mine = true
            canCancel = true
            return
        }
        guard offer.isTo(meId) else { return }
        // What accepting would cost me: what the proposer wants.
        let covers = hand.covers(offer.want)
        short = !covers
        if offer.isCounter {
            // A counter is to the active player only.
            guard meId == activeId else { return }
            canAccept = covers
            canRefuse = !refused
        } else {
            guard offer.from == activeId else { return }
            canAccept = covers
            canRefuse = !refused
            let countered = offers.contains { $0.isOpen && $0.from == meId && $0.counterTo == offer.id }
            canCounter = !countered
        }
    }
}

// MARK: - Taps: from the legal lists to the board

/// What a tap on the board would do.
enum HomesteadTool: String, Hashable, CaseIterable {
    case road, cottage, town, fox

    var piece: HomesteadPiece? {
        switch self {
        case .road: return .road
        case .cottage: return .cottage
        case .town: return .town
        case .fox: return nil
        }
    }

    init(_ piece: HomesteadPiece) {
        switch piece {
        case .road: self = .road
        case .cottage: self = .cottage
        case .town: self = .town
        }
    }

    var label: String {
        switch self {
        case .road: return "Road"
        case .cottage: return "Cottage"
        case .town: return "Town"
        case .fox: return "Fox"
        }
    }
}

/// One lit spot: which tool, which id.
struct HomesteadTarget: Hashable {
    let tool: HomesteadTool
    let id: String
}

enum HomesteadTargets {
    /// Every spot to light, given the step and the piece picked (if any).
    ///
    /// The step decides when it can: placing in setup lights the piece it
    /// needs; the fox step lights the fox's hexes; free roads light roads. In
    /// the main step a picked piece lights only its own spots; with nothing
    /// picked every spot lights, except on hard, where nothing lights until a
    /// piece is picked (the spec's "no hints").
    static func lit(_ state: HomesteadState, picked: HomesteadPiece?) -> [HomesteadTarget] {
        let legal = state.legal
        func all(_ tool: HomesteadTool, _ ids: [String]) -> [HomesteadTarget] {
            ids.filter { valid(tool, $0, on: state.board) }.map { HomesteadTarget(tool: tool, id: $0) }
        }
        switch state.step {
        case .fox?:
            return all(.fox, legal.fox)
        case .setup?:
            let need = state.setup?.need ?? picked ?? .cottage
            return all(HomesteadTool(need), legal.spots(for: need))
        case .roads?:
            return all(.road, legal.road)
        case .main?:
            if let picked { return all(HomesteadTool(picked), legal.spots(for: picked)) }
            if state.hard { return [] }
            return all(.town, legal.town) + all(.cottage, legal.cottage) + all(.road, legal.road)
        default:
            // Open building lets others build in someone else's main step;
            // anything else lists nothing, and lights nothing.
            if let picked { return all(HomesteadTool(picked), legal.spots(for: picked)) }
            return []
        }
    }

    /// The board must hold the spot: a corner or side of a land hex, or a land hex.
    static func valid(_ tool: HomesteadTool, _ id: String, on board: HomesteadBoard) -> Bool {
        switch tool {
        case .road: return board.isEdge(id)
        case .cottage, .town: return board.isVertex(id)
        case .fox: return board.hex(id) != nil
        }
    }

    /// Where a target is drawn, in board space.
    static func point(_ target: HomesteadTarget, size s: Double) -> CGPoint? {
        switch target.tool {
        case .road: return HomesteadEdge(id: target.id).map { HomesteadPixels.midpoint($0, size: s) }
        case .cottage, .town: return HomesteadVertex(id: target.id).map { HomesteadPixels.point($0, size: s) }
        case .fox: return HexCoord(id: target.id).map { HomesteadPixels.centre($0, size: s) }
        }
    }

    /// The lit target nearest a tap (board space), or nil when none is close
    /// enough. Only ever one of `targets`: a tap can never pick a spot the
    /// server did not list. Corners and sides must be within `reach` (board
    /// units); a fox hex catches any tap inside its circle.
    static func hit(_ tap: CGPoint, among targets: [HomesteadTarget], size s: Double, reach: Double) -> HomesteadTarget? {
        var best: (HomesteadTarget, Double)?
        for target in targets {
            guard let p = point(target, size: s) else { continue }
            let d = HomesteadPixels.distance(tap, p)
            let limit = target.tool == .fox ? s * 0.9 : reach
            guard d <= limit else { continue }
            // Corners win a near-tie over a side's midpoint: a cottage spot sits
            // where three sides meet and is the smaller thing to hit.
            let weighted = target.tool == .road ? d * 1.15 : d
            if best == nil || weighted < best!.1 { best = (target, weighted) }
        }
        return best?.0
    }

    /// What VoiceOver says for a lit target: "Cottage spot, fields 8 and quarry 5".
    static func spoken(_ target: HomesteadTarget, in state: HomesteadState) -> String {
        let board = state.board
        func names(_ hexes: [HomesteadHex]) -> String {
            GameNamesList.join(hexes.map(\.spoken))
        }
        switch target.tool {
        case .cottage:
            guard let v = HomesteadVertex(id: target.id) else { return "Cottage spot" }
            var line = "Cottage spot, \(names(board.land(around: v)))"
            if let harbour = board.harbour(at: target.id) { line += ", harbour \(harbour.label)" }
            return line
        case .town:
            guard let v = HomesteadVertex(id: target.id) else { return "Town spot" }
            return "Make a town here, \(names(board.land(around: v)))"
        case .road:
            guard let e = HomesteadEdge(id: target.id) else { return "Road spot" }
            let land = board.land(beside: e)
            return land.isEmpty ? "Road spot" : "Road spot beside \(names(land))"
        case .fox:
            guard let hex = board.hex(target.id) else { return "Move the fox here" }
            var line = "Move the fox to \(hex.spoken)"
            let victims = (state.legal.victims[target.id] ?? []).compactMap { state.player($0)?.name }
            if !victims.isEmpty { line += ", next to \(GameNamesList.join(victims))" }
            return line
        }
    }
}

/// "a", "a and b", "a, b and c" — Foundation-only twin of `GameNames.list`.
enum GameNamesList {
    static func join(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}

// MARK: - The view onto the board

/// Board space to screen and back: fit the island to the view, then the
/// player's zoom (0.6× to 3×) and pan on top.
struct HomesteadViewport: Equatable {
    static let minZoom = 0.6
    static let maxZoom = 3.0

    /// Board-space box to fit.
    var bounds: CGRect
    var viewSize: CGSize
    var zoom: Double = 1
    var pan: CGSize = .zero
    /// Room around the island at 1×, in points.
    var margin: Double = 12

    /// Points per board unit at 1×.
    var fitScale: Double {
        let w = max(1, Double(viewSize.width) - 2 * margin)
        let h = max(1, Double(viewSize.height) - 2 * margin)
        let bw = max(1, Double(bounds.width))
        let bh = max(1, Double(bounds.height))
        return min(w / bw, h / bh)
    }

    var scale: Double { fitScale * zoom }

    func toScreen(_ p: CGPoint) -> CGPoint {
        let cx = Double(bounds.midX), cy = Double(bounds.midY)
        return CGPoint(x: Double(viewSize.width) / 2 + (Double(p.x) - cx) * scale + Double(pan.width),
                       y: Double(viewSize.height) / 2 + (Double(p.y) - cy) * scale + Double(pan.height))
    }

    func toBoard(_ p: CGPoint) -> CGPoint {
        let cx = Double(bounds.midX), cy = Double(bounds.midY)
        return CGPoint(x: (Double(p.x) - Double(viewSize.width) / 2 - Double(pan.width)) / scale + cx,
                       y: (Double(p.y) - Double(viewSize.height) / 2 - Double(pan.height)) / scale + cy)
    }

    static func clampZoom(_ z: Double) -> Double { min(maxZoom, max(minZoom, z)) }

    /// Keep at least part of the island on screen.
    func clampedPan(_ proposed: CGSize) -> CGSize {
        let limitX = Double(bounds.width) * scale / 2 + Double(viewSize.width) / 3
        let limitY = Double(bounds.height) * scale / 2 + Double(viewSize.height) / 3
        return CGSize(width: min(limitX, max(-limitX, Double(proposed.width))),
                      height: min(limitY, max(-limitY, Double(proposed.height))))
    }
}

// MARK: - Request bodies

/// A JSON value for a move body.
enum HomesteadValue: Encodable, Equatable {
    case string(String)
    case int(Int)
    case strings([String])
    case counts([String: Int])
    case null

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .strings(let v): try c.encode(v)
        case .counts(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

/// `POST /api/native/games/<id>` for a Homestead move: `{ action, …fields }`.
/// Its own body (not `GameActionBody`): Homestead's `give` is a resource name
/// at the bank but a map in an offer, and its `to` is a list of player ids.
struct HomesteadMove: Encodable, Equatable {
    let action: String
    var fields: [String: HomesteadValue] = [:]

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(action, forKey: Key("action"))
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            try c.encode(value, forKey: Key(key))
        }
    }

    static let roll = HomesteadMove(action: "roll")
    static let buy = HomesteadMove(action: "buy")
    static let skip = HomesteadMove(action: "skip")
    static let end = HomesteadMove(action: "end")

    static func build(_ piece: HomesteadPiece, at id: String) -> HomesteadMove {
        HomesteadMove(action: "build", fields: ["piece": .string(piece.rawValue), "at": .string(id)])
    }

    static func play(_ card: HomesteadCard, take: [HomesteadResource]? = nil, resource: HomesteadResource? = nil) -> HomesteadMove {
        var fields: [String: HomesteadValue] = ["card": .string(card.raw)]
        if let take { fields["take"] = .strings(take.map(\.rawValue)) }
        if let resource { fields["resource"] = .string(resource.rawValue) }
        return HomesteadMove(action: "play", fields: fields)
    }

    static func fox(_ hex: String, victim: String?) -> HomesteadMove {
        var fields: [String: HomesteadValue] = ["hex": .string(hex)]
        if let victim { fields["victim"] = .string(victim) }
        return HomesteadMove(action: "fox", fields: fields)
    }

    static func discard(_ cards: HomesteadCounts) -> HomesteadMove {
        HomesteadMove(action: "discard", fields: ["cards": .counts(cards.wire)])
    }

    static func bank(give: HomesteadResource, get: HomesteadResource) -> HomesteadMove {
        HomesteadMove(action: "bank", fields: ["give": .string(give.rawValue), "get": .string(get.rawValue)])
    }

    /// `to` nil = everyone.
    static func offer(give: HomesteadCounts, want: HomesteadCounts, to: [String]?) -> HomesteadMove {
        HomesteadMove(action: "offer", fields: [
            "give": .counts(give.wire), "want": .counts(want.wire),
            "to": to.map { .strings($0) } ?? .null,
        ])
    }

    static func counter(_ offerId: String, give: HomesteadCounts, want: HomesteadCounts) -> HomesteadMove {
        HomesteadMove(action: "counter", fields: ["offerId": .string(offerId), "give": .counts(give.wire), "want": .counts(want.wire)])
    }

    static func accept(_ offerId: String) -> HomesteadMove { HomesteadMove(action: "accept", fields: ["offerId": .string(offerId)]) }
    static func refuse(_ offerId: String) -> HomesteadMove { HomesteadMove(action: "refuse", fields: ["offerId": .string(offerId)]) }
    static func cancel(_ offerId: String) -> HomesteadMove { HomesteadMove(action: "cancel", fields: ["offerId": .string(offerId)]) }
}

/// A composed trade, checked before it is sent (the server checks again).
struct HomesteadTradeDraft: Equatable {
    var give = HomesteadCounts()
    var want = HomesteadCounts()

    /// Why it cannot be sent yet, or nil when it can.
    func problem(hand: HomesteadCounts) -> String? {
        if give.isEmpty { return "Pick something to give." }
        if want.isEmpty { return "Pick something you want." }
        if HomesteadResource.allCases.contains(where: { give[$0] > 0 && want[$0] > 0 }) {
            return "A resource can't be on both sides."
        }
        if !hand.covers(give) { return "You don't have those cards." }
        return nil
    }
}

/// The discard sheet: exactly `owed` cards from what I hold.
struct HomesteadDiscardDraft: Equatable {
    var cards = HomesteadCounts()

    func ready(owed: Int, hand: HomesteadCounts) -> Bool {
        cards.total == owed && hand.covers(cards)
    }

    /// One more of `r`, if I hold it and still owe.
    mutating func add(_ r: HomesteadResource, owed: Int, hand: HomesteadCounts) {
        guard cards.total < owed, cards[r] < hand[r] else { return }
        cards[r] += 1
    }

    mutating func remove(_ r: HomesteadResource) {
        guard cards[r] > 0 else { return }
        cards[r] -= 1
    }
}

// MARK: - Sentences and figures

enum HomesteadText {
    /// The spec's prices, used when a room leaves `costs` out.
    static let defaultCosts: [String: HomesteadCounts] = [
        "road": HomesteadCounts([.timber: 1, .clay: 1]),
        "cottage": HomesteadCounts([.timber: 1, .clay: 1, .wool: 1, .grain: 1]),
        "town": HomesteadCounts([.grain: 2, .stone: 3]),
        "card": HomesteadCounts([.wool: 1, .grain: 1, .stone: 1]),
    ]

    /// Chances in 36: 2/12 = 1 … 6/8 = 5; 7 and nothing = 0.
    static func pips(_ token: Int?) -> Int {
        guard let token, (2...12).contains(token), token != 7 else { return 0 }
        return 6 - abs(7 - token)
    }

    /// A deadline, from the milliseconds left: "0:42", "12 min", "21 h".
    static func timeLeft(_ ms: Double) -> String {
        let seconds = max(0, Int((ms / 1000).rounded(.down)))
        if seconds < 600 { return "\(seconds / 60):\(String(format: "%02d", seconds % 60))" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return "\(seconds / 3600) h"
    }

    /// What the room is waiting for, as a headline.
    static func headline(_ state: HomesteadState, name: (String) -> String) -> String {
        guard state.phase == .playing, let step = state.step else { return "Waiting…" }
        let mine = state.isMyTurn
        let who = state.activeId.map(name) ?? "Someone"
        switch step {
        case .setup:
            let need = state.setup?.need ?? .cottage
            if mine { return need == .road ? "Place a road next to it" : "Place a cottage" }
            return "\(who) is placing a \(need.rawValue)"
        case .roll:
            return mine ? "Your turn: roll the dice" : "\(who) to roll"
        case .discard:
            if state.myDiscard > 0 { return "Put back \(state.myDiscard) cards" }
            return "Waiting for discards"
        case .fox:
            return mine ? "Move the fox" : "\(who) is moving the fox"
        case .main:
            return mine ? "Your turn: build and trade" : "\(who)'s turn"
        case .roads:
            return mine ? "Place your free roads" : "\(who) is placing free roads"
        case .unknown:
            return mine ? "Your turn" : "\(who)'s turn"
        }
    }

    /// "8 points to win · friendly fox".
    static func rules(_ state: HomesteadState) -> String {
        var bits = ["\(state.vpTarget) points to win"]
        if state.difficulty == "easy" { bits.append("friendly fox") }
        if state.isAsync, let hours = state.deadlineHours { bits.append("\(hours) h a turn") }
        return bits.joined(separator: " · ")
    }

    /// How a game ended, in a sentence.
    static func outcome(_ state: HomesteadState, name: (String) -> String) -> String? {
        guard let result = state.result else { return nil }
        switch result.reason {
        case "points":
            guard let id = result.winnerId else { return nil }
            let who = name(id)
            return who == "You" ? "You reached \(state.vpTarget) points first." : "\(who) reached \(state.vpTarget) points first."
        case "left":
            guard let id = result.winnerId else { return "Everyone else left." }
            return "\(name(id)) stayed to the end: everyone else left."
        case "abandoned":
            return "Everyone was away, so the game stopped."
        default:
            return nil
        }
    }

    /// The bits of a player's strip: "5 points · 7 cards · 2 almanac".
    static func strip(_ p: HomesteadPlayer) -> String {
        var bits = ["\(p.publicVp) \(p.publicVp == 1 ? "point" : "points")",
                    "\(p.handCount) \(p.handCount == 1 ? "card" : "cards")"]
        if p.cardCount > 0 { bits.append("\(p.cardCount) almanac") }
        return bits.joined(separator: " · ")
    }
}

// MARK: - The room and the new-game sheet
//
// These read the shared `GameRoom` / `CreateGameBody` (GameModels.swift, also
// Foundation only).

/// Which of the screen's pages a room is on: Homestead's own phase when the
/// room carries it, else the shared phase (a lobby from an older answer).
enum HomesteadScreenPhase {
    static func of(_ room: GameRoom) -> HomesteadPhase {
        if let phase = room.homestead?.phase, phase != .unknown { return phase }
        switch room.phase {
        case .lobby: return .lobby
        case .countdown: return .countdown
        case .playing: return .playing
        case .finished: return .finished
        case .closed: return .closed
        default: return .unknown
        }
    }
}

/// What the new-game sheet sends for Homestead. The pace (play now, or over
/// days) is the durable sheet's, added on top for any game that offers it.
struct HomesteadSettings: Equatable {
    /// `auto` is large with five at the start, standard otherwise.
    static let islands: [HomesteadIslandChoice] = [.auto, .standard, .large]

    var difficulty: GameDifficulty
    var island: HomesteadIslandChoice = .auto

    static func island(at index: Int) -> HomesteadIslandChoice {
        islands.indices.contains(index) ? islands[index] : .auto
    }

    func createBody(invite: [String]) -> CreateGameBody {
        CreateGameBody(game: GameKind.homestead.rawValue, difficulty: difficulty.rawValue, invite: invite,
                       island: island.rawValue)
    }

    static func line(island: HomesteadIslandChoice) -> String {
        let size: String
        switch island {
        case .auto: size = "The island grows to 31 hexes when five of you play."
        case .standard: size = "19 hexes: a snug island for three or four."
        case .large: size = "31 hexes, with more harbours: room for five."
        }
        return size + " Three to five players: invite at least two."
    }
}

enum HomesteadIslandChoice: String, Equatable, CaseIterable {
    case auto, standard, large

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .standard: return "Standard"
        case .large: return "Large"
        }
    }
}

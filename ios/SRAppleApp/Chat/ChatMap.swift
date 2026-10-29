import Foundation

// MARK: - A map a turn made
//
// SR-Main reduces a turn's map for the phone (`$lib/jkai/native-rich`): pins
// and tracks as plain coordinates, with the box they sit in, arrive as
// `{ type: "map", simple: true, points, tracks, bounds, caption }`; anything
// richer (a heatmap) arrives as `simple: false` and stays a web card. This is
// the simple shape, read tolerantly — a pin with no usable coordinate is
// skipped, not fatal — and the region to open on. Foundation only, so the
// Linux harness tests it; `ChatMapView` (`ChatRich.swift`) draws it.

struct ChatMap: Decodable, Hashable {
    struct Coordinate: Hashable {
        let lat: Double
        let lon: Double

        var isValid: Bool { (-90...90).contains(lat) && (-180...180).contains(lon) }
    }

    struct Pin: Hashable {
        let coordinate: Coordinate
        let label: String?
    }

    struct Bounds: Hashable {
        let south: Double
        let west: Double
        let north: Double
        let east: Double
    }

    /// Where the map opens: a centre and a span, in degrees.
    struct Region: Hashable {
        let centerLat: Double
        let centerLon: Double
        let latDelta: Double
        let lonDelta: Double
    }

    let points: [Pin]
    let tracks: [[Coordinate]]
    let bounds: Bounds?
    let caption: String?

    /// Something to draw. A map with neither a pin nor a track is a web card.
    var drawable: Bool { !points.isEmpty || !tracks.isEmpty }

    init(points: [Pin], tracks: [[Coordinate]], bounds: Bounds?, caption: String?) {
        self.points = points
        self.tracks = tracks
        self.bounds = bounds
        self.caption = caption
    }

    private enum Keys: String, CodingKey { case points, tracks, bounds, caption }
    private struct RawPoint: Decodable { let lat: Double?; let lon: Double?; let label: String? }
    private struct RawBounds: Decodable { let south: Double?; let west: Double?; let north: Double?; let east: Double? }
    /// Decodes anything, keeping a point only if it is one.
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        caption = (try? c.decodeIfPresent(String.self, forKey: .caption)) ?? nil
        let raw = ((try? c.decodeIfPresent([Lossy<RawPoint>].self, forKey: .points)) ?? nil) ?? []
        points = raw.compactMap { item in
            guard let p = item.value, let lat = p.lat, let lon = p.lon else { return nil }
            let coordinate = Coordinate(lat: lat, lon: lon)
            guard coordinate.isValid else { return nil }
            let label = p.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Pin(coordinate: coordinate, label: label?.isEmpty == false ? label : nil)
        }
        let rawTracks = ((try? c.decodeIfPresent([Lossy<[Lossy<RawPoint>]>].self, forKey: .tracks)) ?? nil) ?? []
        tracks = rawTracks.compactMap { track -> [Coordinate]? in
            let line = (track.value ?? []).compactMap { item -> Coordinate? in
                guard let p = item.value, let lat = p.lat, let lon = p.lon else { return nil }
                let coordinate = Coordinate(lat: lat, lon: lon)
                return coordinate.isValid ? coordinate : nil
            }
            // A line needs two ends.
            return line.count >= 2 ? line : nil
        }
        if let b = (try? c.decodeIfPresent(RawBounds.self, forKey: .bounds)) ?? nil,
           let south = b.south, let west = b.west, let north = b.north, let east = b.east,
           south <= north, (-90...90).contains(south), (-90...90).contains(north),
           (-180...180).contains(west), (-180...180).contains(east) {
            bounds = Bounds(south: south, west: west, north: north, east: east)
        } else {
            bounds = nil
        }
    }

    /// The smallest span the map opens at: about a kilometre, so a single pin
    /// is a street rather than a single building.
    static let minimumSpan = 0.01
    /// Room round the edge, so a pin is never drawn under the frame.
    static let padding = 1.25

    /// From the server's bounds; failing those, from everything drawn.
    var region: Region? {
        let box: Bounds
        if let bounds {
            box = bounds
        } else {
            let all = points.map(\.coordinate) + tracks.flatMap { $0 }
            guard let first = all.first else { return nil }
            box = all.dropFirst().reduce(Bounds(south: first.lat, west: first.lon, north: first.lat, east: first.lon)) { b, c in
                Bounds(south: min(b.south, c.lat), west: min(b.west, c.lon), north: max(b.north, c.lat), east: max(b.east, c.lon))
            }
        }
        // A box whose west is east of its east crosses the antimeridian.
        let lonSpan = box.east >= box.west ? box.east - box.west : box.east + 360 - box.west
        var centerLon = box.west + lonSpan / 2
        if centerLon > 180 { centerLon -= 360 }
        return Region(
            centerLat: (box.south + box.north) / 2,
            centerLon: centerLon,
            latDelta: min(max((box.north - box.south) * Self.padding, Self.minimumSpan), 180),
            lonDelta: min(max(lonSpan * Self.padding, Self.minimumSpan), 360)
        )
    }
}

import Foundation

// Car Racer+ scenery: what stands beyond the walls of each circuit — trees
// round the parkland and the forest, buildings along the streets,
// containers and cranes at the harbour, spoil heaps at the quarry, dunes on
// the coast, grandstands by the start and floodlights after dark. Placed
// once per circuit from a seed of its id, so a circuit always looks the
// same, and never on the road, the run-off or the walls.

/// A kind of thing beside a circuit.
enum CarProPropKind: String, Equatable, CaseIterable {
    /// A round broadleaf canopy.
    case tree
    /// A darker, pointed forest tree.
    case pine
    case bush
    case rock
    /// A roof seen from above.
    case building
    /// A shipping container.
    case container
    /// A dockside crane's long boom.
    case crane
    /// A stand of seats facing the road.
    case grandstand
    /// A lighting tower: a pool of light after dark.
    case floodlight
    /// A stack of old tyres.
    case tyres
    /// A beach hut.
    case hut
    /// A sand dune.
    case dune
    /// A heap of spoil.
    case heap
}

/// One thing beside the circuit.
struct CarProProp: Equatable {
    var kind: CarProPropKind
    var position: CarProVec
    /// Its radius (or half its length), m.
    var size: Double
    /// Which way it faces, radians.
    var angle: Double
    /// Which of the theme's shades it takes.
    var shade: Int
}

enum CarProScenery {
    /// The mix of things beside a theme's circuits: each kind and how often.
    static func mix(_ theme: CarProTrackTheme) -> [(CarProPropKind, Double)] {
        switch theme {
        case .parkland: return [(.tree, 0.62), (.bush, 0.3), (.tyres, 0.08)]
        case .speedway: return [(.tree, 0.35), (.bush, 0.25), (.tyres, 0.25), (.building, 0.15)]
        case .streets: return [(.building, 0.82), (.tree, 0.18)]
        case .hills: return [(.tree, 0.46), (.pine, 0.2), (.rock, 0.26), (.bush, 0.08)]
        case .coast: return [(.dune, 0.4), (.hut, 0.2), (.rock, 0.2), (.bush, 0.2)]
        case .quarry: return [(.heap, 0.38), (.rock, 0.42), (.tyres, 0.2)]
        case .harbourNight: return [(.container, 0.72), (.crane, 0.1), (.building, 0.18)]
        case .forest: return [(.pine, 0.7), (.tree, 0.26), (.rock, 0.04)]
        }
    }

    /// How many things per side per candidate spot, 0…1.
    static func density(_ theme: CarProTrackTheme) -> Double {
        switch theme {
        case .forest: return 0.95
        case .streets, .harbourNight: return 0.9
        case .parkland, .hills: return 0.7
        case .coast, .quarry: return 0.6
        case .speedway: return 0.45
        }
    }

    /// The size of a kind, m, from a 0…1 roll.
    static func size(_ kind: CarProPropKind, roll: Double) -> Double {
        switch kind {
        case .tree: return 3.2 + 2.6 * roll
        case .pine: return 2.4 + 1.8 * roll
        case .bush: return 1.2 + 1.0 * roll
        case .rock: return 1.0 + 2.2 * roll
        case .building: return 7 + 6 * roll
        case .container: return 6.1
        case .crane: return 16 + 6 * roll
        case .grandstand: return 22
        case .floodlight: return 0.8
        case .tyres: return 1.1
        case .hut: return 1.6
        case .dune: return 6 + 6 * roll
        case .heap: return 6 + 5 * roll
        }
    }

    /// Metres from `point` out past the nearest stretch's wall (negative is
    /// inside a wall): the room a thing has there.
    static func clearance(_ point: CarProVec, track: CarProTrack) -> Double {
        var best = Double.infinity
        for s in track.samples {
            let rel = point - s.centre
            let reach = s.halfWidth + (rel.dot(s.normal) > 0 ? s.runoffRight : s.runoffLeft)
            let d = rel.length - reach
            if d < best { best = d }
        }
        return best
    }

    /// Every thing beside `track`, the same every time.
    static func props(for track: CarProTrack) -> [CarProProp] {
        var random = CarProRandom(seed: CarProRandom.seed(track.id, salt: 0x5CE7E))
        let samples = track.samples
        let n = samples.count
        guard n > 8 else { return [] }
        let mix = Self.mix(track.theme)
        let density = Self.density(track.theme)
        // Every 12 m or so on each side.
        let step = max(1, Int((12 / track.spacing).rounded()))
        var out: [CarProProp] = []
        out.reserveCapacity(n / step * 2)

        func pick(_ roll: Double) -> CarProPropKind {
            var total = 0.0
            for (_, weight) in mix { total += weight }
            var r = roll * total
            for (kind, weight) in mix {
                if r < weight { return kind }
                r -= weight
            }
            return mix.last?.0 ?? .tree
        }

        for i in stride(from: 0, to: n, by: step) {
            for side in [-1.0, 1.0] {
                guard random.next() < density else { continue }
                let s = samples[i]
                let kind = pick(random.next())
                let size = Self.size(kind, roll: random.next())
                let wall = side < 0 ? s.runoffLeft : s.runoffRight
                let out0 = s.halfWidth + wall + 2 + size
                let offset = side * (out0 + random.next() * 22)
                let along = (random.next() - 0.5) * track.spacing * Double(step)
                let point = s.centre + s.tangent * along + s.normal * offset
                guard clearance(point, track: track) > size + 1.2 else { continue }
                // Buildings and containers line up with the road; the rest are turned anyhow.
                let squared = kind == .building || kind == .container || kind == .hut || kind == .crane
                let angle = squared ? s.direction + (random.next() < 0.3 ? .pi / 2 : 0) : random.next() * 2 * .pi
                out.append(CarProProp(kind: kind, position: point, size: size, angle: angle,
                                      shade: Int(random.next() * 4) % 4))
            }
        }

        // A grandstand by the start, on whichever side has room.
        if let stand = grandstand(track) { out.append(stand) }
        // Lighting towers along the night circuit.
        if track.theme.isNight { out.append(contentsOf: floodlights(track)) }
        return out
    }

    private static func grandstand(_ track: CarProTrack) -> CarProProp? {
        let s = track.samples[track.index(at: track.length - 30)]
        for side in [-1.0, 1.0] {
            let wall = side < 0 ? s.runoffLeft : s.runoffRight
            let point = s.point(side * (s.halfWidth + wall + 10))
            if clearance(point, track: track) > 9 {
                return CarProProp(kind: .grandstand, position: point, size: Self.size(.grandstand, roll: 0),
                                  angle: s.direction, shade: side < 0 ? 0 : 1)
            }
        }
        return nil
    }

    /// A tower every 60 m or so, swapping sides, just behind the wall.
    static func floodlights(_ track: CarProTrack) -> [CarProProp] {
        let step = max(1, Int((60 / track.spacing).rounded()))
        var out: [CarProProp] = []
        var side = 1.0
        for i in stride(from: 0, to: track.samples.count, by: step) {
            let s = track.samples[i]
            for attempt in 0..<2 {
                let here = attempt == 0 ? side : -side
                let wall = here < 0 ? s.runoffLeft : s.runoffRight
                let point = s.point(here * (s.halfWidth + wall + 2.5))
                if clearance(point, track: track) > 1.2 {
                    out.append(CarProProp(kind: .floodlight, position: point, size: Self.size(.floodlight, roll: 0),
                                          angle: s.direction, shade: 0))
                    break
                }
            }
            side = -side
        }
        return out
    }
}

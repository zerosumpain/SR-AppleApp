import Foundation

// Car Racer+ circuits as geometry: a centre line through control points
// (centripetal Catmull-Rom, so it never loops between close points),
// resampled every few metres; the tarmac's width; kerbs on the apexes and
// exits; run-off of grass, with gravel traps on the outside of the bends;
// walls at the edge of the run-off (pulled in wherever another stretch of
// the circuit comes close); banking; dirt and damp patches; corners and
// sectors; the start grid; and a minimum-curvature racing line.

/// The look of a circuit's surroundings, for the drawing.
enum CarProTrackTheme: String, Codable, CaseIterable {
    case parkland
    case speedway
    case streets
    case hills
    case coast
    case quarry
    case harbourNight
    case forest

    /// Drawn after dark: floodlights and headlights.
    var isNight: Bool { self == .harbourNight }
}

/// A named corner, for the HUD and the telemetry chart.
struct CarProCorner: Equatable, Identifiable {
    let name: String
    /// Metres round from the line to the apex.
    let distance: Double
    /// +1 a right-hander, −1 a left-hander.
    let direction: Int
    var id: String { name }
}

/// A circuit as written down: control points and its character.
struct CarProCircuit {
    let id: String
    let name: String
    /// One sentence for the picker.
    let line: String
    let location: String
    let theme: CarProTrackTheme
    /// Tarmac width, m.
    let width: Double
    /// Centre-line control points in racing order, metres; the first is the
    /// start line, on the main straight.
    let control: [(Double, Double)]
    /// Corners at control-point indices.
    let corners: [(Int, String)]
    /// The control points where sectors 2 and 3 begin.
    let sectors: (Int, Int)
    /// Metres past the first control point to the start line.
    var start: Double = 0
    /// Grass beside the tarmac each side, m.
    var runoff: Double = 10
    /// Gravel traps on the outside of the bends, and how deep.
    var gravel: Bool = true
    var gravelDepth: Double = 20
    /// Most banking in the bends, radians.
    var banking: Double = 0
    /// Control-point index ranges (start, end) where the racing surface is
    /// loose dirt, and where it is damp.
    var dirt: [(Int, Int)] = []
    var wet: [(Int, Int)] = []
}

/// One sample of a circuit, every few metres round.
struct CarProTrackSample: Equatable {
    var centre: CarProVec
    var distance: Double
    var direction: Double
    var tangent: CarProVec
    /// The right of the direction of travel.
    var normal: CarProVec
    /// 1/radius, positive bending right.
    var curvature: Double
    var halfWidth: Double
    /// The racing surface here: tarmac, dirt or a damp patch.
    var surface: CarProSurface
    var kerbLeft = false
    var kerbRight = false
    /// Metres from the tarmac edge to the wall, each side.
    var runoffLeft: Double
    var runoffRight: Double
    /// Gravel beyond the first strip of grass, each side.
    var gravelLeft = false
    var gravelRight = false
    /// Radians; positive tilts down to the right.
    var bank: Double = 0
    /// The racing line: metres right of the centre.
    var lineOffset: Double = 0
    var linePoint: CarProVec = .zero
    var lineCurvature: Double = 0

    /// A point `offset` metres right of the centre (negative is left).
    func point(_ offset: Double) -> CarProVec { centre + normal * offset }
    /// The wall each side, as an offset from the centre.
    var wallLeft: Double { -(halfWidth + runoffLeft) }
    var wallRight: Double { halfWidth + runoffRight }
}

/// Where a point sits against a circuit.
struct CarProTrackSpot: Equatable {
    /// The sample at the start of the segment the point is beside.
    let index: Int
    /// Metres round from the start line, 0..<length.
    let distance: Double
    /// Metres right of the centre line.
    let offset: Double
    let centre: CarProVec
    let tangent: CarProVec
    let normal: CarProVec
}

/// A circuit ready to race.
struct CarProTrack: Identifiable {
    let id: String
    let name: String
    let line: String
    let location: String
    let theme: CarProTrackTheme
    let samples: [CarProTrackSample]
    let length: Double
    /// Metres between samples.
    let spacing: Double
    let corners: [CarProCorner]
    /// Where sectors 2 and 3 begin, metres round.
    let sectorStarts: [Double]
    /// The widest the walls are from the centre: for the far search.
    let maxReach: Double

    /// The kerb strip's width beyond the white line, m.
    static let kerbWidth: Double = 1.4
    /// Grass between the kerb and a gravel trap, m.
    static let grassBand: Double = 3
    /// Centre-line spacing, about, m.
    static let targetSpacing: Double = 4

    init(_ circuit: CarProCircuit) {
        id = circuit.id
        name = circuit.name
        line = circuit.line
        location = circuit.location
        theme = circuit.theme
        let control = circuit.control.map { CarProVec(x: $0.0, y: $0.1) }
        let built = Self.centreLine(control, start: circuit.start)
        length = built.length
        spacing = built.spacing
        let points = built.points
        let n = points.count
        let half = circuit.width / 2

        // Directions and curvature.
        var tangents: [CarProVec] = []
        tangents.reserveCapacity(n)
        for i in 0..<n {
            tangents.append((points[(i + 1) % n] - points[(i - 1 + n) % n]).normalized)
        }
        var rawCurve = [Double](repeating: 0, count: n)
        for i in 0..<n { rawCurve[i] = Self.curvature(points, i, stride: 2) }
        let curve = Self.smooth(rawCurve, radius: 2)

        // The racing surface: dirt and damp ranges by control index.
        let controlDistance = built.controlDistances
        func inRanges(_ ranges: [(Int, Int)], _ d: Double) -> Bool {
            for (a, b) in ranges {
                let from = controlDistance[a % control.count], to = controlDistance[b % control.count]
                if from <= to { if d >= from && d <= to { return true } } else if d >= from || d <= to { return true }
            }
            return false
        }

        var samples: [CarProTrackSample] = []
        samples.reserveCapacity(n)
        for i in 0..<n {
            let t = tangents[i]
            let d = Double(i) * built.spacing
            var surface = CarProSurface.tarmac
            if inRanges(circuit.dirt, d) { surface = .dirt } else if inRanges(circuit.wet, d) { surface = .wet }
            samples.append(CarProTrackSample(centre: points[i], distance: d, direction: atan2(t.y, t.x), tangent: t,
                                             normal: t.right, curvature: curve[i], halfWidth: half, surface: surface,
                                             runoffLeft: circuit.runoff, runoffRight: circuit.runoff))
        }

        // Kerbs: the inside of every real bend, and the outside on the way out.
        let apex = 1.0 / 115
        for i in 0..<n {
            let k = curve[i]
            if abs(k) > apex {
                if k > 0 { samples[i].kerbRight = true } else { samples[i].kerbLeft = true }
            }
            var exit = 0.0
            for back in 1...9 { exit = abs(exit) > abs(curve[(i - back + n) % n]) ? exit : curve[(i - back + n) % n] }
            if abs(exit) > apex * 1.1 && abs(k) < abs(exit) * 0.85 && k * exit >= 0 {
                if exit > 0 { samples[i].kerbLeft = true } else { samples[i].kerbRight = true }
            }
        }

        // Gravel on the outside of the bends, out to the trap's depth.
        if circuit.gravel {
            let bend = 1.0 / 200
            for i in 0..<n {
                var strongest = 0.0
                for j in -4...10 {
                    let c = curve[(i + j + n) % n]
                    if abs(c) > abs(strongest) { strongest = c }
                }
                guard abs(strongest) > bend else { continue }
                if strongest > 0 {
                    samples[i].gravelLeft = true
                    samples[i].runoffLeft = max(samples[i].runoffLeft, circuit.gravelDepth)
                } else {
                    samples[i].gravelRight = true
                    samples[i].runoffRight = max(samples[i].runoffRight, circuit.gravelDepth)
                }
            }
        }

        // Banking in the bends.
        if circuit.banking > 0 {
            for i in 0..<n {
                let k = curve[i]
                samples[i].bank = circuit.banking * CarProMath.clamp(abs(k) * 160, 0, 1) * (k >= 0 ? 1 : -1)
            }
        }

        Self.fitWalls(&samples, spacing: built.spacing)

        // The racing line.
        let offsets = Self.racingLine(samples, spacing: built.spacing)
        for i in 0..<n {
            samples[i].lineOffset = offsets[i]
            samples[i].linePoint = samples[i].point(offsets[i])
        }
        var rawLine = [Double](repeating: 0, count: n)
        let linePoints = samples.map(\.linePoint)
        for i in 0..<n { rawLine[i] = Self.curvature(linePoints, i, stride: 3) }
        let lineCurve = Self.smooth(rawLine, radius: 2)
        for i in 0..<n { samples[i].lineCurvature = lineCurve[i] }

        self.samples = samples
        var reach = 0.0
        for s in samples { reach = max(reach, s.halfWidth + max(s.runoffLeft, s.runoffRight)) }
        maxReach = reach

        corners = circuit.corners.map { index, name in
            let d = controlDistance[index % control.count]
            let i = Int(d / built.spacing) % n
            var k = 0.0
            for j in -6...6 { let c = curve[(i + j + n) % n]; if abs(c) > abs(k) { k = c } }
            return CarProCorner(name: name, distance: d, direction: k >= 0 ? 1 : -1)
        }
        sectorStarts = [controlDistance[circuit.sectors.0], controlDistance[circuit.sectors.1]]
    }

    // MARK: - Geometry

    /// The centre line through `control`, sampled about every `targetSpacing` metres.
    private static func centreLine(_ control: [CarProVec], start: Double) -> (points: [CarProVec], spacing: Double,
                                                                              length: Double, controlDistances: [Double]) {
        let n = control.count
        var dense: [CarProVec] = []
        var controlIndex: [Int] = []
        for i in 0..<n {
            let p0 = control[(i - 1 + n) % n], p1 = control[i], p2 = control[(i + 1) % n], p3 = control[(i + 2) % n]
            let chord = (p2 - p1).length
            let steps = max(4, Int(chord.rounded(.up)))
            controlIndex.append(dense.count)
            for k in 0..<steps { dense.append(catmullRom(p0, p1, p2, p3, Double(k) / Double(steps))) }
        }
        let m = dense.count
        var run: [Double] = [0]
        run.reserveCapacity(m + 1)
        for i in 0..<m { run.append(run[i] + (dense[(i + 1) % m] - dense[i]).length) }
        let length = run[m]
        let count = max(8, Int((length / targetSpacing).rounded()))
        let spacing = length / Double(count)
        var points: [CarProVec] = []
        points.reserveCapacity(count)
        var j = 0
        for i in 0..<count {
            let d = Double(i) * spacing
            while j < m - 1 && run[j + 1] < d { j += 1 }
            let a = dense[j], b = dense[(j + 1) % m]
            let span = run[j + 1] - run[j]
            let t = span > 0 ? (d - run[j]) / span : 0
            points.append(a + (b - a) * t)
        }
        // Start the samples at the start line.
        let shift = ((Int((start / spacing).rounded()) % count) + count) % count
        let rotated = Array(points[shift...] + points[..<shift])
        let moved = Double(shift) * spacing
        let controlDistances = controlIndex.map { index -> Double in
            var d = run[index] - moved
            if d < 0 { d += length }
            return d
        }
        return (rotated, spacing, length, controlDistances)
    }

    /// Centripetal Catmull-Rom between `p1` and `p2`.
    private static func catmullRom(_ p0: CarProVec, _ p1: CarProVec, _ p2: CarProVec, _ p3: CarProVec,
                                   _ t: Double) -> CarProVec {
        func knot(_ ti: Double, _ a: CarProVec, _ b: CarProVec) -> Double { ti + max((b - a).length, 1e-6).squareRoot() }
        let t0 = 0.0, t1 = knot(t0, p0, p1), t2 = knot(t1, p1, p2), t3 = knot(t2, p2, p3)
        let tt = t1 + (t2 - t1) * t
        func mix(_ a: CarProVec, _ b: CarProVec, _ ta: Double, _ tb: Double) -> CarProVec {
            a * ((tb - tt) / (tb - ta)) + b * ((tt - ta) / (tb - ta))
        }
        let a1 = mix(p0, p1, t0, t1), a2 = mix(p1, p2, t1, t2), a3 = mix(p2, p3, t2, t3)
        let b1 = mix(a1, a2, t0, t2), b2 = mix(a2, a3, t1, t3)
        return mix(b1, b2, t1, t2)
    }

    /// Signed curvature at `i` from the circle through its neighbours `stride` away.
    static func curvature(_ points: [CarProVec], _ i: Int, stride: Int) -> Double {
        let n = points.count
        let a = points[(i - stride + n) % n], b = points[i], c = points[(i + stride) % n]
        let ab = (b - a).length, bc = (c - b).length, ca = (a - c).length
        let product = ab * bc * ca
        guard product > 1e-9 else { return 0 }
        return 2 * (b - a).cross(c - a) / product
    }

    /// A circular moving average.
    static func smooth(_ values: [Double], radius: Int) -> [Double] {
        let n = values.count
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var sum = 0.0
            for j in -radius...radius { sum += values[(i + j + n) % n] }
            out[i] = sum / Double(2 * radius + 1)
        }
        return out
    }

    /// Pulls each wall in wherever another stretch of the circuit is close on
    /// that side, so the two run-offs meet at one wall halfway; then evens
    /// the walls out so they do not jag.
    private static func fitWalls(_ samples: inout [CarProTrackSample], spacing: Double) {
        let n = samples.count
        let cell = 30.0
        var grid: [Int64: [Int]] = [:]
        func key(_ p: CarProVec) -> (Int64, Int64) { (Int64((p.x / cell).rounded(.down)), Int64((p.y / cell).rounded(.down))) }
        for i in 0..<n {
            let k = key(samples[i].centre)
            grid[k.0 &* 1_000_003 &+ k.1, default: []].append(i)
        }
        var left = samples.map(\.runoffLeft), right = samples.map(\.runoffRight)
        for i in 0..<n {
            let s = samples[i]
            let reach = s.halfWidth + max(s.runoffLeft, s.runoffRight) + 40
            let span = Int((reach / cell).rounded(.up))
            let k = key(s.centre)
            for gx in (k.0 - Int64(span))...(k.0 + Int64(span)) {
                for gy in (k.1 - Int64(span))...(k.1 + Int64(span)) {
                    guard let list = grid[gx &* 1_000_003 &+ gy] else { continue }
                    for j in list {
                        let apart = abs(i - j)
                        let round = Double(min(apart, n - apart)) * spacing
                        guard round > 60 else { continue }
                        let d = samples[j].centre - s.centre
                        let across = d.dot(s.normal)
                        let along = d.dot(s.tangent)
                        guard abs(along) < abs(across) * 0.8 + 4 else { continue }
                        let gap = abs(across) - s.halfWidth - samples[j].halfWidth
                        let allowed = max(0.8, gap / 2 - 0.25)
                        if across > 0 { right[i] = min(right[i], allowed) } else { left[i] = min(left[i], allowed) }
                    }
                }
            }
        }
        // A wall never steps out faster than it can be drawn smoothly.
        for _ in 0..<2 {
            for i in 0..<n {
                let prev = (i - 1 + n) % n, next = (i + 1) % n
                left[i] = min(left[i], left[prev] + spacing * 0.8, left[next] + spacing * 0.8)
                right[i] = min(right[i], right[prev] + spacing * 0.8, right[next] + spacing * 0.8)
            }
        }
        for i in 0..<n {
            samples[i].runoffLeft = left[i]
            samples[i].runoffRight = right[i]
            if left[i] < CarProTrack.kerbWidth + CarProTrack.grassBand + 2 { samples[i].gravelLeft = false }
            if right[i] < CarProTrack.kerbWidth + CarProTrack.grassBand + 2 { samples[i].gravelRight = false }
        }
    }

    /// A minimum-curvature line inside the tarmac: the sum of the squared
    /// second differences of the line's points is relaxed down (Gauss-Seidel
    /// on the biharmonic, coarse strides first so long bends settle quickly),
    /// with every point kept a car's width inside the edges.
    private static func racingLine(_ samples: [CarProTrackSample], spacing: Double) -> [Double] {
        let n = samples.count
        var e = [Double](repeating: 0, count: n)
        let margin = 2.3
        var passes: [(Int, Int)] = []
        for stride in [12, 6, 3, 1] where stride * 6 < n { passes.append((stride, stride == 1 ? 60 : 90)) }
        func point(_ i: Int) -> CarProVec {
            let s = samples[(i % n + n) % n]
            return s.centre + s.normal * e[(i % n + n) % n]
        }
        for (stride, iterations) in passes {
            for _ in 0..<iterations {
                for i in 0..<n {
                    let near = point(i - stride) + point(i + stride)
                    let far = point(i - 2 * stride) + point(i + 2 * stride)
                    let target = (near * 4 - far) * (1.0 / 6)
                    let s = samples[i]
                    let limit = s.halfWidth - margin
                    let want = CarProMath.clamp((target - s.centre).dot(s.normal), -limit, limit)
                    e[i] += (want - e[i]) * 0.7
                }
            }
        }
        return e
    }

    // MARK: - Finding things

    /// The sample index `distance` metres round (wrapping).
    func index(at distance: Double) -> Int {
        var d = distance.truncatingRemainder(dividingBy: length)
        if d < 0 { d += length }
        return min(samples.count - 1, Int(d / spacing))
    }

    /// The sample `steps` on from `i`, wrapping.
    func index(_ i: Int, plus steps: Int) -> Int {
        let n = samples.count
        return ((i + steps) % n + n) % n
    }

    /// Metres round from `from` to `to`, folded into −length/2…length/2.
    func gap(from: Double, to: Double) -> Double {
        var d = (to - from).truncatingRemainder(dividingBy: length)
        if d > length / 2 { d -= length }
        if d < -length / 2 { d += length }
        return d
    }

    /// Where `p` sits against the circuit, searching near sample `hint`
    /// first (a car's last spot) and the whole circuit if that misses.
    func locate(_ p: CarProVec, hint: Int) -> CarProTrackSpot {
        let n = samples.count
        var best = Double.infinity
        var bestIndex = 0, bestT = 0.0
        let h = ((hint % n) + n) % n
        for k in -8...8 {
            let i = (h + k + n) % n
            let (d2, t) = segmentDistance(p, i)
            if d2 < best { best = d2; bestIndex = i; bestT = t }
        }
        if best > (maxReach + 6) * (maxReach + 6) {
            for i in 0..<n {
                let (d2, t) = segmentDistance(p, i)
                if d2 < best { best = d2; bestIndex = i; bestT = t }
            }
        }
        let a = samples[bestIndex], b = samples[(bestIndex + 1) % n]
        let centre = a.centre + (b.centre - a.centre) * bestT
        let tangent = (b.centre - a.centre).normalized
        let normal = tangent.right
        var distance = a.distance + spacing * bestT
        if distance >= length { distance -= length }
        return CarProTrackSpot(index: bestIndex, distance: distance, offset: (p - centre).dot(normal),
                               centre: centre, tangent: tangent, normal: normal)
    }

    private func segmentDistance(_ p: CarProVec, _ i: Int) -> (Double, Double) {
        let a = samples[i].centre, b = samples[(i + 1) % samples.count].centre
        let ab = b - a
        let span2 = ab.lengthSquared
        let t = span2 > 0 ? CarProMath.clamp((p - a).dot(ab) / span2, 0, 1) : 0
        let q = a + ab * t
        return ((p - q).lengthSquared, t)
    }

    /// The ground at `offset` metres right of the centre line, `along` metres
    /// on from sample `index`.
    func surface(near index: Int, along: Double, offset: Double) -> CarProSurface {
        let i = self.index(index, plus: Int((along / spacing).rounded()))
        return surface(sample: i, offset: offset)
    }

    /// The ground at `offset` metres right of the centre at sample `i`.
    func surface(sample i: Int, offset: Double) -> CarProSurface {
        let s = samples[i]
        let beyond = abs(offset) - s.halfWidth
        if beyond <= 0 { return s.surface }
        let right = offset > 0
        if (right ? s.kerbRight : s.kerbLeft) && beyond <= Self.kerbWidth { return .kerb }
        if (right ? s.gravelRight : s.gravelLeft) && beyond > Self.kerbWidth + Self.grassBand { return .gravel }
        return .grass
    }

    /// Where grid slot `slot` (0 is pole) lines up: two abreast, staggered,
    /// behind the line, facing round.
    func grid(_ slot: Int) -> (position: CarProVec, heading: Double, distance: Double) {
        let row = Double(slot / 2)
        let side: Double = slot % 2 == 0 ? -1 : 1
        let back = 9 + row * 9 + (slot % 2 == 0 ? 0 : 4.5)
        let i = index(at: length - back)
        let s = samples[i]
        return (s.point(side * s.halfWidth * 0.38), s.direction, length - back)
    }

    /// The point `distance` round and `offset` right, with the direction there.
    func point(at distance: Double, offset: Double = 0) -> (position: CarProVec, direction: Double) {
        let i = index(at: distance)
        let a = samples[i], b = samples[(i + 1) % samples.count]
        var d = distance.truncatingRemainder(dividingBy: length)
        if d < 0 { d += length }
        let t = CarProMath.clamp((d - a.distance) / spacing, 0, 1)
        let c = a.centre + (b.centre - a.centre) * t
        return (c + a.normal * offset, a.direction)
    }

    /// The box the circuit and its run-off fit in: for the minimap and camera.
    var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        var b = (minX: Double.infinity, minY: Double.infinity, maxX: -Double.infinity, maxY: -Double.infinity)
        for s in samples {
            let l = s.point(s.wallLeft), r = s.point(s.wallRight)
            b.minX = min(b.minX, l.x, r.x); b.maxX = max(b.maxX, l.x, r.x)
            b.minY = min(b.minY, l.y, r.y); b.maxY = max(b.maxY, l.y, r.y)
        }
        return b
    }

    /// Every `every`th centre point, for a minimap path.
    func minimap(every: Int = 4) -> [CarProVec] {
        stride(from: 0, to: samples.count, by: max(1, every)).map { samples[$0].centre }
    }

    /// Every `every`th sample's point at `offset(sample)` metres right of the
    /// centre: the edges, kerbs, walls or racing line as one closed polyline.
    func points(every: Int = 1, offset: (CarProTrackSample) -> Double) -> [CarProVec] {
        stride(from: 0, to: samples.count, by: max(1, every)).map { samples[$0].point(offset(samples[$0])) }
    }

    /// The runs of consecutive samples where `test` holds (kerbs, gravel,
    /// dirt), as index ranges; a run over the line wraps (its upper bound is
    /// then past the last index: take it modulo `samples.count`).
    func runs(where test: (CarProTrackSample) -> Bool) -> [ClosedRange<Int>] {
        let n = samples.count
        guard let gap = samples.indices.first(where: { !test(samples[$0]) }) else { return [0...(n - 1)] }
        var result: [ClosedRange<Int>] = []
        var start: Int?
        for k in 1...n {
            let i = gap + k
            if test(samples[i % n]) {
                if start == nil { start = i }
            } else if let s = start {
                let lower = s % n
                result.append(lower...(lower + (i - 1 - s)))
                start = nil
            }
        }
        return result.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// Which sector (0, 1, 2) `distance` round is in.
    func sector(at distance: Double) -> Int {
        if distance >= sectorStarts[1] { return 2 }
        if distance >= sectorStarts[0] { return 1 }
        return 0
    }

    /// The corner nearest ahead within `within` metres, for the HUD.
    func corner(ahead distance: Double, within: Double = 160) -> CarProCorner? {
        var best: CarProCorner?
        var bestGap = within
        for c in corners {
            let g = gap(from: distance, to: c.distance)
            if g >= -15 && g < bestGap { bestGap = g; best = c }
        }
        return best
    }

    // MARK: - Checks

    /// Pairs of centre-line segments that cross (0 for a sound circuit).
    func crossings() -> Int {
        let n = samples.count
        var count = 0
        for i in 0..<n {
            let a = samples[i].centre, b = samples[(i + 1) % n].centre
            for j in (i + 2)..<max(i + 2, n) where (j + 1) % n != i {
                let c = samples[j].centre, d = samples[(j + 1) % n].centre
                // Quick reject on boxes before the orientation tests.
                if max(a.x, b.x) < min(c.x, d.x) || max(c.x, d.x) < min(a.x, b.x) { continue }
                if max(a.y, b.y) < min(c.y, d.y) || max(c.y, d.y) < min(a.y, b.y) { continue }
                let d1 = (d - c).cross(a - c), d2 = (d - c).cross(b - c)
                let d3 = (b - a).cross(c - a), d4 = (b - a).cross(d - a)
                if d1 * d2 < 0 && d3 * d4 < 0 { count += 1 }
            }
        }
        return count
    }

    /// The least grass-and-wall gap between the tarmac of two stretches that
    /// are far apart round the circuit, m: two roads never touch.
    func tightestGap() -> Double {
        let n = samples.count
        var worst = Double.infinity
        let step = 2
        for i in stride(from: 0, to: n, by: step) {
            for j in stride(from: i + step, to: n, by: step) {
                let apart = min(j - i, n - (j - i))
                guard Double(apart) * spacing > 80 else { continue }
                let gap = (samples[i].centre - samples[j].centre).length - samples[i].halfWidth - samples[j].halfWidth
                worst = min(worst, gap)
            }
        }
        return worst
    }
}

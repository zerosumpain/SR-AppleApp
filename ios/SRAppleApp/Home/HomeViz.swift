import SwiftUI

// The small pictures inside Home's tiles.
//
// Each borrows a form that is famous for saying one thing at a glance, sized
// down to a tile and drawn in the tile's own type colour (`foregroundStyle`
// from `HomeTileFrame`), so one picture works on every hue:
//
// - Steps: a RADIAL BAR race — one lane per person, the arc's sweep their
//   share of the leader's count (the form of Apple's own rings, as a league).
// - Health: a NIGHTINGALE ROSE — Florence Nightingale's coxcomb, one petal
//   per part of readiness, petal AREA (not radius) true to the score.
// - Tasks: a WAFFLE — one square per task, so "three left" is three squares.
// - News: WARMING STRIPES — Ed Hawkins's climate stripes, one stripe per
//   story, cool to hot by how fast it is moving.
// - Trips: a METRO LINE — Harry Beck's diagram: stops as stations, the ones
//   behind you filled.
// - Backlog: a SHELF of spines, one per thing saved.
//
// Static unless their data changes: nothing here runs a timer.

// MARK: - Steps: radial bars

struct StepsLanes: View {
    struct Lane: Equatable, Identifiable {
        let id: String
        let steps: Int
        let me: Bool
    }

    let lanes: [Lane]

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let leader = Double(max(lanes.map(\.steps).max() ?? 1, 1))
            let pitch = side / 2 / CGFloat(max(lanes.count, 1) + 1)
            let width = max(4, pitch * 0.62)
            for (index, lane) in lanes.enumerated() {
                let r = side / 2 - CGFloat(index) * pitch - width / 2
                guard r > width else { continue }
                var track = Path()
                track.addArc(center: centre, radius: r, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: false)
                var faint = context
                faint.opacity = 0.2
                faint.stroke(track, with: .foreground, style: StrokeStyle(lineWidth: width, lineCap: .round))
                let sweep = 270 * Double(lane.steps) / leader
                guard sweep > 0 else { continue }
                var arc = Path()
                arc.addArc(center: centre, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + max(sweep, 4)), clockwise: false)
                var strong = context
                strong.opacity = lane.me ? 1 : 0.6
                strong.stroke(arc, with: .foreground, style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Health: the rose

/// One petal per part of readiness, area-true: a petal at half the score has
/// half the area, so its radius is the square root. The Move ring runs round
/// the outside.
struct ReadinessRose: View {
    /// 0…100 each.
    let petals: [Double]
    /// Today's Move ring, 0…1+ (closes past 1).
    let move: Double?

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = side / 2 - 5
            let roseR = outer - 9
            if let move {
                var track = Path()
                track.addArc(center: centre, radius: outer, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
                context.stroke(track, with: .color(.white.opacity(0.2)), lineWidth: 5)
                var arc = Path()
                arc.addArc(center: centre, radius: outer, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * min(move, 1)), clockwise: false)
                context.stroke(arc, with: .color(.white), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            let n = petals.count
            guard n > 0 else { return }
            let slice = 2 * Double.pi / Double(n)
            for (index, score) in petals.enumerated() {
                let r = roseR * CGFloat(sqrt(max(0.04, min(score, 100) / 100)))
                let start = -Double.pi / 2 + Double(index) * slice + 0.06
                let end = start + slice - 0.12
                var petal = Path()
                petal.move(to: centre)
                petal.addArc(center: centre, radius: r, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
                petal.closeSubpath()
                context.fill(petal, with: .color(.white.opacity(0.45 + 0.5 * min(score, 100) / 100)))
            }
            // A faint guide at full score.
            var full = Path()
            full.addArc(center: centre, radius: roseR, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            context.stroke(full, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        .accessibilityHidden(true)
    }
}

/// A Move ring as a glass of water: the level is how far round you are.
struct MoveGlass: View {
    let fraction: Double

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            let circle = Path(ellipseIn: rect)
            context.stroke(circle, with: .color(.white.opacity(0.35)), lineWidth: 3)
            let level = rect.maxY - rect.height * CGFloat(min(max(fraction, 0), 1))
            var water = Path()
            water.move(to: CGPoint(x: rect.minX, y: level))
            let waves = 2.0
            for step in 0...40 {
                let t = Double(step) / 40
                let x = rect.minX + rect.width * CGFloat(t)
                let y = level + CGFloat(sin(t * waves * 2 * .pi)) * 4
                water.addLine(to: CGPoint(x: x, y: y))
            }
            water.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            water.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            water.closeSubpath()
            context.clip(to: circle)
            context.fill(water, with: .color(.white.opacity(0.85)))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Tasks: the waffle

struct TaskWaffle: View {
    let done: Int
    let awaiting: Int
    let toDo: Int
    let overdue: Int
    var columns = 8
    var limit = 32

    var body: some View {
        let cells = Array(repeating: 3, count: min(overdue, limit))
            + Array(repeating: 2, count: min(max(toDo - overdue, 0), max(limit - overdue, 0)))
            + Array(repeating: 1, count: awaiting)
            + Array(repeating: 0, count: done)
        let shown = Array(cells.prefix(limit))
        let grid = Array(repeating: GridItem(.flexible(), spacing: 4), count: columns)
        LazyVGrid(columns: grid, alignment: .leading, spacing: 4) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, cell in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(fill(cell))
                    .overlay {
                        if cell == 2 || cell == 3 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(HierarchicalShapeStyle.primary.opacity(cell == 3 ? 1 : 0.7), lineWidth: 1.5)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
    }

    private func fill(_ cell: Int) -> AnyShapeStyle {
        switch cell {
        case 0: return AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.85))
        case 1: return AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.45))
        case 3: return AnyShapeStyle(Color(hex: 0xD7193F).opacity(0.85))
        default: return AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.08))
        }
    }
}

// MARK: - News: warming stripes

struct HeatStripes: View {
    /// One per story, in the desk's order.
    let heats: [Double]

    var body: some View {
        let top = max(heats.max() ?? 1, 0.0001)
        HStack(spacing: 0) {
            ForEach(Array(heats.enumerated()), id: \.offset) { _, heat in
                Rectangle().fill(Self.ramp(heat / top))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
        .accessibilityHidden(true)
    }

    /// Hawkins's ramp: deep blue through pale to deep red.
    static func ramp(_ t: Double) -> Color {
        let stops: [UInt32] = [0x08306B, 0x2171B5, 0x6BAED6, 0xDEEBF7, 0xFEE0D2, 0xFB6A4A, 0xCB181D, 0x67000D]
        let x = min(max(t, 0), 1) * Double(stops.count - 1)
        return Color(hex: stops[Int(x.rounded())])
    }
}

// MARK: - Trips: the metro line

struct MetroLine: View {
    struct Station: Equatable, Identifiable {
        let id: String
        let done: Bool
        let current: Bool
    }

    let stations: [Station]

    var body: some View {
        GeometryReader { geo in
            let count = max(stations.count, 1)
            let step = count > 1 ? (geo.size.width - 16) / CGFloat(count - 1) : 0
            let y = geo.size.height / 2
            let lastDone = stations.lastIndex(where: { $0.done || $0.current }) ?? -1
            ZStack(alignment: .topLeading) {
                Capsule().fill(HierarchicalShapeStyle.primary.opacity(0.3))
                    .frame(width: max(geo.size.width - 16, 0), height: 6)
                    .position(x: geo.size.width / 2, y: y)
                if lastDone > 0 {
                    Capsule().fill(.primary)
                        .frame(width: step * CGFloat(lastDone), height: 6)
                        .position(x: 8 + step * CGFloat(lastDone) / 2, y: y)
                }
                ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                    Circle()
                        .fill(station.done ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(Color.clear))
                        .overlay(Circle().strokeBorder(.primary, lineWidth: 3))
                        .frame(width: station.current ? 20 : 14, height: station.current ? 20 : 14)
                        .background {
                            if station.current { Circle().fill(HierarchicalShapeStyle.primary.opacity(0.3)).scaleEffect(1.7) }
                        }
                        .position(x: 8 + step * CGFloat(index), y: y)
                }
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}

// MARK: - Backlog: the shelf

struct SpineShelf: View {
    let count: Int
    let fresh: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<min(max(count, 1), 14), id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(HierarchicalShapeStyle.primary.opacity(index < count ? (index < fresh ? 1 : 0.55) : 0.15))
                    .frame(width: 9 + CGFloat((index * 7) % 5), height: 30 + CGFloat((index * 13) % 22))
                    .rotationEffect(.degrees(index == min(count, 14) - 1 && count > 3 ? -8 : 0), anchor: .bottom)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(HierarchicalShapeStyle.primary.opacity(0.6)).frame(height: 2).offset(y: 2)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Games: the die

struct DieFace: View {
    let pips: Int

    var body: some View {
        let layout: [Int: [(CGFloat, CGFloat)]] = [
            0: [],
            1: [(0.5, 0.5)],
            2: [(0.27, 0.27), (0.73, 0.73)],
            3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
            4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
            5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
            6: [(0.27, 0.25), (0.73, 0.25), (0.27, 0.5), (0.73, 0.5), (0.27, 0.75), (0.73, 0.75)],
        ]
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(HierarchicalShapeStyle.primary.opacity(0.92))
                ForEach(Array((layout[min(max(pips, 0), 6)] ?? []).enumerated()), id: \.offset) { _, spot in
                    Circle()
                        .fill(SR.Hue.games.base)
                        .frame(width: side * 0.18, height: side * 0.18)
                        .position(x: spot.0 * side, y: spot.1 * side)
                }
            }
            .frame(width: side, height: side)
            .rotationEffect(.degrees(-9))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Daydream: the aurora

/// A still aurora in the daydream's hues, brighter the more there is to
/// decide. A `MeshGradient` on iOS 18; two gradients before it.
struct AuroraField: View {
    var intensity: Double = 1

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.35, 0.55], [1, 0.4], [0, 1], [0.6, 1], [1, 1]],
                    colors: [
                        Color(hex: 0x9333EA), Color(hex: 0xF472B6), Color(hex: 0x6366F1),
                        Color(hex: 0x22D3EE).opacity(0.8 * intensity), Color(hex: 0xF0ABFC), Color(hex: 0xA855F7),
                        Color(hex: 0x7C3AED), Color(hex: 0x38BDF8).opacity(0.9 * intensity), Color(hex: 0xDB2777),
                    ]
                )
            } else {
                ZStack {
                    SR.Hue.daydream.gradient
                    RadialGradient(colors: [Color(hex: 0x22D3EE).opacity(0.6 * intensity), .clear], center: .bottomLeading, startRadius: 0, endRadius: 180)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Flows: the dots

struct FlowDots: View {
    let working: Int
    let failing: Int

    var body: some View {
        let total = min(working + failing, 24)
        let grid = Array(repeating: GridItem(.fixed(12), spacing: 6), count: 8)
        LazyVGrid(columns: grid, alignment: .leading, spacing: 6) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Circle()
                    .fill(index < failing ? AnyShapeStyle(Color(hex: 0xFF6B85)) : AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(total == 0 ? 0.2 : 0.85)))
                    .overlay(Circle().strokeBorder(.white.opacity(index < failing ? 0.9 : 0), lineWidth: 2))
                    .frame(width: 12, height: 12)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Coming up: the next hours

/// The next few hours as a line, each due move a person-coloured marker at
/// the time they are due to leave.
struct MovesAxis: View {
    struct Mark: Equatable, Identifiable {
        let id: String
        let at: Date
        let colour: Color
        let initials: String
    }

    let marks: [Mark]
    let from: Date
    var hours: Double = 6

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - 24
            let y = geo.size.height - 14
            ZStack(alignment: .topLeading) {
                Capsule().fill(HierarchicalShapeStyle.primary.opacity(0.3)).frame(width: width, height: 4).position(x: 12 + width / 2, y: y)
                ForEach(0...Int(hours), id: \.self) { hour in
                    let x = 12 + width * CGFloat(Double(hour) / hours)
                    Rectangle().fill(HierarchicalShapeStyle.primary.opacity(0.5)).frame(width: 1.5, height: hour % 3 == 0 ? 10 : 6).position(x: x, y: y)
                    if hour % 3 == 0, let tick = Calendar.current.date(byAdding: .hour, value: hour, to: from) {
                        Text(hour == 0 ? "now" : tick.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                            .font(SR.Text.label(10))
                            .opacity(0.85)
                            .position(x: x, y: y + 13)
                    }
                }
                ForEach(marks) { mark in
                    let t = min(max(mark.at.timeIntervalSince(from) / (hours * 3600), 0), 1)
                    VStack(spacing: 2) {
                        Text(mark.initials)
                            .font(SR.Text.label(10))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(mark.colour))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        Rectangle().fill(.white).frame(width: 2, height: 10)
                    }
                    .position(x: 12 + width * CGFloat(t), y: y - 22)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

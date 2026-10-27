import SwiftUI

// The pictures inside Home's tiles.
//
// Each borrows a form that is famous for saying one thing at a glance, sized
// to a tile. The vivid tiles' pictures are drawn in the tile's own type colour
// (`foregroundStyle` from `HomeTileFrame`), so one picture works on every hue;
// the glass tiles' charts carry their numbers written on them and use the
// palette's reading colours, because green-for-better needs a ground it reads on.
//
// - Health: a GAUGE for readiness, figures against the week, and the three
//   rings as bars along the foot.
// - Steps: a BAR RACE — one bar per person, the count at its end.
// - Tasks: a WAFFLE — one square per task, so "three left" is three squares.
// - News: WARMING STRIPES — Ed Hawkins's climate stripes, one per story,
//   cool to hot by how fast it is moving.
// - Trips: a METRO LINE — Harry Beck's diagram: stops as stations, the ones
//   behind you filled.
// - Backlog: a SHELF of spines, one per thing saved.
//
// Static unless their data changes: nothing here runs a timer.

// MARK: - Steps: the bar race

/// One bar per person, longest first, each as long as their share of the
/// leader's count, with the count written at its end. The caller's bar is
/// the strong one.
struct StepsRace: View {
    struct Row: Equatable, Identifiable {
        let id: String
        let name: String
        let steps: Int
        let me: Bool
    }

    let rows: [Row]
    @ScaledMetric(relativeTo: .caption) private var nameWidth: CGFloat = 56
    @ScaledMetric(relativeTo: .caption) private var countWidth: CGFloat = 52
    @ScaledMetric(relativeTo: .caption) private var bar: CGFloat = 12

    var body: some View {
        let leader = Double(max(rows.map(\.steps).max() ?? 1, 1))
        VStack(spacing: 6) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(row.me ? SR.Text.label(12) : SR.Text.secondary(12))
                        .foregroundStyle(row.me ? SR.ink : SR.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: nameWidth, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(SR.ink.opacity(0.06))
                            Capsule()
                                .fill(row.me ? AnyShapeStyle(SR.Hue.steps.gradient) : AnyShapeStyle(SR.Hue.steps.base.opacity(0.38)))
                                .frame(width: max(bar, geo.size.width * CGFloat(Double(row.steps) / leader)))
                        }
                    }
                    .frame(height: bar)
                    Text(FamilySteps.figure(row.steps))
                        .font(SR.Text.mono(12))
                        .foregroundStyle(row.me ? SR.ink : SR.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: countWidth, alignment: .trailing)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Health: the gauge

/// Readiness on a three-quarter dial: the arc is the score out of a hundred,
/// the number and its word in the middle.
struct ReadinessDial: View {
    let score: Double
    let label: String

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = max(6, side * 0.1)
            let fraction = min(max(score, 0), 100) / 100
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(SR.ink.opacity(0.08), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * fraction)
                    .stroke(Self.tint(score), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(135))
                VStack(spacing: 0) {
                    Text("\(Int(score.rounded()))")
                        .font(SR.Text.figure(side * 0.3))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(label)
                        .font(SR.Text.label(11))
                        .foregroundStyle(SR.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(line * 1.6)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Readiness's own bands, as the Health tab colours them.
    static func tint(_ score: Double) -> Color {
        score >= 70 ? SR.good : score >= 40 ? SR.Hue.health.base : SR.warn
    }
}

// MARK: - Health: the rings

private extension ActivityRingsStore.Ring {
    /// Move in its own hue, Exercise in Health's, Stand in Trips' blue — the
    /// Watch's red, green and cyan, in the reader's palette.
    var tint: Color {
        switch key {
        case "move": return SR.Hue.move.base
        case "exercise": return SR.Hue.health.base
        default: return SR.Hue.trips.base
        }
    }
}

/// The owner's three rings as three bars along the foot of the Health tile:
/// "Move 412/600".
struct HomeRingBars: View {
    let rings: ActivityRingsStore.Rings?

    var body: some View {
        let shown = (rings?.all ?? []).compactMap { $0 }
        if shown.isEmpty {
            Text("Rings not read yet — they come from Apple Health on this iPhone")
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } else {
            HStack(spacing: 12) {
                ForEach(shown) { ring in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(ring.label)
                                .font(SR.Text.label(11))
                                .foregroundStyle(SR.inkSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 2)
                            Text("\(Int(ring.value.rounded()))/\(Int(ring.goal.rounded()))")
                                .font(SR.Text.mono(11))
                                .foregroundStyle(SR.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ring.tint.opacity(0.16))
                                Capsule().fill(ring.tint)
                                    .frame(width: max(6, geo.size.width * CGFloat(min(ring.fraction, 1))))
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// A member's three rings, nested as on the Watch, with Move's share in the middle.
struct HomeRingsDial: View {
    let rings: ActivityRingsStore.Rings?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = max(6, side * 0.11)
            let list = rings?.all ?? [nil, nil, nil]
            ZStack {
                ForEach(Array(list.enumerated()), id: \.offset) { index, ring in
                    let tint = ring?.tint ?? SR.ink.opacity(0.3)
                    let inset = CGFloat(index) * (line + 2) + line / 2
                    ZStack {
                        Circle().stroke(tint.opacity(0.16), lineWidth: line)
                        if let ring {
                            Circle()
                                .trim(from: 0, to: min(ring.fraction, 1))
                                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .padding(inset)
                }
                if let move = rings?.move {
                    Text("\(Int((move.fraction * 100).rounded()))%")
                        .font(SR.Text.figure(side * 0.17))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(3 * (line + 2) + 2)
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Beside a member's rings: each ring's figure and what is left of it.
struct HomeRingRows: View {
    let rings: ActivityRingsStore.Rings?

    var body: some View {
        let shown = (rings?.all ?? []).compactMap { $0 }
        VStack(alignment: .leading, spacing: 8) {
            if shown.isEmpty {
                Text("Today's rings come from Apple Health on this iPhone")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(3)
            }
            ForEach(shown) { ring in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(ring.tint).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(Int(ring.value.rounded()))")
                                .font(SR.Text.figure(18))
                                .foregroundStyle(SR.ink)
                            Text("/\(Int(ring.goal.rounded())) \(ring.unit)")
                                .font(SR.Text.mono(12))
                                .foregroundStyle(SR.inkSecondary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        Text(ring.fraction >= 1 ? "\(ring.label) closed" : HomeBriefing.ringLeft(.init(key: ring.key, label: ring.label, value: ring.value, goal: ring.goal, unit: ring.unit)))
                            .font(SR.Text.secondary(12))
                            .foregroundStyle(ring.fraction >= 1 ? SR.good : SR.inkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        case 3: return AnyShapeStyle(SR.Hue.alerts.base.opacity(0.85))
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
        // Nine spines at most: fourteen were wider than a square tile and ran
        // out of its right-hand side.
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<min(max(count, 1), 9), id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(HierarchicalShapeStyle.primary.opacity(index < count ? (index < fresh ? 1 : 0.55) : 0.15))
                    .frame(width: 9 + CGFloat((index * 7) % 5), height: 22 + CGFloat((index * 13) % 17))
                    .rotationEffect(.degrees(index == min(count, 9) - 1 && count > 3 ? -8 : 0), anchor: .bottom)
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

/// A still aurora in the daydream's hues and its neighbours', brighter the more there is to
/// decide. A `MeshGradient` on iOS 18; two gradients before it.
struct AuroraField: View {
    var intensity: Double = 1

    var body: some View {
        let dream = SR.Hue.daydream
        Group {
            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.35, 0.55], [1, 0.4], [0, 1], [0.6, 1], [1, 1]],
                    colors: [
                        dream.base, dream.glow, SR.Hue.chat.glow,
                        SR.Hue.news.glow.opacity(0.8 * intensity), dream.glow.opacity(0.7), SR.Hue.games.base,
                        SR.Hue.games.base, SR.Hue.trips.glow.opacity(0.9 * intensity), SR.Hue.backlog.base,
                    ]
                )
            } else {
                ZStack {
                    SR.Hue.daydream.gradient
                    RadialGradient(colors: [SR.Hue.news.glow.opacity(0.6 * intensity), .clear], center: .bottomLeading, startRadius: 0, endRadius: 180)
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
        // Two rows at most: a third pushed the figure under it out of the tile.
        let total = min(working + failing, 16)
        // Flexible, not fixed: eight fixed 12-point dots and their gaps are
        // 138 points, wider than a square tile on the smaller phones.
        let grid = Array(repeating: GridItem(.flexible(minimum: 6, maximum: 12), spacing: 5), count: 8)
        LazyVGrid(columns: grid, alignment: .leading, spacing: 5) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Circle()
                    .fill(index < failing ? AnyShapeStyle(SR.errorOnDark) : AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(total == 0 ? 0.2 : 0.85)))
                    .overlay(Circle().strokeBorder(.white.opacity(index < failing ? 0.9 : 0), lineWidth: 2))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 12)
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

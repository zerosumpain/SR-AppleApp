import SwiftUI

// Car Racer+ furniture shared by the menu pages: the page scroll, the big
// tiles, choice chips, circuit maps, PI badges, stat bars with an
// upgrade's after-bar, results and standings tables, the telemetry chart
// and the notice that answers a refusal. All of it on the app's design
// system: glass cards over the ground, SR type, SR colours.

/// A menu page: the ground, a scroll, the gutter and the section rhythm.
struct CarProPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                content
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .srGround(.warm)
    }
}

/// Circuit outlines by id, worked out once.
@MainActor
enum CarProMapCache {
    private static var shapes: [String: CarProMapShape] = [:]

    static func shape(_ track: CarProTrack) -> CarProMapShape {
        if let shape = shapes[track.id] { return shape }
        let shape = CarProMapShape(track: track)
        shapes[track.id] = shape
        return shape
    }
}

/// A circuit's outline on its own ground, the start marked.
struct CarProTrackMap: View {
    let track: CarProTrack

    var body: some View {
        let shape = CarProMapCache.shape(track)
        let paint = CarProPalette.of(track.theme)
        let start = shape.unit(track.samples[0].centre)
        return Canvas { context, size in
            let side = Double(min(size.width, size.height))
            let ox = (Double(size.width) - side) / 2, oy = (Double(size.height) - side) / 2
            var g = context
            g.translateBy(x: ox, y: oy)
            let inset = side * 0.1
            let path = shape.path(side: side, inset: inset)
            g.stroke(path, with: .color(paint.runoff), style: StrokeStyle(lineWidth: max(7, side * 0.07), lineJoin: .round))
            g.stroke(path, with: .color(Color.white.opacity(0.9)), style: StrokeStyle(lineWidth: max(4, side * 0.038), lineJoin: .round))
            g.stroke(path, with: .color(paint.tarmac), style: StrokeStyle(lineWidth: max(2.6, side * 0.026), lineJoin: .round))
            let k = side - 2 * inset
            let s = CGPoint(x: inset + Double(start.x) * k, y: inset + Double(start.y) * k)
            g.fill(Path(ellipseIn: CGRect(x: s.x - 4, y: s.y - 4, width: 8, height: 8)), with: .color(.white))
            g.fill(Path(ellipseIn: CGRect(x: s.x - 2.5, y: s.y - 2.5, width: 5, height: 5)), with: .color(CarProPalette.red))
        }
        .background(
            LinearGradient(colors: [paint.outside, paint.runoff], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .accessibilityHidden(true)
    }
}

/// A big tile on the home page: an icon, a title and a line.
struct CarProTile: View {
    let icon: String
    let title: String
    let line: String
    let tint: Color
    let id: String
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(SR.Text.title(20))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(tint))
                    .accessibilityHidden(true)
                Text(title)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(SR.cardPadding)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .srGlassCard(.paper, radius: 22, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(SRPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
    }
}

/// A big choice: a figure (or word) with a caption, lit when chosen.
struct CarProChip: View {
    let title: String
    let caption: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            VStack(spacing: 0) {
                Text(title)
                    .font(SR.Text.display(20))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caption.uppercased())
                    .font(SR.Text.label())
                    .tracking(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? SR.paper : SR.ink)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? SR.accentDeep : SR.ink.opacity(0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel("\(title) \(caption)")
        .accessibilityAddTraits(selected ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
    }
}

/// The performance index: the class letter in its colour, and the number.
struct CarProPIBadge: View {
    let pi: Int
    var large = false

    static func colour(_ letter: String) -> Color {
        switch letter {
        case "D": return Color(red: 0.45, green: 0.50, blue: 0.56)
        case "C": return Color(red: 0.16, green: 0.62, blue: 0.36)
        case "B": return Color(red: 0.16, green: 0.45, blue: 0.85)
        case "A": return Color(red: 0.52, green: 0.30, blue: 0.88)
        case "S": return Color(red: 0.92, green: 0.46, blue: 0.10)
        default: return Color(red: 0.86, green: 0.18, blue: 0.22)
        }
    }

    var body: some View {
        let letter = CarProCarStats.piClass(pi)
        HStack(spacing: 0) {
            Text(letter)
                .font(large ? SR.Text.display(18) : SR.monoBold(12))
                .foregroundStyle(Color.white)
                .frame(minWidth: large ? 30 : 20)
                .padding(.vertical, large ? 4 : 2)
                .background(Self.colour(letter))
            Text("\(pi)")
                .font(large ? SR.Text.display(18) : SR.monoBold(12))
                .foregroundStyle(Self.colour(letter))
                .padding(.horizontal, large ? 8 : 5)
                .padding(.vertical, large ? 4 : 2)
        }
        .background(Self.colour(letter).opacity(0.14))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Self.colour(letter), lineWidth: 1.5))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Performance index \(pi), class \(letter)")
    }
}

/// One stat as a bar, with the bar it would have after an upgrade.
struct CarProStatBar: View {
    let name: String
    let value: Double
    var after: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkSecondary)
                Spacer(minLength: 6)
                if let after, abs(after - value) > 0.004 {
                    Text((after > value ? "+" : "−") + "\(Int((abs(after - value) * 100).rounded()))")
                        .font(SR.monoBold())
                        .foregroundStyle(after > value ? SR.good : SR.error)
                }
            }
            GeometryReader { geo in
                let w = Double(geo.size.width)
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.ink.opacity(0.1))
                    if let after, after > value {
                        Capsule().fill(SR.good.opacity(0.7)).frame(width: CGFloat(w * CarProMath.clamp(after, 0.02, 1)))
                    }
                    Capsule().fill(SR.accent).frame(width: CGFloat(w * CarProMath.clamp(min(value, after ?? value), 0.02, 1)))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var words = "\(name) \(Int((value * 100).rounded())) out of 100"
        if let after, abs(after - value) > 0.004 { words += ", \(Int((after * 100).rounded())) after" }
        return words
    }
}

/// A results table: place, driver, car, gap, best lap, and points if scored.
struct CarProResultsTable: View {
    let results: [CarProResult]
    var showPoints = false

    var body: some View {
        let leader = results.first
        let fastest = results.filter { $0.time != nil && $0.bestLap != nil }
            .min { ($0.bestLap ?? .infinity) < ($1.bestLap ?? .infinity) }
        VStack(spacing: 0) {
            ForEach(results) { result in
                if result.position > 1 { Divider().overlay(SR.divider) }
                row(result, leader: leader, fastest: fastest?.id == result.id)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 4)
        .srGlassCard(.paper)
        .accessibilityIdentifier("car-pro-results")
    }

    private func row(_ result: CarProResult, leader: CarProResult?, fastest: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(result.position)")
                .font(SR.Text.display(18))
                .foregroundStyle(result.position <= 3 ? SR.accent : SR.inkGhost)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(result.name)
                        .font(SR.Text.title(15))
                        .foregroundStyle(result.isPlayer ? SR.accent : SR.ink)
                        .lineLimit(1)
                    if fastest {
                        Image(systemName: "bolt.fill")
                            .font(SR.Text.label())
                            .foregroundStyle(CarProHUDStyle.best)
                            .accessibilityLabel("Fastest lap")
                    }
                }
                Text(result.model.name + (result.bestLap.map { " · best \(CarProFormat.time($0))" } ?? ""))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(CarProPresent.gap(result, leader: leader))
                    .font(SR.Text.title(15))
                    .monospacedDigit()
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                if showPoints && result.time != nil {
                    let points = CarProPresent.points(forPosition: result.position) + (fastest ? 1 : 0)
                    if points > 0 {
                        Text("+\(points) pts")
                            .font(SR.monoBold())
                            .foregroundStyle(SR.good)
                    }
                }
                if result.penalty > 0 {
                    Text("+\(Int(result.penalty)) s pen.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.error)
                }
            }
        }
        .padding(.vertical, 8)
        .background(result.isPlayer ? SR.accent.opacity(0.07) : Color.clear)
        .accessibilityElement(children: .combine)
    }
}

/// The championship table.
struct CarProStandingsTable: View {
    let table: [CarProStanding]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(table.enumerated()), id: \.element.id) { index, line in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(SR.Text.display(17))
                        .foregroundStyle(index < 3 ? SR.accent : SR.inkGhost)
                        .frame(width: 26, alignment: .leading)
                    Text(line.name)
                        .font(SR.Text.title(15))
                        .foregroundStyle(line.isPlayer ? SR.accent : SR.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if line.wins > 0 {
                        Label("\(line.wins)", systemImage: "trophy.fill")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .labelStyle(.titleAndIcon)
                            .accessibilityLabel("\(line.wins) win\(line.wins == 1 ? "" : "s")")
                    }
                    Text("\(line.points)")
                        .font(SR.Text.display(17))
                        .monospacedDigit()
                        .foregroundStyle(SR.ink)
                        .frame(minWidth: 34, alignment: .trailing)
                        .accessibilityLabel("\(line.points) points")
                }
                .padding(.vertical, 8)
                .background(line.isPlayer ? SR.accent.opacity(0.07) : Color.clear)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 4)
        .srGlassCard(.paper)
        .accessibilityIdentifier("car-pro-standings")
    }
}

/// A lap's speed against distance, with the best lap behind it, the pedals
/// under it and the corners named along the bottom.
struct CarProTelemetryChart: View {
    let last: CarProTelemetry
    let best: CarProTelemetry?
    let track: CarProTrack
    let mph: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                legend(SR.accent, "Last lap \(CarProFormat.time(last.lapTime))")
                if let best, best != last {
                    legend(SR.inkMuted, "Best \(CarProFormat.time(best.lapTime))")
                }
            }
            Canvas { context, size in
                draw(in: context, size: size)
            }
            .frame(height: 180)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let top = last.speeds.max() ?? 0
        let low = last.speeds.min() ?? 0
        return "Speed trace. Top speed \(CarProPresent.speedText(top, mph: mph)), slowest \(CarProPresent.speedText(low, mph: mph))."
    }

    private func legend(_ colour: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(colour).frame(width: 16, height: 4)
            Text(text)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkSecondary)
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        let strip = 16.0
        let chartH = h - strip - 22
        let bins = max(last.speeds.count, best?.speeds.count ?? 0, 2)
        let top = max(last.speeds.max() ?? 1, best?.speeds.max() ?? 1, 1) * 1.08
        func x(_ i: Int) -> Double { Double(i) / Double(bins - 1) * w }
        func y(_ v: Double) -> Double { chartH - v / top * chartH }

        // Grid: a line every 50 (mph or km/h).
        let unit = mph ? CarProMath.mph : CarProMath.kmh
        var grid = Path()
        var mark = 50.0
        while mark / unit < top {
            let yy = y(mark / unit)
            grid.move(to: CGPoint(x: 0, y: yy))
            grid.addLine(to: CGPoint(x: w, y: yy))
            mark += 50
        }
        context.stroke(grid, with: .color(SR.ink.opacity(0.08)), lineWidth: 1)

        // The corners along the bottom.
        let length = track.length
        for corner in track.corners {
            let cx = corner.distance / length * w
            var tick = Path()
            tick.move(to: CGPoint(x: cx, y: 0))
            tick.addLine(to: CGPoint(x: cx, y: chartH))
            context.stroke(tick, with: .color(SR.ink.opacity(0.1)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        if let best, best != last { context.stroke(trace(best, x: x, y: y), with: .color(SR.inkMuted), lineWidth: 1.5) }
        context.stroke(trace(last, x: x, y: y), with: .color(SR.accent), style: StrokeStyle(lineWidth: 2.4, lineJoin: .round))

        // The pedals under the trace: green throttle, red brake.
        let stripTop = chartH + 6
        let barW = max(1, w / Double(bins))
        var gas = Path(), stop = Path()
        for i in 0..<last.speeds.count {
            let t = i < last.throttle.count ? last.throttle[i] : 0
            let b = i < last.brake.count ? last.brake[i] : 0
            if b > 0.05 {
                stop.addRect(CGRect(x: x(i), y: stripTop, width: barW, height: strip * b))
            } else if t > 0.05 {
                gas.addRect(CGRect(x: x(i), y: stripTop + strip * (1 - t), width: barW, height: strip * t))
            }
        }
        context.fill(gas, with: .color(SR.good.opacity(0.7)))
        context.fill(stop, with: .color(SR.error.opacity(0.75)))

        // Up to five corner names, spaced so they do not collide.
        var lastLabel = -100.0
        for corner in track.corners {
            let cx = corner.distance / length * w
            guard cx - lastLabel > 70 else { continue }
            lastLabel = cx
            let label = Text(corner.name).font(SR.Text.mono(12)).foregroundColor(SR.inkMuted)
            context.draw(label, at: CGPoint(x: min(max(cx, 30), w - 30), y: h - 8), anchor: .center)
        }
    }

    private func trace(_ telemetry: CarProTelemetry, x: (Int) -> Double, y: (Double) -> Double) -> Path {
        var path = Path()
        for (i, v) in telemetry.speeds.enumerated() {
            let p = CGPoint(x: x(i), y: y(v))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

/// The answer to something refused (or done), floating at the top of a page.
struct CarProNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SR.Text.bodyMedium(15))
            .foregroundStyle(SR.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .srGlassCard(.paper, radius: 20)
            .padding(.horizontal, SR.gutter)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A small fact: a label over a figure.
struct CarProFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
            Text(value)
                .font(SR.Text.title(16))
                .monospacedDigit()
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A circuit to pick: its map, name, kind of place and a best time.
struct CarProTrackCard: View {
    let track: CarProTrack
    let selected: Bool
    let best: Double?
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CarProTrackMap(track: track)
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(SR.Text.title(20))
                                .foregroundStyle(Color.white, SR.accent)
                                .padding(6)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name)
                        .font(SR.Text.title(15))
                        .foregroundStyle(SR.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(track.location) · \(CarProFormat.length(track.length))")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(best.map { "Best \(CarProFormat.time($0))" } ?? "No time yet")
                        .font(SR.Text.mono())
                        .foregroundStyle(best == nil ? SR.inkGhost : SR.good)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper, radius: 22, interactive: true)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selected ? SR.accent : Color.clear, lineWidth: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.name), \(track.location), \(CarProFormat.length(track.length))"
                            + (best.map { ", best \(CarProFormat.time($0))" } ?? ""))
        .accessibilityAddTraits(selected ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
        .accessibilityIdentifier("car-pro-track-\(track.id)")
    }
}

/// Every circuit as a card, two to a row (one at the largest text sizes).
struct CarProTrackPicker: View {
    let selected: String
    let best: (CarProTrack) -> Double?
    let pick: (String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns: [GridItem] = typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: SR.cardGap), GridItem(.flexible(), spacing: SR.cardGap)]
        LazyVGrid(columns: columns, spacing: SR.cardGap) {
            ForEach(CarProCircuits.all) { track in
                CarProTrackCard(track: track, selected: track.id == selected, best: best(track)) {
                    pick(track.id)
                }
            }
        }
    }
}

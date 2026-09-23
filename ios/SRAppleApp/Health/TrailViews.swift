import SwiftUI
import MapKit
import Charts

// The parts the activity and segment screens share: rows, a route map, the
// charts, the zone strip, the splits table and the state screens.
//
// Charts follow /health's one-hue rule: the accent line with a 14% accent area
// under it on paper, dashed ghost reference lines, and no second colour unless a
// second MEANING needs one. A heart-rate chart in red beside an elevation chart
// in green is two charts shouting; one hue lets the shape carry it.

// MARK: - Rows

/// One activity in a list.
struct ActivityListRow: View {
    let row: ActivityRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Sport.icon(row.activityType))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(SR.accent)
                .frame(width: 26, height: 26)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !row.summaryLine.isEmpty {
                    Text(row.summaryLine)
                        .font(SR.Text.mono(13))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(row.dateLine.uppercased())
                    .font(SR.Text.mono())
                    .tracking(0.8)
                    .foregroundStyle(SR.inkMuted)
                if let highlight = row.highlight {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "star.fill").font(.system(size: 9, weight: .bold))
                        Text("\(highlight.label) — \(highlight.detail)")
                            .font(SR.Text.secondary(13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(SR.accent)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, SR.rowPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One segment in a list: where it is, how hard, your best, which way it is going.
struct SegmentListRow: View {
    let row: SegmentRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.terrainIcon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SR.accent)
                .frame(width: 26, height: 26)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                // Not the descriptor as well: it is "1.51 km · flat · 31
                // efforts", which is this line again in other words.
                Text(detailLine)
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let form = row.form, form.known, let delta = form.deltaPct {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TrailFormat.signedPercent(delta))
                        .font(SR.Text.mono(13))
                        .foregroundStyle(form.improving ? SR.good : SR.inkSecondary)
                    Text(form.direction.uppercased())
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
            }
        }
        .padding(.vertical, SR.rowPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        var parts = ["\(TrailFormat.km(row.distanceM)) km", "\(row.terrain) \(String(format: "%.1f", row.gradientPct))%"]
        if let best = row.bestDurationS { parts.append("best \(TrailFormat.duration(best))") }
        parts.append(row.effortCount == 1 ? "1 effort" : "\(row.effortCount) efforts")
        return parts.joined(separator: " · ")
    }
}

// MARK: - States

/// Loading, Health down, not found, failed — said the same way on every
/// trails screen, in the app's one empty-state voice.
struct TrailStateView: View {
    let state: TrailLoad
    var noun: String = "activity"
    var retry: (() -> Void)? = nil

    var body: some View {
        switch state {
        case .idle, .loading, .loaded:
            HStack { Spacer(); ProgressView().tint(SR.accent); Spacer() }
                .padding(.vertical, 48)
        case .unavailable:
            SREmpty(
                title: "Health is not answering",
                icon: "heart.slash",
                message: "The health service did not reply. Nothing is lost — try again in a moment.",
                actionLabel: retry == nil ? nil : "Try again",
                action: retry
            )
        case .missing:
            SREmpty(
                title: "No such \(noun)",
                icon: "questionmark.circle",
                message: "It may have been merged or deleted on the website."
            )
        case .failed(let message):
            SREmpty(
                title: "Could not load this",
                icon: "exclamationmark.triangle",
                message: message,
                actionLabel: retry == nil ? nil : "Try again",
                action: retry
            )
        }
    }
}

// MARK: - Map

/// The route, drawn once, not for panning. Tap for a full-screen map that is.
///
/// A draggable map inside a scroll view steals the scroll — the reader goes to
/// flick past it and moves the map instead — so the inline one takes no
/// gestures at all.
struct RouteMap: View {
    let route: [CLLocationCoordinate2D]
    var height: CGFloat = 220
    @State private var expanded = false

    var body: some View {
        RouteMapCanvas(route: route, interactive: false)
            .frame(height: height)
            .allowsHitTesting(false)
            .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
            // A clear button over the whole map, rather than a tap gesture on
            // it: the map is a UIKit view and can swallow a gesture attached
            // to it even with its own interaction switched off.
            .overlay {
                Button {
                    SRHaptic.tap()
                    expanded = true
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Route map")
                .accessibilityHint("Opens the map full screen")
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SR.ink)
                    .frame(width: 30, height: 30)
                    .background(SR.paper)
                    .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
                    .padding(8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .sheet(isPresented: $expanded) {
                NavigationStack {
                    RouteMapCanvas(route: route, interactive: true)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("Route")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { expanded = false }
                            }
                        }
                }
            }
    }
}

struct RouteMapCanvas: View {
    let route: [CLLocationCoordinate2D]
    let interactive: Bool

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: interactive ? MapInteractionModes.all : []) {
            MapPolyline(coordinates: route)
                .stroke(SR.accent, lineWidth: 3.5)
            if let start = route.first {
                Annotation("Start", coordinate: start, anchor: .center) {
                    RouteDot(fill: SR.good)
                }
                .annotationTitles(.hidden)
            }
            if route.count > 1, let finish = route.last {
                Annotation("Finish", coordinate: finish, anchor: .center) {
                    RouteDot(fill: SR.ink)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
    }
}

private struct RouteDot: View {
    let fill: Color

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(SR.paper, lineWidth: 2))
    }
}

// MARK: - Charts

/// Axis furniture in the app's register: hairline grid, mono labels.
private struct SRAxis: ViewModifier {
    func body(content: Content) -> some View {
        content
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(SR.divider)
                    AxisValueLabel().font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(SR.divider)
                    AxisValueLabel().font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                }
            }
    }
}

/// Elevation against distance. x in km, y in metres.
struct ElevationChart: View {
    let points: [ElevationPoint]

    var body: some View {
        let low = points.map(\.e).min() ?? 0
        let high = points.map(\.e).max() ?? 1
        // Pad the floor so a flat route is not drawn as a mountain range: the
        // domain is at least 40 m tall however little the ground moved.
        let span = max(high - low, 40)
        let floor = low - span * 0.1
        let ceiling = low + span * 1.1

        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("km", point.d / 1000),
                    yStart: .value("Floor", floor),
                    yEnd: .value("Elevation", point.e)
                )
                .foregroundStyle(SR.accent.opacity(0.14))
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("km", point.d / 1000),
                    y: .value("Elevation", point.e)
                )
                .foregroundStyle(SR.accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: floor...ceiling)
        .modifier(SRAxis())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elevation profile, \(Int(low.rounded())) to \(Int(high.rounded())) metres")
    }
}

/// Heart rate against time, with the average as a dashed reference.
struct HeartRateChart: View {
    let points: [HeartRatePoint]
    var average: Double? = nil

    var body: some View {
        let low = points.map(\.v).min() ?? 60
        let high = points.map(\.v).max() ?? 180
        let floor = max(0, low - 8)
        let ceiling = high + 6

        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("min", point.t / 60),
                    yStart: .value("Floor", floor),
                    yEnd: .value("bpm", point.v)
                )
                .foregroundStyle(SR.accent.opacity(0.14))
                LineMark(
                    x: .value("min", point.t / 60),
                    y: .value("bpm", point.v)
                )
                .foregroundStyle(SR.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(SR.inkGhost)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartYScale(domain: floor...ceiling)
        .modifier(SRAxis())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate, \(Int(low.rounded())) to \(Int(high.rounded())) beats per minute")
    }
}

/// A segment's efforts over time: every effort as a dot, the running best as a
/// step line under them. Lower is quicker.
struct EffortsChart: View {
    let efforts: [SegmentEffort]

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let seconds: Double
        let best: Double
    }

    var body: some View {
        let points = Self.points(efforts)
        let low = points.map(\.seconds).min() ?? 0
        let high = points.map(\.seconds).max() ?? 1
        let pad = max((high - low) * 0.15, 5)

        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Best", point.best)
                )
                .foregroundStyle(SR.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.stepEnd)
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Time", point.seconds)
                )
                .foregroundStyle(SR.accent.opacity(point.seconds <= point.best ? 1 : 0.4))
                .symbolSize(point.seconds <= point.best ? 48 : 28)
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(SR.divider)
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(SR.divider)
                AxisValueLabel {
                    Text(TrailFormat.duration(value.as(Double.self) ?? 0))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(points.count) efforts, best \(TrailFormat.duration(low))")
    }

    /// Oldest first, with the best-so-far carried along.
    private static func points(_ efforts: [SegmentEffort]) -> [Point] {
        let dated = efforts.compactMap { effort -> (SegmentEffort, Date)? in
            guard effort.durationS > 0, let date = isoDate(effort.startedAt) else { return nil }
            return (effort, date)
        }
        .sorted { $0.1 < $1.1 }
        var best = Double.infinity
        return dated.map { effort, date in
            best = min(best, effort.durationS)
            return Point(id: effort.id, date: date, seconds: effort.durationS, best: best)
        }
    }
}

// MARK: - Heart-rate zones

/// Time in each zone as one strip — a single-hue ramp, not a rainbow.
///
/// /health's ramp: the easy zones are ink tints, the working zones step up the
/// accent, and zone 5 is solid ink because it is off the top of the scale —
/// the one place a reader should see a hard stop rather than more orange.
struct ZoneStrip: View {
    let zones: [HeartRateZone]

    static func colour(_ zone: Int) -> Color {
        switch zone {
        case 0: return SR.ink.opacity(0.12)
        case 1: return SR.ink.opacity(0.20)
        case 2: return SR.accent.opacity(0.28)
        case 3: return SR.accent.opacity(0.50)
        case 4: return SR.accent
        default: return SR.ink
        }
    }

    var body: some View {
        let sorted = zones.sorted { $0.zone < $1.zone }
        let total = max(sorted.reduce(0) { $0 + $1.seconds }, 1)

        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(sorted) { zone in
                        Rectangle()
                            .fill(Self.colour(zone.zone))
                            .frame(width: max(0, geo.size.width * zone.seconds / total - 1))
                    }
                }
            }
            .frame(height: 18)

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(sorted) { zone in
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(Self.colour(zone.zone))
                            .frame(width: 10, height: 10)
                            .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 0.5))
                        Text("Z\(zone.zone) \(TrailFormat.minutes(Int((zone.seconds / 60).rounded())))")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sorted.map { "Zone \($0.zone), \(Int(($0.seconds / 60).rounded())) minutes" }.joined(separator: ", "))
    }
}

// MARK: - Splits

/// Per-kilometre splits. The quickest is marked, because that is the question a
/// splits table is read for.
struct SplitsTable: View {
    let splits: [ActivitySplit]
    let activityType: String

    var body: some View {
        let pace = Sport.isPace(activityType)
        let quickest = splits.filter { $0.distanceM >= 900 }.compactMap(\.paceSPerKm).filter { $0 > 0 }.min()

        VStack(spacing: 0) {
            SplitLine(cells: ["KM", "TIME", pace ? "PACE" : "KM/H", "↑ M"], header: true, lit: false)
            ForEach(Array(splits.enumerated()), id: \.offset) { index, split in
                SplitLine(
                    cells: Self.cells(split, index: index, pace: pace),
                    header: false,
                    lit: split.paceSPerKm != nil && split.paceSPerKm == quickest
                )
            }
        }
        .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
    }

    /// The last split is usually a part-kilometre, and is labelled by its
    /// length rather than as another whole one.
    static func cells(_ split: ActivitySplit, index: Int, pace: Bool) -> [String] {
        let label = split.distanceM < 950 ? TrailFormat.km(split.distanceM) : "\(index + 1)"
        var rate = "—"
        if let value = split.paceSPerKm, value > 0 {
            rate = pace ? TrailFormat.pace(value) : TrailFormat.speed(paceSPerKm: value)
        }
        let climb = split.elevationGainM.map { TrailFormat.metres($0) } ?? "—"
        return [label, TrailFormat.duration(split.durationS), rate, climb]
    }
}

private struct SplitLine: View {
    let cells: [String]
    let header: Bool
    let lit: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(cell)
                    .font(header ? SR.Text.label() : SR.Text.mono(14))
                    .tracking(header ? 1.2 : 0)
                    .foregroundStyle(header ? SR.inkMuted : (lit && index == 2 ? SR.accent : SR.ink))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, header ? 8 : 9)
        .background(header ? SR.surface : (lit ? SR.accent.opacity(0.08) : Color.clear))
        .overlay(alignment: .bottom) {
            Rectangle().fill(SR.divider).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Paper section head

/// A section on a detail screen: the mono label, then its content.
struct TrailSection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: title, trailing: trailing)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

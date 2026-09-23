import SwiftUI
import MapKit

// Activities and segments, pushed onto the Health tab's stack.
//
// Every screen here is reached by a value — `ActivityRef`, `SegmentRef`,
// `HealthRoute` — registered once on `HealthScreen`, so an activity can open a
// segment which can open another activity without any of them knowing about
// the others' views. The ref carries the name so the title paints before the
// detail arrives.

// MARK: - All activities

struct ActivitiesScreen: View {
    @StateObject private var store = ActivitiesStore(pageSize: 30)

    var body: some View {
        List {
            if store.rows.isEmpty {
                if store.state == .loaded {
                    SREmpty(
                        title: "No activities yet",
                        icon: "figure.walk",
                        message: "Workouts appear here once Apple Health or Strava has sent them to the site."
                    )
                    .srPlainRow()
                    .listRowSeparator(.hidden)
                } else {
                    TrailStateView(state: store.state, retry: reload)
                        .srPlainRow()
                        .listRowSeparator(.hidden)
                }
            } else {
                ForEach(store.rows) { row in
                    NavigationLink(value: ActivityRef(id: row.id, name: row.name)) {
                        ActivityListRow(row: row)
                    }
                    .srPlainRow()
                    .onAppear {
                        // The list continuing is what every iPhone list does; a
                        // "More" button at the end is a control you have to find.
                        if row.id == store.rows.last?.id { Task { await store.loadMore() } }
                    }
                }
                if store.loadingMore {
                    HStack { Spacer(); ProgressView().tint(SR.accent); Spacer() }
                        .srPlainRow()
                        .padding(.vertical, 12)
                }
            }
        }
        .listStyle(.plain)
        .srPaper()
        .navigationTitle("Activities")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: HealthRoute.segments) {
                    Text("SEGMENTS").font(SR.Text.label()).tracking(1.1)
                }
            }
        }
        .srRefreshable { await store.load() }
        .task { if store.rows.isEmpty { await store.load() } }
    }

    private func reload() {
        Task { await store.load() }
    }
}

// MARK: - Segments

struct SegmentsScreen: View {
    @StateObject private var store = SegmentsStore()

    var body: some View {
        List {
            if store.rows.isEmpty {
                if store.state == .loaded {
                    SREmpty(
                        title: "No segments yet",
                        icon: "flag.checkered",
                        message: "A segment appears once the same stretch has been covered more than once."
                    )
                    .srPlainRow()
                    .listRowSeparator(.hidden)
                } else {
                    TrailStateView(state: store.state, noun: "segment", retry: reload)
                        .srPlainRow()
                        .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(store.rows) { row in
                        NavigationLink(value: SegmentRef(id: row.id, name: row.name)) {
                            SegmentListRow(row: row)
                        }
                        .srPlainRow()
                    }
                } header: {
                    SRSectionLabel(text: "Most recently covered", trailing: "\(store.rows.count)")
                        .srPlainRow()
                        .padding(.vertical, 6)
                }
            }
        }
        .listStyle(.plain)
        .srPaper()
        .navigationTitle("Segments")
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable { await store.load() }
        .task { if store.rows.isEmpty { await store.load() } }
    }

    private func reload() {
        Task { await store.load() }
    }
}

// MARK: - One activity

struct ActivityDetailScreen: View {
    let ref: ActivityRef
    @StateObject private var store = ActivityDetailStore()

    var body: some View {
        Group {
            if let detail = store.detail {
                ActivityDetailBody(detail: detail)
            } else {
                ScrollView {
                    TrailStateView(state: store.state, retry: reload)
                        .padding(.top, 40)
                }
            }
        }
        .srPaper()
        .navigationTitle(ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable { await store.load(ref.id) }
        .task { if store.detail == nil { await store.load(ref.id) } }
    }

    private func reload() {
        Task { await store.load(ref.id) }
    }
}

/// The activity itself, separate from its loading so it can be drawn from a
/// decoded sample — which is how the unit tests photograph it.
struct ActivityDetailBody: View {
    let detail: ActivityDetailResponse
    /// A long walk can carry fourteen highlights. Four, then the rest on ask.
    @State private var allHighlights = false

    private var activity: ActivityDetail { detail.activity }
    private var row: ActivityRow { detail.activity.row }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ActivityHero(detail: activity)
                VStack(alignment: .leading, spacing: 30) {
                    if !activity.route.isEmpty {
                        RouteMap(route: activity.route)
                    }
                    if !detail.highlights.isEmpty {
                        highlights
                    }
                    if activity.elevation.count > 1 {
                        TrailSection(title: "Elevation", trailing: elevationTrailing) {
                            ElevationChart(points: activity.elevation).frame(height: 150)
                        }
                    }
                    if activity.heartRate.count > 1 {
                        TrailSection(title: "Heart rate", trailing: heartTrailing) {
                            HeartRateChart(points: activity.heartRate, average: row.avgHeartrate).frame(height: 150)
                        }
                    }
                    if let zones = detail.physio?.zones, zones.contains(where: { $0.seconds > 0 }) {
                        TrailSection(title: "Time in zone") {
                            ZoneStrip(zones: zones)
                        }
                    }
                    if !activity.splits.isEmpty {
                        TrailSection(title: "Splits", trailing: "\(activity.splits.count)") {
                            SplitsTable(splits: activity.splits, activityType: row.activityType)
                        }
                    }
                    if !detail.segments.isEmpty {
                        segments
                    }
                    if let physio = detail.physio, !load(physio).isEmpty {
                        TrailSection(title: "Load") {
                            SRTileGrid {
                                ForEach(load(physio), id: \.label) { tile in
                                    SRStatTile(value: tile.value, unit: tile.unit, label: tile.label, caption: tile.caption)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 24)
                .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .srPaper()
    }

    private var elevationTrailing: String? {
        guard let gain = row.elevationGainM else { return nil }
        let loss = activity.elevationLossM.map { " ↓\(TrailFormat.metres($0))" } ?? ""
        return "↑\(TrailFormat.metres(gain))\(loss) m"
    }

    private var heartTrailing: String? {
        guard let avg = row.avgHeartrate else { return nil }
        guard let peak = activity.maxHeartrate else { return "avg \(Int(avg.rounded()))" }
        return "avg \(Int(avg.rounded())) · max \(Int(peak.rounded()))"
    }

    private var highlights: some View {
        TrailSection(title: "Highlights", trailing: "\(detail.highlights.count)") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(shownHighlights.enumerated()), id: \.offset) { _, highlight in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(SR.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(highlight.label)
                                .font(SR.Text.bodyMedium(15))
                                .foregroundStyle(SR.ink)
                            Text(highlight.detail)
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if detail.highlights.count > Self.highlightLimit {
                    ShowAllButton(expanded: $allHighlights, total: detail.highlights.count)
                }
            }
        }
    }

    static let highlightLimit = 4

    private var shownHighlights: [ActivityHighlight] {
        allHighlights ? detail.highlights : Array(detail.highlights.prefix(Self.highlightLimit))
    }

    private var segments: some View {
        TrailSection(title: "Segments", trailing: "\(detail.segments.count)") {
            SRLedger {
                ForEach(detail.segments) { effort in
                    NavigationLink(value: SegmentRef(id: effort.segmentId, name: effort.name)) {
                        ActivitySegmentLine(effort: effort, pace: Sport.isPace(row.activityType))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private struct LoadTile {
        let label: String
        let value: String
        let unit: String?
        let caption: String
    }

    private func load(_ physio: ActivityPhysio) -> [LoadTile] {
        var tiles: [LoadTile] = []
        if let trimp = physio.trimp {
            tiles.append(LoadTile(label: "TRIMP", value: "\(Int(trimp.rounded()))", unit: nil, caption: "training load"))
        }
        if let ef = physio.efficiencyFactor {
            tiles.append(LoadTile(label: "Efficiency", value: String(format: "%.2f", ef), unit: nil, caption: "speed per beat"))
        }
        if let drift = physio.decouplingPct {
            tiles.append(LoadTile(label: "Decoupling", value: String(format: "%.1f", drift), unit: "%", caption: "HR drift"))
        }
        if let hrr = physio.hrr60 {
            tiles.append(LoadTile(label: "HRR 60s", value: "\(Int(hrr.rounded()))", unit: "bpm", caption: "recovery"))
        }
        return tiles
    }
}

/// The ink hero at the top of an activity.
struct ActivityHero: View {
    let detail: ActivityDetail

    private var row: ActivityRow { detail.row }

    var body: some View {
        SRInkBand(kicker: kicker) {
            VStack(alignment: .leading, spacing: 8) {
                SRInkTitle(text: row.name, size: 32)
                Text(row.dateLine)
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.onInk(.date))
            }
            SRInkCellGrid(figures: Self.figures(row))
            if let highlight = row.highlight {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SR.accentOnDark)
                    Text("\(highlight.label) — \(highlight.detail)")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.onInk(.note))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var kicker: String {
        let source = Self.sourceLabel(detail.source, id: row.id)
        return source.isEmpty ? Sport.label(row.activityType) : "\(Sport.label(row.activityType)) · \(source)"
    }

    static func sourceLabel(_ source: String?, id: String) -> String {
        let raw = (source?.isEmpty == false ? source! : String(id.split(separator: ":").first ?? "")).lowercased()
        switch raw {
        case "apple", "apple_health", "healthkit", "hae": return "Apple Health"
        case "strava": return "Strava"
        case "": return ""
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Distance lit, because it is the figure the activity is remembered by.
    static func figures(_ row: ActivityRow) -> [SRInkFigure] {
        var figures: [SRInkFigure] = []
        if let distance = row.distanceM, distance > 0 {
            figures.append(SRInkFigure(label: "Distance", value: TrailFormat.km(distance), unit: "km", lit: true))
        }
        figures.append(SRInkFigure(label: row.movingS == nil ? "Time" : "Moving", value: TrailFormat.duration(row.timeS)))
        if let pace = row.paceSPerKm, pace > 0 {
            figures.append(Sport.isPace(row.activityType)
                ? SRInkFigure(label: "Pace", value: TrailFormat.pace(pace), unit: "/km")
                : SRInkFigure(label: "Speed", value: TrailFormat.speed(paceSPerKm: pace), unit: "km/h"))
        }
        if let gain = row.elevationGainM {
            figures.append(SRInkFigure(label: "Climb", value: TrailFormat.metres(gain), unit: "m"))
        }
        if let hr = row.avgHeartrate, hr > 0 {
            figures.append(SRInkFigure(label: "Avg HR", value: "\(Int(hr.rounded()))", unit: "bpm"))
        }
        if let kcal = row.energyKcal, kcal > 0 {
            figures.append(SRInkFigure(label: "Energy", value: "\(Int(kcal.rounded()))", unit: "kcal"))
        }
        return figures
    }
}

/// A segment as covered in this activity: its time, and where that time ranks.
private struct ActivitySegmentLine: View {
    let effort: ActivitySegmentEffort
    let pace: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(effort.name)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subline)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(TrailFormat.duration(effort.durationS))
                    .font(SR.Text.mono(15))
                    .foregroundStyle(SR.ink)
                if let rank = effort.rankLine {
                    Text(rank.uppercased())
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(effort.rankByTime == 1 ? SR.accent : SR.inkMuted)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SR.inkGhost)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: SR.tapTarget)
        .background(SR.paper)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subline: String {
        var parts = ["\(TrailFormat.km(effort.distanceM)) km"]
        if let value = effort.paceSPerKm, value > 0 {
            parts.append(pace ? "\(TrailFormat.pace(value)) /km" : "\(TrailFormat.speed(paceSPerKm: value)) km/h")
        }
        if let hr = effort.avgHeartrate, hr > 0 { parts.append("\(Int(hr.rounded())) bpm") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - One segment

struct SegmentDetailScreen: View {
    let ref: SegmentRef
    @StateObject private var store = SegmentDetailStore()

    var body: some View {
        Group {
            if let detail = store.detail {
                SegmentDetailBody(detail: detail)
            } else {
                ScrollView {
                    TrailStateView(state: store.state, noun: "segment", retry: reload)
                        .padding(.top, 40)
                }
            }
        }
        .srPaper()
        .navigationTitle(ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable { await store.load(ref.id) }
        .task { if store.detail == nil { await store.load(ref.id) } }
    }

    private func reload() {
        Task { await store.load(ref.id) }
    }
}

struct SegmentDetailBody: View {
    let detail: SegmentDetailResponse
    /// A well-used segment has a hundred efforts. The latest dozen, then the
    /// rest on ask — the chart above already shows the whole history.
    @State private var allEfforts = false

    static let effortLimit = 12

    private var segment: SegmentRow { detail.segment.row }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SegmentHero(detail: detail.segment, efforts: detail.efforts.count)
                VStack(alignment: .leading, spacing: 30) {
                    if !detail.segment.route.isEmpty {
                        RouteMap(route: detail.segment.route, height: 200)
                    }
                    if detail.efforts.count > 1 {
                        TrailSection(title: "Efforts over time", trailing: "lower is quicker") {
                            EffortsChart(efforts: detail.efforts).frame(height: 160)
                        }
                    }
                    if let conditions = detail.segment.conditions, let line = Self.conditionsLine(conditions) {
                        TrailSection(title: "Conditions") {
                            Text(line)
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !detail.efforts.isEmpty {
                        TrailSection(title: "Efforts", trailing: "newest first") {
                            SRLedger {
                                ForEach(allEfforts ? detail.efforts : Array(detail.efforts.prefix(Self.effortLimit))) { effort in
                                    NavigationLink(value: ActivityRef(id: effort.activityId, name: effort.activityName)) {
                                        SegmentEffortLine(effort: effort, pace: Sport.isPace(segment.activityType))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(effort.activityId.isEmpty)
                                }
                            }
                            if detail.efforts.count > Self.effortLimit {
                                ShowAllButton(expanded: $allEfforts, total: detail.efforts.count)
                            }
                        }
                    }
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 24)
                .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .srPaper()
    }

    static func conditionsLine(_ c: SegmentConditions) -> String? {
        var parts: [String] = []
        if let mean = c.meanC { parts.append("Usually \(Int(mean.rounded()))°C") }
        if let quickest = c.quickestC { parts.append("quickest at \(Int(quickest.rounded()))°C") }
        if let slowest = c.slowestC { parts.append("slowest at \(Int(slowest.rounded()))°C") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ") + "."
    }
}

struct SegmentHero: View {
    let detail: SegmentDetail
    let efforts: Int

    private var row: SegmentRow { detail.row }

    var body: some View {
        SRInkBand(kicker: "\(row.terrain) · \(Sport.label(row.activityType))") {
            VStack(alignment: .leading, spacing: 8) {
                SRInkTitle(text: row.name, size: 30)
                if !row.descriptor.isEmpty {
                    Text(row.descriptor)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.onInk(.note))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let last = row.lastEffortAt, !TrailFormat.day(last).isEmpty {
                    Text("LAST \(TrailFormat.day(last).uppercased())")
                        .font(SR.Text.mono())
                        .tracking(1)
                        .foregroundStyle(SR.onInk(.date))
                }
            }
            SRInkCellGrid(figures: Self.figures(row, efforts: max(efforts, row.effortCount)))
        }
    }

    /// Best time lit: on a segment, that is the number.
    static func figures(_ row: SegmentRow, efforts: Int) -> [SRInkFigure] {
        var figures: [SRInkFigure] = [
            SRInkFigure(label: "Distance", value: TrailFormat.km(row.distanceM), unit: "km"),
            SRInkFigure(label: "Gradient", value: String(format: "%.1f", row.gradientPct), unit: "%"),
            SRInkFigure(label: "Climb", value: TrailFormat.metres(row.elevationGainM), unit: "m"),
        ]
        if let best = row.bestDurationS {
            figures.append(SRInkFigure(label: "Best", value: TrailFormat.duration(best), lit: true))
        }
        figures.append(SRInkFigure(label: "Efforts", value: "\(efforts)"))
        if let form = row.form, form.known, let delta = form.deltaPct {
            figures.append(SRInkFigure(label: "Form · \(form.direction)", value: TrailFormat.signedPercent(delta)))
        }
        return figures
    }
}

private struct SegmentEffortLine: View {
    let effort: SegmentEffort
    let pace: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(effort.activityName)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(subline)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(TrailFormat.duration(effort.durationS))
                    .font(SR.Text.mono(15))
                    .foregroundStyle(effort.isBest ? SR.accent : SR.ink)
                if effort.isBest {
                    Text("BEST")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.accent)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SR.inkGhost)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: SR.tapTarget)
        // Opaque: the ledger's hairlines are its background showing through
        // the gaps, so a translucent row would be tinted by them.
        .background {
            ZStack {
                SR.paper
                if effort.isBest { SR.accent.opacity(0.06) }
            }
        }
        .overlay(alignment: .leading) {
            if effort.isBest { Rectangle().fill(SR.accent).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subline: String {
        var parts = [TrailFormat.day(effort.startedAt)]
        if let value = effort.paceSPerKm, value > 0 {
            parts.append(pace ? "\(TrailFormat.pace(value)) /km" : "\(TrailFormat.speed(paceSPerKm: value)) km/h")
        }
        if let hr = effort.avgHeartrate, hr > 0 { parts.append("\(Int(hr.rounded())) bpm") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// "Show all 14" / "Show fewer" under a clipped list.
private struct ShowAllButton: View {
    @Binding var expanded: Bool
    let total: Int

    var body: some View {
        Button {
            SRHaptic.tap()
            expanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(expanded ? "SHOW FEWER" : "SHOW ALL \(total)")
                    .font(SR.Text.label())
                    .tracking(1.2)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(SR.accent)
            .frame(minHeight: SR.tapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

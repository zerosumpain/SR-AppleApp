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

/// The whole history, with the week as its headline.
///
/// Read top down it answers three questions in the order they get asked: how
/// has this week gone (the band), what are my bests (the records, sideways),
/// and what did I do (the history, by month — "September · 12 · 84 km" is how
/// anybody remembers a training log, and a flat list of sixty rows is not).
/// The sport chips only appear when there is more than one sport to choose.
struct ActivitiesScreen: View {
    /// The summary's week and records — the tab's, handed down, so the band
    /// is drawn by the same numbers the tab's tile quoted.
    var week: HealthWeek? = nil
    var records: [HealthRecordHighlight] = []
    @StateObject private var store = ActivitiesStore(pageSize: 30)
    @State private var sport: String?

    var body: some View {
        List {
            if week != nil || !store.rows.isEmpty {
                ActivitiesWeekBand(week: week, days: ActivityWeekDay.lastSeven(store.rows))
                    .srInkRow()
            }
            if !records.isEmpty {
                Section {
                    RecordsStrip(records: records)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    SRSectionLabel(text: "Personal records")
                }
            }

            if store.rows.isEmpty {
                if store.state == .loaded {
                    SREmpty(
                        title: "No activities yet",
                        icon: "figure.walk",
                        message: "Workouts appear here once Apple Health has sent them to the site."
                    )
                    .srBareRow()
                } else {
                    TrailStateView(state: store.state, retry: reload)
                        .srBareRow()
                }
            } else {
                if sportChips.count > 2 {
                    HealthChips(chips: sportChips, selection: $sport)
                        .srBareRow()
                }
                ForEach(months) { month in
                    Section {
                        ForEach(month.rows) { row in
                            NavigationLink(value: ActivityRef(id: row.id, name: row.name)) {
                                ActivityListRow(row: row)
                            }
                            .srGlassRow()
                            .onAppear {
                                // The list continuing is what every iPhone list does; a
                                // "More" button at the end is a control you have to find.
                                if row.id == filtered.last?.id { Task { await store.loadMore() } }
                            }
                        }
                    } header: {
                        SRSectionLabel(text: ActivityDay.month(month.key), trailing: monthTotal(month))
                    }
                }
                if filtered.isEmpty {
                    if store.hasMore {
                        // No row of this sport in what has loaded, so no row
                        // appears to ask for the next page: this does instead.
                        HStack { Spacer(); ProgressView().tint(SR.accent); Spacer() }
                            .srBareRow()
                            .padding(.vertical, 12)
                            .onAppear { Task { await store.loadMore() } }
                    } else {
                        Text("Nothing in this sport yet.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .srBareRow()
                    }
                } else if store.loadingMore {
                    HStack { Spacer(); ProgressView().tint(SR.accent); Spacer() }
                        .srBareRow()
                        .padding(.vertical, 12)
                }
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.vital)
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

    // MARK: Filtering and grouping

    private var filtered: [ActivityRow] {
        guard let sport else { return store.rows }
        return store.rows.filter { Sport.key($0.activityType) == sport }
    }

    /// "All", then each sport by how often it is done.
    private var sportChips: [HealthChip] {
        let counts = Dictionary(grouping: store.rows, by: { Sport.key($0.activityType) }).mapValues(\.count)
        let sports = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        return [HealthChip(key: nil, label: "All", count: store.rows.count)]
            + sports.map { HealthChip(key: $0.key, label: Sport.label($0.key), count: $0.value) }
    }

    private struct Month: Identifiable {
        let key: String
        var rows: [ActivityRow]
        var id: String { key }
    }

    /// Consecutive rows by the month they were lived in. The rows arrive
    /// newest first, so this keeps their order.
    private var months: [Month] {
        var out: [Month] = []
        for row in filtered {
            let key = ActivityDay.key(row).map { String($0.prefix(7)) } ?? "earlier"
            if out.last?.key == key {
                out[out.count - 1].rows.append(row)
            } else {
                out.append(Month(key: key, rows: [row]))
            }
        }
        return out
    }

    /// "12 · 84.2 km" — but not on the last month while older pages are still
    /// to come: a half-loaded month's total would be a wrong number, said
    /// confidently.
    private func monthTotal(_ month: Month) -> String? {
        if store.hasMore && month.id == months.last?.id { return nil }
        let km = month.rows.compactMap(\.distanceM).reduce(0, +)
        let count = "\(month.rows.count)"
        return km > 0 ? "\(count) · \(TrailFormat.km(km)) km" : count
    }
}

// MARK: - Segments

/// Every stretch covered more than once, with form as the headline.
///
/// The band says which way things are going; "Within reach" is the question
/// the reader actually brings to this screen — where is a best gettable — as
/// /health answered it; then the list, filterable by form.
struct SegmentsScreen: View {
    /// /health's gettable bests, from the tab's digest. Matched to rows by
    /// name, so one the list does not carry still shows, just without a push.
    var gettable: [HubDigest.Segments.Gettable] = []
    @StateObject private var store = SegmentsStore()
    @State private var form: String?

    var body: some View {
        List {
            if store.rows.isEmpty {
                if store.state == .loaded {
                    SREmpty(
                        title: "No segments yet",
                        icon: "flag.checkered",
                        message: "A segment appears once the same stretch has been covered more than once."
                    )
                    .srBareRow()
                } else {
                    TrailStateView(state: store.state, noun: "segment", retry: reload)
                        .srBareRow()
                }
            } else {
                SegmentsFormBand(rows: store.rows).srInkRow()

                if !gettable.isEmpty {
                    Section {
                        ForEach(gettable) { near in
                            if let row = store.rows.first(where: { $0.name == near.name }) {
                                NavigationLink(value: SegmentRef(id: row.id, name: row.name)) {
                                    WithinReachRow(gettable: near)
                                }
                                .srGlassRow()
                            } else {
                                WithinReachRow(gettable: near).srGlassRow()
                            }
                        }
                    } header: {
                        SRSectionLabel(text: "Within reach", trailing: "a best is gettable")
                    }
                }

                if formChips.count > 2 {
                    HealthChips(chips: formChips, selection: $form)
                        .srBareRow()
                }
                Section {
                    if filtered.isEmpty {
                        Text("None \(form ?? "") right now.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .srGlassRow()
                    }
                    ForEach(filtered) { row in
                        NavigationLink(value: SegmentRef(id: row.id, name: row.name)) {
                            SegmentListRow(row: row)
                        }
                        .srGlassRow()
                    }
                } header: {
                    SRSectionLabel(text: "Most recently covered", trailing: "\(filtered.count)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.vital)
        .navigationTitle("Segments")
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable { await store.load() }
        .task { if store.rows.isEmpty { await store.load() } }
    }

    private func reload() {
        Task { await store.load() }
    }

    private var filtered: [SegmentRow] {
        guard let form else { return store.rows }
        return store.rows.filter { ($0.form?.direction ?? "unknown") == form }
    }

    /// "All", then the three directions that have any segments in them.
    private var formChips: [HealthChip] {
        let all = HealthChip(key: nil, label: "All", count: store.rows.count)
        let directions = ["improving", "holding", "slipping"].compactMap { direction -> HealthChip? in
            let count = store.rows.filter { $0.form?.direction == direction }.count
            return count == 0 ? nil : HealthChip(key: direction, label: direction.capitalized, count: count)
        }
        return [all] + directions
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
                // In the order the outing is remembered: where it went and
                // its shape, what stood out (highlights, then segments — a PB
                // is the thing anybody opens a run to see), how hard it was,
                // and last the kilometre-by-kilometre detail, which is long
                // and read least.
                VStack(alignment: .leading, spacing: 30) {
                    if !row.origin.isEmpty {
                        ActivityOriginNote(row: row)
                    }
                    if !activity.route.isEmpty {
                        RouteMap(route: activity.route)
                    }
                    if activity.elevation.count > 1 {
                        TrailSection(title: "Elevation", trailing: elevationTrailing) {
                            ElevationChart(points: activity.elevation).frame(height: 150)
                        }
                    }
                    if !detail.highlights.isEmpty {
                        highlights
                    }
                    if !detail.segments.isEmpty {
                        segments
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
                    if let physio = detail.physio, !load(physio).isEmpty {
                        TrailSection(title: "Load") {
                            SRTileGrid {
                                ForEach(load(physio), id: \.label) { tile in
                                    SRStatTile(value: tile.value, unit: tile.unit, label: tile.label, caption: tile.caption)
                                }
                            }
                        }
                    }
                    if !activity.splits.isEmpty {
                        TrailSection(title: "Splits", trailing: "\(activity.splits.count)") {
                            SplitsTable(splits: activity.splits, activityType: row.activityType)
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

    /// "3 · 1 PB" — the PB count is why anybody reads this section.
    private var segmentsTrailing: String {
        let pbs = detail.segments.filter { $0.rankByTime == 1 && $0.rankedByTimeOf > 1 }.count
        return pbs == 0 ? "\(detail.segments.count)" : "\(detail.segments.count) · \(pbs) PB"
    }

    private var shownHighlights: [ActivityHighlight] {
        allHighlights ? detail.highlights : Array(detail.highlights.prefix(Self.highlightLimit))
    }

    private var segments: some View {
        TrailSection(title: "Segments", trailing: segmentsTrailing) {
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
        let source = ActivityOrigin.label(row.origin)
        return source.isEmpty ? Sport.label(row.activityType) : "\(Sport.label(row.activityType)) · \(source)"
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

/// Where this activity came from, and what that means for its figures.
///
/// Directly under the hero rather than at the foot: for an outing the SR app
/// captured, "the type is a guess and there is no elevation" is how the
/// numbers above it should be read, so it belongs next to them.
struct ActivityOriginNote: View {
    let row: ActivityRow

    var body: some View {
        TrailSection(title: "Source") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: ActivityOrigin.icon(row.origin))
                    .font(SR.Text.label(13))
                    .foregroundStyle(SR.accent)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ActivityOrigin.label(row.origin))
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.ink)
                    ForEach(Self.sentences(row), id: \.self) { sentence in
                        Text(sentence)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// What the origin means, then why a duplicate is missing, if one is.
    static func sentences(_ row: ActivityRow) -> [String] {
        [
            ActivityOrigin.explanation(row.origin),
            ActivityOrigin.foldedNote(row.origin, alsoFrom: row.alsoFrom),
        ].compactMap { $0 }
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
                    .foregroundStyle(best ? SR.accent : SR.ink)
                if let rank = effort.rankLine {
                    Text(rank.uppercased())
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(best ? SR.accent : SR.inkMuted)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SR.inkGhost)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: SR.tapTarget)
        // The same mark a best effort carries on the segment's own screen:
        // a PB looks like a PB wherever it is seen.
        .background {
            ZStack {
                SR.paper
                if best { SR.accent.opacity(0.06) }
            }
        }
        .overlay(alignment: .leading) {
            if best { Rectangle().fill(SR.accent).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var best: Bool { effort.rankByTime == 1 && effort.rankedByTimeOf > 1 }

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

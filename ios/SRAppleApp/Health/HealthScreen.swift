import SwiftUI
import MapKit

/// The health tab.
///
/// /health has nine sections and is read top to bottom at a desk. A phone is
/// opened for one question — "how am I doing" — so the order here is the
/// answer, then the evidence, then everything else: readiness, four figures,
/// the week, the records, and then the things only this app knows, which are
/// what the phone uploaded and where the family is.
struct HealthScreen: View {
    @ObservedObject var companion: Companion
    @StateObject private var store = HealthStore()
    /// The latest few activities. The full history is its own screen.
    @StateObject private var recent = ActivitiesStore(pageSize: 5)
    @EnvironmentObject private var router: Router

    var body: some View {
        List {
            SRPageHeader(kicker: "Body · \(Date().formatted(.dateTime.weekday(.wide)))", title: "Health")
                .srBareRow()
            if let summary = store.summary {
                // The ink band: readiness and today's figures, /health's hero.
                HealthHero(summary: summary).srInkRow()
                recentActivities
                if let week = summary.week { weekSection(week) }
                if !summary.records.isEmpty { records(summary.records) }
            } else if store.unavailable {
                SREmpty(
                    title: "Health is not answering",
                    icon: "heart.slash",
                    message: "The health service did not reply. Your uploaded records are still here.",
                    actionLabel: "Try again",
                    action: reload
                )
                .srBareRow()
            } else if store.loading {
                HStack { Spacer(); ProgressView().tint(SR.accent); Spacer() }
                    .padding(.vertical, 40)
                    .srBareRow()
            }

            if store.summary == nil { recentActivities }
            uploaded
            family
        }
        .listStyle(.insetGrouped)
        .srGround(.vital)
        .navigationTitle("Health")
        // Inline, not large. A large title renders BLANK on this OS with this
        // appearance proxy — the bar lays out at full height and paints no text.
        // Verified in CI screenshots; inline titles in the same build draw in
        // Archivo Black correctly. A compact bar also gives a list more of the
        // screen, which on a phone is the thing actually being asked for.
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable {
            await store.load(fresh: true)
            await recent.load()
            try? await companion.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .principal) { SRBarMark() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.openSettings(.health) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Health settings")
            }
        }
        .navigationDestination(for: HealthFigure.self) { FigureDetail(figure: $0) }
        // Every trails screen is pushed by value onto THIS stack, so an activity
        // can open a segment that opens another activity, and each is one swipe
        // back. Registered once, here, at the root.
        .navigationDestination(for: ActivityRef.self) { ActivityDetailScreen(ref: $0) }
        .navigationDestination(for: SegmentRef.self) { SegmentDetailScreen(ref: $0) }
        .navigationDestination(for: HealthRoute.self) { route in
            switch route {
            case .activities: ActivitiesScreen()
            case .segments: SegmentsScreen()
            }
        }
        .task {
            await store.load()
            if recent.rows.isEmpty { await recent.load() }
        }
    }

    /// See `ThreadListScreen.startThread` — a closure that is only a `Task`
    /// infers `Task<(), Never>` as its return type, and coercing that into an
    /// action tuple crashes the type checker.
    private func reload() {
        Task { await store.load(fresh: true) }
    }

    // MARK: - Sections

    /// The latest activities, each a push to its detail, then the way into
    /// the whole history and the segments.
    ///
    /// Shown only once the store has tried: an unpaired phone has nothing to
    /// ask, and an empty "Recent activities" header over nothing reads as a
    /// fault.
    @ViewBuilder
    private var recentActivities: some View {
        if recent.state != .idle || !recent.rows.isEmpty {
            Section {
                if recent.rows.isEmpty {
                    Text(recentEmptyLine)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .srGlassRow()
                        .padding(.vertical, 10)
                } else {
                    ForEach(recent.rows.prefix(5)) { row in
                        NavigationLink(value: ActivityRef(id: row.id, name: row.name)) {
                            ActivityListRow(row: row)
                        }
                        .srGlassRow()
                    }
                }
                NavigationLink(value: HealthRoute.activities) {
                    SRRow(title: "All activities", icon: "list.bullet")
                }
                .srGlassRow()
                .accessibilityIdentifier("health-all-activities")
                NavigationLink(value: HealthRoute.segments) {
                    SRRow(title: "Segments", icon: "flag.checkered")
                }
                .srGlassRow()
                .accessibilityIdentifier("health-segments")
            } header: {
                SRSectionLabel(text: "Recent activities")
            }
        }
    }

    private var recentEmptyLine: String {
        switch recent.state {
        case .loading, .idle: return "Loading activities…"
        case .loaded: return "No activities yet."
        case .unavailable: return "Health is not answering. Pull to try again."
        case .missing, .failed: return "Activities could not be loaded."
        }
    }

    @ViewBuilder
    private func weekSection(_ week: HealthWeek) -> some View {
        Section {
            SRTileGrid {
                // Each opens the activities that add up to it.
                SRStatTile(value: "\(week.activities)", label: "Activities", caption: "7 days", onTap: openActivities)
                SRStatTile(value: TrailFormat.km(fromKm: week.distanceKm), unit: "km", label: "Distance", caption: "7 days", onTap: openActivities)
                SRStatTile(value: TrailFormat.minutes(week.durationMinutes), label: "Moving", caption: "7 days", onTap: openActivities)
                SRStatTile(value: "\(week.elevationM)", unit: "m", label: "Climbed", caption: "7 days", onTap: openActivities)
            }
            .srBareRow()
        } header: {
            SRSectionLabel(text: "This week")
        }
    }

    @ViewBuilder
    private func records(_ records: [HealthRecordHighlight]) -> some View {
        Section {
            ForEach(records) { record in
                SRRow(title: record.label, subtitle: record.date) {
                    Text(record.display)
                        .font(SR.Text.mono(14))
                        .foregroundStyle(SR.ink)
                }
                .srGlassRow()
            }
        } header: {
            SRSectionLabel(text: "Personal records")
        }
    }

    /// What this phone has sent up. Only the last few — the website holds the
    /// archive and a phone scrolling a thousand rows is not reading any of them.
    @ViewBuilder
    private var uploaded: some View {
        Section {
            if companion.records.isEmpty {
                Text(companion.paired
                     ? "Nothing uploaded yet. Choose categories under Settings → Apple Health."
                     : "Connect the companion to upload from Apple Health.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .srGlassRow()
                    .padding(.vertical, 10)
            } else {
                ForEach(companion.records.prefix(8)) { record in
                    SRRow(
                        title: HealthCollector.labels[record.kind] ?? record.kind,
                        subtitle: "\(record.source) · \(shortAgo(record.start))"
                    ) {
                        if let value = record.value {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(value.formatted())
                                    .font(SR.Text.mono(15))
                                    .foregroundStyle(SR.ink)
                                if let unit = record.unit {
                                    Text(unit).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                                }
                            }
                        }
                    }
                    .srGlassRow()
                }
            }
        } header: {
            SRSectionLabel(text: "From this iPhone", trailing: companion.queueCount > 0 ? "\(companion.queueCount) waiting" : nil)
        } footer: {
            Text("Only you can see these. Heart rate is not a live feed, and sleep records can overlap between sources.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var family: some View {
        if !companion.family.isEmpty {
            Section {
                ForEach(companion.family) { member in
                    FamilyRow(member: member).srGlassRow()
                }
            } header: {
                SRSectionLabel(text: "Family")
            } footer: {
                Text("Family members see a location you chose to share, and nothing else.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .padding(.vertical, 4)
            }
        }
    }

    private func openActivities() {
        router.health.append(HealthRoute.activities)
    }
}

// MARK: - The ink hero

/// Readiness and today's figures on an ink band — the top of /health.
///
/// The only ink on the tab. Everything under it stays paper: a tall ink area
/// reads as intensity, and the band is there to be the headline, not the page.
struct HealthHero: View {
    let summary: HealthSummary
    @EnvironmentObject private var router: Router

    var body: some View {
        // Inset 0: the grouped list already holds it off the screen edge.
        SRInkBand(kicker: "Readiness · Today", meta: updated, inset: 0) {
            if let readiness = summary.readiness {
                SRInkReadiness(readiness: readiness)
            } else {
                Text(summary.strap)
                    .font(SR.Text.body(15))
                    .foregroundStyle(SR.onInk(.note))
                    .fixedSize(horizontal: false, vertical: true)
            }

            SRTileGrid {
                // Buttons that push, not NavigationLinks: inside a List row a
                // NavigationLink earns a disclosure chevron, and four of them
                // drew chevrons in the gutters between the tiles.
                ForEach(summary.figures) { figure in
                    Button {
                        SRHaptic.tap()
                        router.health.append(figure)
                    } label: {
                        InkFigureTile(figure: figure)
                    }
                    .buttonStyle(.plain)
                }
            }

            if summary.isMock {
                SRInkMockNote()
            }
        }
    }

    private var updated: String? {
        let ago = shortAgo(summary.generatedAt)
        return ago.isEmpty ? nil : "Updated \(ago) ago"
    }
}

/// "These are not you", said on the band where the figures are.
struct SRInkMockNote: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(SR.accentOnDark)
            Text("Demonstration data — no real measurement landed in this window, so these figures are synthetic.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.onInk(.note))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A /health figure as an ink tile: value and unit apart, the sparkline where
/// the series travelled, and the movement coloured by whether it is good for
/// THIS metric.
struct InkFigureTile: View {
    let figure: HealthFigure

    var body: some View {
        SRInkTile(
            label: figure.label,
            value: figure.inkValue.value,
            unit: figure.inkValue.unit,
            spark: figure.series,
            foot: figure.deltaDisplay ?? figure.caption,
            footGood: figure.deltaDisplay == nil ? nil : figure.improving,
            footIcon: figure.deltaDisplay == nil ? nil : (figure.direction == "down" ? "arrow.down.right" : "arrow.up.right")
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(figure.label): \(figure.displayWithUnit)"
            + (figure.deltaDisplay.map { ", \($0) \(figure.caption)" } ?? ", \(figure.caption)")
            + (figure.improving == nil ? "" : figure.improving! ? ", improving" : ", worse")
        )
    }
}

extension HealthFigure {
    /// The value and the unit apart, for a tile that sets them in two faces.
    /// Percent stays attached — "62 %" reads as two things.
    var inkValue: (value: String, unit: String?) {
        guard measured else { return ("—", nil) }
        switch unit {
        case "%": return ("\(display)%", nil)
        case "h", "": return (display, nil)
        default: return (display, unit)
        }
    }
}

/// A figure, as a tappable tile with its movement.
struct FigureTile: View {
    let figure: HealthFigure

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(figure.label.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)

            Text(figure.displayWithUnit)
                .font(SR.Text.figure(30))
                .foregroundStyle(SR.ink)
                // See SRTileGrid: the grid folds at accessibility sizes rather
                // than the figure shrinking back to where it started.
                .lineLimit(1)

            HStack(spacing: 5) {
                if let delta = figure.deltaDisplay {
                    Image(systemName: figure.direction == "down" ? "arrow.down.right" : "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(delta).font(SR.Text.mono())
                } else {
                    Text(figure.caption).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                }
            }
            .foregroundStyle(tone)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SR.cardPadding)
        .frame(minHeight: 104, alignment: .topLeading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(figure.label): \(figure.displayWithUnit)"
            + (figure.deltaDisplay.map { ", \($0) \(figure.caption)" } ?? ", \(figure.caption)")
            + (figure.improving == nil ? "" : figure.improving! ? ", improving" : ", worse")
        )
    }

    /// The accent's counterpart, not the accent. Colour here means "the number
    /// moved in the good direction for THIS metric", which is not the same
    /// question as "this is the important thing on the screen".
    private var tone: Color {
        guard let improving = figure.improving else { return SR.inkGhost }
        return improving ? SR.good : SR.accent
    }
}

/// One figure, thirty days of it.
struct FigureDetail: View {
    let figure: HealthFigure

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(figure.displayWithUnit)
                        .font(SR.Text.hero(48))
                        .foregroundStyle(SR.ink)
                    Text(figure.caption)
                        .font(SR.Text.mono())
                        .tracking(1.1)
                        .foregroundStyle(SR.inkMuted)
                    if let delta = figure.deltaDisplay {
                        Text(delta + (figure.improving == true ? " — the good direction" : ""))
                            .font(SR.Text.secondary())
                            .foregroundStyle(figure.improving == true ? SR.good : SR.accent)
                    }
                }

                if let series = figure.series, series.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        SRSectionLabel(text: "Last \(series.count) days", trailing: range(series))
                        SRSparkline(values: series)
                            .frame(height: 120)
                    }
                } else {
                    Text("No history for this figure yet.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }

                Text("Measured and derived on the website. The phone shows what /health computed; it does not recompute anything.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .srPaper()
        .navigationTitle(figure.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func range(_ series: [Double]) -> String {
        guard let low = series.min(), let high = series.max() else { return "" }
        return "\(Int(low.rounded()))–\(Int(high.rounded()))"
    }
}

/// A line, and the band it moves in. No axes, no grid.
///
/// A sparkline is read for its SHAPE; a chart small enough to sit under a
/// figure has no room for the furniture that would let it be read for its
/// values, and half-drawn furniture invites exactly the precision it cannot
/// support. The low and the high are printed as text above it instead.
struct SRSparkline: View {
    let values: [Double]
    /// On an ink band the line is accent-on-dark and the end dot is too —
    /// petrol has no role on ink.
    var register: SRRegister = .paper

    var body: some View {
        GeometryReader { geo in
            let low = values.min() ?? 0
            let high = values.max() ?? 1
            // A flat series has zero span, and dividing by it puts every point
            // at NaN — which draws nothing at all, silently.
            let span = max(high - low, 0.0001)
            let step = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : 0

            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) * step,
                    y: geo.size.height - CGFloat((value - low) / span) * geo.size.height
                )
            }

            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    for point in points { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(register.accent.opacity(0.14))

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(register.accent, style: StrokeStyle(lineWidth: register == .ink ? 1.5 : 2, lineCap: .round, lineJoin: .round))

                if let last = points.last {
                    Circle()
                        .fill(register == .ink ? SR.accentOnDark : SR.accentInk)
                        .frame(width: register == .ink ? 5 : 7, height: register == .ink ? 5 : 7)
                        .position(last)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trend over \(values.count) days")
    }
}

/// One family member's latest position.
struct FamilyRow: View {
    let member: FamilyMember

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(member.name).font(SR.Text.title()).foregroundStyle(SR.ink)
                Spacer(minLength: 6)
                if let point = member.location {
                    let stale = (parseTimestamp(point.recorded)?.timeIntervalSinceNow ?? -.infinity) < -1200
                    // The glyph carries the hue; the word carries the meaning.
                    // `--warn` measures 2.58:1 on cream and cannot hold 12pt
                    // copy on its own — a second encoding is what makes the
                    // colour legal here rather than decorative.
                    HStack(spacing: 4) {
                        Image(systemName: stale ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(stale ? SR.warn : SR.good)
                        Text(stale ? "STALE" : "LATEST")
                            .font(SR.Text.mono())
                            .tracking(1)
                            .foregroundStyle(SR.inkSecondary)
                    }
                }
            }
            if let point = member.location {
                Text("±\(Int(point.accuracy)) m · \(point.moving ? "Moving" : "Stationary") · \(shortAgo(point.recorded))")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                Button {
                    SRHaptic.tap()
                    MKMapItem(placemark: MKPlacemark(
                        coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                    )).openInMaps()
                } label: {
                    Label("Open in Maps", systemImage: "map")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.accent)
                }
                .buttonStyle(.plain)
                .frame(minHeight: SR.tapTarget, alignment: .leading)
            } else {
                Text(member.sharing ? "Waiting for a location" : "Location sharing paused")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(.vertical, 8)
    }
}

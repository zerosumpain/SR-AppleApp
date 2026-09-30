import SwiftUI
import MapKit

/// The health tab.
///
/// /health has nine sections and is read top to bottom at a desk. A phone is
/// opened for one question — "how am I doing" — so the tab is the answer and
/// then the way to everything else:
///
/// 1. the hero: readiness and four figures (the summary, which answers fast);
/// 2. four areas, two by two — Activities, Segments, Routes and Insights —
///    each one push away (`HealthAreasGrid`). Insights holds the read, what
///    the loop noticed, tripwires, moves and "The full picture";
/// 3. heart rate over the last day, from this iPhone;
/// 4. the family.
///
/// Everything /health concludes is on the phone — but the tab says where it
/// lives, rather than stacking nine sections a thumb has to scroll past to
/// reach the one that changed.
struct HealthScreen: View {
    @ObservedObject var companion: Companion
    @StateObject private var store = HealthStore()
    @StateObject private var hub = HealthHubStore()
    @StateObject private var heart = HeartTimelineStore()
    /// What the daydream loop noticed about health. Silent when it fails.
    /// Loaded here so Insights opens on it; the grid counts it.
    @StateObject private var noticed = HealthNoticedStore()
    @ObservedObject private var feedback = NoticedFeedback.shared
    /// The site's sections — the hero, the areas — are the owner's /health.
    /// Gated on OWNER, not on the site being paired: a member's phone may hold
    /// a site credential for chat or news. Everybody keeps what is theirs:
    /// this phone's heart rate and the family rows.
    @ObservedObject private var access = AccessStore.shared
    @EnvironmentObject private var router: Router

    var body: some View {
        List {
            if access.current.owner {
                if let summary = store.summary {
                    // The ink band: readiness and today's figures, /health's hero.
                    HealthHero(summary: summary).srInkRow()
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
                // The areas stand whether or not the summary answered: each
                // screen behind them loads for itself.
                Section {
                    HealthAreasGrid(
                        week: store.summary?.week,
                        hub: hub.hub,
                        noticed: noticed.notes.filter(feedback.isShowing).count
                    )
                    .srBareRow()
                }
            }
            heartSection
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
            async let summary: Void = store.load(fresh: true)
            async let deep: Void = hub.load(fresh: true)
            async let heartRate: Void = heart.load(companion: companion)
            async let notes: Void = noticed.load()
            _ = await (summary, deep, heartRate, notes)
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
        .navigationDestination(for: RouteRef.self) { PlannedRouteScreen(ref: $0) }
        .navigationDestination(for: HealthRoute.self) { route in
            switch route {
            case .activities: ActivitiesScreen()
            case .segments: SegmentsScreen()
            case .routes: RoutesScreen()
            case .planRoute: PlanRouteScreen()
            case .nearbyRoutes: NearbyRoutesScreen()
            case .offlineMaps: OfflineMapsScreen()
            case .insights: HealthInsightsScreen(store: store, hub: hub, noticed: noticed)
            case .instruments: if let h = hub.hub { InstrumentsScreen(hub: h) }
            case .forecast: if let h = hub.hub { ForecastScreen(hub: h) }
            case .tripwires: if let h = hub.hub { TripwiresScreen(hub: h) }
            case .moves: if let h = hub.hub { MovesScreen(hub: h) }
            case .experiments: if let h = hub.hub { ExperimentsScreen(hub: h) }
            case .verdict: if let v = hub.hub?.verdict { VerdictScreen(verdict: v) }
            }
        }
        .task {
            // The hero first — it is one small request — then the deep read and
            // the heart-rate day together, filling in beneath it.
            await store.load()
            async let deep: Void = hub.load()
            async let heartRate: Void = heart.load(companion: companion)
            async let notes: Void = noticed.load()
            _ = await (deep, heartRate, notes)
        }
    }

    /// See `ThreadListScreen.startThread` — a closure that is only a `Task`
    /// infers `Task<(), Never>` as its return type, and coercing that into an
    /// action tuple crashes the type checker.
    private func reload() {
        Task { await store.load(fresh: true) }
    }

    // MARK: - Heart rate

    /// What this iPhone sent up, as the line it is — it used to be the last
    /// eight readings as rows, which is a list of numbers nobody can read a day
    /// out of. The upload queue is one line under it now.
    @ViewBuilder
    private var heartSection: some View {
        Section {
            if !companion.paired && !Self.demo {
                // A fresh install. The rows this section replaced used to say how
                // to fill it, and the onboarding test is right that an empty tab
                // must still say that.
                Text("Connect the companion to upload from Apple Health, and your heart rate appears here as a day's line.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .srGlassRow()
                    .padding(.vertical, 10)
            } else if let timeline = heart.timeline {
                HeartRateCard(timeline: timeline).srBareRow()
            } else if heart.failed {
                Text("Heart rate did not load. Pull to try again.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .srGlassRow()
            } else {
                HStack { Spacer(); ProgressView().tint(SR.accent); Spacer() }
                    .frame(height: 120)
                    .srBareRow()
            }
        } header: {
            SRSectionLabel(text: "Last 24 hours", trailing: uploadLine)
        } footer: {
            Text("From this iPhone via Apple Health. Only you can see it. Not a live feed: it moves when the phone syncs.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .padding(.vertical, 4)
        }
    }

    private var uploadLine: String? {
        if companion.queueCount > 0 { return "\(companion.queueCount) waiting" }
        if let latest = companion.records.first { return "latest \(shortAgo(latest.start))" }
        return nil
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

    /// Demo mode: the review demo, or `-SRDemo`.
    static var demo: Bool { SRDemo.isOn }

    /// The four figures the ink hero draws from the summary.
    static let heroKeys: Set<String> = ["recovery", "hrv", "rhr", "sleep"]

    /// A HealthKit-ish kind ("heart_rate_variability") as a reader-facing
    /// label ("Heart rate variability"). Kinds are catalogued with their
    /// groups, not with a display name of their own, so this is the display
    /// name — derived, not looked up.
    static func label(for kind: String) -> String {
        kind.replacingOccurrences(of: "_", with: " ").capitalizedFirst
    }
}

fileprivate extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
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

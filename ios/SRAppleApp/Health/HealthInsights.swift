import SwiftUI

// MARK: - The four areas

/// The four ways off the Health tab, two by two under the ink hero:
/// Activities, Segments, Routes, Insights.
///
/// The tab used to stack the read, the tripwires, the moves, recent
/// activities and "The full picture" under the hero — nine sections a thumb
/// scrolled past to reach the one it wanted. Now the hero answers "how am I
/// doing" and these four say where everything else lives, each one push away.
struct HealthAreasGrid: View {
    let week: HealthWeek?
    let hub: HubDigest?
    let noticed: Int

    var body: some View {
        SRTileGrid {
            HealthAreaTile(
                title: "Activities",
                icon: "figure.run",
                detail: activitiesLine,
                route: .activities,
                identifier: "health-all-activities"
            )
            HealthAreaTile(
                title: "Segments",
                icon: "flag.checkered",
                detail: segmentsLine,
                route: .segments,
                identifier: "health-segments"
            )
            HealthAreaTile(
                title: "Routes",
                icon: "point.topleft.down.to.point.bottomright.curvepath",
                detail: "Plan, save and follow",
                route: .routes,
                identifier: "health-routes"
            )
            HealthAreaTile(
                title: "Insights",
                icon: "sparkles",
                detail: insightsLine,
                route: .insights,
                identifier: "health-insights",
                flagged: liveTripwires > 0
            )
        }
    }

    private var activitiesLine: String {
        guard let week else { return "Every workout" }
        if week.activities == 0 { return "None this week" }
        return "\(week.activities) this week · \(TrailFormat.km(fromKm: week.distanceKm)) km"
    }

    private var segmentsLine: String {
        guard let segments = hub?.segments else { return "Your efforts, compared" }
        return "\(segments.improving) improving · \(segments.slipping) slipping"
    }

    private var liveTripwires: Int { hub?.tripwires.filter(\.live).count ?? 0 }

    private var insightsLine: String {
        guard let hub else { return "The read, forecasts, verdict" }
        if liveTripwires > 0 {
            return liveTripwires == 1 ? "1 tripwire live" : "\(liveTripwires) tripwires live"
        }
        if noticed > 0 { return noticed == 1 ? "1 thing noticed" : "\(noticed) things noticed" }
        if !hub.tripwires.isEmpty { return "All clear" }
        return "The read, forecasts, verdict"
    }
}

/// One area: a glyph, its name, and a line on what is in it.
///
/// A Button that pushes, not a NavigationLink — inside a List row a
/// NavigationLink earns a disclosure chevron, and the hero's tiles found that
/// four of them draw chevrons in the gutters between tiles.
struct HealthAreaTile: View {
    let title: String
    let icon: String
    let detail: String
    let route: HealthRoute
    let identifier: String
    /// Something inside wants a look: the glyph takes the accent's dot.
    var flagged = false
    @EnvironmentObject private var router: Router

    var body: some View {
        Button {
            SRHaptic.tap()
            router.health.append(route)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SR.accent)
                        .frame(width: 28, height: 28, alignment: .leading)
                        .overlay(alignment: .topTrailing) {
                            if flagged {
                                Circle().fill(SR.accent).frame(width: 7, height: 7).offset(x: 2, y: -2)
                            }
                        }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SR.inkGhost)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(SR.Text.display(19))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                    // Two lines reserved, so the four tiles stand the same
                    // height whatever each has to say.
                    Text(detail)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SR.cardPadding)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(detail)")
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Insights

/// Everything /health concludes, one push off the tab: the read, what the
/// loop noticed, the live tripwires and the top moves, then "The full picture"
/// — instruments, forecast, experiments, the verdict — and the week and the
/// records.
///
/// The stores are the tab's own, handed down, so the deep read loaded for the
/// grid's lines is the one drawn here and refreshing either refreshes both.
struct HealthInsightsScreen: View {
    @ObservedObject var store: HealthStore
    @ObservedObject var hub: HealthHubStore
    @ObservedObject var noticed: HealthNoticedStore
    /// So a note rated here, or on Today, leaves this list too.
    @ObservedObject private var feedback = NoticedFeedback.shared
    @EnvironmentObject private var router: Router

    var body: some View {
        List {
            if let digest = hub.hub { readSection(digest) }
            noticedSection
            if let digest = hub.hub {
                attentionSections(digest)
                fullPicture(digest)
            } else if hub.failed {
                Text("The deeper read did not load. Pull to try again.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .srBareRow()
            } else {
                HStack { Spacer(); ProgressView().tint(SR.accent); Spacer() }
                    .padding(.vertical, 40)
                    .srBareRow()
            }
            if let summary = store.summary {
                if let week = summary.week { weekSection(week) }
                if !summary.records.isEmpty { records(summary.records) }
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.vital)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable {
            async let summary: Void = store.load(fresh: true)
            async let deep: Void = hub.load(fresh: true)
            async let notes: Void = noticed.load()
            _ = await (summary, deep, notes)
        }
        .task { if hub.hub == nil { await hub.load() } }
    }

    // MARK: - The read

    @ViewBuilder
    private func readSection(_ digest: HubDigest) -> some View {
        if digest.lede != nil || digest.readiness != nil || digest.planner != nil || digest.plan != nil {
            Section {
                HubReadCard(hub: digest).srBareRow()
                // The tiles the hero does not already carry — the week's volume
                // and VO₂max — with /health's own footnote under each.
                let extra = digest.tiles.filter { !HealthScreen.heroKeys.contains($0.key) }
                if !extra.isEmpty {
                    SRTileGrid {
                        ForEach(extra) { tile in
                            SRStatTile(value: tile.display, unit: tile.unit, label: tile.label, caption: tile.foot)
                        }
                    }
                    .srBareRow()
                }
                if let plan = digest.plan { HubPlanCard(plan: plan).srBareRow() }
            } header: {
                SRSectionLabel(text: "The read")
            }
        }
    }

    // MARK: - Noticed

    /// The daydream loop's health notes, under the read: the read is what
    /// /health concludes, these are what the loop noticed beside it. No
    /// header over nothing, and never an error card — see `HealthNoticedStore`.
    @ViewBuilder
    private var noticedSection: some View {
        let notes = noticed.notes.filter(feedback.isShowing)
        if !notes.isEmpty {
            Section {
                ForEach(notes) { note in
                    NoticedNoteRow(note: note).srGlassRow()
                }
            } header: {
                SRSectionLabel(text: "Noticed")
            }
        }
    }

    // MARK: - What needs attention

    @ViewBuilder
    private func attentionSections(_ digest: HubDigest) -> some View {
        let live = digest.tripwires.filter(\.live)
        if !digest.tripwires.isEmpty {
            Section {
                if live.isEmpty {
                    SRRow(title: "All \(digest.tripwires.count) clear", subtitle: "Nothing has crossed its line", icon: "checkmark.circle") { EmptyView() }
                        .srGlassRow()
                } else {
                    ForEach(live) { TripwireRow(tripwire: $0).srGlassRow() }
                }
            } header: {
                SRSectionLabel(text: "Tripwires", trailing: live.isEmpty ? nil : "\(live.count) of \(digest.tripwires.count)")
            }
        }
        if !digest.moves.isEmpty {
            Section {
                ForEach(digest.moves.prefix(3)) { MoveRow(move: $0).srGlassRow() }
                if digest.moves.count > 3 {
                    NavigationLink(value: HealthRoute.moves) {
                        SRRow(title: "All \(digest.moves.count) moves", icon: "list.number") { EmptyView() }
                    }
                    .srGlassRow()
                }
            } header: {
                SRSectionLabel(text: "Ranked moves")
            }
        }
    }

    // MARK: - The full picture

    /// Segments are not here: they have their own tile on the tab.
    @ViewBuilder
    private func fullPicture(_ digest: HubDigest) -> some View {
        Section {
            if !digest.instruments.isEmpty {
                let watching = digest.instruments.filter { $0.tone == .watch || $0.tone == .bad }.count
                NavigationLink(value: HealthRoute.instruments) {
                    SRRow(title: "Instruments",
                          subtitle: watching == 0 ? "All \(digest.instruments.count) in range" : "\(watching) of \(digest.instruments.count) to watch",
                          icon: "gauge.with.dots.needle.33percent") { EmptyView() }
                }
                .srGlassRow()
            }
            if !digest.forecasts.isEmpty {
                NavigationLink(value: HealthRoute.forecast) {
                    SRRow(title: "Forecast",
                          subtitle: digest.forecasts.map(\.label).joined(separator: " · "),
                          icon: "chart.line.uptrend.xyaxis") { EmptyView() }
                }
                .srGlassRow()
            }
            if !digest.tripwires.isEmpty {
                NavigationLink(value: HealthRoute.tripwires) {
                    SRRow(title: "Every tripwire", subtitle: "\(digest.tripwires.count) lines, and where each stands", icon: "exclamationmark.triangle") { EmptyView() }
                }
                .srGlassRow()
            }
            if !digest.experiments.isEmpty {
                let live = digest.experiments.filter(\.live).count
                NavigationLink(value: HealthRoute.experiments) {
                    SRRow(title: "Experiments", subtitle: "\(live) live · \(digest.experiments.count - live) queued", icon: "testtube.2") { EmptyView() }
                }
                .srGlassRow()
            }
            if let verdict = digest.verdict {
                NavigationLink(value: HealthRoute.verdict) {
                    SRRow(title: "The verdict", subtitle: verdict.headline.joined(separator: " "), icon: "text.quote") { EmptyView() }
                }
                .srGlassRow()
            }
        } header: {
            SRSectionLabel(text: "The full picture")
        } footer: {
            if digest.isMock {
                Text("Demonstration data: no real measurement landed in this window.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.accent)
            }
        }
    }

    // MARK: - The week and the records

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

    private func openActivities() {
        router.health.append(HealthRoute.activities)
    }
}

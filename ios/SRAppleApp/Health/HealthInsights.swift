import SwiftUI

// MARK: - Insights

/// Everything /health concludes, one push off the tab, in the order it is
/// acted on:
///
/// 1. the read, on ink — the one line, and what readiness is made of;
/// 2. today — what the planner would commission and the session it wrote;
/// 3. what needs attention — live tripwires, then the top three moves;
/// 4. what the loop noticed;
/// 5. the figures the tab's hero does not carry, and "The full picture" —
///    instruments, forecast, experiments, the verdict — each one push away.
///
/// The week and the records moved to Activities, where the rows that make
/// them up are.
///
/// The stores are the tab's own, handed down, so the deep read loaded for the
/// grid's lines is the one drawn here and refreshing either refreshes both.
struct HealthInsightsScreen: View {
    @ObservedObject var hub: HealthHubStore
    @ObservedObject var noticed: HealthNoticedStore
    /// So a note rated here, or on Today, leaves this list too.
    @ObservedObject private var feedback = NoticedFeedback.shared

    var body: some View {
        List {
            if let digest = hub.hub {
                if digest.lede != nil || digest.readiness != nil || digest.isMock {
                    InsightsReadBand(hub: digest).srInkRow()
                }
                todaySection(digest)
                attentionSections(digest)
                noticedSection
                alsoMeasured(digest)
                fullPicture(digest)
            } else if hub.failed {
                SREmpty(
                    title: "The deeper read did not load",
                    icon: "sparkles",
                    message: "Pull to try again. The figures on the Health tab still stand.",
                    actionLabel: "Try again",
                    action: reload
                )
                .srBareRow()
            } else {
                HStack { Spacer(); ProgressView().tint(SR.accent); Spacer() }
                    .padding(.vertical, 40)
                    .srBareRow()
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.vital)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable {
            async let deep: Void = hub.load(fresh: true)
            async let notes: Void = noticed.load()
            _ = await (deep, notes)
        }
        .task { if hub.hub == nil { await hub.load() } }
    }

    private func reload() {
        Task { await hub.load(fresh: true) }
    }

    // MARK: - Today

    @ViewBuilder
    private func todaySection(_ digest: HubDigest) -> some View {
        if digest.planner != nil || digest.plan != nil {
            Section {
                if let plan = digest.plan { HubPlanCard(plan: plan).srBareRow() }
                if let planner = digest.planner { HubPlannerCard(planner: planner).srBareRow() }
            } header: {
                SRSectionLabel(text: "Today")
            }
        }
    }

    /// The tiles the hero does not already carry — the week's volume and
    /// VO₂max — with /health's own footnote under each.
    @ViewBuilder
    private func alsoMeasured(_ digest: HubDigest) -> some View {
        let extra = digest.tiles.filter { !HealthScreen.heroKeys.contains($0.key) }
        if !extra.isEmpty {
            Section {
                SRTileGrid {
                    ForEach(extra) { tile in
                        SRStatTile(value: tile.display, unit: tile.unit, label: tile.label, caption: tile.foot)
                    }
                }
                .srBareRow()
            } header: {
                SRSectionLabel(text: "Also measured")
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
                SRSectionLabel(text: live.isEmpty ? "Tripwires" : "Needs attention", trailing: live.isEmpty ? nil : "\(live.count) of \(digest.tripwires.count) tripwires")
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
        }
    }
}

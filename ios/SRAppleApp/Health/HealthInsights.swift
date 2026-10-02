import SwiftUI
import Charts

// MARK: - Insights

/// Everything /health concludes, one push off the tab, ranked by how much it
/// should pull the eye:
///
/// 1. the read, on ink — readiness as a verdict and what to do about it, the
///    one line, and what readiness is made of;
/// 2. what needs attention — live tripwires, each with a badge that is the
///    loudest thing on the page, red when crossed and orange when close;
/// 3. the forecast, two by two — where each trend is heading, one tap from
///    its chart;
/// 4. the ranked moves;
/// 5. quieter: what the loop noticed, the figures the tab's hero does not
///    carry, and "More" — instruments, experiments, the verdict.
///
/// There is no "Today" section: the planner's commission and its session
/// repeated what the read already says, one screen lower.
///
/// Colour is a ranking, not decoration. Red and orange belong to attention
/// alone; petrol is the forecast's; olive is the moves'. Everything below the
/// moves is ink at reading weight, so nothing quiet can outshout a tripwire.
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
                attentionSection(digest)
                forecastSection(digest)
                movesSection(digest)
                noticedSection
                alsoMeasured(digest)
                more(digest)
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

    // MARK: - What needs attention

    /// Live tripwires as their own loud card. All clear is one quiet olive
    /// line — good news should not take the space bad news would.
    @ViewBuilder
    private func attentionSection(_ digest: HubDigest) -> some View {
        let live = digest.tripwires.filter(\.live)
            .sorted { InsightsAttention.rank($0.state) < InsightsAttention.rank($1.state) }
        if !digest.tripwires.isEmpty {
            Section {
                if live.isEmpty {
                    InsightsAllClear(count: digest.tripwires.count).srBareRow()
                } else {
                    InsightsAttentionCard(tripwires: live).srBareRow()
                }
            } header: {
                if !live.isEmpty {
                    InsightsHeader(
                        text: "Needs attention",
                        icon: "bell.badge.fill",
                        tint: SR.error,
                        trailing: "\(live.count) of \(digest.tripwires.count) tripwires"
                    )
                }
            }
        }
    }

    // MARK: - Forecast

    /// Up to four forecasts, two by two. Each tile opens the full charts.
    @ViewBuilder
    private func forecastSection(_ digest: HubDigest) -> some View {
        if !digest.forecasts.isEmpty {
            Section {
                InsightsForecastGrid(forecasts: Array(digest.forecasts.prefix(4))).srBareRow()
            } header: {
                InsightsHeader(
                    text: "Forecast",
                    icon: "chart.line.uptrend.xyaxis",
                    tint: SR.accentInk,
                    trailing: digest.forecasts.first.map { "next \($0.horizonDays) days" }
                )
            }
        }
    }

    // MARK: - Moves

    @ViewBuilder
    private func movesSection(_ digest: HubDigest) -> some View {
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
                InsightsHeader(text: "Ranked moves", icon: "arrow.up.forward.circle.fill", tint: SR.good)
            }
        }
    }

    // MARK: - Noticed

    /// The daydream loop's health notes. No header over nothing, and never an
    /// error card — see `HealthNoticedStore`.
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

    // MARK: - More

    /// The rest of the picture, quietly: each one push away. Forecast is not
    /// here — it has its own grid above — and segments have their own tile on
    /// the tab.
    @ViewBuilder
    private func more(_ digest: HubDigest) -> some View {
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
            SRSectionLabel(text: "More")
        }
    }
}

// MARK: - Section header

/// A section's eyebrow with its colour and glyph: the colour says how loud
/// the section is allowed to be.
struct InsightsHeader: View {
    let text: String
    let icon: String
    let tint: Color
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text.uppercased())
                .font(SR.Text.label(13))
                .tracking(1.4)
                .foregroundStyle(tint)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing.uppercased())
                    .font(SR.Text.mono())
                    .tracking(1)
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Attention

enum InsightsAttention {
    /// Tripped before close before anything else.
    static func rank(_ state: String) -> Int {
        switch state {
        case "tripped": return 0
        case "close": return 1
        default: return 2
        }
    }

    static func tint(_ state: String) -> Color {
        state == "tripped" ? SR.error : SR.accent
    }

    static func symbol(_ state: String) -> String {
        state == "tripped" ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"
    }

    static func word(_ state: String) -> String {
        state == "tripped" ? "TRIPPED" : "CLOSE"
    }
}

/// The live tripwires, on a card tinted the colour of the worst of them.
struct InsightsAttentionCard: View {
    let tripwires: [HubDigest.Tripwire]

    private var worst: Color {
        InsightsAttention.tint(tripwires.first?.state ?? "close")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tripwires.enumerated()), id: \.element.id) { index, tripwire in
                if index > 0 {
                    Rectangle().fill(worst.opacity(0.18)).frame(height: 1).padding(.leading, 62)
                }
                InsightsAttentionRow(tripwire: tripwire)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                .fill(worst.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                .strokeBorder(worst.opacity(0.45), lineWidth: 1.5)
        )
        .accessibilityIdentifier("insights-attention")
    }
}

/// One live tripwire: a badge that pulses when it has been crossed, the
/// signal and where it stands, then what it means.
struct InsightsAttentionRow: View {
    let tripwire: HubDigest.Tripwire
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tint = InsightsAttention.tint(tripwire.state)
        let tripped = tripwire.state == "tripped"
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(tint)
                Image(systemName: InsightsAttention.symbol(tripwire.state))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating, isActive: tripped && !reduceMotion)
            }
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(InsightsAttention.word(tripwire.state))
                        .font(SR.Text.label(11))
                        .tracking(1.2)
                        .foregroundStyle(tint)
                    Spacer(minLength: 6)
                    Text(tripwire.now)
                        .font(SR.Text.figure(17))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(tripwire.signal)
                    .font(SR.Text.display(19))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(tripwire.window) · trips at \(tripwire.trigger)")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                if !tripwire.meaning.isEmpty {
                    Text(tripwire.meaning)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}

/// Every tripwire clear: one quiet line, not a card.
struct InsightsAllClear: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SR.good)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("All \(count) tripwires clear")
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                Text("Nothing has crossed its line")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                .fill(SR.good.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Forecast, two by two

/// Four forecasts as a two-by-two grid: where each trend is now, where it is
/// heading, and a thumbnail of the line and its cone. A tile opens the full
/// charts.
struct InsightsForecastGrid: View {
    let forecasts: [HubDigest.Forecast]

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(forecasts) { forecast in
                // One element per tile, and it is the link: the tile itself
                // must not also be a button, or VoiceOver reads each twice.
                NavigationLink(value: HealthRoute.forecast) {
                    InsightsForecastTile(forecast: forecast)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(InsightsForecastTile.spoken(forecast))
            }
        }
        .accessibilityIdentifier("insights-forecast-grid")
    }
}

struct InsightsForecastTile: View {
    let forecast: HubDigest.Forecast

    /// "Sleep · 30d mean" → "Sleep": the tile is narrow, the window is on the
    /// chart screen.
    private var title: String {
        forecast.label.components(separatedBy: " · ").first ?? forecast.label
    }

    /// Up, down or flat, by more than 2% of where it is now.
    private var trend: (symbol: String, word: String) {
        guard let now = forecast.now, let projected = forecast.projected else { return ("minus", "flat") }
        let change = projected - now
        if abs(change) <= max(abs(now) * 0.02, 0.001) { return ("arrow.right", "holding") }
        return change > 0 ? ("arrow.up.right", "rising") : ("arrow.down.right", "falling")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(title.uppercased())
                    .font(SR.Text.label(11))
                    .tracking(1.1)
                    .foregroundStyle(SR.accentInk)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: trend.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SR.accentInk)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Self.format(forecast.projected ?? forecast.now))
                    .font(SR.Text.figure(24))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = forecast.unit {
                    Text(unit).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                }
            }
            Text("from \(Self.format(forecast.now)) · \(forecast.horizonDays)d")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            ForecastSpark(forecast: forecast)
                .frame(height: 44)
            Text(forecast.reading)
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                .fill(SR.accentInk.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                .strokeBorder(SR.accentInk.opacity(0.22), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous))
    }

    /// "Sleep forecast: 7.28 h in 90 days, rising. Rising at +0.03 a month."
    static func spoken(_ forecast: HubDigest.Forecast) -> String {
        let tile = InsightsForecastTile(forecast: forecast)
        let unit = forecast.unit.map { " \($0)" } ?? ""
        return "\(tile.title) forecast: \(format(forecast.projected ?? forecast.now))\(unit) in \(forecast.horizonDays) days, \(tile.trend.word). \(forecast.reading)"
    }

    /// Two significant places for small numbers, none for large ones.
    static func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        let magnitude = abs(value)
        if magnitude >= 100 { return String(format: "%.0f", value) }
        if magnitude >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }
}

/// The forecast's line and cone, without axes: a thumbnail of `ForecastCard`.
struct ForecastSpark: View {
    let forecast: HubDigest.Forecast

    private struct Dated: Identifiable {
        let index: Int
        let value: Double
        let low: Double
        let high: Double
        var id: Int { index }
    }

    var body: some View {
        // Positions, not dates: a thumbnail needs the shape, and an index
        // cannot fail to parse.
        let history = forecast.history.enumerated().map { Dated(index: $0.offset, value: $0.element.value, low: $0.element.value, high: $0.element.value) }
        let start = history.count
        let cone = forecast.cone.enumerated().map { Dated(index: start + $0.offset, value: $0.element.value, low: $0.element.low, high: $0.element.high) }
        let values = history.map(\.value) + cone.flatMap { [$0.low, $0.high] }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.08, 0.001)
        Chart {
            ForEach(cone) { p in
                AreaMark(x: .value("i", p.index), yStart: .value("Low", p.low), yEnd: .value("High", p.high))
                    .foregroundStyle(SR.accentInk.opacity(0.14))
            }
            ForEach(history) { p in
                LineMark(x: .value("i", p.index), y: .value("v", p.value), series: .value("Line", "Observed"))
                    .foregroundStyle(SR.ink.opacity(0.75))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
            }
            ForEach(cone) { p in
                LineMark(x: .value("i", p.index), y: .value("v", p.value), series: .value("Line", "Projected"))
                    .foregroundStyle(SR.accentInk)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [3, 2]))
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
    }
}

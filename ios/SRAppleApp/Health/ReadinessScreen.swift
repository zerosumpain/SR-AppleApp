import SwiftUI
import HealthKit

// MARK: - Move, Exercise and Stand, from this iPhone

/// Today's three Activity rings, read from Apple Health on the phone.
///
/// `MoveRingStore` reads Move alone for Today's row; the Health tab's hero
/// draws all three, nested the way the Watch draws them, so it reads the
/// whole summary. Same rules: no permission sheet from here (the companion
/// asks for the activity summary), and nothing granted reads as no rings,
/// not as a screen that opens on a system prompt.
@MainActor
final class ActivityRingsStore: ObservableObject {
    struct Ring: Equatable, Sendable, Identifiable {
        let key: String
        let label: String
        let value: Double
        let goal: Double
        /// "kcal", "min" or "h".
        let unit: String

        var id: String { key }
        var fraction: Double { goal > 0 ? value / goal : 0 }
        /// "412 / 600 kcal".
        var spoken: String { "\(label) \(Int(value.rounded())) of \(Int(goal.rounded())) \(unit)" }
    }

    struct Rings: Equatable, Sendable {
        let move: Ring?
        let exercise: Ring?
        let stand: Ring?

        /// Outermost first, as they nest.
        var all: [Ring?] { [move, exercise, stand] }
        var isEmpty: Bool { move == nil && exercise == nil && stand == nil }
    }

    @Published private(set) var rings: Rings?

    private let store = HKHealthStore()
    private var query: HKActivitySummaryQuery?
    private var day: DateComponents?

    /// Start watching today's rings, or re-point the watch at a new day.
    /// Cheap to call on every refresh: a query already on today is left alone.
    func start(now: Date = Date()) {
        // Demo mode has no HealthKit to read: the rings the screenshots show.
        if SRDemo.isOn {
            rings = Self.demo
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let calendar = Calendar.current
        var today = calendar.dateComponents([.era, .year, .month, .day], from: now)
        today.calendar = calendar
        if query != nil, day == today { return }
        stop()
        day = today

        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: today, end: today)
        let handler: (HKActivitySummaryQuery, [HKActivitySummary]?, Error?) -> Void = { [weak self] _, summaries, _ in
            let latest = summaries?.last.map(Self.rings(from:))
            Task { @MainActor in self?.rings = latest }
        }
        let summaryQuery = HKActivitySummaryQuery(predicate: predicate, resultsHandler: handler)
        summaryQuery.updateHandler = handler
        store.execute(summaryQuery)
        query = summaryQuery
    }

    func stop() {
        if let query { store.stop(query) }
        query = nil
    }

    nonisolated static func rings(from summary: HKActivitySummary) -> Rings {
        let move = MoveRingStore.reading(from: summary).map {
            Ring(key: "move", label: "Move", value: $0.value, goal: $0.goal, unit: $0.unit)
        }
        var exercise: Ring?
        if let goal = summary.exerciseTimeGoal?.doubleValue(for: .minute()), goal > 0 {
            exercise = Ring(key: "exercise", label: "Exercise",
                            value: summary.appleExerciseTime.doubleValue(for: .minute()), goal: goal, unit: "min")
        }
        var stand: Ring?
        if let goal = summary.standHoursGoal?.doubleValue(for: .count()), goal > 0 {
            stand = Ring(key: "stand", label: "Stand",
                         value: summary.appleStandHours.doubleValue(for: .count()), goal: goal, unit: "h")
        }
        return Rings(move: move, exercise: exercise, stand: stand)
    }

    nonisolated static let demo = Rings(
        move: Ring(key: "move", label: "Move", value: 412, goal: 600, unit: "kcal"),
        exercise: Ring(key: "exercise", label: "Exercise", value: 22, goal: 30, unit: "min"),
        stand: Ring(key: "stand", label: "Stand", value: 9, goal: 12, unit: "h")
    )
}

// MARK: - Where today sits

/// Today's value against the window it came from, for the hero's range bars:
/// the dot is today within the window's low and high, the tick is the last
/// seven days' mean — so a dot right of the tick is above your week.
///
/// Placement, not a conclusion: the same series the sparkline draws, put on a
/// line. Whether that side of the tick is good is still the server's
/// `improving`, which colours the dot.
struct FigureRange: Equatable {
    /// 0…1.
    let position: Double
    /// 0…1.
    let baseline: Double

    static func make(_ figure: HealthFigure) -> FigureRange? {
        guard figure.measured, let series = figure.series, series.count > 1,
              let low = series.min(), let high = series.max(), high > low else { return nil }
        let week = series.suffix(7)
        let mean = week.reduce(0, +) / Double(week.count)
        func at(_ value: Double) -> Double { min(1, max(0, (value - low) / (high - low))) }
        return FigureRange(position: at(figure.value), baseline: at(mean))
    }
}

// MARK: - The compact hero

/// The top of the Health tab: readiness inside today's three rings, and the
/// four figures as where-today-sits lines. One card, one tap to Readiness,
/// where the verdict, its reasons and the fortnight are.
///
/// It was a tall band — the donut, the verdict, four tiles with sparklines —
/// that pushed the four areas below the first screen. This keeps the numbers
/// and moves the reading of them one push away.
struct HealthCompactHero: View {
    let summary: HealthSummary
    let rings: ActivityRingsStore.Rings?
    @EnvironmentObject private var router: Router
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button {
            SRHaptic.tap()
            router.health.append(HealthRoute.readiness)
        } label: {
            SRInkBand(inset: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        SRInkKicker(text: "Readiness · Today")
                        if let updated {
                            Text(updated.uppercased())
                                .font(SR.Text.mono())
                                .tracking(1)
                                .foregroundStyle(SR.onInk(.unit))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SR.onInk(.note))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(SR.onInk(.fill)))
                        .overlay(Circle().strokeBorder(SR.onInk(.hairline), lineWidth: 1))
                }

                // Side by side; stacked once the reader's text is large
                // enough that four figure lines beside the rings would be a
                // word a line.
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
                layout {
                    ReadinessRings(score: score, rings: rings)
                        .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(summary.figures.prefix(4)) { figure in
                            InkFigureLine(figure: figure)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if summary.isMock {
                    SRInkMockNote()
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens readiness")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("health-readiness")
    }

    private var score: String {
        summary.readiness.map { "\(Int($0.score.rounded()))" } ?? "—"
    }

    private var updated: String? {
        let ago = shortAgo(summary.generatedAt)
        return ago.isEmpty ? nil : "Updated \(ago) ago"
    }

    /// "Readiness 72, Primed. Move 412 of 600 kcal, … Resting HR 52 bpm, …"
    private var spoken: String {
        var parts: [String] = []
        if let readiness = summary.readiness {
            parts.append("Readiness \(Int(readiness.score.rounded())), \(readiness.label)")
        } else {
            parts.append("Readiness not in yet")
        }
        let ringLine = (rings?.all ?? []).compactMap { $0?.spoken }.joined(separator: ", ")
        if !ringLine.isEmpty { parts.append(ringLine) }
        let figureLine = summary.figures.prefix(4).map { "\($0.label) \($0.displayWithUnit)" }.joined(separator: ", ")
        if !figureLine.isEmpty { parts.append(figureLine) }
        return parts.joined(separator: ". ")
    }
}

/// Readiness in the middle of today's Move, Exercise and Stand, nested the
/// way the Watch draws them. A ring with no reading draws its track alone.
struct ReadinessRings: View {
    let score: String
    let rings: ActivityRingsStore.Rings?

    /// Move, Exercise, Stand — the lifted partners, because this is on ink.
    static let tints: [Color] = [SR.accentOnDark, SR.goodOnDark, SR.accentInkOnDark]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = side * 8.5 / 120
            let step = side * 10 / 120
            let all = rings?.all ?? [nil, nil, nil]
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let tint = Self.tints[index]
                    ZStack {
                        Circle().stroke(tint.opacity(0.18), lineWidth: line)
                        if let ring = all[index] {
                            Circle()
                                .trim(from: 0, to: max(0, min(1, ring.fraction)))
                                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .padding(CGFloat(index) * step + line / 2)
                }
                Text(score)
                    .font(SR.Text.figure(32))
                    .tracking(-0.64)
                    .foregroundStyle(SR.onInk(.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, step * 3)
            }
            .frame(width: side, height: side)
            .animation(.easeInOut(duration: 0.4), value: rings)
        }
        .accessibilityHidden(true)
    }
}

/// One figure on the hero: label and value, then where today sits.
struct InkFigureLine: View {
    let figure: HealthFigure

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(figure.label.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.4)
                    .foregroundStyle(SR.onInk(.label))
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(figure.inkValue.value)
                        .font(SR.Text.figure(15))
                        .foregroundStyle(SR.onInk(.primary))
                    if let unit = figure.inkValue.unit {
                        Text(unit)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.onInk(.unit))
                    }
                }
                .lineLimit(1)
                .fixedSize()
            }
            if let range = FigureRange.make(figure) {
                InkRangeBar(range: range, tone: tone)
            }
        }
    }

    /// The server says whether this direction is good for THIS metric.
    private var tone: Color {
        switch figure.improving {
        case .some(true): return SR.goodOnDark
        case .some(false): return SR.accentOnDark
        case .none: return SR.onInk(.note)
        }
    }
}

/// A hairline track, a tick for the week, a dot for today.
struct InkRangeBar: View {
    let range: FigureRange
    let tone: Color

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 5
            let width = max(0, proxy.size.width - inset * 2)
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(SR.onInk(.track))
                    .frame(height: 4)
                    .offset(y: 3)
                Rectangle()
                    .fill(SR.onInk(.label))
                    .frame(width: 1.5, height: 10)
                    .offset(x: inset + width * range.baseline - 0.75)
                Circle()
                    .fill(tone)
                    .overlay(Circle().strokeBorder(SR.band, lineWidth: 1.2))
                    .frame(width: 9, height: 9)
                    .offset(x: inset + width * range.position - 4.5, y: 0.5)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

// MARK: - Readiness, one push away

/// Readiness in full: the verdict and what to do about it, what it is made
/// of, today's rings from this iPhone, and the fortnight behind each figure.
///
/// The stores are the tab's own, handed down, so the numbers here are the
/// ones the hero just drew.
struct ReadinessScreen: View {
    @ObservedObject var store: HealthStore
    @ObservedObject var hub: HealthHubStore
    @ObservedObject var rings: ActivityRingsStore

    var body: some View {
        List {
            if let summary = store.summary {
                ReadinessBand(summary: summary, factors: factors(summary)).srInkRow()

                Section {
                    ActivityTodayCard(rings: rings.rings).srBareRow()
                } header: {
                    SRSectionLabel(text: "Activity · today", trailing: "From this iPhone")
                }

                if !summary.figures.isEmpty {
                    Section {
                        SRTileGrid {
                            ForEach(summary.figures) { FigureTrendTile(figure: $0) }
                        }
                        .srBareRow()
                    } header: {
                        SRSectionLabel(text: window(summary), trailing: "Tap for more")
                    } footer: {
                        Text("Measured and derived on the website. The phone shows what /health computed; it does not recompute anything.")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .padding(.vertical, 4)
                    }
                }
            } else if store.unavailable {
                SREmpty(
                    title: "Health is not answering",
                    icon: "heart.slash",
                    message: "The health service did not reply. Pull to try again."
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
        .navigationTitle("Readiness")
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable {
            async let summary: Void = store.load(fresh: true)
            async let deep: Void = hub.load(fresh: true)
            _ = await (summary, deep)
            rings.start()
        }
        .task { rings.start() }
    }

    /// The summary's own factors, else the deep read's: either may be the
    /// one that arrived.
    private func factors(_ summary: HealthSummary) -> [ReadinessFactorLine] {
        if let factors = summary.readiness?.factors, !factors.isEmpty {
            return factors.map { ReadinessFactorLine(key: $0.key, label: $0.label, score: $0.score) }
        }
        return (hub.hub?.readiness?.factors ?? []).map {
            ReadinessFactorLine(key: $0.key, label: $0.label, score: $0.score)
        }
    }

    /// "Last 14 days" — as long as the series the tiles draw.
    private func window(_ summary: HealthSummary) -> String {
        let days = summary.figures.compactMap { $0.series?.count }.max() ?? 0
        return days > 1 ? "Last \(days) days" : "Recent"
    }
}

struct ReadinessFactorLine: Identifiable, Hashable {
    let key: String
    let label: String
    let score: Double
    var id: String { key }
}

/// The verdict on ink: the donut, the word, what to do, and its parts.
struct ReadinessBand: View {
    let summary: HealthSummary
    let factors: [ReadinessFactorLine]

    var body: some View {
        SRInkBand(kicker: "Readiness · Today", meta: updated, inset: 0) {
            if let readiness = summary.readiness {
                SRInkReadiness(readiness: readiness)
            } else {
                Text(summary.strap)
                    .font(SR.Text.body(15))
                    .foregroundStyle(SR.onInk(.note))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !factors.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("WHAT READINESS IS MADE OF")
                        .font(SR.Text.label())
                        .tracking(SR.inkLabelTracking)
                        .foregroundStyle(SR.onInk(.label))
                    ForEach(factors) { factor in
                        InkFactorBar(factor: factor)
                    }
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

private struct InkFactorBar: View {
    let factor: ReadinessFactorLine

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(factor.label.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.4)
                    .foregroundStyle(SR.onInk(.label))
                Spacer(minLength: 8)
                Text("\(Int(factor.score.rounded()))")
                    .font(SR.Text.figure(14))
                    .foregroundStyle(SR.onInk(.primary))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.onInk(.track))
                    Capsule().fill(SR.accentOnDark)
                        .frame(width: proxy.size.width * CGFloat(min(max(factor.score, 0), 100) / 100))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(factor.label): \(Int(factor.score.rounded())) out of 100")
    }
}

/// Move, Exercise and Stand as three bars on paper, with their goals.
struct ActivityTodayCard: View {
    let rings: ActivityRingsStore.Rings?

    /// The paper partners of the hero's ring colours.
    static let tints: [String: Color] = ["move": SR.accent, "exercise": SR.good, "stand": SR.accentInk]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let rings, !rings.isEmpty {
                ForEach(rings.all.compactMap { $0 }) { ring in
                    row(ring)
                }
            } else {
                Text("No rings from Apple Health yet today. They appear here once the Watch or this iPhone has recorded some.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: 20)
    }

    private func row(_ ring: ActivityRingsStore.Ring) -> some View {
        let tint = Self.tints[ring.key] ?? SR.accent
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    Circle().fill(tint).frame(width: 8, height: 8)
                    Text(ring.label.uppercased())
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(ring.value.rounded()))")
                        .font(SR.Text.figure(17))
                        .foregroundStyle(SR.ink)
                    Text("/ \(Int(ring.goal.rounded())) \(ring.unit)")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
                .lineLimit(1)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.line)
                    Capsule().fill(tint)
                        .frame(width: proxy.size.width * CGFloat(min(max(ring.fraction, 0), 1)))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ring.spoken)
    }
}

/// A figure over its window: the value, the line, and the movement — each
/// a push to the figure's own page.
struct FigureTrendTile: View {
    let figure: HealthFigure
    @EnvironmentObject private var router: Router

    var body: some View {
        Button {
            SRHaptic.tap()
            router.health.append(figure)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(figure.label.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(figure.inkValue.value)
                        .font(SR.Text.figure(26))
                        .foregroundStyle(SR.ink)
                    if let unit = figure.inkValue.unit {
                        Text(unit)
                            .font(SR.Text.mono(13))
                            .foregroundStyle(SR.inkMuted)
                    }
                }
                .lineLimit(1)
                if let series = figure.series, series.count > 1 {
                    SRSparkline(values: series)
                        .frame(height: 34)
                }
                Text(foot.uppercased())
                    .font(SR.Text.mono())
                    .tracking(1)
                    .foregroundStyle(tone)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SR.cardPadding)
            .srGlassCard(.paper, radius: 20, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(figure.label): \(figure.displayWithUnit), \(foot)"
            + (figure.improving == nil ? "" : figure.improving! ? ", improving" : ", worse")
        )
        .accessibilityAddTraits(.isButton)
    }

    /// "↗ +5 vs 7d", or the caption when there is no movement to show.
    private var foot: String {
        guard let delta = figure.deltaDisplay else { return figure.caption }
        let arrow = figure.direction == "down" ? "↘" : figure.direction == "up" ? "↗" : "→"
        return "\(arrow) \(delta)"
    }

    private var tone: Color {
        switch figure.improving {
        case .some(true): return SR.good
        case .some(false): return SR.accent
        case .none: return SR.inkMuted
        }
    }
}

import SwiftUI
import HealthKit

// MARK: - Move, from this iPhone

/// Today's Move ring, read from Apple Health on the phone.
///
/// Not from the site: the site hears about active energy when the companion
/// next uploads, which is hours behind the ring on the wrist. HealthKit has the
/// ring itself, and an `HKActivitySummaryQuery` with an update handler is told
/// every time the watch syncs — so the number on Today moves through the day
/// without a round trip.
///
/// No permission sheet from here. The companion asks for the activity summary
/// when the ring goals are on in its catalogue; if it was never granted,
/// HealthKit answers with nothing and the ring says "—" rather than a Today
/// screen that opens on a system prompt.
@MainActor
final class MoveRingStore: ObservableObject {
    struct Reading: Equatable, Sendable {
        let value: Double
        let goal: Double
        /// "kcal", or "min" for a ring in move-time mode.
        let unit: String

        var fraction: Double { goal > 0 ? value / goal : 0 }
    }

    @Published private(set) var reading: Reading?

    private let store = HKHealthStore()
    private var query: HKActivitySummaryQuery?
    private var day: DateComponents?

    /// Start watching today's ring, or re-point the watch at a new day. Cheap
    /// to call on every refresh: a query already on today is left alone.
    func start(now: Date = Date()) {
        // Demo mode (the review demo, or the screenshot harness): a ring part
        // closed, so Today's sun has a Move ring to draw. No launch flag is
        // read here, so this is safe in a Release build.
        if SRDemo.isOn { reading = Reading(value: 412, goal: 600, unit: "kcal"); return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let calendar = Calendar.current
        var today = calendar.dateComponents([.era, .year, .month, .day], from: now)
        today.calendar = calendar
        if query != nil, day == today { return }
        stop()
        day = today

        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: today, end: today)
        let handler: (HKActivitySummaryQuery, [HKActivitySummary]?, Error?) -> Void = { [weak self] _, summaries, _ in
            let latest = summaries?.last.flatMap(Self.reading(from:))
            Task { @MainActor in self?.reading = latest }
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

    nonisolated static func reading(from summary: HKActivitySummary) -> Reading? {
        if summary.activityMoveMode == .appleMoveTime {
            let value = summary.appleMoveTime.doubleValue(for: .minute())
            let goal = summary.appleMoveTimeGoal.doubleValue(for: .minute())
            return goal > 0 ? Reading(value: value, goal: goal, unit: "min") : nil
        }
        let value = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
        let goal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
        // A zero goal is a summary with no ring set up — nothing to be a
        // fraction of.
        return goal > 0 ? Reading(value: value, goal: goal, unit: "kcal") : nil
    }
}

// MARK: - The three numbers

/// Move, Recovery and Readiness, as the Today card draws them.
///
/// Pure, so the rules are tested without a view: which source wins, what an
/// absent number looks like, and that a ring past its goal still reads true.
struct TodayVital: Equatable, Identifiable {
    let key: String
    let label: String
    /// 0…1 of the arc, or more for a ring past its goal; nil draws an empty track.
    let fraction: Double?
    /// In the ring.
    let value: String
    /// Under the label.
    let caption: String?
    /// Read out.
    let spoken: String

    var id: String { key }

    static func make(health: TodayHealth?, move: MoveRingStore.Reading?) -> [TodayVital] {
        [moveVital(move), recoveryVital(health), readinessVital(health)]
    }

    static func moveVital(_ move: MoveRingStore.Reading?) -> TodayVital {
        guard let move else {
            return TodayVital(key: "move", label: "Move", fraction: nil, value: "—",
                              caption: "No ring yet", spoken: "Move: no reading yet")
        }
        let percent = Int((move.fraction * 100).rounded())
        let caption = "\(Int(move.value.rounded()))/\(Int(move.goal.rounded())) \(move.unit)"
        return TodayVital(key: "move", label: "Move", fraction: move.fraction, value: "\(percent)%",
                          caption: caption,
                          spoken: "Move: \(percent) percent of goal, \(caption)")
    }

    /// The figure first — it is the number /health prints — then the
    /// composite's own recovery factor, which is the same measurement in the
    /// readiness score's hands.
    static func recoveryVital(_ health: TodayHealth?) -> TodayVital {
        if let figure = health?.figures.first(where: { $0.key == "recovery" }), figure.measured {
            let caption = figure.deltaDisplay ?? figure.caption
            return TodayVital(key: "recovery", label: "Recovery", fraction: figure.value / 100,
                              value: "\(figure.display)%", caption: caption,
                              spoken: "Recovery: \(figure.display) percent, \(caption)")
        }
        if let factor = health?.readiness?.factors.first(where: { $0.key == "recovery" }) {
            let score = Int(factor.score.rounded())
            return TodayVital(key: "recovery", label: "Recovery", fraction: factor.score / 100,
                              value: "\(score)%", caption: nil,
                              spoken: "Recovery: \(score) percent")
        }
        return TodayVital(key: "recovery", label: "Recovery", fraction: nil, value: "—",
                          caption: "Not in yet", spoken: "Recovery: not in yet")
    }

    static func readinessVital(_ health: TodayHealth?) -> TodayVital {
        guard let readiness = health?.readiness else {
            return TodayVital(key: "readiness", label: "Readiness", fraction: nil, value: "—",
                              caption: "Not in yet", spoken: "Readiness: not in yet")
        }
        let score = Int(readiness.score.rounded())
        return TodayVital(key: "readiness", label: "Readiness", fraction: readiness.score / 100,
                          value: "\(score)", caption: readiness.label,
                          spoken: "Readiness: \(score), \(readiness.label)")
    }
}

/// Move, Recovery and Readiness as three concentric rings, outermost first.
/// A number with no reading draws its track and no arc.
///
/// Today's sun is the one place they are drawn now. It draws them thinner
/// (`lineScale`), sweeps them in on the first Today of a launch (`progress`
/// with `stagger`, each ring a beat after the one outside it), and fades the
/// site's two (`dimmed`) when the figures behind them are hours old.
struct TodayRings: View {
    let vitals: [TodayVital]
    /// How much of each arc is drawn, 0…1: the sunrise sweep. 1 draws the
    /// reading as it is.
    var progress: Double = 1
    /// The stroke, as a share of the side.
    var lineScale: CGFloat = 0.11
    /// Each ring sweeps in after the one outside it, instead of all at once.
    var stagger: Bool = false
    /// Keys whose ring is drawn at half strength.
    var dimmed: Set<String> = []
    /// Read here, not left to the caller: an `.animation(_:value:)` on the
    /// arc itself overrides any outer transaction that clears it, so only the
    /// ring can stop its own sweep under Reduce Motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func tint(_ key: String) -> Color {
        switch key {
        case "move": return SR.accent
        case "recovery": return SR.good
        default: return SR.accentInk
        }
    }

    static func line(side: CGFloat, lineScale: CGFloat) -> CGFloat { max(3, side * lineScale) }

    /// The clear disc inside the innermost ring, where a figure can go.
    static func hole(side: CGFloat, count: Int, lineScale: CGFloat) -> CGFloat {
        let line = line(side: side, lineScale: lineScale)
        let rings = CGFloat(max(1, count))
        return max(0, side - 2 * ((rings - 1) * (line + 1.5) + line))
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = Self.line(side: side, lineScale: lineScale)
            ZStack {
                ForEach(Array(vitals.enumerated()), id: \.element.id) { index, vital in
                    let inset = CGFloat(index) * (line + 1.5)
                    let tint = Self.tint(vital.key)
                    ZStack {
                        Circle().stroke(tint.opacity(0.16), lineWidth: line)
                        if let fraction = vital.fraction {
                            Circle()
                                .trim(from: 0, to: max(0, min(1, fraction)) * max(0, min(1, progress)))
                                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(stagger && !reduceMotion ? SRMotion.sweep.delay(0.2 + 0.08 * Double(index)) : nil,
                                           value: progress)
                        }
                    }
                    .opacity(dimmed.contains(vital.key) ? 0.5 : 1)
                    .padding(inset + line / 2)
                }
            }
            .frame(width: side, height: side)
            // A new reading eases in; under Reduce Motion it simply changes.
            .srAnimation(.easeInOut(duration: 0.4), value: vitals)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The sun's reading

/// What Today's sun says: its rings, the figure in the middle, the word
/// beside it and the colour of its glow.
///
/// Pure, like `TodayVital`, so who gets what is tested without a view. The
/// owner with the site paired gets the three rings and the readiness score;
/// anybody else — a member, or the owner before the site is paired — gets
/// the one ring this phone knows, Move, and its percentage. Nothing of the
/// site's ever reaches a member's sun: their endpoints would only refuse
/// them, and the figures are not theirs to read.
struct TodayHeroLead: Equatable {
    enum Band: Equatable {
        /// Readiness 70 and up.
        case good
        /// 40 to 69.
        case mid
        /// Under 40.
        case low
        /// No readiness to colour by: Move only, or not in yet.
        case neutral
    }

    /// Outermost first.
    let rings: [TodayVital]
    /// In the sun: "72", "69%", or "—".
    let figure: String
    /// What the figure rolls between when it changes.
    let figureValue: Double
    /// Beside the sun: "Primed", "Move", or nothing.
    let word: String
    let band: Band
    /// The site's figures are more than three hours old. Said, and the
    /// site's rings faded; no words are added to the screen.
    let stale: Bool
    /// The sun's VoiceOver label, after "Health. ".
    let spoken: String
    /// The owner's site figures, behind a long press. Empty for anybody else.
    let figures: [HealthFigure]
    /// The readiness verdict's advice, for the same.
    let recommendation: String?
    /// "412 / 600 kcal", for a Move-only long press.
    let moveDetail: String?
    /// The owner, with the site's figures in reach.
    let ownerSite: Bool

    /// The glow behind the figure.
    var bandTint: Color {
        switch band {
        case .good: return SR.good
        case .mid, .neutral: return SR.accent
        case .low: return SR.accentInk
        }
    }

    /// Past this, the site's figures are yesterday's news in all but name.
    static let staleAfter: TimeInterval = 3 * 3600

    static func band(_ score: Int?) -> Band {
        guard let score else { return .neutral }
        if score >= 70 { return .good }
        if score >= 40 { return .mid }
        return .low
    }

    static func make(ownerSite: Bool, health: TodayHealth?, move: MoveRingStore.Reading?, now: Date) -> TodayHeroLead {
        let moveVital = TodayVital.moveVital(move)
        let moveDetail = move.map { "\(Int($0.value.rounded())) / \(Int($0.goal.rounded())) \($0.unit)" }
        guard ownerSite else {
            let percent = move.map { Int(($0.fraction * 100).rounded()) }
            return TodayHeroLead(
                rings: [moveVital], figure: percent.map { "\($0)%" } ?? "—", figureValue: Double(percent ?? 0),
                word: "Move", band: .neutral, stale: false, spoken: moveVital.spoken,
                figures: [], recommendation: nil, moveDetail: moveDetail, ownerSite: false
            )
        }
        let vitals = TodayVital.make(health: health, move: move)
        let score = health?.readiness.map { Int($0.score.rounded()) }
        let generated = health.flatMap { isoDate($0.generatedAt) }
        let stale = generated.map { now.timeIntervalSince($0) > staleAfter } ?? false
        var spoken = vitals.map(\.spoken).joined(separator: ". ")
        if stale, let generated {
            // "06:40" on this phone's clock, whatever its 12/24-hour setting:
            // a 12-hour "06" with no am or pm would be a guess for the ear.
            let hm = Calendar.current.dateComponents([.hour, .minute], from: generated)
            spoken += ", as of " + String(format: "%02d:%02d", hm.hour ?? 0, hm.minute ?? 0)
        }
        if health?.isMock ?? false { spoken += ". Demonstration figures" }
        return TodayHeroLead(
            rings: vitals, figure: score.map { "\($0)" } ?? "—", figureValue: Double(score ?? 0),
            word: health?.readiness?.label ?? "", band: band(score), stale: stale, spoken: spoken,
            figures: health?.figures ?? [], recommendation: health?.readiness?.recommendation,
            moveDetail: moveDetail, ownerSite: true
        )
    }
}

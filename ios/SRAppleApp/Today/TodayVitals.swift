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

// MARK: - The card

/// Three small rings in one card: the day's answer, not the reasoning. The
/// Health tab, one tap away, has the rest.
struct TodayVitalsCard: View {
    let vitals: [TodayVital]
    var updated: String? = nil
    var isMock = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Health · today", trailing: updated)
                .padding(.horizontal, 4)
            SRCard(interactive: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(vitals) { vital in
                            VitalColumn(vital: vital, tint: tint(vital.key))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if isMock {
                        Text("Demonstration figures, not a measurement.")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func tint(_ key: String) -> Color {
        switch key {
        case "move": return SR.accent
        case "recovery": return SR.good
        default: return SR.warn
        }
    }
}

private struct VitalColumn: View {
    let vital: TodayVital
    let tint: Color
    @ScaledMetric(relativeTo: .body) private var ring: CGFloat = 52

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.16), lineWidth: 5)
                if let fraction = vital.fraction {
                    Circle()
                        .trim(from: 0, to: max(0, min(1, fraction)))
                        .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(vital.value)
                    .font(SR.Text.figure(16))
                    .foregroundStyle(vital.fraction == nil ? SR.inkMuted : SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(7)
            }
            .frame(width: ring, height: ring)
            .animation(.easeInOut(duration: 0.4), value: vital.fraction)

            Text(vital.label.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let caption = vital.caption {
                Text(caption)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(vital.spoken)
    }
}

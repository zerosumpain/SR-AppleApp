import Foundation
import HealthKit

/// Today's Move ring, read on the Watch itself — the way `MoveRingStore` does
/// on the phone — so it is live rather than as old as the last upload.
@MainActor
final class WatchMove: ObservableObject {
    struct Reading: Equatable, Sendable {
        let value: Double
        let goal: Double
        let unit: String
        var fraction: Double { goal > 0 ? value / goal : 0 }
    }

    @Published private(set) var reading: Reading?
    /// Whether the wearer has been asked. The Today page offers the question
    /// once, on a tap, rather than on launch.
    @Published private(set) var needsPermission = false

    private let store = HKHealthStore()
    private var query: HKActivitySummaryQuery?
    private var day: DateComponents?

    func start(now: Date = Date()) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        store.getRequestStatusForAuthorization(toShare: [], read: [HKObjectType.activitySummaryType()]) { status, _ in
            Task { @MainActor in self.needsPermission = status == .shouldRequest }
        }
        let calendar = Calendar.current
        var today = calendar.dateComponents([.era, .year, .month, .day], from: now)
        today.calendar = calendar
        if query != nil, day == today { return }
        if let query { store.stop(query) }
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

    func requestPermission() async {
        try? await store.requestAuthorization(toShare: [], read: [HKObjectType.activitySummaryType()])
        needsPermission = false
        query.map { store.stop($0) }
        query = nil
        start()
    }

    nonisolated static func reading(from summary: HKActivitySummary) -> Reading? {
        if summary.activityMoveMode == .appleMoveTime {
            let goal = summary.appleMoveTimeGoal.doubleValue(for: .minute())
            return goal > 0 ? Reading(value: summary.appleMoveTime.doubleValue(for: .minute()), goal: goal, unit: "min") : nil
        }
        let goal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
        return goal > 0 ? Reading(value: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()), goal: goal, unit: "kcal") : nil
    }
}

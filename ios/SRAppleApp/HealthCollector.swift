import Foundation
import HealthKit

@MainActor final class HealthCollector {
    let store = HKHealthStore()
    let outbox: Outbox
    var onUpdate: (() -> Void)?
    private var observers: [HKObserverQuery] = []
    private var collecting = false
    private var generation = 0
    static let labels = ["steps": "Steps", "heart_rate": "Heart rate", "resting_heart_rate": "Resting heart rate", "sleep": "Sleep", "workout": "Workouts"]
    init(outbox: Outbox) { self.outbox = outbox }
    func type(_ kind: String) -> HKSampleType {
        switch kind {
        case "steps": return HKQuantityType.quantityType(forIdentifier: .stepCount)!
        case "heart_rate": return HKQuantityType.quantityType(forIdentifier: .heartRate)!
        case "resting_heart_rate": return HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        case "sleep": return HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        default: return HKObjectType.workoutType()
        }
    }
    func authorize() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw CompanionError.message("Apple Health is unavailable on this device.") }
        let types = Set(outbox.state.healthEnabled.map { type($0) as HKObjectType })
        guard !types.isEmpty else { return }
        try await store.requestAuthorization(toShare: [], read: types)
        // Completion means the permission sheet finished, not that read access was granted.
        startObservers()
    }
    func startObservers() {
        generation += 1
        observers.forEach { store.stop($0) }; observers.removeAll()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        for kind in Self.labels.keys {
            let sampleType = type(kind)
            guard outbox.state.healthEnabled.contains(kind) else {
                store.disableBackgroundDelivery(for: sampleType) { _, _ in }; continue
            }
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completion, error in
                Task { @MainActor in
                    defer { completion() }
                    guard let self, error == nil else { return }
                    do { try await self.collect(); self.onUpdate?() } catch { /* Retry after unlock or next foreground sync. */ }
                    // And while we are awake anyway: take whatever the site has
                    // been trying to say.
                    //
                    // This app has no push certificate, so a notification only
                    // ever arrives on a wake the app already gets. There are two
                    // of those, and they are not equal: `BGAppRefreshTask` runs
                    // when iOS feels like it, which for an app opened twice a day
                    // is not often. HealthKit background delivery is scheduled —
                    // hourly, on an entitlement this app has held and used since
                    // the first version — and it fires precisely when the health
                    // figures the reader asked to be told about have changed.
                    //
                    // The site's three-hour floor still governs what is actually
                    // raised, so the extra wakes cost a request and nothing else.
                    await AlertStore.backgroundPass()
                }
            }
            observers.append(query); store.execute(query)
            store.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { _, _ in }
        }
    }
    func collect() async throws {
        guard !collecting, HKHealthStore.isHealthDataAvailable() else { return }
        collecting = true; defer { collecting = false }
        let startedGeneration = generation
        for kind in outbox.state.healthEnabled {
            if kind == "steps" { try await steps(generation: startedGeneration); continue }
            var more = true
            while more {
                let anchorData = outbox.state.anchors[kind]
                let anchor = try anchorData.map { try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) } ?? nil
                let result = try await changes(kind: kind, anchor: anchor)
                guard generation == startedGeneration, outbox.state.healthEnabled.contains(kind) else { return }
                try Task.checkCancellation()
                let records = result.0.map { record($0, kind: kind) }
                let deleted = result.1.map { $0.uuid.uuidString }
                let next = try result.2.map { try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
                try outbox.change {
                    if !records.isEmpty || !deleted.isEmpty { $0.batches.append(UploadBatch(health: records, deleted: deleted)) }
                    $0.anchors[kind] = next
                }
                more = result.0.count + result.1.count >= 200
            }
        }
    }
    private func changes(kind: String, anchor: HKQueryAnchor?) async throws -> ([HKSample], [HKDeletedObject], HKQueryAnchor?) {
        let predicate = HKQuery.predicateForSamples(withStart: outbox.state.historyStart, end: nil)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type(kind), predicate: predicate, anchor: anchor, limit: 200) { _, samples, deleted, next, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples ?? [], deleted ?? [], next)) }
            }
            store.execute(query)
        }
    }
    private func record(_ sample: HKSample, kind: String) -> HealthRecord {
        var result = HealthRecord(id: sample.uuid.uuidString, kind: kind, start: timestamp(sample.startDate), end: timestamp(sample.endDate), source: sample.sourceRevision.source.name)
        if let quantity = sample as? HKQuantitySample {
            result.value = quantity.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            result.unit = "bpm"
        } else if let sleep = sample as? HKCategorySample {
            result.stage = [0: "in_bed", 1: "asleep", 2: "awake", 3: "core", 4: "deep", 5: "rem"][sleep.value] ?? "asleep"
        } else if let workout = sample as? HKWorkout {
            result.value = workout.duration; result.unit = "seconds"
            result.activity = Self.workoutName(workout.workoutActivityType)
            result.distance = workout.totalDistance?.doubleValue(for: .meter())
            result.energy = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        }
        return result
    }
    static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: return "Walking"
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .traditionalStrengthTraining: return "Strength training"
        case .functionalStrengthTraining: return "Functional strength"
        default: return "Workout \(type.rawValue)"
        }
    }
    private func steps(generation startedGeneration: Int) async throws {
        let calendar = Calendar.current
        let recentStart = calendar.date(byAdding: .day, value: -29, to: Date())!
        let start = calendar.startOfDay(for: max(outbox.state.historyStart, recentStart))
        let end = Date()
        let quantity = type("steps") as! HKQuantityType
        let records: [HealthRecord] = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: quantity, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end), options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                var records: [HealthRecord] = []
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    // Use HealthKit's merged statistics, never sum raw phone and Watch samples.
                    guard let sum = stats.sumQuantity() else { return }
                    let date = calendar.dateComponents([.year, .month, .day], from: stats.startDate)
                    let id = String(format: "steps-%04d-%02d-%02d", date.year!, date.month!, date.day!)
                    records.append(HealthRecord(id: id, kind: "steps", start: timestamp(stats.startDate), end: timestamp(min(stats.endDate, end)), value: sum.doubleValue(for: .count()), unit: "count", source: "HealthKit daily statistics"))
                }
                continuation.resume(returning: records)
            }
            store.execute(query)
        }
        guard generation == startedGeneration, outbox.state.healthEnabled.contains("steps") else { return }
        try Task.checkCancellation()
        if !records.isEmpty { try outbox.change { $0.batches.append(UploadBatch(health: records)) } }
    }
}

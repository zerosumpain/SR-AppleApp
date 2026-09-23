import Foundation
import HealthKit
import CoreLocation

/// The route handler's running state. A box, not captured `var`s: the
/// handler may be imported as @Sendable, and mutating a captured var there does
/// not compile. HealthKit calls it serially, so no lock is needed.
private final class RouteGathering: @unchecked Sendable {
    var locations: [CLLocation] = []
    var finished = false
}

/// Reads the server's health catalogue out of HealthKit in four passes —
/// anchored samples, hourly statistics, daily steps and workouts (with their
/// series, route and events) — each under a deadline, so a background wake
/// stops in time and the rest resumes from the saved anchors next wake.
@MainActor final class HealthCollector {
    let store = HKHealthStore()
    let outbox: Outbox
    var onUpdate: (() -> Void)?
    private var observers: [HKObserverQuery] = []
    private var collecting = false
    private var alerting = false
    private var generation = 0

    init(outbox: Outbox) {
        self.outbox = outbox
        // Pre-catalogue installs: per-kind toggles become groups. The workout
        // re-read waits for `authorize()` (version 1 → 2): the widened groups
        // include types the reader has never been asked for, and a re-read
        // before they are granted would move the anchor past every workout
        // without its series or route.
        if outbox.state.catalogueVersion == 0 {
            try? outbox.change {
                $0.healthEnabled = HealthCatalogue.migrate($0.healthEnabled)
                $0.catalogueVersion = 1
            }
        }
    }

    var enabledKinds: [String] { HealthCatalogue.kinds(inGroups: outbox.state.healthEnabled) }

    /// An upgraded install whose new categories have not been put to the
    /// reader yet, or an enabled type HealthKit says was never asked for (a
    /// group turned on later). The second is cached by
    /// `refreshAuthorizationStatus()`, because HealthKit only answers async.
    var needsPermissionReview: Bool {
        (outbox.state.catalogueVersion < PersistedState.currentCatalogueVersion && !outbox.state.healthEnabled.isEmpty)
            || unrequestedTypes
    }

    private(set) var unrequestedTypes = false

    /// Asks HealthKit whether the permission sheet still has something to
    /// show for the enabled types (`.shouldRequest`). An error counts as no.
    func refreshAuthorizationStatus() async {
        let types = readTypes
        guard HKHealthStore.isHealthDataAvailable(), !types.isEmpty else { unrequestedTypes = false; return }
        let status: HKAuthorizationRequestStatus? = await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: types) { status, error in
                if error != nil { continuation.resume(returning: nil) } else { continuation.resume(returning: status) }
            }
        }
        unrequestedTypes = status == .shouldRequest
    }

    private static func quantityType(_ id: HKQuantityTypeIdentifier) -> HKQuantityType {
        HKQuantityType.quantityType(forIdentifier: id)!
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for kind in enabledKinds {
            if let type = HealthReadings.sampleType(for: kind) { types.insert(type) }
        }
        if enabledKinds.contains("workout") {
            // The workout pass reads these too (series, recovery, effort).
            for s in HealthReadings.workoutSeries { types.insert(Self.quantityType(s.type)) }
            types.insert(HKSeriesType.workoutRoute())
            if #available(iOS 18.0, *) {
                types.insert(Self.quantityType(.workoutEffortScore))
                types.insert(Self.quantityType(.estimatedWorkoutEffortScore))
            }
        }
        // The ring goals live on HKActivitySummary, which is not a sample type.
        if enabledKinds.contains(where: HealthReadings.isActivityGoal) { types.insert(HKObjectType.activitySummaryType()) }
        return types
    }

    func authorize() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw CompanionError.message("Apple Health is unavailable on this device.") }
        let types = readTypes
        guard !types.isEmpty else { return }
        try await store.requestAuthorization(toShare: [], read: types)
        // Completion means the permission sheet finished, not that read access was granted.
        // First time on the catalogue: now that the reader has been asked,
        // re-read every workout since historyStart WITH its route, series and
        // events. No await between this and `startObservers()`, whose
        // generation bump stops an in-flight pass committing the old anchor.
        if outbox.state.catalogueVersion < PersistedState.currentCatalogueVersion {
            try outbox.change {
                $0.anchors.removeValue(forKey: "workout")
                $0.catalogueVersion = PersistedState.currentCatalogueVersion
            }
        }
        startObservers()
    }

    func startObservers() {
        generation += 1
        observers.forEach { store.stop($0) }; observers.removeAll()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var observed = Set<HKSampleType>()
        for kind in enabledKinds {
            if let type = HealthReadings.sampleType(for: kind) { observed.insert(type) }
        }
        // Stop background delivery only for types no longer observed, so a
        // late-landing disable can never race the enables below.
        for kind in HealthCatalogue.file.kinds.keys {
            guard let type = HealthReadings.sampleType(for: kind), !observed.contains(type) else { continue }
            store.disableBackgroundDelivery(for: type) { _, _ in }
        }
        for sampleType in observed {
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completion, error in
                Task { @MainActor in
                    defer { completion() }
                    guard let self, error == nil else { return }
                    do { try await self.collect(until: Date().addingTimeInterval(20)); self.onUpdate?() } catch { /* resumes from anchors next wake */ }
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
                    //
                    // (One pass at a time: a wake fires every observer at once.)
                    guard !self.alerting else { return }
                    self.alerting = true
                    await AlertStore.backgroundPass()
                    self.alerting = false
                }
            }
            observers.append(query); store.execute(query)
            store.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { _, _ in }
        }
    }

    // MARK: - The passes

    func collect(until deadline: Date) async throws {
        guard !collecting, HKHealthStore.isHealthDataAvailable() else { return }
        collecting = true; defer { collecting = false }
        let startedGeneration = generation
        let live: () -> Bool = { self.generation == startedGeneration }
        for kind in enabledKinds {
            guard Date() < deadline, live() else { return }   // the rest resumes from anchors next wake
            // One kind's failure (typically a type the reader has not been
            // asked for yet: errorAuthorizationNotDetermined) skips that kind
            // only. Its anchor has not moved, so it resumes once granted.
            do {
                try await pass(kind: kind, deadline: deadline, generation: startedGeneration, live: live)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures[kind] = error.localizedDescription
                continue
            }
            failures.removeValue(forKey: kind)
        }
    }

    /// The last error per kind, cleared when that kind's pass next succeeds.
    private(set) var failures: [String: String] = [:]

    /// A group turned off: its kinds' errors no longer apply.
    func forgetFailures(for kinds: Set<String>) {
        for kind in kinds { failures.removeValue(forKey: kind) }
    }

    private func pass(kind: String, deadline: Date, generation startedGeneration: Int, live: () -> Bool) async throws {
        switch HealthReadings.reading(for: kind) {
        case .dailySteps:
            try await steps(generation: startedGeneration)
        case .hourly(let id, let unit, let options, let scale):
            try await hourly(kind: kind, id: id, unit: unit, options: options, scale: scale, live: live)
        case .sample, .standHour, .mindful, .stateOfMind, .sleep:
            try await anchored(kind: kind, deadline: deadline, live: live)
        case .workout:
            try await anchored(kind: kind, deadline: deadline, live: live)
            try await retryRoutes(deadline: deadline, live: live)
        case .activityGoal:
            // One summary query covers all three goals: run it for the first
            // enabled goal kind only, so it happens once per collect.
            guard kind == enabledKinds.first(where: HealthReadings.isActivityGoal) else { return }
            try await activityGoals(generation: startedGeneration)
        case .workoutPart, nil:
            return
        }
    }

    /// Anchored changes since historyStart; each page persists its anchor, so
    /// an interrupted pass loses at most one page. Workouts page by 10: each
    /// costs a dozen queries, and a page that never fits the deadline would
    /// never commit its anchor.
    private func anchored(kind: String, deadline: Date, live: () -> Bool) async throws {
        guard let sampleType = HealthReadings.sampleType(for: kind) else { return }
        let limit = kind == "workout" ? 10 : 200
        var more = true
        while more, Date() < deadline {
            let anchorData = outbox.state.anchors[kind]
            let anchor = try anchorData.map { try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) } ?? nil
            let (found, deleted, next) = try await changes(type: sampleType, anchor: anchor, limit: limit)
            guard live(), enabledKinds.contains(kind) else { return }
            try Task.checkCancellation()
            var records: [HealthRecord] = []
            for sample in found {
                try Task.checkCancellation()
                if kind == "workout", let w = sample as? HKWorkout {
                    let parts = try await workoutRecords(w)
                    records += parts
                } else if let r = record(sample, kind: kind) {
                    records.append(r)
                }
            }
            guard live(), enabledKinds.contains(kind) else { return }
            records = records.filter { HealthCatalogue.accepts($0) }
            let gone = deleted.map { $0.uuid.uuidString }
            let nextData = try next.map { try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
            try outbox.change {
                $0.batches += HealthBatching.batches(records)
                if !gone.isEmpty { $0.batches.append(UploadBatch(deleted: gone)) }
                $0.anchors[kind] = nextData
            }
            // A workout backfill runs for minutes: upload each page as it
            // lands rather than holding the lot until the pass ends.
            if kind == "workout", !records.isEmpty || !gone.isEmpty { onUpdate?() }
            more = found.count + deleted.count >= limit
        }
    }

    private func changes(type: HKSampleType, anchor: HKQueryAnchor?, limit: Int) async throws -> ([HKSample], [HKDeletedObject], HKQueryAnchor?) {
        let predicate = HKQuery.predicateForSamples(withStart: outbox.state.historyStart, end: nil)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: anchor, limit: limit) { _, samples, deleted, next, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples ?? [], deleted ?? [], next)) }
            }
            store.execute(query)
        }
    }

    private var zone: String { TimeZone.current.identifier }

    /// One HealthKit sample → one record, in the catalogue's unit. nil = not a
    /// record this kind sends (a stand hour spent idle is still a record: value 0).
    private func record(_ sample: HKSample, kind: String) -> HealthRecord? {
        var r = HealthRecord(id: sample.uuid.uuidString, kind: kind, start: timestamp(sample.startDate), end: timestamp(sample.endDate), source: sample.sourceRevision.source.name)
        r.tz = zone
        r.unit = HealthCatalogue.file.kinds[kind]?.unit
        switch HealthReadings.reading(for: kind) {
        case .sample(_, let unit, let scale):
            guard let q = sample as? HKQuantitySample else { return nil }
            r.value = q.quantity.doubleValue(for: unit) * scale
        case .standHour:
            guard let c = sample as? HKCategorySample else { return nil }
            r.value = c.value == HKCategoryValueAppleStandHour.stood.rawValue ? 1 : 0
        case .mindful:
            r.value = sample.endDate.timeIntervalSince(sample.startDate) / 60
        case .stateOfMind:
            if #available(iOS 18.0, *) {
                guard let s = sample as? HKStateOfMind else { return nil }
                r.value = s.valence
            } else {
                return nil
            }
        case .sleep:
            guard let c = sample as? HKCategorySample else { return nil }
            r.unit = nil
            r.stage = [0: "in_bed", 1: "asleep", 2: "awake", 3: "core", 4: "deep", 5: "rem"][c.value] ?? "asleep"
        default:
            return nil
        }
        return r
    }

    /// HealthKit's own merged statistics per UTC hour (spec E7): phone and
    /// Watch counted once, which is why these match the Health app. Ids are
    /// zone-free (`step_count-2026-09-23T14`), so a re-read replaces in place.
    private func hourly(kind: String, id: HKQuantityTypeIdentifier, unit: HKUnit, options: HKStatisticsOptions, scale: Double, live: () -> Bool) async throws {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let from = max(outbox.state.hourlyFrom[kind] ?? outbox.state.historyStart, outbox.state.historyStart)
        let start = utc.dateInterval(of: .hour, for: from)!.start
        let end = Date()
        let label = DateFormatter()
        label.calendar = utc; label.timeZone = utc.timeZone; label.locale = Locale(identifier: "en_US_POSIX"); label.dateFormat = "yyyy-MM-dd'T'HH"
        let catalogueUnit = HealthCatalogue.file.kinds[kind]?.unit
        let tz = zone
        let quantityType = Self.quantityType(id)
        let records: [HealthRecord] = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: quantityType, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end), options: options, anchorDate: start, intervalComponents: DateComponents(hour: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                var out: [HealthRecord] = []
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let quantity: HKQuantity? = options.contains(.cumulativeSum) ? stats.sumQuantity() : stats.averageQuantity()
                    guard let quantity else { return }
                    var r = HealthRecord(id: "\(kind)-\(label.string(from: stats.startDate))", kind: kind, start: timestamp(stats.startDate), end: timestamp(min(stats.endDate, end)), source: "HealthKit hourly statistics")
                    r.value = quantity.doubleValue(for: unit) * scale
                    r.unit = catalogueUnit
                    r.tz = tz
                    out.append(r)
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
        guard live(), enabledKinds.contains(kind) else { return }
        try Task.checkCancellation()
        let accepted = records.filter { HealthCatalogue.accepts($0) }
        // Only buckets whose value moved since they were last queued; the 48
        // hours re-read every wake would otherwise queue ~49 unchanged rows
        // per kind per wake, and fill the offline outbox within a day.
        var queued = 0
        try outbox.change {
            let (changed, sent) = HealthBatching.changed(accepted, since: $0.hourlySent[kind] ?? [:])
            $0.batches = HealthBatching.queue(changed, into: $0.batches)
            $0.hourlySent[kind] = sent
            $0.hourlyFrom[kind] = end.addingTimeInterval(-48 * 3600)
            queued = changed.count
        }
        if queued > 0 { onUpdate?() }
    }

    /// The pilot's own timeline reads `steps`: one record per local day.
    private func steps(generation startedGeneration: Int) async throws {
        let calendar = Calendar.current
        let recentStart = calendar.date(byAdding: .day, value: -29, to: Date())!
        let start = calendar.startOfDay(for: max(outbox.state.historyStart, recentStart))
        let end = Date()
        let quantity = Self.quantityType(.stepCount)
        let tz = zone
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
                    var r = HealthRecord(id: id, kind: "steps", start: timestamp(stats.startDate), end: timestamp(min(stats.endDate, end)), value: sum.doubleValue(for: .count()), unit: "count", source: "HealthKit daily statistics")
                    r.tz = tz
                    records.append(r)
                }
                continuation.resume(returning: records)
            }
            store.execute(query)
        }
        guard generation == startedGeneration, enabledKinds.contains("steps") else { return }
        try Task.checkCancellation()
        // As `hourly`: only days whose total moved, replacing any queued copy.
        let (changed, sent) = HealthBatching.changed(records, since: outbox.state.hourlySent["steps"] ?? [:])
        guard !changed.isEmpty || sent != (outbox.state.hourlySent["steps"] ?? [:]) else { return }
        try outbox.change {
            $0.batches = HealthBatching.queue(changed, into: $0.batches)
            $0.hourlySent["steps"] = sent
        }
    }

    /// Apple's daily Move, Exercise and Stand goals, one record per kind per
    /// local day, from the Activity summaries of the same 30 days `steps`
    /// re-reads. HKActivitySummary cannot be observed, so this rides every
    /// collect pass; the changed-only dedupe keeps unchanged goals out of the
    /// queue.
    private func activityGoals(generation startedGeneration: Int) async throws {
        let calendar = Calendar.current
        let now = Date()
        let recentStart = calendar.date(byAdding: .day, value: -29, to: now)!
        let dayParts: Set<Calendar.Component> = [.era, .year, .month, .day]
        var from = calendar.dateComponents(dayParts, from: max(outbox.state.historyStart, recentStart))
        var to = calendar.dateComponents(dayParts, from: now)
        from.calendar = calendar; to.calendar = calendar
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: from, end: to)
        let summaries: [HKActivitySummary] = try await withCheckedThrowingContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: summaries ?? []) }
            }
            store.execute(query)
        }
        guard generation == startedGeneration else { return }
        try Task.checkCancellation()
        let tz = zone
        var records: [HealthRecord] = []
        for summary in summaries {
            let goals = HealthReadings.activityGoals.map { (kind: $0.kind, value: HealthReadings.goal($0.kind, in: summary)) }
            records += HealthBatching.activityGoals(goals, day: summary.dateComponents(for: calendar), calendar: calendar, now: now, tz: tz)
        }
        // As `steps`, per kind: only days whose goal moved, replacing any queued copy.
        let kinds = HealthReadings.activityGoals.map(\.kind).filter(enabledKinds.contains)
        var updates: [(kind: String, changed: [HealthRecord], sent: [String: Double])] = []
        for kind in kinds {
            let accepted = records.filter { $0.kind == kind && HealthCatalogue.accepts($0) }
            let before = outbox.state.hourlySent[kind] ?? [:]
            let (changed, sent) = HealthBatching.changed(accepted, since: before)
            if !changed.isEmpty || sent != before { updates.append((kind: kind, changed: changed, sent: sent)) }
        }
        guard !updates.isEmpty else { return }
        try outbox.change {
            for update in updates {
                $0.batches = HealthBatching.queue(update.changed, into: $0.batches)
                $0.hourlySent[update.kind] = update.sent
            }
        }
    }

    // MARK: - Workouts

    private func fetchSamples(_ type: HKSampleType, _ predicate: NSPredicate) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }

    /// `[epoch seconds, value]` pairs, the shape a series chunk carries.
    private static func points(_ samples: [HKSample], unit: HKUnit) -> [[Double?]] {
        var out: [[Double?]] = []
        for sample in samples {
            guard let q = sample as? HKQuantitySample,
                  let point = HealthBatching.seriesPoint(epoch: sample.startDate.timeIntervalSince1970, value: q.quantity.doubleValue(for: unit)) else { continue }
            out.append(point)
        }
        return out
    }

    /// Activities whose route watchOS may save late. Gym work never gets one,
    /// and neither does a pool swim (swims are left out whole: an open-water
    /// route that lands late is the one loss), so neither earns a week of retries.
    private static let routed: [HKWorkoutActivityType] = [.walking, .running, .cycling, .hiking, .rowing, .paddleSports,
                                                          .crossCountrySkiing, .downhillSkiing, .snowboarding, .skatingSports,
                                                          .surfingSports, .sailing, .wheelchairWalkPace, .wheelchairRunPace]

    /// A workout as the pilot wants it (spec E9): the summary, then its series
    /// and route as chunk records. The route may not exist yet — watchOS saves
    /// it after the workout — so an outdoor workout without one is queued for
    /// `retryRoutes`.
    private func workoutRecords(_ w: HKWorkout) async throws -> [HealthRecord] {
        let id = w.uuid.uuidString, source = w.sourceRevision.source.name
        let metadata = w.metadata ?? [:]
        var r = HealthRecord(id: id, kind: "workout", start: timestamp(w.startDate), end: timestamp(w.endDate), value: w.duration, unit: "seconds", source: source)
        r.activity = HealthReadings.workoutName(w)
        r.tz = (metadata[HKMetadataKeyTimeZone] as? String) ?? zone
        r.indoor = metadata[HKMetadataKeyIndoorWorkout] as? Bool
        let distanceType: HKQuantityTypeIdentifier = w.workoutActivityType == .cycling ? .distanceCycling : .distanceWalkingRunning
        r.distance = w.statistics(for: Self.quantityType(distanceType))?.sumQuantity()?.doubleValue(for: .meter()) ?? w.totalDistance?.doubleValue(for: .meter())
        r.energy = w.statistics(for: Self.quantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        r.elevation = (metadata[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter())
        // kcal/(kg·hr), built rather than parsed: a bad unit string throws an
        // Objective-C exception, which Swift cannot catch.
        let metsUnit = HKUnit.kilocalorie().unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .hour()))
        r.mets = (metadata[HKMetadataKeyAverageMETs] as? HKQuantity)?.doubleValue(for: metsUnit)
        r.temperature = (metadata[HKMetadataKeyWeatherTemperature] as? HKQuantity)?.doubleValue(for: .degreeCelsius())
        if let humidity = metadata[HKMetadataKeyWeatherHumidity] as? HKQuantity { r.humidity = humidity.doubleValue(for: .percent()) * 100 }
        if let events = w.workoutEvents {
            var marks: [WorkoutEventRecord] = []
            for e in events {
                guard let name = HealthReadings.eventName(e.type) else { continue }
                marks.append(WorkoutEventRecord(type: name, start: timestamp(e.dateInterval.start), end: timestamp(e.dateInterval.end)))
            }
            r.events = marks
        }
        if #available(iOS 18.0, *) {
            let related = HKQuery.predicateForWorkoutEffortSamplesRelated(workout: w, activity: nil)
            for effortType in [HKQuantityTypeIdentifier.workoutEffortScore, HKQuantityTypeIdentifier.estimatedWorkoutEffortScore] {
                let found = try await fetchSamples(Self.quantityType(effortType), related)
                if let s = found.last as? HKQuantitySample {
                    r.effort = s.quantity.doubleValue(for: .appleEffortScore())
                    break
                }
            }
        }
        var out = [HealthBatching.finiteWorkoutFields(r)]
        // Series: samples HealthKit ASSOCIATES with the workout; a third-party
        // app may associate none, so fall back to the workout's time window.
        var seen = Set<String>()
        for s in HealthReadings.workoutSeries where !seen.contains(s.metric) {
            let type = Self.quantityType(s.type)
            var found = try await fetchSamples(type, HKQuery.predicateForObjects(from: w))
            if found.isEmpty { found = try await fetchSamples(type, HKQuery.predicateForSamples(withStart: w.startDate, end: w.endDate, options: .strictStartDate)) }
            let points = Self.points(found, unit: s.unit)
            guard !points.isEmpty else { continue }
            seen.insert(s.metric)
            out += HealthBatching.chunks(kind: "workout_series", workout: id, metric: s.metric, unit: HealthCatalogue.file.series[s.metric], points: points, source: source, size: HealthBatching.seriesChunk)
        }
        // Heart-rate recovery: the three minutes after the workout ends
        // (physio-service reads HRR60 from this).
        let after = try await fetchSamples(Self.quantityType(.heartRate), HKQuery.predicateForSamples(withStart: w.endDate, end: w.endDate.addingTimeInterval(180), options: []))
        let recovery = Self.points(after, unit: HealthReadings.bpm)
        if !recovery.isEmpty { out += HealthBatching.chunks(kind: "workout_series", workout: id, metric: "heart_rate_recovery", unit: "bpm", points: recovery, source: source, size: HealthBatching.seriesChunk) }
        let route = try await routePoints(w)
        if route.isEmpty, r.indoor != true, Self.routed.contains(w.workoutActivityType), w.endDate > Date().addingTimeInterval(-7 * 86400) {
            try outbox.change { $0.pendingRoutes[id] = w.endDate }
        }
        out += HealthBatching.chunks(kind: "workout_route", workout: id, metric: nil, unit: nil, points: route, source: source, size: HealthBatching.routeChunk)
        return out
    }

    /// `[epoch, lat, lon, altitude?, speed?, horizontal accuracy?]`, oldest first.
    private func routePoints(_ w: HKWorkout) async throws -> [[Double?]] {
        let routes = try await fetchSamples(HKSeriesType.workoutRoute(), HKQuery.predicateForObjects(from: w)).compactMap { $0 as? HKWorkoutRoute }
        var points: [[Double?]] = []
        for route in routes {
            let fixes = try await locations(of: route)
            for l in fixes {
                let altitude: Double? = l.verticalAccuracy >= 0 ? l.altitude : nil
                let speed: Double? = l.speed >= 0 ? l.speed : nil
                let accuracy: Double? = l.horizontalAccuracy >= 0 ? l.horizontalAccuracy : nil
                // Bounds-checked: one point the server refuses sinks the batch.
                guard let point = HealthBatching.routePoint(epoch: l.timestamp.timeIntervalSince1970, latitude: l.coordinate.latitude, longitude: l.coordinate.longitude,
                                                            altitude: altitude, speed: speed, accuracy: accuracy) else { continue }
                points.append(point)
            }
        }
        return points.sorted { ($0[0] ?? 0) < ($1[0] ?? 0) }
    }

    /// HKWorkoutRouteQuery calls its handler once per batch; resume once, on
    /// the last batch or the first error.
    private func locations(of route: HKWorkoutRoute) async throws -> [CLLocation] {
        let gathered = RouteGathering()
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                guard !gathered.finished else { return }
                if let error {
                    gathered.finished = true
                    continuation.resume(throwing: error)
                    return
                }
                if let batch { gathered.locations.append(contentsOf: batch) }
                if done {
                    gathered.finished = true
                    continuation.resume(returning: gathered.locations)
                }
            }
            store.execute(query)
        }
    }

    /// Routes watchOS saved after their workout. Seven days, then give up.
    private func retryRoutes(deadline: Date, live: () -> Bool) async throws {
        for (id, ended) in outbox.state.pendingRoutes {
            guard Date() < deadline, live() else { return }
            if ended < Date().addingTimeInterval(-7 * 86400) {
                try outbox.change { $0.pendingRoutes.removeValue(forKey: id) }
                continue
            }
            guard let uuid = UUID(uuidString: id) else {
                try outbox.change { $0.pendingRoutes.removeValue(forKey: id) }
                continue
            }
            let found = try await fetchSamples(HKObjectType.workoutType(), HKQuery.predicateForObject(with: uuid))
            guard let w = found.first as? HKWorkout else { continue }
            let route = try await routePoints(w)
            guard !route.isEmpty, live() else { continue }
            let chunks = HealthBatching.chunks(kind: "workout_route", workout: id, metric: nil, unit: nil, points: route, source: w.sourceRevision.source.name, size: HealthBatching.routeChunk)
            try outbox.change {
                $0.batches += HealthBatching.batches(chunks)
                $0.pendingRoutes.removeValue(forKey: id)
            }
        }
    }
}

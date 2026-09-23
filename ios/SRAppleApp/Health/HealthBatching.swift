import Foundation

enum HealthBatching {
    static let routeChunk = 2000   // == ROUTE_POINT_LIMIT on the server
    static let seriesChunk = 5000  // == SERIES_POINT_LIMIT
    static let plainPerBatch = 400 // under the server's 500, leaving room for deletions

    static func chunks(kind: String, workout: String, metric: String?, unit: String?, points: [[Double?]], source: String, size: Int) -> [HealthRecord] {
        stride(from: 0, to: points.count, by: size).enumerated().map { index, offset in
            let slice = Array(points[offset..<min(offset + size, points.count)])
            let first = Date(timeIntervalSince1970: slice.first?[0] ?? 0), last = Date(timeIntervalSince1970: slice.last?[0] ?? 0)
            let id = metric.map { "series:\(workout):\($0):\(index)" } ?? "route:\(workout):\(index)"
            var r = HealthRecord(id: id, kind: kind, start: timestamp(first), end: timestamp(last), source: source)
            r.workout = workout; r.metric = metric; r.unit = unit; r.chunk = index; r.points = slice
            return r
        }
    }

    /// One route point in the server's bounds, or nil to drop it. A position
    /// out of range drops the point; an out-of-range altitude, speed or
    /// accuracy (CoreLocation's -1 = unknown, or a wild reading) becomes nil.
    /// One bad point would otherwise get the whole batch refused, forever.
    static func routePoint(epoch: Double, latitude: Double, longitude: Double, altitude: Double?, speed: Double?, accuracy: Double?) -> [Double?]? {
        guard epoch.isFinite, epoch > 1e9, latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        func within(_ x: Double?, _ range: ClosedRange<Double>) -> Double? {
            guard let x, x.isFinite, range.contains(x) else { return nil }
            return x
        }
        let point: [Double?] = [epoch.rounded(), latitude, longitude, within(altitude, -500...9000), within(speed, 0...400), within(accuracy, 0...10000)]
        return point
    }

    /// One series point in the server's bounds, or nil to drop it.
    static func seriesPoint(epoch: Double, value: Double) -> [Double?]? {
        guard epoch.isFinite, epoch > 1e9, value.isFinite, abs(value) <= 1e6 else { return nil }
        let point: [Double?] = [epoch.rounded(), value]
        return point
    }

    static func batches(_ records: [HealthRecord]) -> [UploadBatch] {
        let parts = records.filter { $0.points != nil }, plain = records.filter { $0.points == nil }
        let plainBatches = stride(from: 0, to: plain.count, by: plainPerBatch).map { UploadBatch(health: Array(plain[$0..<min($0 + plainPerBatch, plain.count)])) }
        return plainBatches + parts.map { UploadBatch(health: [$0]) }
    }

    // MARK: - Re-read buckets

    /// The hourly (or daily) buckets whose value differs from the one last
    /// queued, and the map to keep for next time: exactly the buckets read
    /// now, so ids that have left the re-read window fall out by themselves.
    /// A record without a value is always sent.
    static func changed(_ records: [HealthRecord], since sent: [String: Double]) -> (changed: [HealthRecord], sent: [String: Double]) {
        var out: [HealthRecord] = [], next: [String: Double] = [:]
        for r in records {
            if let value = r.value {
                next[r.id] = value
                if sent[r.id] == value { continue }
            }
            out.append(r)
        }
        return (out, next)
    }

    /// Appends `records`, first dropping any still-queued record with the same
    /// id: a bucket updated twice before an upload travels once, with its
    /// latest value. A batch left empty by that is removed.
    static func queue(_ records: [HealthRecord], into queued: [UploadBatch]) -> [UploadBatch] {
        guard !records.isEmpty else { return queued }
        let ids = Set(records.map(\.id))
        var kept = queued
        for index in kept.indices { kept[index].health.removeAll { ids.contains($0.id) } }
        kept.removeAll { $0.health.isEmpty && $0.locations.isEmpty && $0.deleted.isEmpty }
        return kept + batches(records)
    }

    // MARK: - Activity-ring goals

    /// One `HKActivitySummary` day's goals as daily records: ids
    /// `move_goal-2026-09-22` from the summary's OWN date components (so a
    /// re-read replaces in place), spanning that local day, its end clamped to
    /// `now`. A goal that is missing, zero or not finite is left out — an old
    /// summary has no exercise goal, and a Move Time user's energy goal is 0.
    static func activityGoals(_ goals: [(kind: String, value: Double?)], day: DateComponents, calendar: Calendar, now: Date, tz: String) -> [HealthRecord] {
        guard let year = day.year, let month = day.month, let date = day.day else { return [] }
        var components = DateComponents(year: year, month: month, day: date)
        components.era = day.era
        guard let start = calendar.date(from: components), start <= now,
              let next = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let end = min(next, now)
        let label = String(format: "%04d-%02d-%02d", year, month, date)
        return goals.compactMap { goal in
            guard let value = goal.value, value.isFinite, value > 0 else { return nil }
            var r = HealthRecord(id: "\(goal.kind)-\(label)", kind: goal.kind, start: timestamp(start), end: timestamp(end), value: value,
                                 unit: HealthCatalogue.file.kinds[goal.kind]?.unit, source: "HealthKit activity summary")
            r.tz = tz
            return r
        }
    }

    // MARK: - Refused batches

    /// 400 (a record the server will never take) or 413 (too big): sending the
    /// same batch again can only fail again. Anything else — offline, 5xx,
    /// 401, 409 — may pass later, so it waits and retries.
    static func isRefusal(status: Int) -> Bool { status == 400 || status == 413 }

    /// A refused batch in two halves — health, then locations, then deletions,
    /// in order — so the good records still go; `[]` when it held one record,
    /// which the caller drops. Each half is non-empty and strictly smaller, so
    /// halving always ends.
    static func split(_ b: UploadBatch) -> [UploadBatch] {
        let total = b.health.count + b.locations.count + b.deleted.count
        guard total > 1 else { return [] }
        let half = total / 2
        let h = min(b.health.count, half)
        let l = min(b.locations.count, half - h)
        let d = half - h - l
        let first = UploadBatch(health: Array(b.health.prefix(h)), locations: Array(b.locations.prefix(l)), deleted: Array(b.deleted.prefix(d)))
        let second = UploadBatch(health: Array(b.health.dropFirst(h)), locations: Array(b.locations.dropFirst(l)), deleted: Array(b.deleted.dropFirst(d)))
        return [first, second]
    }

    /// The server's reason for a body it could not parse: a truncated upload,
    /// never the record's fault, so it never costs a record.
    static let invalidJSON = "Invalid JSON"

    // MARK: - Guards and reporting

    /// Optional workout figures with NaN/infinity cleared: a non-finite
    /// Double makes JSONEncoder throw inside `outbox.change`, which would fail
    /// the whole workout pass on every wake.
    static func finiteWorkoutFields(_ record: HealthRecord) -> HealthRecord {
        var r = record
        func finite(_ x: Double?) -> Double? { x.flatMap { $0.isFinite ? $0 : nil } }
        r.distance = finite(r.distance); r.energy = finite(r.energy); r.elevation = finite(r.elevation)
        r.mets = finite(r.mets); r.temperature = finite(r.temperature); r.humidity = finite(r.humidity)
        r.effort = finite(r.effort)
        return r
    }

    /// One line for the status message: a full outbox first (it stops
    /// location too), else how many kinds could not be read, with one reason.
    static func failureSummary(_ failures: [String: String]) -> String? {
        guard !failures.isEmpty else { return nil }
        if failures.values.contains(outboxFullMessage) { return outboxFullMessage }
        let kinds = failures.keys.sorted()
        let what = kinds.count == 1 ? kinds[0] : "\(kinds.count) health kinds"
        return "Could not read \(what) from Apple Health: \(failures[kinds[0]] ?? "unknown error")"
    }
}


/// What to do with a batch the server refused (400/413).
enum RefusalStep: Equatable {
    /// Halve it and send the halves.
    case split
    /// A lone record the server will not take while it takes others: drop it.
    case drop
    /// Keep it, skip it for the rest of this flush, try the batches behind it.
    case hold
    /// Stop the flush, keep everything, retry later.
    case stop
}

/// One flush's evidence about refusals. A 400 is not always the record's
/// fault: a catalogue the deployed server does not know yet, a phone clock
/// ahead, a truncated body. Anchors and `hourlySent` have already moved on,
/// so a dropped record is gone for good — a record is dropped only once the
/// server has accepted something else in the same flush, a deletion never,
/// and three refusals in a row stop the flush with everything kept.
struct UploadRound {
    private(set) var acceptedAny = false
    private(set) var consecutiveRefusals = 0
    /// Lone refused batches set aside for this flush.
    private(set) var held: Set<UUID> = []
    /// Held batches that become droppable once anything is accepted.
    private(set) var awaitingEvidence: [UUID] = []

    static let breaker = 3

    /// The next batch to send: the first one not set aside.
    func next(in queue: [UploadBatch]) -> UploadBatch? { queue.first { !held.contains($0.id) } }

    /// The server took a batch. Returns the held batches that can now be
    /// dropped: it has shown it takes records, so theirs was refused on merit.
    mutating func accepted() -> [UUID] {
        acceptedAny = true
        consecutiveRefusals = 0
        let evidenced = awaitingEvidence
        awaitingEvidence = []
        return evidenced
    }

    /// The server refused `batch` (as it stands in the queue now) with `reason`.
    /// A reason that is not our server's own JSON (`uploadFallbackMessage`:
    /// a proxy's page, say) or "Invalid JSON" says nothing about the record.
    mutating func refused(_ batch: UploadBatch, reason: String) -> RefusalStep {
        consecutiveRefusals += 1
        let transient = reason == HealthBatching.invalidJSON || reason == uploadFallbackMessage
        if transient || consecutiveRefusals >= Self.breaker { return .stop }
        if batch.health.count + batch.locations.count + batch.deleted.count > 1 { return .split }
        let deletion = !batch.deleted.isEmpty
        if acceptedAny && !deletion { return .drop }
        held.insert(batch.id)
        if !deletion { awaitingEvidence.append(batch.id) }
        return .hold
    }
}

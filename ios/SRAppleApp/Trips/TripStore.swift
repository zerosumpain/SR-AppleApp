import Foundation
import Combine
import Network
import CoreLocation

// The trip companion's memory: every trip bundle kept on disk so a whole
// day in Rome works in airplane mode, what happened at each stop, the days
// re-planned on the phone, and the events waiting to go up.
//
// One rule from the contract decides what wins: while a day is running the
// PHONE's version of that day wins. A site edit to today that lands after a
// phone version is listed in the plan's `changes` ("Changed on the site
// while you were out — …") and the phone shows it rather than swapping the
// day out from under the person walking it.

// MARK: - Network

/// Online or not, and whether on Wi-Fi (unmetered) — the day's map pack
/// waits for that. The queue drains whenever a path comes back.
@MainActor
final class TripNetwork: ObservableObject {
    static let shared = TripNetwork()

    @Published private(set) var online = true
    @Published private(set) var unmetered = false

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            let unmetered = online && !path.isExpensive && !path.isConstrained
            Task { @MainActor in
                let wasOffline = !TripNetwork.shared.online
                TripNetwork.shared.online = online
                TripNetwork.shared.unmetered = unmetered
                if online && wasOffline { await TripEventQueue.shared.flush() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "sr.trips.network"))
    }
}

// MARK: - Files

enum TripFiles {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trips", isDirectory: true)
    }

    static func url(_ name: String) -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.")
        let safe = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
        return directory.appendingPathComponent(safe)
    }

    static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        write(data, name)
    }

    static func write(_ data: Data, _ name: String) {
        // A demo's made-up Rome must never land in a real trip's files.
        guard !SRDemo.isOn else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Readable after first unlock, like the route cache: arrival
        // detection wakes the app in the background with the phone locked.
        try? data.write(to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
    }
}

// MARK: - The store

@MainActor
final class TripStore: ObservableObject {
    static let shared = TripStore()

    /// A day re-planned on the phone, and the server version that stored it.
    struct LocalDay: Codable, Hashable {
        var day: PlannedDay
        var appliedAt: Date
        var label: String
        /// The plan version the server answered with once it took the event.
        var acceptedVersion: Int?
    }

    /// Everything on the phone that is not the server's bundle.
    private struct Local: Codable {
        var days: [String: [String: LocalDay]] = [:]
        var marks: [String: [String: TripStopMark]] = [:]
    }

    @Published private(set) var summaries: [TripSummary] = []
    @Published private(set) var bundles: [String: TripBundle] = [:]
    @Published private(set) var loading = false
    /// 403: trips are the owner's for now.
    @Published private(set) var ownerOnly = false
    @Published var message: String?
    @Published private(set) var refreshedAt: Date?
    @Published private var local = Local()

    private static let indexFile = "index.json"
    private static let localFile = "local.json"
    private static func bundleFile(_ id: String) -> String { "bundle-\(id).json" }

    private init() {
        if SRDemo.isOn {
            TripDemo.seed(into: self)
            return
        }
        summaries = TripFiles.read([TripSummary].self, Self.indexFile) ?? []
        for summary in summaries {
            if let bundle = TripFiles.read(TripBundle.self, Self.bundleFile(summary.id)) {
                bundles[summary.id] = bundle
            }
        }
        local = TripFiles.read(Local.self, Self.localFile) ?? Local()
    }

    // MARK: Reading

    /// The day as it should be shown: the phone's own version when it has
    /// one for that date, else the server's.
    func day(_ tripId: String, _ date: String) -> PlannedDay? {
        local.days[tripId]?[date]?.day ?? bundles[tripId]?.day(date)
    }

    func localDay(_ tripId: String, _ date: String) -> LocalDay? { local.days[tripId]?[date] }

    func marks(_ tripId: String) -> [String: TripStopMark] { local.marks[tripId] ?? [:] }

    func clock(_ tripId: String) -> TripClock? {
        (bundles[tripId]?.trip.timeZone ?? summaries.first { $0.id == tripId }?.timeZone).map(TripClock.init)
    }

    /// The trip whose date range includes today in ITS time zone, with
    /// that local date. The first such, by start date.
    func running(now: Date = Date()) -> (bundle: TripBundle, date: String)? {
        for summary in summaries.sorted(by: { $0.startDate < $1.startDate }) where summary.status != .draft {
            let clock = TripClock(summary.timeZone)
            let today = clock.localDate(now)
            guard TripClock.within(today, summary.startDate, summary.endDate),
                  let bundle = bundles[summary.id] else { continue }
            return (bundle, today)
        }
        return nil
    }

    /// The next trip that has not started, for Today's quieter card.
    func upcoming(now: Date = Date()) -> TripSummary? {
        summaries
            .filter { $0.status != .done && TripClock($0.timeZone).localDate(now) < $0.startDate }
            .min { $0.startDate < $1.startDate }
    }

    func progress(_ tripId: String, _ date: String, now: Date = Date()) -> TripProgress? {
        guard let day = day(tripId, date), let clock = clock(tripId) else { return nil }
        return TripProgress.of(day: day, marks: marks(tripId), nowMin: clock.minutes(now), clock: clock)
    }

    /// "Changed on the site while you were out — …", for a day the phone holds.
    func siteChanges(_ tripId: String) -> [String] {
        (bundles[tripId]?.plan?.changes ?? []).filter { $0.hasPrefix("Changed on the site while you were out") }
    }

    // MARK: Refreshing

    /// The list, then every trip that is not over, each on its ETag.
    func refresh() async {
        guard AccessStore.ownerSite || SRDemo.isOn, !loading else { return }
        loading = true
        defer { loading = false }
        await TripEventQueue.shared.flush()
        do {
            let list = try await TripsAPI.list()
            ownerOnly = false
            summaries = list
            TripFiles.write(list, Self.indexFile)
            let now = Date()
            for summary in list where summary.status != .done || bundles[summary.id] == nil {
                // A trip that ended more than a week ago keeps whatever it has.
                if let end = TripClock(summary.timeZone).days(from: summary.endDate, to: TripClock(summary.timeZone).localDate(now)), end > 7,
                   bundles[summary.id] != nil { continue }
                await fetch(summary.id)
            }
            prune(keeping: Set(list.map(\.id)))
            refreshedAt = now
            message = nil
        } catch TripsAPI.Failure.ownerOnly {
            ownerOnly = true
            message = nil
        } catch is CancellationError {
            return
        } catch {
            // Offline is the expected case on a trip: the cache stands and
            // the screen says how old it is, not that something broke.
            if let failure = error as? TripsAPI.Failure, case .offline = failure, !summaries.isEmpty {
                message = nil
            } else {
                message = error.localizedDescription
            }
        }
    }

    /// Re-read at most every few minutes from a foreground or an appearance.
    func refreshIfStale(after seconds: TimeInterval = 300) async {
        if let refreshedAt, Date().timeIntervalSince(refreshedAt) < seconds { return }
        await refresh()
    }

    func fetch(_ id: String) async {
        do {
            switch try await TripsAPI.bundle(id, etag: bundles[id]?.etag) {
            case .unchanged:
                break
            case .fresh(let bundle, _):
                bundles[id] = bundle
                TripFiles.write(bundle, Self.bundleFile(id))
                settleLocalDays(id)
            }
        } catch TripsAPI.Failure.ownerOnly {
            ownerOnly = true
        } catch {
            // Kept: the cached bundle is the day's map and plan.
        }
    }

    /// Phone versions of days that are no longer running, and that the
    /// server has stored, give way to the server's plan. Today's stays.
    private func settleLocalDays(_ tripId: String) {
        guard var days = local.days[tripId], let bundle = bundles[tripId] else { return }
        let today = TripClock(bundle.trip.timeZone).localDate(Date())
        let version = bundle.plan?.version ?? 0
        for (date, kept) in days where date != today {
            if date < today || (kept.acceptedVersion.map { version >= $0 } ?? false) { days[date] = nil }
        }
        local.days[tripId] = days
        persistLocal()
    }

    private func prune(keeping ids: Set<String>) {
        for id in bundles.keys where !ids.contains(id) {
            bundles[id] = nil
            TripFiles.remove(Self.bundleFile(id))
        }
    }

    // MARK: Recording

    /// Something happened at a stop. Marks it here at once, queues the
    /// event, and sends it if there is signal.
    func record(_ kind: TripEventKind, tripId: String, stop: PlannedStop?, at: Date = Date(), detail: [String: TripJSON]? = nil, corrected: Bool = false) {
        if let stop {
            var marks = local.marks[tripId] ?? [:]
            var mark = marks[stop.id] ?? TripStopMark()
            switch kind {
            case .arrived: mark.arrivedAt = at
            case .left:
                mark.leftAt = at
                if mark.arrivedAt == nil { mark.arrivedAt = at }
            case .skipped: mark.skipped = true
            default: break
            }
            if corrected { mark.corrected = true }
            marks[stop.id] = mark
            local.marks[tripId] = marks
            persistLocal()
        }
        var detail = detail
        if corrected { detail = (detail ?? [:]).merging(["corrected": .bool(true)]) { a, _ in a } }
        let event = TripEvent(
            clientId: UUID().uuidString.lowercased(), kind: kind, stopId: stop?.id, wishId: stop?.wishId,
            at: Self.iso(at), detail: detail
        )
        TripEventQueue.shared.add(event, trip: tripId, basePlanVersion: bundles[tripId]?.plan?.version ?? 0)
        Task { await TripEventQueue.shared.flush() }
        TripLive.shared.refresh()
    }

    /// Undo a mark the phone got wrong — "not here yet", "not skipped".
    /// Local only: the contract has no event for taking one back, so the
    /// server keeps the original and the phone's next plan supersedes it.
    func clear(_ stopId: String, tripId: String) {
        local.marks[tripId]?[stopId] = nil
        persistLocal()
        TripLive.shared.refresh()
    }

    /// One tap on an option: the phone's version of the day, at once, and
    /// `option-applied` with the new day queued for the server.
    func apply(_ option: ReplanOption, tripId: String) {
        var days = local.days[tripId] ?? [:]
        days[option.day.date] = LocalDay(day: option.day, appliedAt: Date(), label: option.label, acceptedVersion: nil)
        local.days[tripId] = days
        persistLocal()
        var detail: [String: TripJSON] = ["optionId": .string(option.id), "label": .string(option.label)]
        if let day = TripJSON.from(option.day) { detail["day"] = day }
        record(.optionApplied, tripId: tripId, stop: nil, detail: detail)
        TripArrivals.shared.refresh()
    }

    /// The server took an `option-applied`: remember which version stored it.
    func accepted(planVersion: Int, tripId: String, dates: [String]) {
        guard var days = local.days[tripId] else { return }
        for date in dates where days[date] != nil { days[date]?.acceptedVersion = planVersion }
        local.days[tripId] = days
        persistLocal()
    }

    private func persistLocal() {
        TripFiles.write(local, Self.localFile)
    }

    nonisolated static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// The demo's Rome day (`-SRDemo` and the review demo), held in memory
    /// only: nothing a real trip keeps on disk is touched.
    func adoptDemo(_ bundle: TripBundle, marks: [String: TripStopMark]) {
        bundles[bundle.trip.id] = bundle
        summaries = [bundle.summary]
        local.marks[bundle.trip.id] = marks
    }
}

// MARK: - The event queue

/// Events not yet accepted by the site, oldest first, kept on disk. Modelled
/// on `RecordingQueue`: idempotent on `clientId` (the server keeps one row
/// per trip and clientId), so a retry after a lost reply records nothing twice.
@MainActor
final class TripEventQueue: ObservableObject {
    static let shared = TripEventQueue()

    struct Pending: Codable, Hashable {
        var tripId: String
        var basePlanVersion: Int
        var event: TripEvent
    }

    @Published private(set) var pending: [Pending] = []
    @Published private(set) var lastError: String?

    private static let file = "events.json"
    private var sending = false

    private init() {
        pending = TripFiles.read([Pending].self, Self.file) ?? []
    }

    func add(_ event: TripEvent, trip: String, basePlanVersion: Int) {
        pending.removeAll { $0.event.clientId == event.clientId }
        pending.append(Pending(tripId: trip, basePlanVersion: basePlanVersion, event: event))
        persist()
    }

    func count(for tripId: String) -> Int { pending.filter { $0.tripId == tripId }.count }

    /// Send what is waiting, a trip at a time in the order it happened.
    /// Stops at the first network failure: the rest would fail the same way.
    func flush() async {
        guard !sending, !pending.isEmpty, SiteClient.shared.isPaired, !SRDemo.isOn else { return }
        sending = true
        defer { sending = false }
        while let head = pending.first {
            // The head's trip, and as many of its events as follow it at the
            // same base version — one request, not one per footstep.
            let batch = Array(pending.prefix { $0.tripId == head.tripId && $0.basePlanVersion == head.basePlanVersion }.prefix(50))
            do {
                let reply = try await TripsAPI.send(
                    events: batch.map(\.event), basePlanVersion: head.basePlanVersion, trip: head.tripId
                )
                let sent = Set(batch.map(\.event.clientId))
                pending.removeAll { sent.contains($0.event.clientId) }
                persist()
                lastError = nil
                let appliedDates = batch
                    .filter { $0.event.kind == .optionApplied && reply.accepted.contains($0.event.clientId) }
                    .compactMap { $0.event.detail?["day"]?.decode(PlannedDay.self)?.date }
                if !appliedDates.isEmpty {
                    TripStore.shared.accepted(planVersion: reply.planVersion, tripId: head.tripId, dates: appliedDates)
                }
            } catch TripsAPI.Failure.refused(let status, let sentence) where (400..<500).contains(status) && status != 408 && status != 429 {
                // Refused outright: retrying will not change its mind, and a
                // stuck head would block every later event.
                let sent = Set(batch.map(\.event.clientId))
                pending.removeAll { sent.contains($0.event.clientId) }
                persist()
                lastError = sentence
            } catch {
                lastError = error.localizedDescription
                return
            }
        }
    }

    private func persist() {
        TripFiles.write(pending, Self.file)
    }
}

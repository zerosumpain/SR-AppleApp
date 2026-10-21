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
        /// v8: each trip's latest change and its Undo. Optional, so a file
        /// written before it existed still reads (a missing key is not a
        /// default for synthesised Codable).
        var changes: [String: TripChangeRecord]? = nil
        /// v8: the answer this phone voted for, by question id.
        var votes: [String: String]? = nil
    }

    @Published private(set) var summaries: [TripSummary] = []
    @Published private(set) var bundles: [String: TripBundle] = [:]
    @Published private(set) var loading = false
    /// 403: trips are the owner's for now.
    @Published private(set) var ownerOnly = false
    @Published var message: String?
    @Published private(set) var refreshedAt: Date?
    @Published private var local = Local()
    /// v8: what is being sent right now — a proposal's id, a question's id,
    /// `swap:<stopId>`, `day:<date>`, `undo:<tripId>`, `brief:<tripId>` — so
    /// its card shows it is working and cannot be tapped twice.
    @Published private(set) var busy: Set<String> = []
    /// v8: what became of proposals and questions decided on this phone
    /// ("Used", "Turned down", "Answered: Carry on"), for a conversation that
    /// still shows the card it came with.
    @Published private(set) var decided: [String: String] = [:]

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
        // v5: every family member with a site pairing sees the family's trips.
        guard SiteClient.shared.isPaired || SRDemo.isOn, !loading else { return }
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
            // v7: the evening-before briefings and booking nudges, on this phone.
            await TripReminders.sync(Array(bundles.values))
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
                // v7: the places' photographs and the forecast go offline with the trip.
                TripPhotos.shared.prefetch(bundle)
                TripWeatherStore.shared.refresh(bundle)
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

    /// Delete a trip this person started: on the site, then everything this
    /// phone kept of it — the offline copy, its own day versions and marks,
    /// the reminders and the arrival geofences. Nil when it went; otherwise why not.
    func delete(_ id: String) async -> String? {
        do {
            try await TripsAPI.delete(trip: id)
        } catch {
            return error.localizedDescription
        }
        summaries.removeAll { $0.id == id }
        TripFiles.write(summaries, Self.indexFile)
        bundles[id] = nil
        TripFiles.remove(Self.bundleFile(id))
        local.days[id] = nil
        local.marks[id] = nil
        persistLocal()
        await TripReminders.sync(Array(bundles.values))
        TripArrivals.shared.refresh()
        return nil
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
        // An arrival, a departure or a skip can be what puts someone off
        // the plan (out of order, behind).
        TripOffPlan.shared.check()
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

    /// A whole-trip option (v2): every day it carries becomes the phone's
    /// version, and `option-applied` goes up with `detail.days`.
    func apply(_ option: TripReplanOption, tripId: String) {
        var days = local.days[tripId] ?? [:]
        for day in option.days {
            days[day.date] = LocalDay(day: day, appliedAt: Date(), label: option.label, acceptedVersion: nil)
        }
        local.days[tripId] = days
        persistLocal()
        var detail: [String: TripJSON] = ["optionId": .string(option.id), "label": .string(option.label)]
        if let all = TripJSON.from(option.days) { detail["days"] = all }
        record(.optionApplied, tripId: tripId, stop: nil, detail: detail)
        TripArrivals.shared.refresh()
    }

    /// After a conversation turn changed the plan: the server's version is
    /// now the one to show, so the phone's own versions of days give way.
    func adoptServerPlan(_ tripId: String) async {
        local.days[tripId] = nil
        persistLocal()
        await fetch(tripId)
        TripArrivals.shared.refresh()
        TripLive.shared.refresh()
    }

    // MARK: v5: the family's trips

    /// A new trip from its opening message: made on the server, then read
    /// so it opens at once. Nil and a sentence when it could not be made.
    func create(from text: String) async -> (id: String?, failure: String?) {
        do {
            let made = try await TripsAPI.create(text: text)
            await refresh()
            await fetch(made.id)
            return (made.id, nil)
        } catch {
            return (nil, "Not made: \(error.localizedDescription)")
        }
    }

    /// Suggest an idea for a slot (any family member). The bundle is re-read
    /// so the suggestion shows in its slot.
    func suggest(_ wish: WishDraft, tripId: String, date: String, stage: DayStage, note: String?, fitText: String?) async -> String? {
        do {
            try await TripsAPI.suggest(trip: tripId, date: date, stage: stage, wish: wish, note: note, fitText: fitText)
            await fetch(tripId)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Approve, reject or withdraw a suggestion. An approval changes the
    /// plan on the server, so the server's version is adopted.
    /// Nil when done cleanly; otherwise the sentence to show — a failure, or
    /// the server's warning about an approval that went through.
    func decide(_ suggestion: TripSuggestion, action: String, tripId: String) async -> String? {
        do {
            let decided = try await TripsAPI.decide(trip: tripId, suggestion: suggestion.id, action: action)
            if action == "approve" { await adoptServerPlan(tripId) } else { await fetch(tripId) }
            return decided.warning
        } catch {
            await fetch(tripId)
            return error.localizedDescription
        }
    }

    /// "Add this" (an editor): straight into the plan. A parent adds it as
    /// an approved suggestion — the server's one path for a slot's addition,
    /// by id. v8 retired the other path (a sentence through the chat, "Add X
    /// on Tuesday afternoon", which lost the place and took a minute): a
    /// creator who is not a parent suggests it, and a parent adds it. The
    /// planner's own ideas now come as proposals, taken by id.
    func add(_ idea: TripIdea, tripId: String, date: String, stage: DayStage) async -> String? {
        let access = bundles[tripId]?.can ?? .owner
        do {
            guard access.canApprove else {
                try await TripsAPI.suggest(trip: tripId, date: date, stage: stage, wish: idea.wish, note: idea.why, fitText: idea.fit)
                await fetch(tripId)
                return "Suggested — a parent adds it to the plan."
            }
            let made = try await TripsAPI.suggest(trip: tripId, date: date, stage: stage, wish: idea.wish, note: nil, fitText: idea.fit)
            if let made {
                let decided = try await TripsAPI.decide(trip: tripId, suggestion: made.id, action: "approve")
                if let warning = decided.warning {
                    await adoptServerPlan(tripId)
                    return warning
                }
            }
            await adoptServerPlan(tripId)
            return nil
        } catch {
            return error.localizedDescription
        }
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
    /// only: nothing a real trip keeps on disk is touched. v8: and the trip
    /// being planned, before it starts.
    func adoptDemo(_ bundle: TripBundle, marks: [String: TripStopMark], planning: TripBundle? = nil) {
        bundles[bundle.trip.id] = bundle
        summaries = [bundle.summary]
        local.marks[bundle.trip.id] = marks
        if let planning {
            bundles[planning.trip.id] = planning
            summaries.append(planning.summary)
        }
    }

    // MARK: v8: decisions — propose, research, ask
    //
    // The brief, the questions, the proposals and the pack live on the
    // trip's bundle (kept on disk like the rest), so nothing a card shows is
    // view state: a sheet closed mid-decision, or a relaunch, finds them
    // where they were. Each action changes the phone's copy the moment the
    // server answers (`TripBundle.settle`), then the bundle is read again.

    /// The latest change on a trip and its Undo, until put away.
    func lastChange(_ tripId: String) -> TripChangeRecord? { local.changes?[tripId] }

    func dismissChange(_ tripId: String) {
        local.changes?[tripId] = nil
        persistLocal()
    }

    /// The answer this phone voted for.
    func vote(_ questionId: String) -> String? { local.votes?[questionId] }

    func isBusy(_ id: String) -> Bool { busy.contains(id) }

    private func keep(_ change: TripChangeRecord) {
        var all = local.changes ?? [:]
        all[change.tripId] = change
        local.changes = all
        persistLocal()
    }

    /// Change the phone's copy of a trip's decisions, and keep it.
    private func edit(_ tripId: String, _ change: (inout TripBundle) -> Void) {
        guard var bundle = bundles[tripId] else { return }
        change(&bundle)
        bundles[tripId] = bundle
        TripFiles.write(bundle, Self.bundleFile(tripId))
    }

    /// `GET …/decisions`: the brief, questions and proposals, without the
    /// whole bundle — after a pull, or when a sheet opens.
    func refreshDecisions(_ tripId: String) async {
        guard bundles[tripId].map(TripDecisions.speaksV8) == true || SRDemo.isOn else { return }
        guard let wire = try? await TripsAPI.decisions(trip: tripId) else { return }
        edit(tripId) { b in
            b.brief = wire.brief
            b.questions = wire.questions
            b.answered = wire.answered
            b.proposals = wire.proposals
            b.pack = wire.pack
        }
    }

    /// Ask for one group of alternatives: a swap, a fill, a day's version, a
    /// nudge, trip shapes. Kept with the trip's proposals.
    func requestProposals(_ request: ProposalRequest, tripId: String, busyKey: String) async -> (group: [TripProposal], failure: String?) {
        guard !busy.contains(busyKey) else { return ([], nil) }
        busy.insert(busyKey)
        defer { busy.remove(busyKey) }
        do {
            let group = try await TripsAPI.proposals(request, trip: tripId)
            edit(tripId) { $0.merge(group: group) }
            if group.isEmpty { return ([], "Nothing fitted there — try another nudge, or tell the planner.") }
            return (group, nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    /// "Like this, but closer": new alternatives for the same slot. The group
    /// it was nudged from goes, so the slot shows one set of ideas.
    func nudge(_ nudge: Nudge, on proposal: TripProposal, tripId: String) async -> (group: [TripProposal], failure: String?) {
        let result = await requestProposals(.nudge(nudge, on: proposal), tripId: tripId, busyKey: "nudge:\(proposal.groupId)")
        if let first = result.group.first, first.groupId != proposal.groupId {
            edit(tripId) { b in b.proposals = b.proposals?.filter { $0.groupId != proposal.groupId } }
        }
        return result
    }

    /// What became of a decision.
    enum Outcome {
        case done(TripChangeRecord?)
        /// The plan moved: the re-checked proposal, to show and ask again.
        case stale(TripProposal)
        case failed(String)
    }

    /// Use this: the server replays the proposal's checked ops.
    func accept(_ proposal: TripProposal, tripId: String) async -> Outcome {
        guard !busy.contains(proposal.id) else { return .failed("Already sending that.") }
        busy.insert(proposal.id)
        defer { busy.remove(proposal.id) }
        do {
            switch try await TripsAPI.decide(.accept, proposal: proposal.id, trip: tripId) {
            case .accepted(let result):
                edit(tripId) { $0.settle(accepted: proposal) }
                decided[proposal.id] = "Used"
                let change = TripChangeRecord.of(result, tripId: tripId, title: "Used \(proposal.title)")
                keep(change)
                await adoptServerPlan(tripId)
                return .done(change)
            case .stale(let fresh):
                edit(tripId) { $0.replace(fresh) }
                return .stale(fresh)
            case .closed(let why):
                edit(tripId) { $0.settle(rejected: proposal) }
                await fetch(tripId)
                return .failed(why)
            case .rejected:
                return .done(nil)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Not this, with why — a preference signal, not just a dismissal.
    func reject(_ proposal: TripProposal, reason: RejectReason, tripId: String) async -> String? {
        guard !busy.contains(proposal.id) else { return nil }
        busy.insert(proposal.id)
        defer { busy.remove(proposal.id) }
        do {
            switch try await TripsAPI.decide(.reject(reason, note: nil), proposal: proposal.id, trip: tripId) {
            case .closed(let why):
                edit(tripId) { $0.settle(rejected: proposal) }
                return why
            default:
                edit(tripId) { $0.settle(rejected: proposal) }
                decided[proposal.id] = "Turned down: \(reason.label.lowercased())"
                return nil
            }
        } catch {
            return error.localizedDescription
        }
    }

    /// A member's way with a proposal: suggest its place for that slot, for
    /// a parent to approve. Members never accept.
    func suggest(_ proposal: TripProposal, tripId: String) async -> String? {
        guard let place = proposal.place, let date = proposal.scope.date else {
            return "This one can't be suggested from here — tell the planner instead."
        }
        let stage = proposal.scope.stage.flatMap(DayStage.init(rawValue:)) ?? .afternoon
        let wish = WishDraft(title: proposal.title, placeQuery: place.name, priority: "nice", durationMin: nil,
                             partOfDay: stage == .evening ? "evening" : (stage == .morning ? "morning" : "afternoon"),
                             fixedDate: date, fixedStartMin: nil, note: nil,
                             place: TripPlace(name: place.name, location: place.location, osmId: nil, address: nil))
        return await suggest(wish, tripId: tripId, date: date, stage: stage, note: proposal.why, fitText: proposal.tradeoffs.fitText)
    }

    /// Answer a question (or You decide, skip, or — a member — vote).
    func answer(_ question: TripQuestion, _ action: QuestionAction, tripId: String) async -> Outcome {
        guard !busy.contains(question.id) else { return .failed("Already sending that.") }
        busy.insert(question.id)
        defer { busy.remove(question.id) }
        do {
            let result = try await TripsAPI.answer(action, question: question.id, trip: tripId)
            var settled = result.question ?? question
            if result.question == nil {
                // An answer without the question echoed: settle it here.
                switch action {
                case .vote: break
                case .skip: settled.status = .skipped
                case .decide:
                    settled.status = .answered
                    settled.answerId = question.defaultAnswerId
                case .answer(let id):
                    settled.status = .answered
                    settled.answerId = id
                }
            }
            edit(tripId) { $0.settle(question: settled) }
            if case .vote(let id) = action {
                var votes = local.votes ?? [:]
                votes[question.id] = id
                local.votes = votes
                persistLocal()
                return .done(nil)
            }
            let chosen = question.answers.first { $0.id == (action == .decide ? question.defaultAnswerId : action.answerId) }
            let title: String
            switch action {
            case .skip: title = "Skipped: \(question.prompt)"
            case .decide: title = "You let the planner decide: " + (chosen?.label.lowercased() ?? "its suggestion")
            default: title = "You answered: " + (chosen?.label.lowercased() ?? "done")
            }
            decided[question.id] = title
            let change = TripChangeRecord.of(result, tripId: tripId, title: title)
            // A skip or the answer already assumed may change nothing: no card for that.
            let moved = !(change.diff.changes.isEmpty && change.diff.lines.isEmpty)
            if moved { keep(change) }
            if result.planVersion != nil { await adoptServerPlan(tripId) } else { await fetch(tripId) }
            return .done(moved ? change : nil)
        } catch {
            await fetch(tripId)
            return .failed(error.localizedDescription)
        }
    }

    /// Undo: back to the version before a change. The server appends a new
    /// version (history is never rewritten), which says "Undone: …".
    func undo(_ change: TripChangeRecord) async -> String? {
        let key = "undo:\(change.tripId)"
        guard !busy.contains(key) else { return nil }
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            let result = try await TripsAPI.undo(toVersion: change.undoTo, trip: change.tripId)
            let diff = result.diff ?? PlanDiff(lines: result.changes, changes: [], dates: [], walkDeltaM: nil, dropped: [])
            keep(TripChangeRecord(id: UUID().uuidString.lowercased(), tripId: change.tripId, title: "Undone: \(change.title.prefix(1).lowercased() + change.title.dropFirst())",
                                    diff: diff, lines: result.changes, undoTo: nil, planVersion: result.planVersion, at: Date(), remember: nil))
            await adoptServerPlan(change.tripId)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Restore an earlier version from the plan's history.
    func restore(_ version: Int, tripId: String) async -> String? {
        await undo(TripChangeRecord(id: "restore", tripId: tripId, title: "Back to version \(version)", diff: .empty, lines: [],
                                    undoTo: version, planVersion: nil, at: Date(), remember: nil))
    }

    /// A direct edit to the brief — dates, who, pace — or "Right" on a guess.
    func patchBrief(_ patch: BriefPatch, tripId: String) async -> String? {
        let key = "brief:\(tripId)"
        guard !busy.contains(key) else { return nil }
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            let reply = try await TripsAPI.patchBrief(patch, trip: tripId)
            edit(tripId) { $0.brief = reply.brief }
            if reply.planVersion != nil { await adoptServerPlan(tripId) } else { await fetch(tripId) }
            return nil
        } catch {
            return error.localizedDescription
        }
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
                    .flatMap { item -> [String] in
                        if let day = item.event.detail?["day"]?.decode(PlannedDay.self) { return [day.date] }
                        return item.event.detail?["days"]?.decode([PlannedDay].self)?.map(\.date) ?? []
                    }
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

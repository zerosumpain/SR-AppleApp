import Foundation
import Combine

/// The planner's long calls, kept going whatever the app does meanwhile.
///
/// "Make a suggestion", a conversation turn and a new trip each start a job
/// on the server (`TripsAPI.start`) and collect it by polling. The job's id
/// is written down here the moment it exists, so a phone that goes to the
/// background — or is closed — mid-job picks the result up when it comes
/// back (`resume`, on launch and on every foreground), for up to 30 minutes,
/// which is as long as the server keeps a finished job.
///
/// Screens read the state by key (`ideasKey`, `converseKey`, `createKey`);
/// a sheet closed while the planner thinks finds the answer waiting when it
/// is opened again.
@MainActor
final class TripJobs: ObservableObject {
    static let shared = TripJobs()

    enum Kind: String, Codable { case ideas, converse, create }

    /// A job started and not yet collected — what survives a relaunch.
    struct Record: Codable, Equatable {
        var key: String
        var kind: Kind
        var tripId: String?
        var jobId: String
        var startedAt: Date
        /// What was asked: the conversation's words, so the screen can show
        /// them while the planner thinks.
        var asked: String?
    }

    enum State: Equatable {
        case running(since: Date, asked: String?)
        case failed(String)
    }

    @Published private(set) var states: [String: State] = [:]
    @Published private(set) var ideas: [String: TripIdeasReply] = [:]
    @Published private(set) var conversed: [String: ConverseResult] = [:]
    /// A new trip's id, once made.
    @Published private(set) var created: [String: String] = [:]

    /// The server keeps a finished job this long.
    static let keepFor: TimeInterval = 30 * 60
    private static let file = "jobs.json"
    private var records: [Record]
    private var tasks: [String: Task<Void, Never>] = [:]

    private init() {
        records = (TripFiles.read([Record].self, Self.file) ?? []).filter { Date().timeIntervalSince($0.startedAt) < Self.keepFor }
    }

    // MARK: Keys

    static func ideasKey(_ tripId: String, _ date: String, _ stage: DayStage) -> String { "ideas|\(tripId)|\(date)|\(stage.rawValue)" }
    static func converseKey(_ tripId: String) -> String { "converse|\(tripId)" }
    static let createKey = "create"

    func isRunning(_ key: String) -> Bool {
        if case .running = states[key] { return true }
        return false
    }

    // MARK: Starting

    /// "Make a suggestion" for a slot.
    func askIdeas(tripId: String, date: String, stage: DayStage, after: String?, before: String?) {
        let key = Self.ideasKey(tripId, date, stage)
        ideas[key] = nil
        launch(key, kind: .ideas, tripId: tripId, asked: nil) {
            try await TripsAPI.start(TripsAPI.path(tripId) + "/ideas",
                                     body: try TripsAPI.ideasBody(date: date, stage: stage, after: after, before: before))
        }
    }

    /// One turn of the conversation (Edit plan / Ask).
    func converse(_ text: String, tripId: String) {
        let key = Self.converseKey(tripId)
        conversed[key] = nil
        launch(key, kind: .converse, tripId: tripId, asked: text) {
            try await TripsAPI.start(TripsAPI.path(tripId) + "/converse", body: try JSONEncoder().encode(ConverseBody(text: text)))
        }
    }

    /// A new trip from its opening message.
    func create(_ text: String) {
        created[Self.createKey] = nil
        launch(Self.createKey, kind: .create, tripId: nil, asked: text) {
            try await TripsAPI.start("api/native/trips", body: try JSONEncoder().encode(ConverseBody(text: text)))
        }
    }

    func cancel(_ key: String) {
        tasks[key]?.cancel()
        tasks[key] = nil
        states[key] = nil
        forget(key)
    }

    /// Put an answer away ("Put the ideas away", a sheet that has shown it).
    func clear(_ key: String) {
        ideas[key] = nil
        conversed[key] = nil
        created[key] = nil
        if case .failed = states[key] { states[key] = nil }
    }

    // MARK: Resuming

    /// Pick up every job still worth collecting: at launch, and whenever the
    /// app comes back to the front.
    func resume() {
        guard !SRDemo.isOn else { return }
        records = records.filter { Date().timeIntervalSince($0.startedAt) < Self.keepFor }
        persist()
        for record in records where tasks[record.key] == nil {
            states[record.key] = .running(since: record.startedAt, asked: record.asked)
            tasks[record.key] = Task { await self.collect(record, started: .job(record.jobId)) }
        }
    }

    // MARK: The work

    private func launch(_ key: String, kind: Kind, tripId: String?, asked: String?, start: @escaping () async throws -> TripsAPI.Started) {
        tasks[key]?.cancel()
        let since = Date()
        states[key] = .running(since: since, asked: asked)
        tasks[key] = Task {
            do {
                let started = try await start()
                if case .job(let id) = started {
                    self.remember(Record(key: key, kind: kind, tripId: tripId, jobId: id, startedAt: since, asked: asked))
                }
                await self.collect(Record(key: key, kind: kind, tripId: tripId, jobId: "", startedAt: since, asked: asked), started: started)
            } catch is CancellationError {
                return
            } catch {
                self.fail(key, error)
            }
        }
    }

    private func collect(_ record: Record, started: TripsAPI.Started) async {
        let key = record.key
        do {
            switch record.kind {
            case .ideas:
                let reply = try await TripsAPI.result(started, as: TripIdeasReply.self, since: record.startedAt,
                                                      unreadable: "The planner's ideas were unreadable.")
                ideas[key] = reply
            case .converse:
                let result = try await TripsAPI.result(started, as: ConverseResult.self, since: record.startedAt,
                                                       unreadable: "The planner's answer was unreadable.")
                conversed[key] = result
                // The planner may have changed the plan; its turn is stored
                // either way, so the trip is read again.
                if let tripId = record.tripId {
                    if result.planVersion != nil || !result.applied.isEmpty {
                        await TripStore.shared.adoptServerPlan(tripId)
                    } else {
                        await TripStore.shared.fetch(tripId)
                    }
                }
            case .create:
                let made = try await TripsAPI.result(started, as: TripCreated.self, since: record.startedAt,
                                                     unreadable: "The new trip's answer was unreadable.")
                await TripStore.shared.refresh()
                await TripStore.shared.fetch(made.id)
                created[key] = made.id
            }
            states[key] = nil
            SRHaptic.ok()
        } catch is CancellationError {
            return
        } catch {
            fail(key, error)
        }
        tasks[key] = nil
        forget(key)
    }

    private func fail(_ key: String, _ error: Error) {
        states[key] = .failed(error.localizedDescription)
        tasks[key] = nil
        forget(key)
        SRHaptic.bad()
    }

    private func remember(_ record: Record) {
        records.removeAll { $0.key == record.key }
        records.append(record)
        persist()
    }

    private func forget(_ key: String) {
        records.removeAll { $0.key == key }
        persist()
    }

    private func persist() {
        TripFiles.write(records, Self.file)
    }
}

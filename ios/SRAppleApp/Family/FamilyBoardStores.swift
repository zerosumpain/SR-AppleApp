import Foundation
import HealthKit
import WidgetKit

/// The family step board, from the site (`GET /api/native/family/steps`).
///
/// Shared — Today's card, the Steps page and the widget bridge all read one
/// board, so the page opens on the numbers the card showed. The site refreshes
/// the board every fifteen minutes; this phone's own Apple Health count is
/// laid over the caller's row when it is higher (`FamilySteps.withLive`).
@MainActor
final class FamilyStepsStore: ObservableObject {
    static let shared = FamilyStepsStore()

    /// As the site sent it.
    @Published private(set) var board: FamilyStepsBoard?
    /// This iPhone's steps today, from Apple Health; nil when unreadable.
    @Published private(set) var live: Int?
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    @Published var message: String?

    /// What every screen draws: the board, with this phone's count in.
    var shown: FamilyStepsBoard? {
        guard let board else { return nil }
        // Only on today's board, and only for this phone's own person —
        // "View as" shows somebody else's seat, and this phone's count is not
        // theirs.
        guard AccessStore.shared.viewingAs == nil, FamilySteps.isToday(board) else { return board }
        return FamilySteps.withLive(board, liveSteps: live)
    }

    func load() async {
        guard SiteClient.shared.isPaired, !loading else { return }
        loading = true
        defer { loading = false; loaded = true }
        do {
            let fetched: FamilyStepsBoard = try await SiteClient.shared.send("api/native/family/steps")
            board = fetched
            message = nil
            FamilyWidgetBridge.save(steps: fetched)
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            // Authentication failures discard the sensitive cached board.
            if let failure = error as? SiteError, failure.status == 401 || failure.status == 403 {
                board = nil; FamilyWidgetBridge.clear()
            }
            message = board == nil ? Self.sentence(for: error) : nil
        }
        if AccessStore.shared.viewingAs == nil { live = await LiveSteps.today() }
    }

    /// "View as" changed: the board was somebody else's.
    func reset() {
        board = nil
        live = nil
        loaded = false
        message = nil
    }

    static func sentence(for error: Error) -> String {
        if case .status(let code, _)? = error as? SiteError {
            if code == 403 { return "The step board is for the family." }
            if code == 404 { return "The step board isn't on the site yet." }
        }
        return error.localizedDescription
    }
}

/// This iPhone's steps since midnight, from Apple Health.
///
/// A cumulative-sum statistic, so a phone and a Watch counting the same walk
/// are counted once. Never asks for permission: the app asks for Activity in
/// Settings → Apple Health, and a denied read looks like no data, which is
/// nil here and simply no "live" figure.
enum LiveSteps {
    private static let store = HKHealthStore()

    static func today(now: Date = Date()) async -> Int? {
        // The demo's own figure, above the board's, so the screenshot shows
        // the "live" row — and a reviewer's own steps stay out of a made-up board.
        if SRDemo.isOn { return 9_120 }
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: .count())
                continuation.resume(returning: value.map { Int($0.rounded()) })
            }
            store.execute(query)
        }
    }
}

/// The family task list, from the site (`/api/native/family/tasks`).
@MainActor
final class FamilyTasksStore: ObservableObject {
    static let shared = FamilyTasksStore()

    @Published private(set) var board: FamilyTasksBoard?
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    /// The task id an action is waiting on, or "new".
    @Published private(set) var busyTasks: Set<String> = []
    var busy: String? { busyTasks.first }
    struct PendingAction: Codable { let task: FamilyTask; let body: FamilyTaskActionBody }
    @Published private(set) var pendingActions: [String: PendingAction] = [:]
    private var journalScope: String?
    private var draining = false
    private var revision = 0
    @Published var message: String?

    var summary: FamilyTasksSummary? { board.map { FamilyTasksSummary.make($0) } }

    func load() async {
        guard SiteClient.shared.isPaired, !loading else { return }
        if let scope = SiteClient.shared.storageScope, journalScope != scope {
            let saved = await LocalJournal.shared.read([String: PendingAction].self, scope: scope, key: "family-task-actions") ?? [:]
            guard scope == SiteClient.shared.storageScope else { return }
            pendingActions = saved; journalScope = scope
        }
        loading = true
        let startedRevision = revision
        defer { loading = false; loaded = true }
        do {
            let fetched: FamilyTasksBoard = try await SiteClient.shared.send("api/native/family/tasks")
            guard startedRevision == revision else { return }
            board = fetched
            for pending in pendingActions.values { optimistic(pending) }
            message = pendingActions.isEmpty ? nil : "\(pendingActions.count) changes saved, waiting to sync."
            await drainPending()
            FamilyWidgetBridge.save(tasks: fetched)
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            if let failure = error as? SiteError, failure.status == 401 || failure.status == 403 {
                board = nil; FamilyWidgetBridge.clear()
            }
            message = board == nil ? Self.sentence(for: error) : nil
        }
    }

    /// Add a task. Nil when it went; otherwise the sentence for the sheet.
    func create(_ body: FamilyTaskCreateBody) async -> String? {
        guard !busyTasks.contains("new") else { return "Saving already…" }
        busyTasks.insert("new")
        defer { busyTasks.remove("new") }
        do {
            try await SiteClient.shared.post("api/native/family/tasks", body: try JSONEncoder().encode(body))
            SRHaptic.ok()
            await load()
            return nil
        } catch {
            return Self.sentence(for: error)
        }
    }

    /// Done, undo, confirm, send back, paid, delete. False when refused; the
    /// reason is in `message`.
    @discardableResult
    func act(_ action: FamilyTaskAction, on task: FamilyTask, note: String? = nil) async -> Bool {
        guard !busyTasks.contains(task.id), pendingActions[task.id] == nil else { return false }
        if (action == .done || action == .undo), task.updatedAt != nil,
           let scope = SiteClient.shared.storageScope, AccessStore.shared.viewingAs == nil {
            let pending = PendingAction(task: task, body: FamilyTaskActionBody(action: action.rawValue, note: note, expectedUpdatedAt: task.updatedAt))
            pendingActions[task.id] = pending
            revision += 1
            optimistic(pending)
            do { try await LocalJournal.shared.save(pendingActions, scope: scope, key: "family-task-actions") }
            catch {
                pendingActions.removeValue(forKey: task.id); replace(task)
                message = "Could not save this change. Try again."
                return false
            }
            guard scope == SiteClient.shared.storageScope else { return false }
            return await sendPending(pending)
        }
        // Payments, approvals, deletion and creation require a server answer.
        busyTasks.insert(task.id); defer { busyTasks.remove(task.id) }
        do {
            let body = FamilyTaskActionBody(action: action.rawValue, note: note, expectedUpdatedAt: task.updatedAt)
            try await SiteClient.shared.call("api/native/family/tasks/\(task.id)", method: "PATCH", body: try JSONEncoder().encode(body))
            revision += 1
            await load()
            SRHaptic.ok()
            return true
        } catch { message = Self.sentence(for: error); return false }
    }

    private struct TaskReply: Decodable { let task: FamilyTask }
    private func replace(_ task: FamilyTask) {
        if let index = board?.open.firstIndex(where: { $0.id == task.id }) { board?.open[index] = task }
        if let index = board?.completed.firstIndex(where: { $0.id == task.id }) { board?.completed[index] = task }
    }
    private func optimistic(_ pending: PendingAction) {
        var task = pending.task
        if pending.body.action == "done" {
            task.status = "done"; task.doneBy = board?.me.id; task.doneAt = timestamp(Date()); task.sentBackNote = nil
        } else { task.status = "open"; task.doneBy = nil; task.doneAt = nil }
        replace(task)
    }
    @discardableResult private func sendPending(_ pending: PendingAction) async -> Bool {
        guard let scope = SiteClient.shared.storageScope, !busyTasks.contains(pending.task.id) else { return false }
        busyTasks.insert(pending.task.id); defer { busyTasks.remove(pending.task.id) }
        do {
            let response: TaskReply = try await SiteClient.shared.send("api/native/family/tasks/\(pending.task.id)", method: "PATCH", body: JSONEncoder().encode(pending.body))
            guard scope == SiteClient.shared.storageScope else { return false }
            replace(response.task)
            pendingActions.removeValue(forKey: pending.task.id)
            revision += 1
            do { try await LocalJournal.shared.save(pendingActions, scope: scope, key: "family-task-actions") }
            catch {
                message = "Saved on the site. Local recovery cleanup will retry when you reopen Tasks."
                return true
            }
            message = pendingActions.isEmpty ? nil : "Some changes are waiting to sync."
            SRHaptic.ok()
            return true
        } catch {
            guard scope == SiteClient.shared.storageScope else { return false }
            if error is URLError {
                message = "Saved on this iPhone. It will sync when you reopen Tasks or pull to refresh."
                return true
            }
            pendingActions.removeValue(forKey: pending.task.id)
            replace(pending.task)
            try? await LocalJournal.shared.save(pendingActions, scope: scope, key: "family-task-actions")
            if let failure = error as? SiteError, failure.status == 409 {
                // This can run inside load's queue drain; do not call load
                // recursively and leave the reverted, stale task on screen.
                if let current: FamilyTasksBoard = try? await SiteClient.shared.send("api/native/family/tasks"), scope == SiteClient.shared.storageScope {
                    board = current
                    for other in pendingActions.values { optimistic(other) }
                }
            } else if !loading { await load() }
            message = Self.sentence(for: error)
            return false
        }
    }
    func drainPending() async {
        guard !draining else { return }
        draining = true; defer { draining = false }
        for pending in Array(pendingActions.values) {
            guard SiteClient.shared.isPaired, !Task.isCancelled else { return }
            _ = await sendPending(pending)
        }
    }

    func reset() {
        pendingActions = [:]; journalScope = nil; busyTasks = []; revision += 1
        board = nil
        loaded = false
        message = nil
    }

    static func sentence(for error: Error) -> String {
        switch error as? SiteError {
        case .status(let code, let text)?:
            switch code {
            case 403 where AccessStore.shared.viewingAs != nil: return "View as is look-only."
            case 403: return text.isEmpty ? "That's for a parent to do." : text
            case 404: return "That task has gone."
            case 409: return "Someone got there first — the list is up to date now."
            default: return text
            }
        case .invalid(let text, _)?:
            return text
        default:
            return error.localizedDescription
        }
    }
}

/// The app's half of the family widgets: it keeps the shared Keychain shelf
/// (`FamilyShelf`) filled and tells WidgetKit when something changed.
///
/// Never in demo mode (the simulator's Keychain is not a phone's), and never
/// while viewing the app as somebody — the widgets are this phone's person.
@MainActor
enum FamilyWidgetBridge {
    private static var active: Bool {
        if SRDemo.isOn { return false }
        return AccessStore.shared.viewingAs == nil
    }

    static func save(steps board: FamilyStepsBoard) {
        guard active else { return }
        // Compared without the timestamp, so an unchanged board does not
        // cost a reload.
        if FamilyShelf.load(FamilyStepsSnapshot.self, .steps)?.board == board { return }
        if FamilyShelf.save(FamilyStepsSnapshot(board: board, savedAt: Date()), .steps) {
            WidgetCenter.shared.reloadTimelines(ofKind: FamilyWidgetKind.steps)
        }
    }

    static func save(tasks board: FamilyTasksBoard) {
        guard active else { return }
        let summary = FamilyTasksSummary.make(board)
        if FamilyShelf.load(FamilyTasksSnapshot.self, .tasks)?.summary == summary { return }
        if FamilyShelf.save(FamilyTasksSnapshot(summary: summary, savedAt: Date()), .tasks) {
            WidgetCenter.shared.reloadTimelines(ofKind: FamilyWidgetKind.tasks)
        }
    }

    /// Hand the widgets the site credential while this person may see the
    /// boards; take it and the snapshots away the moment they may not.
    static func sync(allowed: Bool) {
        guard active else { return }
        if allowed, let token = SiteClient.shared.token {
            let credential = FamilyWidgetCredential(origin: SiteClient.shared.origin.absoluteString, token: token)
            if FamilyShelf.save(credential, .credential) {
                WidgetCenter.shared.reloadTimelines(ofKind: FamilyWidgetKind.steps)
                WidgetCenter.shared.reloadTimelines(ofKind: FamilyWidgetKind.tasks)
            }
        } else {
            clear()
        }
    }

    /// Signed out, or no longer family: nothing left behind for a widget.
    static func clear() {
        if SRDemo.isOn { return }
        guard FamilyShelf.read(.credential) != nil || FamilyShelf.read(.steps) != nil || FamilyShelf.read(.tasks) != nil else { return }
        FamilyShelf.clearAll()
        WidgetCenter.shared.reloadTimelines(ofKind: FamilyWidgetKind.steps)
        WidgetCenter.shared.reloadTimelines(ofKind: FamilyWidgetKind.tasks)
    }
}

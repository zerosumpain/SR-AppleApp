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
            // A board on screen stays; the next read catches up.
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
    @Published private(set) var busy: String?
    @Published var message: String?

    var summary: FamilyTasksSummary? { board.map { FamilyTasksSummary.make($0) } }

    func load() async {
        guard SiteClient.shared.isPaired, !loading else { return }
        loading = true
        defer { loading = false; loaded = true }
        do {
            let fetched: FamilyTasksBoard = try await SiteClient.shared.send("api/native/family/tasks")
            board = fetched
            message = nil
            FamilyWidgetBridge.save(tasks: fetched)
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            message = board == nil ? Self.sentence(for: error) : nil
        }
    }

    /// Add a task. Nil when it went; otherwise the sentence for the sheet.
    func create(_ body: FamilyTaskCreateBody) async -> String? {
        guard busy == nil else { return "Saving already…" }
        busy = "new"
        defer { busy = nil }
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
        guard busy == nil else { return false }
        busy = task.id
        defer { busy = nil }
        do {
            let body = FamilyTaskActionBody(action: action.rawValue, note: note)
            try await SiteClient.shared.call("api/native/family/tasks/\(task.id)", method: "PATCH", body: try JSONEncoder().encode(body))
            if action == .delete { SRHaptic.tap() } else { SRHaptic.ok() }
            message = nil
            await load()
            return true
        } catch {
            SRHaptic.bad()
            message = Self.sentence(for: error)
            await load()
            return false
        }
    }

    func reset() {
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

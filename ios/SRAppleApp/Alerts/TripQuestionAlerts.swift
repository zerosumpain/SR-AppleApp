import Foundation
import UserNotifications
import Combine

/// The UserNotifications half of `TripQuestionPushes`: registering a question's
/// buttons, and sending what one of them answered.
extension TripQuestionPushes {
    /// A question's category as iOS takes it. Every button runs in the
    /// BACKGROUND (`options: []`), as every other alert's does, so it works the
    /// same from a lock-screen banner as from a wrist. Opening the trip stays
    /// the default tap.
    static func notificationCategory(_ category: Category) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: category.identifier,
            actions: category.buttons.map { UNNotificationAction(identifier: $0.id, title: $0.title, options: []) },
            intentIdentifiers: [],
            options: []
        )
    }

    /// Everything to register, as one set: `setNotificationCategories`
    /// REPLACES the whole set, so the app's own categories (`base`) and
    /// anything else already there are kept, and the trip questions' are
    /// swapped for these — an answered question's buttons go with it.
    static func merged(
        existing: Set<UNNotificationCategory>, base: Set<UNNotificationCategory>, questions: [Category]
    ) -> Set<UNNotificationCategory> {
        var byId: [String: UNNotificationCategory] = [:]
        for category in existing where questionId(categoryIdentifier: category.identifier) == nil {
            byId[category.identifier] = category
        }
        for category in base { byId[category.identifier] = category }
        for category in questions { byId[category.identifier] = notificationCategory(category) }
        return Set(byId.values)
    }
}

/// Keeps the open questions' buttons registered: whenever the trips on this
/// phone change — read from disk at launch, a foreground refresh, the
/// background refresh — their categories are registered again.
///
/// Watches `TripStore.bundles` rather than being called from the store, so
/// the store needs no hook; an unchanged set of questions registers nothing.
@MainActor
final class TripQuestionAlerts {
    static let shared = TripQuestionAlerts()

    private var watching: AnyCancellable?
    private var registered: [TripQuestionPushes.Category]?

    private init() {}

    /// From `didFinishLaunching`, after the app's own categories. The store's
    /// cached trips arrive at once, so a question loaded before the app was
    /// closed has its buttons again from launch.
    func start() {
        guard watching == nil else { return }
        watching = TripStore.shared.$bundles
            .map { TripQuestionPushes.categories(Array($0.values)) }
            .removeDuplicates()
            .sink { [weak self] categories in
                Task { await self?.register(categories) }
            }
    }

    func register(_ categories: [TripQuestionPushes.Category]) async {
        guard categories != registered else { return }
        registered = categories
        let center = UNUserNotificationCenter.current()
        let existing = await center.notificationCategories()
        center.setNotificationCategories(
            TripQuestionPushes.merged(existing: existing, base: AlertActions.categories, questions: categories)
        )
    }

    /// Said on a local notification when the answer did not land.
    enum Delivery: Equatable {
        case sent
        /// 404 or 409: answered elsewhere, or no longer asked. Nothing to say.
        case gone
        case failed(String)
    }

    /// Answer from a button, then re-read the trip, so the plan on the phone
    /// is the answered one and the question's buttons go. Often on the Watch,
    /// with the app in the background.
    static func send(_ answer: TripQuestionPushes.Answer) async -> Delivery {
        let bundle = TripStore.shared.bundles[answer.tripId]
        let question = (bundle?.questions ?? []).first { $0.id == answer.questionId }
        let body = TripQuestionPushes.body(answer.choice, question: question, access: bundle?.access)
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            // The answer is the solver alone (under 3 s, wire contract); a
            // button's background time is about thirty.
            let _: EmptyReply = try await SiteClient.shared.send(answer.path, method: "POST", body: data, asSelf: true, timeout: 20)
        } catch let error as SiteError where error.status == 404 || error.status == 409 {
            await TripStore.shared.fetch(answer.tripId)
            return .gone
        } catch {
            return .failed(error.localizedDescription)
        }
        await TripStore.shared.fetch(answer.tripId)
        return .sent
    }

    /// Only when it did NOT land: a notification for every success would be
    /// noise over the silence that success is (as `AppDelegate.answer`).
    /// Tapping it opens the question, to answer there.
    static func answer(_ answer: TripQuestionPushes.Answer) async {
        guard case .failed(let reason) = await send(answer) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your answer was not sent"
        content.body = "Open the trip to answer it. (\(reason))"
        content.sound = .default
        content.threadIdentifier = TripLink.category
        var info: [String: String] = ["category": TripLink.category, "tripId": answer.tripId, "questionId": answer.questionId]
        if let url = TripLink.questionURL(tripId: answer.tripId, questionId: answer.questionId) { info["url"] = url.absoluteString }
        content.userInfo = info
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "trip-answer-failed-\(answer.questionId)", content: content, trigger: nil)
        )
    }
}

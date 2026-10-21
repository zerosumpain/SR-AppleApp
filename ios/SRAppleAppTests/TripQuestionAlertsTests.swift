import XCTest
import UserNotifications
@testable import SRAppleApp

/// A trip question's notification buttons, as iOS gets them, and how a press
/// or a tap is routed — the UserNotifications half of `TripReachTests`.
///
/// A simulator cannot press a notification button, so, as in
/// `AlertActionsTests`, what is checked is the pure half: the categories
/// registered and what each response means.
final class TripQuestionAlertsTests: XCTestCase {

    private func category(_ id: String, _ buttons: [(String, String)]) -> TripQuestionPushes.Category {
        TripQuestionPushes.Category(identifier: "trip-q-\(id)", buttons: buttons.map { TripQuestionPushes.Button(id: $0.0, title: $0.1) })
    }

    func testTheSpelledOutActionIdentifiersAreTheSystems() {
        XCTAssertEqual(TripQuestionPushes.tapAction, UNNotificationDefaultActionIdentifier)
        XCTAssertEqual(TripQuestionPushes.dismissAction, UNNotificationDismissActionIdentifier)
    }

    func testEveryAnswerButtonStaysInTheBackground() {
        let registered = TripQuestionPushes.notificationCategory(category("q1", [("a0", "Back to the flat"), ("a1", "Carry on"), ("decide", "You decide")]))
        XCTAssertEqual(registered.identifier, "trip-q-q1")
        XCTAssertEqual(registered.actions.map(\.identifier), ["a0", "a1", "decide"])
        XCTAssertEqual(registered.actions.map(\.title), ["Back to the flat", "Carry on", "You decide"])
        // A foreground action from a wrist can only be passed on, not done.
        for action in registered.actions { XCTAssertTrue(action.options.isEmpty, action.identifier) }
    }

    func testRegisteringKeepsEveryOtherCategoryAndSwapsTheQuestions() {
        let stale = TripQuestionPushes.notificationCategory(category("old", [("a0", "Old"), ("decide", "You decide")]))
        let other = UNNotificationCategory(identifier: "someone-elses", actions: [], intentIdentifiers: [], options: [])
        let merged = TripQuestionPushes.merged(
            existing: [stale, other], base: AlertActions.categories,
            questions: [category("q1", [("a0", "Yes"), ("decide", "You decide")])]
        )
        let ids = Set(merged.map(\.identifier))
        XCTAssertTrue(ids.isSuperset(of: Set(AlertActions.categories.map(\.identifier))))
        XCTAssertTrue(ids.contains("someone-elses"))
        XCTAssertTrue(ids.contains("trip-q-q1"))
        XCTAssertFalse(ids.contains("trip-q-old"), "an answered question's buttons go")
        XCTAssertEqual(merged.count, ids.count, "one category per identifier")
    }

    // MARK: - Routing, through the one function the delegate asks

    func testAnAnswerButtonAnswersInTheBackground() {
        let outcome = AlertActions.outcome(
            action: "a0", categoryIdentifier: "trip-q-q1",
            userInfo: ["category": "trip-question", "tripId": "rome", "questionId": "q1"]
        )
        XCTAssertEqual(outcome, .tripAnswer(.init(tripId: "rome", questionId: "q1", choice: .answer("a0"))))
    }

    func testTappingAQuestionOpensTheTripAtIt() {
        let outcome = AlertActions.outcome(
            action: UNNotificationDefaultActionIdentifier, categoryIdentifier: "trip-question",
            userInfo: ["category": "trip-question", "url": "sr://trips/rome/questions/q1"]
        )
        XCTAssertEqual(outcome, .openTrip(TripLink(tripId: "rome", date: nil, questionId: "q1")))
    }

    /// The red team's finding (15 Oct): "A booking is at risk" fell through to
    /// Today and the alerts inbox. It opens its day, and stays that way.
    func testATripAlertOpensItsDayNotTheInbox() {
        let outcome = AlertActions.outcome(
            action: UNNotificationDefaultActionIdentifier, categoryIdentifier: "",
            userInfo: ["category": TripLink.category, "tripId": "rome", "date": "2026-10-27"]
        )
        XCTAssertEqual(outcome, .openTrip(TripLink(tripId: "rome", date: "2026-10-27")))
        XCTAssertEqual(
            AlertActions.outcome(action: UNNotificationDefaultActionIdentifier, categoryIdentifier: TripLink.category, userInfo: [:]),
            .openTrip(TripLink(tripId: nil, date: nil))
        )
    }

    func testTheFailedAnswerNoticeOpensTheQuestion() {
        let outcome = AlertActions.outcome(
            action: UNNotificationDefaultActionIdentifier, categoryIdentifier: "",
            userInfo: ["category": TripLink.category, "tripId": "rome", "questionId": "q1"]
        )
        XCTAssertEqual(outcome, .openTrip(TripLink(tripId: "rome", date: nil, questionId: "q1")))
    }

    func testOtherAlertsRouteAsBefore() {
        XCTAssertEqual(
            AlertActions.outcome(action: UNNotificationDefaultActionIdentifier, categoryIdentifier: AlertActions.alertCategory, userInfo: ["category": "health"]),
            .open(category: "health")
        )
        XCTAssertEqual(AlertActions.outcome(action: AlertActions.read, categoryIdentifier: AlertActions.alertCategory, userInfo: ["id": "a1"]), .read(id: "a1"))
    }
}

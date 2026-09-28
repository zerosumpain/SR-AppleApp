import XCTest
import UserNotifications
import Combine
@testable import SRAppleApp

/// The buttons on a raised alert, which are what the Watch shows.
///
/// A simulator cannot press a notification button, so what is checked here is
/// the pure half: which category an alert wears, what each response means, and
/// that no button would try to open the app from a wrist.
final class AlertActionsTests: XCTestCase {

    private func alert(_ category: String) -> SiteAlert {
        SiteAlert(id: "a1", category: category, title: "Title", body: "", url: nil,
                  severity: "info", createdAt: "2026-09-26T08:00:00Z", read: false)
    }

    // MARK: - Categories

    func testEverySiteCategoryWearsTheOneWithButtons() {
        for category in ["health", "build", "news", "something-new-tomorrow"] {
            XCTAssertEqual(AlertActions.categoryIdentifier(for: alert(category)), AlertActions.alertCategory)
        }
    }

    func testALapsedConnectionWearsItsOwnAndHasNoButtons() throws {
        XCTAssertEqual(AlertActions.categoryIdentifier(for: alert("connections")), AlertActions.connectionsCategory)
        let registered = try XCTUnwrap(
            AlertActions.categories.first { $0.identifier == AlertActions.connectionsCategory }
        )
        XCTAssertTrue(registered.actions.isEmpty)
    }

    func testNoButtonOpensTheApp() {
        // A foreground action from a wrist can only be passed on, not done.
        let actions = AlertActions.categories.flatMap(\.actions)
        XCTAssertEqual(
            Set(actions.map(\.identifier)),
            [AlertActions.read, AlertActions.clear, AlertActions.approve, AlertActions.reject, AlertActions.reply]
        )
        for action in actions {
            XCTAssertFalse(action.options.contains(.foreground), action.identifier)
        }
    }

    // MARK: - Responses

    func testATapOpensTheSiteCategoryFromUserInfo() {
        let outcome = AlertActions.outcome(
            action: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: AlertActions.alertCategory,
            userInfo: ["id": "a1", "category": "health"]
        )
        XCTAssertEqual(outcome, .open(category: "health"))
    }

    func testATapOnANotificationRaisedBeforeTheseCategoriesStillRoutes() {
        // Those carried the site's category as their identifier and no copy in
        // userInfo was relied on.
        let outcome = AlertActions.outcome(
            action: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: "connections",
            userInfo: [:]
        )
        XCTAssertEqual(outcome, .open(category: "connections"))
    }

    func testClearNamesTheAlert() {
        let outcome = AlertActions.outcome(
            action: AlertActions.clear,
            categoryIdentifier: AlertActions.alertCategory,
            userInfo: ["id": "a1", "category": "build"]
        )
        XCTAssertEqual(outcome, .clear(id: "a1"))
    }

    func testClearWithoutAnIdDoesNothingRatherThanOpeningTheApp() {
        let outcome = AlertActions.outcome(
            action: AlertActions.clear,
            categoryIdentifier: AlertActions.alertCategory,
            userInfo: ["category": "build"]
        )
        XCTAssertEqual(outcome, .ignore)
    }

    func testMarkReadNamesTheAlert() {
        let outcome = AlertActions.outcome(
            action: AlertActions.read,
            categoryIdentifier: AlertActions.alertCategory,
            userInfo: ["id": "a1", "category": "build"]
        )
        XCTAssertEqual(outcome, .read(id: "a1"))
    }

    func testMarkReadWithoutAnIdDoesNothing() {
        let outcome = AlertActions.outcome(
            action: AlertActions.read,
            categoryIdentifier: AlertActions.alertCategory,
            userInfo: [:]
        )
        XCTAssertEqual(outcome, .ignore)
    }

    func testATapOnTheHealthConnectionCheckOpensConnections() {
        // `PersonalHealth.notifyOnce` sets no identifier at all; the category
        // is only in userInfo, and used to be missed, landing on Today.
        let outcome = AlertActions.outcome(
            action: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: "",
            userInfo: ["category": "connections", "id": "x"]
        )
        XCTAssertEqual(outcome, .open(category: "connections"))
    }

    // MARK: - Answering a stalled chat turn

    private let confirmInfo: [AnyHashable: Any] = [
        "id": "a1", "category": "chat", "gate": "confirm", "jobId": "job-1", "confirmId": "c-1",
    ]

    func testApproveAnswersTheConfirmationThePushNamed() {
        let outcome = AlertActions.outcome(action: AlertActions.approve, categoryIdentifier: AlertActions.confirmCategory, userInfo: confirmInfo)
        XCTAssertEqual(outcome, .answer(GateAnswer(jobId: "job-1", kind: .confirm(id: "c-1", approved: true))))
        guard case .answer(let answer) = outcome else { return XCTFail() }
        XCTAssertEqual(answer.path, "api/workflows/orchestrator/chat?jobId=job-1")
        XCTAssertEqual(answer.body["type"] as? String, "confirm_ack")
        XCTAssertEqual(answer.body["decision"] as? String, "approved")
    }

    func testRejectingAPlanSendsAPlanAck() {
        let info: [AnyHashable: Any] = ["gate": "plan", "jobId": "job-2", "planId": "p-1", "category": "chat"]
        let outcome = AlertActions.outcome(action: AlertActions.reject, categoryIdentifier: AlertActions.planCategory, userInfo: info)
        guard case .answer(let answer) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(answer.body["type"] as? String, "plan_ack")
        XCTAssertEqual(answer.body["planId"] as? String, "p-1")
        XCTAssertEqual(answer.body["decision"] as? String, "rejected")
    }

    func testAReplyAnswersTheOneQuestion() {
        let info: [AnyHashable: Any] = ["gate": "clarify", "jobId": "job-3", "clarifyId": "q-set", "questionId": "q1"]
        let outcome = AlertActions.outcome(action: AlertActions.reply, categoryIdentifier: AlertActions.clarifyCategory, userInfo: info, text: "  Tuesday  ")
        guard case .answer(let answer) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(answer.body["type"] as? String, "clarify_ack")
        XCTAssertEqual(answer.body["answers"] as? [String: String], ["q1": "Tuesday"])
    }

    func testAnEmptyReplyOrAMissingIdSendsNothing() {
        let info: [AnyHashable: Any] = ["gate": "clarify", "jobId": "job-3", "clarifyId": "q-set", "questionId": "q1"]
        XCTAssertEqual(AlertActions.outcome(action: AlertActions.reply, categoryIdentifier: "", userInfo: info, text: "   "), .ignore)
        var noJob = confirmInfo
        noJob.removeValue(forKey: "jobId")
        XCTAssertEqual(AlertActions.outcome(action: AlertActions.approve, categoryIdentifier: "", userInfo: noJob), .ignore)
    }

    func testApprovingNeedsAnUnlockedPhoneAndRejectingDoesNot() throws {
        for category in [AlertActions.confirmCategory, AlertActions.planCategory] {
            let registered = try XCTUnwrap(AlertActions.categories.first { $0.identifier == category })
            let approve = try XCTUnwrap(registered.actions.first { $0.identifier == AlertActions.approve })
            let reject = try XCTUnwrap(registered.actions.first { $0.identifier == AlertActions.reject })
            XCTAssertTrue(approve.options.contains(.authenticationRequired), category)
            XCTAssertFalse(reject.options.contains(.authenticationRequired), category)
        }
    }

    func testATapOnAGateStillOpensChat() {
        let outcome = AlertActions.outcome(action: UNNotificationDefaultActionIdentifier, categoryIdentifier: AlertActions.confirmCategory, userInfo: confirmInfo)
        XCTAssertEqual(outcome, .open(category: "chat"))
    }

    // MARK: - Clearing from a notification

    @MainActor func testClearingFromANotificationReachesAStoreAScreenIsHolding() async {
        let suite = "AlertActionsTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let onScreen = AlertStore(defaults: defaults)
        XCTAssertTrue(onScreen.clearedFromToday.isEmpty)

        let caughtUp = expectation(description: "the on-screen store re-read")
        let watcher = onScreen.$clearedFromToday.dropFirst().sink { cleared in
            if cleared.contains("a1") { caughtUp.fulfill() }
        }
        AlertStore.clearFromNotification("a1", defaults: defaults)
        await fulfillment(of: [caughtUp], timeout: 2)
        watcher.cancel()

        XCTAssertEqual(defaults.stringArray(forKey: AlertStore.clearedKey), ["a1"])
    }
}

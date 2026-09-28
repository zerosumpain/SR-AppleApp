import Foundation
import UserNotifications

/// The buttons on a raised alert — which is also what an Apple Watch shows.
///
/// ## Why this is the first watch feature, and needs no watch app
///
/// iOS forwards a local notification to the Watch whenever the phone is locked
/// and the Watch is on a wrist, and it brings the notification's category
/// actions with it. A button whose action runs in the BACKGROUND is handed back
/// to this app on the phone, which is woken to handle it; nothing on the Watch
/// has to exist. So every alert this app already raises gains wrist buttons for
/// the price of registering a category — no second target, no second
/// provisioning profile. See `docs/WATCH.md` for what a real watch app adds and
/// what it costs.
///
/// ## Two categories, not one per site category
///
/// `UNNotificationCategory` is matched by identifier, and the site's categories
/// are open-ended — a producer can start sending "garden" tomorrow, and an
/// identifier nobody registered raises a notification with no buttons at all.
/// So the notification carries one of two FIXED identifiers and the site's own
/// category travels in `userInfo`, where the tap handler reads it.
///
/// ## Why no action opens the app
///
/// A `.foreground` action means "unlock the phone and bring the app up", which
/// from a wrist is a request the Watch can only pass on, not honour. Every
/// button here does its whole job in the background, so it works the same from
/// the Watch as from a lock-screen banner. Opening the app stays the default
/// tap, as before.
///
/// ## Answering a stalled chat turn
///
/// A jkai turn that stops at a plan, a confirmation or a single question is
/// PUSHED (SR-Main's dispatcher, `sr.gate.<gate>`) with the ids its answer
/// needs. Approve, Reject and Reply send the same `PATCH …/chat?jobId=` the
/// chat screen sends (`GateAnswer`). Approve and Reply are
/// `.authenticationRequired`: a destructive tool approved from a locked phone
/// in somebody else's hand is the one thing this must never allow. Reject is
/// not — stopping something is always safe.
enum AlertActions {
    /// Every alert but a lapsed connection.
    static let alertCategory = "sr.alert"
    /// A lapsed connection. Registered with NO buttons: the only fix is
    /// re-authorising in a browser, which a wrist cannot do, and clearing it
    /// would hide the one alert that means something has stopped working.
    static let connectionsCategory = "sr.connections"

    /// Mark this alert read on the site, as opening it on the phone does
    /// (`AlertStore.markRead`).
    static let read = "sr.alert.read"
    /// Take this alert off the Today card. Local — see `AlertStore.clearedFromToday`.
    static let clear = "sr.alert.clear"

    /// A chat turn waiting on a confirmation (a destructive tool).
    static let confirmCategory = "sr.gate.confirm"
    /// A chat turn waiting on its plan being approved.
    static let planCategory = "sr.gate.plan"
    /// A chat turn waiting on the answer to one question.
    static let clarifyCategory = "sr.gate.clarify"
    static let approve = "sr.gate.approve"
    static let reject = "sr.gate.reject"
    static let reply = "sr.gate.reply"

    static var categories: Set<UNNotificationCategory> {
        [
            UNNotificationCategory(
                identifier: alertCategory,
                actions: [
                    UNNotificationAction(identifier: read, title: "Mark read", options: []),
                    UNNotificationAction(identifier: clear, title: "Clear from Today", options: []),
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: connectionsCategory,
                actions: [],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: confirmCategory,
                actions: [
                    UNNotificationAction(identifier: approve, title: "Approve", options: [.authenticationRequired]),
                    UNNotificationAction(identifier: reject, title: "Reject", options: [.destructive]),
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: planCategory,
                actions: [
                    UNNotificationAction(identifier: approve, title: "Approve plan", options: [.authenticationRequired]),
                    UNNotificationAction(identifier: reject, title: "Reject", options: [.destructive]),
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: clarifyCategory,
                actions: [
                    UNTextInputNotificationAction(
                        identifier: reply, title: "Reply", options: [.authenticationRequired],
                        textInputButtonTitle: "Send", textInputPlaceholder: "Your answer"
                    ),
                ],
                intentIdentifiers: [],
                options: []
            ),
        ]
    }

    /// Which of the two a raised alert wears.
    static func categoryIdentifier(for alert: SiteAlert) -> String {
        alert.isConnections ? connectionsCategory : alertCategory
    }

    /// What a response asked for.
    enum Outcome: Equatable {
        /// The notification itself was tapped: go to the tab owning `category`.
        case open(category: String)
        case openCommission(id: String)
        /// Mark this alert read on the site.
        case read(id: String)
        /// Take this alert off the Today card.
        case clear(id: String)
        /// Answer a stalled chat turn.
        case answer(GateAnswer)
        /// A button pressed on a notification that carries no id. Every alert
        /// this app raises has one, so this is a guard, and it must not open
        /// the app: the button promised to stay in the background.
        case ignore
    }

    /// Decide what a response means. Pure, so the routing is testable without a
    /// notification centre — which a simulator test cannot drive.
    ///
    /// The site's category is read from `userInfo` first. Every producer puts
    /// it there (alerts, household, games, the personal-health connection
    /// check, which sets no identifier at all), and a notification raised
    /// before these categories existed carries it as its identifier instead,
    /// so that is the fallback.
    static func outcome(action: String, categoryIdentifier: String, userInfo: [AnyHashable: Any], text: String? = nil) -> Outcome {
        let category = userInfo["category"] as? String ?? categoryIdentifier
        let id = userInfo["id"] as? String
        switch action {
        case approve, reject, reply:
            guard let answer = GateAnswer(action: action, userInfo: userInfo, text: text) else { return .ignore }
            return .answer(answer)
        case read:
            guard let id else { return .ignore }
            return .read(id: id)
        case clear:
            guard let id else { return .ignore }
            return .clear(id: id)
        default:
            if let commissionId = userInfo["commissionId"] as? String, UUID(uuidString: commissionId) != nil {
                return .openCommission(id: commissionId)
            }
            return .open(category: category)
        }
    }
}

/// One answer to a stalled chat turn, from a notification button.
///
/// Built from the push's `userInfo` (`gate`, `jobId` and the gate's own id),
/// never from anything the app remembers: the turn may have been started on
/// the website, and the push is the only thing that knows its ids.
struct GateAnswer: Equatable {
    enum Kind: Equatable {
        case confirm(id: String, approved: Bool)
        case plan(id: String, approved: Bool)
        case clarify(id: String, questionId: String, text: String)
    }

    let jobId: String
    let kind: Kind

    init(jobId: String, kind: Kind) {
        self.jobId = jobId
        self.kind = kind
    }

    /// Nil for a response that cannot be answered: a missing id, a gate this
    /// build does not know, an empty reply.
    init?(action: String, userInfo: [AnyHashable: Any], text: String?) {
        guard let gate = userInfo["gate"] as? String,
              let job = userInfo["jobId"] as? String, !job.isEmpty else { return nil }
        switch (action, gate) {
        case (AlertActions.approve, "confirm"), (AlertActions.reject, "confirm"):
            guard let id = userInfo["confirmId"] as? String else { return nil }
            self.init(jobId: job, kind: .confirm(id: id, approved: action == AlertActions.approve))
        case (AlertActions.approve, "plan"), (AlertActions.reject, "plan"):
            guard let id = userInfo["planId"] as? String else { return nil }
            self.init(jobId: job, kind: .plan(id: id, approved: action == AlertActions.approve))
        case (AlertActions.reply, "clarify"):
            let answer = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = userInfo["clarifyId"] as? String,
                  let question = userInfo["questionId"] as? String, !answer.isEmpty else { return nil }
            self.init(jobId: job, kind: .clarify(id: id, questionId: question, text: answer))
        default:
            return nil
        }
    }

    /// `PATCH` here — the chat screen's own call (`ChatStore.acknowledge`).
    var path: String {
        let job = jobId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? jobId
        return "api/workflows/orchestrator/chat?jobId=\(job)"
    }

    /// The `_ack` the server's waiter is keyed on.
    var body: [String: Any] {
        switch kind {
        case .confirm(let id, let approved):
            return ["type": "confirm_ack", "confirmId": id, "decision": approved ? "approved" : "rejected"]
        case .plan(let id, let approved):
            return ["type": "plan_ack", "planId": id, "decision": approved ? "approved" : "rejected"]
        case .clarify(let id, let question, let text):
            return ["type": "clarify_ack", "clarifyId": id, "answers": [question: text]]
        }
    }

    /// Said on a local notification when the answer did not land.
    var failureTitle: String {
        switch kind {
        case .confirm: return "Your answer was not sent"
        case .plan: return "Your plan answer was not sent"
        case .clarify: return "Your reply was not sent"
        }
    }

    /// Send it. True when the turn took it. A 404 means the turn was answered
    /// elsewhere or stopped waiting — not worth a second notification.
    @MainActor func send() async -> Delivery {
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            let _: EmptyReply = try await SiteClient.shared.send(path, method: "PATCH", body: data, asSelf: true)
            return .sent
        } catch SiteError.status(let code, _) where code == 404 {
            return .gone
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    enum Delivery: Equatable {
        case sent
        case gone
        case failed(String)
    }
}

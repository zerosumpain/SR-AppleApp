import Foundation

/// A trip question, answered from its notification (v8, plan §5.4).
///
/// ## A category per question, and no extension
///
/// The system's buttons are fixed per CATEGORY, and every question has its
/// own answers. The usual answer is a notification content extension that
/// draws them; that is a new target, with its own App ID and provisioning
/// profile, which this app avoids (see `AlertActions` on the Watch). So the
/// phone registers one category per OPEN question it knows of —
/// `trip-q-<questionId>`, its buttons the answers' own words (each action's
/// identifier is the answer's id) and "You decide" — every time it loads the
/// trips (`TripQuestionAlerts`). The site pushes the question wearing that
/// identifier, and the buttons are there.
///
/// A push for a question this phone has not loaded yet finds no such
/// category: iOS shows it plainly, with no buttons, and a tap still opens the
/// question. So does a push wearing the contract's fixed `trip-question`.
///
/// ## Answering in the background
///
/// Every button does its whole job in the background (no `.foreground`), as
/// the other alerts' do: `POST …/questions/:qid` with the answer, then the
/// trip is re-read. Said on a local notification only when it did NOT land —
/// silence is what success sounds like everywhere else in the app.
///
/// Foundation only, so the Linux harness tests it; the UserNotifications half
/// is `TripQuestionAlerts`.
enum TripQuestionPushes {
    /// `trip-q-<questionId>`: a question this phone has registered buttons for.
    static let categoryPrefix = "trip-q-"
    /// The wire contract's fixed category (and `userInfo.category`): no buttons.
    static let fixedCategory = "trip-question"
    /// "You decide": take the answer the plan already assumes.
    static let decide = "decide"
    static let decideTitle = "You decide"
    /// Answers shown as buttons; with "You decide", four — what a banner and
    /// a wrist both show.
    static let maxAnswers = 3

    /// `UNNotificationDefaultActionIdentifier` and the dismiss one, spelled
    /// out so this file needs no UserNotifications (`TripQuestionAlertsTests`
    /// checks they match).
    static let tapAction = "com.apple.UNNotificationDefaultActionIdentifier"
    static let dismissAction = "com.apple.UNNotificationDismissActionIdentifier"

    struct Button: Equatable, Hashable {
        let id: String
        let title: String
    }

    struct Category: Equatable, Hashable {
        let identifier: String
        let buttons: [Button]
    }

    static func categoryIdentifier(questionId: String) -> String { categoryPrefix + questionId }

    static func questionId(categoryIdentifier: String) -> String? {
        guard categoryIdentifier.hasPrefix(categoryPrefix) else { return nil }
        let id = String(categoryIdentifier.dropFirst(categoryPrefix.count))
        return id.isEmpty ? nil : id
    }

    /// Either form: a registered question's, or the fixed one.
    static func isQuestion(_ category: String) -> Bool {
        category == fixedCategory || questionId(categoryIdentifier: category) != nil
    }

    // MARK: Categories

    /// One question's buttons: its first three answers in the server's order,
    /// then "You decide". Nil for a question that is not open, or has no
    /// answer a button can carry.
    ///
    /// An answer whose id would collide with "You decide" or with the
    /// system's own identifiers is left off rather than mistaken for them.
    static func category(_ question: TripQuestion) -> Category? {
        guard question.status == .open else { return nil }
        let answers = question.answers
            .filter { usable($0.id) && !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(maxAnswers)
            .map { Button(id: $0.id, title: $0.label) }
        guard !answers.isEmpty else { return nil }
        return Category(
            identifier: categoryIdentifier(questionId: question.id),
            buttons: Array(answers) + [Button(id: decide, title: decideTitle)]
        )
    }

    /// Every open question of every trip on the phone, one category each,
    /// sorted so an unchanged set compares equal.
    static func categories(_ bundles: [TripBundle]) -> [Category] {
        categories(questions: bundles.flatMap { $0.questions ?? [] })
    }

    static func categories(questions: [TripQuestion]) -> [Category] {
        var seen: Set<String> = []
        var out: [Category] = []
        for question in questions {
            guard let category = category(question), seen.insert(category.identifier).inserted else { continue }
            out.append(category)
        }
        return out.sorted { $0.identifier < $1.identifier }
    }

    private static func usable(_ id: String) -> Bool {
        !id.isEmpty && id != decide && !id.hasPrefix("com.apple.")
    }

    // MARK: Responses

    enum Choice: Equatable {
        case answer(String)
        /// Take the assumed answer.
        case decide
    }

    /// An answer from a button: which trip, which question, which answer.
    struct Answer: Equatable {
        let tripId: String
        let questionId: String
        let choice: Choice

        /// `POST` here (SR-Main `questions/:qid`).
        var path: String {
            "api/native/trips/\(escape(tripId))/questions/\(escape(questionId))"
        }
    }

    enum Response: Equatable {
        /// A button: answer in the background, open nothing.
        case answer(Answer)
        /// The notification itself: the trip's planning home, at the question.
        case open(TripLink)
        /// A button on a push that names no trip — or a dismissal. Must not
        /// open the app: the button promised to stay in the background.
        case ignore
    }

    /// What a response to a trip question means. Nil when it is not a trip
    /// question's (the other alerts' routing takes it).
    ///
    /// The ids come from `userInfo` (`tripId`, `questionId`), else its `url`
    /// (`sr://trips/<id>/questions/<qid>`), else — the question only — the
    /// category's own identifier: a phone that hides notification details
    /// gets a push keeping only `category` and `url`.
    static func response(action: String, categoryIdentifier: String, userInfo: [AnyHashable: Any]) -> Response? {
        let category = userInfo["category"] as? String ?? categoryIdentifier
        guard isQuestion(categoryIdentifier) || isQuestion(category) else { return nil }
        var link = TripLink.from(userInfo: userInfo)
        if link.questionId == nil {
            link.questionId = questionId(categoryIdentifier: categoryIdentifier) ?? questionId(categoryIdentifier: category)
            if link.questionId != nil { link.date = nil }
        }
        switch action {
        case tapAction:
            return .open(link)
        case dismissAction, "":
            return .ignore
        default:
            guard let trip = link.tripId, let question = link.questionId else { return .ignore }
            return .answer(Answer(tripId: trip, questionId: question, choice: action == decide ? .decide : .answer(action)))
        }
    }

    // MARK: The request

    /// `{ action: 'answer', answerId }` or `{ action: 'decide' }` — or, for
    /// a family question asked of somebody who is not one of its deciders,
    /// `{ action: 'vote', answerId }`: the family votes and a parent decides
    /// (wire contract, Questions). "You decide" is then a vote for the
    /// answer the plan already assumes.
    ///
    /// `question` and `access` are what this phone holds of the trip; with
    /// neither (a trip not loaded yet) it answers, and the site judges.
    static func body(_ choice: Choice, question: TripQuestion?, access: TripAccess?) -> [String: String] {
        let decider = access.map { $0.canEdit || $0.canApprove } ?? true
        let votes = question?.audience == "family" && !decider
        switch choice {
        case .answer(let id):
            return ["action": votes ? "vote" : "answer", "answerId": id]
        case .decide:
            if votes, let assumed = question?.defaultAnswerId, !assumed.isEmpty {
                return ["action": "vote", "answerId": assumed]
            }
            return ["action": "decide"]
        }
    }

    /// Ids are the server's own (url-safe), escaped all the same, as
    /// `TripsAPI.path` does: a `/` in one would address another route.
    private static func escape(_ part: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        return part.addingPercentEncoding(withAllowedCharacters: allowed) ?? part
    }
}

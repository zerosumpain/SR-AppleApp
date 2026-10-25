import Foundation

/// Where a trip notification or the Lock Screen card leads: the trips list,
/// a trip, one of its days, or one of its questions. `sr://trips`,
/// `sr://trips/<id>`, `sr://trips/<id>/<date>` and
/// `sr://trips/<id>/questions/<qid>`, or a notification's `tripId`, `date`
/// and `questionId` (v8).
///
/// Foundation only: the Linux harness compiles it.
struct TripLink: Equatable {
    /// Nil: the list itself.
    var tripId: String?
    var date: String?
    /// v8: a question to open the trip's planning home at.
    var questionId: String? = nil

    /// The category an off-plan alert is posted with (`TripOffPlan.notify`).
    static let category = "trip"

    static func from(url: URL) -> TripLink? {
        guard url.scheme?.lowercased() == "sr", url.host?.lowercased() == "trips" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let id = parts.first else { return TripLink(tripId: nil, date: nil) }
        // `questions/<qid>`: the planning home, at that question. Never a day
        // called "questions".
        if parts.count > 1, parts[1] == "questions" {
            return TripLink(tripId: id, date: nil, questionId: parts.count > 2 ? parts[2] : nil)
        }
        return TripLink(tripId: id, date: parts.count > 1 ? parts[1] : nil)
    }

    /// A tapped trip notification. Without a trip id it still lands on the
    /// list — never on the alerts inbox, where a trip alert is not.
    ///
    /// The ids are read from `userInfo` first, then from its `url`: a phone
    /// that hides notification details gets a push whose `userInfo` keeps
    /// only `category` and `url` (SR-Main `privatePush`), and the link still
    /// names the trip and the question.
    static func from(userInfo: [AnyHashable: Any]) -> TripLink {
        let id = nonEmpty(userInfo["tripId"])
        let date = nonEmpty(userInfo["date"])
        let question = nonEmpty(userInfo["questionId"])
        if id == nil, let raw = userInfo["url"] as? String, let url = URL(string: raw), let link = from(url: url) {
            return link
        }
        guard let id else { return TripLink(tripId: nil, date: nil) }
        if let question { return TripLink(tripId: id, date: nil, questionId: question) }
        return TripLink(tripId: id, date: date)
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        (value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `sr://trips/<id>/questions/<qid>` — what a question's push carries.
    static func questionURL(tripId: String, questionId: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        let trip = tripId.addingPercentEncoding(withAllowedCharacters: allowed) ?? tripId
        let question = questionId.addingPercentEncoding(withAllowedCharacters: allowed) ?? questionId
        return URL(string: "sr://trips/\(trip)/questions/\(question)")
    }
}

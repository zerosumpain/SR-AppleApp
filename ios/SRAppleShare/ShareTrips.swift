import Foundation

// "Add to a trip", over the wire: the trips to offer, and the one turn sent.
// The extension's only two trip requests, each with the shelf's credential —
// the same one the backlog share posts with (FamilyBacklogShared.swift).

enum TripSharePost {
    enum Outcome: Equatable {
        /// The planner has it: started as a job (202), or answered at once.
        case sent
        /// No credential on the shelf, or no longer family.
        case notSignedIn
        /// The site said no, in its own words.
        case refused(String)
        /// Never reached the site. NOT queued: a conversation needs the
        /// planner to answer, as on the trip's own "Tell the planner".
        case unreachable
    }

    /// The family's trips, for the picker. Nil without a credential or an
    /// answer — the sheet then offers the backlog alone, as before.
    static func trips() async -> [TripShareTarget]? {
        guard let (origin, token) = credential() else { return nil }
        var request = URLRequest(url: origin.appending(path: "api/native/trips"))
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONDecoder().decode(TripShareList.self, from: data))?.trips
    }

    /// One turn of the trip's conversation, started and left to run: the
    /// v8 planner answers on the trip, with a proposal or a question.
    static func send(_ text: String, to tripId: String) async -> Outcome {
        guard let (origin, token) = credential(),
              let body = try? JSONEncoder().encode(TripShareTurn(text: text, async: true)) else { return .notSignedIn }
        // The id as ONE component: `appending(component:)` escapes a `/` in
        // it, so it can never address another route.
        let url = origin.appending(path: "api/native/trips").appending(component: tripId).appending(path: "converse")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        // A job starts at once (202). A server too old for jobs would think
        // for a minute; the sheet does not wait that long.
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return .unreachable }
        switch http.statusCode {
        case 200..<300:
            return .sent
        case 401, 403:
            return .notSignedIn
        case 400..<500:
            let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            return .refused(error ?? "The planner would not take that.")
        default:
            return .unreachable
        }
    }

    private static func credential() -> (URL, String)? {
        guard let credential = FamilyShelf.load(FamilyWidgetCredential.self, .credential),
              let origin = URL(string: credential.origin), origin.scheme == "https" else { return nil }
        return (origin, credential.token)
    }
}

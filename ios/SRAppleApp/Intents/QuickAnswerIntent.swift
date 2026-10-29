import AppIntents
import Foundation

/// "Quick answer from jkai ‹question›" — asked and answered aloud, without
/// opening the app (Siri, the Action button, Shortcuts).
///
/// The one place a turn is sent with nobody looking at the thread, so it is
/// held to what cannot go wrong out of sight (owner decision 14, 2026-10-28):
///
/// - Unlocked only. `.requiresAuthentication` makes iOS ask for Face ID or
///   the passcode first: the answer is personal, and a locked phone on a
///   table must not read John's day to whoever holds it.
/// - Read-only. SR-Jkai-Core gives a 'siri' turn only read tools, auto-denies
///   every gate, caps it at four rounds and answers in the voice overlay. Its
///   model and spend are the `jkai.voice` workload.
/// - One thread. Every quick answer lands in "Quick answers" (Core picks it,
///   whatever the body names), so each one can be read later.
///
/// `AskJkaiIntent` still fills the composer unsent: anything that might need
/// a yes goes through the screen.
struct QuickAnswerIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick answer from jkai"
    static var description = IntentDescription(
        "Ask jkai something and hear a short answer. Read-only: anything that would change something is left for the app."
    )
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Question", requestValueDialog: "What would you like to know?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Hands-free answers read the owner's private tools.
        // Not while viewing as someone: their phone would not answer as John.
        guard AccessStore.shared.current.owner, AccessStore.shared.allows(.chat),
              AccessStore.shared.viewingAs == nil else {
            throw AccessRefusal.unavailable
        }
        guard SiteClient.shared.isPaired else {
            return .result(dialog: IntentDialog(
                LocalizedStringResource(stringLiteral: "Connect this iPhone to Strange Ramblings first.")
            ))
        }
        let line = await QuickAnswerRunner.ask(question, surface: "siri")
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: line)))
    }
}

/// `QuickAnswer.run` on the real network. Shared by the intent ('siri') and
/// the Watch's quick answer ('watch').
@MainActor
enum QuickAnswerRunner {
    static func ask(_ question: String, surface: String, client: SiteClient = .shared) async -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "What would you like to know?" }
        let request = QuickAnswer.request(question: trimmed, surface: surface)
        let outcome = await QuickAnswer.run(
            sleep: { seconds in try? await Task.sleep(for: .seconds(seconds)) },
            post: {
                // The same body every attempt: the requestId makes a retry the
                // same turn, not a second one.
                let reply = try await client.postTurn(try request.body())
                return TurnStart.classify(status: reply.status, body: reply.body, retryAfter: reply.retryAfter)
            },
            poll: { job in
                let (data, http) = try await client.exchange("api/workflows/orchestrator/chat?jobId=\(job)", method: "GET")
                return QuickAnswer.readPoll(status: http.statusCode, body: data)
            }
        )
        return QuickAnswer.spoken(outcome)
    }
}

import AppIntents
import Foundation

/// Siri, Shortcuts and the Action button.
///
/// These are the capability a web page cannot have at all: the phone answering
/// a question about you without being opened, and a sentence you say becoming a
/// thread. They live in the app target rather than an extension deliberately —
/// an extension needs a bundle identifier and a provisioning profile of its
/// own, and this repository's TestFlight lane holds exactly one profile, for
/// the app. Everything here works from the app target and signs with what we
/// already have. Widgets and Live Activities do not, which is why there are
/// none yet.

/// "How am I doing?"
struct HealthTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Health today"
    static var description = IntentDescription(
        "Today's readiness, recovery, HRV, resting heart rate and sleep, read out."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard SiteClient.shared.isPaired else {
            return .result(dialog: IntentDialog(
                LocalizedStringResource(stringLiteral: "Connect this iPhone to Strange Ramblings first.")
            ))
        }
        let summary: HealthSummary = try await SiteClient.shared.send("api/native/health/summary")

        var parts: [String] = []
        if let readiness = summary.readiness {
            parts.append("Readiness \(Int(readiness.score.rounded())), \(readiness.label).")
        }
        // Spoken, so the unit is said rather than printed: "fifty two ms" is
        // not a sentence anybody says.
        for figure in summary.figures {
            switch figure.key {
            case "recovery": parts.append("Recovery \(figure.display) percent.")
            case "hrv": parts.append("HRV \(figure.display) milliseconds.")
            case "rhr": parts.append("Resting heart rate \(figure.display).")
            case "sleep": parts.append("Slept \(figure.display).")
            default: break
            }
        }
        if summary.isMock { parts.append("These are demonstration figures, not measurements.") }

        let sentence = parts.isEmpty ? "No health figures yet." : parts.joined(separator: " ")
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: sentence)))
    }
}

/// "Ask jkai ‹something›" — opens the app on chat with the question waiting.
///
/// It deliberately does NOT send. A turn sent from a locked phone with no
/// transcript in front of you is a turn you cannot see go wrong, and chat here
/// can open gates the phone is unable to answer. The question lands in the
/// composer and a thumb sends it.
struct AskJkaiIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask jkai"
    static var description = IntentDescription("Open jkai with a question ready to send.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Question", requestValueDialog: "What would you like to ask?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDelegate.pending.question = question
        AppDelegate.pending.tab = .chat
        return .result()
    }
}

/// "Sync my health" — push whatever is queued, now.
struct SyncNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync now"
    static var description = IntentDescription("Upload anything this iPhone has collected and not yet sent.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppDelegate.pending.sync = true
        AppDelegate.pending.tab = .today
        return .result(dialog: IntentDialog(
            LocalizedStringResource(stringLiteral: "Syncing in the background.")
        ))
    }
}

/// The phrases Siri listens for, and the tiles the Shortcuts app offers.
struct SRShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: HealthTodayIntent(),
            phrases: [
                "How am I doing in \(.applicationName)",
                "My health in \(.applicationName)",
            ],
            shortTitle: "Health today",
            systemImageName: "heart.text.square"
        )
        AppShortcut(
            intent: AskJkaiIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask jkai in \(.applicationName)",
            ],
            shortTitle: "Ask jkai",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
        AppShortcut(
            intent: SyncNowIntent(),
            phrases: ["Sync \(.applicationName)"],
            shortTitle: "Sync now",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}

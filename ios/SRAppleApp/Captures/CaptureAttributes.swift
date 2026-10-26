import Foundation
import ActivityKit

/// A capture recording, on the Lock Screen and in the Dynamic Island: a
/// running timer and Stop.
///
/// It is also what makes recording from the Action Button or Control Center
/// legal at all: iOS keeps an `AudioRecordingIntent` recording in the
/// background only while a Live Activity shows it. The app starts it in the
/// same breath as the recorder and ends it at Stop — nothing is left on the
/// Lock Screen and nothing keeps listening.
///
/// Nothing in it is fetched or pushed. Compiled into the app and the
/// SRAppleLive extension (`watch.yml`).
struct CaptureAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When recording began, epoch SECONDS: ActivityKit's own date
        /// decoding counts from 2001, which nothing else here does.
        var startedAt: Double
        /// "recording", or "saving" for the moment between Stop and the card
        /// going away.
        var phase: String
        /// A screenshot came with it (from a Shortcut).
        var withScreenshot: Bool

        var started: Date { Date(timeIntervalSince1970: startedAt) }
        var saving: Bool { phase == "saving" }
    }

    /// "button", "app" or "shortcut".
    var source: String

    /// A tap on the card opens the Captures page.
    var link: URL? { URL(string: "sr://captures") }
}

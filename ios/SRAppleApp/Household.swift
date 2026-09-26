import Foundation
import UserNotifications

/// One arrival or departure, queued for this person on the companion server.
///
/// `title` and `body` are the server's words and are posted verbatim: the body
/// already carries the crossing time ("arrived 17:52"), which is the honest
/// thing for a notification that may reach the phone hours later.
struct HouseholdAlert: Codable, Equatable {
    var id: String
    var title: String
    var body: String
    var at: String?
}
struct HouseholdAlertsResponse: Codable { var alerts: [HouseholdAlert] }

/// The household half of the notification drain.
///
/// Separate from `AlertStore`, which drains the SITE's queue over the owner's
/// native lane. Family members have no site pairing, so their alerts come from
/// the companion server on the credential they already hold. Same contract:
/// post, then acknowledge only what iOS accepted.
enum HouseholdAlerts {
    /// A flush runs on every location fix and HealthKit wake; the queue does not
    /// need asking that often.
    static let minimumInterval: TimeInterval = 60
    /// For both the queue GET and the ack POST (the API default is 25 s).
    static let requestTimeout: TimeInterval = 6

    /// `uploadFailed`: the flush this drain rides on could not reach the
    /// server, so asking again now would only spend the wake's time.
    static func due(last: Date?, now: Date, uploadFailed: Bool = false) -> Bool {
        guard !uploadFailed else { return false }
        guard let last else { return true }
        return now.timeIntervalSince(last) >= minimumInterval
    }

    /// Identified by the alert's id, so a drain that is killed before its ack
    /// and repeated replaces the notification rather than adding a second one.
    static func request(for alert: HouseholdAlert) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = "household"
        content.categoryIdentifier = "household"
        content.userInfo = ["id": alert.id, "category": "household"]
        return UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
    }

    /// Posts each alert through `add` and returns the ids that were accepted,
    /// in order. One failure is skipped, never fatal: it stays unacknowledged
    /// on the server and the next drain tries it again.
    @MainActor static func post(_ alerts: [HouseholdAlert], add: (UNNotificationRequest) async throws -> Void) async -> [String] {
        var delivered: [String] = []
        for alert in alerts {
            do {
                try await add(request(for: alert))
                delivered.append(alert.id)
            } catch {
                continue
            }
        }
        return delivered
    }
}

/// "Share your location with the household?" — asked once per pairing.
///
/// Only put to a phone that is paired and NOT already sharing — locally, or on
/// the server (`refresh()` adopts the server's answer before the question is
/// checked). Answering "Not now" never sends sharing off.
enum SharingQuestion {
    static let title = "Share your location with the household?"
    static let message = "Your family will see where you are and when you arrive or leave places you've named. You can change this any time in Settings."

    static func shouldAsk(paired: Bool, asked: Bool, sharing: Bool) -> Bool {
        paired && !asked && !sharing
    }

    /// Whether `/me` saying "sharing" should switch this phone's sharing on.
    /// Only when the phone is off and has no change of its own waiting to be
    /// sent: a pending local choice outranks the server until it is delivered.
    static func adoptsServerSharing(local: Bool, pending: Bool?, server: Bool) -> Bool {
        server && !local && pending == nil
    }
}

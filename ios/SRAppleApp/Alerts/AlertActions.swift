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
        /// Mark this alert read on the site.
        case read(id: String)
        /// Take this alert off the Today card.
        case clear(id: String)
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
    static func outcome(action: String, categoryIdentifier: String, userInfo: [AnyHashable: Any]) -> Outcome {
        let category = userInfo["category"] as? String ?? categoryIdentifier
        let id = userInfo["id"] as? String
        switch action {
        case read:
            guard let id else { return .ignore }
            return .read(id: id)
        case clear:
            guard let id else { return .ignore }
            return .clear(id: id)
        default:
            return .open(category: category)
        }
    }
}

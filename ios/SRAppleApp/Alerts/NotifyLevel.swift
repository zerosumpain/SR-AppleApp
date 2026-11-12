import Foundation

/// How much this person is notified: Minimal, Normal or Verbose.
///
/// Minimal is what every phone starts on. Each notification has a TIER, the
/// quietest level that still hears it, and a level hears its own tier and
/// every quieter one. Nothing is lost by a lower level: what is not raised is
/// still in the app, on the screen it belongs to.
///
/// The site keeps the level per PERSON and applies it to everything it pushes
/// (`push-devices`, SR-Main). This copy is for what never passes through a
/// push: the notifications the app raises itself, the two pull queues, and a
/// phone paired with the companion alone, which the site cannot ask.
enum NotifyLevel: String, Codable, CaseIterable, Identifiable {
    case minimal, normal, verbose

    static let key = "notify.level"
    /// Chosen here and not yet taken by the site (offline, or not paired).
    private static let unsentKey = "notify.level.unsent"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: return "Minimal"
        case .normal: return "Normal"
        case .verbose: return "Verbose"
        }
    }

    var summary: String {
        switch self {
        case .minimal:
            return "Only what needs you: family messages and the bat phone, the family alarm, a task given to you, a game invite, a child late for school, a question waiting on your answer, and anything that has stopped working."
        case .normal:
            return "Minimal, and: family arriving and leaving, safe arrivals, low batteries, trip reminders and questions, leave-by reminders, tasks finished, your turn in a game, replies and warnings."
        case .verbose:
            return "Everything: also arrival estimates, steps, reactions, finished games, and the day's briefings and updates."
        }
    }

    private var rank: Int {
        switch self {
        case .minimal: return 0
        case .normal: return 1
        case .verbose: return 2
        }
    }

    /// Whether this level raises a notification of that tier.
    func hears(_ tier: NotifyLevel) -> Bool { rank >= tier.rank }

    static func stored(in defaults: UserDefaults = .standard) -> NotifyLevel {
        defaults.string(forKey: key).flatMap(NotifyLevel.init(rawValue:)) ?? .minimal
    }

    /// This phone's level; Minimal until somebody chooses otherwise.
    static var current: NotifyLevel { stored() }

    // MARK: - Tiers for what arrives by pull

    /// The owner's alert ledger, as SR-Main's `push-dispatch` grades it.
    static func tier(for alert: SiteAlert) -> NotifyLevel {
        // A chat turn stalled on an answer.
        if alert.data?["gate"]?.string != nil { return .minimal }
        let kind = alert.data?["kind"]?.string
        if alert.category == "chat", kind == "reply" || kind == "stopped" { return .normal }
        if alert.category == "drive" { return alert.isAlert ? .normal : .verbose }
        if alert.isConnections || alert.isAlert { return .minimal }
        return alert.isWarning ? .normal : .verbose
    }

    /// The household queue: an arrival estimate (`eta-…`) is Verbose, a
    /// crossing is Normal.
    static func tier(forHousehold id: String) -> NotifyLevel {
        id.hasPrefix("eta-") ? .verbose : .normal
    }

    // MARK: - Keeping the site's copy

    private struct Reply: Decodable { let notifyLevel: NotifyLevel? }

    /// Choose a level: kept here at once, and sent to the site when paired.
    /// Returns nil when the site took it (or there is no site to tell).
    @MainActor @discardableResult
    static func choose(_ level: NotifyLevel, defaults: UserDefaults = .standard) async -> String? {
        defaults.set(level.rawValue, forKey: key)
        defaults.set(true, forKey: unsentKey)
        return await sync(defaults: defaults)
    }

    /// Send a choice the site has not taken; otherwise take the site's, which
    /// another of this person's phones may have changed. Silent when offline:
    /// the next launch tries again, and this phone goes on using its own copy.
    @MainActor @discardableResult
    static func sync(defaults: UserDefaults = .standard) async -> String? {
        guard !SRDemo.isOn, SiteClient.shared.token != nil else { return nil }
        do {
            if defaults.bool(forKey: unsentKey) {
                let body = try JSONSerialization.data(withJSONObject: ["notifyLevel": stored(in: defaults).rawValue])
                let _: Reply = try await SiteClient.shared.send("api/native/push", method: "PATCH", body: body, asSelf: true)
                defaults.set(false, forKey: unsentKey)
            } else {
                let reply: Reply = try await SiteClient.shared.send("api/native/push", asSelf: true)
                if let level = reply.notifyLevel { defaults.set(level.rawValue, forKey: key) }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

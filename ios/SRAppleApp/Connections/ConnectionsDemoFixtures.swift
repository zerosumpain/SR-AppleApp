import Foundation

// MARK: - Demo connections
//
// `-SRDemo` answers `/api/native/connections` with ONE lapsed Gmail — the case
// the whole feature exists for — so the CI screenshots show the banner on every
// tab. Synthetic: the repository is public.

extension SRDemoFixtures {

    static func demoConnectionItem(_ clock: DemoClock) -> String {
        """
        {"id": "gmail:2", "label": "Gmail", "group": "Google", "status": "auth_expired",
         "detail": "Google stopped accepting the site's sign-in, so mail steps are paused.",
         "fixHint": "Sign in to Google again from the site. It takes about a minute.",
         "fixUrl": "https://strangeramblings.com/admin/connections",
         "since": \(s(clock.iso(minutesAgo: 60 * 26)))}
        """
    }

    /// None at all for the App Store screenshots (`-SRStoreShots`): the
    /// banner would sit across every shot.
    static func connectionsFeed(_ clock: DemoClock) -> String {
        let items = SRDemo.isStoreShots ? "" : demoConnectionItem(clock)
        return """
        {"needsAttention": [\(items)], "checkedAt": \(s(clock.iso(minutesAgo: 2)))}
        """
    }

    /// The `connections` block on `/api/native/today`.
    static func todayConnections(_ clock: DemoClock) -> String {
        if SRDemo.isStoreShots { return #"{"needsAttention": 0, "items": []}"# }
        return """
        {"needsAttention": 1, "items": [\(demoConnectionItem(clock))]}
        """
    }
}

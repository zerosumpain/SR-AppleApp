#if DEBUG
import Foundation

// MARK: - Demo connections
//
// `-SRDemo` answers `/api/native/connections` with ONE lapsed Gmail — the case
// the whole feature exists for — so the CI screenshots show the banner on every
// tab. Synthetic: the repository is public.

extension SRDemoFixtures {

    static func demoConnectionItem(_ clock: DemoClock) -> String {
        """
        {"id": "google:gmail", "label": "Gmail", "group": "Google", "status": "expired",
         "detail": "Google stopped accepting the site's sign-in, so mail steps are paused.",
         "fixHint": "Sign in to Google again from the site. It takes about a minute.",
         "fixUrl": "https://strangeramblings.com/admin/connections",
         "since": \(s(clock.iso(minutesAgo: 60 * 26)))}
        """
    }

    static func connectionsFeed(_ clock: DemoClock) -> String {
        """
        {"needsAttention": [\(demoConnectionItem(clock))], "checkedAt": \(s(clock.iso(minutesAgo: 2)))}
        """
    }

    /// The `connections` block on `/api/native/today`.
    static func todayConnections(_ clock: DemoClock) -> String {
        """
        {"needsAttention": 1, "items": [\(demoConnectionItem(clock))]}
        """
    }
}
#endif

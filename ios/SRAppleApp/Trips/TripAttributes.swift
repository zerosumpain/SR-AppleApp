import Foundation
import ActivityKit

/// A trip day on the Lock Screen: "Next: Pantheon · leave in 8 min · 12 min walk".
///
/// Separate from `JourneyAttributes` (the family's journeys). Started and
/// updated by the app itself in this phase — no server push — but the shape is
/// the contract's (SR-Main `docs/superpowers/specs/2026-10-13-trips.md`,
/// "Live Activity") so a later push can drive it unchanged. Every property
/// name is a JSON key.
///
/// Times are epoch SECONDS (`Double`), as with journeys: ActivityKit's own
/// date decoding counts from 2001, which a server has no reason to know.
///
/// Compiled into the app and the SRAppleLive extension (`watch.yml`).
struct TripAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var nextTitle: String
        /// When to leave for it, epoch seconds.
        var leaveAt: Double
        /// "walk", "cycle", "drive" or "transit".
        var legMode: String
        var legMinutes: Int
        /// When the plan arrives there, epoch seconds.
        var arriveAt: Double
        /// 0-based index of the next stop, and how many stops the day has.
        var stopIndex: Int
        var stopCount: Int

        var leave: Date { Date(timeIntervalSince1970: leaveAt) }
        var arrive: Date { Date(timeIntervalSince1970: arriveAt) }

        /// "12 min walk", "25 min by transit".
        var legLine: String {
            let how: String
            switch legMode {
            case "walk": how = "walk"
            case "cycle": how = "cycle"
            case "drive": how = "drive"
            case "transit": how = "by transit"
            case "taxi": how = "by taxi"
            default: how = legMode
            }
            return "\(legMinutes) min \(how)"
        }

        /// "leave in 8 min", "leave now", "left 3 min late".
        func leaveLine(now: Date) -> String {
            let minutes = Int((leaveAt - now.timeIntervalSince1970) / 60)
            if minutes > 0 { return "leave in \(minutes) min" }
            if minutes > -2 { return "leave now" }
            return "\(-minutes) min past leave time"
        }

        var symbol: String {
            switch legMode {
            case "walk": return "figure.walk"
            case "cycle": return "bicycle"
            case "drive": return "car.fill"
            case "transit": return "tram.fill"
            case "taxi": return "car.side.fill"
            default: return "mappin.and.ellipse"
            }
        }

        /// "Stop 3 of 7".
        var stopLine: String { "Stop \(stopIndex + 1) of \(stopCount)" }
    }

    var tripId: String
    var title: String

    /// Where a tap on the card goes: `sr://trips/<id>`, which the app opens
    /// at the day running now (`Router.openTrip`). Without it a tap opened
    /// the app wherever it was last left.
    var link: URL? {
        tripId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap { URL(string: "sr://trips/\($0)") }
    }
}

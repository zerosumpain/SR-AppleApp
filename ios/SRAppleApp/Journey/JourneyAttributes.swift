import Foundation
import ActivityKit

/// A family member on the move — the Live Activity the site starts, updates
/// and ends by push (SR-Main `$lib/home/presence/live-journey`).
///
/// Compiled into the app (which reports tokens) and the Live Activity
/// extension (which draws it). The type NAME is part of the contract: the
/// start push names it as `attributes-type`. Every property name is too —
/// ActivityKit decodes the push's JSON straight into these, and a renamed key
/// drops the whole update.
///
/// Times arrive as epoch SECONDS (`Double`), not `Date`: ActivityKit's own
/// date decoding counts from 2001, which the server has no reason to know.
struct JourneyAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "moving", "arrived" or "ended".
        var phase: String
        /// "Sam left School", "Sam arrived at Home".
        var headline: String
        /// "2.4 km from home · walking · ~12 min".
        var detail: String
        var distanceHomeM: Double?
        /// 0–1 toward home. Nil when the journey started at home.
        var progress: Double?
        var etaMinutes: Int?
        /// The trail's coarse mode: walking, active, vehicle, rail, still.
        var mode: String?
        var updatedAt: Double

        var updated: Date { Date(timeIntervalSince1970: updatedAt) }
        var arrived: Bool { phase == "arrived" }
        var moving: Bool { phase == "moving" }

        /// "2.4 km", "650 m" — the Dynamic Island's trailing figure.
        var shortDistance: String? {
            guard let m = distanceHomeM else { return nil }
            if m < 1000 { return "\(Int((m / 10).rounded()) * 10) m" }
            return m < 10_000 ? String(format: "%.1f km", m / 1000) : "\(Int((m / 1000).rounded())) km"
        }

        /// An SF Symbol for how they are moving.
        var symbol: String {
            if arrived { return "house.fill" }
            switch mode {
            case "walking": return "figure.walk"
            case "active": return "figure.run"
            case "vehicle": return "car.fill"
            case "rail": return "tram.fill"
            case "still": return "pause.circle"
            default: return "location.fill"
            }
        }
    }

    var journeyId: String
    var name: String
    var fromPlace: String
    var startedAt: Double
}

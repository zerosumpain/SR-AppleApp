import Foundation

// MARK: - Demo location hold
//
// `-SRDemo` answers for `/api/native/family/hold`: GET, PUT and DELETE, held
// in memory for the demo session. Synthetic — the point the phone sends back
// is whatever the demo was asked to hold.

final class LocationHoldDemo: @unchecked Sendable {
    static let shared = LocationHoldDemo()

    private let lock = NSLock()
    private var held: [String: Any]?

    func route(method: String, body: Data?, clock: SRDemoFixtures.DemoClock) -> String? {
        lock.lock(); defer { lock.unlock() }
        switch method {
        case "GET":
            break
        case "PUT":
            guard let body, let ask = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
            held = ["lat": ask["lat"] ?? 0, "lon": ask["lon"] ?? 0, "label": ask["label"] ?? "Here",
                    "since": clock.iso(minutesAgo: 0), "until": ask["until"] ?? clock.iso(minutesAgo: -60)]
        case "DELETE":
            held = nil
        default:
            return nil
        }
        let answer: [String: Any] = ["hold": held ?? NSNull()]
        return (try? JSONSerialization.data(withJSONObject: answer)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

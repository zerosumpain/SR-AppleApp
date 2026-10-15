import Foundation

/// Where a trip notification or the Lock Screen card leads: the trips list,
/// a trip, or one of its days. `sr://trips`, `sr://trips/<id>` and
/// `sr://trips/<id>/<date>`, or a notification's `tripId` and `date`.
///
/// Foundation only: the Linux harness compiles it.
struct TripLink: Equatable {
    /// Nil: the list itself.
    var tripId: String?
    var date: String?

    /// The category an off-plan alert is posted with (`TripOffPlan.notify`).
    static let category = "trip"

    static func from(url: URL) -> TripLink? {
        guard url.scheme?.lowercased() == "sr", url.host?.lowercased() == "trips" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        return TripLink(tripId: parts.first, date: parts.count > 1 ? parts[1] : nil)
    }

    /// A tapped trip notification. Without a trip id it still lands on the
    /// list — never on the alerts inbox, where a trip alert is not.
    static func from(userInfo: [AnyHashable: Any]) -> TripLink {
        let id = (userInfo["tripId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let date = (userInfo["date"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return TripLink(tripId: id, date: id == nil ? nil : date)
    }
}

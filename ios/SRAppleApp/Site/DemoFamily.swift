#if DEBUG
import Foundation

/// The Family tab's demo household. Central Park, never a real address: the
/// repo is public, and a route starts at somebody's front door.
///
/// Built as JSON and DECODED, not constructed in Swift, so the fixture goes
/// through the same decoder a real view does and cannot quietly drift from it.
extension SRDemoFixtures {
    static func householdView(now: Date) -> HouseholdViewResponse {
        let iso = ISO8601DateFormatter()
        let at = { (minutesAgo: Double) in iso.string(from: now.addingTimeInterval(-minutesAgo * 60)) }
        let epoch = { (minutesAgo: Double) in Int(now.addingTimeInterval(-minutesAgo * 60).timeIntervalSince1970) }

        // A walk up the park's east side and back, a fix a minute, with a
        // twenty-minute hole in the middle so the line breaks where it should.
        var walk: [String] = []
        for i in 0..<40 {
            let minutesAgo = Double(115 - i * 2 - (i >= 20 ? 20 : 0))
            let t = Double(i) / 39
            let lat = 40.7644 + 0.012 * sin(t * .pi)
            let lon = -73.9730 + 0.004 * t
            walk.append("[\(String(format: "%.5f", lat)),\(String(format: "%.5f", lon)),\(epoch(minutesAgo))]")
        }
        let school = (0..<12).map { i in
            "[\(String(format: "%.5f", 40.7812 - Double(i) * 0.0009)),\(String(format: "%.5f", -73.9665 - Double(i) * 0.0004)),\(epoch(Double(400 - i * 3)))]"
        }

        // The same answer `AccessStore` holds in demo mode, so the view and
        // the tab bar never disagree.
        let access = SRDemo.access
        let accessJSON = "{\"owner\":\(access.owner),\"chat\":\(access.chat),\"news\":\(access.news),\"research\":\(access.research),\"notes\":\(access.notes),\"intel\":\(access.intel),\"family\":\(access.family),\"sitePair\":null}"

        let json = """
        {"view":{"generatedAt":"\(at(1))","viewer":"owner","people":[
          {"subject":"alex","name":"Alex","self":true,"status":"out","line":"Bethesda Terrace · seen 2m ago",
           "batteryPct":64,"lastSeenAt":"\(at(2))","position":{"lat":40.7740,"lon":-73.9708,"at":"\(at(2))"},
           "today":{"firstOut":"08:12","minutesOut":127,"distanceKm":4.6,"stops":["Home","The Boathouse","Bethesda Terrace"],"trail":[\(walk.joined(separator: ","))]}},
          {"subject":"sam","name":"Sam","self":false,"status":"out","line":"At School · seen 6m ago",
           "batteryPct":18,"lastSeenAt":"\(at(6))","position":{"lat":40.7713,"lon":-73.9709,"at":"\(at(6))"},
           "today":{"firstOut":"07:48","minutesOut":312,"distanceKm":1.9,"stops":["Home","School"],"trail":[\(school.joined(separator: ","))]}},
          {"subject":"robin","name":"Robin","self":false,"status":"home","line":"At home · seen 4m ago",
           "batteryPct":91,"lastSeenAt":"\(at(4))","position":{"lat":40.7644,"lon":-73.9730,"at":"\(at(4))"},
           "today":{"firstOut":null,"minutesOut":0,"distanceKm":0,"stops":[],"trail":[]}},
          {"subject":"kit","name":"Kit","self":false,"status":"unknown","line":"Last at The Reservoir · 2h ago",
           "batteryPct":null,"lastSeenAt":"\(at(130))","position":{"lat":40.7851,"lon":-73.9626,"at":"\(at(130))"},"today":null},
          {"subject":"pat","name":"Pat","self":false,"status":"off","line":"Not sharing their location.",
           "batteryPct":null,"lastSeenAt":null,"position":null,"today":null}
        ],"access":\(accessJSON)},"updated":"\(at(1))"}
        """
        do {
            return try JSONDecoder().decode(HouseholdViewResponse.self, from: Data(json.utf8))
        } catch {
            // A fixture that no longer decodes is a test failure, not a blank tab.
            fatalError("demo household view no longer decodes: \(error)")
        }
    }
}
#endif

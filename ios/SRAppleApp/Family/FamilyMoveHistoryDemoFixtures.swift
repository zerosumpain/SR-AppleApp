import Foundation

// MARK: - Demo move history
//
// `-SRDemo` answers for `/api/native/family/forecast/history?subject=&days=`.
// Synthetic throughout — the repository is public: the demo family's made-up
// places, a school run and a swimming lesson, drawn the same for any subject
// with the names changed, and dated from now so "last Mon" reads live.

extension SRDemoFixtures {
    static func familyMoveHistory(subject: String, days: Int, clock: DemoClock) -> String {
        let name = subject.prefix(1).uppercased() + subject.dropFirst()
        let window = [7, 28, 90].contains(days) ? days : 90
        // A school day: Home → School at 08:2x, School → Home at 15:4x; Tuesdays
        // and Thursdays Home → Pool at 17:30. Weekends one trip to the Park.
        var trips: [[String: Any]] = []
        for back in 0..<window {
            let day = clock.now.addingTimeInterval(-Double(back) * 86_400)
            let weekday = (Calendar(identifier: .gregorian).component(.weekday, from: day) + 5) % 7  // Mon = 0
            func at(_ hour: Int, _ minute: Int) -> Date {
                Calendar(identifier: .gregorian).date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            }
            let wobble = (back * 7) % 11
            func trip(_ from: String, _ to: String, _ start: Date, _ minutes: Double, _ mode: String) {
                guard start < clock.now else { return }
                trips.append(["from": from, "to": to, "start": clock.iso(start), "minutes": minutes, "mode": mode, "broken": false])
            }
            if weekday < 5 {
                trip("Home", "School", at(8, 18 + wobble), 14 + Double(wobble % 4), "active")
                trip("School", "Home", at(15, 40 + wobble % 6), 16 + Double(wobble % 5), "active")
                if weekday == 1 || weekday == 3 {
                    trip("Home", "Pool", at(17, 25 + wobble % 8), 11 + Double(wobble % 3), "vehicle")
                    trip("Pool", "Home", at(18, 40 + wobble % 9), 12 + Double(wobble % 3), "vehicle")
                }
            } else if back % 2 == 0 {
                trip("Home", "The Park", at(10, 30 + wobble), 22, "active")
                trip("The Park", "Home", at(12, 15 + wobble), 24, "active")
            }
        }
        trips.sort { ($0["start"] as? String ?? "") > ($1["start"] as? String ?? "") }
        var pattern = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        var arrivals: [String: Int] = [:]
        var minutes = 0.0
        for t in trips {
            if let iso = t["start"] as? String, let date = parseTimestamp(iso) {
                let weekday = (Calendar(identifier: .gregorian).component(.weekday, from: date) + 5) % 7
                pattern[weekday][Calendar(identifier: .gregorian).component(.hour, from: date)] += 1
            }
            arrivals[t["to"] as? String ?? "", default: 0] += 1
            minutes += t["minutes"] as? Double ?? 0
        }
        let places = arrivals.sorted { $0.value > $1.value }.map {
            ["name": $0.key, "trips": $0.value, "share": Double($0.value) / Double(max(1, trips.count))] as [String: Any]
        }
        func route(_ id: String, _ from: String, _ to: String, _ mode: String, _ median: Double, _ recent: Double, _ earlier: Double, _ departure: String) -> [String: Any] {
            let n = trips.filter { ($0["from"] as? String) == from && ($0["to"] as? String) == to }
            return ["id": id, "from": from, "to": to, "mode": mode, "trips": n.count, "median": median,
                    "low": median - 3, "high": median + 4, "departure": departure,
                    "recentMedian": recent, "earlierMedian": earlier, "lastAt": n.first?["start"] ?? NSNull()]
        }
        let weekdays = max(1, window * 5 / 7)
        let body: [String: Any] = [
            "subject": subject, "name": name, "days": window, "generatedAt": clock.iso(minutesAgo: 0),
            "totals": ["trips": trips.count, "places": arrivals.count, "minutes": minutes,
                       "perWeek": Double(trips.count) / (Double(window) / 7)],
            "places": places,
            "routes": [
                route("r-school", "Home", "School", "active", 15, 14, 16, "08:24"),
                route("r-back", "School", "Home", "active", 18, 18, 18, "15:43"),
                route("r-pool", "Home", "Pool", "vehicle", 12, 13, 11, "17:30"),
            ],
            "routines": [
                ["id": "r-school:weekday", "from": "Home", "to": "School", "dayType": "weekday", "departure": "08:24",
                 "window": [497, 510], "days": weekdays - 1, "of": weekdays,
                 "punctuality": ["early": 1, "onTime": max(0, weekdays - 4), "late": 2]],
                ["id": "r-pool:weekday", "from": "Home", "to": "Pool", "dayType": "weekday", "departure": "17:30",
                 "window": [1045, 1060], "days": max(1, window * 2 / 7 - 1), "of": weekdays,
                 "punctuality": ["early": 0, "onTime": max(1, window * 2 / 7 - 2), "late": 1]],
            ],
            "trips": Array(trips.prefix(150)),
            "pattern": pattern,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

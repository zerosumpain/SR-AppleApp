import Foundation

// MARK: - Demo walking figures
//
// `-SRDemo` answers for `/api/native/family/movement?subject=&days=`.
// Synthetic throughout — the repository is public: the demo family's made-up
// school run and park walks, the same for any subject with the name changed.

extension SRDemoFixtures {
    static func familyMovement(subject: String, days: Int, clock: DemoClock) -> String {
        let name = subject.prefix(1).uppercased() + subject.dropFirst()
        let window = days == 90 ? 90 : 30
        let scale = Double(window) / 30
        let calendar = Calendar(identifier: .gregorian)
        // Thirteen weeks of pace, getting a little brisker.
        let weekly: [[String: Any]] = (0..<min(13, window / 7)).reversed().map { back in
            let monday = clock.now.addingTimeInterval(-Double(back) * 7 * 86_400)
            let date = calendar.dateComponents([.year, .month, .day], from: monday)
            let label = String(format: "%04d-%02d-%02d", date.year ?? 2026, date.month ?? 1, date.day ?? 1)
            return ["weekStart": label, "medianMps": 1.28 + Double(12 - back) * 0.012, "n": 4 + back % 3]
        }
        let trip: (String, String, Int, String, Double, String, Double?, Double?, Double?) -> [String: Any] = {
            from, to, count, departure, median, mode, metres, fastest, pace in
            var t: [String: Any] = ["fromLabel": from, "toLabel": to, "count": count, "usualDeparture": departure,
                                    "medianSeconds": median, "totalSeconds": median * Double(count), "mode": mode,
                                    "lastAt": clock.iso(minutesAgo: 60 * 20)]
            if let metres { t["medianMetres"] = metres }
            if let fastest { t["fastestSeconds"] = fastest }
            if let pace { t["medianPaceSecPerKm"] = pace }
            return t
        }
        let body: [String: Any] = [
            "subject": subject, "name": name, "days": window,
            "stats": [
                "byMode": [
                    "foot": ["count": Int(44 * scale), "metres": 52_000 * scale, "seconds": 41_000 * scale],
                    "car": ["count": Int(9 * scale), "metres": 61_000 * scale, "seconds": 6_800 * scale],
                    "rail": ["count": 0, "metres": 0, "seconds": 0],
                    "other": ["count": Int(2 * scale), "metres": 9_000 * scale, "seconds": 2_400 * scale],
                ],
                "walkingPace": ["medianMps": 1.39, "p75Mps": 1.52, "n": Int(38 * scale), "weekly": weekly],
                "commonTrips": [
                    trip("Home", "School", Int(20 * scale), "08:24", 1_000, "foot", 1_320, 840, 755),
                    trip("School", "Home", Int(19 * scale), "15:43", 1_110, "foot", 1_340, 930, 820),
                    trip("Home", "The Park", Int(4 * scale), "10:35", 1_380, "foot", 1_850, 1_200, 745),
                    trip("Home", "Pool", Int(8 * scale), "17:30", 720, "car", 5_600, 600, nil),
                ],
                "roundTrips": ["count": Int(6 * scale), "medianSeconds": 1_900, "totalSeconds": 11_400 * scale],
                "timeOut": [] as [Any],
            ] as [String: Any],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

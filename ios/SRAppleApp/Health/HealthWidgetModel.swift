import Foundation

// "Health today" on the Home Screen and the Lock Screen: today's activity
// rings and steps, and — for the owner — the readiness score. What the app
// leaves on the Keychain shelf (`FamilyShelf`, account `.health`) and every
// rule about it as a pure function.
//
// SHARED with the widget extension (`SRAppleLive`, see watch.yml), so nothing
// here may reach for the app: no `ActivityRingsStore`, no `TodayHealth`.
// Foundation only, so the Linux harness runs its tests
// (`scripts/home-check.sh`).
//
// The extension never reads Apple Health and asks for no permission of its
// own. Everything here was read by the app, which already holds the grants
// (`ActivityRingsStore`, `LiveSteps`), or sent to it by the site
// (`/api/native/today`, the owner's alone). So the widget is as fresh as the
// app's last look; at midnight it stops showing yesterday's rings as today's.

// MARK: - What the shelf holds

/// One activity ring: Move, Exercise or Stand.
struct HealthWidgetRing: Codable, Equatable, Identifiable {
    /// "move", "exercise", "stand".
    var key: String
    var label: String
    var value: Double
    var goal: Double
    /// "kcal", "min" or "h".
    var unit: String

    var id: String { key }
    var fraction: Double { goal > 0 ? max(value, 0) / goal : 0 }
}

struct HealthWidgetSnapshot: Codable, Equatable {
    /// The local day the figures are for, `YYYY-MM-DD`.
    var day: String
    /// Outermost first, as they nest. Empty with no rings set up.
    var rings: [HealthWidgetRing]
    /// This phone's steps since midnight. Nil when unreadable.
    var steps: Int?
    /// The owner's readiness, 0…100, and its word ("Primed"). Nil for
    /// anybody else, and before it is in.
    var readiness: Int?
    var readinessLabel: String?
    var savedAt: Date

    func sameContent(as other: HealthWidgetSnapshot?) -> Bool {
        guard var other else { return false }
        other.savedAt = savedAt
        return other == self
    }
}

// MARK: - Rules

enum HealthWidget {
    /// `YYYY-MM-DD` on this phone's calendar.
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
    }

    /// The snapshot as it stands at `now`: today's figures, or — once the
    /// day has turned and the app has not been opened since — a fresh day
    /// with empty rings and no steps, never yesterday's passed off as today's.
    static func today(_ snapshot: HealthWidgetSnapshot?, now: Date, calendar: Calendar = .current) -> HealthWidgetSnapshot? {
        guard let snapshot else { return nil }
        let today = day(now, calendar: calendar)
        guard snapshot.day != today else { return snapshot }
        var fresh = snapshot
        fresh.day = today
        fresh.rings = snapshot.rings.map { var ring = $0; ring.value = 0; return ring }
        fresh.steps = nil
        fresh.readiness = nil
        fresh.readinessLabel = nil
        return fresh
    }

    /// Whether the figures on the shelf are from an earlier day.
    static func isCarriedOver(_ snapshot: HealthWidgetSnapshot, now: Date, calendar: Calendar = .current) -> Bool {
        snapshot.day != day(now, calendar: calendar)
    }

    /// Whether a new snapshot is worth a widget reload. The rings move with
    /// every Watch sync and the steps with every few paces; a reload for
    /// each would spend the widget's budget on numbers nobody could tell
    /// apart at a glance. A new day, a new readiness, a ring closing, a
    /// ring moving two points or the steps moving 250 are.
    static func worthReload(from old: HealthWidgetSnapshot?, to new: HealthWidgetSnapshot) -> Bool {
        guard let old else { return true }
        if old.day != new.day || old.readiness != new.readiness || old.readinessLabel != new.readinessLabel { return true }
        if old.rings.map(\.key) != new.rings.map(\.key) { return true }
        for (a, b) in zip(old.rings, new.rings) {
            if (a.fraction >= 1) != (b.fraction >= 1) { return true }
            if abs(percent(a) - percent(b)) >= 2 { return true }
            if a.goal != b.goal { return true }
        }
        switch (old.steps, new.steps) {
        case (nil, nil): return false
        case let (a?, b?): return abs(a - b) >= 250
        default: return true
        }
    }

    /// 0…, rounded: a ring past its goal reads past 100.
    static func percent(_ ring: HealthWidgetRing) -> Int { Int((ring.fraction * 100).rounded()) }

    /// "412/600 kcal", "22/30 min", "9/12 h".
    static func figure(_ ring: HealthWidgetRing) -> String {
        "\(Int(ring.value.rounded()))/\(Int(ring.goal.rounded())) \(ring.unit)"
    }

    /// "9,120".
    static func steps(_ count: Int) -> String {
        let out = NumberFormatter()
        out.locale = Locale(identifier: "en_GB")
        out.numberStyle = .decimal
        return out.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    /// What sits inside the rings: the owner's readiness, else the Move
    /// ring's percentage, else a dash.
    static func centre(_ s: HealthWidgetSnapshot) -> (figure: String, word: String) {
        if let readiness = s.readiness { return ("\(readiness)", s.readinessLabel ?? "Ready") }
        if let move = s.rings.first(where: { $0.key == "move" }) { return ("\(percent(move))%", "Move") }
        if let steps = s.steps { return (compact(steps), "steps") }
        return ("—", "Today")
    }

    /// "9.1k", "640" — steps where a ring's centre has room for four characters.
    static func compact(_ count: Int) -> String {
        guard count >= 1000 else { return "\(max(count, 0))" }
        let thousands = Double(count) / 1000
        return thousands < 10 ? String(format: "%.1fk", thousands) : "\(Int(thousands))k"
    }

    /// The Lock Screen's line: "Move 69% · Exercise 73% · Stand 9/12".
    static func ringsLine(_ s: HealthWidgetSnapshot) -> String? {
        let parts = s.rings.map { ring -> String in
            ring.key == "stand" ? "\(ring.label) \(Int(ring.value.rounded()))/\(Int(ring.goal.rounded()))" : "\(ring.label) \(percent(ring))%"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Read out: "Readiness 72, Primed. Move 69 percent, 412 of 600 kcal.
    /// 9,120 steps."
    static func spoken(_ s: HealthWidgetSnapshot) -> String {
        var parts: [String] = []
        if let readiness = s.readiness { parts.append("Readiness \(readiness)" + (s.readinessLabel.map { ", \($0)" } ?? "")) }
        for ring in s.rings {
            parts.append("\(ring.label) \(percent(ring)) percent, \(Int(ring.value.rounded())) of \(Int(ring.goal.rounded())) \(ring.unit)")
        }
        if let steps = s.steps { parts.append("\(self.steps(steps)) steps") }
        return parts.isEmpty ? "Nothing in yet today" : parts.joined(separator: ". ")
    }

    /// The next midnight on this phone's calendar: where the widget's
    /// timeline turns to a new day.
    static func nextMidnight(after now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
    }
}

// MARK: - Samples

/// A made-up day for the widget's placeholder and the gallery.
enum HealthWidgetSamples {
    static func snapshot(now: Date = Date(), readiness: Bool = true) -> HealthWidgetSnapshot {
        HealthWidgetSnapshot(
            day: HealthWidget.day(now),
            rings: [
                HealthWidgetRing(key: "move", label: "Move", value: 412, goal: 600, unit: "kcal"),
                HealthWidgetRing(key: "exercise", label: "Exercise", value: 22, goal: 30, unit: "min"),
                HealthWidgetRing(key: "stand", label: "Stand", value: 9, goal: 12, unit: "h"),
            ],
            steps: 9_120,
            readiness: readiness ? 72 : nil,
            readinessLabel: readiness ? "Primed" : nil,
            savedAt: now
        )
    }
}

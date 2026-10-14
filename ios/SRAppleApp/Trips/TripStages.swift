import Foundation

/// v4: every day in four stages — breakfast & morning, lunch, afternoon,
/// dinner & evening (SR-Main `DayStage`, `DAY_STAGE_LABEL`). The solver sets
/// `PlannedStop.stage` on every stop; a stop without one (an older plan)
/// gets the same answer from the solver's own `stageOf`, ported in
/// `TripReplan` (stages.ts).
///
/// Foundation only: the Linux harness compiles it.
enum DayStage: String, CaseIterable, Hashable {
    case morning, lunch, afternoon, evening

    /// `DAY_STAGE_LABEL`.
    var label: String {
        switch self {
        case .morning: return "Breakfast & morning"
        case .lunch: return "Lunch"
        case .afternoon: return "Afternoon"
        case .evening: return "Dinner & evening"
        }
    }
}

enum TripStages {
    /// Each stop's stage, in order: the solver's own where every stop has
    /// one, else `stageOf` for the whole day (it never goes backwards, so a
    /// day is judged as a whole, not stop by stop).
    static func stages(_ day: PlannedDay, wishes: [TripWish]) -> [DayStage] {
        let given = day.stops.compactMap { $0.stage.flatMap(DayStage.init(rawValue:)) }
        if given.count == day.stops.count { return given }
        var replaces: [String: String] = [:]
        for w in wishes { if let meal = w.replacesMeal, !meal.isEmpty { replaces[w.id] = meal } }
        return TripReplan.stageOf(day.stops) { TripReplan.mealOfStop($0, replaces) }
    }

    struct Group: Hashable {
        let stage: DayStage
        /// The stops' indexes in the day.
        let indexes: [Int]
    }

    /// The day's stops grouped by stage, in stage order. Empty stages are
    /// kept, so a day reads as four parts.
    static func groups(_ day: PlannedDay, wishes: [TripWish]) -> [Group] {
        let each = stages(day, wishes: wishes)
        return DayStage.allCases.map { stage in
            Group(stage: stage, indexes: each.indices.filter { each[$0] == stage })
        }
    }

    /// "Colosseum, Pantheon" — what a stage holds, said briefly. The day's
    /// opening and closing stays are left out; a meal says itself.
    static func brief(_ day: PlannedDay, _ indexes: [Int]) -> String {
        let names = indexes.map { day.stops[$0] }
            .filter { !($0.kind == .stay && ($0.id.hasSuffix(":start") || $0.id.hasSuffix(":end"))) }
            .map(\.title)
        if names.isEmpty { return "Free" }
        return names.count <= 2 ? names.joined(separator: ", ") : "\(names[0]), \(names[1]) +\(names.count - 2)"
    }
}

/// v5: how full a day is — active (non-meal, non-free) minutes against the
/// day's capacity. The server sends it (`bundle.fullness`); a day it has not
/// covered (an older server, a day re-planned on the phone) gets the same
/// measure worked out here.
enum TripFullness {
    /// The bands, as the server draws them.
    static func band(_ pct: Double) -> String {
        switch pct {
        case ..<10: return "empty"
        case ..<50: return "light"
        case ..<85: return "balanced"
        case ...100: return "full"
        default: return "overfull"
        }
    }

    static func word(_ band: String) -> String {
        switch band {
        case "empty": return "free"
        case "light": return "light"
        case "balanced": return "balanced"
        case "full": return "full"
        case "overfull": return "too full"
        default: return band
        }
    }

    static func of(_ day: PlannedDay, bundle: TripBundle) -> DayFullness {
        // A day the phone re-planned is measured afresh; otherwise the server's.
        if bundle.day(day.date) == day, let given = bundle.fullness?[day.date] { return given }
        let rules = TripReplan.solverRules(bundle.trip.pace)
        let frame = TripReplan.dayFrame(rules, bundle.trip.dayLoads ?? [:], day.date, nil)
        let lunchMin = rules.lunch.durationSec / 60
        let capacity = max(1, (frame.activeEndMin ?? frame.dayEndMin) - frame.dayStartMin - lunchMin)
        let replacing = Set(bundle.wishes.filter { ($0.replacesMeal ?? "").isEmpty == false }.map(\.id))
        let active = day.stops
            .filter { $0.kind == .wish && !replacing.contains($0.wishId ?? "") }
            .reduce(0.0) { $0 + max(0, $1.departMin - $1.arriveMin - $1.waitSec / 60) }
        let pct = (active / capacity * 100).rounded()
        return DayFullness(activeMin: active, capacityMin: capacity, pct: pct, band: band(pct))
    }
}

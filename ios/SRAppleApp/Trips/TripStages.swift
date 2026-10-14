import Foundation

/// v4: every day in four stages — breakfast & morning, lunch, afternoon,
/// dinner & evening (SR-Main `DayStage`, `DAY_STAGE_LABEL`). The solver sets
/// `PlannedStop.stage`; a stop without one (an older server, a day re-timed
/// before the port caught up) gets the same answer from `stageOf` here.
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
    /// Where the afternoon ends when the day has no dinner.
    static let eveningFromMin = 18.0 * 60

    /// Each stop's stage, in order. The solver's own `stage` wins; the rest
    /// follow the spec's rule: morning = day start → lunch; lunch = the lunch
    /// meal (or the wish that replaces it); afternoon = after lunch → dinner
    /// (or 18:00); evening = dinner and after. Travel belongs to the stage
    /// it falls in.
    ///
    /// Provisional until the solver's `stageOf` is ported; same rule.
    static func stages(_ day: PlannedDay, wishes: [TripWish]) -> [DayStage] {
        func replaces(_ stop: PlannedStop, _ meal: String) -> Bool {
            if stop.kind == .meal { return stop.id.hasSuffix(":\(meal)") }
            guard let id = stop.wishId else { return false }
            return wishes.first { $0.id == id }?.replacesMeal == meal
        }
        let lunch = day.stops.firstIndex { replaces($0, "lunch") }
        let dinner = day.stops.firstIndex { replaces($0, "dinner") }
        return day.stops.enumerated().map { i, stop in
            if let given = stop.stage.flatMap(DayStage.init(rawValue:)) { return given }
            if i == lunch { return .lunch }
            if let dinner, i >= dinner { return .evening }
            if let lunch {
                if i < lunch { return .morning }
                return dinner == nil && stop.arriveMin >= eveningFromMin ? .evening : .afternoon
            }
            if stop.arriveMin < 12 * 60 { return .morning }
            if let dinner, i < dinner { return .afternoon }
            return stop.arriveMin < eveningFromMin ? .afternoon : .evening
        }
    }

    /// The day's stops grouped by stage, in stage order, with each stop's
    /// index in the day. Empty stages are kept, so a day reads as four parts.
    struct Group: Hashable {
        let stage: DayStage
        /// The stops' indexes in the day.
        let indexes: [Int]
    }

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

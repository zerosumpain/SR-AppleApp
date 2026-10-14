import Foundation

// Re-timing and re-planning the rest of a trip day ON THE PHONE, with no
// signal: a Swift port of SR-Main's solver (`src/lib/trips/solver/`,
// branch feat/trips-solver, c1100734) — `retimeDay` and `replanDay` and exactly the
// parts of `timing.ts`, `items.ts`, `matrix.ts`, `order.ts`, `hours.ts`,
// `estimate.ts` and `calendar.ts` they use. `solveTrip` (whole-trip planning)
// stays on the server.
//
// The port is deliberately literal: same function names, same order of
// operations, same tie-breaks. The two must give the same answer to the
// minute, and `TripReplanTests` replays the solver's shared JSON cases
// (`SRAppleAppTests/Fixtures/TripCases/*.json`) to prove it. Three places
// where Swift and JavaScript differ by default are handled explicitly:
//
//   * `Math.round` rounds .5 UP (towards +∞); Swift's `.rounded()` rounds
//     away from zero. `js.round` is JavaScript's.
//   * `Array.prototype.sort` is stable; Swift's `sort` is not promised to
//     be. `js.sorted` is stable.
//   * Ties between ids break on plain UTF-16 code-unit order (the solver's
//     `cmp`), which Swift's `String <` is not: `js.compare` is that order.
//
// Foundation only: the Linux harness compiles this with the models.

enum TripReplan {

    // MARK: Inputs

    /// Everything but the day: `RetimeInput` in the solver.
    struct Context {
        var trip: Trip
        var stays: [TripStay]
        var wishes: [TripWish]
        var bookings: [TripBooking]
        var matrix: TravelMatrix
    }

    /// `ReplanInput`.
    struct Input {
        var context: Context
        var day: PlannedDay
        var nowMin: Double
        var position: TripLatLng?
        var atStopId: String?
        var doneStopIds: [String]
    }

    // MARK: retimeDay

    /// Keeps stops before `fromIndex` as they are and re-times the rest in
    /// the same order, setting off towards `stops[fromIndex]` at `startMin`
    /// (0 = leave the stay then). Nothing is dropped or reordered.
    static func retimeDay(_ day: PlannedDay, fromIndex: Int, startMin: Double, context input: Context) -> PlannedDay {
        if day.stops.isEmpty {
            return PlannedDay(date: day.date, stayId: day.stayId, stops: [], legs: [], warnings: day.warnings)
        }
        let ctx = SolverContext(input.trip, input.stays, input.wishes, input.matrix)
        let frame = frameFor(ctx, day, input.stays)
        let body = day.stops.filter { !isEndStay($0) }
        let i = max(0, min(fromIndex, body.count))
        var start: SimStart
        var rest: [PlannedStop]
        if i == 0, body.first?.kind == .stay, frame.stay != nil {
            start = freshStart(frame, atMin: startMin, leaveEarlyForSlot: false)
            rest = Array(body.dropFirst())
        } else if i == 0 {
            start = SimStart(prefixStops: [], prefixLegs: [], fromPoint: nil, fromStopId: nil, departMin: startMin)
            rest = body
        } else {
            start = startAfter(Array(body.prefix(i)), day, departMin: startMin)
            rest = Array(body.suffix(from: i))
        }
        let sim = simulate(ctx, frame, start, toItems(rest, day, input.wishes, input.bookings, ctx))
        return toPlannedDay(frame, sim)
    }

    // MARK: replanDay

    /// Up to three ways to carry on from now, best first: shift, drop nices,
    /// swap or reorder. Identical days are offered once.
    /// Where the person is in today's plan, as the re-planners see it
    /// (`situation` in replan.ts).
    struct Situation {
        var ctx: SolverContext
        var frame: DayFrame
        var done: Set<String>
        var prefix: [PlannedStop]
        var pending: [PlannedStop]
        var at: Int
        var leave: Double
        var start: SimStart
        /// Pending stops as items: missed slots removed, locked stops held.
        var items: [Item]
        var missed: [Item]
        var missedWarnings: [String]
        var missedIds: [String]
        var oldEnd: Double

        /// Earliest arrival at an item going straight there from `start`.
        func direct(_ item: Item) -> Double {
            guard let point = item.point else { return leave }
            if let position = start.fromPosition {
                return leave + js.ceil(legFromPosition(ctx, position, point).durationSec / 60)
            }
            guard let from = start.fromPoint else { return leave }
            return leave + js.ceil(chooseLeg(ctx, from, point).durationSec / 60)
        }
    }

    static func situation(_ input: Input) -> Situation {
        let day = input.day
        let c = input.context
        let ctx = SolverContext(c.trip, c.stays, c.wishes, c.matrix)
        let frame = frameFor(ctx, day, c.stays)
        let done = Set(input.doneStopIds)
        let body = day.stops.filter { !isEndStay($0) }
        let oldEnd = day.stops.last?.departMin ?? 0

        // Where we are in the day.
        let at = input.atStopId.flatMap { id in body.firstIndex { $0.id == id } } ?? -1
        var h = at
        if at < 0 {
            h = body.first?.kind == .stay ? 0 : -1
            while h + 1 < body.count && done.contains(body[h + 1].id) { h += 1 }
        }
        var prefix = Array(body.prefix(h + 1))
        let pending = Array(body.suffix(from: h + 1).filter { !done.contains($0.id) && $0.kind != .stay })
        let stillThere = !prefix.isEmpty && (at >= 0 || prefix[prefix.count - 1].kind == .stay)
        // Still at a stop (or the stay): set off once the visit and its
        // buffer are over, or now if that has passed.
        let bufferMin = prefix.last?.kind == .wish ? js.round(ctx.rules.bufferSec / 60) : 0
        let leave = stillThere ? max(input.nowMin, prefix[prefix.count - 1].departMin + bufferMin) : input.nowMin
        if stillThere && input.nowMin > prefix[prefix.count - 1].departMin {
            prefix[prefix.count - 1].departMin = input.nowMin
        }

        var start = startAfter(prefix, day, departMin: leave)
        if let position = input.position, at < 0 { start.fromPosition = position }
        let all = toItems(pending, day, c.wishes, c.bookings, ctx)

        var sit = Situation(
            ctx: ctx, frame: frame, done: done, prefix: prefix, pending: pending, at: at, leave: leave,
            start: start, items: [], missed: [], missedWarnings: [], missedIds: [], oldEnd: oldEnd
        )
        // Missed slots: a locked stop we cannot reach within the grace even
        // going straight there leaves today's plan, is listed in every
        // option's `dropped`, and every option's day carries a warning.
        let missed = all.filter { i in
            guard i.locked, let fixed = i.fixedStartMin else { return false }
            return sit.direct(i) > fixed + missedSlotGraceMin
        }
        let missedSerials = Set(missed.map(\.serial))
        sit.items = all.filter { !missedSerials.contains($0.serial) }.map { i in
            guard i.locked, let planned = pending.first(where: { $0.id == i.id }) else { return i }
            var held = i
            held.heldArriveMin = planned.arriveMin
            return held
        }
        sit.missed = missed
        sit.missedWarnings = missed.map { "Missed your \(fmtMin($0.fixedStartMin ?? 0)) \($0.title) slot" }
        sit.missedIds = missed.map { $0.wishId ?? $0.id }
        return sit
    }

    /// Make a sequence work without reordering it: drop the nices squeezing a
    /// slot, then any closed on arrival, then the lowest value — but only
    /// while a drop buys more than the nice is worth.
    static func settle(_ ctx: SolverContext, _ frame: DayFrame, _ start: SimStart, _ seq: [Item])
        -> (seq: [Item], sim: Simulation, gone: [Item], moved: [(Item, Item)]) {
        let first = repair(ctx, frame, start, seq, dropFirst: true)
        var current = first.seq
        var sim = first.sim
        var gone = first.dropped
        var moved = first.moved
        while hasProblems(sim) {
            let candidates = current.filter(droppable)
            if candidates.isEmpty { break }
            let closed = js.sorted(candidates.filter { cand in
                sim.issues.contains { $0.itemId == cand.id && $0.kind == .closed }
            }, by: byLowestValue)
            guard let victim = closed.first ?? js.sorted(candidates, by: byLowestValue).first else { break }
            let next = repair(ctx, frame, start, current.filter { $0.serial != victim.serial }, dropFirst: true)
            if next.sim.cost + Cost.droppedNice * Double(next.dropped.count + 1) >= sim.cost { break }
            gone.append(victim)
            current = next.seq
            sim = next.sim
            gone += next.dropped
            moved = next.moved
        }
        return (current, sim, gone, moved)
    }

    static func replanDay(_ input: Input) -> [ReplanOption] {
        let sit = situation(input)
        let ctx = sit.ctx, frame = sit.frame, pending = sit.pending, begin = sit.start, items = sit.items
        let missed = sit.missed, missedWarnings = sit.missedWarnings, missedIds = sit.missedIds, oldEnd = sit.oldEnd
        func direct(_ item: Item) -> Double { sit.direct(item) }

        struct Scored { var option: ReplanOption; var score: Double }
        var options: [Scored] = []
        func make(_ id: String, _ kind: ReplanOption.Kind, _ label: String, _ sim: Simulation, _ dropped: [String]) {
            var planned = toPlannedDay(frame, sim)
            planned.warnings = missedWarnings + planned.warnings
            let end = planned.stops.last?.departMin ?? 0
            options.append(Scored(
                option: ReplanOption(id: id, label: label, kind: kind, day: planned, dropped: missedIds + dropped, endsLaterMin: end - oldEnd),
                score: sim.cost + Double(dropped.count) * Cost.droppedNice
            ))
        }
        func repairSeq(_ seq: [Item], _ dropFirst: Bool) -> Repaired {
            repair(ctx, frame, begin, seq, dropFirst: dropFirst)
        }
        func movedNote(_ moved: [(Item, Item)]) -> String {
            guard !moved.isEmpty else { return "" }
            var anchors: [String] = []
            for (_, anchor) in moved where !anchors.contains(anchor.title) { anchors.append(anchor.title) }
            let names = moved.map { $0.0.kind == .meal ? $0.0.title.lowercased() : $0.0.title }
            return ", \(joinNames(names)) after the \(joinNames(anchors)) slot"
        }

        // 1. Shift: same order, re-timed from now; whatever no longer fits
        // before a slot moves to just after it.
        let shift = repairSeq(items, false)
        let firstFree = pending.first { p in !p.locked && shift.sim.stops.contains { $0.id == p.id } }
        let firstNew = firstFree.flatMap { p in shift.sim.stops.first { $0.id == p.id } }
        let delay: Double = {
            guard let p = firstFree, let n = firstNew else { return 0 }
            return n.arriveMin - p.arriveMin
        }()
        let lateSlot = items.first { i in
            i.locked && shift.sim.issues.contains { $0.itemId == i.id && $0.kind == .lateForSlot }
        }
        let shiftLabel: String
        if !missed.isEmpty {
            shiftLabel = "Carry on without the missed \(joinNames(missed.map(\.title))) slot"
        } else if let late = lateSlot {
            shiftLabel = "Go straight to the \(late.title) — about \(js.num(direct(late) - (late.fixedStartMin ?? 0))) min late"
        } else if delay > 0 {
            shiftLabel = "Push \(items.contains { $0.locked } ? "the rest" : "everything") back \(js.num(delay)) min"
        } else if delay < 0 {
            shiftLabel = "Bring everything forward \(js.num(-delay)) min"
        } else {
            shiftLabel = "Keep the plan as it is"
        }
        make("shift", .shift, shiftLabel + movedNote(shift.moved), shift.sim, [])

        // 2. Drop nices until the day works: those squeezing a slot first,
        // then any closed on arrival, then the lowest value.
        if hasProblems(shift.sim) || !shift.moved.isEmpty {
            let settled = settle(ctx, frame, begin, items)
            let sim = settled.sim, gone = settled.gone, moved = settled.moved
            if !gone.isEmpty {
                let names = gone.map(\.title)
                make(
                    "drop:" + gone.map(\.id).joined(separator: ","), .drop,
                    "Drop \(joinNames(names)) (nice-to-have\(names.count > 1 ? "s" : ""))\(movedNote(moved))",
                    sim, gone.map { $0.wishId ?? $0.id }
                )
            }
        }

        // 3. Re-order what is left (meals re-slotted, locked stops stay put).
        let wishItems = items.filter { $0.kind == .wish }
        let meals = items.filter { $0.kind == .meal }
        if wishItems.count > 1 {
            let cost: SequenceCost = { seq in withMeals(ctx, frame, begin, seq, meals).sim.cost }
            let ordered = orderDay(wishItems, cost)
            let placed = withMeals(ctx, frame, begin, ordered, meals).seq
            let repaired = repairSeq(placed, false)
            let seq = repaired.seq, sim = repaired.sim
            let before = wishItems.map(\.id)
            let after = seq.filter { $0.kind == .wish }.map(\.id)
            let sameSequence = shift.seq.map(\.id).joined(separator: "|") == seq.map(\.id).joined(separator: "|")
            if sim.cost < shift.sim.cost && !sameSequence {
                let swapped = before.count >= 2 && after.count >= 2 && before[0] == after[1] && before[1] == after[0]
                    && before.dropFirst(2).joined(separator: "|") == after.dropFirst(2).joined(separator: "|")
                if swapped {
                    make("swap", .swap, "Swap the next two", sim, [])
                } else if before.joined(separator: "|") == after.joined(separator: "|") {
                    let movedMeals = sim.stops.filter { s in s.kind == .meal && meals.contains { $0.id == s.id } }
                    let label = movedMeals.isEmpty
                        ? "Reorder the rest of the day"
                        : "Move " + joinNames(movedMeals.map { "\($0.title.lowercased()) to \(fmtMin($0.arriveMin + js.round($0.waitSec / 60)))" })
                    make("reorder", .reorder, label, sim, [])
                } else {
                    make("reorder", .reorder, "Reorder the rest of the day", sim, [])
                }
            }
        }

        let ranked = js.sorted(options) { a, b in
            js.cmp(a.score, b.score) ?? js.cmp(Double(kindRank(a.option.kind)), Double(kindRank(b.option.kind)))
                ?? js.compare(a.option.id, b.option.id)
        }
        var seen = Set<String>()
        var out: [ReplanOption] = []
        for o in ranked {
            let key = dayKey(o.option.day)
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(o.option)
            if out.count == 3 { break }
        }
        return out
    }

    /// A booked/locked stop more than this late is a missed slot.
    static let missedSlotGraceMin = 30.0

    struct Repaired {
        var seq: [Item]
        var sim: Simulation
        var dropped: [Item]
        /// (moved stop, the locked stop it now follows).
        var moved: [(Item, Item)]
    }

    /// Make a sequence respect its locked stops: while one would be late
    /// because of unlocked stops since the previous locked stop, drop the
    /// lowest-value nice among them (`dropFirst`) or move the last sight to
    /// just after it. Late with nothing before it to remove, it stays.
    static func repair(_ ctx: SolverContext, _ frame: DayFrame, _ start: SimStart, _ seq: [Item], dropFirst: Bool) -> Repaired {
        var current = seq
        var dropped: [Item] = []
        var moved: [(Item, Item)] = []
        for _ in 0..<(4 * seq.count + 4) {
            let sim = simulate(ctx, frame, start, current)
            var fixed = false
            var prevLocked = -1
            for k in current.indices {
                let item = current[k]
                if !item.locked { continue }
                let late = sim.issues.contains { $0.itemId == item.id && $0.kind == .lateForSlot }
                let between = current[(prevLocked + 1)..<k].filter { !$0.locked }
                if late && !between.isEmpty {
                    let nice = dropFirst ? js.sorted(between.filter(droppable), by: byLowestValue).first : nil
                    if let nice {
                        current = current.filter { $0.serial != nice.serial }
                        dropped.append(nice)
                    } else {
                        // Move the last sight rather than a meal: a meal after
                        // the slot would only run late.
                        let sights = between.filter { $0.kind == .wish }
                        let pool = sights.isEmpty ? Array(between) : sights
                        let mover = pool[pool.count - 1]
                        var rest = current.filter { $0.serial != mover.serial }
                        let at = rest.firstIndex { $0.serial == item.serial } ?? (rest.count - 1)
                        rest.insert(mover, at: at + 1)
                        current = rest
                        moved.append((mover, item))
                    }
                    fixed = true
                    break
                }
                prevLocked = k
            }
            if !fixed { return Repaired(seq: current, sim: sim, dropped: dropped, moved: moved) }
        }
        return Repaired(seq: current, sim: simulate(ctx, frame, start, current), dropped: dropped, moved: moved)
    }

    private static func kindRank(_ kind: ReplanOption.Kind) -> Int {
        switch kind {
        case .shift: return 0
        case .swap: return 1
        case .reorder: return 2
        case .drop: return 3
        }
    }

    private static func dayKey(_ day: PlannedDay) -> String {
        day.stops.map { "\($0.id)@\(js.num($0.arriveMin))-\(js.num($0.departMin))" }.joined(separator: "|")
    }

    static func joinNames(_ names: [String]) -> String {
        if names.count <= 1 { return names.joined() }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    private static func isEndStay(_ s: PlannedStop) -> Bool { s.kind == .stay && s.id.hasSuffix(":end") }

    /// Problems dropping a nice can fix (lateness for a slot is `repair`'s job).
    private static func hasProblems(_ sim: Simulation) -> Bool {
        sim.overrunMin > 0 || sim.issues.contains { $0.kind != .lateForSlot }
    }

    // MARK: - replan.ts helpers

    struct DayFrame {
        var date: String
        var stay: TripStay?
        var dayStartMin: Double
        var dayEndMin: Double
        /// v2.1: "light", "normal" or "full".
        var load: String = "normal"
    }

    /// A light day ends this much earlier than the pace's day end.
    static let lightDayEarlierMin = 90.0

    /// The frame for a date under the pace and that date's load (items.ts).
    static func dayFrame(_ rules: TripPaceRules, _ dayLoads: [String: String], _ date: String, _ stay: TripStay?) -> DayFrame {
        let raw = dayLoads[date] ?? "normal"
        let load = ["light", "normal", "full"].contains(raw) ? raw : "normal"
        return DayFrame(
            date: date, stay: stay, dayStartMin: rules.dayStartMin,
            dayEndMin: load == "light" ? rules.dayEndMin - lightDayEarlierMin : rules.dayEndMin, load: load
        )
    }

    static func frameFor(_ ctx: SolverContext, _ day: PlannedDay, _ stays: [TripStay]) -> DayFrame {
        dayFrame(ctx.rules, ctx.dayLoads, day.date, stays.first { $0.id == day.stayId })
    }

    /// The matrix point we are at after a run of stops (meals sit where the stop before was).
    static func pointAfter(_ prefix: [PlannedStop], _ stayId: String?) -> String? {
        for stop in prefix.reversed() {
            if let p = pointOfStop(stop, stayId) { return p }
        }
        return nil
    }

    static func startAfter(_ prefix: [PlannedStop], _ day: PlannedDay, departMin: Double) -> SimStart {
        SimStart(
            prefixStops: prefix,
            prefixLegs: Array(day.legs.prefix(max(0, prefix.count - 1))),
            fromPoint: pointAfter(prefix, day.stayId),
            fromStopId: prefix.last?.id,
            departMin: departMin
        )
    }

    static func toItems(_ stops: [PlannedStop], _ day: PlannedDay, _ wishes: [TripWish], _ bookings: [TripBooking], _ ctx: SolverContext) -> [Item] {
        var byId: [String: TripWish] = [:]
        for w in wishes { byId[w.id] = w }
        return stops.filter { $0.kind != .stay }.map { itemFromStop($0, day.date, byId, bookings, ctx.rules) }
    }

    // MARK: - calendar.ts

    static func dayNumber(_ date: String) -> Int? {
        let p = date.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        let (yy, m, d) = (p[0], p[1], p[2])
        let y = m <= 2 ? yy - 1 : yy
        let era = js.floorDiv(y, 400)
        let yoe = y - era * 400
        let doy = js.floorDiv(153 * (m + (m > 2 ? -3 : 9)) + 2, 5) + d - 1
        let doe = yoe * 365 + js.floorDiv(yoe, 4) - js.floorDiv(yoe, 100) + doy
        return era * 146097 + doe - 719468
    }

    /// 1 = Monday … 7 = Sunday.
    static func isoWeekday(_ date: String) -> Int? {
        guard let n = dayNumber(date) else { return nil }
        return (((n + 3) % 7) + 7) % 7 + 1
    }

    /// "Tue 27 Oct".
    static func dayLabel(_ date: String) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let p = date.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]), let w = isoWeekday(date) else { return date }
        return "\(weekdays[w - 1]) \(p[2]) \(months[p[1] - 1])"
    }

    /// "HH:MM", wrapping past midnight.
    static func fmtMin(_ min: Double) -> String {
        let r = Int(js.round(min))
        let m = ((r % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    // MARK: - estimate.ts

    static let networkFactor = 1.3
    static let transitOverheadSec = 15.0 * 60
    static func kmh(_ mode: TravelMode) -> Double {
        switch mode {
        case .walk: return 4.8
        case .cycle: return 15
        case .transit: return 18
        case .drive, .taxi, .unknown: return 20
        }
    }

    static func haversineM(_ a: TripLatLng, _ b: TripLatLng) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.lat - a.lat) * rad
        let dLng = (b.lng - a.lng) * rad
        let h = pow(sin(dLat / 2), 2) + cos(a.lat * rad) * cos(b.lat * rad) * pow(sin(dLng / 2), 2)
        return 2 * 6371008.8 * asin(min(1, h.squareRoot()))
    }

    static func estimateLeg(_ a: TripLatLng, _ b: TripLatLng, _ mode: TravelMode) -> (seconds: Double, metres: Double) {
        let metres = js.round(haversineM(a, b) * networkFactor)
        if metres == 0 { return (0, 0) }
        let travel = metres / ((kmh(mode) * 1000) / 3600)
        let overhead = mode == .transit ? transitOverheadSec : mode == .taxi ? TravelMode.taxiPickupSec : 0
        return (js.round(travel + overhead), metres)
    }

    // MARK: - hours.ts (the read side: `windowsOn`)

    /// Open windows on a date: [] closed, nil unknown.
    static func windowsOn(_ facts: TripFacts?, _ date: String) -> [TripOpenRange]? {
        guard let facts else { return nil }
        if facts.closedDates.contains(date) { return [] }
        guard let hours = facts.hours ?? TripHours.parse(facts.openingHoursText),
              let weekday = isoWeekday(date) else { return nil }
        return hours[String(weekday)]
    }

    // MARK: - matrix.ts

    struct LegChoice: Equatable {
        var mode: TravelMode
        var durationSec: Double
        var distanceM: Double?
        var estimated: Bool
    }

    static func stayPoint(_ stayId: String) -> String { "stay:\(stayId)" }

    final class SolverContext {
        let rules: TripPaceRules
        /// Allowed modes, walk always, canonical order (walk, cycle, drive, transit).
        let modes: [TravelMode]
        let matrix: TravelMatrix
        let index: [String: Int]
        let locations: [String: TripLatLng]
        var cache: [String: LegChoice] = [:]
        /// v2.1: per-date load; missing = normal.
        let dayLoads: [String: String]

        init(_ trip: Trip, _ stays: [TripStay], _ wishes: [TripWish], _ matrix: TravelMatrix) {
            var index: [String: Int] = [:]
            for (i, p) in matrix.points.enumerated() where index[p] == nil { index[p] = i }
            var locations: [String: TripLatLng] = [:]
            for s in stays { locations[stayPoint(s.id)] = s.location }
            for w in wishes { if let place = w.place { locations[w.id] = place.location } }
            rules = TripPaceRules.of(trip.pace)
            modes = TravelMode.canonical.filter { $0 == .walk || trip.modes.contains($0) }
            self.matrix = matrix
            self.index = index
            self.locations = locations
            dayLoads = trip.dayLoads ?? [:]
        }
    }

    private static func cell(_ table: [String: [[Double?]]], _ mode: TravelMode, _ i: Int, _ j: Int) -> Double? {
        guard let rows = table[mode.rawValue], i < rows.count, j < rows[i].count, let v = rows[i][j], v.isFinite else { return nil }
        return v
    }

    /// Taxi time from a drive time: the drive plus the wait for pick-up.
    static func taxiSec(_ driveSec: Double) -> Double { driveSec + TravelMode.taxiPickupSec }

    /// One mode between matrix indices. Taxi is derived from the drive row
    /// (a matrix never has taxi rows); nil = no route.
    static func modeSeconds(_ matrix: TravelMatrix, _ mode: TravelMode, _ i: Int, _ j: Int) -> (seconds: Double, metres: Double?, estimated: Bool)? {
        let row: TravelMode = mode == .taxi ? .drive : mode
        guard let sec = cell(matrix.seconds, row, i, j) else { return nil }
        return (mode == .taxi ? taxiSec(sec) : sec, cell(matrix.metres, row, i, j), matrix.estimated[row.rawValue] ?? false)
    }

    /// Walk when the walk is within the pace's limit, else the fastest
    /// allowed mode with a route, else an estimated walk.
    static func chooseLeg(_ ctx: SolverContext, _ from: String, _ to: String) -> LegChoice {
        if from == to { return LegChoice(mode: .walk, durationSec: 0, distanceM: 0, estimated: false) }
        let key = "\(from)\u{0}\(to)"
        if let hit = ctx.cache[key] { return hit }
        var choice: LegChoice?
        if let i = ctx.index[from], let j = ctx.index[to] {
            func of(_ mode: TravelMode) -> LegChoice? {
                guard let m = modeSeconds(ctx.matrix, mode, i, j) else { return nil }
                return LegChoice(mode: mode, durationSec: m.seconds, distanceM: m.metres, estimated: m.estimated)
            }
            if let walk = of(.walk), walk.durationSec <= ctx.rules.walkLimitSec {
                choice = walk
            } else {
                for mode in ctx.modes {
                    if let c = of(mode), choice == nil || c.durationSec < choice!.durationSec { choice = c }
                }
            }
        }
        let result = choice ?? estimatedWalk(ctx.locations[from], ctx.locations[to])
        ctx.cache[key] = result
        return result
    }

    static func estimatedWalk(_ a: TripLatLng?, _ b: TripLatLng?) -> LegChoice {
        guard let a, let b else { return LegChoice(mode: .walk, durationSec: 0, distanceM: nil, estimated: true) }
        let e = estimateLeg(a, b, .walk)
        return LegChoice(mode: .walk, durationSec: e.seconds, distanceM: e.metres, estimated: true)
    }

    /// From the phone's position to a point, by the same walk-limit rule.
    static func legFromPosition(_ ctx: SolverContext, _ position: TripLatLng, _ to: String) -> LegChoice {
        guard let target = ctx.locations[to] else {
            return LegChoice(mode: .walk, durationSec: 0, distanceM: nil, estimated: true)
        }
        let walk = estimateLeg(position, target, .walk)
        if walk.seconds <= ctx.rules.walkLimitSec {
            return LegChoice(mode: .walk, durationSec: walk.seconds, distanceM: walk.metres, estimated: true)
        }
        var best: LegChoice?
        for mode in ctx.modes {
            let e = estimateLeg(position, target, mode)
            if best == nil || e.seconds < best!.durationSec {
                best = LegChoice(mode: mode, durationSec: e.seconds, distanceM: e.metres, estimated: true)
            }
        }
        return best ?? LegChoice(mode: .walk, durationSec: walk.seconds, distanceM: walk.metres, estimated: true)
    }

    // MARK: - items.ts

    enum ItemKind { case wish, meal }

    struct Item {
        /// Identity for `filter(c => c !== victim)`: JavaScript compares the
        /// object, not its fields.
        let serial: Int
        var id: String
        var kind: ItemKind
        var wishId: String?
        var title: String
        /// Matrix point; nil = where the previous stop was (meals).
        var point: String?
        var location: TripLatLng?
        var durationMin: Double
        var fixedStartMin: Double?
        /// Hard end (a locked stop being re-timed keeps its planned end).
        var fixedEndMin: Double? = nil
        /// Re-planning only: show this planned arrival for a locked stop.
        var heldArriveMin: Double? = nil
        var locked: Bool
        var bookingId: String?
        var priority: TripPriority?
        var partOfDay: PartOfDay
        /// nil = unknown (treated as open), [] = closed all day.
        var windows: [TripOpenRange]?
        var baseWarnings: [String]
        var sortHint: Double
        /// v2.1: this wish is that day's lunch or dinner.
        var replacesMeal: MealKind? = nil
    }

    private static var serials = 0
    private static func nextSerial() -> Int {
        serials &+= 1
        return serials
    }

    static func hasBooked(_ wishId: String, _ bookings: [TripBooking]) -> Bool {
        bookings.contains { $0.wishId == wishId && $0.status == .booked }
    }

    static func wishWarnings(_ wish: TripWish, _ bookings: [TripBooking], _ windows: [TripOpenRange]?) -> [String] {
        var out: [String] = []
        if wish.facts?.bookingRequired == true && !hasBooked(wish.id, bookings) {
            if let ahead = wish.facts?.bookAheadDays, ahead > 0 {
                out.append("Booking needed \(js.num(ahead)) day\(ahead == 1 ? "" : "s") ahead — not booked yet")
            } else {
                out.append("Booking needed — not booked yet")
            }
        }
        if windows == nil { out.append("Opening hours unknown — check before you go") }
        return out
    }

    enum MealKind: String { case lunch, dinner }

    static func mealItem(_ date: String, _ kind: MealKind, _ rules: TripPaceRules) -> Item? {
        guard let w = kind == .lunch ? rules.lunch : rules.dinner else { return nil }
        return Item(
            serial: nextSerial(), id: "meal:\(date):\(kind.rawValue)", kind: .meal, wishId: nil,
            title: kind == .lunch ? "Lunch" : "Dinner", point: nil, location: nil,
            durationMin: js.round(w.durationSec / 60), fixedStartMin: nil, locked: false, bookingId: nil,
            priority: nil, partOfDay: .any, windows: [TripOpenRange(openMin: w.fromMin, closeMin: w.toMin)],
            baseWarnings: [], sortHint: 0
        )
    }

    static func mealKindOf(_ stopId: String) -> MealKind? {
        if stopId.hasSuffix(":lunch") { return .lunch }
        if stopId.hasSuffix(":dinner") { return .dinner }
        return nil
    }

    /// Matrix point of a planned stop (meals inherit, so nil).
    static func pointOfStop(_ stop: PlannedStop, _ stayId: String?) -> String? {
        switch stop.kind {
        case .stay: return stayId.map(stayPoint)
        case .wish: return stop.wishId ?? stop.id
        case .meal: return nil
        }
    }

    /// An already-planned stop as an item, keeping its planned visit length.
    /// A locked stop keeps its planned start as a hard start.
    static func itemFromStop(_ stop: PlannedStop, _ date: String, _ wishes: [String: TripWish], _ bookings: [TripBooking], _ rules: TripPaceRules) -> Item {
        let startMin = stop.arriveMin + js.round(stop.waitSec / 60)
        let durationMin = max(0, stop.departMin - startMin)
        if stop.kind == .meal {
            let meal = mealKindOf(stop.id).flatMap { mealItem(date, $0, rules) }
            return Item(
                serial: nextSerial(), id: stop.id, kind: .meal, wishId: nil, title: stop.title, point: nil, location: nil,
                durationMin: durationMin, fixedStartMin: stop.locked ? startMin : nil, fixedEndMin: stop.locked ? stop.departMin : nil,
                locked: stop.locked, bookingId: nil,
                priority: nil, partOfDay: .any, windows: meal?.windows, baseWarnings: [], sortHint: 0
            )
        }
        let wish = stop.wishId.flatMap { wishes[$0] }
        let windows = wish.flatMap { wishWindows($0, date, rules) }
        let replaces = wish.flatMap(mealKind)
        return Item(
            serial: nextSerial(), id: stop.id, kind: .wish, wishId: stop.wishId, title: stop.title,
            point: stop.wishId ?? stop.id, location: stop.location, durationMin: durationMin,
            fixedStartMin: stop.locked ? startMin : nil, fixedEndMin: stop.locked ? stop.departMin : nil,
            locked: stop.locked, bookingId: stop.bookingId,
            priority: wish?.priority, partOfDay: replaces != nil ? .any : (wish?.partOfDay ?? .any), windows: windows,
            baseWarnings: wish.map { wishWarnings($0, bookings, replaces != nil ? windowsOn($0.facts, date) : windows) } ?? [],
            sortHint: wish?.sortHint ?? 0, replacesMeal: replaces
        )
    }

    static let defaultVisitMin = 60.0

    /// Dinner window for a wish that replaces dinner when the pace plans none.
    static let fallbackDinner = TripPaceRules.Meal(fromMin: 19 * 60, toMin: 21 * 60, durationSec: 75 * 60)

    /// The meal window a meal-replacing wish must start in.
    static func replacedMealWindow(_ rules: TripPaceRules, _ kind: MealKind) -> (fromMin: Double, latestStartMin: Double) {
        let w = (kind == .lunch ? rules.lunch : rules.dinner) ?? fallbackDinner
        return (w.fromMin, w.toMin - js.round(w.durationSec / 60))
    }

    static func mealKind(_ wish: TripWish) -> MealKind? { wish.replacesMeal.flatMap(MealKind.init(rawValue:)) }

    /// Opening windows for a wish on a date; a meal-replacing wish is
    /// narrowed to start inside its meal window (it may run on past it).
    static func wishWindows(_ wish: TripWish, _ date: String, _ rules: TripPaceRules?) -> [TripOpenRange]? {
        let windows = windowsOn(wish.facts, date)
        guard let kind = mealKind(wish), let rules else { return windows }
        let meal = replacedMealWindow(rules, kind)
        let slot = TripOpenRange(openMin: meal.fromMin, closeMin: meal.latestStartMin + visitMin(wish, nil))
        guard let windows else { return [slot] }
        return windows
            .map { TripOpenRange(openMin: max($0.openMin, slot.openMin), closeMin: min($0.closeMin, slot.closeMin)) }
            .filter { $0.closeMin > $0.openMin }
    }

    /// The booked booking for a wish: earliest date and time, then id.
    static func bookedSlot(_ wishId: String, _ bookings: [TripBooking]) -> TripBooking? {
        js.sorted(bookings.filter { $0.wishId == wishId && $0.status == .booked && $0.date != nil && $0.startMin != nil }) { a, b in
            let d = js.compare(a.date ?? "", b.date ?? "")
            if d != 0 { return d }
            return js.cmp(a.startMin ?? 0, b.startMin ?? 0) ?? js.compare(a.id, b.id)
        }.first
    }

    /// The date a wish is pinned to: its booked slot's, else its fixed date.
    static func pinnedDate(_ wish: TripWish, _ bookings: [TripBooking]) -> String? {
        bookedSlot(wish.id, bookings)?.date ?? wish.fixedDate
    }

    static func visitMin(_ wish: TripWish, _ booking: TripBooking?) -> Double {
        if let d = wish.durationSec, d > 0 { return js.round(d / 60) }
        if let t = wish.facts?.typicalVisitSec, t > 0 { return js.round(t / 60) }
        if let b = booking, let s = b.startMin, let e = b.endMin, e > s { return e - s }
        return defaultVisitMin
    }

    static func wishItem(_ wish: TripWish, _ date: String, _ bookings: [TripBooking], _ rules: TripPaceRules? = nil) -> Item {
        let booking = bookedSlot(wish.id, bookings)
        let windows = wishWindows(wish, date, rules)
        var fixedStartMin: Double?
        var bookingId: String?
        if let booking, booking.date == date {
            fixedStartMin = booking.startMin
            bookingId = booking.id
        } else if wish.fixedDate == date, let fixed = wish.fixedStartMin {
            fixedStartMin = fixed
        }
        return Item(
            serial: nextSerial(), id: wish.id, kind: .wish, wishId: wish.id, title: wish.title, point: wish.id,
            location: wish.place?.location, durationMin: visitMin(wish, booking), fixedStartMin: fixedStartMin,
            locked: fixedStartMin != nil || wish.locked, bookingId: bookingId, priority: wish.priority,
            partOfDay: mealKind(wish) != nil ? .any : wish.partOfDay, windows: windows,
            baseWarnings: wishWarnings(wish, bookings, mealKind(wish) != nil ? windowsOn(wish.facts, date) : windows),
            sortHint: wish.sortHint, replacesMeal: mealKind(wish)
        )
    }

    // MARK: - trip.ts: the offline pull-forward

    /// A later-day wish this close on foot (seconds) can be pulled into now.
    static let pullForwardWalkSec = 15.0 * 60

    struct PullCandidate: Equatable {
        var wishId: String
        var from: String
        var walkSec: Double
    }

    /// Later-day wishes (not locked or pinned, open today) within
    /// `pullForwardWalkSec` on foot of `position`, nearest first.
    static func pullForwardCandidates(_ wishes: [TripWish], _ bookings: [TripBooking], today: String,
                                      laterDays: [PlannedDay], position: TripLatLng) -> [PullCandidate] {
        var byId: [String: TripWish] = [:]
        for w in wishes { byId[w.id] = w }
        var out: [(PullCandidate, Double)] = []
        for day in laterDays where js.compare(day.date, today) > 0 {
            for s in day.stops {
                guard let id = s.wishId, let wish = byId[id], let place = wish.place,
                      !s.locked, !wish.locked, pinnedDate(wish, bookings) == nil else { continue }
                if let w = windowsOn(wish.facts, today), w.isEmpty { continue }
                let walkSec = estimateLeg(position, place.location, .walk).seconds
                if walkSec > pullForwardWalkSec { continue }
                out.append((PullCandidate(wishId: wish.id, from: day.date, walkSec: walkSec), wish.sortHint))
            }
        }
        return js.sorted(out) { a, b in
            js.cmp(a.0.walkSec, b.0.walkSec) ?? js.cmp(a.1, b.1) ?? js.compare(a.0.wishId, b.0.wishId)
        }.map(\.0)
    }

    /// Today with `wishIds` done first, from now: the same pieces as
    /// `replanDay` (missed-slot rule, held locked stops, settle). The day the
    /// wish left is re-fitted by the server; offline the phone only removes it.
    static func pullForwardDay(_ input: Input, wishIds: [String], without: [String] = [])
        -> (day: PlannedDay, dropped: [String], gone: [Item]) {
        let sit = situation(input)
        var byId: [String: TripWish] = [:]
        for w in input.context.wishes { byId[w.id] = w }
        let already = sit.items.filter { wishIds.contains($0.wishId ?? "") }
        let alreadySerials = Set(already.map(\.serial))
        let pulled = wishIds
            .filter { id in !already.contains { $0.wishId == id } }
            .compactMap { byId[$0] }
            .map { wishItem($0, sit.frame.date, input.context.bookings, sit.ctx.rules) }
        let rest = sit.items.filter {
            !alreadySerials.contains($0.serial) && $0.kind != .meal && !without.contains($0.wishId ?? "")
        }
        let meals = sit.items.filter { $0.kind == .meal }
        let placed = withMeals(sit.ctx, sit.frame, sit.start, already + pulled + rest, meals).seq
        let settled = settle(sit.ctx, sit.frame, sit.start, placed)
        var day = toPlannedDay(sit.frame, settled.sim)
        day.warnings = sit.missedWarnings + day.warnings
        return (day, sit.missedIds + settled.gone.map { $0.wishId ?? $0.id }, settled.gone)
    }

    // MARK: - order.ts

    typealias SequenceCost = ([Item]) -> Double
    private static let eps = 1e-9
    private static let maxPasses = 60

    static func anchorsInOrder(_ seq: [Item]) -> Bool {
        var last = -Double.infinity
        for item in seq {
            guard let fixed = item.fixedStartMin else { continue }
            if fixed < last { return false }
            last = fixed
        }
        return true
    }

    static func byInsertionOrder(_ a: Item, _ b: Item) -> Double {
        let pa: Double = a.priority == .must ? 0 : 1
        let pb: Double = b.priority == .must ? 0 : 1
        return js.cmp(pa, pb) ?? js.cmp(a.sortHint, b.sortHint) ?? js.compare(a.id, b.id)
    }

    static func insertCheapest(_ seq: [Item], _ item: Item, _ cost: SequenceCost) -> [Item] {
        var best: (seq: [Item], cost: Double)?
        for p in 0...seq.count {
            var trial = seq
            trial.insert(item, at: p)
            if !anchorsInOrder(trial) { continue }
            let c = cost(trial)
            if best == nil || c < best!.cost - eps { best = (trial, c) }
        }
        return best?.seq ?? (seq + [item])
    }

    static func improve(_ seq: [Item], _ cost: SequenceCost) -> [Item] {
        var current = seq
        var currentCost = cost(current)
        let n = current.count
        for _ in 0..<maxPasses {
            var improved = false
            // or-opt: move a run of 1…3 to another position.
            if n >= 2 {
                outer: for len in 1...min(3, n - 1) {
                    var i = 0
                    while i + len <= n {
                        let run = Array(current[i..<(i + len)])
                        let rest = Array(current[0..<i]) + Array(current[(i + len)...])
                        for j in 0...rest.count where j != i {
                            let trial = Array(rest[0..<j]) + run + Array(rest[j...])
                            if !anchorsInOrder(trial) { continue }
                            let c = cost(trial)
                            if c < currentCost - eps {
                                current = trial
                                currentCost = c
                                improved = true
                                break outer
                            }
                        }
                        i += 1
                    }
                }
            }
            if !improved && n >= 2 {
                // 2-opt: reverse current[i…j].
                outer2: for i in 0..<(n - 1) {
                    for j in (i + 1)..<n {
                        let trial = Array(current[0..<i]) + Array(current[i...j].reversed()) + Array(current[(j + 1)...])
                        if !anchorsInOrder(trial) { continue }
                        let c = cost(trial)
                        if c < currentCost - eps {
                            current = trial
                            currentCost = c
                            improved = true
                            break outer2
                        }
                    }
                }
            }
            if !improved { break }
        }
        return current
    }

    /// Anchors by time, cheapest insertion for the rest, then improve.
    static func orderDay(_ items: [Item], _ cost: SequenceCost) -> [Item] {
        let anchors = js.sorted(items.filter { $0.fixedStartMin != nil }) { a, b in
            js.cmp(a.fixedStartMin ?? 0, b.fixedStartMin ?? 0) ?? js.compare(a.id, b.id)
        }
        let flex = js.sorted(items.filter { $0.fixedStartMin == nil }, by: byInsertionOrder)
        var seq = anchors
        for item in flex { seq = insertCheapest(seq, item, cost) }
        return seq.count > 1 ? improve(seq, cost) : seq
    }

    // MARK: - timing.ts

    enum Cost {
        static let travelPerMin = 1.0
        static let waitPerMin = 1.0
        static let overrunPerMin = 10.0
        static let lateForSlotPerMin = 20.0
        static let cutShortPerMin = 5.0
        static let closedMust = 600.0
        static let closedNice = 300.0
        static let partOfDayMiss = 15.0
        static let partOfDayPerMin = 0.5
        static let partOfDayMaxMin = 240.0
        static let droppedNice = 90.0
        static let mustWarning = 60.0
    }

    enum IssueKind { case closed, cutShort, lateForSlot }

    struct Issue {
        var itemId: String
        var kind: IssueKind
    }

    struct Simulation {
        var stops: [PlannedStop]
        var legs: [PlannedLeg]
        var warnings: [String]
        var travelMin: Double
        var waitMin: Double
        var overrunMin: Double
        var endMin: Double
        var issues: [Issue]
        var cost: Double
    }

    struct SimStart {
        var prefixStops: [PlannedStop]
        var prefixLegs: [PlannedLeg]
        var fromPoint: String?
        var fromStopId: String?
        var departMin: Double
        /// Where the phone actually is: the first leg is estimated from here.
        var fromPosition: TripLatLng? = nil
        /// Fresh day: leave the stay earlier for a first slot we would miss.
        var leaveEarlyForSlot = false
    }

    private static func partRange(_ part: PartOfDay) -> (Double, Double)? {
        switch part {
        case .morning: return (0, 12 * 60)
        case .afternoon: return (12 * 60, 17 * 60)
        case .evening: return (17 * 60, 24 * 60)
        case .any: return nil
        }
    }

    static func stayStartStop(_ frame: DayFrame, atMin: Double) -> PlannedStop? {
        guard let stay = frame.stay else { return nil }
        return PlannedStop(
            id: "stay:\(frame.date):start", kind: .stay, wishId: nil, title: stay.name, location: stay.location,
            arriveMin: atMin, departMin: atMin, waitSec: 0, locked: false, bookingId: nil, warnings: []
        )
    }

    static func freshStart(_ frame: DayFrame, atMin: Double, leaveEarlyForSlot: Bool) -> SimStart {
        let start = stayStartStop(frame, atMin: atMin)
        return SimStart(
            prefixStops: start.map { [$0] } ?? [],
            prefixLegs: [],
            fromPoint: frame.stay.map { stayPoint($0.id) },
            fromStopId: start?.id,
            departMin: atMin,
            leaveEarlyForSlot: leaveEarlyForSlot
        )
    }

    private static func legOf(_ from: String, _ to: String, _ c: LegChoice) -> PlannedLeg {
        PlannedLeg(fromStopId: from, toStopId: to, mode: c.mode, durationSec: c.durationSec,
                   distanceM: c.distanceM, estimated: c.estimated, line: nil)
    }

    private static let zeroLeg = LegChoice(mode: .walk, durationSec: 0, distanceM: 0, estimated: false)

    /// Time a sequence forward from a start. Never reorders or drops.
    static func simulate(_ ctx: SolverContext, _ frame: DayFrame, _ start: SimStart, _ items: [Item]) -> Simulation {
        var stops = start.prefixStops
        var legs = start.prefixLegs
        var issues: [Issue] = []
        var point = start.fromPoint
        var prevStopId = start.fromStopId
        var prevLocation: TripLatLng? = stops.last?.location
        var t = start.departMin
        var travelMin = 0.0
        var waitMin = 0.0
        var cost = 0.0
        let bufferMin = js.round(ctx.rules.bufferSec / 60)
        var first = true

        // A booked first stop we would miss from the normal start: leave earlier.
        if start.leaveEarlyForSlot, let head = items.first, let fixed = head.fixedStartMin,
           let headPoint = head.point, let from = point, stops.last?.kind == .stay {
            let legMin = js.ceil(chooseLeg(ctx, from, headPoint).durationSec / 60)
            let latest = fixed - legMin
            if latest < t {
                t = latest
                stops[stops.count - 1].arriveMin = latest
                stops[stops.count - 1].departMin = latest
            }
        }

        func travel(_ to: String?, _ toStopId: String) -> Double {
            guard let prev = prevStopId else { return 0 }
            let c: LegChoice
            if first, let position = start.fromPosition, let to {
                c = legFromPosition(ctx, position, to)
            } else if let to {
                if let point {
                    c = chooseLeg(ctx, point, to)
                } else {
                    // From a meal (no matrix point): estimated from where it was.
                    c = prevLocation.map { legFromPosition(ctx, $0, to) } ?? zeroLeg
                }
            } else {
                c = zeroLeg
            }
            first = false
            legs.append(legOf(prev, toStopId, c))
            return js.ceil(c.durationSec / 60)
        }

        for item in items {
            let target = item.point ?? point
            let legMin = travel(target, item.id)
            travelMin += legMin
            let arrive = t + legMin
            var begin = arrive
            var warnings = item.baseWarnings
            let what: String? = item.kind == .meal ? item.title.lowercased() : item.replacesMeal?.rawValue
            if let fixed = item.fixedStartMin {
                if arrive <= fixed {
                    begin = fixed
                } else {
                    warnings.append("Booked for \(fmtMin(fixed)) — you arrive \(fmtMin(arrive))")
                    issues.append(Issue(itemId: item.id, kind: .lateForSlot))
                    cost += (arrive - fixed) * Cost.lateForSlotPerMin
                }
            } else if let windows = item.windows {
                if windows.isEmpty {
                    warnings.append("Closed on \(dayLabel(frame.date))")
                    issues.append(Issue(itemId: item.id, kind: .closed))
                    cost += item.priority == .must ? Cost.closedMust : Cost.closedNice
                } else {
                    let fits = windows.first { max(arrive, $0.openMin) + item.durationMin <= $0.closeMin }
                    let open = windows.first { max(arrive, $0.openMin) < $0.closeMin }
                    if let fits {
                        begin = max(arrive, fits.openMin)
                    } else if let open {
                        begin = max(arrive, open.openMin)
                        warnings.append(what.map { "Late \($0) — starts \(fmtMin(begin))" }
                            ?? "Closes \(fmtMin(open.closeMin)) — you arrive \(fmtMin(arrive))")
                        issues.append(Issue(itemId: item.id, kind: .cutShort))
                        cost += (begin + item.durationMin - open.closeMin) * Cost.cutShortPerMin
                    } else {
                        let last = windows[windows.count - 1]
                        warnings.append(what.map { "Late \($0) — starts \(fmtMin(begin))" }
                            ?? "Closed by the time you arrive — closes \(fmtMin(last.closeMin)), you arrive \(fmtMin(arrive))")
                        issues.append(Issue(itemId: item.id, kind: what != nil ? .cutShort : .closed))
                        cost += what != nil
                            ? (begin + item.durationMin - last.closeMin) * Cost.cutShortPerMin
                            : item.priority == .must ? Cost.closedMust : Cost.closedNice
                    }
                }
            }
            if let (from, to) = partRange(item.partOfDay) {
                // The wanted part of the day works like a soft opening: wait
                // for it (unless the slot is fixed), and pay for starting after it.
                if item.fixedStartMin == nil && begin < from && !issues.contains(where: { $0.itemId == item.id }) {
                    let window = item.windows?.first { $0.closeMin >= from + item.durationMin && $0.openMin <= from }
                    if item.windows == nil || window != nil { begin = from }
                }
                let miss = begin < from ? from - begin : begin >= to ? begin - to + 1 : 0
                if miss > 0 { cost += Cost.partOfDayMiss + min(miss, Cost.partOfDayMaxMin) * Cost.partOfDayPerMin }
            }
            waitMin += max(0, begin - arrive)
            // Re-planning holds a locked stop's planned times: the slot never
            // moves, and lateness shows only as the "Booked for …" warning.
            var shownArrive = arrive
            if let held = item.heldArriveMin, let fixed = item.fixedStartMin {
                begin = fixed
                shownArrive = held
            }
            // A locked stop being re-timed keeps its planned end, even when late.
            let depart = item.fixedEndMin.map { max($0, begin) } ?? begin + item.durationMin
            let location = item.location ?? prevLocation
            stops.append(PlannedStop(
                id: item.id, kind: item.kind == .meal ? .meal : .wish, wishId: item.wishId, title: item.title,
                location: location, arriveMin: shownArrive, departMin: depart, waitSec: (begin - shownArrive) * 60,
                locked: item.locked, bookingId: item.bookingId, warnings: warnings
            ))
            prevStopId = item.id
            prevLocation = location
            point = target
            t = depart + (item.kind == .meal ? 0 : bufferMin)
        }

        var endMin = stops.last?.departMin ?? t
        if let stay = frame.stay {
            let endId = "stay:\(frame.date):end"
            let legMin = travel(stayPoint(stay.id), endId)
            travelMin += legMin
            endMin = t + legMin
            stops.append(PlannedStop(
                id: endId, kind: .stay, wishId: nil, title: stay.name, location: stay.location,
                arriveMin: endMin, departMin: endMin, waitSec: 0, locked: false, bookingId: nil, warnings: []
            ))
        }
        var warnings: [String] = []
        if frame.stay == nil { warnings.append("No stay booked for this night") }
        let overrunMin = max(0, endMin - frame.dayEndMin)
        if overrunMin > 0 {
            warnings.append(frame.stay != nil
                ? "Back at the stay \(fmtMin(endMin)) — later than \(fmtMin(frame.dayEndMin))"
                : "Runs to \(fmtMin(endMin)) — later than \(fmtMin(frame.dayEndMin))")
        }
        cost += travelMin * Cost.travelPerMin + waitMin * Cost.waitPerMin + overrunMin * Cost.overrunPerMin
        return Simulation(stops: stops, legs: legs, warnings: warnings, travelMin: travelMin, waitMin: waitMin,
                          overrunMin: overrunMin, endMin: endMin, issues: issues, cost: cost)
    }

    static func toPlannedDay(_ frame: DayFrame, _ sim: Simulation) -> PlannedDay {
        PlannedDay(date: frame.date, stayId: frame.stay?.id, stops: sim.stops, legs: sim.legs, warnings: sim.warnings)
    }

    /// Insert meals at the cheapest gap, one at a time; ties go to the earliest gap.
    static func withMeals(_ ctx: SolverContext, _ frame: DayFrame, _ start: SimStart, _ seq: [Item], _ meals: [Item]) -> (seq: [Item], sim: Simulation) {
        var current = seq
        for meal in meals {
            var best: (seq: [Item], cost: Double)?
            for p in 0...current.count {
                var trial = current
                trial.insert(meal, at: p)
                let cost = simulate(ctx, frame, start, trial).cost
                if best == nil || cost < best!.cost { best = (trial, cost) }
            }
            if let best { current = best.seq }
        }
        return (current, simulate(ctx, frame, start, current))
    }

    /// Lowest value first: later-listed nices first, then id (descending).
    static func byLowestValue(_ a: Item, _ b: Item) -> Double {
        js.cmp(b.sortHint, a.sortHint) ?? js.compare(b.id, a.id)
    }

    static func droppable(_ item: Item) -> Bool {
        item.kind == .wish && item.priority == .nice && !item.locked && item.fixedStartMin == nil
    }
}

// MARK: - JavaScript semantics

/// The handful of places where a literal port would otherwise drift.
enum js {
    /// `Math.round`: halves go up, towards +∞.
    static func round(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
    static func ceil(_ x: Double) -> Double { x.rounded(.up) }
    static func floorDiv(_ a: Int, _ b: Int) -> Int { Int((Double(a) / Double(b)).rounded(.down)) }

    /// A comparator's `a - b`, as the left of `||`: nil when 0 (falsy), so
    /// the chain moves on to the next key.
    static func cmp(_ a: Double, _ b: Double) -> Double? {
        let d = a - b
        return d == 0 ? nil : d
    }

    /// `Array.prototype.sort` with a numeric comparator: stable.
    static func sorted<T>(_ items: [T], by compare: (T, T) -> Double) -> [T] {
        items.enumerated().sorted { x, y in
            let c = compare(x.element, y.element)
            return c != 0 ? c < 0 : x.offset < y.offset
        }.map(\.element)
    }

    /// `${n}` for a number: whole numbers print without a decimal point.
    static func num(_ x: Double) -> String {
        if x == x.rounded(), abs(x) < 1e15 { return String(Int(x)) }
        return String(x)
    }

    /// The solver's `cmp`: plain UTF-16 code-unit order, as JavaScript's
    /// `<` on strings. Never locale-dependent (SR-Main 609dcfd6), so the two
    /// break ties identically. -1, 0 or 1.
    static func compare(_ a: String, _ b: String) -> Double {
        if a == b { return 0 }
        return Array(a.utf16).lexicographicallyPrecedes(Array(b.utf16)) ? -1 : 1
    }
}

// MARK: - Opening hours text

/// `parseOpeningHours` from `hours.ts`: the solver's fallback when a fact
/// sheet has the OSM text but no parsed hours. Keys are ISO weekday strings.
enum TripHours {
    private static let codes = ["Mo": 1, "Tu": 2, "We": 3, "Th": 4, "Fr": 5, "Sa": 6, "Su": 7]
    private static let all = [1, 2, 3, 4, 5, 6, 7]

    static func parse(_ text: String?) -> [String: [TripOpenRange]]? {
        guard let text, !text.isEmpty else { return nil }
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: #"\s*-\s*"#, with: "-", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*,\s*(?=\d)"#, with: ",", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(Mo|Tu|We|Th|Fr|Sa|Su|PH)\s*,\s*(?=(Mo|Tu|We|Th|Fr|Sa|Su|PH)\b)"#, with: "$1,", options: .regularExpression)
        if s.isEmpty { return nil }
        let rules = split(s, #"\s*;\s*"#)
            .flatMap { split($0, #",\s+(?=(?:Mo|Tu|We|Th|Fr|Sa|Su|PH)[-,\s])"#) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var hours: [Int: [TripOpenRange]] = [:]
        var any = false
        for rule in rules {
            if rule == "24/7" {
                for d in all { hours[d] = [TripOpenRange(openMin: 0, closeMin: 1440)] }
                any = true
                continue
            }
            let tokens = split(rule, #"\s+"#)
            var days: [Int]?
            let spansText: String
            if tokens.count == 1 {
                days = matches(tokens[0], #"^[\d:,-]+$|^off$|^closed$"#) ? all : nil
                spansText = tokens[0]
                if days == nil { return nil }
            } else if tokens.count == 2 {
                days = selector(tokens[0])
                spansText = tokens[1]
            } else {
                return nil
            }
            guard let chosen = days, let spans = self.spans(spansText) else { return nil }
            if chosen.isEmpty { continue }
            for d in chosen { hours[d] = spans }
            any = true
        }
        if !any { return nil }
        for d in all where hours[d] == nil { hours[d] = [] }
        return Dictionary(uniqueKeysWithValues: hours.map { (String($0.key), $0.value) })
    }

    private static func clock(_ text: String) -> Double? {
        let p = text.split(separator: ":", omittingEmptySubsequences: false)
        guard p.count == 2, (1...2).contains(p[0].count), p[1].count == 2,
              let h = Int(p[0]), let m = Int(p[1]), p[0].allSatisfy(\.isNumber), p[1].allSatisfy(\.isNumber) else { return nil }
        if h > 24 || m > 59 || (h == 24 && m != 0) { return nil }
        return Double(h * 60 + m)
    }

    private static func selector(_ text: String) -> [Int]? {
        var days = Set<Int>()
        for part in text.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
            if part == "PH" { continue }
            let ends = part.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            guard (1...2).contains(ends.count), let from = codes[ends[0]] else { return nil }
            let to: Int
            if ends.count == 2 {
                guard let t = codes[ends[1]] else { return nil }
                to = t
            } else {
                to = from
            }
            var d = from
            while true {
                days.insert(d)
                if d == to { break }
                d = d % 7 + 1
            }
        }
        return all.filter { days.contains($0) }
    }

    private static func spans(_ text: String) -> [TripOpenRange]? {
        if text == "off" || text == "closed" { return [] }
        var out: [TripOpenRange] = []
        for part in text.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
            guard matches(part, #"^[\d:]+-[\d:]+$"#) else { return nil }
            let ends = part.split(separator: "-").map(String.init)
            guard ends.count == 2, let open = clock(ends[0]), var close = clock(ends[1]) else { return nil }
            if close <= open { close = 1440 }
            out.append(TripOpenRange(openMin: open, closeMin: close))
        }
        out = js.sorted(out) { a, b in js.cmp(a.openMin, b.openMin) ?? (a.closeMin - b.closeMin) }
        var merged: [TripOpenRange] = []
        for s in out {
            if let last = merged.last, s.openMin <= last.closeMin {
                merged[merged.count - 1].closeMin = max(last.closeMin, s.closeMin)
            } else {
                merged.append(s)
            }
        }
        return merged
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }

    /// `String.split(regex)`.
    private static func split(_ s: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [s] }
        var out: [String] = []
        var from = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r = Range(m.range, in: s) else { continue }
            out.append(String(s[from..<r.lowerBound]))
            from = r.upperBound
        }
        out.append(String(s[from...]))
        return out
    }
}

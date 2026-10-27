import Foundation

/// What a trip map draws, worked out from the plan: lines styled by how each
/// leg is travelled, numbered pins coloured by part of the day, and the
/// points to frame. `TripSceneMap` only paints it.
///
/// The map-led day (red team 2026-10-15, proposal A) leans on three rules:
///  - a pin's number is the stop's number in the list beside it, so the map
///    and the list are one thing (`numbers`);
///  - a leg the router never drew is a faint DASHED guess between its two
///    ends, never a line that passes for a real route;
///  - a proposed change is drawn over the current plan, which stays as a
///    dashed ghost, so you see what a choice does before taking it;
///  - what is behind you is off the map: a leg to a stop you have done, or
///    one the phone has walked (`Walked`), goes, and the leg you are on
///    starts from where you are.
///
/// Foundation only: the Linux harness compiles and tests it.
enum TripMapScene {
    // MARK: Shapes

    struct LineStyle: Hashable {
        enum Pattern: String, Hashable { case solid, dotted, dashed }
        var pattern: Pattern
        var color: UInt32
        var alpha: Double = 1
        var width: Double

        /// A layer per distinct style: this is its id's tail.
        var key: String {
            "\(pattern.rawValue)-\(String(color, radix: 16))-\(Int((alpha * 100).rounded()))-\(Int((width * 10).rounded()))"
        }
    }

    struct Line: Hashable {
        var points: [TripLatLng]
        var style: LineStyle
    }

    struct Badge: Hashable {
        enum Glyph: Hashable {
            case number(Int)
            /// An SF Symbol name.
            case symbol(String)
            /// A plain dot.
            case dot
        }
        var glyph: Glyph
        var fill: UInt32
        /// Diameter, points.
        var size: Double
        /// A ring outside the white edge: the stop that is next, or picked.
        var ring: UInt32? = nil
        var faded = false

        /// The image's name in the map style — one image per distinct badge.
        var name: String {
            let g: String
            switch glyph {
            case .number(let n): g = "n\(n)"
            case .symbol(let s): g = "s-" + s
            case .dot: g = "dot"
            }
            return "sr-pin-\(g)-\(String(fill, radix: 16))-\(Int(size))-\(ring.map { String($0, radix: 16) } ?? "x")-\(faded ? 1 : 0)"
        }
    }

    struct Pin: Hashable {
        /// The stop's id (a day), or the day's date (the trip overview).
        var id: String
        var at: TripLatLng
        var badge: Badge
        /// Drawn above every other pin: the next stop, the picked one.
        var top = false
        /// What VoiceOver says for it — "3. Trevi Fountain, 14:20" — so a pin
        /// is reachable without sight (plan §5.5). Nil: not an element of its
        /// own (the overview's small dots, which its numbered pin speaks for).
        var label: String? = nil
    }

    struct Scene: Hashable {
        var lines: [Line] = []
        var pins: [Pin] = []
        /// What "fit" frames.
        var frame: [TripLatLng] = []
    }

    // MARK: Palette (fixed: the map's tiles are light in either theme)

    /// The light through the day (Prism): sky-blue morning, coral noon,
    /// amber afternoon, indigo evening.
    static func stageColor(_ stage: DayStage) -> UInt32 {
        switch stage {
        case .morning: return 0x1E63E9
        case .lunch: return 0xE62E5C
        case .afternoon: return 0xE85D00
        case .evening: return 0x15123A
        }
    }

    static let ink: UInt32 = 0x15123A
    static let accent: UInt32 = 0x5233F0
    static let petrol: UInt32 = 0x087078
    static let green: UInt32 = 0x0A8048

    /// One colour a day on the trip's overview, in turn.
    static let dayColors: [UInt32] = [0x5233F0, 0xE62E5C, 0x1E63E9, 0x0E9F5A, 0xE85D00, 0x9333EA]

    static func dayColor(_ index: Int) -> UInt32 { dayColors[((index % dayColors.count) + dayColors.count) % dayColors.count] }

    /// How a leg reads by mode: a dotted walk, a petrol transit line, a solid
    /// ride. `next`: the leg you are about to take, drawn heavier.
    static func legStyle(_ mode: TravelMode, next: Bool) -> LineStyle {
        let extra = next ? 2.0 : 0
        switch mode {
        case .walk: return LineStyle(pattern: .dotted, color: accent, width: 5 + extra)
        case .transit: return LineStyle(pattern: .solid, color: petrol, width: 5 + extra)
        case .cycle: return LineStyle(pattern: .solid, color: green, width: 4 + extra)
        case .taxi, .drive, .unknown: return LineStyle(pattern: .solid, color: ink, width: 4 + extra)
        }
    }

    /// A leg with no routed line: where it goes, said as a guess.
    static let guess = LineStyle(pattern: .dashed, color: ink, alpha: 0.45, width: 2.5)
    /// The plan as it stands, under a proposed change.
    static let ghost = LineStyle(pattern: .dashed, color: ink, alpha: 0.35, width: 3)

    // MARK: Numbers

    /// A visit, as the list numbers it: a wish, or a stop made on the day.
    /// Stays, meals and journeys carry a symbol instead.
    static func isVisit(_ stop: PlannedStop) -> Bool { stop.kind == .wish }

    /// Each visit's number in the day, from 1, by stop id.
    static func numbers(_ day: PlannedDay) -> [String: Int] {
        var out: [String: Int] = [:]
        var n = 0
        for stop in day.stops where isVisit(stop) {
            n += 1
            out[stop.id] = n
        }
        return out
    }

    /// The symbol a non-visit stop wears on the map.
    static func symbol(_ stop: PlannedStop) -> String {
        if stop.id.hasPrefix("here:") && stop.wishId == nil { return "cup.and.saucer.fill" }
        if stop.title.lowercased().hasPrefix("drop bags") || stop.id.hasSuffix(":bags") { return "suitcase.rolling.fill" }
        switch stop.kind {
        case .stay: return "bed.double.fill"
        case .meal: return "fork.knife"
        case .transport: return "airplane"
        case .wish, .unknown: return "mappin"
        }
    }

    // MARK: A day

    /// One day: the legs still ahead by mode, its stops numbered and
    /// coloured by stage, the next one and any picked one on top. A leg to a
    /// done stop is not drawn; with `walked`, neither is what the phone has
    /// walked of the rest, and a stop reached that way is faded as done.
    ///
    /// `preview`: a proposed version of the day. Its route is drawn and its
    /// pins shown, over the current plan's remaining legs as a ghost.
    static func day(
        _ day: PlannedDay, stages: [DayStage], done: Set<String>, nextId: String?, selectedId: String?,
        preview: PlannedDay? = nil, previewStages: [DayStage] = [], walked: Walked? = nil
    ) -> Scene {
        var scene = Scene()
        let ahead = self.ahead(day, done: done, nextId: nextId, walked: walked)
        let done = done.union(ahead.reached)
        if let preview {
            scene.lines += self.ahead(day, done: done, nextId: nil, walked: walked).lines.map { Line(points: $0.points, style: ghost) }
            let previewNext = preview.stops.first { !done.contains($0.id) && $0.kind != .stay }?.id
            scene.lines += self.ahead(preview, done: done, nextId: previewNext, walked: walked).lines
            scene.pins = pins(preview, stages: previewStages, done: done, nextId: previewNext, selectedId: selectedId)
            scene.frame = framePoints(preview) + framePoints(day)
            return scene
        }
        scene.lines = ahead.lines
        scene.pins = pins(day, stages: stages, done: done, nextId: nextId, selectedId: selectedId)
        scene.frame = framePoints(day)
        return scene
    }

    /// Every leg still ahead as a line. A leg whose end has no place (a meal
    /// not yet given one) is bridged: the last placed stop to the next, as a
    /// guess. A leg to a done stop is left out.
    static func legs(_ day: PlannedDay, done: Set<String>, nextId: String?, walked: Walked? = nil) -> [Line] {
        ahead(day, done: done, nextId: nextId, walked: walked).lines
    }

    /// The legs ahead, and the stops `walked` shows were walked to.
    ///
    /// Walked legs come off in order, as a day is walked: each leg counts
    /// only once every one before it is behind you, and the first that is
    /// not starts where you are. So an evening's walk home down the morning's
    /// streets stays on the map until it is the walk you are on. The next
    /// stop is never `reached` — you are on your way to it, or at it, and
    /// it keeps its ring.
    static func ahead(_ day: PlannedDay, done: Set<String>, nextId: String?, walked: Walked?) -> (lines: [Line], reached: Set<String>) {
        var lines: [Line] = []
        var reached: Set<String> = []
        let stops = day.stops
        var lastPlaced: Int? = stops.first?.location == nil ? nil : 0
        var behind = walked.map { !$0.isEmpty } ?? false
        guard stops.count > 1 else { return (lines, reached) }
        for i in 1..<stops.count {
            let to = stops[i]
            guard let b = to.location else { continue }
            defer { lastPlaced = i }
            guard let from = lastPlaced, let a = stops[from].location, !done.contains(to.id) else { continue }
            let leg = from == i - 1 ? day.leg(before: i) : nil
            let routed = leg?.line.flatMap { $0.count > 1 ? $0 : nil }
            // Nowhere to go (a meal where you already are): no line, and
            // nothing to say about what is behind you.
            guard routed != nil || a != b else { continue }
            let style = routed != nil ? legStyle(leg!.mode, next: to.id == nextId) : guess
            var points = routed ?? [a, b]
            if behind, let walked {
                guard let left = walked.remaining(points) else {
                    if to.id != nextId { reached.insert(to.id) }
                    continue
                }
                behind = false
                points = left
            }
            lines.append(Line(points: points, style: style))
        }
        return (lines, reached)
    }

    static func pins(_ day: PlannedDay, stages: [DayStage], done: Set<String>, nextId: String?, selectedId: String?) -> [Pin] {
        let numbers = numbers(day)
        var out: [Pin] = []
        var stayAt: Set<String> = []
        for (i, stop) in day.stops.enumerated() {
            let stage = i < stages.count ? stages[i] : .morning
            // A meal with no place yet (the solver's placeholder sits where
            // you were before): its options instead, as small pins to pick.
            if stop.kind == .meal, let options = stop.mealOptions, !options.isEmpty {
                for option in options {
                    let id = mealOptionPinId(stop: stop.id, option: option.id)
                    let isPicked = id == selectedId
                    out.append(Pin(
                        id: id, at: option.place.location,
                        badge: Badge(
                            glyph: .symbol(option.kind == "cafe" ? "cup.and.saucer.fill" : "fork.knife"),
                            fill: stageColor(stage), size: isPicked ? 30 : 22, ring: isPicked ? ink : nil
                        ),
                        top: isPicked,
                        label: "\(option.name), a place for \(stop.title.lowercased()) around \(TripFormat.time(stop.arriveMin))"
                    ))
                }
                continue
            }
            guard let at = stop.location else { continue }
            // The morning's and the evening's stay are one place: one pin.
            if stop.kind == .stay {
                let key = String(format: "%.5f,%.5f", at.lat, at.lng)
                if stayAt.contains(key) && stop.id != selectedId { continue }
                stayAt.insert(key)
            }
            let isNext = stop.id == nextId
            let isPicked = stop.id == selectedId
            let isDone = done.contains(stop.id)
            let glyph: Badge.Glyph = numbers[stop.id].map { .number($0) } ?? .symbol(symbol(stop))
            let fill = stop.kind == .stay ? ink : stageColor(stage)
            let size: Double = isPicked || isNext ? 34 : (numbers[stop.id] == nil ? 24 : 28)
            let ring: UInt32? = isPicked ? ink : (isNext ? accent : nil)
            out.append(Pin(
                id: stop.id, at: at,
                badge: Badge(glyph: glyph, fill: fill, size: size, ring: ring, faded: isDone && !isPicked),
                top: isNext || isPicked,
                label: spoken(stop, number: numbers[stop.id], next: isNext, done: isDone)
            ))
        }
        return out
    }

    /// "3. Trevi Fountain, 14:20", "Hotel Artemide, 09:00" — and ", next" or
    /// ", done" when that is what the pin's ring or fading says.
    static func spoken(_ stop: PlannedStop, number: Int?, next: Bool = false, done: Bool = false) -> String {
        var words = (number.map { "\($0). " } ?? "") + stop.title + ", " + TripFormat.time(stop.arriveMin)
        if next { words += ", next" } else if done { words += ", done" }
        return words
    }

    /// A meal option's pin: `meal-option:<meal stop id>|<option id>`.
    static func mealOptionPinId(stop: String, option: String) -> String { "meal-option:\(stop)|\(option)" }

    /// The meal stop and option a pin id names, or nil for a stop's pin.
    static func mealOption(pinId: String) -> (stopId: String, optionId: String)? {
        guard pinId.hasPrefix("meal-option:") else { return nil }
        let rest = pinId.dropFirst("meal-option:".count)
        guard let bar = rest.firstIndex(of: "|") else { return nil }
        return (String(rest[..<bar]), String(rest[rest.index(after: bar)...]))
    }

    // MARK: Walked

    /// Where the phone has been today, for taking what is behind you off the
    /// map. A point is walked when the trail passed within `nearM` of it —
    /// wide enough for GPS on a city street, narrow enough that the next
    /// street over is not.
    struct Walked: Equatable {
        static let nearM = 40.0
        /// A leg this much walked is behind you.
        static let walkedShare = 0.85
        /// What is left shorter than this is not worth a line.
        static let shortestM = 30.0
        /// The line is checked every this many metres.
        static let stepM = 15.0

        /// The trail, bucketed by cells about `nearM` across.
        private let cells: [Cell: [TripLatLng]]
        /// The latest position: the leg you are on starts here.
        let here: TripLatLng?

        private struct Cell: Hashable { var x: Int, y: Int }

        init(trail: [TripLatLng], here: TripLatLng? = nil) {
            var cells: [Cell: [TripLatLng]] = [:]
            for p in trail { cells[Self.cell(p), default: []].append(p) }
            self.cells = cells
            self.here = here ?? trail.last
        }

        var isEmpty: Bool { cells.isEmpty && here == nil }

        private static func cell(_ p: TripLatLng) -> Cell {
            // ~nearM in degrees; longitude cells are narrower away from the
            // equator, which only means more of them are looked in.
            let size = nearM / 111_320
            return Cell(x: Int((p.lng / size).rounded(.down)), y: Int((p.lat / size).rounded(.down)))
        }

        /// Has the trail passed within `nearM` of this point?
        func passed(_ p: TripLatLng) -> Bool {
            let c = Self.cell(p)
            let reach = Int((1 / max(cos(p.lat * .pi / 180), 0.2)).rounded(.up))
            for dx in -reach...reach {
                for dy in -1...1 {
                    if let near = cells[Cell(x: c.x + dx, y: c.y + dy)],
                       near.contains(where: { TripMapScene.distanceM($0, p) <= Self.nearM }) { return true }
                }
            }
            return false
        }

        /// What is left of a leg's line to walk: nil when it is behind you;
        /// else the line from the furthest point walked along it in an
        /// unbroken run from its start, or from the point nearest where you
        /// are when you are on it.
        func remaining(_ line: [TripLatLng]) -> [TripLatLng]? {
            guard line.count > 1 else { return line }
            let dense = TripMapScene.densify(line, stepM: Self.stepM)
            let covered = dense.map(passed)
            let walkedCount = covered.filter { $0 }.count
            if Double(walkedCount) / Double(dense.count) >= Self.walkedShare { return nil }
            // The run walked from the start, through gaps a GPS jump makes.
            var cut = 0
            var gap = 0
            for (i, c) in covered.enumerated() {
                if c { cut = i; gap = 0 } else { gap += 1; if gap * Int(Self.stepM) > 60 { break } }
            }
            // On the line now: it starts where you are.
            if let here, cut < dense.count - 1 {
                var best = cut
                var bestM = Double.infinity
                for i in cut..<dense.count {
                    let d = TripMapScene.distanceM(dense[i], here)
                    if d < bestM { bestM = d; best = i }
                }
                if bestM <= Self.nearM { cut = max(cut, best) }
            }
            if cut == 0 { return line }
            let left = Array(dense[cut...])
            return TripMapScene.lengthM(left) < Self.shortestM ? nil : left
        }
    }

    /// Metres between two points (equirectangular: ample at street scale).
    static func distanceM(_ a: TripLatLng, _ b: TripLatLng) -> Double {
        let x = (b.lng - a.lng) * .pi / 180 * cos((a.lat + b.lat) / 2 * .pi / 180)
        let y = (b.lat - a.lat) * .pi / 180
        return (x * x + y * y).squareRoot() * 6_371_000
    }

    static func lengthM(_ line: [TripLatLng]) -> Double {
        zip(line, line.dropFirst()).reduce(0) { $0 + distanceM($1.0, $1.1) }
    }

    /// The line with a point at least every `stepM`, its own points kept.
    static func densify(_ line: [TripLatLng], stepM: Double) -> [TripLatLng] {
        guard var last = line.first else { return [] }
        var out = [last]
        for p in line.dropFirst() {
            let d = distanceM(last, p)
            let n = Int((d / stepM).rounded(.up))
            if n > 1 {
                for k in 1..<n {
                    let t = Double(k) / Double(n)
                    out.append(TripLatLng(lat: last.lat + (p.lat - last.lat) * t, lng: last.lng + (p.lng - last.lng) * t))
                }
            }
            out.append(p)
            last = p
        }
        return out
    }

    static func framePoints(_ day: PlannedDay) -> [TripLatLng] {
        day.stops.compactMap(\.location) + day.legs.flatMap { $0.line ?? [] }
    }

    // MARK: The whole trip

    /// Every day on one map: each in its colour, its first visit wearing the
    /// day's number (tap it to open the day), the other visits as dots, and
    /// the stays. Pin ids are the days' dates.
    ///
    /// `today` (the trip's local date): a day before it is behind you — its
    /// pins faded, its route off the map — and today's route loses what
    /// `walked` has walked. The days still to come are drawn whole.
    static func overview(_ days: [PlannedDay], stays: [TripStay], today: String? = nil, walked: Walked? = nil) -> Scene {
        var scene = Scene()
        for (d, day) in days.enumerated() {
            let color = dayColor(d)
            let past = today.map { day.date < $0 } ?? false
            let todayWalked = day.date == today ? walked : nil
            for line in past ? [] : legs(day, done: [], nextId: nil, walked: todayWalked) {
                var style = line.style == guess
                    ? LineStyle(pattern: .dashed, color: color, alpha: 0.6, width: 2.5)
                    : LineStyle(pattern: .solid, color: color, alpha: 0.9, width: 3.5)
                if line.style.pattern == .dotted { style.pattern = .dotted; style.width = 4 }
                scene.lines.append(Line(points: line.points, style: style))
            }
            let visits = day.stops.filter { isVisit($0) && $0.location != nil }
            for (k, stop) in visits.enumerated() {
                guard let at = stop.location else { continue }
                scene.pins.append(Pin(
                    id: day.date, at: at,
                    badge: k == 0 ? Badge(glyph: .number(d + 1), fill: color, size: 30, faded: past) : Badge(glyph: .dot, fill: color, size: 12, faded: past),
                    top: k == 0,
                    label: k == 0 ? "Day \(d + 1), from \(stop.title), \(visits.count) \(visits.count == 1 ? "place" : "places")" : nil
                ))
            }
            scene.frame += framePoints(day)
        }
        for stay in stays {
            scene.pins.append(Pin(id: "stay:\(stay.id)", at: stay.location, badge: Badge(glyph: .symbol("bed.double.fill"), fill: ink, size: 28), top: true,
                                  label: "\(stay.name), where you stay"))
            scene.frame.append(stay.location)
        }
        return scene
    }

    // MARK: Framing

    struct Bounds: Equatable {
        var minLat: Double, minLng: Double, maxLat: Double, maxLng: Double
    }

    /// The box around some points, opened out to at least `minSpan` degrees
    /// so one stop is not framed at street-sign zoom.
    static func bounds(_ points: [TripLatLng], minSpan: Double = 0.004) -> Bounds? {
        guard let first = points.first else { return nil }
        var b = Bounds(minLat: first.lat, minLng: first.lng, maxLat: first.lat, maxLng: first.lng)
        for p in points {
            b.minLat = min(b.minLat, p.lat); b.maxLat = max(b.maxLat, p.lat)
            b.minLng = min(b.minLng, p.lng); b.maxLng = max(b.maxLng, p.lng)
        }
        if b.maxLat - b.minLat < minSpan {
            let mid = (b.maxLat + b.minLat) / 2
            b.minLat = mid - minSpan / 2; b.maxLat = mid + minSpan / 2
        }
        if b.maxLng - b.minLng < minSpan {
            let mid = (b.maxLng + b.minLng) / 2
            b.minLng = mid - minSpan / 2; b.maxLng = mid + minSpan / 2
        }
        return b
    }
}

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
///    dashed ghost, so you see what a choice does before taking it.
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
    }

    struct Scene: Hashable {
        var lines: [Line] = []
        var pins: [Pin] = []
        /// What "fit" frames.
        var frame: [TripLatLng] = []
    }

    // MARK: Palette (fixed: the map's tiles are light in either theme)

    /// The light through the day: petrol morning, orange noon, ochre
    /// afternoon, ink evening.
    static func stageColor(_ stage: DayStage) -> UInt32 {
        switch stage {
        case .morning: return 0x0E5B66
        case .lunch: return 0xC4570A
        case .afternoon: return 0xB0892A
        case .evening: return 0x1A1008
        }
    }

    static let ink: UInt32 = 0x1A1008
    static let accent: UInt32 = 0xC4570A
    static let petrol: UInt32 = 0x0E5B66
    static let green: UInt32 = 0x55663A

    /// One colour a day on the trip's overview, in turn.
    static let dayColors: [UInt32] = [0xC4570A, 0x0E5B66, 0x55663A, 0xB0892A, 0x3D2E1A, 0x8C3B2E]

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
    /// A leg already travelled.
    static let travelled = LineStyle(pattern: .solid, color: ink, alpha: 0.28, width: 3)
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

    /// One day: its legs by mode (travelled ones quiet), its stops numbered
    /// and coloured by stage, the next one and any picked one on top.
    ///
    /// `preview`: a proposed version of the day. Its route is drawn and its
    /// pins shown, over the current plan's remaining legs as a ghost.
    static func day(
        _ day: PlannedDay, stages: [DayStage], done: Set<String>, nextId: String?, selectedId: String?,
        preview: PlannedDay? = nil, previewStages: [DayStage] = []
    ) -> Scene {
        var scene = Scene()
        if let preview {
            scene.lines += legs(day, done: done, nextId: nil).filter { $0.style != travelled }.map { Line(points: $0.points, style: ghost) }
            let previewNext = preview.stops.first { !done.contains($0.id) && $0.kind != .stay }?.id
            scene.lines += legs(preview, done: done, nextId: previewNext)
            scene.pins = pins(preview, stages: previewStages, done: done, nextId: previewNext, selectedId: selectedId)
            scene.frame = framePoints(preview) + framePoints(day)
            return scene
        }
        scene.lines = legs(day, done: done, nextId: nextId)
        scene.pins = pins(day, stages: stages, done: done, nextId: nextId, selectedId: selectedId)
        scene.frame = framePoints(day)
        return scene
    }

    /// Every leg as a line. A leg whose end has no place (a meal not yet
    /// given one) is bridged: the last placed stop to the next, as a guess.
    static func legs(_ day: PlannedDay, done: Set<String>, nextId: String?) -> [Line] {
        var out: [Line] = []
        let stops = day.stops
        var lastPlaced: Int? = stops.first?.location == nil ? nil : 0
        guard stops.count > 1 else { return out }
        for i in 1..<stops.count {
            let to = stops[i]
            guard let b = to.location else { continue }
            defer { lastPlaced = i }
            guard let from = lastPlaced, let a = stops[from].location else { continue }
            let travelledLeg = done.contains(to.id)
            let leg = from == i - 1 ? day.leg(before: i) : nil
            if let leg, let line = leg.line, line.count > 1 {
                out.append(Line(points: line, style: travelledLeg ? travelled : legStyle(leg.mode, next: to.id == nextId)))
            } else if a != b {
                out.append(Line(points: [a, b], style: travelledLeg ? travelled : guess))
            }
        }
        return out
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
                        top: isPicked
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
                top: isNext || isPicked
            ))
        }
        return out
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

    static func framePoints(_ day: PlannedDay) -> [TripLatLng] {
        day.stops.compactMap(\.location) + day.legs.flatMap { $0.line ?? [] }
    }

    // MARK: The whole trip

    /// Every day on one map: each in its colour, its first visit wearing the
    /// day's number (tap it to open the day), the other visits as dots, and
    /// the stays. Pin ids are the days' dates.
    static func overview(_ days: [PlannedDay], stays: [TripStay]) -> Scene {
        var scene = Scene()
        for (d, day) in days.enumerated() {
            let color = dayColor(d)
            for line in legs(day, done: [], nextId: nil) {
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
                    badge: k == 0 ? Badge(glyph: .number(d + 1), fill: color, size: 30) : Badge(glyph: .dot, fill: color, size: 12),
                    top: k == 0
                ))
            }
            scene.frame += framePoints(day)
        }
        for stay in stays {
            scene.pins.append(Pin(id: "stay:\(stay.id)", at: stay.location, badge: Badge(glyph: .symbol("bed.double.fill"), fill: ink, size: 28), top: true))
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

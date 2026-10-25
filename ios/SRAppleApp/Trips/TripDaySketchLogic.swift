import Foundation

// v8.1: the day's route as a sketch for the planning home's day rows (plan
// §5.3, mockup 4b's map thumbnails) — no tiles, no network, so it draws the
// same offline in Rome as at home. This file is the geometry: the day's
// located stops placed in a unit square, north up, keeping the shape (one
// degree of longitude is shorter than one of latitude away from the equator),
// with a margin so no dot sits on the edge.
//
// Foundation only: compiled and tested on Linux with the solver port.

struct TripSketchPoint: Equatable {
    /// 0…1 across, 0…1 down (north at the top).
    var x: Double
    var y: Double
    /// A `DayStage` raw value, or nil (the stay, a journey).
    var stage: String?
    var isStay: Bool
}

enum TripDaySketchLogic {
    /// The day's located stops in order, placed in a unit square with `margin`.
    /// Fewer than two distinct places → [] (a dot is not a route; the row
    /// keeps its numbered disc).
    static func points(_ day: PlannedDay, margin: Double = 0.14) -> [TripSketchPoint] {
        let located = day.stops.compactMap { s -> (TripLatLng, PlannedStop)? in s.location.map { ($0, s) } }
        guard located.count >= 2 else { return [] }
        let lats = located.map { $0.0.lat }
        let lngs = located.map { $0.0.lng }
        let midLat = (lats.min()! + lats.max()!) / 2
        // Longitude shrinks with latitude: scale it so the sketch keeps the city's shape.
        let kx = cos(midLat * .pi / 180)
        let xs = lngs.map { $0 * kx }
        let spanX = xs.max()! - xs.min()!
        let spanY = lats.max()! - lats.min()!
        let span = max(spanX, spanY)
        guard span > 1e-6 else { return [] }
        let inner = 1 - 2 * margin
        // Centre the shorter side.
        let offX = (span - spanX) / 2
        let offY = (span - spanY) / 2
        return located.enumerated().map { i, pair in
            let (at, stop) = pair
            let x = margin + inner * ((xs[i] - xs.min()!) + offX) / span
            let y = margin + inner * ((lats.max()! - at.lat) + offY) / span
            return TripSketchPoint(x: x, y: y, stage: stop.stage, isStay: stop.kind == .stay)
        }
    }
}

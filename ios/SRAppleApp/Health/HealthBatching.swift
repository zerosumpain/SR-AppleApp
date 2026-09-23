import Foundation

enum HealthBatching {
    static let routeChunk = 2000   // == ROUTE_POINT_LIMIT on the server
    static let seriesChunk = 5000  // == SERIES_POINT_LIMIT
    static let plainPerBatch = 400 // under the server's 500, leaving room for deletions

    static func chunks(kind: String, workout: String, metric: String?, unit: String?, points: [[Double?]], source: String, size: Int) -> [HealthRecord] {
        stride(from: 0, to: points.count, by: size).enumerated().map { index, offset in
            let slice = Array(points[offset..<min(offset + size, points.count)])
            let first = Date(timeIntervalSince1970: slice.first?[0] ?? 0), last = Date(timeIntervalSince1970: slice.last?[0] ?? 0)
            let id = metric.map { "series:\(workout):\($0):\(index)" } ?? "route:\(workout):\(index)"
            var r = HealthRecord(id: id, kind: kind, start: timestamp(first), end: timestamp(last), source: source)
            r.workout = workout; r.metric = metric; r.unit = unit; r.chunk = index; r.points = slice
            return r
        }
    }

    /// One route point in the server's bounds, or nil to drop it. A position
    /// out of range drops the point; an out-of-range altitude, speed or
    /// accuracy (CoreLocation's -1 = unknown, or a wild reading) becomes nil.
    /// One bad point would otherwise get the whole batch refused, forever.
    static func routePoint(epoch: Double, latitude: Double, longitude: Double, altitude: Double?, speed: Double?, accuracy: Double?) -> [Double?]? {
        guard epoch.isFinite, epoch > 1e9, latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        func within(_ x: Double?, _ range: ClosedRange<Double>) -> Double? {
            guard let x, x.isFinite, range.contains(x) else { return nil }
            return x
        }
        let point: [Double?] = [epoch.rounded(), latitude, longitude, within(altitude, -500...9000), within(speed, 0...400), within(accuracy, 0...10000)]
        return point
    }

    /// One series point in the server's bounds, or nil to drop it.
    static func seriesPoint(epoch: Double, value: Double) -> [Double?]? {
        guard epoch.isFinite, epoch > 1e9, value.isFinite, abs(value) <= 1e6 else { return nil }
        let point: [Double?] = [epoch.rounded(), value]
        return point
    }

    static func batches(_ records: [HealthRecord]) -> [UploadBatch] {
        let parts = records.filter { $0.points != nil }, plain = records.filter { $0.points == nil }
        let plainBatches = stride(from: 0, to: plain.count, by: plainPerBatch).map { UploadBatch(health: Array(plain[$0..<min($0 + plainPerBatch, plain.count)])) }
        return plainBatches + parts.map { UploadBatch(health: [$0]) }
    }
}

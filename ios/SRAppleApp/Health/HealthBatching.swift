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

    static func batches(_ records: [HealthRecord]) -> [UploadBatch] {
        let parts = records.filter { $0.points != nil }, plain = records.filter { $0.points == nil }
        let plainBatches = stride(from: 0, to: plain.count, by: plainPerBatch).map { UploadBatch(health: Array(plain[$0..<min($0 + plainPerBatch, plain.count)])) }
        return plainBatches + parts.map { UploadBatch(health: [$0]) }
    }
}

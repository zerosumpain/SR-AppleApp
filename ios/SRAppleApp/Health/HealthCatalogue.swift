import Foundation

/// The pilot server's catalogue (server/health-catalogue.json), bundled as a
/// resource. Groups, units and bounds live THERE; this file only reads them.
struct HealthCatalogueFile: Decodable {
    struct Group: Decodable { let label: String; let kinds: [String] }
    struct Kind: Decodable { let shape: String; let unit: String?; let min: Double?; let max: Double? }
    let groups: [String: Group]
    let legacyKinds: [String: String]
    let kinds: [String: Kind]
    let series: [String: String]
}

enum HealthCatalogue {
    static let file: HealthCatalogueFile = {
        guard let url = Bundle.main.url(forResource: "health-catalogue", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(HealthCatalogueFile.self, from: data)
        else { fatalError("health-catalogue.json is missing from the bundle — see project.yml") }
        return file
    }()

    /// Toggle order on the settings screen.
    static let groupOrder = ["activity", "heart", "vitals", "fitness", "workouts", "sleep", "mobility", "body", "lifestyle"]

    static func label(forGroup group: String) -> String { file.groups[group]?.label ?? group }

    static func kinds(inGroups groups: [String]) -> [String] {
        groupOrder.filter(groups.contains).flatMap { file.groups[$0]?.kinds ?? [] }
    }

    /// A pre-catalogue install stored per-kind toggles ("heart_rate"); map
    /// each to its group, keep anything that is already a group, in toggle order.
    static func migrate(_ enabled: [String]) -> [String] {
        let groups = Set(enabled.compactMap { file.groups[$0] != nil ? $0 : file.legacyKinds[$0] })
        return groupOrder.filter(groups.contains)
    }

    /// The server's rule, applied before a record is queued. A record the
    /// server would refuse is dropped here, because a refused batch is retried
    /// forever and holds every later upload behind it.
    static func accepts(_ r: HealthRecord, now: Date = Date()) -> Bool {
        guard let spec = file.kinds[r.kind] else { return false }
        // The server refuses an end more than five minutes ahead, or before the start.
        guard let start = parseTimestamp(r.start), let end = parseTimestamp(r.end),
              end >= start, end.timeIntervalSince(now) <= 300 else { return false }
        switch spec.shape {
        case "sample", "hourly", "event", "daily", "workout":
            guard let value = r.value, value.isFinite, let lo = spec.min, let hi = spec.max else { return false }
            return value >= lo && value <= hi && r.unit == spec.unit
        default:
            return true
        }
    }
}

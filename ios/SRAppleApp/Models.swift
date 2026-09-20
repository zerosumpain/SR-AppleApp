import Foundation

struct HealthRecord: Codable, Identifiable {
    var id: String
    var kind: String
    var start: String
    var end: String
    var value: Double?
    var unit: String?
    var source: String
    var stage: String?
    var activity: String?
    var distance: Double?
    var energy: Double?
}
struct LocationRecord: Codable, Identifiable {
    var id: String = UUID().uuidString
    var recorded: String
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var speed: Double
    var moving: Bool
}
struct UploadBatch: Codable, Identifiable {
    var id = UUID()
    var health: [HealthRecord] = []
    var locations: [LocationRecord] = []
    var deleted: [String] = []
    enum CodingKeys: String, CodingKey { case health, locations, deleted }
}
struct Profile: Codable { var id: String; var name: String; var sharing: Bool }
struct FamilyMember: Codable, Identifiable {
    var id: String
    var name: String
    var sharing: Bool
    var location: LocationRecord?
}
struct FamilyResponse: Codable { var members: [FamilyMember] }
struct HealthResponse: Codable { var records: [HealthRecord] }
func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

/// The complete outbox and HealthKit anchors are replaced atomically together.
struct PersistedState: Codable {
    var batches: [UploadBatch] = []
    var anchors: [String: Data] = [:]
    var healthEnabled: [String] = []
    var sharing = false
    var lastUpload: Date?
    var historyStart = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
}
@MainActor final class Outbox: ObservableObject {
    @Published private(set) var state: PersistedState
    private let url: URL
    init(url: URL? = nil) throws {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.url = url ?? directory.appendingPathComponent("sync-state.json")
        try FileManager.default.createDirectory(at: self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: self.url.path) {
            state = try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: self.url))
        } else { state = PersistedState() }
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        var dir = self.url.deletingLastPathComponent(); try dir.setResourceValues(resource)
    }
    func change(_ transform: (inout PersistedState) throws -> Void) throws {
        var next = state; try transform(&next)
        let data = try JSONEncoder().encode(next)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        state = next
    }
    func clear() throws { try change { $0 = PersistedState() } }
}

/// Upload cadence is separate from Core Location's sensor/update frequency.
struct MovementPolicy {
    private(set) var moving = false
    private var lastMovement: Date?
    private var lastRecorded: Date?
    mutating func shouldRecord(at time: Date, speed: Double, distance: Double, accuracy: Double) -> Bool {
        guard accuracy >= 0, accuracy <= 100 else { return false }
        let wasMoving = moving
        if speed >= 0.8 || distance > max(30, accuracy * 2) { moving = true; lastMovement = time }
        else if let lastMovement, time.timeIntervalSince(lastMovement) >= 180 { moving = false }
        let interval: TimeInterval = moving ? 30 : 600
        guard lastRecorded == nil || wasMoving != moving || time.timeIntervalSince(lastRecorded!) >= interval else { return false }
        lastRecorded = time
        return true
    }
}

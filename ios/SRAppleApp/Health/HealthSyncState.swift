import Foundation

/// Collection checkpoints are committed in the same transaction as their data.
struct HealthSyncState: Codable {
    var paused = false
    var wifiOnly = true
    var automaticEfficiency = false
    var historyDays = 30
    var nextJob = 0
    var recentStart: Date?
    var recentComplete: [String] = []
    var historyComplete: [String] = []
    var enabledSince: Date?
    var lastCollected: Date?
    var lastHealthUpload: Date?
    var lastLocationUpload: Date?
    var workoutParts: [String: Int]? = nil
    var refused: [String: String] = [:]
}

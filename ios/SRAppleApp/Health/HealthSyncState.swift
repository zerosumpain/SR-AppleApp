import Foundation

/// Collection checkpoints are committed in the same transaction as their data.
struct HealthSyncState: Codable {
    var paused = false
    var wifiOnly = true
    var automaticEfficiency = false
    var historyDays = 30
    var nextJob = 0
    var recentStart: Date?
    var historyStarts: [String: Date]?
    var recentStarts: [String: Date]?
    var recentComplete: [String] = []
    var historyComplete: [String] = []
    var enabledSince: Date?
    var lastCollected: Date?
    var lastHealthUpload: Date?
    var lastLocationUpload: Date?
    var workoutParts: [String: Int]? = nil
    var refused: [String: String] = [:]
    /// A new or re-enabled category gets the selected window from today.
    /// Existing cursors retain the predicate they were originally created for.
    mutating func prepareWindow(kind: String, legacyHistoryStart: Date, hasHistoryCursor: Bool, hasRecentCursor: Bool, now: Date = Date()) {
        if historyStarts == nil { historyStarts = [:] }
        if recentStarts == nil { recentStarts = [:] }
        if historyStarts?[kind] == nil {
            historyStarts?[kind] = hasHistoryCursor ? legacyHistoryStart
                : Calendar.current.date(byAdding: .day, value: -historyDays, to: now)!
        }
        if recentStarts?[kind] == nil {
            recentStarts?[kind] = hasRecentCursor ? (recentStart ?? now.addingTimeInterval(-48 * 3600))
                : now.addingTimeInterval(-48 * 3600)
        }
    }
}


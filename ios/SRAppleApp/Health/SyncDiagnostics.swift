import Foundation

/// Deliberately excludes record IDs, Health values, locations and credentials.
enum SyncDiagnostics {
    static func report(_ state: PersistedState, now: Date = Date()) -> String {
        func date(_ value: Date?) -> String { value.map { ISO8601DateFormatter().string(from: $0) } ?? "none" }
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        return """
        Strange Ramblings sync diagnostics
        App: \(version) (\(build))
        Generated: \(date(now))
        Queue batches: \(state.batches.count)
        Health records: \(state.batches.reduce(0) { $0 + $1.health.count + $1.deleted.count })
        Location records: \(state.batches.reduce(0) { $0 + $1.locations.count })
        Refused batches retained: \(state.sync.refused.count)
        Import paused: \(state.sync.paused)
        Wi-Fi only bulk uploads: \(state.sync.wifiOnly)
        Automatic efficiency: \(state.sync.automaticEfficiency)
        History days: \(state.sync.historyDays)
        Last collection pass: \(date(state.sync.lastCollected))
        Last accepted Health upload: \(date(state.sync.lastHealthUpload))
        Last accepted location upload: \(date(state.sync.lastLocationUpload))
        Website processing completion is separate from upload acceptance.
        """
    }
}

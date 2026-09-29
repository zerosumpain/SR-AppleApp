import Foundation
import Combine
import SQLite3

/// The main actor only prepares mutations and publishes committed state. Disk
/// work runs on its own actor; a transaction always stores records and anchors
/// together. Serial admission prevents a suspended write overwriting a setting.
@MainActor final class Outbox: ObservableObject {
    @Published private(set) var state: PersistedState
    private let storage: OutboxStorage
    private var writing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(url: URL? = nil) throws {
        let opened = try OutboxStorage.open(url: url)
        state = opened.state
        storage = opened.storage
    }

    private init(state: PersistedState, storage: OutboxStorage) {
        self.state = state; self.storage = storage
    }

    /// Cold launch does not decode an offline queue on the UI thread.
    static func open(url: URL? = nil) async throws -> Outbox {
        let opened = try await Task.detached(priority: .utility) { try OutboxStorage.open(url: url) }.value
        return Outbox(state: opened.state, storage: opened.storage)
    }

    private func enter() async {
        if writing { await withCheckedContinuation { waiters.append($0) } }
        else { writing = true }
    }

    private func leave() {
        if waiters.isEmpty { writing = false } else { waiters.removeFirst().resume() }
    }

    func change(persist: Bool = true, _ transform: (inout PersistedState) throws -> Void) async throws {
        await enter()
        defer { leave() }
        var next = state
        try transform(&next)
        let health = next.batches.reduce(0) { $0 + $1.health.count + $1.deleted.count }
        let total = health + next.batches.reduce(0) { $0 + $1.locations.count }
        // Leave room for location even when a Health backfill is offline.
        let oldHealth = state.batches.reduce(0) { $0 + $1.health.count + $1.deleted.count }
        let oldTotal = oldHealth + state.batches.reduce(0) { $0 + $1.locations.count }
        guard health <= 45_000 || health <= oldHealth, total <= 50_000 || total <= oldTotal else { throw CompanionError.message(outboxFullMessage) }
        // `persist` remains source-compatible with the former deferred writes.
        // Small SQLite transactions make every acknowledgement durable now.
        try await storage.write(next)
        state = next
    }

    func persistIfDirty() async throws {
        await enter(); leave() // all admitted writes are durable already
    }

    func clear() async throws {
        try await change { let kept = $0.connections; $0 = PersistedState(); $0.connections = kept }
    }
}

/// One protected SQLite file, with changed batches stored independently. Large
/// route payloads are never re-encoded because a battery reading changed.
actor OutboxStorage {
    struct Opened { let state: PersistedState; let storage: OutboxStorage }
    private let db: OpaquePointer
    private var previous: PersistedState
    private var sizes: [UUID: Int]
    static let healthByteLimit = 48 * 1024 * 1024
    static let byteLimit = 64 * 1024 * 1024

    private init(db: OpaquePointer, state: PersistedState, sizes: [UUID: Int]) {
        self.db = db; previous = state; self.sizes = sizes
    }
    deinit { sqlite3_close(db) }

    nonisolated static func open(url: URL?) throws -> Opened {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = url ?? directory.appendingPathComponent("sync-state.json")
        let file = legacy.appendingPathExtension("sqlite")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        var parent = file.deletingLastPathComponent(); try parent.setResourceValues(resource)
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(file.path, &pointer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let db = pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw CompanionError.message("Saved sync data could not be opened.")
        }
        do {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            // DELETE journal keeps file protection simple, including recovery
            // after first unlock; transactions contain only changed payloads.
            try exec(db, "PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS batches (id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL, payload BLOB NOT NULL)")
            var state: PersistedState
            let metadata = try rows(db, "SELECT payload FROM state WHERE id=1")
            if let data = metadata.first?.last {
                state = try JSONDecoder().decode(PersistedState.self, from: data)
            } else {
                state = FileManager.default.fileExists(atPath: legacy.path)
                    ? try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: legacy)) : PersistedState()
                try store(db, state: state, previous: PersistedState())
                // Keep the original JSON as the migration recovery source.
            }
            state.batches = try rows(db, "SELECT id,payload FROM batches ORDER BY ordinal").map { row in
                var batch = try JSONDecoder().decode(UploadBatch.self, from: row[1])
                guard let id = UUID(uuidString: String(decoding: row[0], as: UTF8.self)) else { throw CompanionError.message("Saved upload identity is invalid.") }
                batch.id = id
                return batch
            }
            let sizes = try Dictionary(uniqueKeysWithValues: state.batches.map { ($0.id, try JSONEncoder().encode($0).count) })
            if FileManager.default.fileExists(atPath: legacy.path) { try FileManager.default.removeItem(at: legacy) }
            return Opened(state: state, storage: OutboxStorage(db: db, state: state, sizes: sizes))
        } catch { sqlite3_close(db); throw error }
    }

    func write(_ state: PersistedState) throws {
        let old = Dictionary(uniqueKeysWithValues: previous.batches.map { ($0.id, $0) })
        var nextSizes: [UUID: Int] = [:]
        var healthBytes = 0, bytes = 0
        for batch in state.batches {
            let size = old[batch.id] == batch ? (sizes[batch.id] ?? 0) : try JSONEncoder().encode(batch).count
            nextSizes[batch.id] = size; bytes += size
            if !batch.health.isEmpty || !batch.deleted.isEmpty { healthBytes += size }
        }
        guard bytes <= Self.byteLimit || bytes <= sizes.values.reduce(0, +) else { throw CompanionError.message(outboxFullMessage) }
        let previousHealth = previous.batches.filter { !$0.health.isEmpty || !$0.deleted.isEmpty }.reduce(0) { $0 + (sizes[$1.id] ?? 0) }
        guard healthBytes <= Self.healthByteLimit || healthBytes <= previousHealth else { throw CompanionError.message(outboxFullMessage) }
        try Self.store(db, state: state, previous: previous)
        previous = state; sizes = nextSizes
    }

    private nonisolated static func store(_ db: OpaquePointer, state: PersistedState, previous: PersistedState) throws {
        var metadata = state; metadata.batches = []
        let payload = try JSONEncoder().encode(metadata)
        let old = Dictionary(uniqueKeysWithValues: previous.batches.enumerated().map { ($0.element.id, ($0.offset, $0.element)) })
        let kept = Set(state.batches.map(\.id))
        try exec(db, "BEGIN IMMEDIATE")
        do {
            try bind(db, "INSERT OR REPLACE INTO state VALUES (1,?)", values: [payload])
            for batch in previous.batches where !kept.contains(batch.id) {
                try bind(db, "DELETE FROM batches WHERE id=?", values: [Data(batch.id.uuidString.utf8)])
            }
            for (index, batch) in state.batches.enumerated() {
                if let prior = old[batch.id], prior.1 == batch {
                    if prior.0 != index { try bind(db, "UPDATE batches SET ordinal=\(index) WHERE id=?", values: [Data(batch.id.uuidString.utf8)]) }
                } else {
                    try bind(db, "INSERT OR REPLACE INTO batches VALUES (?,\(index),?)", values: [Data(batch.id.uuidString.utf8), try JSONEncoder().encode(batch)])
                }
            }
            try exec(db, "COMMIT")
        } catch { try? exec(db, "ROLLBACK"); throw error }
    }

    private nonisolated static func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CompanionError.message("Could not save sync data. Free some storage and retry.") }
    }
    private nonisolated static func bind(_ db: OpaquePointer, _ sql: String, values: [Data]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CompanionError.message("Could not prepare sync storage.") }
        defer { sqlite3_finalize(stmt) }
        for (index, value) in values.enumerated() {
            let result = value.withUnsafeBytes { sqlite3_bind_blob(stmt, Int32(index + 1), $0.baseAddress, Int32(value.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK else { throw CompanionError.message("Could not prepare sync data.") }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw CompanionError.message("Could not save sync data. Free some storage and retry.") }
    }
    private nonisolated static func rows(_ db: OpaquePointer, _ sql: String) throws -> [[Data]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CompanionError.message("Could not read sync storage.") }
        defer { sqlite3_finalize(stmt) }
        var rows: [[Data]] = []
        while true {
            let status = sqlite3_step(stmt)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW else { throw CompanionError.message("Could not read saved sync data.") }
            rows.append((0..<sqlite3_column_count(stmt)).map { Data(bytes: sqlite3_column_blob(stmt, $0), count: Int(sqlite3_column_bytes(stmt, $0))) })
        }
    }
}

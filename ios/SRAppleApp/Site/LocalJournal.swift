import Foundation

/// Small drafts and pending reversible actions. Writes are atomic and run off
/// the UI actor; an action cannot be called "saved" before this returns.
actor LocalJournal {
    static let shared = LocalJournal()
    private var root: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalJournal", isDirectory: true) }
    private func file(_ scope: String, _ key: String) -> URL { root.appendingPathComponent(scope).appendingPathComponent(OfflineSnapshots.digest(key)) }
    func read<T: Decodable>(_ type: T.Type, scope: String, key: String) -> T? {
        guard let data = try? Data(contentsOf: file(scope, key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func save<T: Encodable>(_ value: T, scope: String, key: String) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 1024 * 1024 else { throw SiteError.message("This draft is too large to save on the phone.") }
        let path = file(scope, key)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var directory = root; try directory.setResourceValues(values)
        try data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func remove(scope: String, key: String) { try? FileManager.default.removeItem(at: file(scope, key)) }
    func clear() { try? FileManager.default.removeItem(at: root) }
}

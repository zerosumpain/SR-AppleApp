import Foundation
import CryptoKit
import Combine

@MainActor final class OfflineSnapshotStatus: ObservableObject {
    static let shared = OfflineSnapshotStatus()
    @Published var message: String?
}

/// Device-protected, bounded, credential-and-preview-scoped snapshots. Only
/// explicitly selected read endpoints use this cache; permissions, maps and
/// actions must always ask the server. Tokens never appear in files or names.
actor OfflineSnapshots {
    static let shared = OfflineSnapshots()
    struct Entry: Codable { let data: Data; let savedAt: Date; let etag: String? }
    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OfflineSnapshots", isDirectory: true)
    }
    nonisolated static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    nonisolated static func allowed(_ path: String) -> Bool {
        let route = path.split(separator: "?").first.map(String.init) ?? path
        return route == "api/native/today" || route == "api/native/health" || route.hasPrefix("api/native/health/") || route == "api/native/news" || route.hasPrefix("api/native/news/story/")
    }
    nonisolated static func normalized(_ path: String) -> String {
        guard var parts = URLComponents(string: path) else { return path }
        parts.queryItems = parts.queryItems?.filter { $0.name != "fresh" }.sorted { $0.name < $1.name }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        return parts.string ?? path
    }
    private func file(scope: String, path: String) -> URL { directory.appendingPathComponent(scope).appendingPathComponent(Self.digest(Self.normalized(path)) + ".json") }
    func read(scope: String, path: String) -> Entry? {
        guard let data = try? Data(contentsOf: file(scope: scope, path: path)), let entry = try? JSONDecoder().decode(Entry.self, from: data), Date().timeIntervalSince(entry.savedAt) < 7 * 86400 else { return nil }
        return entry
    }
    func save(_ data: Data, scope: String, path: String, etag: String?) throws {
        guard data.count <= 2 * 1024 * 1024 else { return }
        let url = file(scope: scope, path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var root = directory; try root.setResourceValues(values)
        let encoded = try JSONEncoder().encode(Entry(data: data, savedAt: Date(), etag: etag))
        try encoded.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        prune()
    }
    func erase(scope: String) { try? FileManager.default.removeItem(at: directory.appendingPathComponent(scope)) }
    func eraseAll() { try? FileManager.default.removeItem(at: directory) }
    private func prune() {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]) else { return }
        var files: [(URL, Int, Date)] = []
        for case let url as URL in enumerator {
            guard let value = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]), value.isRegularFile == true else { continue }
            files.append((url, value.fileSize ?? 0, value.contentModificationDate ?? .distantPast))
        }
        var size = files.reduce(0) { $0 + $1.1 }
        for (url, bytes, date) in files.sorted(by: { $0.2 < $1.2 }) where size > 32 * 1024 * 1024 || Date().timeIntervalSince(date) > 7 * 86400 {
            try? FileManager.default.removeItem(at: url); size -= bytes
        }
    }
}

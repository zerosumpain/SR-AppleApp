import Foundation
import UIKit

/// One folder of one space, as the site answers it, and the writes made in it.
///
/// One model per screen (each folder is its own pushed screen), so going back
/// up shows the parent as it was and a pull refreshes only what is in view.
@MainActor
final class DriveFolderModel: ObservableObject {
    /// What is on screen. Changes only at the top of Drive, between the two spaces.
    @Published private(set) var ref: DriveRef
    @Published private(set) var listing: DriveListing?
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    /// "Adding 2 of 5…" while an upload runs; nil otherwise.
    @Published private(set) var progress: String?
    @Published var message: String?
    /// The file being fetched for a preview, so its row can show a spinner.
    @Published private(set) var opening: String?

    init(ref: DriveRef) {
        self.ref = ref
    }

    /// Show another space at the top of Drive: the old listing goes at once,
    /// so a moment of the other space's files is never mistaken for this one's.
    func show(_ next: DriveRef) async {
        ref = next
        listing = nil
        loaded = false
        message = nil
        await load()
    }

    var maxUpload: Int { listing?.maxUploadBytes ?? DriveLogic.defaultMaxUpload }

    func load() async {
        guard SiteClient.shared.isPaired else {
            loaded = true
            message = SiteError.unpaired.errorDescription
            return
        }
        loading = true
        defer { loading = false; loaded = true }
        let asked = ref
        do {
            let answer: DriveListing = try await SiteClient.shared.send(DriveLogic.listPath(asked))
            guard asked == ref else { return }
            listing = answer
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    /// Photos from the library or the camera: re-encoded as JPEG (a HEIC
    /// original opens nowhere but on Apple devices) at no more than
    /// `photoMaxEdge` on the long side.
    func addPhotos(_ images: [UIImage]) async {
        let now = Date()
        var files: [(data: Data, name: String, mime: String)] = []
        for (i, image) in images.enumerated() {
            guard let data = Self.jpeg(image) else { continue }
            files.append((data: data, name: DriveLogic.photoName(at: now, index: images.count > 1 ? i : 0), mime: "image/jpeg"))
        }
        if files.count < images.count { message = "A photo could not be read." }
        await upload(files)
    }

    /// Files from the Files app, as they are.
    func addFiles(_ urls: [URL]) async {
        var files: [(data: Data, name: String, mime: String)] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
                if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
            }
            guard let data = try? Data(contentsOf: url) else {
                message = "\(url.lastPathComponent) could not be read."
                continue
            }
            files.append((data: data, name: url.lastPathComponent, mime: ChatUpload.mimeType(for: url)))
        }
        await upload(files)
    }

    /// A video from the library, already loaded.
    func addVideo(_ data: Data, ext: String) async {
        let name = DriveLogic.photoName(at: Date(), index: 0, ext: ext).replacingOccurrences(of: "Photo ", with: "Video ")
        await upload([(data: data, name: name, mime: ext == "mp4" ? "video/mp4" : "video/quicktime")])
    }

    private func upload(_ files: [(data: Data, name: String, mime: String)]) async {
        guard !files.isEmpty else { return }
        var added = 0
        defer { progress = nil }
        for (i, file) in files.enumerated() {
            progress = files.count > 1 ? "Adding \(i + 1) of \(files.count)…" : "Adding…"
            if let refusal = DriveLogic.tooLarge(file.data.count, limit: maxUpload) {
                message = "\(file.name): \(refusal)"
                continue
            }
            do {
                struct Reply: Decodable { let file: DriveFile }
                let _: Reply = try await SiteClient.shared.upload(
                    "api/native/drive/files",
                    file: file.data,
                    filename: file.name,
                    // Always octet-stream on the wire, the real type in `type`:
                    // the site refuses a text/plain POST from a phone as a
                    // cross-site form before any route runs.
                    mimeType: "application/octet-stream",
                    fields: ["space": ref.space.rawValue, "folder": ref.folder, "type": file.mime],
                    timeout: 300
                )
                added += 1
            } catch {
                message = "\(file.name): \(error.localizedDescription)"
            }
        }
        if added > 0 { SRHaptic.ok() }
        await load()
    }

    func makeFolder(_ raw: String) async {
        guard let name = DriveLogic.usableName(raw) else {
            message = "That folder name can't be used."
            return
        }
        struct Body: Encodable { let space: String; let parent: String; let name: String }
        do {
            let body = try JSONEncoder().encode(Body(space: ref.space.rawValue, parent: ref.folder, name: name))
            try await SiteClient.shared.post("api/native/drive/folders", body: body)
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    func delete(_ file: DriveFile) async {
        do {
            try await SiteClient.shared.call("api/native/drive/files/\(file.id)", method: "DELETE")
            DriveCache.forget(file)
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    func delete(_ folder: DriveFolder) async {
        let path = "api/native/drive/folders?space=\(ref.space.rawValue)&folder=\(DriveLogic.escape(folder.path))"
        do {
            try await SiteClient.shared.call(path, method: "DELETE")
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    /// The file on this phone, fetched once per version, for Quick Look and Share.
    func localCopy(of file: DriveFile) async -> URL? {
        if let hit = DriveCache.url(for: file) { return hit }
        opening = file.id
        defer { opening = nil }
        do {
            let data = try await SiteClient.shared.bytes("api/native/drive/files/\(file.id)")
            return try DriveCache.store(data, for: file)
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    nonisolated static func jpeg(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, DriveLogic.photoMaxEdge / longest)
        if scale >= 1 { return image.jpegData(compressionQuality: 0.85) }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

/// Downloaded files, kept in Caches (the system may clear it) under the
/// file's id and version — a changed file is fetched again, an unchanged one
/// opens at once.
enum DriveCache {
    private static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("drive", isDirectory: true)
    }

    private static func folder(for file: DriveFile) -> URL {
        let version = file.updatedAt.filter { $0.isNumber }
        return root.appendingPathComponent("\(file.id)-\(version)", isDirectory: true)
    }

    /// The name on disk: the file's own, which Quick Look and Share show.
    private static func path(for file: DriveFile) -> URL {
        let safe = file.name.replacingOccurrences(of: "/", with: "_")
        return folder(for: file).appendingPathComponent(safe.isEmpty ? "file" : safe)
    }

    static func url(for file: DriveFile) -> URL? {
        let url = path(for: file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func store(_ data: Data, for file: DriveFile) throws -> URL {
        let url = path(for: file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func forget(_ file: DriveFile) {
        try? FileManager.default.removeItem(at: folder(for: file))
    }

    /// Everything — on sign-out, so the next person on this phone finds nothing.
    static func clear() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// Small thumbnails for the photos in a listing, fetched once each per session.
@MainActor
final class DriveThumbnails: ObservableObject {
    static let shared = DriveThumbnails()
    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: Set<String> = []
    @Published private(set) var revision = 0

    func image(for file: DriveFile) -> UIImage? {
        cache.object(forKey: "\(file.id)-\(file.updatedAt)" as NSString)
    }

    func load(_ file: DriveFile) async {
        let key = "\(file.id)-\(file.updatedAt)"
        guard DriveLogic.isImage(file), cache.object(forKey: key as NSString) == nil,
              !inFlight.contains(key), file.sizeBytes <= 15 * 1024 * 1024 else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        let data: Data
        if let local = DriveCache.url(for: file), let saved = try? Data(contentsOf: local) {
            data = saved
        } else if let fetched = try? await SiteClient.shared.bytes("api/native/drive/files/\(file.id)") {
            data = fetched
            _ = try? DriveCache.store(fetched, for: file)
        } else {
            return
        }
        guard let thumb = await Self.thumbnail(data) else { return }
        cache.setObject(thumb, forKey: key as NSString)
        revision += 1
    }

    nonisolated private static func thumbnail(_ data: Data) async -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return await image.byPreparingThumbnail(ofSize: CGSize(width: 120, height: 120))
    }
}

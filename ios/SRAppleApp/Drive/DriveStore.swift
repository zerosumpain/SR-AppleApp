import Foundation
import PhotosUI
import SwiftUI
import UIKit

/// One folder of one space, as the site answers it, and the writes made in it.
///
/// Uploads go through `DriveUploadQueue` (in the background, from files on
/// disk); this model only queues them and reloads when one lands here.
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
    @Published var message: String?
    /// Good news for the banner: "Saved to Photos."
    @Published var note: String?
    /// "Reading 3 of 40…" while picked photos are read off the library.
    @Published var preparing: String?
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
            DriveUploadQueue.shared.remember(answer)
            guard asked == ref else { return }
            listing = answer
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    /// A photo just taken with the camera: JPEG (a camera `UIImage` carries
    /// no EXIF to keep) at no more than `photoMaxEdge` on the long side,
    /// named for now.
    func addPhotos(_ images: [UIImage]) async {
        let now = Date()
        var unreadable = 0
        for (i, image) in images.enumerated() {
            guard let data = Self.jpeg(image) else { unreadable += 1; continue }
            let name = DriveLogic.photoName(at: now, index: images.count > 1 ? i : 0)
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            do {
                try data.write(to: temp)
            } catch {
                unreadable += 1
                continue
            }
            await queue(temp, consume: true, name: name, mime: "image/jpeg", takenAt: DriveLogic.localISO(now))
        }
        if unreadable > 0 { message = "A photo could not be read." }
    }

    /// Files from the Files app, as they are — copied into the upload queue,
    /// so the system can send them with the app shut.
    func addFiles(_ urls: [URL], into folder: String? = nil) async {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            await queue(url, consume: false, name: url.lastPathComponent, mime: ChatUpload.mimeType(for: url), folder: folder)
            if scoped { url.stopAccessingSecurityScopedResource() }
            if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Photos and videos from the picker, already on disk as files
    /// (`DrivePickedMedia`): sent as they are, or as JPEG with their EXIF
    /// when "Keep originals" is off (`DrivePhotoImport.prepare`).
    func addPicked(_ items: [PhotosPickerItem], keepOriginals: Bool) async {
        let read = await DrivePhotoImport.prepare(items, keepOriginals: keepOriginals) { done, total in
            preparing = total > 1 ? "Reading \(done) of \(total)…" : "Reading…"
        }
        preparing = nil
        if read.failed > 0 { message = read.failed == 1 ? "One couldn't be read." : "\(read.failed) couldn't be read." }
        await addPicked(read.media)
    }

    func addPicked(_ items: [DrivePickedMedia]) async {
        for item in items {
            await queue(item.url, consume: true, name: item.filename, mime: item.mimeType, takenAt: item.takenAt)
        }
    }

    /// One file into the background queue, refusals said on the banner.
    func queue(_ url: URL, consume: Bool, name: String, mime: String, takenAt: String? = nil, assetId: String? = nil,
               folder: String? = nil) async {
        do {
            try await DriveUploadQueue.shared.enqueue(url, consume: consume, space: ref.space, folder: folder ?? ref.folder,
                                                      filename: name, mimeType: mime, takenAt: takenAt,
                                                      assetId: assetId, limits: listing?.limits)
        } catch {
            message = error.localizedDescription
            if consume { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: - Rename, move, delete

    /// A new name, in the same folder. The site answers 409 "That name is
    /// taken here." for a clash, said as it is.
    func rename(_ file: DriveFile, to raw: String) async {
        guard let name = DriveLogic.usableName(raw) else {
            message = "That name can't be used."
            return
        }
        guard name != file.name else { return }
        await change(file, DriveFileChange(space: ref.space.rawValue, name: name))
    }

    /// Into another folder of the same space ("" for its top).
    func move(_ file: DriveFile, to folder: String) async {
        await change(file, DriveFileChange(space: ref.space.rawValue, folder: folder))
    }

    /// A file dragged onto a folder: only its id is known.
    func moveFile(id: String, to folder: String) async {
        do {
            let _: DriveAPI.Changed = try await SiteClient.shared.send(
                DriveLogic.filePath(id), method: "PATCH",
                body: try JSONEncoder().encode(DriveFileChange(space: ref.space.rawValue, folder: folder))
            )
            SRHaptic.ok()
        } catch {
            message = error.localizedDescription
        }
        await load()
    }

    func move(_ files: [DriveFile], to folder: String) async {
        for file in files { await change(file, DriveFileChange(space: ref.space.rawValue, folder: folder), reload: false) }
        await load()
    }

    func delete(_ files: [DriveFile]) async {
        for file in files where file.canDelete {
            do {
                try await SiteClient.shared.call(DriveLogic.filePath(file.id), method: "DELETE")
                DriveCache.forget(file)
            } catch {
                message = "\(file.name): \(error.localizedDescription)"
            }
        }
        await load()
    }

    private func change(_ file: DriveFile, _ body: DriveFileChange, reload: Bool = true) async {
        do {
            let _: DriveAPI.Changed = try await SiteClient.shared.send(
                DriveLogic.filePath(file.id), method: "PATCH", body: try JSONEncoder().encode(body)
            )
            DriveCache.forget(file)
            SRHaptic.ok()
        } catch {
            message = "\(file.name): \(error.localizedDescription)"
        }
        if reload { await load() }
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
            try await SiteClient.shared.call(DriveLogic.filePath(file.id), method: "DELETE")
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
            let data = try await SiteClient.shared.bytes(DriveLogic.filePath(file.id))
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
        DriveImageLoader.forget(id: file.id)
    }

    /// The site's preview JPEGs for tiles and the viewer (`DriveImageLoader`):
    /// beside the downloads, so sign-out's `clear` takes them too. Never the
    /// originals — a tile is drawn from a ~30 KB preview, not a 15 MB photo.
    static var previewsFolder: URL {
        root.appendingPathComponent(".previews", isDirectory: true)
    }

    /// Everything — on sign-out, so the next person on this phone finds
    /// nothing, on disk or decoded in memory.
    static func clear() {
        try? FileManager.default.removeItem(at: root)
        SRImageMemory.drive.removeAll()
        SRImageMemory.driveViews.removeAll()
    }
}

/// The site's Drive calls that are about one file rather than a folder.
@MainActor
enum DriveAPI {
    struct Changed: Decodable { let file: DriveFile }

    /// One folder, for the Move… picker: nil when it would not open.
    static func listing(space: DriveSpace, folder: String) async -> DriveListing? {
        do {
            let listing: DriveListing = try await SiteClient.shared.send(DriveLogic.listPath(DriveRef(space: space, folder: folder)))
            return listing
        } catch {
            return nil
        }
    }

    static func meta(_ ref: DriveFileRef) async throws -> DriveFileMeta {
        try await SiteClient.shared.send(DriveLogic.metaPath(ref))
    }

    /// Names across the whole space, and — for the owner in My files —
    /// what the files say. Nil for a search the site would refuse.
    static func search(_ query: String, space: DriveSpace) async throws -> DriveSearchResults? {
        guard let path = DriveLogic.searchPath(space: space, query: query) else { return nil }
        let found: DriveSearchResults = try await SiteClient.shared.send(path, timeout: 25)
        return found
    }

    /// jkai's summary of a file: kept by the site, so only `refresh` asks again.
    static func analyse(_ id: String, refresh: Bool = false) async throws -> FileAnalysis {
        struct Body: Encodable { let refresh: Bool }
        return try await SiteClient.shared.send(
            DriveLogic.filePath(id, "analyse"), method: "POST", body: try JSONEncoder().encode(Body(refresh: refresh)),
            timeout: 130
        )
    }

    /// "Extract entities": the file into the knowledge graph, queued.
    static func extractEntities(_ id: String) async throws -> DriveIntelJob {
        try await SiteClient.shared.send(DriveLogic.filePath(id, "intel"), method: "POST", body: Data("{}".utf8), timeout: 80)
    }

    static func intelStatus(_ id: String, job: Int?) async throws -> DriveIntelState {
        let path = DriveLogic.filePath(id, "intel") + (job.map { "?job=\($0)" } ?? "")
        return try await SiteClient.shared.send(path)
    }

    /// Ask, wait two seconds, ask again — until it settles or two minutes pass.
    static func extractAndWait(_ id: String, update: (DriveIntelState) -> Void) async throws -> DriveIntelState {
        let job = try await extractEntities(id)
        var last = DriveIntelState(status: "pending", outcome: nil, entityCount: nil, attempts: nil, error: nil)
        update(last)
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            last = try await intelStatus(id, job: job.jobId)
            update(last)
            if DriveLogic.intelSettled(last.status) { break }
        }
        return last
    }
}

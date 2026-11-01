import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// One photo or video picked for Drive, already a file on disk.
struct DrivePickedMedia: Equatable {
    let url: URL
    let filename: String
    let mimeType: String
    /// When it was taken, as the phone's wall clock with its offset.
    let takenAt: String?
}

/// What the picker hands over: the file itself, copied out of the system's
/// temporary place before it goes. A `FileRepresentation`, so a film is never
/// loaded into memory — the old `Data` load held a whole video in RAM.
struct DrivePickedFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            try DrivePickedFile(url: DrivePhotoImport.keep(received.file))
        }
        FileRepresentation(importedContentType: .image) { received in
            try DrivePickedFile(url: DrivePhotoImport.keep(received.file))
        }
    }
}

/// Photos into Drive: picked a few at a time, or moved off the phone in bulk.
///
/// Originals go as they are (HEIC, with where and when they were taken) unless
/// "Keep originals" is off, when each is re-encoded as JPEG through ImageIO —
/// which keeps the EXIF, unlike `UIImage.jpegData`.
enum DrivePhotoImport {
    /// The picker's ceiling.
    static let pickLimit = 100
    /// One "Move from phone" run at most: the rest wait for the next.
    static let moveLimit = 300
    /// `@AppStorage` key: send HEIC originals (on) or JPEG copies.
    static let keepOriginalsKey = "drive.keepOriginals"

    /// Read what the picker chose, one file at a time. `progress` is told
    /// "3 of 40" as it goes.
    @MainActor
    static func prepare(_ items: [PhotosPickerItem], keepOriginals: Bool,
                        progress: (Int, Int) -> Void) async -> (media: [DrivePickedMedia], failed: Int) {
        var out: [DrivePickedMedia] = []
        var failed = 0
        for (i, item) in items.enumerated() {
            progress(i + 1, items.count)
            guard let picked = try? await item.loadTransferable(type: DrivePickedFile.self) else {
                failed += 1
                continue
            }
            let fallback = item.itemIdentifier.flatMap { DrivePhotoImport.creationDate(of: $0) }
            let file = picked.url
            let media = await Task.detached(priority: .utility) {
                DrivePhotoImport.describe(file, keepOriginals: keepOriginals, fallbackDate: fallback)
            }.value
            out.append(media)
        }
        return (out, failed)
    }

    /// The name, type and taken-at of one file, converting a HEIC to JPEG
    /// first when originals are not kept.
    nonisolated static func describe(_ url: URL, keepOriginals: Bool, fallbackDate: Date?) -> DrivePickedMedia {
        var file = url
        let type = UTType(filenameExtension: url.pathExtension)
        let isImage = type?.conforms(to: .image) ?? false
        let taken = isImage ? takenAt(file) : nil
        if isImage, !keepOriginals, let type, type.conforms(to: .heic) || type.conforms(to: .heif),
           let jpeg = jpegKeepingMetadata(file) {
            try? FileManager.default.removeItem(at: file)
            file = jpeg
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return DrivePickedMedia(url: file, filename: file.lastPathComponent, mimeType: mime,
                                takenAt: taken ?? fallbackDate.map { DriveLogic.localISO($0) })
    }

    /// The system's copy goes when the import closure returns: keep our own,
    /// under its own name, in a folder of its own so two `IMG_0001`s never meet.
    nonisolated static func keep(_ file: URL) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drive-picked", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(file.lastPathComponent.isEmpty ? "file" : file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: target)
        return target
    }

    /// EXIF `DateTimeOriginal` (and its offset), as a `takenAt`.
    nonisolated static func takenAt(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] else { return nil }
        return DriveLogic.takenAt(
            exif: exif[kCGImagePropertyExifDateTimeOriginal as String] as? String,
            offset: exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String
        )
    }

    /// A JPEG beside the original, metadata and all, no larger than
    /// `photoMaxEdge` on its long side. Nil if ImageIO could not.
    nonisolated static func jpegKeepingMetadata(_ input: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else { return nil }
        let output = input.deletingPathExtension().appendingPathExtension("jpg")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: 0.85,
            kCGImageDestinationImageMaxPixelSize as String: Int(DriveLogic.photoMaxEdge),
        ]
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            return nil
        }
        return output
    }

    /// When the library says a picked item was taken — only readable when
    /// the library is open to the app; nil otherwise, and the EXIF decides.
    nonisolated static func creationDate(of localIdentifier: String) -> Date? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject?.creationDate
    }

    // MARK: - Save to Photos (add-only)

    /// A Drive photo or film into the phone's library. Asks for add-only
    /// access, which never lets the app read the library.
    @MainActor
    static func saveToPhotos(_ file: URL, isVideo: Bool) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SiteError.message("Photos access is off for SR. Turn it on in Settings to save here.")
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request: PHAssetChangeRequest?
            if isVideo {
                request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: file)
            } else {
                request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: file)
            }
            _ = request
        }
    }
}

/// "Move from phone": photos and videos from a stretch of days, or an
/// album, copied to a Drive folder through the upload queue — and then, once
/// the site has said it holds each one (a 201, or a 200 with
/// `duplicate: true`), offered for removal from the phone in one go, which
/// the system confirms itself. Nothing is ever removed that the ledger does
/// not hold as safely stored.
@MainActor
final class DriveMoveFromPhone: ObservableObject {
    struct Album: Identifiable, Hashable {
        let id: String
        let title: String
    }

    @Published private(set) var access: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var albums: [Album] = []
    @Published var album: String? = nil { didSet { count() } }
    @Published var from: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date() { didSet { count() } }
    @Published var to: Date = Date() { didSet { count() } }
    @Published private(set) var candidates = 0
    @Published private(set) var copying: String?
    @Published var message: String?

    var allowed: Bool { access == .authorized }

    /// Full access, which deleting needs. Limited access cannot delete.
    func ask() async {
        access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        load()
    }

    func load() {
        guard allowed else { return }
        var out: [Album] = []
        let user = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        user.enumerateObjects { collection, _, _ in
            out.append(Album(id: collection.localIdentifier, title: collection.localizedTitle ?? "Album"))
        }
        albums = out.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        count()
    }

    /// The photos and videos chosen, less any already moved.
    private func fetch() -> [PHAsset] {
        guard allowed else { return [] }
        let options = PHFetchOptions()
        let start = Calendar.current.startOfDay(for: min(from, to))
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(from, to))) ?? to
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@ AND (mediaType == %d OR mediaType == %d)",
                                        start as NSDate, end as NSDate,
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result: PHFetchResult<PHAsset>
        if let album, let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album], options: nil).firstObject {
            result = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            result = PHAsset.fetchAssets(with: options)
        }
        let ledger = DriveUploadQueue.shared.ledger
        var out: [PHAsset] = []
        result.enumerateObjects { asset, _, stop in
            if !ledger.contains(asset.localIdentifier) { out.append(asset) }
            if out.count >= DrivePhotoImport.moveLimit { stop.pointee = true }
        }
        return out
    }

    private func count() {
        candidates = fetch().count
    }

    /// Copy each to the folder, through the queue. The originals stay until
    /// "Remove from phone".
    func copy(into model: DriveFolderModel, keepOriginals: Bool) async {
        let assets = fetch()
        guard !assets.isEmpty else { return }
        defer { copying = nil; count() }
        var failed = 0
        for (i, asset) in assets.enumerated() {
            copying = "Copying \(i + 1) of \(assets.count)…"
            guard let file = await Self.export(asset) else { failed += 1; continue }
            let created = asset.creationDate
            let media = await Task.detached(priority: .utility) {
                DrivePhotoImport.describe(file, keepOriginals: keepOriginals, fallbackDate: created)
            }.value
            // The library's own date is the truth for a library photo.
            let takenAt = created.map { DriveLogic.localISO($0) } ?? media.takenAt
            await model.queue(media.url, consume: true, name: media.filename, mime: media.mimeType,
                              takenAt: takenAt, assetId: asset.localIdentifier)
        }
        if failed > 0 { message = failed == 1 ? "One couldn't be read from the library." : "\(failed) couldn't be read from the library." }
    }

    /// The original's bytes, written straight to a file — from iCloud if
    /// that is where it is.
    private static func export(_ asset: PHAsset) async -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        let wanted: [PHAssetResourceType] = asset.mediaType == .video ? [.video, .fullSizeVideo] : [.photo, .fullSizePhoto]
        var chosen: PHAssetResource?
        for type in wanted where chosen == nil { chosen = resources.first { $0.type == type } }
        guard let resource = chosen else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drive-move", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let name = resource.originalFilename.isEmpty ? "file" : resource.originalFilename
        let target = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: resource, toFile: target, options: options) { error in
                    if let error { done.resume(throwing: error) } else { done.resume() }
                }
            }
            return target
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }

    /// Stored safely, still on the phone — and nothing still on its way up.
    var removable: [DriveMoveLedger.Entry] { DriveUploadQueue.shared.ledger.removable }

    var stillSending: Bool { DriveUploadQueue.shared.jobs.contains { $0.assetId != nil && !$0.isFinished } }

    /// One request for every safely stored original; the system shows its
    /// own "Delete N photos?" and nothing goes without it.
    func removeFromPhone() async {
        let ids = removable.map(\.assetId)
        guard !ids.isEmpty, allowed else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        // Already gone from the library (deleted by hand): just as removed.
        var present = Set<String>()
        assets.enumerateObjects { asset, _, _ in present.insert(asset.localIdentifier) }
        let missing = Set(ids).subtracting(present)
        if !missing.isEmpty { DriveUploadQueue.shared.markRemoved(missing) }
        guard assets.count > 0 else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            DriveUploadQueue.shared.markRemoved(present)
            SRHaptic.ok()
            message = present.count == 1 ? "Removed from this phone. It's in Drive." : "\(present.count) removed from this phone. They're in Drive."
        } catch {
            // Cancelled at the system's prompt, most often: nothing changed.
            message = "Nothing was removed from this phone."
        }
        count()
    }
}

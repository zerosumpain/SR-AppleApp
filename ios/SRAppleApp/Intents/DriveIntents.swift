import AppIntents
import Foundation
import UniformTypeIdentifiers

/// Drive from Shortcuts: files into it without opening the app, and the app
/// opened at a folder. Both are refused — politely, opening nothing — for
/// somebody without Drive, while the owner is viewing as somebody, and in
/// the demo, exactly as the hub would not show it.

extension DriveSpace: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Drive space"
    static var caseDisplayRepresentations: [DriveSpace: DisplayRepresentation] = [
        .mine: "My files",
        .shared: "Shared",
    ]
}

enum DriveIntentGate {
    @MainActor static var open: Bool {
        AccessStore.shared.drive && AccessStore.shared.viewingAs == nil && !SRDemo.isOn
    }
}

/// "Upload to Drive": the files handed in, queued for the background
/// upload, and a sentence back. The app stays shut.
struct UploadToDriveIntent: AppIntent {
    static var title: LocalizedStringResource = "Upload to Drive"
    static var description = IntentDescription("Add files to your Drive, in your own files or the family's shared folder.")

    @Parameter(title: "Files")
    var files: [IntentFile]

    @Parameter(title: "Space", default: .mine)
    var space: DriveSpace

    @Parameter(title: "Folder")
    var folder: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard DriveIntentGate.open else { throw AccessRefusal.unavailable }
        let place = DriveLink.cleanFolder(folder)
        var queued = 0
        var already = 0
        var refusal: String?
        for file in files {
            let name = DriveLogic.usableName(file.filename) ?? "File"
            let folderURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("drive-intent/\(UUID().uuidString)", isDirectory: true)
            let temp = folderURL.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                if let source = file.fileURL {
                    let scoped = source.startAccessingSecurityScopedResource()
                    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                    try FileManager.default.copyItem(at: source, to: temp)
                } else {
                    try file.data.write(to: temp)
                }
                let mime = file.type?.preferredMIMEType
                    ?? UTType(filenameExtension: temp.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                let job = try await DriveUploadQueue.shared.enqueue(
                    temp, consume: true, space: space, folder: place, filename: name, mimeType: mime,
                    limit: DriveLogic.defaultMaxUpload
                )
                if job == nil { already += 1 } else { queued += 1 }
            } catch {
                try? FileManager.default.removeItem(at: folderURL)
                refusal = error.localizedDescription
            }
        }
        let where_ = place.isEmpty ? space.title : place
        var sentence: String
        switch queued {
        case 0: sentence = already > 0 ? "Those are already on their way to \(where_)." : "Nothing was added."
        case 1: sentence = "Adding 1 file to \(where_)."
        default: sentence = "Adding \(queued) files to \(where_)."
        }
        if let refusal { sentence += " \(refusal)" }
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: sentence)))
    }
}

/// "Open Drive": the app, on Drive, at the folder named.
struct OpenDriveIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Drive"
    static var description = IntentDescription("Open your Drive, at a folder if you name one.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Space", default: .mine)
    var space: DriveSpace

    @Parameter(title: "Folder")
    var folder: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard DriveIntentGate.open else {
            AppDelegate.pending.tab = .today
            throw AccessRefusal.unavailable
        }
        AppDelegate.pending.driveLink = DriveLink(space: space, folder: DriveLink.cleanFolder(folder))
        NotificationCenter.default.post(name: PendingEntry.changed, object: nil)
        return .result()
    }
}

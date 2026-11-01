import Foundation
import SwiftUI
import UniformTypeIdentifiers

// Drive from the share extension: "Share → SR → Drive".
//
// SHARED with the share extension (`SRAppleShare`, see watch.yml), with
// `DriveModels.swift` for the wire shapes. Nothing here may reach for the
// app's own types (`SiteClient`, `AccessStore`, `SRHaptic`): the extension
// has the site credential the app leaves on the shared Keychain shelf
// (`FamilyShelf`), and nothing else.
//
// Foreground only. A background upload from an extension needs a shared
// container, which needs an App Group, which this app cannot have (see
// FamilyWidgetShared.swift). So the sheet sends while it is open, streaming
// each file from disk — an extension is killed at around 120 MB of memory —
// and says so plainly when it can't.

/// Whether the shelf says this phone's person has Drive. Written by the app
/// (`FamilyWidgetBridge.sync`) beside the credential.
enum DriveShelf {
    static var allowed: Bool {
        FamilyShelf.load(Bool.self, .driveAllowed) == true
            && FamilyShelf.load(FamilyWidgetCredential.self, .credential) != nil
    }

    /// The origin and token, for an HTTPS site only.
    static func credential() -> (URL, String)? {
        guard let credential = FamilyShelf.load(FamilyWidgetCredential.self, .credential),
              let origin = URL(string: credential.origin), origin.scheme == "https" else { return nil }
        return (origin, credential.token)
    }

    /// `origin` + `path` + an already-escaped query.
    static func url(_ origin: URL, path: String, query: String?) -> URL? {
        guard var parts = URLComponents(url: origin.appending(path: path), resolvingAgainstBaseURL: false) else { return nil }
        parts.percentEncodedQuery = query
        return parts.url
    }

    /// The file's type for the site's `type` field.
    static func mimeType(for file: URL) -> String {
        UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}

enum DriveSharePost {
    enum Outcome: Equatable {
        /// On the site — new, or these bytes were already there.
        case stored(name: String, duplicate: Bool)
        /// No credential on the shelf, or no longer allowed Drive.
        case notSignedIn
        /// The site said no, in its own words (too big, no room, a bad name).
        case refused(String)
        /// Never reached the site, or it never answered.
        case unreachable
    }

    /// One file, streamed from disk as the raw request body, with its name
    /// and place in the query — the same request the app's own uploads make
    /// (`POST api/native/drive/files`). The body is always octet-stream, the
    /// real type in `type`: the site refuses a text/plain POST from a phone
    /// as a cross-site form.
    static func upload(fileURL: URL, space: DriveSpace, folder: String, filename: String, type: String,
                       timeout: TimeInterval = 120) async -> Outcome {
        guard let (origin, token) = DriveShelf.credential() else { return .notSignedIn }
        var fields = ["space": space.rawValue, "filename": filename, "type": type]
        if !folder.isEmpty { fields["folder"] = folder }
        let query = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\(DriveLogic.escape($0.value))" }
            .joined(separator: "&")
        guard let url = DriveShelf.url(origin, path: "api/native/drive/files", query: query) else { return .refused("That file name can't be used.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.upload(for: request, fromFile: fileURL),
              let http = response as? HTTPURLResponse else { return .unreachable }
        switch http.statusCode {
        case 200..<300:
            guard let reply = try? JSONDecoder().decode(DriveUploadReply.self, from: data) else { return .unreachable }
            return .stored(name: reply.file.name, duplicate: reply.duplicate == true)
        case 401, 403:
            // A 403 with words is a refusal of THIS file (a shared file
            // someone else added); without, the credential lost Drive.
            if http.statusCode == 403, let error = refusal(data) { return .refused(error) }
            return .notSignedIn
        case 400..<500:
            return .refused(refusal(data) ?? "Drive wouldn't take that file.")
        default:
            return .unreachable
        }
    }

    private static func refusal(_ data: Data) -> String? {
        let text = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        return (text?.isEmpty ?? true) ? nil : text
    }
}

/// One folder of a space, for the share sheet's folder picker.
enum DriveFolderFetch {
    static func list(space: DriveSpace, folder: String) async -> DriveListing? {
        guard let (origin, token) = DriveShelf.credential() else { return nil }
        var query = "space=\(space.rawValue)"
        if !folder.isEmpty { query += "&folder=\(DriveLogic.escape(folder))" }
        guard let url = DriveShelf.url(origin, path: "api/native/drive", query: query) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(DriveListing.self, from: data)
    }
}

/// Choose a folder of a space: Move… in the app, and where a share goes in
/// the extension. It walks the space one folder at a time with whatever
/// `load` reads it through (the app's client, or the shelf's credential),
/// and hands back the folder showing when the confirm button is pressed.
struct DriveFolderPicker: View {
    let space: DriveSpace
    let title: String
    let confirm: String
    var start: String = ""
    let load: (DriveSpace, String) async -> DriveListing?
    let chosen: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var folder: String?
    @State private var listing: DriveListing?
    @State private var loading = false

    private var here: String { folder ?? start }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if !here.isEmpty {
                        Button {
                            folder = DriveLogic.parent(here)
                        } label: {
                            Label("Up to \(DriveLogic.lastSegment(DriveLogic.parent(here)) ?? space.title)",
                                  systemImage: "arrow.turn.left.up")
                        }
                    }
                    if let listing, listing.space == space, listing.folder == here {
                        ForEach(DriveLogic.sorted(listing.folders)) { child in
                            Button {
                                folder = child.path
                            } label: {
                                Label(child.name, systemImage: "folder")
                            }
                        }
                        if listing.folders.isEmpty {
                            Text("No folders in here.").foregroundStyle(.secondary)
                        }
                    } else if loading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("This folder didn't open.").foregroundStyle(.secondary)
                    }
                } header: {
                    Text(here.isEmpty ? space.title : here)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm) {
                        chosen(here)
                        dismiss()
                    }
                }
            }
            .task(id: here) {
                loading = true
                listing = await load(space, here)
                loading = false
            }
        }
    }
}

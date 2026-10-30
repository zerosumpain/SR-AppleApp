import CoreGraphics
import Foundation

/// Drive on the phone: two places and nothing else of the site's drive.
///
/// `mine` is this person's own space — nobody else in the family can open it
/// (for John it is his whole /drive). `shared` is the family's folder that
/// everyone on the app reads and adds to; a file in it is deleted only by
/// whoever put it there. The SITE enforces all of that (SR-Main
/// `$lib/drive/app-lane`); this app only draws what it is sent and offers
/// Delete where the site said `canDelete`.
enum DriveSpace: String, Codable, CaseIterable, Identifiable, Hashable {
    case mine, shared

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mine: return "My files"
        case .shared: return "Shared"
        }
    }

    var icon: String {
        switch self {
        case .mine: return "lock.fill"
        case .shared: return "person.3.fill"
        }
    }

    /// One line under the picker: what this space is, in family words.
    var promise: String {
        switch self {
        case .mine: return "Only you can see these."
        case .shared: return "Everyone in the family can see and add to these."
        }
    }
}

/// A folder of a space to show — what a Drive screen is pushed with.
struct DriveRef: Hashable {
    var space: DriveSpace = .mine
    /// Relative to the space: "" for its top, else "Holiday/2026".
    var folder: String = ""

    var title: String { DriveLogic.lastSegment(folder) ?? "Drive" }
}

struct DriveFolder: Codable, Equatable, Identifiable, Hashable {
    let name: String
    let path: String
    let items: Int
    var id: String { path }
}

struct DriveFile: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let mimeType: String
    let sizeBytes: Int
    let createdAt: String
    let updatedAt: String
    let mine: Bool
    let addedBy: String?
    let canDelete: Bool
}

struct DriveUsage: Codable, Equatable {
    let bytes: Int
    /// Nil for the owner's own drive, which has no limit.
    let quotaBytes: Int?
}

struct DriveListing: Codable, Equatable {
    let space: DriveSpace
    let folder: String
    let folders: [DriveFolder]
    let files: [DriveFile]
    let usage: DriveUsage
    let maxUploadBytes: Int
}

/// The pure parts, so each is a unit test.
enum DriveLogic {
    /// What the site takes per file (SR-Main `MAX_UPLOAD_BYTES`), until a
    /// listing says otherwise.
    static let defaultMaxUpload = 30 * 1024 * 1024
    /// The longest side a photo is sent at: plenty for a screen or a print,
    /// and a 48-megapixel original would otherwise be over the limit.
    static let photoMaxEdge: CGFloat = 4032

    /// "Holiday/2026" → "2026"; "" → nil.
    static func lastSegment(_ path: String) -> String? {
        path.split(separator: "/").last.map(String.init)
    }

    /// A folder inside another: "" + "Trip" → "Trip"; "Holiday" + "2026" → "Holiday/2026".
    static func child(_ parent: String, _ name: String) -> String {
        parent.isEmpty ? name : "\(parent)/\(name)"
    }

    /// A name the site would refuse, caught before the round trip: empty,
    /// a separator, `.`/`..`, the folder marker, or longer than 120.
    static func usableName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120, name != ".", name != "..", name != ".keep",
              !name.contains("/"), !name.contains("\\"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return name
    }

    /// A photo's file name: when it was added, so two never clash and they sort by time.
    static func photoName(at date: Date, index: Int, ext: String = "jpg") -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_GB_POSIX")
        format.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let suffix = index > 0 ? " \(index + 1)" : ""
        return "Photo \(format.string(from: date))\(suffix).\(ext)"
    }

    /// "1.2 MB".
    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// "120 MB of 2 GB" — or just what is held, where there is no limit.
    static func usage(_ usage: DriveUsage) -> String {
        guard let quota = usage.quotaBytes else { return "\(size(usage.bytes)) used" }
        return "\(size(usage.bytes)) of \(size(quota))"
    }

    /// The SF Symbol for a file, by its type.
    static func icon(mime: String, name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        if mime.hasPrefix("image/") || ["heic", "jpg", "jpeg", "png", "gif"].contains(ext) { return "photo" }
        if mime.hasPrefix("video/") || ["mov", "mp4", "m4v"].contains(ext) { return "film" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime == "application/pdf" || ext == "pdf" { return "doc.richtext" }
        if ["xlsx", "xls", "csv", "numbers"].contains(ext) { return "tablecells" }
        if ["zip", "gz", "tar"].contains(ext) { return "doc.zipper" }
        return "doc.text"
    }

    /// Whether a file is a picture this phone can draw a thumbnail of.
    static func isImage(_ file: DriveFile) -> Bool {
        icon(mime: file.mimeType, name: file.name) == "photo"
    }

    /// The query for a listing — values escaped strictly (`&`, `=`, `+` too),
    /// as `SiteClient.upload` does.
    static func listPath(_ ref: DriveRef) -> String {
        var path = "api/native/drive?space=\(ref.space.rawValue)"
        if !ref.folder.isEmpty { path += "&folder=\(escape(ref.folder))" }
        return path
    }

    static func escape(_ value: String) -> String {
        var strict = CharacterSet.urlQueryAllowed
        strict.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(withAllowedCharacters: strict) ?? ""
    }

    /// Whether an upload of this size will be refused, and the sentence to say instead.
    static func tooLarge(_ bytes: Int, limit: Int) -> String? {
        bytes > limit ? "That is \(size(bytes)) — the most is \(size(limit)) a file." : nil
    }
}

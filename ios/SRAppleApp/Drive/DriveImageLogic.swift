import Foundation

/// The two pictures the site renders of a photo in Drive (SR-Drive's
/// `/api/files/app/files/<id>/preview`, relayed by SR-Main): a tile for the
/// grid and the list, and a screen-sized one for the viewer.
enum DrivePreviewSize: String, CaseIterable {
    /// 360 px on the long side (SR-Drive `PREVIEW_EDGE.thumb`).
    case thumb
    /// 2048 px on the long side.
    case view

    /// The longest edge the site renders this size at.
    var edge: Int {
        switch self {
        case .thumb: return 360
        case .view: return 2048
        }
    }
}

/// The pure parts of Drive's pictures: what to ask for, what to call it in the
/// cache, and when the old way is still worth it. Foundation only, so each is
/// a unit test on Linux.
enum DrivePreviewLogic {
    /// The largest original fetched for a tile when the site has no preview
    /// route yet (an older site answers the preview 404). Anything bigger
    /// shows its type's mark: pulling 15 MB for a 120-pixel square is the
    /// cost this route exists to remove.
    static let fallbackMaxBytes = 4 * 1024 * 1024

    /// What the site renders (SR-Drive `canPreview`): JPEG, PNG, WebP, GIF,
    /// AVIF, TIFF and HEIC/HEIF. Not SVG — a document, not a picture — so
    /// nothing is asked that would only be refused.
    static func canPreview(mime: String, name: String) -> Bool {
        let type = mime.lowercased()
        let ext = (name as NSString).pathExtension.lowercased()
        let mimes: Set<String> = [
            "image/jpeg", "image/jpg", "image/pjpeg", "image/png", "image/webp", "image/gif", "image/avif",
            "image/tiff", "image/tif", "image/heic", "image/heif", "image/heic-sequence", "image/heif-sequence",
        ]
        let exts: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "avif", "tif", "tiff", "heic", "heif"]
        return mimes.contains(type) || exts.contains(ext)
    }

    /// The version key the site's cache headers are keyed on: anything that
    /// changes when the bytes do. Size and modified time, digits only, which
    /// SR-Main passes through as it is (`[A-Za-z0-9._-]{1,64}`).
    static func version(sizeBytes: Int, updatedAt: String) -> String {
        let stamp = updatedAt.filter { $0.isASCII && $0.isNumber }
        return String("\(max(0, sizeBytes))-\(stamp)".prefix(64))
    }

    /// `size=thumb&v=…`: the query of a preview request.
    static func query(size: DrivePreviewSize, version: String?) -> String {
        guard let version, !version.isEmpty else { return "size=\(size.rawValue)" }
        return "size=\(size.rawValue)&v=\(version)"
    }

    /// The preview's file in the phone's disk cache: one per file, version
    /// and size, whatever size it is drawn at.
    static func diskName(id: String, version: String, size: DrivePreviewSize) -> String {
        SRImageLogic.fileName([id, version, size.rawValue], ext: "jpg")
    }

    /// The start of every disk name for a file id, to forget all its versions.
    static func diskPrefix(id: String) -> String {
        String(SRImageLogic.fileName([id, ""], ext: "x").dropLast(2))
    }

    /// The decoded picture in memory: per drawn size too, so a 32-point list
    /// mark never holds a tile's pixels.
    static func memoryKey(id: String, version: String, size: DrivePreviewSize, points: Double) -> String {
        "\(id)|\(version)|\(size.rawValue)|\(Int(points.rounded(.up)))"
    }

    /// What to do with the site's answer to a preview.
    enum Answer: Equatable {
        /// Draw it.
        case show
        /// An older site with no preview route: fetch the original, if it is small.
        case original
        /// The site will not render this one (not a picture, gone, undecodable):
        /// show the mark, and do not ask again this session.
        case mark
        /// Trouble on the way (offline, a timeout, a 5xx): show the mark, ask again later.
        case later
    }

    /// The decision for a preview's HTTP status (nil: no answer at all).
    static func answer(status: Int?) -> Answer {
        switch status {
        case .some(200...299): return .show
        case .some(404): return .original
        case .some(410), .some(415), .some(422): return .mark
        default: return .later
        }
    }

    /// Whether a tile may fall back to the original: a small enough picture.
    static func mayFetchOriginal(sizeBytes: Int) -> Bool {
        sizeBytes > 0 && sizeBytes <= fallbackMaxBytes
    }
}

/// The grid's columns and rows, as SwiftUI's adaptive grid would lay them,
/// so the grid can be List rows (lazy, cancelled when they scroll away)
/// instead of one row holding every tile.
enum DriveGridLayout {
    static let minimum = 96.0
    static let maximum = 140.0
    static let spacing = 8.0

    /// As many columns of at least `minimum` as fit; three before the width is known.
    static func columns(width: Double) -> Int {
        guard width.isFinite, width > 0 else { return 3 }
        return max(1, Int((width + spacing) / (minimum + spacing)))
    }

    /// Each tile's side: the width shared out, never more than `maximum`.
    static func tileSide(width: Double, columns: Int) -> Double {
        let n = Double(max(1, columns))
        guard width.isFinite, width > 0 else { return maximum }
        return min(maximum, max(1, (width - spacing * (n - 1)) / n))
    }

    /// Item indices in rows of `columns`; the last row may be short.
    static func rows(count: Int, columns: Int) -> [Range<Int>] {
        guard count > 0 else { return [] }
        let n = max(1, columns)
        return stride(from: 0, to: count, by: n).map { $0..<min(count, $0 + n) }
    }
}

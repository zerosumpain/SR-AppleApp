#if canImport(CoreGraphics)
import CoreGraphics
#endif
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
    /// The most one request takes (the single-shot upload).
    let maxUploadBytes: Int
    /// The most a file may be when sent a piece at a time (the 4 GB cap, or
    /// what is left of this person's room if less). Missing from an older
    /// site, which takes no big uploads.
    var maxLargeUploadBytes: Int? = nil
    /// The size of each piece, when the site takes big uploads.
    var chunkBytes: Int? = nil

    var limits: DriveUploadLimits {
        DriveUploadLimits(single: maxUploadBytes, large: maxLargeUploadBytes)
    }
}

/// What a space takes per file, from its listing: one request up to
/// `single`, a session a piece at a time up to `large` (nil: no sessions).
struct DriveUploadLimits: Equatable {
    var single: Int = DriveLogic.defaultMaxUpload
    var large: Int? = nil
}

/// One file of a space, on its own screen — what a tapped file's Info, a
/// push about a saved attachment, or a `sr://drive?…&file=` link pushes.
///
/// `known` is the row the listing already drew, so the screen has a name
/// before the site answers. It is not part of the identity: the same file
/// reached two ways is one screen.
struct DriveFileRef: Hashable {
    var space: DriveSpace = .mine
    var id: String
    var known: DriveFile? = nil
    /// Something to do as the screen opens: a menu's Analyse or Extract
    /// entities lands here, where the answer is shown.
    var action: DriveFileAction? = nil

    static func == (a: DriveFileRef, b: DriveFileRef) -> Bool { a.space == b.space && a.id == b.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(space)
        hasher.combine(id)
    }
}

enum DriveFileAction: String, Hashable {
    case analyse, extract
}

/// How a folder's files are put in order (`@AppStorage("drive.sort")`).
enum DriveSort: String, CaseIterable, Identifiable, Codable {
    case name, date, size, type

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .date: return "Newest first"
        case .size: return "Largest first"
        case .type: return "Kind"
        }
    }

    var icon: String {
        switch self {
        case .name: return "textformat"
        case .date: return "calendar"
        case .size: return "arrow.up.arrow.down"
        case .type: return "square.grid.2x2"
        }
    }
}

/// What jkai made of one file (build map §2.3) — the same JSON in Drive, the
/// site's relay, Core and here. Read leniently: a list the server left out
/// is empty, and a document type this version does not know is still shown.
struct FileAnalysis: Codable, Equatable {
    struct Fact: Codable, Equatable, Hashable {
        let label: String
        let value: String
    }

    struct DateFact: Codable, Equatable, Hashable {
        let label: String
        /// `YYYY-MM-DD`.
        let date: String
    }

    struct Amount: Codable, Equatable, Hashable {
        let label: String
        let value: Double
        let currency: String
    }

    let fileId: String
    let contentHash: String?
    /// `drive` (asked for on /drive or here) or `mail-rule` (filed from mail).
    let source: String
    let model: String
    let summary: String
    let docType: String
    let keyFacts: [Fact]
    let dates: [DateFact]
    let amounts: [Amount]
    let actionNeeded: String?
    let createdAt: String

    init(fileId: String, contentHash: String? = nil, source: String = "drive", model: String = "", summary: String,
         docType: String = "other", keyFacts: [Fact] = [], dates: [DateFact] = [], amounts: [Amount] = [],
         actionNeeded: String? = nil, createdAt: String = "") {
        self.fileId = fileId
        self.contentHash = contentHash
        self.source = source
        self.model = model
        self.summary = summary
        self.docType = docType
        self.keyFacts = keyFacts
        self.dates = dates
        self.amounts = amounts
        self.actionNeeded = actionNeeded
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case fileId, contentHash, source, model, summary, docType, keyFacts, dates, amounts, actionNeeded, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fileId = try c.decode(String.self, forKey: .fileId)
        contentHash = try c.decodeIfPresent(String.self, forKey: .contentHash)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "drive"
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        docType = try c.decodeIfPresent(String.self, forKey: .docType) ?? "other"
        keyFacts = (try? c.decodeIfPresent([Fact].self, forKey: .keyFacts)) ?? []
        dates = (try? c.decodeIfPresent([DateFact].self, forKey: .dates)) ?? []
        amounts = (try? c.decodeIfPresent([Amount].self, forKey: .amounts)) ?? []
        let action = try c.decodeIfPresent(String.self, forKey: .actionNeeded)?.trimmingCharacters(in: .whitespacesAndNewlines)
        actionNeeded = (action?.isEmpty ?? true) ? nil : action
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }

    /// "Invoice", "Bank statement" — the type as a word on the card.
    var docTypeTitle: String {
        switch docType {
        case "invoice": return "Invoice"
        case "receipt": return "Receipt"
        case "contract": return "Contract"
        case "statement": return "Statement"
        case "letter": return "Letter"
        case "report": return "Report"
        case "form": return "Form"
        case "photo": return "Photo"
        default: return "Document"
        }
    }

    /// "£120.50" in the amount's own currency.
    static func money(_ amount: Amount) -> String {
        let format = NumberFormatter()
        format.numberStyle = .currency
        format.currencyCode = amount.currency.isEmpty ? "GBP" : amount.currency
        format.locale = Locale(identifier: "en_GB")
        return format.string(from: NSNumber(value: amount.value)) ?? String(format: "%.2f %@", amount.value, amount.currency)
    }
}

/// `GET api/native/drive/files/<id>/meta` (build map §2.2.1). `analysis`,
/// `intel` and `mail` are always null for a member: the site decides.
struct DriveFileMeta: Decodable, Equatable {
    struct Intel: Decodable, Equatable {
        /// `unknown` | `pending` | `failing` | `done`.
        let status: String
        let outcome: String?
        let entityCount: Int?
    }

    /// The email a file was saved from. `from` is a name or a domain, never an address.
    struct Mail: Decodable, Equatable {
        let from: String
        let subject: String?
        let receivedAt: String
    }

    let file: DriveFile
    /// The folder it sits in, relative to the space.
    let folder: String
    let description: String?
    let analysis: FileAnalysis?
    let intel: Intel?
    let mail: Mail?

    init(file: DriveFile, folder: String = "", description: String? = nil, analysis: FileAnalysis? = nil,
         intel: Intel? = nil, mail: Mail? = nil) {
        self.file = file
        self.folder = folder
        self.description = description
        self.analysis = analysis
        self.intel = intel
        self.mail = mail
    }

    private enum CodingKeys: String, CodingKey { case file, analysis, intel, mail }
    /// The two fields the meta answer adds to a listing's file.
    private struct Extra: Decodable {
        let folder: String?
        let description: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decode(DriveFile.self, forKey: .file)
        let extra = try c.decode(Extra.self, forKey: .file)
        folder = extra.folder ?? ""
        description = extra.description
        analysis = try c.decodeIfPresent(FileAnalysis.self, forKey: .analysis)
        intel = try c.decodeIfPresent(Intel.self, forKey: .intel)
        mail = try c.decodeIfPresent(Mail.self, forKey: .mail)
    }
}

/// `GET api/native/drive/search` (§2.2.3): names for everyone, and what the
/// files say for the owner in My files.
struct DriveSearchResults: Decodable, Equatable {
    struct Passage: Decodable, Equatable, Identifiable {
        let file: DriveFile
        let score: Double
        let passage: String
        /// One file can say the thing in more than one place.
        var id: String { "\(file.id)|\(score)|\(passage.prefix(48))" }
    }

    let files: [DriveFile]
    let semantic: [Passage]?
}

/// "Extract entities" queued (202), and how it is getting on.
struct DriveIntelJob: Decodable, Equatable {
    let jobId: Int
    let status: String
}

struct DriveIntelState: Decodable, Equatable {
    let status: String
    let outcome: String?
    let entityCount: Int?
    let attempts: Int?
    let error: String?
}

/// A rename or a move, as `PATCH api/native/drive/files/<id>` takes it.
/// Nil parts are left out of the JSON, and so left as they are.
struct DriveFileChange: Encodable, Equatable {
    let space: String
    var name: String? = nil
    var folder: String? = nil
}

/// The answer to an upload: 201 `{file, duplicate:false}`, or 200
/// `{file, duplicate:true}` when these bytes were already in the space.
struct DriveUploadReply: Decodable, Equatable {
    let file: DriveFile
    let duplicate: Bool?
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

    /// The folder above: "Holiday/2026" → "Holiday"; "Holiday" → "".
    static func parent(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
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

    // MARK: - Order and search

    /// Files in the order asked for. Ties fall back to the name, so the order
    /// never shuffles between two loads.
    static func sorted(_ files: [DriveFile], by sort: DriveSort) -> [DriveFile] {
        files.sorted { a, b in
            switch sort {
            case .name:
                break
            case .date:
                if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            case .size:
                if a.sizeBytes != b.sizeBytes { return a.sizeBytes > b.sizeBytes }
            case .type:
                let ka = kind(a), kb = kind(b)
                if ka != kb { return ka < kb }
            }
            let byName = a.name.localizedStandardCompare(b.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return a.id < b.id
        }
    }

    /// Folders have no date or size of their own: always by name.
    /// Incoming photos and movies first, where the phone puts things; then by name.
    static func sorted(_ folders: [DriveFolder]) -> [DriveFolder] {
        folders.sorted { a, b in
            let ia = incomingMark(a.path) != nil, ib = incomingMark(b.path) != nil
            if ia != ib { return ia }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// The SF Symbol for a space's Incoming photos or movies folder (the
    /// server's protected pair, at the top of a space); nil for any other.
    static func incomingMark(_ path: String) -> String? {
        switch path {
        case "Incoming photos": return "photo.on.rectangle.angled"
        case "Incoming movies": return "film.stack"
        default: return nil
        }
    }

    /// What a file is, for sorting by kind: photos, films, sound, documents…
    static func kind(_ file: DriveFile) -> String {
        let order = ["photo": "1", "film": "2", "waveform": "3", "doc.richtext": "4", "tablecells": "5", "doc.zipper": "7"]
        let mark = icon(mime: file.mimeType, name: file.name)
        let ext = (file.name as NSString).pathExtension.lowercased()
        return (order[mark] ?? "6") + ext
    }

    /// The site's own name match (SR-Drive `nameMatches`): every word of the
    /// search somewhere in the name, any case.
    static func matches(_ name: String, query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return true }
        let hay = name.lowercased()
        return words.allSatisfy { hay.contains($0) }
    }

    /// The longest search the site takes.
    static let searchMax = 200

    /// `api/native/drive/search?space=…&q=…`, or nil for a search the site
    /// would refuse (empty, or over 200 characters).
    static func searchPath(space: DriveSpace, query raw: String) -> String? {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= searchMax else { return nil }
        return "api/native/drive/search?space=\(space.rawValue)&q=\(escape(query))"
    }

    /// `api/native/drive/files/<id>` and what hangs off it. The id is one
    /// path component, escaped, so it can never address another route.
    static func filePath(_ id: String, _ tail: String = "") -> String {
        var component = CharacterSet.urlPathAllowed
        component.remove(charactersIn: "/?#%")
        let safe = id.addingPercentEncoding(withAllowedCharacters: component) ?? ""
        return "api/native/drive/files/\(safe)" + (tail.isEmpty ? "" : "/\(tail)")
    }

    static func metaPath(_ ref: DriveFileRef) -> String {
        filePath(ref.id, "meta") + "?space=\(ref.space.rawValue)"
    }

    /// One upload's identity in the queue: the same bytes into the same
    /// folder of the same space is the same job, however often it is asked for.
    static func dedupeKey(space: DriveSpace, folder: String, sha256: String) -> String {
        "\(space.rawValue)|\(folder.lowercased())|\(sha256.lowercased())"
    }

    // MARK: - Names and times

    /// The name the site stores a photo under when it is told when it was
    /// taken (SR-Drive `photoNameFor`, build map §2.2.6): an upload with no
    /// name, or an image under the camera's `IMG_1234` name, becomes
    /// "Photo yyyy-MM-dd HH.mm.ss.<ext>" from the wall clock written in
    /// `takenAt`. Nil: the name sent is kept. Shown in the queue, so what the
    /// phone says it is adding is what lands.
    static func photoName(takenAt: String?, filename: String?, mimeType: String) -> String? {
        guard let stamp = takenAt?.trimmingCharacters(in: .whitespaces),
              let match = stamp.range(of: #"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}"#, options: .regularExpression) else { return nil }
        let clock = String(stamp[match])
        let name = (filename ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let mime = mimeType.lowercased()
        let ext = (name as NSString).pathExtension.lowercased()
        let isImage = mime.hasPrefix("image/") || imageExtensions.contains(ext)
        if !name.isEmpty && !(isImage && name.lowercased().hasPrefix("img_")) { return nil }
        let chosen: String
        if !name.isEmpty, name.contains("."), !ext.isEmpty, !name.hasPrefix(".") {
            chosen = ext
        } else {
            chosen = mimeExtensions[mime] ?? (mime.hasPrefix("image/") ? "jpg" : "bin")
        }
        let digits = clock.replacingOccurrences(of: "T", with: " ")
        let day = digits.prefix(10)
        let time = digits.dropFirst(11).replacingOccurrences(of: ":", with: ".")
        return "Photo \(day) \(time).\(chosen)"
    }

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "gif", "webp", "dng", "tif", "tiff"]
    private static let mimeExtensions: [String: String] = [
        "image/jpeg": "jpg", "image/jpg": "jpg", "image/heic": "heic", "image/heif": "heif", "image/png": "png",
        "image/gif": "gif", "image/webp": "webp", "video/quicktime": "mov", "video/mp4": "mp4",
    ]

    /// A moment as the phone's own clock read it, with its offset —
    /// "2026-10-30T09:05:09+01:00" — which is what `takenAt` must carry: the
    /// site names the photo from the wall clock in the string.
    static func localISO(_ date: Date, timeZone: TimeZone = .current) -> String {
        let format = ISO8601DateFormatter()
        format.timeZone = timeZone
        format.formatOptions = [.withInternetDateTime]
        return format.string(from: date)
    }

    /// A photo's own record of when it was taken — EXIF `DateTimeOriginal`
    /// ("2026:10:30 09:05:09") and, when the camera wrote one,
    /// `OffsetTimeOriginal` ("+01:00") — as a `takenAt`. Without an offset
    /// the phone's own zone is assumed, which is where it was taken nine
    /// times out of ten.
    static func takenAt(exif raw: String?, offset: String?, timeZone: TimeZone = .current) -> String? {
        guard let raw, raw.range(of: #"^\d{4}:\d{2}:\d{2} \d{2}:\d{2}:\d{2}"#, options: .regularExpression) != nil else { return nil }
        let date = raw.prefix(10).replacingOccurrences(of: ":", with: "-")
        let clock = String(raw.dropFirst(11).prefix(8))
        if let offset, offset.range(of: #"^[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil {
            return "\(date)T\(clock)\(offset)"
        }
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = timeZone
        parse.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let moment = parse.date(from: "\(date)T\(clock)") else { return nil }
        return localISO(moment, timeZone: timeZone)
    }

    /// An ISO time from the site, read with or without its milliseconds.
    static func date(_ iso: String) -> Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = format.date(from: iso) { return date }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: iso)
    }

    /// "30 Oct 2026" — or "Today", "Yesterday".
    static func day(_ iso: String, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let date = date(iso) else { return nil }
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_GB")
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.dateFormat = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "d MMM" : "d MMM yyyy"
        return format.string(from: date)
    }

    /// The one line under a file's name: "1.2 MB · 30 Oct · added by Rory".
    static func detail(_ file: DriveFile, now: Date = Date(), calendar: Calendar = .current) -> String {
        [size(file.sizeBytes), day(file.updatedAt, now: now, calendar: calendar), file.addedBy.map { "added by \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Photos and films can be saved to the phone's library; nothing else can.
    static func savesToPhotos(_ file: DriveFile) -> Bool {
        let mark = icon(mime: file.mimeType, name: file.name)
        return mark == "photo" || mark == "film"
    }

    /// Where a file can move to from where it is: the space's folders the
    /// listing knows, its parent, and the top — never where it already is.
    static func moveTargets(from folder: String, children: [DriveFolder]) -> [String] {
        var out: [String] = []
        if !folder.isEmpty { out.append("") }
        if let slash = folder.lastIndex(of: "/") {
            let parent = String(folder[..<slash])
            if !out.contains(parent) { out.append(parent) }
        }
        for child in children where child.path != folder && !out.contains(child.path) { out.append(child.path) }
        return out
    }

    /// What a jkai answer about the extraction says, in words.
    static func intelSentence(status: String, outcome: String?, entityCount: Int?) -> String {
        switch (status, outcome ?? "") {
        case ("done", "extracted"):
            let n = entityCount ?? 0
            return n == 0 ? "Read into the knowledge graph." : (n == 1 ? "Found 1 person, place or thing." : "Found \(n) people, places and things.")
        case ("done", "unchanged"): return "Already in the knowledge graph, unchanged."
        case ("done", "held"): return "Waiting for you to check it on the site."
        case ("done", "skipped"): return "This folder is kept out of the knowledge graph. Change it on the site's folder policy."
        case ("done", "too-short"): return "Too little text to find anything in."
        case ("done", "disabled"): return "The knowledge graph is switched off."
        case ("done", "failed"), ("failing", _): return "jkai couldn't read it this time. It tries again by itself."
        case ("pending", _): return "Queued — jkai reads it in the next minute or two."
        case ("done", _): return "Done."
        default: return "Not read into the knowledge graph yet."
        }
    }

    /// What "Ask jkai" puts in the composer for a file — never sent by
    /// itself. jkai's chat has no Drive reference kind, so the file goes by
    /// its place in Drive, with `@files` to point jkai at the files tool.
    static func askPrompt(for file: DriveFile) -> String {
        "@files About “\(file.path)” in my Drive: "
    }

    /// Whether an extraction has stopped moving, so polling can stop.
    static func intelSettled(_ status: String) -> Bool {
        status == "done" || status == "unknown"
    }
}

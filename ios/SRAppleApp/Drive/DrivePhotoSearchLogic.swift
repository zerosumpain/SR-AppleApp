import Foundation

/// Photo search in Drive: the pure half (no UI, no network), so every rule is
/// a unit test (`DrivePhotoSearchTests`) and runs on Linux in `home-check.sh`.
///
/// The site answers `GET api/native/drive/photos/search` (SR-Main
/// `$lib/drive/native-photos`) from SR-Drive's Immich — faces, CLIP smart
/// search, words in the image, places, dates — and adds, on the first page of
/// a "what's in it" search, the images in Drive's own file index that Immich
/// does not know. It is the owner's alone; the screen is never offered to
/// anyone else.

// MARK: - What is asked

/// One person picked for the search: the face cluster's id, and the name to show.
struct PhotoPersonPick: Codable, Equatable, Hashable, Identifiable {
    let id: String
    /// Nil for a face John has not named yet.
    let name: String?

    var label: String { name ?? "Unnamed person" }
}

enum PhotoKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case photo, video

    var id: String { rawValue }
    var title: String { self == .photo ? "Photos" : "Videos" }
}

/// Everything the search screen can ask, as one value: the screen edits it,
/// the chips are drawn from it, and the query is built from it.
struct PhotoSearchCriteria: Equatable, Hashable {
    /// What the picture shows, in plain words (Immich's smart search).
    var text = ""
    /// Words written in the image (OCR): a sign, a receipt.
    var ocr = ""
    /// Every one of them must be in the photo. The site takes ten at most.
    var people: [PhotoPersonPick] = []
    /// City, region or country.
    var place = ""
    /// Inclusive days, as the phone's calendar reads them.
    var from: Date? = nil
    var to: Date? = nil
    var kind: PhotoKind? = nil

    static let maxPeople = 10
    static let maxText = 200

    /// Nothing asked yet: no search is sent, so the grid is not the whole library.
    var isEmpty: Bool {
        PhotoSearchLogic.clean(text) == nil && PhotoSearchLogic.clean(ocr) == nil && people.isEmpty
            && PhotoSearchLogic.clean(place) == nil && from == nil && to == nil && kind == nil
    }

    /// A date range the wrong way round, said before the site refuses it.
    var rangeProblem: String? {
        guard let from, let to, PhotoSearchLogic.day(from) > PhotoSearchLogic.day(to) else { return nil }
        return "The start date is after the end date."
    }

    mutating func add(_ person: PhotoPersonPick) {
        guard !people.contains(where: { $0.id == person.id }), people.count < Self.maxPeople else { return }
        people.append(person)
    }
}

/// One removable chip under the search field.
struct PhotoFilterChip: Equatable, Hashable, Identifiable {
    enum Kind: Hashable {
        case text, ocr, person(String), place, dates, kind
    }

    let kind: Kind
    let label: String
    let icon: String

    var id: Kind { kind }
}

extension PhotoSearchCriteria {
    /// The active filters, in the order the screen asks for them.
    func chips(calendar: Calendar = .current) -> [PhotoFilterChip] {
        var out: [PhotoFilterChip] = []
        if let t = PhotoSearchLogic.clean(text) { out.append(PhotoFilterChip(kind: .text, label: "“\(t)”", icon: "sparkle.magnifyingglass")) }
        if let o = PhotoSearchLogic.clean(ocr) { out.append(PhotoFilterChip(kind: .ocr, label: "Says “\(o)”", icon: "text.viewfinder")) }
        for p in people { out.append(PhotoFilterChip(kind: .person(p.id), label: p.label, icon: "person.crop.circle")) }
        if let pl = PhotoSearchLogic.clean(place) { out.append(PhotoFilterChip(kind: .place, label: pl, icon: "mappin.and.ellipse")) }
        if let dates = PhotoSearchLogic.rangeLabel(from: from, to: to, calendar: calendar) {
            out.append(PhotoFilterChip(kind: .dates, label: dates, icon: "calendar"))
        }
        if let kind { out.append(PhotoFilterChip(kind: .kind, label: kind.title, icon: kind == .video ? "video" : "photo")) }
        return out
    }

    /// The same search without that one filter.
    func removing(_ chip: PhotoFilterChip.Kind) -> PhotoSearchCriteria {
        var next = self
        switch chip {
        case .text: next.text = ""
        case .ocr: next.ocr = ""
        case .person(let id): next.people.removeAll { $0.id == id }
        case .place: next.place = ""
        case .dates:
            next.from = nil
            next.to = nil
        case .kind: next.kind = nil
        }
        return next
    }

    /// `api/native/drive/photos/search?…` for one page, or nil when nothing is
    /// asked. Values are escaped strictly (`&`, `=`, `+` too), as the rest of
    /// Drive's paths are; dates are the phone's own calendar days.
    func path(page: Int = 1, limit: Int = PhotoSearchLogic.pageSize, calendar: Calendar = .current) -> String? {
        guard !isEmpty else { return nil }
        var pairs: [(String, String)] = []
        for p in people.prefix(Self.maxPeople) { pairs.append(("person", p.id)) }
        if let t = PhotoSearchLogic.clean(text) { pairs.append(("text", t)) }
        if let o = PhotoSearchLogic.clean(ocr) { pairs.append(("ocr", o)) }
        if let pl = PhotoSearchLogic.clean(place) { pairs.append(("place", pl)) }
        if let from { pairs.append(("from", PhotoSearchLogic.day(from, calendar: calendar))) }
        if let to { pairs.append(("to", PhotoSearchLogic.day(to, calendar: calendar))) }
        if let kind { pairs.append(("type", kind.rawValue)) }
        pairs.append(("limit", String(max(1, min(100, limit)))))
        if page > 1 { pairs.append(("page", String(page))) }
        let query = pairs.map { "\($0.0)=\(PhotoSearchLogic.escape($0.1))" }.joined(separator: "&")
        return "api/native/drive/photos/search?\(query)"
    }
}

// MARK: - What comes back

/// A Drive file as the site's `forPhone` sends it — the same fields the
/// Drive screens' `DriveFile` decodes, kept here so this file needs nothing
/// but Foundation. `DrivePhotoSearchScreen` turns it into a `DriveFile`.
struct PhotoHitFile: Codable, Equatable, Hashable {
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

/// One matching picture: Immich's (`photos`) or the Drive index's (`drive`).
struct PhotoHit: Decodable, Equatable, Hashable, Identifiable {
    enum Source: String, Decodable { case photos, drive }

    struct Person: Decodable, Equatable, Hashable {
        let id: String
        let name: String?
    }

    struct FileLink: Decodable, Equatable, Hashable {
        let id: String
        let name: String
    }

    let key: String
    let source: Source
    let assetId: String?
    let type: PhotoKind
    let takenAt: String?
    let durationSec: Int?
    let place: String?
    let people: [Person]
    let thumbPath: String
    let previewPath: String
    let driveFile: FileLink?
    let file: PhotoHitFile?
    let passage: String?

    var id: String { key }
    var isVideo: Bool { type == .video }

    private enum CodingKeys: String, CodingKey {
        case key, source, assetId, type, takenAt, durationSec, place, people, thumbPath, previewPath, driveFile, file, passage
    }

    init(key: String, source: Source = .photos, assetId: String? = nil, type: PhotoKind = .photo, takenAt: String? = nil,
         durationSec: Int? = nil, place: String? = nil, people: [Person] = [], thumbPath: String, previewPath: String? = nil,
         driveFile: FileLink? = nil, file: PhotoHitFile? = nil, passage: String? = nil) {
        self.key = key
        self.source = source
        self.assetId = assetId
        self.type = type
        self.takenAt = takenAt
        self.durationSec = durationSec
        self.place = place
        self.people = people
        self.thumbPath = thumbPath
        self.previewPath = previewPath ?? thumbPath
        self.driveFile = driveFile
        self.file = file
        self.passage = passage
    }

    /// Read leniently: a field the site left out is empty, a type this version
    /// does not know is a photo, and an image path that is not one of the
    /// site's native Drive paths is refused, so the phone never fetches
    /// anything but its own owner-only lane.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        source = (try? c.decode(Source.self, forKey: .source)) ?? .photos
        assetId = try c.decodeIfPresent(String.self, forKey: .assetId)
        type = (try? c.decode(PhotoKind.self, forKey: .type)) ?? .photo
        takenAt = try c.decodeIfPresent(String.self, forKey: .takenAt)
        if let seconds = try? c.decodeIfPresent(Double.self, forKey: .durationSec) {
            durationSec = Int(seconds.rounded())
        } else {
            durationSec = nil
        }
        place = try c.decodeIfPresent(String.self, forKey: .place)
        people = (try? c.decodeIfPresent([Person].self, forKey: .people)) ?? []
        let thumb = try c.decode(String.self, forKey: .thumbPath)
        guard PhotoSearchLogic.isNativePath(thumb) else {
            throw DecodingError.dataCorruptedError(forKey: .thumbPath, in: c, debugDescription: "not a native Drive path")
        }
        thumbPath = thumb
        let preview = try c.decodeIfPresent(String.self, forKey: .previewPath) ?? thumb
        previewPath = PhotoSearchLogic.isNativePath(preview) ? preview : thumb
        driveFile = try? c.decodeIfPresent(FileLink.self, forKey: .driveFile)
        file = try? c.decodeIfPresent(PhotoHitFile.self, forKey: .file)
        passage = try c.decodeIfPresent(String.self, forKey: .passage)
    }

    /// The Drive file to open, when there is one.
    var driveFileId: String? { file?.id ?? driveFile?.id }
    /// The one line under a picture in the preview: when, where, who.
    var caption: String {
        var parts: [String] = []
        if let takenAt, let when = PhotoSearchLogic.when(takenAt) { parts.append(when) }
        if let place { parts.append(place) }
        let named = people.compactMap { $0.name }
        if !named.isEmpty { parts.append(named.joined(separator: ", ")) }
        if parts.isEmpty, let name = file?.name ?? driveFile?.name { parts.append(name) }
        return parts.joined(separator: " · ")
    }
}

/// One page of `photos/search`.
struct PhotoSearchPage: Decodable, Equatable {
    let connected: Bool
    let reason: String?
    let total: Int?
    let page: Int
    let hasMore: Bool
    let results: [PhotoHit]

    private enum CodingKeys: String, CodingKey { case connected, reason, total, page, hasMore, results }

    init(connected: Bool = true, reason: String? = nil, total: Int? = nil, page: Int = 1, hasMore: Bool = false, results: [PhotoHit]) {
        self.connected = connected
        self.reason = reason
        self.total = total
        self.page = page
        self.hasMore = hasMore
        self.results = results
    }

    /// A single hit the phone cannot draw is skipped, never the whole page.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        connected = (try? c.decode(Bool.self, forKey: .connected)) ?? false
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        total = try? c.decodeIfPresent(Int.self, forKey: .total)
        page = (try? c.decode(Int.self, forKey: .page)) ?? 1
        hasMore = (try? c.decode(Bool.self, forKey: .hasMore)) ?? false
        results = ((try? c.decode([PhotoLenient<PhotoHit>].self, forKey: .results)) ?? []).compactMap(\.value)
    }
}

/// A face for the person picker.
struct PhotoPerson: Decodable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String?
    let photos: Int?
    let facePath: String

    var pick: PhotoPersonPick { PhotoPersonPick(id: id, name: name) }
}

/// `photos/people`.
struct PhotoPeoplePage: Decodable, Equatable {
    let connected: Bool
    let reason: String?
    let people: [PhotoPerson]

    private enum CodingKeys: String, CodingKey { case connected, reason, people }

    init(connected: Bool = true, reason: String? = nil, people: [PhotoPerson]) {
        self.connected = connected
        self.reason = reason
        self.people = people
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        connected = (try? c.decode(Bool.self, forKey: .connected)) ?? false
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        people = ((try? c.decode([PhotoLenient<PhotoPerson>].self, forKey: .people)) ?? [])
            .compactMap(\.value)
            .filter { PhotoSearchLogic.isNativePath($0.facePath) }
    }
}

/// One element of a list, or nil when it would not decode.
private struct PhotoLenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

// MARK: - The results so far

/// Every page of one search, in order, each picture once. A Drive index hit
/// on page one can be the same file as an Immich photo on a later page, so
/// pictures are also matched by their Drive file.
struct PhotoSearchResults: Equatable {
    private(set) var hits: [PhotoHit] = []
    private(set) var page = 0
    private(set) var hasMore = true
    private(set) var connected = true
    private(set) var reason: String? = nil
    private(set) var total: Int? = nil
    private var keys = Set<String>()
    private var files = Set<String>()

    /// Whether to show "nothing matched" rather than a spinner.
    var loadedNothing: Bool { page > 0 && hits.isEmpty }

    /// Page `next.page` added; an answer for a page already held is ignored.
    mutating func append(_ next: PhotoSearchPage) {
        guard next.page > page else { return }
        page = next.page
        hasMore = next.hasMore && next.connected
        connected = next.connected
        reason = next.reason
        if page == 1 || next.total != nil { total = next.total }
        for hit in next.results {
            if keys.contains(hit.key) { continue }
            if let file = hit.driveFileId, files.contains(file) { continue }
            keys.insert(hit.key)
            if let file = hit.driveFileId { files.insert(file) }
            hits.append(hit)
        }
    }

    /// The page to ask for next, or nil when there is no more.
    var nextPage: Int? { hasMore ? page + 1 : nil }
}

// MARK: - Helpers

enum PhotoSearchLogic {
    /// A page of results: four rows of a three-across grid on most phones, twice.
    static let pageSize = 30
    /// How long typing settles before a search is sent.
    static let debounceNanoseconds: UInt64 = 450_000_000

    /// Trimmed, at most 200 characters, or nil when empty.
    static func clean(_ raw: String) -> String? {
        let t = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(PhotoSearchCriteria.maxText))
        return t.isEmpty ? nil : t
    }

    static func escape(_ value: String) -> String {
        var strict = CharacterSet.urlQueryAllowed
        strict.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(withAllowedCharacters: strict) ?? ""
    }

    /// Only the site's own native Drive lane: photo thumbnails and faces by
    /// UUID, or one Drive file's bytes. Never a full URL, never `..`.
    static func isNativePath(_ path: String) -> Bool {
        guard !path.contains("..") && !path.contains("://") && !path.hasPrefix("/") else { return false }
        let base = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        let uuid = #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#
        let patterns = [
            #"^api/native/drive/photos/(thumb|face)/"# + uuid + "$",
            #"^api/native/drive/files/[^/?#]+$"#,
        ]
        return patterns.contains { base.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    /// `yyyy-MM-dd` for a day of the phone's calendar.
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "1 Jun – 31 Aug 2026", "From 1 Jun 2026", "Until 31 Aug 2026", "4 Jul 2026".
    static func rangeLabel(from: Date?, to: Date?, calendar: Calendar = .current) -> String? {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_GB")
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        func full(_ d: Date) -> String {
            format.dateFormat = "d MMM yyyy"
            return format.string(from: d)
        }
        switch (from, to) {
        case (nil, nil): return nil
        case (let f?, nil): return "From \(full(f))"
        case (nil, let t?): return "Until \(full(t))"
        case (let f?, let t?):
            if calendar.isDate(f, inSameDayAs: t) { return full(f) }
            let sameYear = calendar.component(.year, from: f) == calendar.component(.year, from: t)
            format.dateFormat = sameYear ? "d MMM" : "d MMM yyyy"
            return "\(format.string(from: f)) – \(full(t))"
        }
    }

    /// A video's length: "0:13", "12:05", "1:02:03".
    static func duration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
    }

    /// When a photo was taken, on the wall clock it was taken at: the site
    /// sends ISO with that offset, so the digits are read as written rather
    /// than moved into the phone's zone. "4 Jul 2026, 10:00".
    static func when(_ iso: String) -> String? {
        guard let m = iso.range(of: #"^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2})?"#, options: .regularExpression) else { return nil }
        let head = String(iso[m])
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = TimeZone(identifier: "UTC")
        parse.dateFormat = head.count > 10 ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
        guard let date = parse.date(from: head.replacingOccurrences(of: " ", with: "T")) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_GB")
        out.timeZone = TimeZone(identifier: "UTC")
        out.dateFormat = head.count > 10 ? "d MMM yyyy, HH:mm" : "d MMM yyyy"
        return out.string(from: date)
    }

    /// What the screen says when there is nothing to show.
    static func emptyMessage(_ criteria: PhotoSearchCriteria) -> String {
        if !criteria.people.isEmpty && criteria.people.count > 1 {
            return "No photo has all of them in it. Try fewer people, or a wider date range."
        }
        if criteria.from != nil || criteria.to != nil { return "Nothing matches in those dates. Try a wider range." }
        return "Nothing matches that. Try other words, or fewer filters."
    }

    /// Photos not linked: said kindly, with the site's reason underneath.
    static func notConnectedMessage(_ reason: String?) -> String {
        let base = "Your photo library isn't connected to Drive right now, so only pictures Drive has read itself can be found."
        guard let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty else { return base }
        return "\(base) (\(reason))"
    }
}

import Foundation
import Combine

/// Where a trails screen stands. One enum rather than three booleans, so a
/// screen cannot be "loading" and "failed" at once and draw both.
enum TrailLoad: Equatable {
    case idle
    case loading
    case loaded
    /// Health is down (503), or unreachable. Its own screen, not a red banner.
    case unavailable(String)
    /// The thing asked for does not exist (404).
    case missing(String)
    case failed(String)

    /// Classify a thrown error the same way on every trails screen.
    static func from(_ error: Error) -> TrailLoad {
        if let site = error as? SiteError {
            switch site.status {
            case 404?: return .missing(site.localizedDescription)
            case 502?, 503?, 504?: return .unavailable(site.localizedDescription)
            default: break
            }
        }
        if error is URLError { return .unavailable(error.localizedDescription) }
        return .failed(error.localizedDescription)
    }
}

/// A path segment with EVERYTHING outside RFC 3986's unreserved set escaped.
///
/// An activity id is `apple:UUID`. `.urlPathAllowed` lets `:` through, and a
/// colon in a path is legal but is exactly the character a proxy or a router
/// can read as something else — so it goes out as `%3A` and the server decodes
/// it. `url(for:)` keeps an already-escaped path verbatim (`percentEncodedPath`)
/// rather than escaping its `%` a second time into `%253A`.
enum TrailPath {
    static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    static func activities(limit: Int, before: String? = nil) -> String {
        var path = "api/native/health/activities?limit=\(limit)"
        if let before { path += "&before=\(escape(before))" }
        return path
    }

    static func activity(_ id: String) -> String { "api/native/health/activities/\(escape(id))" }
    static func segments(limit: Int = 100) -> String { "api/native/health/segments?limit=\(limit)" }
    static func segment(id: Int) -> String { "api/native/health/segments/\(id)" }
}

/// The activities list — the recent few on the Health tab, or the whole history
/// paged by `nextBefore` on the list screen.
@MainActor
final class ActivitiesStore: ObservableObject {
    @Published private(set) var rows: [ActivityRow] = []
    @Published private(set) var state: TrailLoad = .idle
    @Published private(set) var loadingMore = false
    @Published private(set) var nextBefore: String?

    let pageSize: Int
    private let client = SiteClient.shared

    init(pageSize: Int = 30) {
        self.pageSize = pageSize
    }

    var hasMore: Bool { nextBefore != nil }

    func load() async {
        guard client.isPaired, state != .loading else { return }
        state = .loading
        do {
            let page: ActivitiesPage = try await client.send(TrailPath.activities(limit: pageSize))
            rows = page.activities
            nextBefore = page.nextBefore
            state = .loaded
        } catch {
            // A list that has rows on screen keeps them; a refresh that failed
            // is not a reason to blank what was readable a moment ago.
            state = rows.isEmpty ? TrailLoad.from(error) : .loaded
        }
    }

    func loadMore() async {
        guard let cursor = nextBefore, !loadingMore, state == .loaded else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page: ActivitiesPage = try await client.send(TrailPath.activities(limit: pageSize, before: cursor))
            // The cursor is exclusive, but a row that shares its start second
            // with the cursor must still not appear twice.
            let seen = Set(rows.map(\.id))
            rows.append(contentsOf: page.activities.filter { !seen.contains($0.id) })
            nextBefore = page.activities.isEmpty ? nil : page.nextBefore
        } catch {
            // Stop paging rather than retrying on every appearance of the last
            // row — a pull to refresh starts it again.
            nextBefore = nil
        }
    }
}

@MainActor
final class SegmentsStore: ObservableObject {
    @Published private(set) var rows: [SegmentRow] = []
    @Published private(set) var state: TrailLoad = .idle

    private let client = SiteClient.shared

    func load() async {
        guard client.isPaired, state != .loading else { return }
        state = .loading
        do {
            let page: SegmentsPage = try await client.send(TrailPath.segments())
            rows = page.segments
            state = .loaded
        } catch {
            state = rows.isEmpty ? TrailLoad.from(error) : .loaded
        }
    }
}

@MainActor
final class ActivityDetailStore: ObservableObject {
    @Published private(set) var detail: ActivityDetailResponse?
    @Published private(set) var state: TrailLoad = .idle

    private let client = SiteClient.shared

    func load(_ id: String) async {
        guard state != .loading else { return }
        state = .loading
        do {
            let fetched: ActivityDetailResponse = try await client.send(TrailPath.activity(id))
            detail = fetched
            state = .loaded
        } catch {
            state = detail == nil ? TrailLoad.from(error) : .loaded
        }
    }
}

@MainActor
final class SegmentDetailStore: ObservableObject {
    @Published private(set) var detail: SegmentDetailResponse?
    @Published private(set) var state: TrailLoad = .idle

    private let client = SiteClient.shared

    func load(_ id: Int) async {
        guard state != .loading else { return }
        state = .loading
        do {
            let fetched: SegmentDetailResponse = try await client.send(TrailPath.segment(id: id))
            detail = fetched
            state = .loaded
        } catch {
            state = detail == nil ? TrailLoad.from(error) : .loaded
        }
    }
}

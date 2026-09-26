import Foundation

/// The news desk as the phone receives it from `/api/native/news`.
///
/// Field for field with the projection that endpoint builds. Where the web desk
/// carries a Set of read keys and tests membership while rendering a table, the
/// row here carries `read` and `kept` as booleans — a list that re-renders per
/// row would rebuild that Set on every one.

struct NewsAlso: Decodable, Identifiable, Hashable {
    let source: String
    let sourceLabel: String
    let discussionUrl: String
    let score: Int
    let commentCount: Int

    var id: String { "\(source):\(discussionUrl)" }
}

/// Why a row surfaced, and what the knowledge base already holds on it.
struct NewsCorrelation: Decodable, Hashable {
    let score: Double
    let names: [String]
    let why: String
    let evidence: Evidence?

    struct Evidence: Decodable, Hashable {
        let notes: Int
        let lastSeen: String?
    }
}

struct NewsStory: Decodable, Identifiable, Hashable {
    let key: String
    let source: String
    let sourceLabel: String
    /// The wire's own id. NOT unique on its own — two wires can both call a
    /// story `44212`, which is the entire reason the desk keys on `source:id`.
    let storyId: String
    let title: String
    let url: String
    let discussionUrl: String
    let domain: String
    let author: String?
    let publishedAt: String
    let score: Int
    let commentCount: Int
    let heat: Double
    let rank: Int
    let read: Bool
    let kept: Bool
    let alsoOn: [NewsAlso]
    let correlation: NewsCorrelation?

    /// `Identifiable` on the COMPOSITE key, never on `storyId`.
    ///
    /// Keying a list on the wire's id means two stories that share a number
    /// across wires collide — `ForEach` reuses one row for both, and a tap on
    /// one opens the other. `key` is `source:id` and is the desk's own unique
    /// key, so it is the only honest answer here.
    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, source, sourceLabel
        case storyId = "id"
        case title, url, discussionUrl, domain, author, publishedAt
        case score, commentCount, heat, rank, read, kept, alsoOn, correlation
    }
}

struct NewsSourceState: Decodable, Identifiable, Hashable {
    let source: String
    let label: String
    let count: Int
    let ok: Bool
    let error: String?

    var id: String { source }
}

struct NewsStats: Decodable, Hashable {
    let read: Int?
    let kept: Int?
    let favourites: Int?
}

struct NewsFeed: Decodable {
    let view: String
    let sort: String
    let updatedAt: String
    let cached: Bool
    let newSinceLast: Int
    let anchorCount: Int
    let sources: [NewsSourceState]
    let stories: [NewsStory]
    /// What this reader may do with a story. Absent from a site older than
    /// member access; `AccessPolicy.newsActions` falls back to the person's
    /// own flags.
    let can: NewsCan?
}

/// One story, opened.
struct NewsArticle: Decodable {
    let story: Story
    /// `submission` — the wire IS the content. `external` — there is nothing to
    /// render and it must open outside. Anything else carries extracted text.
    let mode: String
    let contentTitle: String
    let content: String
    let summary: String
    let finalUrl: String
    let truncated: Bool
    let message: String?
    let favourite: Bool
    /// As on the feed.
    let can: NewsCan?

    struct Story: Decodable {
        let key: String
        let source: String
        let sourceLabel: String
        let id: String
        let title: String
        let url: String
        let discussionUrl: String
        let domain: String
        let author: String?
        let publishedAt: String
        let score: Int
        let commentCount: Int
        let heat: Double
        let alsoOn: [NewsAlso]
    }
}

/// The five views the desk offers. `forYou` is not a fetch — it is the top wire
/// reordered by what the knowledge graph cares about.
enum NewsView: String, CaseIterable, Identifiable {
    case top, new, best
    case forYou = "for-you"
    case favourites

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: return "Top"
        case .new: return "New"
        case .best: return "Best"
        case .forYou: return "For you"
        case .favourites: return "Saved"
        }
    }
}

/// The four things a row can do, all four the same verbs the web desk has.
enum NewsAction: String {
    case favourite, graph, note, research

    var label: String {
        switch self {
        case .favourite: return "Save"
        case .graph: return "Keep in graph"
        case .note: return "Link in note"
        case .research: return "Commission research"
        }
    }

    var icon: String {
        switch self {
        case .favourite: return "bookmark"
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .note: return "note.text"
        case .research: return "magnifyingglass"
        }
    }
}

/// Relative time, in the register the ledger's mono column wants.
func shortAgo(_ iso: String) -> String {
    guard let date = isoDate(iso) else { return "" }
    let seconds = max(0, -date.timeIntervalSinceNow)
    if seconds < 3600 { return "\(Int(seconds / 60))m" }
    if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
    return "\(Int(seconds / 86_400))d"
}

func isoDate(_ value: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return withFraction.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

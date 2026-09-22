import Foundation
import Combine

/// What the news screen knows.
@MainActor
final class NewsStore: ObservableObject {
    @Published private(set) var feed: NewsFeed?
    @Published private(set) var loading = false
    @Published var view: NewsView = .top
    @Published var sort: String = "time"
    @Published var message: String?
    /// Rows whose state this session has changed, laid over the server's answer
    /// so a tap shows immediately rather than at the next refresh.
    @Published private(set) var savedOverrides: [String: Bool] = [:]
    @Published private(set) var keptOverrides: Set<String> = []
    @Published private(set) var busyKey: String?

    private let client = SiteClient.shared

    var stories: [NewsStory] { feed?.stories ?? [] }

    func isSaved(_ story: NewsStory) -> Bool {
        savedOverrides[story.key] ?? (view == .favourites ? true : false)
    }

    func isKept(_ story: NewsStory) -> Bool {
        keptOverrides.contains(story.key) || story.kept
    }

    func load(force: Bool = false) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            var path = "api/native/news?view=\(view.rawValue)&sort=\(sort)"
            if force { path += "&fresh=1" }
            let result: NewsFeed = try await client.send(path)
            feed = result
            sort = result.sort
            // The server's answer is authoritative again after a refresh; an
            // override that outlived its round trip would show a stale tick.
            savedOverrides.removeAll()
            keptOverrides.removeAll()
            message = nil
        } catch SiteError.expired {
            message = "This iPhone needs pairing again."
        } catch {
            // A desk that has stories on screen keeps them. Replacing a readable
            // list with an error because a refresh failed is worse than the
            // stale list, and the wire is flaky by nature.
            message = feed == nil
                ? error.localizedDescription
                : "Could not refresh — showing what loaded last."
        }
    }

    func select(_ next: NewsView) async {
        guard next != view else { return }
        view = next
        // `best` ranks on heat, not points: raw scores are not comparable across
        // wires and one wire reports none at all, so a points default made
        // "best" mean "best on the two wires that vote".
        sort = next == .best ? "heat" : "time"
        feed = nil
        await load()
    }

    private struct FavouriteResult: Decodable { let favourite: Bool? }

    func act(_ action: NewsAction, on story: NewsStory) async {
        guard busyKey == nil else { return }
        busyKey = story.key
        defer { busyKey = nil }
        do {
            let body = try JSONEncoder().encode([
                "action": action.rawValue,
                "source": story.source,
                "id": story.storyId,
            ])
            let data = try await client.post("api/native/news/actions", body: body)
            switch action {
            case .favourite:
                let result = try? JSONDecoder().decode(FavouriteResult.self, from: data)
                let nowSaved = result?.favourite ?? !isSaved(story)
                savedOverrides[story.key] = nowSaved
                message = nowSaved ? "Saved." : "Removed from saved."
            case .graph:
                keptOverrides.insert(story.key)
                message = "Kept in the graph."
            case .note:
                message = "Linked in a note."
            case .research:
                message = "Research commissioned."
            }
        } catch SiteError.expired {
            message = "This iPhone needs pairing again."
        } catch {
            message = error.localizedDescription
        }
    }
}

/// One opened story.
@MainActor
final class StoryStore: ObservableObject {
    @Published private(set) var article: NewsArticle?
    @Published private(set) var loading = false
    @Published var message: String?
    /// Nil until this screen changes it — before that the server's `favourite`
    /// is the answer, and a `false` default would show an unsaved bookmark on a
    /// story that is in fact saved.
    @Published private(set) var savedOverride: Bool?

    private let client = SiteClient.shared

    var isSaved: Bool { savedOverride ?? article?.favourite ?? false }

    func load(source: String, id: String) async {
        loading = true
        defer { loading = false }
        do {
            article = try await client.send("api/native/news/story/\(source)/\(id)")
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private struct FavouriteResult: Decodable { let favourite: Bool? }

    func act(_ action: NewsAction, on story: NewsStory) async {
        do {
            let body = try JSONEncoder().encode([
                "action": action.rawValue,
                "source": story.source,
                "id": story.storyId,
            ])
            let data = try await client.post("api/native/news/actions", body: body)
            switch action {
            case .favourite:
                let result = try? JSONDecoder().decode(FavouriteResult.self, from: data)
                let nowSaved = result?.favourite ?? !isSaved
                savedOverride = nowSaved
                message = nowSaved ? "Saved." : "Removed from saved."
            case .graph: message = "Kept in the graph."
            case .note: message = "Linked in a note."
            case .research: message = "Research commissioned."
            }
        } catch SiteError.expired {
            message = "This iPhone needs pairing again."
        } catch {
            message = error.localizedDescription
        }
    }
}

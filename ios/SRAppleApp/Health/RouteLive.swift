import Foundation
import CoreLocation
import Combine

// A route walk shared live — SR-Main `$lib/home/presence/route-session`.
//
// The WALKER's side (`LiveShare`): start a session with the route's line, send
// fixes and this phone's own reading of the route every ~15 s, end it. With no
// signal the fixes wait in memory and go in one batch when it comes back —
// each carries its own time, so the follower's trail is still right.
//
// The FOLLOWER's side (`LiveWalksStore`, `LiveWalkStore`): the walks this
// phone may follow, and one of them refreshed while it is on screen. The Lock
// Screen card needs none of this — the site pushes it.

enum RouteLivePath {
    static let sessions = "api/native/route-session"
    static func session(_ id: String) -> String { "\(sessions)/\(TrailPath.escape(id))" }
    static func fixes(_ id: String) -> String { "\(session(id))/fixes" }
    static func end(_ id: String) -> String { "\(session(id))/end" }
}

// MARK: - The walker

@MainActor
final class LiveShare: ObservableObject {
    enum State: Equatable {
        case off
        case starting
        case live(followers: Int)
        case failed(String)
        case ended
    }

    @Published private(set) var state: State = .off
    @Published private(set) var shareURL: URL?
    /// Fixes not yet accepted by the site.
    @Published private(set) var backlog = 0

    private(set) var sessionId: String?
    private var pending: [[String: Double]] = []
    private var reading: RouteNav.Progress?
    private var timeLeftS: Double?
    private var timer: Timer?
    private var sending = false

    static let interval: TimeInterval = 15
    /// Six hours at one fix per 3 s is 7,200; a backlog past this keeps the newest.
    static let backlogMax = 3000

    private struct StartBody: Encodable {
        let routeId: String?
        let routeName: String
        let sport: String
        let route: [[Double]]
        let totalM: Double
        let share: Bool
    }

    private struct Started: Decodable {
        let id: String
        let followers: Int
        let shareUrl: String?
    }

    private struct FixesAnswer: Decodable {
        let ended: Bool?
    }

    func start(detail: PlannedRouteDetail, withLink: Bool) async {
        guard state == .off || state.isFailed else { return }
        state = .starting
        // 600 points is plenty to draw; the site thins to that anyway.
        let every = max(1, detail.route.count / 600)
        let line = detail.route.enumerated()
            .filter { $0.offset % every == 0 || $0.offset == detail.route.count - 1 }
            .map { [$0.element.lat, $0.element.lng] }
        let body = StartBody(
            routeId: detail.id, routeName: detail.name, sport: detail.sport,
            route: line, totalM: RouteNav.cumulative(detail.coordinates).last ?? detail.distanceM, share: withLink
        )
        do {
            let started: Started = try await SiteClient.shared.send(
                RouteLivePath.sessions, method: "POST", body: try JSONEncoder().encode(body), asSelf: true
            )
            sessionId = started.id
            shareURL = started.shareUrl.flatMap(URL.init(string:))
            state = .live(followers: started.followers)
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.flush() }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Called by the follow session for every fix it keeps.
    func add(_ fix: CLLocation, progress: RouteNav.Progress?, timeLeftS: Double?) {
        guard sessionId != nil, case .live = state else { return }
        pending.append(["lat": fix.coordinate.latitude, "lng": fix.coordinate.longitude, "t": fix.timestamp.timeIntervalSince1970])
        if pending.count > Self.backlogMax { pending.removeFirst(pending.count - Self.backlogMax) }
        backlog = pending.count
        if let progress { reading = progress }
        self.timeLeftS = timeLeftS
    }

    func flush() async {
        guard let id = sessionId, case .live = state, !sending, !pending.isEmpty else { return }
        sending = true
        defer { sending = false }
        let batch = Array(pending.prefix(500))
        var body: [String: Any] = ["fixes": batch]
        if let r = reading {
            var p: [String: Any] = ["alongM": r.alongM, "remainingM": r.remainingM, "offRouteM": r.offRouteM, "offRoute": r.offRoute]
            if let t = timeLeftS { p["timeLeftS"] = t }
            body["progress"] = p
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            let answer: FixesAnswer = try await SiteClient.shared.send(RouteLivePath.fixes(id), method: "POST", body: data, asSelf: true)
            pending.removeFirst(min(batch.count, pending.count))
            backlog = pending.count
            if answer.ended == true { stopLocally(.ended) }
        } catch {
            // No signal: keep them for the next tick.
        }
    }

    /// Stop sharing. `finished` says the walk was completed; anything else is a stop.
    func end(finished: Bool) async {
        guard let id = sessionId else { stopLocally(.off); return }
        await flush()
        let body = try? JSONSerialization.data(withJSONObject: ["reason": finished ? "finished" : "stopped"])
        _ = try? await SiteClient.shared.call(RouteLivePath.end(id), method: "POST", body: body)
        stopLocally(.ended)
    }

    private func stopLocally(_ next: State) {
        timer?.invalidate()
        timer = nil
        state = next
        shareURL = nil
    }
}

private extension LiveShare.State {
    var isFailed: Bool { if case .failed = self { return true } else { return false } }
}

// MARK: - The follower

struct LiveWalk: Decodable, Identifiable, Hashable {
    struct Reading: Decodable, Hashable {
        let alongM: Double
        let remainingM: Double
        let offRouteM: Double
        let offRoute: Bool
        let timeLeftS: Double?
    }

    let id: String
    let name: String
    let routeName: String
    let sport: String
    let route: [RoutePoint]
    let trail: [RoutePoint]
    let totalM: Double
    let progress: Reading?
    let startedAt: String
    let lastFixAt: String?
    let endedAt: String?
    let endReason: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, routeName, sport, route, trail, totalM, progress, startedAt, lastFixAt, endedAt, endReason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        routeName = try c.decode(String.self, forKey: .routeName)
        sport = (try? c.decode(String.self, forKey: .sport)) ?? "walk"
        route = RoutePoint.decodeList((try? c.decodeIfPresent([[Double?]].self, forKey: .route)) ?? [])
        // The trail's third element is a time, not a height.
        trail = RoutePoint.decodeList((try? c.decodeIfPresent([[Double?]].self, forKey: .trail)) ?? [])
            .map { RoutePoint(lat: $0.lat, lng: $0.lng, ele: nil) }
        totalM = (try? c.decode(Double.self, forKey: .totalM)) ?? 0
        progress = try? c.decodeIfPresent(Reading.self, forKey: .progress)
        startedAt = (try? c.decode(String.self, forKey: .startedAt)) ?? ""
        lastFixAt = try? c.decodeIfPresent(String.self, forKey: .lastFixAt)
        endedAt = try? c.decodeIfPresent(String.self, forKey: .endedAt)
        endReason = try? c.decodeIfPresent(String.self, forKey: .endReason)
    }

    var fraction: Double {
        guard let p = progress, totalM > 0 else { return 0 }
        return min(1, max(0, p.alongM / totalM))
    }

    var line: String {
        if endedAt != nil {
            return endReason == "finished" ? "Finished" : "No longer shared"
        }
        guard let p = progress else { return "Starting" }
        if p.offRoute { return "Off route · \(TrailFormat.metres(p.offRouteM)) m from the line" }
        var parts = ["\(TrailFormat.km(p.alongM)) of \(TrailFormat.km(totalM)) km"]
        if let t = p.timeLeftS, p.remainingM > 50 { parts.append("~\(TrailFormat.duration(t)) left") }
        return parts.joined(separator: " · ")
    }
}

struct LiveWalksPage: Decodable {
    let sessions: [LiveWalk]
}

/// Pushed on the Family tab.
struct LiveWalkRef: Hashable {
    let id: String
    let title: String
}

@MainActor
final class LiveWalksStore: ObservableObject {
    static let shared = LiveWalksStore()
    @Published private(set) var walks: [LiveWalk] = []

    func load() async {
        guard SiteClient.shared.isPaired else { return }
        if let page: LiveWalksPage = try? await SiteClient.shared.send(RouteLivePath.sessions) {
            walks = page.sessions
        }
    }
}

@MainActor
final class LiveWalkStore: ObservableObject {
    @Published private(set) var walk: LiveWalk?
    @Published private(set) var state: TrailLoad = .idle

    func load(_ id: String) async {
        if walk == nil { state = .loading }
        do {
            walk = try await SiteClient.shared.send(RouteLivePath.session(id))
            state = .loaded
        } catch {
            state = walk == nil ? TrailLoad.from(error) : .loaded
        }
    }
}

// MARK: - Routes sent to a family member

/// A saved route the owner sent to this phone to walk. The route arrives
/// whole — a member cannot read the owner's routes, only what was sent.
struct RouteGift: Decodable, Identifiable {
    let id: String
    let sentAt: String
    let route: PlannedRouteDetail
}

struct RouteGiftRecipient: Decodable, Identifiable, Hashable {
    let subject: String
    let name: String
    var id: String { subject }
}

struct RouteGiftsPage: Decodable {
    let gifts: [RouteGift]
    /// Who the owner can send to; empty for anyone else.
    let recipients: [RouteGiftRecipient]
}

enum RouteGiftPath {
    static let gifts = "api/native/route-gifts"
    static func gift(_ id: String) -> String { "\(gifts)/\(TrailPath.escape(id))" }
}

@MainActor
final class RouteGiftsStore: ObservableObject {
    static let shared = RouteGiftsStore()
    @Published private(set) var gifts: [RouteGift] = []
    @Published private(set) var recipients: [RouteGiftRecipient] = []
    @Published var message: String?

    func load() async {
        guard SiteClient.shared.isPaired else { return }
        if let page: RouteGiftsPage = try? await SiteClient.shared.send(RouteGiftPath.gifts) {
            gifts = page.gifts
            recipients = page.recipients
        }
    }

    func send(routeId: String, to person: RouteGiftRecipient) async {
        struct Body: Encodable { let routeId: String; let toSubject: String }
        do {
            try await SiteClient.shared.post(RouteGiftPath.gifts, body: try JSONEncoder().encode(Body(routeId: routeId, toSubject: person.subject)))
            message = "Sent to \(person.name). It is on their Family tab."
        } catch {
            message = error.localizedDescription
        }
    }

    func dismiss(_ id: String) async {
        gifts.removeAll { $0.id == id }
        _ = try? await SiteClient.shared.call(RouteGiftPath.gift(id), method: "DELETE")
    }
}

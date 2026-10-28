import Foundation

// Games on the Home Screen and the Lock Screen: invites waiting, games where
// it is your move, and how the last one ended. What the app leaves on the
// Keychain shelf (`FamilyShelf`, account `.games`), the thin lobby a widget
// reads for itself, and every rule about them as a pure function.
//
// SHARED with the widget extension (`SRAppleLive`, see watch.yml), so nothing
// here may reach for the app: no `GamesLobby`, no `GameKind`, no
// `GameDeadline`. Foundation only, so the Linux harness runs its tests
// (`scripts/home-check.sh`).
//
// The widget never joins, declines or plays. Every tap opens the app: the
// room for a row, the Games tab for the rest.

// MARK: - The lobby, as a widget reads it

/// `GET /api/native/games`, as thinly as a widget needs it. The app maps its
/// own `GamesLobby` into this; the widget decodes it straight off the wire
/// when it refreshes on its own. Lenient: a missing field costs that field,
/// one bad row costs that row.
struct GamesWidgetFeed: Decodable, Equatable {
    struct Invite: Decodable, Equatable {
        var roomId: String
        var game: String
        var hostName: String
        /// Server epoch ms.
        var expiresAt: Double?

        init(roomId: String, game: String, hostName: String, expiresAt: Double? = nil) {
            self.roomId = roomId
            self.game = game
            self.hostName = hostName
            self.expiresAt = expiresAt
        }

        private enum CodingKeys: String, CodingKey { case roomId, game, hostName, expiresAt }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            roomId = try c.decode(String.self, forKey: .roomId)
            game = (try? c.decodeIfPresent(String.self, forKey: .game)) ?? "tap-duel"
            hostName = (try? c.decodeIfPresent(String.self, forKey: .hostName)) ?? "Someone"
            expiresAt = (try? c.decodeIfPresent(Double.self, forKey: .expiresAt)) ?? nil
        }
    }

    struct Room: Decodable, Equatable {
        var id: String
        var game: String
        /// The site's phase, as a string: "lobby", "playing", "finished"…
        var phase: String
        var hostName: String
        var myTurn: Bool
        var waitingFor: [String]
        /// Server epoch ms.
        var dueAt: Double?
        var updatedAt: Double?
        var summary: String?

        init(id: String, game: String, phase: String, hostName: String, myTurn: Bool = false,
             waitingFor: [String] = [], dueAt: Double? = nil, updatedAt: Double? = nil, summary: String? = nil) {
            self.id = id
            self.game = game
            self.phase = phase
            self.hostName = hostName
            self.myTurn = myTurn
            self.waitingFor = waitingFor
            self.dueAt = dueAt
            self.updatedAt = updatedAt
            self.summary = summary
        }

        private enum CodingKeys: String, CodingKey { case id, game, phase, hostName, myTurn, waitingFor, dueAt, updatedAt, summary }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            game = (try? c.decodeIfPresent(String.self, forKey: .game)) ?? "game"
            phase = (try? c.decodeIfPresent(String.self, forKey: .phase)) ?? "unknown"
            hostName = (try? c.decodeIfPresent(String.self, forKey: .hostName)) ?? "Someone"
            myTurn = (try? c.decodeIfPresent(Bool.self, forKey: .myTurn)) ?? false
            waitingFor = (try? c.decodeIfPresent([String].self, forKey: .waitingFor)) ?? []
            dueAt = (try? c.decodeIfPresent(Double.self, forKey: .dueAt)) ?? nil
            updatedAt = (try? c.decodeIfPresent(Double.self, forKey: .updatedAt)) ?? nil
            let line = ((try? c.decodeIfPresent(String.self, forKey: .summary)) ?? nil)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            summary = (line?.isEmpty ?? true) ? nil : line
        }
    }

    var invites: [Invite]
    var rooms: [Room]
    /// Server epoch ms at the read, so its other times can be put on this
    /// phone's clock. 0 from an older site.
    var serverNow: Double

    init(invites: [Invite], rooms: [Room], serverNow: Double) {
        self.invites = invites
        self.rooms = rooms
        self.serverNow = serverNow
    }

    private enum CodingKeys: String, CodingKey { case invites, rooms, serverNow }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        invites = ((try? c.decodeIfPresent([Lossy<Invite>].self, forKey: .invites)) ?? []).compactMap(\.value)
        rooms = ((try? c.decodeIfPresent([Lossy<Room>].self, forKey: .rooms)) ?? []).compactMap(\.value)
        serverNow = (try? c.decodeIfPresent(Double.self, forKey: .serverNow)) ?? 0
    }

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
}

// MARK: - What the shelf holds

/// One row on the widget: an invite, a game waiting on me, or the last one
/// that finished.
struct GamesWidgetRow: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case invite, move, result }

    var kind: Kind
    var roomId: String
    /// The game's kind, for the link (`sr://games/<room>?game=<kind>`).
    var game: String
    /// "Chess", "Quiz Night".
    var title: String
    /// Who hosts it: the invite's sender, the last game's host.
    var host: String
    /// Invite: when it lapses. Move: the decision's deadline. Result: when
    /// it finished. On this phone's clock.
    var at: Date?
    /// The game's own line, when it has one: a county's "Sunnyvale · Town".
    var detail: String?

    var id: String { "\(kind.rawValue):\(roomId)" }
}

struct GamesWidgetSnapshot: Codable, Equatable {
    var invites: [GamesWidgetRow]
    var moves: [GamesWidgetRow]
    /// Games under way that are not waiting on me: "2 on the go".
    var playing: Int
    var last: GamesWidgetRow?
    /// Each game's title by kind, from the app — so a widget that reads the
    /// lobby for itself names games as the app does, not by their slugs.
    var titles: [String: String]
    var savedAt: Date

    func sameContent(as other: GamesWidgetSnapshot?) -> Bool {
        guard var other else { return false }
        other.savedAt = savedAt
        return other == self
    }
}

// MARK: - Rules

enum GamesWidget {
    /// The most of each kind of row the shelf keeps.
    static let keep = 4

    /// Phases that are no longer a game to play: over, or closed unplayed.
    static let over: Set<String> = ["finished", "closed"]

    /// The shelf's snapshot of a lobby, as of `now`. PURE.
    static func snapshot(_ feed: GamesWidgetFeed, titles: [String: String], now: Date = Date(),
                         keep: Int = GamesWidget.keep) -> GamesWidgetSnapshot {
        // The site's clock, put on this phone's: an invite that lapses in
        // two minutes there lapses in two minutes here. To the minute, so
        // the round trip's jitter does not make every poll a "change".
        let offset = feed.serverNow > 0 ? feed.serverNow / 1000 - now.timeIntervalSince1970 : 0
        func local(_ ms: Double?) -> Date? {
            ms.map { Date(timeIntervalSince1970: (($0 / 1000 - offset) / 60).rounded() * 60) }
        }
        func name(_ game: String) -> String { title(game, titles: titles) }

        let invites = feed.invites
            .filter { invite in local(invite.expiresAt).map { $0 > now } ?? true }
            .prefix(max(keep, 0))
            .map { GamesWidgetRow(kind: .invite, roomId: $0.roomId, game: $0.game, title: name($0.game),
                                  host: $0.hostName, at: local($0.expiresAt), detail: nil) }

        let live = feed.rooms.filter { !over.contains($0.phase) && $0.phase != "lobby" }
        // Soonest deadline first; one without a deadline after them.
        let moves = live.filter(\.myTurn).enumerated().sorted { a, b in
            let x = a.element.dueAt ?? .infinity, y = b.element.dueAt ?? .infinity
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element).prefix(max(keep, 0)).map {
            GamesWidgetRow(kind: .move, roomId: $0.id, game: $0.game, title: name($0.game),
                           host: $0.hostName, at: local($0.dueAt), detail: $0.summary)
        }

        let finished = feed.rooms.filter { $0.phase == "finished" }
        let newest = finished.enumerated().max { a, b in
            let x = a.element.updatedAt ?? 0, y = b.element.updatedAt ?? 0
            return x == y ? a.offset > b.offset : x < y
        }?.element
        let last = newest.map {
            GamesWidgetRow(kind: .result, roomId: $0.id, game: $0.game, title: name($0.game),
                           host: $0.hostName, at: local($0.updatedAt), detail: $0.summary)
        }

        // Only the titles the snapshot names: the shelf is not a catalogue.
        let named = Set((Array(invites) + Array(moves) + [last].compactMap { $0 }).map(\.game))
        return GamesWidgetSnapshot(
            invites: Array(invites), moves: Array(moves), playing: live.filter { !$0.myTurn }.count,
            last: last, titles: titles.filter { named.contains($0.key) }, savedAt: now
        )
    }

    /// The snapshot as it stands at `now`: invites that have lapsed since it
    /// was saved are gone. The rest is the site's to change.
    static func live(_ snapshot: GamesWidgetSnapshot, now: Date) -> GamesWidgetSnapshot {
        var out = snapshot
        out.invites = snapshot.invites.filter { $0.at.map { $0 > now } ?? true }
        return out
    }

    /// "Chess", or "Space Race" for a kind this app has no title for.
    static func title(_ game: String, titles: [String: String]) -> String {
        if let known = titles[game], !known.isEmpty { return known }
        return game.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// "2 invites", "Your move", "2 waiting on you", "All quiet".
    static func headline(_ s: GamesWidgetSnapshot) -> String {
        if !s.invites.isEmpty { return s.invites.count == 1 ? "1 invite" : "\(s.invites.count) invites" }
        if s.moves.count == 1 { return "Your move" }
        if s.moves.count > 1 { return "\(s.moves.count) waiting on you" }
        return "All quiet"
    }

    /// How many things want this person: invites and moves.
    static func waiting(_ s: GamesWidgetSnapshot) -> Int { s.invites.count + s.moves.count }

    /// "21 h left", "40 min left", "2 days left", "Time's up" — as
    /// `GameDeadline` says it, hours rounded down and minutes up.
    static func left(until date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds.isFinite, seconds > 0 else { return "Time's up" }
        if seconds >= 2 * 86_400 { return "\(Int(seconds / 86_400)) days left" }
        if seconds >= 3600 { return "\(Int(seconds / 3600)) h left" }
        return "\(max(1, Int((seconds / 60).rounded(.up)))) min left"
    }

    /// A row's second line: "From Robin", "Your move · 21 h left",
    /// "Finished · Mon".
    static func detail(_ row: GamesWidgetRow, now: Date, calendar: Calendar = .current) -> String {
        switch row.kind {
        case .invite:
            return "From \(firstName(row.host))"
        case .move:
            if let detail = row.detail { return detail }
            guard let due = row.at else { return "Your move" }
            return "Your move · \(left(until: due, now: now))"
        case .result:
            guard let at = row.at else { return "Finished" }
            let when = FamilyMessagesWidget.when(at, now: now, calendar: calendar)
            return when == "now" ? "Finished just now" : "Finished · \(when)"
        }
    }

    static func symbol(_ kind: GamesWidgetRow.Kind) -> String {
        switch kind {
        case .invite: return "envelope.fill"
        case .move: return "arrow.turn.down.right"
        case .result: return "flag.checkered"
        }
    }

    /// The rows a widget lists, most pressing first: invites, then moves,
    /// then the last result.
    static func rows(_ s: GamesWidgetSnapshot, limit: Int) -> [GamesWidgetRow] {
        Array((s.invites + s.moves + [s.last].compactMap { $0 }).prefix(max(limit, 0)))
    }

    /// Where a tap goes: the one room when there is one thing to do, the
    /// Games tab otherwise.
    static func url(_ s: GamesWidgetSnapshot?) -> URL {
        guard let s else { return GlanceLink.gamesURL }
        let pressing = s.invites + s.moves
        if pressing.count == 1, let row = pressing.first { return GlanceLink.gameURL(room: row.roomId, game: row.game) }
        return GlanceLink.gamesURL
    }

    /// When the face changes on its own: each invite lapsing and each
    /// deadline. Sorted, from `now`.
    static func timeline(_ s: GamesWidgetSnapshot?, now: Date, limit: Int = 12) -> [Date] {
        var dates: Set<Date> = [now]
        for row in (s?.invites ?? []) + (s?.moves ?? []) {
            if let at = row.at, at > now { dates.insert(at) }
        }
        return Array(dates.sorted().prefix(max(limit, 1)))
    }

    static func firstName(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? name
    }
}

// MARK: - Samples

/// Made-up games for the widget's placeholder and the gallery.
enum GamesWidgetSamples {
    static func snapshot(now: Date = Date()) -> GamesWidgetSnapshot {
        let ms = now.timeIntervalSince1970 * 1000
        let feed = GamesWidgetFeed(
            invites: [GamesWidgetFeed.Invite(roomId: "g1", game: "quiz-night", hostName: "Robin", expiresAt: ms + 9 * 60_000)],
            rooms: [
                GamesWidgetFeed.Room(id: "g2", game: "chess", phase: "playing", hostName: "Kit", myTurn: true, dueAt: ms + 21 * 3_600_000),
                GamesWidgetFeed.Room(id: "g3", game: "homestead", phase: "playing", hostName: "Sam", waitingFor: ["Sam"]),
                GamesWidgetFeed.Room(id: "g4", game: "wordle-race", phase: "finished", hostName: "Sam", updatedAt: ms - 3 * 3_600_000),
            ],
            serverNow: ms
        )
        let titles = ["quiz-night": "Quiz Night", "chess": "Chess", "homestead": "Homestead", "wordle-race": "Wordle Race"]
        return GamesWidget.snapshot(feed, titles: titles, now: now)
    }
}

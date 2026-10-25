import Foundation
import UserNotifications

// Durable rooms on the phone: the pace a host picks, "Your games" with whose
// turn it is and how long is left, and the "your move" push — see
// docs/specs/2026-10-22-family-games-durable-rooms.md.
//
// A durable room is written to the site's database after every move, so it
// survives a deploy and can be played over days ("async" pace). The wire
// fields are all optional: an older site sends none of them, and every room
// then reads as live and not durable, exactly as before.

/// How a durable game is played: everyone at once, or a move each over days.
enum GamePace: String, CaseIterable, Identifiable, Codable {
    case live
    case async

    var id: String { rawValue }

    /// The picker's words. Never "async": that is the wire's word, not a person's.
    var label: String {
        switch self {
        case .live: return "Play now"
        case .async: return "Over days"
        }
    }

    var line: String {
        switch self {
        case .live: return "Everyone together, with short turn timers."
        case .async: return "A move each whenever you can. Your phone tells you when it's your turn."
        }
    }

    /// Hours a turn may take in an async game — the site's own list.
    static let deadlineHours = [12, 24, 48]
    static let defaultDeadlineHours = 24

    /// A pace string from the wire; anything unknown is live, as on the site.
    static func from(_ raw: String?) -> GamePace {
        raw.flatMap(GamePace.init(rawValue:)) ?? .live
    }

    static func hoursLabel(_ hours: Int) -> String { "\(hours) h" }
}

/// The new-game sheet's pace choice, folded into what Start sends.
struct GamePaceSettings: Equatable {
    var pace: GamePace = .live
    var deadlineHours: Int = GamePace.defaultDeadlineHours

    /// The create body with `pace` (and, over days, `deadlineHours`) set.
    /// Applied only for a game the lobby lists in `paces`: a game that does
    /// not offer a pace never sends one.
    func apply(to body: CreateGameBody) -> CreateGameBody {
        var out = body
        out.pace = pace.rawValue
        out.deadlineHours = pace == .async
            ? (GamePace.deadlineHours.contains(deadlineHours) ? deadlineHours : GamePace.defaultDeadlineHours)
            : nil
        return out
    }

    /// One line under the picker.
    var line: String {
        switch pace {
        case .live: return GamePace.live.line
        case .async: return "Up to \(deadlineHours) hours a turn. Run out and the game moves for you."
        }
    }
}

extension GamesLobby {
    /// The paces a game offers. Only games that can be played over days are
    /// listed by the site; every other game is live only.
    func paceChoices(for game: String) -> [GamePace] {
        let listed = (paces[game] ?? []).compactMap(GamePace.init(rawValue:))
        return listed.contains(.async) ? listed : []
    }
}

// MARK: - Deadlines

enum GameDeadline {
    /// "21 h left", "40 min left", "Time's up". Whole hours round down and
    /// minutes round up, so the line never promises more time than there is
    /// and never says "0 min" with a minute to go.
    static func left(until dueAt: Double, atServer now: Double) -> String {
        let seconds = (dueAt - now) / 1000
        guard seconds.isFinite, seconds > 0 else { return "Time's up" }
        if seconds >= 3600 { return "\(Int(seconds / 3600)) h left" }
        return "\(max(1, Int((seconds / 60).rounded(.up)))) min left"
    }

    /// A lobby's ticking clock: "2:41" under an hour, "23 h 59 m" past one.
    /// An async lobby is held open for a day, which "1439:59" did not say.
    static func clock(seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 { return "\(s / 3600) h \(String(format: "%02d", (s % 3600) / 60)) m" }
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

// MARK: - Your games

enum YourGames {
    /// My move first (the soonest deadline first), then everything else by
    /// its last change, newest first. A room with no `updatedAt` — an
    /// in-memory game, playing right now — sorts as just changed, so live
    /// games stay above days-old ones, in the order the site sent them.
    static func ordered(_ rooms: [GameRoomSummary]) -> [GameRoomSummary] {
        let indexed = Array(rooms.enumerated())
        return indexed.sorted { a, b in
            let (x, y) = (a.element, b.element)
            if x.myTurn != y.myTurn { return x.myTurn }
            if x.myTurn {
                let dx = x.dueAt ?? .infinity, dy = y.dueAt ?? .infinity
                if dx != dy { return dx < dy }
            }
            let ux = x.updatedAt ?? .infinity, uy = y.updatedAt ?? .infinity
            if ux != uy { return ux > uy }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// The row's second line for a durable room: "Your move · 21 h left",
    /// "Waiting for Rory". Nil for a room that is not durable, or that waits
    /// on nobody (a lobby, a finished game): the row says who hosts it.
    static func status(_ room: GameRoomSummary, atServer now: Double?) -> String? {
        guard room.durable else { return nil }
        // A county has no turns: it waits on nobody, and its row says how the
        // town is doing (the site's summary) and whether something is waiting
        // for me — an offer, a vote, a gift, the Gazette. No deadline: a
        // county never runs out of time.
        if room.game == GameKind.hometowns.rawValue {
            let base = room.summary ?? "Your county"
            return room.myTurn ? "\(base) · something waiting" : base
        }
        if room.myTurn {
            guard let due = room.dueAt, let now else { return "Your move" }
            return "Your move · \(GameDeadline.left(until: due, atServer: now))"
        }
        guard !room.waitingFor.isEmpty else { return nil }
        return "Waiting for \(GameNames.list(room.waitingFor))"
    }

    /// The row's pace line for a game played over days.
    static func paceLine(_ room: GameRoomSummary) -> String {
        room.game == GameKind.hometowns.rawValue
            ? "A year a day · hosted by \(room.hostName)"
            : "\(GamePace.async.label) · hosted by \(room.hostName)"
    }

    /// How many rooms are waiting on me — the chip's count.
    static func myMoves(_ rooms: [GameRoomSummary]) -> Int { rooms.filter(\.myTurn).count }
}

// MARK: - The "your move" push

/// A `game` notification from the site: an invite, a turn ("Your move in
/// Homestead"), or a finish ("Homestead is over"). All open the room through
/// the existing `category == "game"` tap path; this decides what happens when
/// one arrives with the app open.
enum GameTurnPush {
    /// Posted (object: the room id) when a game push lands in the foreground,
    /// so the room on screen and the lobby re-read at once.
    static let arrived = Notification.Name("SRGamePushArrived")

    /// The room a `game` notification is about, or nil for any other.
    static func roomId(category: String, userInfo: [AnyHashable: Any]) -> String? {
        guard category == "game" else { return nil }
        return userInfo["roomId"] as? String
    }

    /// `turn`, `finished`, or nil (an invite carries no kind).
    static func kind(_ userInfo: [AnyHashable: Any]) -> String? {
        userInfo["kind"] as? String
    }

    /// Swallowed while the room it is about is the one on screen: the board
    /// already shows it is my move, and a banner over it is noise.
    static func silenced(roomId: String?, onScreen: Set<String>) -> Bool {
        guard let roomId else { return false }
        return onScreen.contains(roomId)
    }

    /// The notification id the site uses (`collapseId`), and the local
    /// invite banner's. Opening the room clears it: it has been answered.
    static func identifier(_ roomId: String) -> String { "game-\(roomId)" }
}

/// Which rooms a `GameRoomLink` is holding open right now — the room on
/// screen. Counted, so a link closing never forgets another's room.
@MainActor
enum GameRoomsOnScreen {
    private(set) static var counts: [String: Int] = [:]

    static var ids: Set<String> { Set(counts.keys) }

    static func opened(_ roomId: String) {
        counts[roomId, default: 0] += 1
    }

    static func closed(_ roomId: String) {
        guard let n = counts[roomId] else { return }
        if n <= 1 { counts[roomId] = nil } else { counts[roomId] = n - 1 }
    }

    /// Clear the room's delivered banner: it is on screen now.
    static func clearDelivered(_ roomId: String) {
        guard !SRDemo.isOn else { return }
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [GameTurnPush.identifier(roomId)])
    }
}

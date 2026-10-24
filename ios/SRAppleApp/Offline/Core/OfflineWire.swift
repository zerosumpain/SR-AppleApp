import Foundation

// What travels between phones. One JSON object per message, inside whichever
// link is carrying it — a MultipeerConnectivity data packet, or a 4-byte
// big-endian length followed by the JSON on a TCP stream.
//
//   guest → host   hello · action · ping · bye
//   host  → guest  welcome · refused · lobby · view · refusal · pong · bye
//
// The host's choices — which game, start, play again — are not messages of
// their own: the host makes them on its own phone and every guest sees the
// result in the next `lobby`. A finished match is a `lobby` whose phase is
// `.finished`, carrying the standings.

/// The envelope: a version, then the message.
struct OfflineEnvelope: Codable, Equatable {
    /// Bumped when a message changes shape. A host refuses a guest on another
    /// version with a sentence, rather than both phones misreading each other.
    static let version = 1

    var v: Int
    var message: OfflineMessage

    init(_ message: OfflineMessage) {
        self.v = Self.version
        self.message = message
    }

    func encoded() throws -> Data { try OfflineCoding.encode(self) }

    static func decode(_ data: Data) throws -> OfflineEnvelope {
        try OfflineCoding.decode(OfflineEnvelope.self, from: data)
    }
}

/// One message.
enum OfflineMessage: Codable, Equatable {
    /// Guest → host, first thing on connecting: who I am.
    case hello(playerId: String, name: String, version: Int)
    /// Host → guest: you are in.
    case welcome(playerId: String, hostId: String, roomName: String)
    /// Host → guest: you are not in (room full, other version). The host
    /// closes the connection after sending it.
    case refused(reason: String)
    /// Host → everyone: who is here, which game, what phase.
    case lobby(OfflineLobby)
    /// Host → one player: their view of the match (the game's `PlayerView`
    /// as JSON).
    case view(OfflineViewPacket)
    /// Guest → host: one action (the game's `Action` as JSON). `match` is the
    /// lobby's match number, so a move meant for the last match is dropped.
    case action(seq: Int, match: Int, data: Data)
    /// Host → guest: action `seq` was illegal, and why.
    case refusal(seq: Int, reason: String)
    /// Guest → host: what time is it? `sentAt` is the guest's own clock.
    case ping(id: Int, sentAt: Double)
    /// Host → guest: the answer, with the guest's `sentAt` echoed back.
    case pong(id: Int, sentAt: Double, hostNow: Double)
    /// Either way: I am leaving. From the host, the room is closed.
    case bye(reason: String)
}

/// The phase of a room.
enum OfflineRoomPhase: String, Codable, Equatable {
    /// Gathering players; the host picks a game.
    case lobby
    /// A match is running.
    case playing
    /// A match has ended; standings are in the lobby.
    case finished
}

/// One person in the lobby.
struct OfflineLobbyPlayer: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    /// False while a player who was in the match is out of reach.
    var present: Bool
    /// In the running match (rather than waiting for the next one).
    var inMatch: Bool

    var player: OfflinePlayer { OfflinePlayer(id: id, name: name) }
}

/// The room, as every player sees it.
struct OfflineLobby: Codable, Equatable {
    var hostId: String
    var roomName: String
    var players: [OfflineLobbyPlayer]
    /// The game the host has chosen, by `OfflineGameInfo.id`.
    var gameId: String?
    var phase: OfflineRoomPhase
    /// Counts matches started in this room; actions carry it.
    var match: Int
    /// The last match's table, once it has finished.
    var standings: [OfflineStanding]?

    /// The players as `OfflinePlayer`, seat order.
    var roster: [OfflinePlayer] { players.map(\.player) }
}

/// One player's view of the match.
struct OfflineViewPacket: Codable, Equatable {
    var gameId: String
    var match: Int
    /// The game's `PlayerView`, as JSON.
    var data: Data
    var over: Bool
}

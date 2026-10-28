import Foundation

/// Which ways a game can be played with no internet: alone (by itself, or
/// against the phone's computer players) and with phones nearby. Pure, so
/// the Games page can ask about any game, online or offline, without
/// building a room.
enum OfflinePlayModes {
    /// Computer players a solo game seats, or nil when it cannot be played
    /// alone: none for a one-player game, else enough to start (at least one
    /// opponent) for a game with a bot — or the game's own
    /// `soloOpponents`, kept to the seats the table and the room have.
    static func soloBots(_ info: OfflineGameInfo, hasBot: Bool) -> Int? {
        if info.minPlayers <= 1 { return 0 }
        guard hasBot else { return nil }
        let fewest = max(1, info.minPlayers - 1)
        let most = max(fewest, min(info.maxPlayers, OfflineRoom.capacity, OfflineRoom.botNames.count + 1) - 1)
        return min(max(info.soloOpponents ?? fewest, fewest), most)
    }

    static func canPlaySolo(_ info: OfflineGameInfo, hasBot: Bool) -> Bool {
        soloBots(info, hasBot: hasBot) != nil
    }

    /// Every offline game is a nearby game: that is what the room is for.
    /// One that needs more people than a room holds is the only exception.
    static func canPlayNearby(_ info: OfflineGameInfo) -> Bool {
        info.minPlayers <= OfflineRoom.capacity
    }

    /// The Games page's online games that also have an offline version here,
    /// by the online game's id → the offline game's id. The online game keeps
    /// its own rules on the site; this one runs on the phone.
    static let offlineTwin: [String: String] = [
        "maths-sprint": "maths-sprint",
    ]

    /// The offline game to open for a game id from either catalogue.
    static func offlineId(for kind: String) -> String {
        offlineTwin[kind] ?? kind
    }
}

extension OfflinePeerHealth {
    /// The host's answer to "Test connection": everyone fine, or who is not.
    static func summary(_ guests: [(name: String, health: OfflinePeerHealth)]) -> String {
        guard !guests.isEmpty else {
            return "Nobody has joined yet. Your room is being advertised again now — ask them to tap Find a room."
        }
        let trouble = guests.filter(\.health.isTrouble)
        if trouble.isEmpty {
            return guests.count == 1
                ? "\(guests[0].name)'s phone answered in the last few seconds."
                : "All \(guests.count) phones answered in the last few seconds."
        }
        return trouble.map { guest in
            switch guest.health {
            case .away: return "\(guest.name) is out of reach — they can rejoin from Find a room."
            case .quiet(let seconds) where seconds > 0: return "\(guest.name) has been quiet for \(seconds) s — ask them to open the app."
            default: return "\(guest.name) is still connecting."
            }
        }.joined(separator: " ")
    }
}

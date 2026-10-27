import Foundation

/// One message for one player, from the host.
struct OfflineOutgoing: Equatable {
    /// A player id — the host's own included (the session delivers that one
    /// locally, so the host plays through exactly the same path).
    let to: String
    let message: OfflineMessage
}

/// The host's room, as a pure value: who is in it, which game, the running
/// match, and what each player has been sent.
///
/// No transport, no timers, no main actor. The session feeds it what happened
/// — a hello, an action, a tick, a dropped connection — then asks `outbox()`
/// what to send, and the room answers with exactly the messages whose content
/// changed: a lobby to whoever has not seen this one, a view to each player
/// whose view is different from the last one they got. So "who sees what" is
/// decided here, once, and tested without a single phone.
struct OfflineRoom {
    /// Five phones, the host's included. MultipeerConnectivity is happiest at
    /// eight or fewer, and five keeps a TCP hotspot room comfortable.
    static let capacity = 5

    /// Computer players' names, in the order they sit down: four, so a host
    /// alone can fill every other seat at the table.
    static let botNames = ["Robo", "Chip", "Pixel", "Sprocket"]

    let hostId: String
    let roomName: String
    /// The room's id on the air and in synced results (`OfflineLobby.roomKey`).
    let roomKey: String
    private let games: [String: OfflineGameEntry]

    /// Seat order: the host first, then guests as they joined.
    private(set) var players: [OfflineLobbyPlayer]
    private(set) var gameId: String?
    private(set) var phase: OfflineRoomPhase = .lobby
    /// Matches started in this room. Actions carry it.
    private(set) var matchNumber = 0
    private(set) var standings: [OfflineStanding]?
    private var match: (any OfflineMatch)?

    private var lobbySent: [String: OfflineLobby] = [:]
    private var viewSent: [String: OfflineViewPacket] = [:]
    /// Host clock: when each computer player next looks for a move.
    private var botDue: [String: Double] = [:]
    /// The view each computer player last "saw", so a change to it (its
    /// turn coming round) starts its thinking time afresh.
    private var botSeen: [String: Data] = [:]
    /// Host clock: when each player who dropped mid-match was last here.
    /// The game is not told until `seatHeld` has passed, so a blip in a
    /// two-player game does not hand the other player a forfeit win.
    private var awaySince: [String: Double] = [:]

    /// How long a dropped player's seat is held before the game plays on
    /// without them. A little longer than the guest keeps trying to get back
    /// (`OfflineReconnect.patience`), because the two phones notice the drop
    /// a few seconds apart and the host must not give up first.
    static let seatHeld: Double = OfflineReconnect.patience + 10

    init(host: OfflinePlayer, roomName: String, games: [OfflineGameEntry],
         roomKey: String = OfflineDiscovery.roomKey(seed: OfflineRNG.freshSeed())) {
        self.hostId = host.id
        self.roomName = roomName
        self.roomKey = roomKey
        var byId: [String: OfflineGameEntry] = [:]
        for entry in games { byId[entry.info.id] = entry }
        self.games = byId
        self.players = [OfflineLobbyPlayer(id: host.id, name: host.name, present: true, inMatch: false)]
    }

    // MARK: - What everyone sees

    var lobby: OfflineLobby {
        OfflineLobby(hostId: hostId, roomName: roomName, players: players, gameId: gameId,
                     phase: phase, match: matchNumber, standings: standings, roomKey: roomKey)
    }

    /// Computer players in the room.
    var bots: [OfflineLobbyPlayer] { players.filter(\.isBot) }

    /// Whether a computer player may be added now, as a refusal sentence; nil when it may.
    var addBotProblem: String? {
        if phase == .playing { return "Finish this game first." }
        guard let entry else { return "Pick a game first." }
        guard entry.hasBot else { return "\(entry.info.title) has no computer player yet." }
        if players.count >= min(Self.capacity, entry.info.maxPlayers) {
            return "\(entry.info.title) has every seat filled."
        }
        if bots.count >= Self.botNames.count { return "That is every computer player." }
        return nil
    }

    /// The chosen game's entry.
    var entry: OfflineGameEntry? { gameId.flatMap { games[$0] } }

    /// Players here now.
    var presentPlayers: [OfflineLobbyPlayer] { players.filter(\.present) }

    /// Why Start is not possible yet, as a sentence; nil when it is.
    var startProblem: String? {
        if phase == .playing { return "A game is already on." }
        guard let entry else { return "Pick a game." }
        let count = presentPlayers.count
        if count < entry.info.minPlayers {
            let more = entry.info.minPlayers - count
            return "\(entry.info.title) needs \(more) more player\(more == 1 ? "" : "s")."
        }
        if count > entry.info.maxPlayers {
            return "\(entry.info.title) is for at most \(entry.info.maxPlayers) players."
        }
        return nil
    }

    // MARK: - Membership

    /// A guest's hello. Throws a refusal the session sends back before closing
    /// the connection. A player id already in the room is a rejoin: the same
    /// seat, sent the lobby and their view afresh.
    mutating func join(_ player: OfflinePlayer, version: Int) throws {
        if version != OfflineEnvelope.version {
            throw OfflineRefusal("That phone has a different version of the app. Update both, then try again.")
        }
        let name = OfflineRoom.cleanName(player.name)
        if let index = players.firstIndex(where: { $0.id == player.id }) {
            players[index].present = true
            players[index].name = name
            awaySince[player.id] = nil
            forget(player.id)
            return
        }
        // A person beats a computer player to a seat, between matches.
        if players.count >= Self.capacity, phase != .playing, let bot = players.lastIndex(where: \.isBot) {
            players.remove(at: bot)
        }
        if players.count >= Self.capacity {
            throw OfflineRefusal("The room is full — \(Self.capacity) is the most.")
        }
        // Mid-match, a newcomer watches and plays the next one.
        players.append(OfflineLobbyPlayer(id: player.id, name: name, present: true, inMatch: false))
    }

    /// A player has gone. Out of a lobby they are simply removed. Out of a
    /// running match they keep their seat, marked away. A player who chose
    /// to leave (`deliberate`, their `bye`) is given up on at once. A dropped
    /// connection gets `seatHeld` to come back first. Most drops are a locked
    /// phone or a radio blip, and in a two-player game telling the game at
    /// once would end the match before the guest had any chance to rejoin.
    /// Once the game is told, a match that falls below its minimum ends with
    /// the table as it stands.
    mutating func drop(_ playerId: String, now: Double, deliberate: Bool = false) {
        guard playerId != hostId, let index = players.firstIndex(where: { $0.id == playerId }) else { return }
        forget(playerId)
        guard phase == .playing, players[index].inMatch else {
            players.remove(at: index)
            awaySince[playerId] = nil
            return
        }
        players[index].present = false
        if deliberate {
            awaySince[playerId] = nil
            giveUp(on: [playerId], now: now)
        } else if awaySince[playerId] == nil {
            awaySince[playerId] = now
        }
    }

    /// Players whose seat is being held for them now, mid-match.
    var held: [String] { awaySince.keys.sorted() }

    // MARK: - The host's choices

    /// Choose the next game. Only between matches.
    mutating func choose(_ gameId: String) throws {
        guard phase != .playing else { throw OfflineRefusal("Finish this game first.") }
        guard let next = games[gameId] else { throw OfflineRefusal("This phone does not know that game.") }
        self.gameId = gameId
        // A game with no computer player cannot seat one; nor can a game
        // with fewer seats than there are players and bots.
        if !next.hasBot {
            players.removeAll(where: \.isBot)
        } else {
            while players.count > next.info.maxPlayers, let last = players.lastIndex(where: \.isBot) {
                players.remove(at: last)
            }
        }
    }

    /// Seat a computer player for the chosen game, named from `botNames`.
    @discardableResult
    mutating func addBot() throws -> String {
        if let problem = addBotProblem { throw OfflineRefusal(problem) }
        let taken = Set(players.map(\.name))
        let name = Self.botNames.first { !taken.contains($0) } ?? "Bot \(bots.count + 1)"
        var n = bots.count + 1
        while players.contains(where: { $0.id == "bot-\(n)" }) { n += 1 }
        let id = "bot-\(n)"
        players.append(OfflineLobbyPlayer(id: id, name: name, present: true, inMatch: false, bot: true))
        return id
    }

    /// Stand a computer player down. Only between matches.
    mutating func removeBot(_ id: String) throws {
        guard phase != .playing else { throw OfflineRefusal("Finish this game first.") }
        players.removeAll { $0.id == id && $0.isBot }
    }

    /// Start the chosen game with everyone present. `seed` comes from
    /// `OfflineRNG.freshSeed()` on a phone and a fixed number in a test.
    mutating func start(seed: UInt64, now: Double) throws {
        if let problem = startProblem { throw OfflineRefusal(problem) }
        guard let entry else { throw OfflineRefusal("Pick a game.") }
        players.removeAll { !$0.present }
        for index in players.indices { players[index].inMatch = true }
        awaySince = [:]
        match = entry.begin(players.map(\.player), seed, now)
        matchNumber += 1
        phase = .playing
        standings = nil
        viewSent = [:]
        botDue = [:]
        botSeen = [:]
        checkOver()
    }

    /// One player's action, as the game's `Action` JSON.
    mutating func act(_ data: Data, by playerId: String, match number: Int, now: Double) throws {
        guard phase == .playing, match != nil else { throw OfflineRefusal("That game has finished.") }
        guard number == matchNumber else { throw OfflineRefusal("That move was for an earlier game.") }
        guard let player = players.first(where: { $0.id == playerId }), player.present, player.inMatch else {
            throw OfflineRefusal("You are watching this one — you will be in the next game.")
        }
        try match?.apply(data, by: playerId, now: now)
        checkOver()
    }

    /// The host's ~10 Hz heartbeat.
    mutating func tick(now: Double) {
        guard phase == .playing else { return }
        let overdue = awaySince.filter { now - $0.value >= Self.seatHeld }.keys.sorted()
        if !overdue.isEmpty {
            for id in overdue { awaySince[id] = nil }
            giveUp(on: overdue, now: now)
            guard phase == .playing else { return }
        }
        match?.tick(now: now)
        checkOver()
        moveBots(now: now)
    }

    /// How long a computer player "thinks" before a move — long enough to
    /// see what it did, short enough not to drag.
    static let botThink: Double = 0.9

    /// Each computer player looks at the table `botThink` after it last
    /// changed and moves if it has a move — so it never answers in the same
    /// instant as the person before it, and goes again (a box closed, a card
    /// drawn) after another pause.
    private mutating func moveBots(now: Double) {
        guard phase == .playing else { return }
        for bot in players where bot.isBot && bot.inMatch {
            guard let seen = match?.viewData(for: bot.id) else { return }
            if botSeen[bot.id] != seen {
                botSeen[bot.id] = seen
                botDue[bot.id] = now + Self.botThink
                continue
            }
            guard let due = botDue[bot.id], now >= due, phase == .playing else { continue }
            botDue[bot.id] = nil
            if match?.botAct(bot.id, now: now) == true { checkOver() }
        }
    }

    /// The host stops the match early: standings as they stand.
    mutating func endMatch() {
        guard phase == .playing else { return }
        finish()
    }

    /// Back to the lobby after a match, to pick again or play again. Anybody
    /// who left during the match goes now.
    mutating func backToLobby() {
        guard phase == .finished else { return }
        phase = .lobby
        match = nil
        players.removeAll { !$0.present }
        for index in players.indices { players[index].inMatch = false }
        viewSent = [:]
        awaySince = [:]
    }

    /// The game's view `playerId` would be sent now (a spectator's if they
    /// are not in the match), or nil between matches. For tests and for
    /// diagnostics — screens get theirs through `outbox` like everyone.
    func currentView(for playerId: String) -> Data? {
        guard let match, phase != .lobby else { return nil }
        let inMatch = players.first { $0.id == playerId }?.inMatch ?? false
        return match.viewData(for: inMatch ? playerId : nil)
    }

    // MARK: - What to send

    /// Every message whose content changed since it was last sent: the lobby
    /// to each present player who has not had this one, then each present
    /// player's view if it differs from their last. Call after every change.
    mutating func outbox() -> [OfflineOutgoing] {
        var out: [OfflineOutgoing] = []
        let current = lobby
        // Bots are moved here, on the host; nothing is sent to them.
        for player in players where player.present && !player.isBot && lobbySent[player.id] != current {
            out.append(OfflineOutgoing(to: player.id, message: .lobby(current)))
            lobbySent[player.id] = current
        }
        if let match, phase != .lobby, let gameId {
            for player in players where player.present && !player.isBot {
                let packet = OfflineViewPacket(
                    gameId: gameId, match: matchNumber,
                    data: match.viewData(for: player.inMatch ? player.id : nil),
                    over: phase == .finished
                )
                if viewSent[player.id] != packet {
                    out.append(OfflineOutgoing(to: player.id, message: .view(packet)))
                    viewSent[player.id] = packet
                }
            }
        }
        return out
    }

    // MARK: - Private

    /// Tell the game these players have gone, then end a match that is now
    /// below its minimum, unless a seat is still being held for somebody
    /// who may yet come back.
    private mutating func giveUp(on ids: [String], now: Double) {
        for id in ids { match?.playerLeft(id, now: now) }
        if let info = match?.info, awaySince.isEmpty,
           players.filter({ $0.inMatch && $0.present }).count < info.minPlayers {
            finish()
        } else {
            checkOver()
        }
    }

    private mutating func checkOver() {
        if match?.isOver == true { finish() }
    }

    private mutating func finish() {
        phase = .finished
        standings = match?.standings ?? []
    }

    /// Forget what a player was sent, so the next outbox sends it all again.
    private mutating func forget(_ playerId: String) {
        lobbySent[playerId] = nil
        viewSent[playerId] = nil
    }

    /// A name fit for a lobby row: trimmed, at most 20 characters, never empty.
    static func cleanName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = String(trimmed.prefix(20))
        return short.isEmpty ? "Player" : short
    }
}

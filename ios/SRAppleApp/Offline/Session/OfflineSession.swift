import Foundation
import UIKit

/// One phone's part in an offline room — the host's or a guest's — or a
/// game played alone.
///
/// The HOST owns an `OfflineRoom` (the pure reducer), feeds it everything the
/// link hears, ticks it ten times a second, and sends whatever its `outbox()`
/// says changed. The host is a player too, and plays through exactly the same
/// path: its own lobby and view come out of the same outbox and are delivered
/// here instead of over the air.
///
/// SOLO is the host with no link at all: a room of one, plus the phone's
/// computer players when the game needs opponents. Every rule, view and
/// standings table is the nearby game's own.
///
/// A GUEST says hello, then draws whatever lobby and view arrive, sends its
/// actions, and pings the host a few times a second at first (less once
/// settled) to learn the host's clock. A guest that loses the host looks for
/// the same room again for `OfflineReconnect.patience` and rejoins its own
/// seat before it gives up.
///
/// Every finished match a phone played in is filed with `OfflineResultStore`,
/// which tells the site when there is internet again.
///
/// One shared instance, so a room survives the page that opened it being
/// popped; it ends only when somebody presses Leave, or the host goes.
@MainActor
final class OfflineSession: ObservableObject {
    static let shared = OfflineSession()

    enum Role: Equatable { case host, guest }

    enum Stage: Equatable {
        /// No room.
        case idle
        /// Guest: looking for rooms.
        case browsing
        /// Guest: knocking on a room's door.
        case connecting(String)
        /// In a room (the lobby says which phase).
        case room
        /// Guest: lost the host, looking for the same room to get back in.
        case reconnecting(String)
        /// The room has closed; the sentence says why.
        case ended(String)
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var role: Role?
    @Published private(set) var transport: OfflineTransport = .auto
    /// A game played alone: no link, perhaps computer players.
    @Published private(set) var isSolo = false
    @Published private(set) var lobby: OfflineLobby?
    /// My view of the current match.
    @Published private(set) var packet: OfflineViewPacket?
    /// Guest: rooms in reach.
    @Published private(set) var found: [OfflineFoundHost] = []
    /// Guest: the link carrying the connection to the host.
    @Published private(set) var route: OfflineTransport?
    /// Host on Wi-Fi: what guests can type.
    @Published private(set) var addresses: [String] = []
    /// Host: how each player's connection looks, by player id. Refreshed
    /// once a second.
    @Published private(set) var health: [String: OfflinePeerHealth] = [:]
    /// The last thing that went wrong with the connection, for the screen.
    @Published private(set) var problem: String?
    /// The host's last refusal of one of my actions; cleared by the next view.
    @Published private(set) var refusal: String?
    /// The host's clock, as this phone knows it.
    @Published private(set) var clock = OfflineHostClock.host
    /// When browsing began, so the screen can say "nothing yet" honestly.
    @Published private(set) var browsingSince: Date?
    /// A connection test is waiting for its answer.
    @Published private(set) var testing = false
    /// The last connection test's answer, as a sentence.
    @Published private(set) var testResult: String?
    /// What this phone is called in rooms. Remembered.
    @Published var nickname: String {
        didSet { UserDefaults.standard.set(nickname, forKey: Self.nicknameKey) }
    }

    /// This phone's player id: the same every time, so a dropped guest who
    /// comes back takes their own seat.
    let playerId: String

    private var link: (any OfflineLink)?
    private var room: OfflineRoom?
    /// Host: who is on which link key, both ways.
    private var peerOfPlayer: [String: String] = [:]
    private var playerOfPeer: [String: String] = [:]
    /// Host: when each guest was last heard from (uptime).
    private var heard: [String: Double] = [:]
    private var lastHealth: Double = 0
    private var estimator = OfflineClockEstimator()
    private var timer: Timer?
    private var actionSeq = 0
    private var pingSeq = 0
    private var lastPing: Double = 0
    /// Guest: the test ping in flight.
    private var testPing: (id: Int, sentAt: Double)?
    /// Guest: when the current join (or the route it is on now) began, to
    /// give up on one that hangs. Set until the host's `welcome`, not just
    /// until the link connects: a connected link whose hello was lost would
    /// otherwise sit on "Joining…" for ever.
    private var joinStartedAt: Double?
    /// Guest: when the last hello went, so it is sent again until welcomed.
    private var lastHello: Double = 0
    /// Guest: the room to get back into after a drop.
    private var reconnect: OfflineReconnect?
    private var lastRejoin: Double = 0
    /// Guest: when the browse was last restarted.
    private var lastRebrowse: Double = 0
    private var frontObserver: NSObjectProtocol?

    private static let nicknameKey = "offline.nickname"
    private static let playerIdKey = "offline.playerId"

    private init() {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: Self.playerIdKey) ?? UUID().uuidString
        defaults.set(id, forKey: Self.playerIdKey)
        playerId = id
        nickname = defaults.string(forKey: Self.nicknameKey) ?? Self.defaultNickname()
        // iOS stops advertising and browsing while the app is away, and the
        // Local Network prompt sends the app inactive and back: either way,
        // start both again the moment the app is in front.
        frontObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            offlineAssumeMain { self?.cameToFront() }
        }
    }

    /// The registered first name if the app knows one, else the phone's name.
    private static func defaultNickname() -> String {
        if let name = RegistrationStore.shared.name?.split(separator: " ").first, !name.isEmpty {
            return String(name)
        }
        return OfflineRoom.cleanName(UIDevice.current.name)
    }

    // MARK: - What the screens read

    var isHost: Bool { role == .host }
    var inRoom: Bool { stage != .idle }

    /// The players, seat order.
    var players: [OfflinePlayer] { lobby?.roster ?? [] }

    /// The chosen game, from the catalogue.
    var chosen: OfflineCatalogueItem? { lobby?.gameId.flatMap(OfflineCatalogue.item) }

    /// Host: why Start is greyed out, or nil.
    var startProblem: String? { room?.startProblem }

    /// Host: why a computer player cannot be added now, or nil when one can.
    var addBotProblem: String? { room?.addBotProblem }

    /// The host's display name.
    var hostName: String {
        guard let lobby else { return "the host" }
        return lobby.players.first { $0.id == lobby.hostId }?.name ?? "the host"
    }

    // MARK: - Host

    /// Open a room on `transport` (both links unless told otherwise),
    /// optionally with a game already chosen.
    func host(via transport: OfflineTransport = .auto, game: String? = nil) {
        leave()
        let me = OfflinePlayer(id: playerId, name: OfflineRoom.cleanName(nickname))
        var room = OfflineRoom(host: me, roomName: "\(me.name)'s game", games: OfflineCatalogue.entries)
        if let game { try? room.choose(game) }
        self.room = room
        self.transport = transport
        role = .host
        stage = .room
        clock = .host
        let link = Self.makeLink(transport)
        link.onEvent = { [weak self] event in self?.handle(event) }
        self.link = link
        link.host(roomName: room.roomName, roomId: room.roomKey, playerName: me.name)
        startTimer()
        flush()
    }

    /// Play `gameId` alone, now: a room with no link, computer players in
    /// the empty seats the game needs, and the match already started.
    func playSolo(_ gameId: String) {
        leave()
        let me = OfflinePlayer(id: playerId, name: OfflineRoom.cleanName(nickname))
        var room = OfflineRoom(host: me, roomName: "Solo", games: OfflineCatalogue.entries)
        do {
            try room.choose(gameId)
            guard let entry = room.entry, let bots = OfflinePlayModes.soloBots(entry.info, hasBot: entry.hasBot) else {
                throw OfflineRefusal("That game needs other people — host it nearby instead.")
            }
            for _ in 0..<bots { try room.addBot() }
            try room.start(seed: OfflineRNG.freshSeed(), now: OfflineUptime.now())
        } catch {
            problem = (error as? OfflineRefusal)?.reason ?? error.localizedDescription
            return
        }
        self.room = room
        isSolo = true
        role = .host
        stage = .room
        clock = .host
        startTimer()
        flush()
    }

    func choose(_ gameId: String) {
        hostDo { try $0.choose(gameId) }
    }

    func start() {
        let now = OfflineUptime.now()
        hostDo { try $0.start(seed: OfflineRNG.freshSeed(), now: now) }
    }

    /// Seat a computer player for the chosen game.
    func addBot() {
        hostDo { _ = try $0.addBot() }
    }

    func removeBot(_ id: String) {
        hostDo { try $0.removeBot(id) }
    }

    /// The same game again, with whoever is here.
    func playAgain() {
        let now = OfflineUptime.now()
        hostDo { room in
            room.backToLobby()
            try room.start(seed: OfflineRNG.freshSeed(), now: now)
        }
    }

    /// Back to the lobby to pick another game.
    func backToLobby() {
        hostDo { $0.backToLobby() }
    }

    /// Stop the match now; standings as they stand.
    func endMatch() {
        hostDo { $0.endMatch() }
    }

    private func hostDo(_ change: (inout OfflineRoom) throws -> Void) {
        guard role == .host, var room else { return }
        do {
            try change(&room)
            problem = nil
        } catch let refusal as OfflineRefusal {
            problem = refusal.reason
        } catch {
            problem = error.localizedDescription
        }
        self.room = room
        flush()
    }

    // MARK: - Guest

    /// Look for rooms (on both links unless told otherwise).
    func browse(via transport: OfflineTransport = .auto) {
        leave()
        self.transport = transport
        role = .guest
        stage = .browsing
        browsingSince = Date()
        lastRebrowse = OfflineUptime.now()
        let link = Self.makeLink(transport)
        link.onEvent = { [weak self] event in self?.handle(event) }
        self.link = link
        link.browse(playerName: OfflineRoom.cleanName(nickname))
        startTimer()
    }

    func join(_ host: OfflineFoundHost) {
        guard role == .guest, let link else { return }
        problem = nil
        stage = .connecting(host.name)
        joinStartedAt = OfflineUptime.now()
        link.join(host)
    }

    func join(address: String) {
        guard role == .guest, let link else { return }
        problem = nil
        stage = .connecting(address)
        joinStartedAt = OfflineUptime.now()
        link.join(address: address)
    }

    /// From "connecting" (or "reconnecting") back to the list.
    func cancelJoin() {
        guard role == .guest else { return }
        browse(via: transport)
    }

    // MARK: - Testing the connection

    /// Guest: time a ping to the host and say how it went. Host: advertise
    /// the room again and say who has and has not been heard from.
    func testConnection() {
        testResult = nil
        switch role {
        case .guest:
            guard stage == .room else { return }
            pingSeq += 1
            let now = OfflineUptime.now()
            testPing = (pingSeq, now)
            testing = true
            lastPing = now
            sendToHost(.ping(id: pingSeq, sentAt: now))
        case .host:
            guard !isSolo else { return }
            link?.refresh()
            refreshHealth(now: OfflineUptime.now())
            let guests = (lobby?.players ?? [])
                .filter { $0.id != playerId && !$0.isBot }
                .map { (name: $0.name, health: health[$0.id] ?? .quiet(0)) }
            testResult = OfflinePeerHealth.summary(guests)
        case nil:
            break
        }
    }

    // MARK: - Playing

    /// Send one action (the game's `Action`, as JSON) — from the context's `send`.
    func send(action data: Data) {
        guard let lobby, lobby.phase == .playing else { return }
        switch role {
        case .host:
            guard var room else { return }
            do {
                try room.act(data, by: playerId, match: lobby.match, now: OfflineUptime.now())
            } catch let refused as OfflineRefusal {
                refusal = refused.reason
            } catch {
                refusal = error.localizedDescription
            }
            self.room = room
            flush()
        case .guest:
            actionSeq += 1
            sendToHost(.action(seq: actionSeq, match: lobby.match, data: data))
        case nil:
            break
        }
    }

    /// Leave the room (or stop looking). A host leaving closes the room.
    func leave() {
        if role == .host {
            for peer in playerOfPeer.keys { send(.bye(reason: "\(hostName) closed the room."), to: peer) }
        } else if role == .guest, stage == .room {
            sendToHost(.bye(reason: "left"))
        }
        reset(to: .idle)
    }

    /// Clear the problem line.
    func dismissProblem() { problem = nil }

    // MARK: - Link events

    private func handle(_ event: OfflineLinkEvent) {
        switch event {
        case .found(let hosts):
            found = hosts
            if case .reconnecting = stage { rejoinIfBack() }
        case .listening(let list):
            addresses = list
        case .problem(let text):
            problem = text
        case .trying:
            // The dual link has moved on to its other route: that route gets
            // the whole join timeout, not what the first one left of it.
            if role == .guest, joinStartedAt != nil { joinStartedAt = OfflineUptime.now() }
        case .connected(let peer):
            if role == .guest, peer == OfflineLinkPeer.host {
                route = link?.connectedVia
                sayHello()
                ping()
            }
        case .disconnected(let peer):
            if role == .host {
                guard let id = playerOfPeer.removeValue(forKey: peer) else { return }
                if peerOfPlayer[id] == peer { peerOfPlayer[id] = nil }
                room?.drop(id, now: OfflineUptime.now())
                flush()
                refreshHealth(now: OfflineUptime.now())
            } else if role == .guest {
                route = nil
                switch stage {
                case .room:
                    beginReconnect()
                case .connecting(let name):
                    // Not the end of anything: back to the list to try again.
                    joinStartedAt = nil
                    stage = .browsing
                    problem = "Could not get into \(name). Try again — or move closer to the host."
                    link?.browse(playerName: OfflineRoom.cleanName(nickname))
                    lastRebrowse = OfflineUptime.now()
                case .reconnecting:
                    // That attempt failed; the next list, or the next beat, tries again.
                    joinStartedAt = nil
                default:
                    break
                }
            }
        case .received(let data, let peer):
            guard let envelope = try? OfflineEnvelope.decode(data) else { return }
            if role == .host {
                if let id = playerOfPeer[peer] { heard[id] = OfflineUptime.now() }
                hostReceived(envelope.message, from: peer)
            } else if role == .guest {
                guestReceived(envelope.message)
            }
        }
    }

    private func hostReceived(_ message: OfflineMessage, from peer: String) {
        switch message {
        case .hello(let id, let name, let version):
            guard var room else { return }
            do {
                try room.join(OfflinePlayer(id: id, name: name), version: version)
            } catch {
                let reason = (error as? OfflineRefusal)?.reason ?? "Could not join."
                send(.refused(reason: reason), to: peer)
                link?.disconnect(peer)
                return
            }
            // A rejoin on a new connection: forget the old one.
            if let old = peerOfPlayer[id], old != peer { playerOfPeer[old] = nil }
            peerOfPlayer[id] = peer
            playerOfPeer[peer] = id
            heard[id] = OfflineUptime.now()
            self.room = room
            send(.welcome(playerId: id, hostId: playerId, roomName: room.roomName), to: peer)
            flush()
            refreshHealth(now: OfflineUptime.now())
        case .action(let seq, let match, let data):
            guard let id = playerOfPeer[peer], var room else { return }
            do {
                try room.act(data, by: id, match: match, now: OfflineUptime.now())
            } catch {
                let reason = (error as? OfflineRefusal)?.reason ?? "That move was refused."
                send(.refusal(seq: seq, reason: reason), to: peer)
            }
            self.room = room
            flush()
        case .ping(let id, let sentAt):
            send(.pong(id: id, sentAt: sentAt, hostNow: OfflineUptime.now()), to: peer)
        case .bye:
            guard let id = playerOfPeer.removeValue(forKey: peer) else { return }
            if peerOfPlayer[id] == peer { peerOfPlayer[id] = nil }
            // They chose to go: no seat is held for them.
            room?.drop(id, now: OfflineUptime.now(), deliberate: true)
            flush()
        default:
            break
        }
    }

    private func guestReceived(_ message: OfflineMessage) {
        switch message {
        case .welcome:
            joinStartedAt = nil
            stage = .room
            problem = nil
            reconnect = nil
        case .refused(let reason):
            end(reason)
        case .lobby(let next):
            apply(next)
        case .view(let next):
            packet = next
            refusal = nil
        case .refusal(_, let reason):
            refusal = reason
        case .pong(let id, let sentAt, let hostNow):
            let now = OfflineUptime.now()
            estimator.record(sentAt: sentAt, receivedAt: now, hostNow: hostNow)
            if let offset = estimator.offset { clock = OfflineHostClock(offset: offset) }
            if let test = testPing, test.id == id {
                testPing = nil
                testing = false
                testResult = OfflineRoundTrip.sentence(ms: Int(((now - sentAt) * 1000).rounded()))
            }
        case .bye(let reason):
            end(reason)
        default:
            break
        }
    }

    /// A lobby, from the air or (on the host) from the room itself. A match
    /// that has just finished is filed for the leaderboard.
    private func apply(_ next: OfflineLobby) {
        let wasFinished = lobby?.phase == .finished && lobby?.match == next.match
        lobby = next
        if next.phase == .lobby { packet = nil }
        if next.phase == .finished, !wasFinished { file(next) }
    }

    /// Queue this phone's row of a finished match to sync later.
    private func file(_ lobby: OfflineLobby) {
        let title = lobby.gameId.flatMap(OfflineCatalogue.item)?.info.title ?? "Offline game"
        guard let result = OfflineResult.from(
            lobby: lobby, me: playerId, title: title, mode: isSolo ? .solo : .nearby,
            finishedAt: Date().timeIntervalSince1970 * 1000
        ) else { return }
        OfflineResultStore.shared.record(result)
    }

    // MARK: - Getting back in

    /// The host has gone quiet mid-room: look for the same room again rather
    /// than ending the game. Rooms from before room ids cannot be found again.
    private func beginReconnect() {
        guard let roomKey = lobby?.roomKey, let link else {
            end("Lost touch with \(hostName). They may have left, locked their phone or gone out of range.")
            return
        }
        let now = OfflineUptime.now()
        reconnect = OfflineReconnect(roomId: roomKey, hostName: hostName, since: now)
        stage = .reconnecting(hostName)
        testing = false
        testPing = nil
        joinStartedAt = nil
        lastRebrowse = now
        link.browse(playerName: OfflineRoom.cleanName(nickname))
    }

    /// Reconnecting: knock again as soon as the room is in the list (and not
    /// while a link is already connected and waiting on its welcome).
    private func rejoinIfBack() {
        guard let reconnect, joinStartedAt == nil, route == nil, let link,
              let host = reconnect.match(in: found) else { return }
        let now = OfflineUptime.now()
        joinStartedAt = now
        lastRejoin = now
        link.join(host)
    }

    /// The app is in front again.
    private func cameToFront() {
        guard let link else { return }
        link.refresh()
        lastRebrowse = OfflineUptime.now()
        if role == .guest, stage == .room { ping() }
    }

    // MARK: - Sending

    /// The room's outbox: the host's own messages delivered here, the rest
    /// sent to each player's link key.
    private func flush() {
        guard role == .host, var room else { return }
        let out = room.outbox()
        self.room = room
        for item in out {
            if item.to == playerId {
                switch item.message {
                case .lobby(let next): apply(next)
                case .view(let next):
                    packet = next
                    refusal = nil
                default: break
                }
            } else if let peer = peerOfPlayer[item.to] {
                send(item.message, to: peer)
            }
        }
    }

    private func send(_ message: OfflineMessage, to peer: String) {
        guard let link, let data = try? OfflineEnvelope(message).encoded() else { return }
        link.send(data, to: peer)
    }

    private func sendToHost(_ message: OfflineMessage) {
        send(message, to: OfflineLinkPeer.host)
    }

    /// Guest: who I am, to the host. Sent on connecting and again every
    /// couple of seconds until the welcome comes: one lost hello (a send that
    /// failed, or data that reached the host before it had registered the
    /// connection) must not leave a guest knocking for ever. The host takes a
    /// repeated hello from the same player as a rejoin, so it is harmless.
    private func sayHello() {
        lastHello = OfflineUptime.now()
        sendToHost(.hello(playerId: playerId, name: OfflineRoom.cleanName(nickname), version: OfflineEnvelope.version))
    }

    private func ping() {
        pingSeq += 1
        lastPing = OfflineUptime.now()
        sendToHost(.ping(id: pingSeq, sentAt: lastPing))
    }

    // MARK: - The heartbeat

    /// Ten times a second: the host ticks the match (and its computer
    /// players) and, once a second, checks who it has heard from; a guest
    /// pings, and keeps an eye on joins that hang and browses that find
    /// nothing.
    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            offlineAssumeMain { self?.beat() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func beat() {
        let now = OfflineUptime.now()
        switch role {
        case .host:
            if var room, room.phase == .playing {
                room.tick(now: now)
                self.room = room
                flush()
            }
            if !isSolo, now - lastHealth >= 1 { refreshHealth(now: now) }
        case .guest:
            guestBeat(now: now)
        case nil:
            break
        }
    }

    private func guestBeat(now: Double) {
        switch stage {
        case .room:
            let gap = estimator.settling ? 0.5 : 3
            if now - lastPing >= gap { ping() }
            if testing, let test = testPing, now - test.sentAt > 3 {
                testPing = nil
                testing = false
                testResult = OfflineRoundTrip.sentence(ms: nil)
            }
        case .browsing:
            if found.isEmpty, now - lastRebrowse >= OfflineReconnect.rebrowseEvery {
                lastRebrowse = now
                link?.refresh()
            }
        case .connecting:
            if let started = joinStartedAt, now - started >= OfflineReconnect.joinTimeout {
                joinStartedAt = nil
                route = nil
                stage = .browsing
                problem = "That room did not answer. Try again — or move closer to the host."
                link?.browse(playerName: OfflineRoom.cleanName(nickname))
                lastRebrowse = now
            } else if route != nil, now - lastHello >= OfflineReconnect.helloEvery {
                sayHello()
            }
        case .reconnecting:
            guard let reconnect else { return }
            if reconnect.givenUp(now: now) {
                end("Lost touch with \(reconnect.hostName). They may have left, locked their phone or gone out of range.")
                return
            }
            // A knock that hangs is abandoned; the room is knocked on again
            // a few seconds later if it is still listed. The dual link
            // remembers the route that hung and tries the other one first.
            if let started = joinStartedAt, now - started >= OfflineReconnect.joinTimeout {
                joinStartedAt = nil
                route = nil
                link?.browse(playerName: OfflineRoom.cleanName(nickname))
                lastRebrowse = now
            } else if joinStartedAt != nil, route != nil, now - lastHello >= OfflineReconnect.helloEvery {
                sayHello()
            } else if joinStartedAt == nil, now - lastRejoin >= 3 {
                rejoinIfBack()
            }
            if joinStartedAt == nil, now - lastRebrowse >= OfflineReconnect.rebrowseEvery {
                lastRebrowse = now
                link?.refresh()
            }
        case .idle, .ended:
            break
        }
    }

    /// Host: each player's connection, from when they were last heard.
    private func refreshHealth(now: Double) {
        lastHealth = now
        var next: [String: OfflinePeerHealth] = [:]
        for player in lobby?.players ?? [] {
            if player.id == playerId || player.isBot {
                next[player.id] = .local
            } else {
                let connected = player.present && peerOfPlayer[player.id] != nil
                next[player.id] = OfflinePeerHealth.of(lastHeard: heard[player.id], now: now, present: connected)
            }
        }
        if next != health { health = next }
    }

    // MARK: - Ending

    private func end(_ reason: String) {
        reset(to: .ended(reason))
    }

    private func reset(to next: Stage) {
        timer?.invalidate()
        timer = nil
        link?.onEvent = nil
        link?.stop()
        link = nil
        room = nil
        peerOfPlayer = [:]
        playerOfPeer = [:]
        heard = [:]
        health = [:]
        estimator = OfflineClockEstimator()
        clock = .host
        lobby = nil
        packet = nil
        found = []
        route = nil
        addresses = []
        refusal = nil
        browsingSince = nil
        testing = false
        testPing = nil
        testResult = nil
        joinStartedAt = nil
        reconnect = nil
        if next == .idle {
            problem = nil
            isSolo = false
        }
        role = next == .idle ? nil : role
        stage = next
    }

    private static func makeLink(_ transport: OfflineTransport) -> any OfflineLink {
        switch transport {
        case .auto: return OfflineDualLink()
        case .nearby: return OfflineNearbyLink()
        case .hotspot: return OfflineHotspotLink()
        }
    }
}

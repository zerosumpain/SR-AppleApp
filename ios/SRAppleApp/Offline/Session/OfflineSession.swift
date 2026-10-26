import Foundation
import UIKit

/// One phone's part in an offline room — the host's or a guest's.
///
/// The HOST owns an `OfflineRoom` (the pure reducer), feeds it everything the
/// link hears, ticks it ten times a second, and sends whatever its `outbox()`
/// says changed. The host is a player too, and plays through exactly the same
/// path: its own lobby and view come out of the same outbox and are delivered
/// here instead of over the air.
///
/// A GUEST says hello, then draws whatever lobby and view arrive, sends its
/// actions, and pings the host a few times a second at first (less once
/// settled) to learn the host's clock.
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
        /// The room has closed; the sentence says why.
        case ended(String)
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var role: Role?
    @Published private(set) var transport: OfflineTransport = .nearby
    @Published private(set) var lobby: OfflineLobby?
    /// My view of the current match.
    @Published private(set) var packet: OfflineViewPacket?
    /// Guest: rooms in reach.
    @Published private(set) var found: [OfflineFoundHost] = []
    /// Host on Wi-Fi: what guests can type.
    @Published private(set) var addresses: [String] = []
    /// The last thing that went wrong with the connection, for the screen.
    @Published private(set) var problem: String?
    /// The host's last refusal of one of my actions; cleared by the next view.
    @Published private(set) var refusal: String?
    /// The host's clock, as this phone knows it.
    @Published private(set) var clock = OfflineHostClock.host
    /// When browsing began, so the screen can say "nothing yet" honestly.
    @Published private(set) var browsingSince: Date?
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
    private var estimator = OfflineClockEstimator()
    private var timer: Timer?
    private var actionSeq = 0
    private var pingSeq = 0
    private var lastPing: Double = 0

    private static let nicknameKey = "offline.nickname"
    private static let playerIdKey = "offline.playerId"

    private init() {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: Self.playerIdKey) ?? UUID().uuidString
        defaults.set(id, forKey: Self.playerIdKey)
        playerId = id
        nickname = defaults.string(forKey: Self.nicknameKey) ?? Self.defaultNickname()
        // The heartbeat stops in the background, where the link has dropped
        // anyway: a room left open kept a ten-a-second timer running for as
        // long as location tracking kept the process alive.
        let centre = NotificationCenter.default
        centre.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            offlineAssumeMain { self?.timer?.invalidate(); self?.timer = nil }
        }
        centre.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            offlineAssumeMain {
                guard let self, self.link != nil, self.timer == nil else { return }
                self.startTimer()
            }
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

    /// The host's display name.
    var hostName: String {
        guard let lobby else { return "the host" }
        return lobby.players.first { $0.id == lobby.hostId }?.name ?? "the host"
    }

    // MARK: - Host

    /// Open a room on `transport`, optionally with a game already chosen.
    func host(via transport: OfflineTransport, game: String? = nil) {
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
        link.host(roomName: room.roomName, playerName: me.name)
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

    /// Look for rooms on `transport`.
    func browse(via transport: OfflineTransport) {
        leave()
        self.transport = transport
        role = .guest
        stage = .browsing
        browsingSince = Date()
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
        link.join(host)
    }

    func join(address: String) {
        guard role == .guest, let link else { return }
        problem = nil
        stage = .connecting(address)
        link.join(address: address)
    }

    /// From "connecting" back to the list.
    func cancelJoin() {
        guard role == .guest else { return }
        browse(via: transport)
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
        case .listening(let list):
            addresses = list
        case .problem(let text):
            problem = text
        case .connected(let peer):
            if role == .guest, peer == OfflineLinkPeer.host {
                sendToHost(.hello(playerId: playerId, name: OfflineRoom.cleanName(nickname), version: OfflineEnvelope.version))
                ping()
            }
        case .disconnected(let peer):
            if role == .host {
                guard let id = playerOfPeer.removeValue(forKey: peer) else { return }
                if peerOfPlayer[id] == peer { peerOfPlayer[id] = nil }
                room?.drop(id, now: OfflineUptime.now())
                flush()
            } else if role == .guest {
                switch stage {
                case .room: end("Lost touch with \(hostName). They may have left, locked their phone or gone out of range.")
                case .connecting: end("Could not join that room.")
                default: break
                }
            }
        case .received(let data, let peer):
            guard let envelope = try? OfflineEnvelope.decode(data) else { return }
            if role == .host {
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
            self.room = room
            send(.welcome(playerId: id, hostId: playerId, roomName: room.roomName), to: peer)
            flush()
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
            room?.drop(id, now: OfflineUptime.now())
            flush()
        default:
            break
        }
    }

    private func guestReceived(_ message: OfflineMessage) {
        switch message {
        case .welcome:
            stage = .room
            problem = nil
        case .refused(let reason):
            end(reason)
        case .lobby(let next):
            apply(next)
        case .view(let next):
            packet = next
            refusal = nil
        case .refusal(_, let reason):
            refusal = reason
        case .pong(_, let sentAt, let hostNow):
            estimator.record(sentAt: sentAt, receivedAt: OfflineUptime.now(), hostNow: hostNow)
            if let offset = estimator.offset { clock = OfflineHostClock(offset: offset) }
        case .bye(let reason):
            end(reason)
        default:
            break
        }
    }

    /// A lobby, from the air or (on the host) from the room itself.
    private func apply(_ next: OfflineLobby) {
        lobby = next
        if next.phase == .lobby { packet = nil }
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

    private func ping() {
        pingSeq += 1
        lastPing = OfflineUptime.now()
        sendToHost(.ping(id: pingSeq, sentAt: lastPing))
    }

    // MARK: - The heartbeat

    /// Ten times a second: the host ticks the match; a guest pings.
    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            offlineAssumeMain { self?.beat() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func beat() {
        switch role {
        case .host:
            guard var room, room.phase == .playing else { return }
            room.tick(now: OfflineUptime.now())
            self.room = room
            flush()
        case .guest:
            guard stage == .room else { return }
            let gap = estimator.settling ? 0.5 : 3
            if OfflineUptime.now() - lastPing >= gap { ping() }
        case nil:
            break
        }
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
        estimator = OfflineClockEstimator()
        clock = .host
        lobby = nil
        packet = nil
        found = []
        addresses = []
        refusal = nil
        browsingSince = nil
        if next == .idle { problem = nil }
        role = next == .idle ? nil : role
        stage = next
    }

    private static func makeLink(_ transport: OfflineTransport) -> any OfflineLink {
        switch transport {
        case .nearby: return OfflineNearbyLink()
        case .hotspot: return OfflineHotspotLink()
        }
    }
}

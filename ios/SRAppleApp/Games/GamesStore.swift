import Foundation
import UserNotifications

/// The Games tab: who can be invited, what I am invited to, which rooms I am in.
///
/// ## Invites are PUSHED, and polled underneath
///
/// The site pushes an invite the moment it is sent (time-sensitive, opens the
/// room). While the app is open `ContentView` also runs `setPolling(true)`,
/// asking `GET /api/native/games` for the lobby (every five seconds on the
/// Games screen, every minute elsewhere); an invite
/// whose room id has not been seen before raises a LOCAL banner — unless the
/// site says a push already reached this phone with it (`pushed`), in which
/// case one ring was enough. A phone the push missed still rings from the poll.
@MainActor
final class GamesStore: ObservableObject {
    @Published private(set) var lobby: GamesLobby?
    @Published private(set) var loading = false
    /// The room id (or "new") an action is waiting on.
    @Published private(set) var busy: String?
    @Published var message: String?
    /// How often this phone starts or joins each game, for the shelf's order
    /// (`GameUsage`). Read once at launch, written on each start or join.
    @Published private(set) var usage: HubUsage
    /// Lobbies whose banner was put away, so it stays away — kept across
    /// launches like `seen`, since a relaunch must not bring it back.
    @Published private(set) var bannerDismissed: Set<String>
    private static let dismissedKey = "games-banner-dismissed"
    /// "Dad closed the Chess lobby." — shown by the banner for a few seconds,
    /// whichever page is open, then cleared by it.
    @Published var closedNote: String?

    /// Every 5 s while the Games screen is on show, a minute anywhere else.
    /// The site pushes invites, so the background poll is only a catch-up —
    /// at 5 s on every tab it kept the radio awake and the phone warm.
    static let pollInterval: TimeInterval = 5
    static let idlePollInterval: TimeInterval = 60
    /// Set by the Games screen while it is on show.
    private var watching = false

    private let client = SiteClient.shared
    private var pollTask: Task<Void, Never>?
    private var inFlight = false
    /// Invite room ids already raised, kept across launches so a relaunch does
    /// not ring for the same invite twice.
    private var seen: Set<String>
    private static let seenKey = "games-seen-invites"

    /// Server epoch ms minus this phone's, at the last lobby read — so "21 h
    /// left" on a durable game keeps counting down between lobby changes.
    private var serverOffsetMs: Double?
    /// Held for the store's life, which is the app's (`ContentView`'s @StateObject).
    private var pushObserver: NSObjectProtocol?
    private var closedObserver: NSObjectProtocol?

    init() {
        seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
        usage = GameUsage.load()
        bannerDismissed = Set(UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? [])
        // A room screen saw its lobby closed by a parent: say so on every
        // page, and read the lobby so the room leaves "Your games" at once.
        closedObserver = NotificationCenter.default.addObserver(
            forName: GameLobbyNews.closedName, object: nil, queue: .main
        ) { [weak self] note in
            let line = note.object as? String
            Task { @MainActor in
                self?.closedNote = line
                await self?.load()
            }
        }
        // A game push with the app open ("Your move in Homestead"): read the
        // lobby now rather than at the next poll, so "Your games" agrees.
        pushObserver = NotificationCenter.default.addObserver(
            forName: GameTurnPush.arrived, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.load() }
        }
    }

    var invites: [GameInvite] { lobby?.invites ?? [] }
    var rooms: [GameRoomSummary] { lobby?.rooms ?? [] }
    var players: [GamePerson] { lobby?.players ?? [] }
    /// "Your games": my move first, then the most recently changed.
    var yourGames: [GameRoomSummary] { YourGames.ordered(rooms) }
    /// A parent (or the owner): may close any lobby not yet started.
    var isParent: Bool { lobby?.parent ?? false }
    /// Every lobby not yet started — a parent's list; empty for anyone else.
    var openLobbies: [GameOpenLobby] { lobby?.openLobbies ?? [] }

    // MARK: - The banner

    /// The lobby the banner across every page offers, if any: an invite to
    /// answer, else a lobby I am in that has not started. Nil once put away.
    var bannerLobby: LobbyBannerCandidate? {
        guard let lobby else { return nil }
        let invites = lobby.invites.map { invite in
            LobbyBannerCandidate(roomId: invite.roomId, game: invite.game, gameTitle: GameNames.title(invite.game),
                                 hostName: invite.hostName, kind: .invite, expiresAt: invite.expiresAt)
        }
        let waiting = lobby.rooms.filter { $0.phase == .lobby }.map { room in
            LobbyBannerCandidate(roomId: room.id, game: room.game, gameTitle: GameNames.title(room.game),
                                 hostName: room.hostName, kind: .waiting, mine: room.hostName == lobby.me.name)
        }
        // A room already on screen (however it was reached — the Games tab,
        // or the hub when Games is there) needs no banner pointing at it.
        let hidden = bannerDismissed.union(GameRoomsOnScreen.ids)
        return LobbyBannerPick.pick(invites + waiting, dismissed: hidden, serverNow: serverNow())
    }

    /// Put a lobby's banner away for good. Room ids are short-lived; the list
    /// only needs the recent ones.
    func dismissBanner(_ roomId: String) {
        bannerDismissed.insert(roomId)
        UserDefaults.standard.set(Array(bannerDismissed.suffix(100)), forKey: Self.dismissedKey)
    }

    /// One play, counted for the shelf's order: a room started or joined, or
    /// a game opened on this phone (which has no room to count it by).
    func recordPlay(_ game: String) {
        usage = GameUsage.record(game, now: Date())
    }

    /// The paces the new-game sheet may offer for a game; empty = live only.
    func paceChoices(for game: GameKind) -> [GamePace] {
        lobby?.paceChoices(for: game.rawValue) ?? []
    }

    /// The server's clock now, from the last lobby read. Nil before one.
    func serverNow() -> Double? {
        serverOffsetMs.map { Date().timeIntervalSince1970 * 1000 + $0 }
    }

    // MARK: - Loading and the poll

    func load() async {
        guard !inFlight else { return }
        inFlight = true
        // The spinner is only drawn before the first lobby, so only then is
        // `loading` published — not twice on every background poll.
        let showsSpinner = lobby == nil
        if showsSpinner { loading = true }
        defer {
            inFlight = false
            if showsSpinner { loading = false }
        }
        do {
            let next: GamesLobby = try await client.send("api/native/games")
            if next.serverNow > 0 { serverOffsetMs = next.serverNow - Date().timeIntervalSince1970 * 1000 }
            // Only publish a real change: `serverNow` moves on every read,
            // and each publish redrew the whole tab view.
            if !Self.same(lobby, next) { lobby = next; GamesWidgetBridge.save(next) }
            if message != nil { message = nil }
            await announce(next.invites)
        } catch is CancellationError {
            return
        } catch SiteError.expired {
            message = "This iPhone needs pairing again."
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            // A lobby on screen stays on screen; the next poll will catch up.
            message = lobby == nil ? error.localizedDescription : nil
        }
    }

    /// The lobby with the server clock left out.
    private static func same(_ a: GamesLobby?, _ b: GamesLobby) -> Bool {
        guard let a else { return false }
        return a.me == b.me && a.players == b.players && a.invites == b.invites && a.rooms == b.rooms
            && a.paces == b.paces && a.parent == b.parent && a.openLobbies == b.openLobbies
    }

    /// The Games screen came on show or went away: poll quickly only while
    /// it is there, and read straight away when it arrives.
    func setWatching(_ on: Bool) {
        guard watching != on else { return }
        watching = on
        guard pollTask != nil else { return }
        setPolling(false)
        setPolling(true)
    }

    /// On while the scene is active and games are allowed; off otherwise.
    func setPolling(_ on: Bool) {
        if on {
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.load()
                    let every = (self?.watching ?? false) ? Self.pollInterval : Self.idlePollInterval
                    try? await Task.sleep(nanoseconds: UInt64(every * 1_000_000_000))
                }
            }
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    // MARK: - Actions

    /// Start a room. The outcome carries the room so the screen can push it,
    /// or the server's sentence ("Pick a different topic.", a quiz cap) for
    /// the sheet to show where the host is looking.
    func create(_ body: CreateGameBody) async -> GameCreateOutcome {
        guard busy == nil else { return .refused("Starting a game already…") }
        busy = "new"
        defer { busy = nil }
        let outcome = await Self.createRoom(body)
        if case .created = outcome {
            recordPlay(body.game)
            message = nil
            Task { await self.load() }
        }
        return outcome
    }

    /// `POST /api/native/games`. Shared with a room's own "Play again", which
    /// is a new room for Quiz Night.
    static func createRoom(_ body: CreateGameBody) async -> GameCreateOutcome {
        do {
            let data = try await SiteClient.shared.post("api/native/games", body: try JSONEncoder().encode(body))
            return .created(try JSONDecoder().decode(GameRoomEnvelope.self, from: data).room)
        } catch {
            if error is DecodingError { return .refused("The server sent something this version of the app cannot read.") }
            return .refused(error.localizedDescription)
        }
    }

    /// Join an invite. Returns true when the room took me.
    func join(_ invite: GameInvite) async -> Bool {
        let joined = await act("join", on: invite.roomId)
        if joined { recordPlay(invite.game) }
        return joined
    }

    /// A parent closes a lobby that has not started — anybody's, in it or
    /// not. Everyone in it sees it close. True when it did.
    func closeLobby(_ roomId: String) async -> Bool {
        guard busy == nil else { return false }
        busy = roomId
        defer { busy = nil }
        do {
            let body = try JSONEncoder().encode(GameActionBody(action: "close"))
            // The answer is the room only for a parent sitting in it; nothing
            // here needs it, so it is not decoded.
            try await client.post("api/native/games/\(roomId)", body: body)
            clearNotification(roomId)
            message = nil
            await load()
            return true
        } catch SiteError.status(let code, _) where code == 404 {
            message = "That lobby has already gone."
            await load()
            return false
        } catch SiteError.status(_, let sentence) {
            // 403 "Only a parent can close a lobby.", 409 "already started".
            message = sentence
            await load()
            return false
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func decline(_ invite: GameInvite) async {
        _ = await act("decline", on: invite.roomId)
    }

    private func act(_ action: String, on roomId: String) async -> Bool {
        guard busy == nil else { return false }
        busy = roomId
        defer { busy = nil }
        do {
            let body = try JSONEncoder().encode(GameActionBody(action: action))
            try await client.post("api/native/games/\(roomId)", body: body)
            clearNotification(roomId)
            message = nil
            await load()
            return true
        } catch SiteError.status(let code, _) where code == 404 {
            message = "That game has already ended."
            await load()
            return false
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    // MARK: - Notifications

    /// Raise a banner for each invite not seen before. Demo mode never rings:
    /// a UI test must not meet a permission prompt or a banner over its shot.
    private func announce(_ invites: [GameInvite]) async {
        let unseen = invites.filter { !seen.contains($0.roomId) }
        guard !unseen.isEmpty else { return }
        for invite in unseen { seen.insert(invite.roomId) }
        // A push already rang for these; the lobby lists them without a banner.
        let fresh = unseen.filter { $0.pushed != true }
        // Room ids are short-lived; the list only needs the recent ones.
        UserDefaults.standard.set(Array(seen.suffix(200)), forKey: Self.seenKey)
        guard !fresh.isEmpty, !Self.isDemo else { return }

        let centre = UNUserNotificationCenter.current()
        let status = await centre.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        for invite in fresh {
            try? await centre.add(Self.request(for: invite))
        }
    }

    /// The local notification for one invite. Identified by the room, so the
    /// same invite can never stack twice.
    nonisolated static func request(for invite: GameInvite) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = invite.notificationTitle
        content.body = invite.notificationBody
        content.sound = .default
        content.categoryIdentifier = "game"
        content.threadIdentifier = "game"
        // `game` lets the tap open the right screen without a round trip.
        content.userInfo = ["roomId": invite.roomId, "game": invite.game, "category": "game"]
        // An invite holds its lobby for two minutes: one that waits out a
        // Focus is an invite nobody can answer. Matches the pushed one.
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        return UNNotificationRequest(identifier: "game-\(invite.roomId)", content: content, trigger: nil)
    }

    /// Answered from the tab: the banner has nothing left to offer.
    private func clearNotification(_ roomId: String) {
        let centre = UNUserNotificationCenter.current()
        centre.removeDeliveredNotifications(withIdentifiers: ["game-\(roomId)"])
    }

    /// Asked on the Games screen, the first time it opens — the one place an
    /// invite banner obviously matters. Never at launch.
    func askForNotificationsIfUndecided() async {
        guard !Self.isDemo else { return }
        let centre = UNUserNotificationCenter.current()
        guard await centre.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await centre.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private static var isDemo: Bool { SRDemo.isOn }
}

/// How a create went.
enum GameCreateOutcome {
    case created(GameRoom)
    /// Refused or failed, with a sentence for the player.
    case refused(String)
}

import Foundation
import UserNotifications

/// The Games tab: who can be invited, what I am invited to, which rooms I am in.
///
/// ## Invites are PULLED
///
/// There is no push certificate, so an invite reaches a phone only while the
/// app is open: `ContentView` runs `setPolling(true)` while the scene is active
/// and this person may play, and this asks `GET /api/native/games` every five
/// seconds. An invite whose room id has not been seen before raises a LOCAL
/// notification — a banner, since `willPresent` shows them in the foreground —
/// that opens the room when tapped. With the app closed nothing arrives, and
/// no copy anywhere says otherwise.
@MainActor
final class GamesStore: ObservableObject {
    @Published private(set) var lobby: GamesLobby?
    @Published private(set) var loading = false
    /// The room id (or "new") an action is waiting on.
    @Published private(set) var busy: String?
    @Published var message: String?

    static let pollInterval: TimeInterval = 5

    private let client = SiteClient.shared
    private var pollTask: Task<Void, Never>?
    /// Invite room ids already raised, kept across launches so a relaunch does
    /// not ring for the same invite twice.
    private var seen: Set<String>
    private static let seenKey = "games-seen-invites"

    init() {
        seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
    }

    var invites: [GameInvite] { lobby?.invites ?? [] }
    var rooms: [GameRoomSummary] { lobby?.rooms ?? [] }
    var players: [GamePerson] { lobby?.players ?? [] }

    // MARK: - Loading and the poll

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let next: GamesLobby = try await client.send("api/native/games")
            lobby = next
            message = nil
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

    /// On while the scene is active and games are allowed; off otherwise.
    func setPolling(_ on: Bool) {
        if on {
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.load()
                    try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                }
            }
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    // MARK: - Actions

    /// Start a room. Returns it so the screen can push it.
    func create(difficulty: GameDifficulty, invite: [String]) async -> GameRoom? {
        guard busy == nil else { return nil }
        busy = "new"
        defer { busy = nil }
        do {
            let body = try JSONEncoder().encode(CreateGameBody(difficulty: difficulty.rawValue, invite: invite))
            let data = try await client.post("api/native/games", body: body)
            let room = try JSONDecoder().decode(GameRoomEnvelope.self, from: data).room
            message = nil
            Task { await self.load() }
            return room
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    /// Join an invite. Returns true when the room took me.
    func join(_ invite: GameInvite) async -> Bool {
        await act("join", on: invite.roomId)
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
        let fresh = invites.filter { !seen.contains($0.roomId) }
        guard !fresh.isEmpty else { return }
        for invite in fresh { seen.insert(invite.roomId) }
        // Room ids are short-lived; the list only needs the recent ones.
        UserDefaults.standard.set(Array(seen.suffix(200)), forKey: Self.seenKey)
        guard !Self.isDemo else { return }

        let centre = UNUserNotificationCenter.current()
        let status = await centre.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        for invite in fresh {
            try? await centre.add(Self.request(for: invite))
        }
    }

    /// The local notification for one invite. Identified by the room, so the
    /// same invite can never stack twice.
    static func request(for invite: GameInvite) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = invite.notificationTitle
        content.body = invite.notificationBody
        content.sound = .default
        content.categoryIdentifier = "game"
        content.threadIdentifier = "game"
        content.userInfo = ["roomId": invite.roomId, "category": "game"]
        // `.timeSensitive` needs an entitlement this profile does not carry;
        // `.active` is as loud as this app may be.
        content.interruptionLevel = .active
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

    private static var isDemo: Bool {
        #if DEBUG
        return SRDemo.isOn
        #else
        return false
        #endif
    }
}

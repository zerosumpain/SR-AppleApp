import Foundation
import WidgetKit

/// The app's half of the Games widget: each time `GamesStore` reads a lobby
/// that changed, it leaves the invites, the games waiting on this person and
/// the last result on the shared Keychain shelf (`FamilyShelf`, account
/// `.games`), and tells WidgetKit — only when that changed. One line in
/// `GamesStore.load()`.
///
/// The widget also reads the lobby for itself every half hour with the
/// credential the app leaves for the family widgets, so an invite that came
/// while the app was shut still shows. The game titles ride along on the
/// shelf (`GamesWidgetSnapshot.titles`), so it names games as the app does.
///
/// Never in demo mode, never while viewing the app as somebody, and only
/// while this person may play.
@MainActor
enum GamesWidgetBridge {
    private static var active: Bool {
        if SRDemo.isOn { return false }
        let access = AccessStore.shared
        return access.viewingAs == nil && access.familyBoards && access.allows(.games)
    }

    static func save(_ lobby: GamesLobby) {
        guard active else { return }
        let made = snapshot(lobby)
        // Compared without the timestamp: the store polls every minute.
        guard !made.sameContent(as: FamilyShelf.load(GamesWidgetSnapshot.self, .games)) else { return }
        if FamilyShelf.save(made, .games) {
            WidgetCenter.shared.reloadTimelines(ofKind: FamilyWidgetKind.games)
        }
    }

    /// The shelf's snapshot of a lobby. The gallery draws this too.
    static func snapshot(_ lobby: GamesLobby, now: Date = Date()) -> GamesWidgetSnapshot {
        GamesWidget.snapshot(feed(lobby), titles: titles, now: now)
    }

    /// Every game's title, by kind.
    static var titles: [String: String] {
        Dictionary(GameKind.allCases.map { ($0.rawValue, $0.title) }, uniquingKeysWith: { first, _ in first })
    }

    private static func feed(_ lobby: GamesLobby) -> GamesWidgetFeed {
        GamesWidgetFeed(
            invites: lobby.invites.map {
                GamesWidgetFeed.Invite(roomId: $0.roomId, game: $0.game, hostName: $0.hostName, expiresAt: $0.expiresAt)
            },
            rooms: lobby.rooms.map {
                GamesWidgetFeed.Room(id: $0.id, game: $0.game, phase: $0.phase.rawValue, hostName: $0.hostName,
                                     myTurn: $0.myTurn, waitingFor: $0.waitingFor, dueAt: $0.dueAt,
                                     updatedAt: $0.updatedAt, summary: $0.summary)
            },
            serverNow: lobby.serverNow
        )
    }
}

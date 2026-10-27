import Combine
import Foundation
import WidgetKit

/// The app's half of msg family's widget: each time msg family loads it
/// leaves the latest threads and the unread count on the shared Keychain
/// shelf (`FamilyShelf`, account `.messages`), and tells WidgetKit when
/// they changed. `FamilyMessagesStore.load()` calls `save` — the one line
/// the store carries for it.
///
/// It also follows the store's read mark, so opening msg family clears the
/// widget's unread count straight away rather than at the next load: the
/// store marks a thread read AFTER it has loaded it.
///
/// Like `FamilyWidgetBridge`: never in demo mode (the simulator's Keychain is
/// not a phone's), never while viewing the app as somebody — the widget is
/// this phone's person — and only while this person may see msg family.
@MainActor
enum FamilyMessagesWidgetBridge {
    private static var readWatch: AnyCancellable?

    private static var active: Bool {
        if SRDemo.isOn { return false }
        let access = AccessStore.shared
        return access.viewingAs == nil && access.familyBoards
    }

    static func save(_ store: FamilyMessagesStore) {
        watchReads(of: store)
        guard active, let feed = store.feed else { return }
        let made = Self.snapshot(feed, readAt: store.readAt)
        // Compared without the timestamp, so an unchanged feed costs neither
        // a Keychain write nor a reload.
        guard !made.sameContent(as: FamilyShelf.load(FamilyMessagesSnapshot.self, .messages)) else { return }
        if FamilyShelf.save(made, .messages) {
            WidgetCenter.shared.reloadTimelines(ofKind: FamilyWidgetKind.messages)
        }
    }

    /// The shelf's snapshot of the app's feed. The gallery draws this too.
    static func snapshot(_ feed: FamilyMessagesFeed, readAt: Date?, now: Date = Date()) -> FamilyMessagesSnapshot {
        FamilyMessagesWidget.snapshot(feed.messages.map(wire), readAt: readAt, now: now)
    }

    private static func wire(_ m: FamilyMessage) -> FamilyMessagesWidgetFeed.Message {
        FamilyMessagesWidgetFeed.Message(
            id: m.id, fromName: m.fromName, mine: m.mine, body: m.body, at: m.at,
            replies: m.replies.map {
                FamilyMessagesWidgetFeed.Reply(fromName: $0.fromName, mine: $0.mine, body: $0.body, reaction: $0.reaction, at: $0.at)
            }
        )
    }

    /// Once: a new read mark saves again. On the main queue, so the store's
    /// `readAt` has its new value by the time `save` reads it (a `@Published`
    /// publisher fires as the value is about to change).
    private static func watchReads(of store: FamilyMessagesStore) {
        guard readWatch == nil else { return }
        readWatch = store.$readAt
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                Task { @MainActor in save(FamilyMessagesStore.shared) }
            }
    }
}

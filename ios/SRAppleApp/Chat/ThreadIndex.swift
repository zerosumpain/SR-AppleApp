import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// A thread reference that a navigation path can carry.
///
/// Spotlight hands back an identifier, not a `Conversation` — the row the
/// search index holds is a title and an id, and rebuilding a whole conversation
/// from it would mean fetching before navigating. So the path takes either: a
/// `Conversation` when the list already has one, or this when only an id is
/// known and the screen should fetch.
struct ThreadReference: Hashable {
    let id: String
}

/// Put the thread ledger in iPhone search.
///
/// The one capability here that costs nothing and changes how the app is used:
/// a thread is findable from the Home Screen without opening anything. Titles
/// and the last line only — the transcript is not indexed, because Spotlight's
/// index is a file on the device that other system processes read, and a
/// conversation with jkai carries a great deal more than its title.
enum ThreadIndex {
    private static let domain = "com.strangeramblings.com.appleapp.threads"

    static func update(_ conversations: [Conversation]) {
        guard !conversations.isEmpty else { return }
        let items = conversations.prefix(200).map { conversation -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: UTType.text)
            attributes.title = conversation.displayTitle
            attributes.contentDescription = conversation.oneLinePreview
            attributes.keywords = ["jkai", "thread", "strange ramblings"]
            let item = CSSearchableItem(
                uniqueIdentifier: conversation.id,
                domainIdentifier: domain,
                attributeSet: attributes
            )
            // Thirty days. A thread nobody has touched in a month is not what
            // somebody is searching their Home Screen for, and an index that
            // only grows is an index that goes stale invisibly.
            item.expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60)
            return item
        }
        CSSearchableIndex.default().indexSearchableItems(Array(items)) { error in
            if let error { print("[spotlight] index failed: \(error.localizedDescription)") }
        }
    }

    /// Drop everything. Called when the phone is disconnected from the site —
    /// a revoked credential must not leave the titles behind in search.
    static func clear() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
    }
}

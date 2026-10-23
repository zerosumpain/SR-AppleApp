import Foundation

// How bytes get between phones, with no server in the middle.
//
// Two links, one shape, so the session never cares which is carrying it:
//
// - `OfflineNearbyLink`: MultipeerConnectivity. Bluetooth and peer-to-peer
//   Wi-Fi, found automatically, no router, no settings. The default.
// - `OfflineHotspotLink`: Network.framework TCP. Everyone on the same Wi-Fi,
//   or on the host's Personal Hotspot; found over Bonjour, or by typing the
//   address the host's screen shows.
//
// A link moves opaque `Data` — one encoded `OfflineEnvelope` per send — and
// names the other end by a string key it makes up. On a guest the one other
// end is always `OfflineLinkPeer.host`.

/// Which link the host chose.
enum OfflineTransport: String, CaseIterable, Identifiable {
    case nearby, hotspot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nearby: return "Nearby"
        case .hotspot: return "Wi-Fi or hotspot"
        }
    }

    var symbol: String {
        switch self {
        case .nearby: return "dot.radiowaves.left.and.right"
        case .hotspot: return "wifi"
        }
    }

    /// One sentence for the host/join choice.
    var detail: String {
        switch self {
        case .nearby:
            return "Bluetooth and phone-to-phone Wi-Fi. No router needed — just be within a few metres."
        case .hotspot:
            return "Everyone on the same Wi-Fi, or joined to the host's Personal Hotspot."
        }
    }
}

/// A room a guest has found.
struct OfflineFoundHost: Identifiable, Equatable {
    /// The link's own key for it.
    let id: String
    /// The room's name, as the host advertised it.
    let name: String
}

/// Something that happened on a link.
enum OfflineLinkEvent {
    /// Guest: the rooms in reach now (the whole list, every time).
    case found([OfflineFoundHost])
    /// Host: a guest connected. Guest: connected to the host. The guest
    /// speaks first (`hello`).
    case connected(peer: String)
    case disconnected(peer: String)
    case received(Data, from: String)
    /// Host on Wi-Fi: the addresses guests can type, ready to show.
    case listening(addresses: [String])
    /// A sentence for the screen: permission off, Bluetooth off, no route.
    case problem(String)
}

/// The key a guest uses for its host.
enum OfflineLinkPeer {
    static let host = "host"
}

/// One way of connecting phones. Every method is called on the main actor and
/// every event is delivered on it, in order.
@MainActor
protocol OfflineLink: AnyObject {
    var transport: OfflineTransport { get }
    var onEvent: ((OfflineLinkEvent) -> Void)? { get set }
    /// Start a room others can find under `roomName`.
    func host(roomName: String, playerName: String)
    /// Start looking for rooms.
    func browse(playerName: String)
    /// Connect to a room from the found list.
    func join(_ host: OfflineFoundHost)
    /// Connect to a typed address (the hotspot link only; the nearby link
    /// says why not).
    func join(address: String)
    /// Send one message. Reliable and in order, or the peer is dropped.
    func send(_ data: Data, to peer: String)
    /// Hang up on one peer (the host refusing a guest). Best effort.
    func disconnect(_ peer: String)
    /// Stop everything: advertising, browsing, every connection.
    func stop()
}

/// Run `body` on the main actor, after whatever is already queued there.
///
/// MultipeerConnectivity calls its delegates on its own queues and
/// Network.framework calls back on the queue it was given; this is the one
/// door back onto the main actor, through the main queue, so events arrive
/// in the order they happened — a `Task { @MainActor in }` per event makes
/// no such promise, and a view arriving before its lobby is a bug.
func offlineOnMain(_ body: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated { body() }
    }
}

/// Step onto the main actor from a callback that is ALREADY on the main queue
/// (Network.framework handlers started with `queue: .main`, a main-run-loop
/// timer). Synchronous, so nothing is reordered.
func offlineAssumeMain(_ body: @MainActor () -> Void) {
    MainActor.assumeIsolated(body)
}

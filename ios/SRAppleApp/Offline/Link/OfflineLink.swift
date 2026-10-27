import Foundation

// How bytes get between phones, with no server in the middle.
//
// Three links, one shape, so the session never cares which is carrying it:
//
// - `OfflineNearbyLink`: MultipeerConnectivity. Bluetooth and peer-to-peer
//   Wi-Fi, found automatically, no router, no settings.
// - `OfflineHotspotLink`: Network.framework TCP. Everyone on the same Wi-Fi,
//   on the host's Personal Hotspot, or phone-to-phone Wi-Fi; found over
//   Bonjour, or by typing the address the host's screen shows.
// - `OfflineDualLink`: both at once — the default. The host advertises on
//   both; a guest sees one list and joins by whichever route answers.
//
// A link moves opaque `Data` — one encoded `OfflineEnvelope` per send — and
// names the other end by a string key it makes up. On a guest the one other
// end is always `OfflineLinkPeer.host`.

// `OfflineTransport` and `OfflineFoundHost` live in Core/OfflineDiscovery.swift,
// with the merging and health rules that are tested on Linux.

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
    /// Guest, dual link only: the first route did not connect and the join
    /// is now trying this one. The session restarts its join timer, so the
    /// fallback gets its full time rather than whatever the first route left.
    case trying(OfflineTransport)
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
    /// Which link carries the connection to the host, once there is one
    /// (a guest), or nil. The dual link says which of its two it used.
    var connectedVia: OfflineTransport? { get }
    /// Start a room others can find under `roomName`, advertising `roomId`
    /// so a guest that drops can find this same room again.
    func host(roomName: String, roomId: String, playerName: String)
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
    /// Start advertising or browsing again, keeping every connection: after
    /// the app comes back to the front (iOS stops both in the background),
    /// after the Local Network prompt is answered (a browse started under
    /// the prompt finds nothing), and when a list has stayed empty too long.
    func refresh()
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

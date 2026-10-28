import Foundation

/// Nearby and Wi-Fi at once — the link a room uses unless told otherwise.
///
/// The old screens asked the host to pick Nearby or Wi-Fi and the guest to
/// pick the same; a guest who picked the other saw an empty list and no
/// reason why, which is how a family can try for an evening and never play.
/// This link removes the choice. The host advertises the room on both
/// links under one room id. A guest browses both and sees one row per room
/// (`OfflineDiscovery.merge`), then joins by the better route and, if that
/// does not connect, by the other — the guest only notices a short wait.
///
/// Peer keys on the host carry the link they came by ("nearby|…",
/// "hotspot|…"), so the two links' made-up keys can never collide.
@MainActor
final class OfflineDualLink: OfflineLink {
    let transport = OfflineTransport.auto
    var onEvent: ((OfflineLinkEvent) -> Void)?
    var connectedVia: OfflineTransport? { active }

    private let links: [OfflineTransport: any OfflineLink]
    private var isHost = false
    /// Guest: what each link has found, merged into the one list.
    private var found: [OfflineTransport: [OfflineFoundHost]] = [:]
    /// Guest: the room being joined, the route being tried, and the ones left.
    private var joining: (host: OfflineFoundHost, trying: OfflineTransport, left: [OfflineTransport])?
    /// Guest: the link connected to the host.
    private var active: OfflineTransport?
    /// Guest: the route that last failed for each room id, tried last next
    /// time. Kept across `browse` and `stop`, which is how a reconnect that
    /// hung on Wi-Fi gets to try Nearby first.
    private var failedRoute: [String: OfflineTransport] = [:]

    init() {
        links = [.nearby: OfflineNearbyLink(), .hotspot: OfflineHotspotLink()]
        for (transport, link) in links {
            link.onEvent = { [weak self] event in self?.handle(event, from: transport) }
        }
    }

    // MARK: - OfflineLink

    func host(roomName: String, roomId: String, playerName: String) {
        stop()
        isHost = true
        for link in links.values { link.host(roomName: roomName, roomId: roomId, playerName: playerName) }
    }

    func browse(playerName: String) {
        stop()
        isHost = false
        for link in links.values { link.browse(playerName: playerName) }
    }

    func join(_ host: OfflineFoundHost) {
        var routes = OfflineDiscovery.routes(for: host, failed: failedRoute[host.id])
        let first = routes.removeFirst()
        attempt(host, via: first, left: routes)
    }

    func join(address: String) {
        joining = (OfflineFoundHost(id: address, name: address, via: [.hotspot]), .hotspot, [])
        links[.hotspot]?.join(address: address)
    }

    func send(_ data: Data, to peer: String) {
        if isHost {
            guard let target = Self.split(peer) else { return }
            links[target.transport]?.send(data, to: target.peer)
        } else if let active {
            links[active]?.send(data, to: peer)
        }
    }

    func disconnect(_ peer: String) {
        guard isHost, let target = Self.split(peer) else { return }
        links[target.transport]?.disconnect(target.peer)
    }

    func refresh() {
        if !isHost, let active {
            links[active]?.refresh()
        } else {
            for link in links.values { link.refresh() }
        }
    }

    func stop() {
        // A join abandoned part-way (the session's timeout) failed on the
        // route it was trying.
        if let joining { failedRoute[joining.host.id] = joining.trying }
        for link in links.values { link.stop() }
        found = [:]
        joining = nil
        active = nil
    }

    // MARK: - Events from the two links

    private func handle(_ event: OfflineLinkEvent, from transport: OfflineTransport) {
        if isHost {
            hostHandle(event, from: transport)
        } else {
            guestHandle(event, from: transport)
        }
    }

    private func hostHandle(_ event: OfflineLinkEvent, from transport: OfflineTransport) {
        switch event {
        case .connected(let peer):
            onEvent?(.connected(peer: Self.key(peer, via: transport)))
        case .disconnected(let peer):
            onEvent?(.disconnected(peer: Self.key(peer, via: transport)))
        case .received(let data, let peer):
            onEvent?(.received(data, from: Self.key(peer, via: transport)))
        case .listening(let addresses):
            onEvent?(.listening(addresses: addresses))
        case .problem(let text):
            // No Wi-Fi is no problem while Nearby is carrying the room.
            if transport == .nearby || text == OfflineHotspotLink.localNetworkDenied { onEvent?(.problem(text)) }
        case .found, .trying:
            break
        }
    }

    private func guestHandle(_ event: OfflineLinkEvent, from transport: OfflineTransport) {
        switch event {
        case .found(let hosts):
            found[transport] = hosts
            onEvent?(.found(OfflineDiscovery.merge(found)))
        case .connected(let peer):
            guard active == nil, let joining, joining.trying == transport else { return }
            active = transport
            failedRoute[joining.host.id] = nil
            self.joining = nil
            // One route is enough; the other link stops scanning and listening.
            for (other, link) in links where other != transport { link.stop() }
            onEvent?(.connected(peer: peer))
        case .disconnected(let peer):
            if active == transport {
                active = nil
                onEvent?(.disconnected(peer: peer))
            } else if let joining, joining.trying == transport {
                failedRoute[joining.host.id] = transport
                if let next = joining.left.first {
                    // Before the attempt, which can fail at once and say so.
                    onEvent?(.trying(next))
                    attempt(joining.host, via: next, left: Array(joining.left.dropFirst()))
                } else {
                    self.joining = nil
                    onEvent?(.disconnected(peer: peer))
                }
            }
        case .received(let data, let peer):
            if active == transport { onEvent?(.received(data, from: peer)) }
        case .listening, .trying:
            break
        case .problem(let text):
            let carrying = active == transport || joining?.trying == transport
            if carrying || transport == .nearby || text == OfflineHotspotLink.localNetworkDenied {
                onEvent?(.problem(text))
            }
        }
    }

    private func attempt(_ host: OfflineFoundHost, via transport: OfflineTransport, left: [OfflineTransport]) {
        joining = (host, transport, left)
        links[transport]?.join(OfflineFoundHost(id: host.id, name: host.name, via: [transport]))
    }

    // MARK: - Keys

    private static func key(_ peer: String, via transport: OfflineTransport) -> String {
        "\(transport.rawValue)|\(peer)"
    }

    private static func split(_ key: String) -> (transport: OfflineTransport, peer: String)? {
        guard let bar = key.firstIndex(of: "|"),
              let transport = OfflineTransport(rawValue: String(key[..<bar])) else { return nil }
        return (transport, String(key[key.index(after: bar)...]))
    }
}

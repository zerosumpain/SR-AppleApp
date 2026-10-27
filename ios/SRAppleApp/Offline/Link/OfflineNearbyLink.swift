import Foundation
import MultipeerConnectivity

/// Phones in reach of each other, over MultipeerConnectivity: Bluetooth to
/// find each other, then peer-to-peer Wi-Fi (or Bluetooth) to talk. No router,
/// no hotspot, no pairing.
///
/// The host advertises and accepts every invitation — whether a guest may
/// stay is the room's decision, made on their `hello`. Guests browse and
/// invite the host they pick. Every send is `.reliable`, so messages arrive
/// whole and in order.
///
/// The service type `sr-play` is declared in Info.plist as `_sr-play._tcp`
/// and `_sr-play._udp` (NSBonjourServices) — without them iOS 14+ finds nothing.
///
/// ## What made it flaky, and what this does about it
///
/// - A fresh `MCPeerID` on every host and browse. MultipeerConnectivity
///   caches peers it has seen, so a guest listed the host's OLD peer from the
///   last room beside the new one, and inviting the ghost hung for the whole
///   timeout. The peer id is now made once and kept (Apple's own advice), and
///   rooms are listed by the room id the host advertises (`rid`), newest
///   peer winning.
/// - One invitation, then "Could not join". The first invitation often fails
///   while the two radios are still settling; a join now invites up to three
///   times before it gives up.
/// - Browsing and advertising never restarted. iOS stops both when the app
///   goes to the background, and a browse started while the Local Network
///   prompt is up finds nothing, ever. `refresh()` restarts them; the session
///   calls it when the app comes back and while a list stays empty.
/// - A guest kept browsing after it connected, so its radio kept scanning
///   while it should be carrying the game. It stops once connected.
/// - `.required` encryption: a longer handshake that is the commonest cause
///   of sessions stuck in "connecting" or dropping seconds after they
///   connect, protecting game moves between phones in one room. Now `.none`.
///   Both phones must run this version: mismatched preferences do not connect.
@MainActor
final class OfflineNearbyLink: NSObject, OfflineLink {
    /// 1–15 characters, lowercase letters, digits and single hyphens.
    static let serviceType = "sr-play"
    /// How long one invitation may wait for the host to answer.
    static let inviteTimeout: TimeInterval = 10
    /// Invitations a join sends before it gives up.
    static let inviteAttempts = 3

    let transport = OfflineTransport.nearby
    var onEvent: ((OfflineLinkEvent) -> Void)?
    private(set) var connectedVia: OfflineTransport?

    private var me: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var isHost = false
    private var roomName = ""
    private var roomId = ""
    /// Host: each guest's peer id and the key the session knows it by.
    private var keyOf: [MCPeerID: String] = [:]
    private var peerOf: [String: MCPeerID] = [:]
    /// Guest: the rooms seen, by room id, and the one being joined.
    private var foundPeers: [String: (peer: MCPeerID, name: String)] = [:]
    private var hostPeer: MCPeerID?
    private var joining: (roomId: String, attempt: Int)?
    private var hostConnected = false

    // MARK: - OfflineLink

    func host(roomName: String, roomId: String, playerName: String) {
        stop()
        isHost = true
        self.roomName = roomName
        self.roomId = roomId
        let me = Self.localPeer(named: playerName)
        self.me = me
        session = makeSession(me)
        startAdvertising()
    }

    func browse(playerName: String) {
        stop()
        isHost = false
        let me = Self.localPeer(named: playerName)
        self.me = me
        session = makeSession(me)
        startBrowsing()
    }

    func join(_ host: OfflineFoundHost) {
        guard let found = foundPeers[host.id], browser != nil, session != nil else {
            onEvent?(.problem("That room has gone out of reach. Try again in a moment."))
            onEvent?(.disconnected(peer: OfflineLinkPeer.host))
            return
        }
        joining = (host.id, 1)
        hostPeer = found.peer
        invite(found.peer)
    }

    func join(address: String) {
        onEvent?(.problem("Nearby finds rooms by itself — there is no address to type. Use Wi-Fi or hotspot for that."))
    }

    func send(_ data: Data, to peer: String) {
        guard let session else { return }
        let target = isHost ? peerOf[peer] : hostPeer
        guard let target, session.connectedPeers.contains(target) else { return }
        do {
            try session.send(data, toPeers: [target], with: .reliable)
        } catch {
            onEvent?(.problem("A message did not get through: \(error.localizedDescription)"))
        }
    }

    /// MultipeerConnectivity cannot hang up on one peer; a refused guest
    /// leaves by itself when it reads `refused`.
    func disconnect(_ peer: String) {}

    func refresh() {
        if isHost {
            guard session != nil else { return }
            startAdvertising()
        } else if !hostConnected, joining == nil, session != nil {
            startBrowsing()
        }
    }

    func stop() {
        stopAdvertising()
        stopBrowsing()
        session?.disconnect()
        session?.delegate = nil
        session = nil
        keyOf = [:]
        peerOf = [:]
        foundPeers = [:]
        hostPeer = nil
        joining = nil
        hostConnected = false
        connectedVia = nil
    }

    // MARK: - Starting and stopping

    private func makeSession(_ me: MCPeerID) -> MCSession {
        let session = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        return session
    }

    /// A new advertiser each time: one stopped by the system does not always
    /// start again when asked.
    private func startAdvertising() {
        stopAdvertising()
        guard let me else { return }
        // Each discovery pair is at most 255 bytes, "room=" included.
        let advertiser = MCNearbyServiceAdvertiser(
            peer: me,
            discoveryInfo: [
                "room": OfflineName.clipped(roomName, toUTF8: 200),
                "v": String(OfflineEnvelope.version),
                "rid": roomId,
            ],
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()
    }

    private func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
    }

    private func startBrowsing() {
        stopBrowsing()
        guard let me else { return }
        let browser = MCNearbyServiceBrowser(peer: me, serviceType: Self.serviceType)
        browser.delegate = self
        self.browser = browser
        browser.startBrowsingForPeers()
    }

    private func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
    }

    private func invite(_ peer: MCPeerID) {
        guard let browser, let session else { return }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: Self.inviteTimeout)
    }

    /// The next invitation of a join, to the freshest peer for the room (the
    /// host's phone may have come back under a new connection meanwhile).
    private func retryInvite() {
        guard let joining, !hostConnected else { return }
        if browser == nil { startBrowsing() }
        let peer = foundPeers[joining.roomId]?.peer ?? hostPeer
        guard let peer else { return }
        hostPeer = peer
        invite(peer)
    }

    // MARK: - On the main actor

    private func peerChanged(_ peer: MCPeerID, to state: MCSessionState) {
        if isHost {
            switch state {
            case .connected:
                let key = keyOf[peer] ?? UUID().uuidString
                keyOf[peer] = key
                peerOf[key] = peer
                onEvent?(.connected(peer: key))
            case .notConnected:
                if let key = keyOf.removeValue(forKey: peer) {
                    peerOf[key] = nil
                    onEvent?(.disconnected(peer: key))
                }
            default:
                break
            }
            return
        }
        guard peer == hostPeer else { return }
        switch state {
        case .connected:
            hostConnected = true
            joining = nil
            connectedVia = .nearby
            // The game needs the radio now; scanning for other rooms only
            // competes with it. Browsing starts again with the next `browse`.
            stopBrowsing()
            onEvent?(.connected(peer: OfflineLinkPeer.host))
        case .notConnected:
            if hostConnected {
                hostConnected = false
                connectedVia = nil
                onEvent?(.disconnected(peer: OfflineLinkPeer.host))
                return
            }
            guard let joining else { return }
            if joining.attempt < Self.inviteAttempts {
                self.joining = (joining.roomId, joining.attempt + 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    offlineAssumeMain { self?.retryInvite() }
                }
            } else {
                self.joining = nil
                hostPeer = nil
                onEvent?(.disconnected(peer: OfflineLinkPeer.host))
            }
        default:
            break
        }
    }

    private func received(_ data: Data, from peer: MCPeerID) {
        if isHost {
            guard let key = keyOf[peer] else { return }
            onEvent?(.received(data, from: key))
        } else if peer == hostPeer {
            onEvent?(.received(data, from: OfflineLinkPeer.host))
        }
    }

    private func found(_ peer: MCPeerID, info: [String: String]?) {
        // Only rooms speaking this version: another version could not play.
        if let version = info?["v"], version != String(OfflineEnvelope.version) { return }
        // By room id, so the same room is one row however many peers it has
        // been seen as; a host from before room ids is keyed by its peer.
        let key = info?["rid"].flatMap { $0.isEmpty ? nil : $0 } ?? "peer-\(peer.displayName)-\(peer.hash)"
        foundPeers[key] = (peer, info?["room"] ?? peer.displayName)
        publishFound()
    }

    private func lost(_ peer: MCPeerID) {
        foundPeers = foundPeers.filter { $0.value.peer != peer }
        publishFound()
    }

    private func publishFound() {
        let hosts = foundPeers.map { OfflineFoundHost(id: $0.key, name: $0.value.name, via: [.nearby]) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        onEvent?(.found(hosts))
    }

    /// A display name MultipeerConnectivity accepts: non-empty, at most 63
    /// bytes of UTF-8 (`OfflineName.peer`). `MCPeerID` raises an exception
    /// for anything else.
    static func displayName(_ name: String) -> String {
        OfflineName.peer(name)
    }

    private static let peerKey = "offline.mcPeerID"
    private static let peerNameKey = "offline.mcPeerName"

    /// This phone's peer id: made once per name and kept, so other phones
    /// see one peer for it rather than a new stranger every room.
    static func localPeer(named name: String) -> MCPeerID {
        let display = displayName(name)
        let defaults = UserDefaults.standard
        if defaults.string(forKey: peerNameKey) == display,
           let data = defaults.data(forKey: peerKey),
           let peer = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            return peer
        }
        let peer = MCPeerID(displayName: display)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: peer, requiringSecureCoding: true) {
            defaults.set(data, forKey: peerKey)
            defaults.set(display, forKey: peerNameKey)
        }
        return peer
    }
}

// MARK: - Delegates (called on MultipeerConnectivity's queues)

extension OfflineNearbyLink: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        offlineOnMain { [weak self] in self?.peerChanged(peerID, to: state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        offlineOnMain { [weak self] in self?.received(data, from: peerID) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    /// No certificates: anybody in reach may connect, and the room decides.
    nonisolated func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }
}

extension OfflineNearbyLink: MCNearbyServiceAdvertiserDelegate {
    /// Every invitation is accepted at once: a family phone should never wait
    /// on a prompt, and the room turns away anyone it must (a full room,
    /// another version) on their hello. Only a link that has stopped hosting
    /// declines.
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        offlineOnMain { [weak self] in
            guard let self, let session = self.session, self.isHost else {
                invitationHandler(false, nil)
                return
            }
            invitationHandler(true, session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        offlineOnMain { [weak self] in
            self?.onEvent?(.problem("Could not start the room nearby. Check Bluetooth is on, then try again."))
        }
    }
}

extension OfflineNearbyLink: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        offlineOnMain { [weak self] in self?.found(peerID, info: info) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        offlineOnMain { [weak self] in self?.lost(peerID) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        offlineOnMain { [weak self] in
            self?.onEvent?(.problem("Could not look for rooms nearby. Check Bluetooth is on and Local Network is allowed for SR Companion in Settings."))
        }
    }
}

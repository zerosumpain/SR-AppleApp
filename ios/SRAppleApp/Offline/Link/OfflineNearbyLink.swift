import Foundation
import MultipeerConnectivity

/// Phones in reach of each other, over MultipeerConnectivity: Bluetooth to
/// find each other, then peer-to-peer Wi-Fi (or Bluetooth) to talk. No router,
/// no hotspot, no pairing.
///
/// The host advertises and accepts every invitation — whether a guest may
/// stay is the room's decision, made on their `hello`. Guests browse and
/// invite the host they pick. The session is `.required` encryption, and
/// every send is `.reliable`, so messages arrive whole and in order.
///
/// The service type `sr-play` is declared in Info.plist as `_sr-play._tcp`
/// and `_sr-play._udp` (NSBonjourServices) — without them iOS 14+ finds nothing.
@MainActor
final class OfflineNearbyLink: NSObject, OfflineLink {
    /// 1–15 characters, lowercase letters, digits and single hyphens.
    static let serviceType = "sr-play"

    let transport = OfflineTransport.nearby
    var onEvent: ((OfflineLinkEvent) -> Void)?

    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var isHost = false
    /// Host: each guest's peer id and the key the session knows it by.
    private var keyOf: [MCPeerID: String] = [:]
    private var peerOf: [String: MCPeerID] = [:]
    /// Guest: the rooms seen, and the one joined.
    private var foundPeers: [String: (peer: MCPeerID, name: String)] = [:]
    private var hostPeer: MCPeerID?

    // MARK: - OfflineLink

    func host(roomName: String, playerName: String) {
        stop()
        isHost = true
        let me = MCPeerID(displayName: Self.displayName(playerName))
        let session = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        // Each discovery pair is at most 255 bytes, "room=" included.
        let advertiser = MCNearbyServiceAdvertiser(
            peer: me,
            discoveryInfo: ["room": OfflineName.clipped(roomName, toUTF8: 200), "v": String(OfflineEnvelope.version)],
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        self.session = session
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()
    }

    func browse(playerName: String) {
        stop()
        isHost = false
        let me = MCPeerID(displayName: Self.displayName(playerName))
        let session = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        let browser = MCNearbyServiceBrowser(peer: me, serviceType: Self.serviceType)
        browser.delegate = self
        self.session = session
        self.browser = browser
        browser.startBrowsingForPeers()
    }

    func join(_ host: OfflineFoundHost) {
        guard let found = foundPeers[host.id], let browser, let session else {
            onEvent?(.problem("That room has gone out of reach. Try again in a moment."))
            return
        }
        hostPeer = found.peer
        browser.invitePeer(found.peer, to: session, withContext: nil, timeout: 20)
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

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        session?.disconnect()
        session?.delegate = nil
        advertiser = nil
        browser = nil
        session = nil
        keyOf = [:]
        peerOf = [:]
        foundPeers = [:]
        hostPeer = nil
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
        } else {
            guard peer == hostPeer else { return }
            switch state {
            case .connected: onEvent?(.connected(peer: OfflineLinkPeer.host))
            case .notConnected: onEvent?(.disconnected(peer: OfflineLinkPeer.host))
            default: break
            }
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
        let key = foundPeers.first { $0.value.peer == peer }?.key ?? UUID().uuidString
        foundPeers[key] = (peer, info?["room"] ?? peer.displayName)
        publishFound()
    }

    private func lost(_ peer: MCPeerID) {
        foundPeers = foundPeers.filter { $0.value.peer != peer }
        publishFound()
    }

    private func publishFound() {
        let hosts = foundPeers.map { OfflineFoundHost(id: $0.key, name: $0.value.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        onEvent?(.found(hosts))
    }

    /// A display name MultipeerConnectivity accepts: non-empty, at most 63
    /// bytes of UTF-8 (`OfflineName.peer`). `MCPeerID` raises an exception
    /// for anything else.
    static func displayName(_ name: String) -> String {
        OfflineName.peer(name)
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
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        offlineOnMain { [weak self] in
            guard let self, let session = self.session else {
                invitationHandler(false, nil)
                return
            }
            // The room is the judge: a sixth phone is told why on its hello.
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

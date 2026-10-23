import Foundation
import Network

/// Phones on one Wi-Fi network — a router, or the host's Personal Hotspot —
/// over plain TCP from Network.framework.
///
/// The host listens (on port 47474 when it is free) and advertises the room
/// over Bonjour as `_srplay._tcp`; guests browse for it, or type the address
/// the host's lobby shows (on a hotspot that is usually 172.20.10.1). Each
/// message is framed as a 4-byte big-endian length and the JSON
/// (`OfflineFraming`), because a TCP stream has no message boundaries.
///
/// Every handler runs on the main queue and steps onto the main actor with
/// `MainActor.assumeIsolated`, synchronously, so bytes are handled in the
/// order they arrived.
@MainActor
final class OfflineHotspotLink: OfflineLink {
    /// Declared in Info.plist (NSBonjourServices).
    static let serviceType = "_srplay._tcp"

    let transport = OfflineTransport.hotspot
    var onEvent: ((OfflineLinkEvent) -> Void)?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [String: OfflineStreamConnection] = [:]
    private var endpoints: [String: NWEndpoint] = [:]
    private var roomName = ""

    // MARK: - Host

    func host(roomName: String, playerName: String) {
        stop()
        self.roomName = roomName
        listen(on: OfflineAddress.preferredPort)
    }

    /// `port` nil: any free port the system picks.
    private func listen(on port: UInt16?) {
        let parameters = NWParameters.tcp
        let listener: NWListener
        do {
            if let port, let fixed = NWEndpoint.Port(rawValue: port) {
                listener = try NWListener(using: parameters, on: fixed)
            } else {
                listener = try NWListener(using: parameters)
            }
        } catch {
            if port != nil { listen(on: nil) } else { onEvent?(.problem("Could not open the room on Wi-Fi: \(error.localizedDescription)")) }
            return
        }
        // A Bonjour service name is at most 63 bytes; a longer one is not
        // registered. Nil lets the system name it after the phone.
        let serviceName = OfflineName.clipped(roomName, toUTF8: 63)
        listener.service = NWListener.Service(name: serviceName.isEmpty ? nil : serviceName, type: Self.serviceType)
        listener.stateUpdateHandler = { [weak self] state in
            offlineAssumeMain { self?.listenerChanged(state, triedPort: port) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            offlineAssumeMain { self?.accept(connection) }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    private func listenerChanged(_ state: NWListener.State, triedPort: UInt16?) {
        switch state {
        case .ready:
            let port = listener?.port?.rawValue ?? OfflineAddress.preferredPort
            let addresses = OfflineAddress.joinable(OfflineHotspotLink.interfaceAddresses()).map { OfflineAddress.display($0, port: port) }
            onEvent?(.listening(addresses: addresses))
            if addresses.isEmpty {
                onEvent?(.problem("This phone is not on Wi-Fi and its Personal Hotspot is off. Turn one on — guests need to be on the same network."))
            }
        case .failed(let error):
            listener?.cancel()
            listener = nil
            // Port taken (another app, or a room that has not quite closed):
            // take any port instead and show it with the address.
            if triedPort != nil {
                listen(on: nil)
            } else {
                onEvent?(.problem(OfflineHotspotLink.sentence(for: error)))
            }
        case .waiting(let error):
            onEvent?(.problem(OfflineHotspotLink.sentence(for: error)))
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let key = UUID().uuidString
        let stream = OfflineStreamConnection(connection: connection)
        stream.onReady = { [weak self] in self?.onEvent?(.connected(peer: key)) }
        stream.onMessage = { [weak self] data in self?.onEvent?(.received(data, from: key)) }
        stream.onClose = { [weak self] _ in
            guard let self, self.connections.removeValue(forKey: key) != nil else { return }
            self.onEvent?(.disconnected(peer: key))
        }
        connections[key] = stream
        stream.start()
    }

    // MARK: - Guest

    func browse(playerName: String) {
        stop()
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: NWParameters.tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            offlineAssumeMain { self?.resultsChanged(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            offlineAssumeMain { self?.browserChanged(state) }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    private func resultsChanged(_ results: Set<NWBrowser.Result>) {
        var hosts: [OfflineFoundHost] = []
        var next: [String: NWEndpoint] = [:]
        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }
            let key = "\(name).\(type).\(domain)"
            next[key] = result.endpoint
            hosts.append(OfflineFoundHost(id: key, name: name))
        }
        endpoints = next
        onEvent?(.found(hosts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }))
    }

    private func browserChanged(_ state: NWBrowser.State) {
        switch state {
        case .failed(let error), .waiting(let error):
            onEvent?(.problem(OfflineHotspotLink.sentence(for: error)))
        default:
            break
        }
    }

    func join(_ host: OfflineFoundHost) {
        guard let endpoint = endpoints[host.id] else {
            onEvent?(.problem("That room has gone. Pull the list down or wait a moment for it to come back."))
            return
        }
        connect(to: endpoint)
    }

    func join(address: String) {
        guard let parsed = OfflineAddress.parse(address), let port = NWEndpoint.Port(rawValue: parsed.port) else {
            onEvent?(.problem("That does not look like an address. It is four numbers with dots, like 172.20.10.1."))
            return
        }
        connect(to: .hostPort(host: NWEndpoint.Host(parsed.host), port: port))
    }

    private func connect(to endpoint: NWEndpoint) {
        connections[OfflineLinkPeer.host]?.cancel()
        let key = OfflineLinkPeer.host
        let stream = OfflineStreamConnection(connection: NWConnection(to: endpoint, using: .tcp))
        stream.onReady = { [weak self] in self?.onEvent?(.connected(peer: key)) }
        stream.onMessage = { [weak self] data in self?.onEvent?(.received(data, from: key)) }
        stream.onWaiting = { [weak self] error in self?.onEvent?(.problem(OfflineHotspotLink.sentence(for: error))) }
        stream.onClose = { [weak self, weak stream] _ in
            guard let self, let stream, self.connections[key] === stream else { return }
            self.connections[key] = nil
            self.onEvent?(.disconnected(peer: key))
        }
        connections[key] = stream
        stream.start()
    }

    // MARK: - Both

    func send(_ data: Data, to peer: String) {
        connections[peer]?.send(data)
    }

    func disconnect(_ peer: String) {
        // After a moment, so the refusal on its way out is not cut off.
        let stream = connections.removeValue(forKey: peer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            offlineAssumeMain { stream?.cancel() }
        }
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        browser?.browseResultsChangedHandler = nil
        browser?.stateUpdateHandler = nil
        browser?.cancel()
        browser = nil
        let open = connections.values
        connections = [:]
        for stream in open { stream.cancel() }
        endpoints = [:]
    }

    // MARK: - Helpers

    /// What went wrong, as the person holding the phone can act on it.
    static func sentence(for error: NWError) -> String {
        // kDNSServiceErr_PolicyDenied: the Local Network permission is off.
        if case .dns(let code) = error, code == -65570 {
            return "SR Companion is not allowed on the local network. Turn it on in Settings › Privacy & Security › Local Network, then try again."
        }
        if case .posix(let code) = error {
            switch code {
            case .ECONNREFUSED: return "Nobody is hosting at that address. Check the number on the host's screen."
            case .ENETUNREACH, .EHOSTUNREACH, .ENETDOWN: return "Cannot reach that phone. Join the same Wi-Fi as the host, or the host's Personal Hotspot."
            case .ETIMEDOUT: return "The host did not answer. Check you are on the same Wi-Fi or hotspot."
            default: break
            }
        }
        return "Connection problem: \(error.localizedDescription)"
    }

    /// This phone's IPv4 addresses by interface, from getifaddrs.
    static func interfaceAddresses() -> [(name: String, address: String)] {
        var out: [(name: String, address: String)] = []
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let start = first else { return out }
        defer { freeifaddrs(start) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = start
        while let current = cursor {
            cursor = current.pointee.ifa_next
            let flags = Int32(current.pointee.ifa_flags)
            guard let address = current.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let ok = getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard ok == 0 else { continue }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            out.append((String(cString: current.pointee.ifa_name), text))
        }
        return out
    }
}

/// One TCP connection carrying framed messages.
@MainActor
final class OfflineStreamConnection {
    private let connection: NWConnection
    private var buffer = Data()
    private var closed = false

    var onReady: (() -> Void)?
    var onMessage: ((Data) -> Void)?
    /// Still trying (no route yet); the reason, for the screen.
    var onWaiting: ((NWError) -> Void)?
    /// Gone, with the reason when there was one.
    var onClose: ((NWError?) -> Void)?

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            offlineAssumeMain { self?.changed(state) }
        }
        connection.start(queue: .main)
    }

    func send(_ payload: Data) {
        guard !closed else { return }
        connection.send(content: OfflineFraming.frame(payload), completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            offlineAssumeMain { self?.close(error) }
        })
    }

    func cancel() {
        guard !closed else { return }
        closed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    private func changed(_ state: NWConnection.State) {
        switch state {
        case .ready:
            onReady?()
            receive()
        case .waiting(let error):
            onWaiting?(error)
        case .failed(let error):
            close(error)
        case .cancelled:
            close(nil)
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            offlineAssumeMain {
                guard let self, !self.closed else { return }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    guard let messages = OfflineFraming.drain(&self.buffer) else {
                        self.close(nil)
                        return
                    }
                    for message in messages where !self.closed { self.onMessage?(message) }
                    // A message can end the room (a refusal, a bye), which
                    // cancels this connection under us.
                    if self.closed { return }
                }
                if let error {
                    self.close(error)
                } else if isComplete {
                    self.close(nil)
                } else {
                    self.receive()
                }
            }
        }
    }

    private func close(_ error: NWError?) {
        guard !closed else { return }
        closed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose?(error)
    }
}

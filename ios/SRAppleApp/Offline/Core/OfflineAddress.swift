import Foundation

// The arithmetic the Wi-Fi/hotspot link needs, kept out of the link so it can
// be tested here: how a message is framed on a TCP stream, how a typed
// address is read, and which of a phone's addresses to show for joining.

/// A TCP stream has no message boundaries, so each message goes as a 4-byte
/// big-endian length and then that many bytes of JSON.
enum OfflineFraming {
    /// Far above any real view; a length beyond it means a garbled stream.
    static let maxLength = 4 * 1024 * 1024

    /// The length header followed by `payload`.
    static func frame(_ payload: Data) -> Data {
        let length = UInt32(payload.count)
        var out = Data([UInt8(length >> 24 & 0xFF), UInt8(length >> 16 & 0xFF),
                        UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)])
        out.append(payload)
        return out
    }

    /// The length a 4-byte header announces; nil for a short header, zero or
    /// anything over `maxLength`.
    static func length(of header: Data) -> Int? {
        guard header.count == 4 else { return nil }
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0, length <= maxLength else { return nil }
        return length
    }

    /// Split a buffer into whole messages, leaving any partial tail in it.
    /// Returns nil if the stream is garbled (a length out of range).
    static func drain(_ buffer: inout Data) -> [Data]? {
        var out: [Data] = []
        while buffer.count >= 4 {
            let start = buffer.startIndex
            guard let length = length(of: buffer.subdata(in: start..<start + 4)) else { return nil }
            guard buffer.count >= 4 + length else { break }
            out.append(buffer.subdata(in: start + 4..<start + 4 + length))
            buffer = buffer.subdata(in: start + 4 + length..<buffer.endIndex)
        }
        return out
    }
}

/// Addresses for the "type the host's address" path.
enum OfflineAddress {
    /// The port a hotspot host listens on when it can, so a typed address
    /// needs no port. A host that cannot have it shows the one it got.
    static let preferredPort: UInt16 = 47_474

    /// "172.20.10.1", "172.20.10.1:5000", "sams-phone.local" → host and port.
    /// Nil for anything that is not plausibly an address.
    static func parse(_ text: String, defaultPort: UInt16 = preferredPort) -> (host: String, port: UInt16)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        var host = trimmed
        var port = defaultPort
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2 {
            guard let typed = UInt16(parts[1]), typed > 0 else { return nil }
            host = String(parts[0])
            port = typed
        } else if parts.count > 2 {
            return nil
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard !host.isEmpty, host.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        // All digits and dots: it must be a whole IPv4 address.
        if host.allSatisfy({ $0.isNumber || $0 == "." }) {
            let octets = host.split(separator: ".", omittingEmptySubsequences: false)
            guard octets.count == 4, octets.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) else { return nil }
        }
        return (host, port)
    }

    /// Which of this phone's IPv4 addresses others can join, best first:
    /// the Personal Hotspot bridge (`bridge…`, 172.20.10.1 on most phones),
    /// then Wi-Fi (`en…`). Mobile data, VPN tunnels, AWDL and loopback are
    /// never useful to someone standing next to you, so they are left out.
    static func joinable(_ interfaces: [(name: String, address: String)]) -> [String] {
        func rank(_ name: String) -> Int? {
            if name.hasPrefix("bridge") { return 0 }
            if name == "en0" { return 1 }
            if name.hasPrefix("en") { return 2 }
            return nil
        }
        let ranked = interfaces.compactMap { item -> (rank: Int, address: String)? in
            guard let r = rank(item.name), !item.address.hasPrefix("169.254."), !item.address.hasPrefix("127.") else { return nil }
            return (r, item.address)
        }
        var seen = Set<String>()
        return ranked.sorted { $0.rank < $1.rank }.map(\.address).filter { seen.insert($0).inserted }
    }

    /// "172.20.10.1" when the host has the preferred port, "172.20.10.1:5000" otherwise.
    static func display(_ address: String, port: UInt16) -> String {
        port == preferredPort ? address : "\(address):\(port)"
    }
}

/// Names as Bonjour and MultipeerConnectivity count them: in bytes, not
/// characters. A Bonjour service name stops at 63 bytes (a longer one is not
/// registered), a discovery-info pair at 255, and a peer's display name at 63
/// — longer, or empty, and `MCPeerID` raises an exception, which ends the
/// app. Twenty characters of a name can be far more than that once they are
/// accented, CJK or emoji, so every name that goes out over the air is cut
/// here first.
enum OfflineName {
    /// `text` cut at a character boundary to at most `bytes` bytes of UTF-8.
    static func clipped(_ text: String, toUTF8 bytes: Int) -> String {
        var out = ""
        var used = 0
        for character in text {
            let size = String(character).utf8.count
            guard used + size <= bytes else { break }
            out.append(character)
            used += size
        }
        return out
    }

    /// A display name `MCPeerID` accepts: the cleaned name in at most 63
    /// bytes, or "Player" when even its first character is longer than that
    /// (one letter stacked with combining marks).
    static func peer(_ name: String) -> String {
        let out = clipped(OfflineRoom.cleanName(name), toUTF8: 63)
        return out.isEmpty ? "Player" : out
    }
}

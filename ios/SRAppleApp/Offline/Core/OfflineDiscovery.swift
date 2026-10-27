import Foundation

// Finding a room and keeping hold of it, as pure values: which way a room can
// be reached, the merged list a guest sees, how healthy each connection
// looks, and when a dropped guest stops trying to get back in.
//
// These used to live beside the links, which only compile on an iPhone. They
// decide what the screen says when a connection is flaky, so they are here,
// where a Linux test can hold them to it.

/// How phones reach each other.
enum OfflineTransport: String, CaseIterable, Identifiable, Codable {
    /// Both at once: the host advertises over Nearby and Wi-Fi together, and
    /// a guest lists rooms from both and joins by whichever answers. The
    /// default, because asking people to pick the same one was the commonest
    /// reason two phones never met.
    case auto
    case nearby, hotspot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Nearby and Wi-Fi"
        case .nearby: return "Nearby"
        case .hotspot: return "Wi-Fi or hotspot"
        }
    }

    /// One word for a badge on a found room.
    var short: String {
        switch self {
        case .auto: return "Any"
        case .nearby: return "Nearby"
        case .hotspot: return "Wi-Fi"
        }
    }

    var symbol: String {
        switch self {
        case .auto: return "antenna.radiowaves.left.and.right"
        case .nearby: return "dot.radiowaves.left.and.right"
        case .hotspot: return "wifi"
        }
    }

    /// One sentence for the host/join choice.
    var detail: String {
        switch self {
        case .auto:
            return "Bluetooth, phone-to-phone Wi-Fi and your Wi-Fi or hotspot, all at once. Guests find you whichever they have on."
        case .nearby:
            return "Bluetooth and phone-to-phone Wi-Fi. No router needed — just be within a few metres."
        case .hotspot:
            return "Everyone on the same Wi-Fi, or joined to the host's Personal Hotspot."
        }
    }
}

/// A room a guest has found.
struct OfflineFoundHost: Identifiable, Equatable {
    /// The room's own id (`OfflineRoom.roomKey`) when the host advertised one,
    /// so the same room seen twice — over two links, or again after a drop —
    /// is one row, and a dropped guest can find its way back to it.
    let id: String
    /// The room's name, as the host advertised it.
    let name: String
    /// The links it was seen on, best first.
    var via: [OfflineTransport] = []
}

enum OfflineDiscovery {
    /// Which link to try first when a room is seen on both. TCP over a shared
    /// network (or phone-to-phone Wi-Fi, which the Wi-Fi link also uses) holds
    /// a busy game better than MultipeerConnectivity's sessions do, and the
    /// nearby link is the fallback that needs no network at all.
    static let preference: [OfflineTransport] = [.hotspot, .nearby]

    /// One list from the rooms each link has found: a room seen on both links
    /// is one row whose `via` lists both, best first; sorted by name.
    static func merge(_ lists: [OfflineTransport: [OfflineFoundHost]]) -> [OfflineFoundHost] {
        var byId: [String: OfflineFoundHost] = [:]
        var order: [String] = []
        for transport in preference + lists.keys.filter({ !preference.contains($0) }).sorted(by: { $0.rawValue < $1.rawValue }) {
            for host in lists[transport] ?? [] {
                if var known = byId[host.id] {
                    if !known.via.contains(transport) { known.via.append(transport) }
                    byId[host.id] = known
                } else {
                    byId[host.id] = OfflineFoundHost(id: host.id, name: host.name, via: [transport])
                    order.append(host.id)
                }
            }
        }
        return order.compactMap { byId[$0] }.sorted {
            let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
            return byName == .orderedSame ? $0.id < $1.id : byName == .orderedAscending
        }
    }

    /// The links to try for `host`, in order.
    static func routes(for host: OfflineFoundHost) -> [OfflineTransport] {
        let known = preference.filter { host.via.contains($0) }
        return known.isEmpty ? preference : known
    }

    /// A short room id for a new room: eight hex digits from `seed`. Short,
    /// because it rides in a Bonjour TXT record and a discovery-info pair.
    static func roomKey(seed: UInt64) -> String {
        let low = String(seed & 0xFFFF_FFFF, radix: 16)
        return String(repeating: "0", count: max(0, 8 - low.count)) + low
    }
}

/// How one phone's connection looks from the other end, from when it was
/// last heard. A guest pings every few seconds, so a quiet guest is a sign of
/// trouble well before the link gives up on it.
enum OfflinePeerHealth: Equatable {
    /// Heard in the last few seconds.
    case good
    /// Not heard for this many whole seconds.
    case quiet(Int)
    /// Out of reach: the link has dropped them.
    case away
    /// The host itself, or a computer player: nothing to hear.
    case local

    /// Heard within this long is good.
    static let goodWithin: Double = 6

    static func of(lastHeard: Double?, now: Double, present: Bool) -> OfflinePeerHealth {
        guard present else { return .away }
        guard let lastHeard else { return .quiet(0) }
        let gap = max(0, now - lastHeard)
        return gap <= goodWithin ? .good : .quiet(Int(gap))
    }

    /// The chip's words.
    var label: String? {
        switch self {
        case .good: return "Connected"
        case .quiet(let seconds): return seconds > 0 ? "Quiet \(seconds) s" : "Connecting"
        case .away: return "Away"
        case .local: return nil
        }
    }

    var isTrouble: Bool {
        switch self {
        case .good, .local: return false
        case .quiet, .away: return true
        }
    }
}

/// When a guest that lost the host keeps trying to get back in, and when it
/// gives up. Locking the phone for a moment, walking to the kitchen, the
/// host's screen dimming: each drops a connection that comes back if it is
/// asked to, so the guest asks rather than ending the game.
struct OfflineReconnect: Equatable {
    /// How long a dropped guest keeps looking for its room.
    static let patience: Double = 45
    /// How long one attempt to connect may take before the guest goes back
    /// to the list (the links have their own, shorter, timeouts inside it).
    static let joinTimeout: Double = 25
    /// How often a browse that has found nothing is restarted: the first
    /// browse can start before the Local Network permission is granted, and
    /// then finds nothing until it is restarted.
    static let rebrowseEvery: Double = 10

    let roomId: String
    let hostName: String
    let since: Double

    func givenUp(now: Double) -> Bool { now - since >= Self.patience }

    /// The room to join from a fresh list, if it is back.
    func match(in found: [OfflineFoundHost]) -> OfflineFoundHost? {
        found.first { $0.id == roomId }
    }
}

/// A connection test's answer, as a sentence.
enum OfflineRoundTrip {
    /// Below this a reaction game feels instant.
    static let goodMs = 80
    static let usableMs = 250

    static func sentence(ms: Int?) -> String {
        guard let ms else { return "No answer from the host. Move closer, or check Bluetooth and Wi-Fi are on." }
        if ms < goodMs { return "Round trip \(ms) ms — a strong connection." }
        if ms < usableMs { return "Round trip \(ms) ms — fine for every game." }
        return "Round trip \(ms) ms — slow. Reaction games will feel laggy; move closer."
    }
}

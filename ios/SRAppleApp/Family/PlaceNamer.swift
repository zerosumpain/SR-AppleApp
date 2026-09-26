import Foundation
import CoreLocation
import Combine

/// "near Station Road, Darlington", for a pin that is moving.
///
/// The site sends coordinates and never a street: nothing on the server
/// reverse-geocodes a family member's position, and nothing needs to. The
/// phone asks Apple's geocoder — the same service the Maps app uses, over the
/// system's own connection — only for people who are MOVING, and caches by a
/// ~100 m square so a refresh every 15 seconds costs no lookups on a walk
/// that has not crossed a block.
@MainActor
final class PlaceNamer: ObservableObject {
    static let shared = PlaceNamer()

    @Published private(set) var names: [String: String] = [:]
    private var asking: Set<String> = []
    private let geocoder = CLGeocoder()

    /// The cached name for a position, or nil (and a lookup started).
    func name(lat: Double, lon: Double) -> String? {
        let key = Self.key(lat: lat, lon: lon)
        if let known = names[key] { return known.isEmpty ? nil : known }
        lookUp(key: key, lat: lat, lon: lon)
        return nil
    }

    /// Three decimals: about 110 m of latitude, 70 m of longitude here.
    nonisolated static func key(lat: Double, lon: Double) -> String {
        String(format: "%.3f,%.3f", lat, lon)
    }

    /// "Station Road, Darlington", "Darlington", or nil. PURE.
    nonisolated static func phrase(street: String?, area: String?, town: String?) -> String? {
        let place = [street ?? area, town].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var seen: [String] = []
        for part in place where !seen.contains(part) { seen.append(part) }
        return seen.isEmpty ? nil : seen.joined(separator: ", ")
    }

    private func lookUp(key: String, lat: Double, lon: Double) {
        // One at a time: CLGeocoder refuses a second request while the first
        // runs, and the moving list is a handful of people at most.
        guard !asking.contains(key), !geocoder.isGeocoding else { return }
        asking.insert(key)
        geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)) { [weak self] marks, _ in
            Task { @MainActor in
                guard let self else { return }
                self.asking.remove(key)
                let mark = marks?.first
                // An empty string caches "no answer" so a failed square is
                // not asked again on every refresh.
                self.names[key] = Self.phrase(street: mark?.thoroughfare, area: mark?.subLocality, town: mark?.locality) ?? ""
            }
        }
    }
}

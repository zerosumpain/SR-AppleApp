import Foundation
import Combine
import MapLibre

/// Map packs downloaded for routes, so a route can be walked with no signal.
///
/// A pack is MapLibre's: the tiles, glyphs and sprites of OpenFreeMap's style
/// inside a shape, fetched into the same store every map tile is read through.
/// The shape is a CORRIDOR — a square either side of the route every ~200 m —
/// not the route's bounding box: an A-to-B across a county has a box of
/// thousands of tiles and a corridor of dozens. OpenFreeMap's tiles stop at
/// zoom 14 and MapLibre draws closer zooms from them, so 10–14 is the whole
/// pack: a 10 km loop is a few megabytes.
///
/// The web kit caches OpenStreetMap's raster tiles, which OSM's tile policy
/// forbids above 250 tiles at zoom 13+; this does not touch OSM's servers.
@MainActor
final class OfflineMaps: ObservableObject {
    static let shared = OfflineMaps()

    enum State: Equatable {
        case none
        case downloading(Double)
        case ready(bytes: UInt64)
        case failed(String)
    }

    struct Saved: Identifiable, Equatable {
        let routeId: String
        let name: String
        let bytes: UInt64
        let complete: Bool
        var id: String { routeId }
    }

    @Published private(set) var states: [String: State] = [:]
    @Published private(set) var saved: [Saved] = []

    static let minZoom = 10.0
    static let maxZoom = 14.0
    /// Half the corridor's width.
    static let corridorM = 500.0

    private var packs: [String: MLNOfflinePack] = [:]
    private var observers: [NSObjectProtocol] = []
    private var watch: NSKeyValueObservation?

    private struct Context: Codable {
        let routeId: String
        let name: String
    }

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .MLNOfflinePackProgressChanged, object: nil, queue: .main) { [weak self] note in
            guard let pack = note.object as? MLNOfflinePack else { return }
            MainActor.assumeIsolated { self?.update(pack) }
        })
        observers.append(center.addObserver(forName: .MLNOfflinePackError, object: nil, queue: .main) { [weak self] note in
            guard let pack = note.object as? MLNOfflinePack,
                  let id = OfflineMaps.context(of: pack)?.routeId else { return }
            let error = note.userInfo?[MLNOfflinePackUserInfoKey.error] as? NSError
            MainActor.assumeIsolated {
                self?.states[id] = .failed(error?.localizedDescription ?? "The download stopped.")
            }
        })
        watch = MLNOfflineStorage.shared.observe(\.packs, options: [.initial, .new]) { [weak self] storage, _ in
            let current = storage.packs ?? []
            Task { @MainActor in self?.adopt(current) }
        }
    }

    func state(for routeId: String) -> State { states[routeId] ?? .none }

    var totalBytes: UInt64 { saved.reduce(0) { $0 + $1.bytes } }

    // MARK: Download and delete

    func download(_ detail: PlannedRouteDetail) {
        if case .downloading = state(for: detail.id) { return }
        let context = (try? JSONEncoder().encode(Context(routeId: detail.id, name: detail.name))) ?? Data()
        let region = MLNShapeOfflineRegion(
            styleURL: SRMapStyle.url,
            shape: Self.corridor(detail.coordinates),
            fromZoomLevel: Self.minZoom,
            toZoomLevel: Self.maxZoom
        )
        states[detail.id] = .downloading(0)
        // A previous, partial pack for this route is replaced, not stacked.
        if let old = packs[detail.id] {
            MLNOfflineStorage.shared.removePack(old, withCompletionHandler: nil)
            packs[detail.id] = nil
        }
        MLNOfflineStorage.shared.addPack(for: region, withContext: context) { [weak self] pack, error in
            MainActor.assumeIsolated {
                guard let pack else {
                    self?.states[detail.id] = .failed(error?.localizedDescription ?? "Could not start the download.")
                    return
                }
                self?.packs[detail.id] = pack
                pack.resume()
            }
        }
    }

    func delete(_ routeId: String) {
        guard let pack = packs[routeId] else { return }
        packs[routeId] = nil
        states[routeId] = Optional.none
        saved.removeAll { $0.routeId == routeId }
        MLNOfflineStorage.shared.removePack(pack, withCompletionHandler: nil)
    }

    // MARK: Bookkeeping

    private func adopt(_ all: [MLNOfflinePack]) {
        for pack in all {
            guard let id = Self.context(of: pack)?.routeId else { continue }
            packs[id] = pack
            pack.requestProgress()
        }
        refreshSaved()
    }

    private func update(_ pack: MLNOfflinePack) {
        guard let id = Self.context(of: pack)?.routeId else { return }
        packs[id] = pack
        let p = pack.progress
        switch pack.state {
        case .complete:
            states[id] = .ready(bytes: p.countOfBytesCompleted)
        case .active:
            let expected = max(p.countOfResourcesExpected, 1)
            states[id] = .downloading(Double(p.countOfResourcesCompleted) / Double(expected))
        case .inactive:
            // Paused with work left (the app went away mid-download): pick it up.
            if p.countOfResourcesCompleted < p.countOfResourcesExpected {
                pack.resume()
            } else if p.countOfResourcesExpected > 0 {
                states[id] = .ready(bytes: p.countOfBytesCompleted)
            }
        default:
            break
        }
        refreshSaved()
    }

    private func refreshSaved() {
        saved = packs.compactMap { id, pack in
            guard let ctx = Self.context(of: pack) else { return nil }
            return Saved(
                routeId: id,
                name: ctx.name,
                bytes: pack.progress.countOfBytesCompleted,
                complete: pack.state == .complete
            )
        }
        .sorted { $0.name < $1.name }
    }

    private static func context(of pack: MLNOfflinePack) -> Context? {
        try? JSONDecoder().decode(Context.self, from: pack.context)
    }

    // MARK: The corridor

    /// Squares `corridorM` either side of the route, one every ~200 m along
    /// it. A tile at zoom 14 is ~1 km across, so neighbouring squares overlap
    /// in the tiles they select and the corridor has no holes.
    nonisolated static func corridor(_ route: [CLLocationCoordinate2D]) -> MLNShape {
        var centres: [CLLocationCoordinate2D] = []
        var since = Double.infinity
        var previous: CLLocationCoordinate2D?
        for c in route {
            if let previous { since += RouteNav.haversineM(previous, c) }
            if since >= 200 {
                centres.append(c)
                since = 0
            }
            previous = c
        }
        if let last = route.last { centres.append(last) }

        let polygons: [MLNPolygon] = centres.map { c in
            let dLat = corridorM / 111_320
            let dLng = corridorM / (111_320 * max(cos(c.latitude * .pi / 180), 0.01))
            var ring = [
                CLLocationCoordinate2D(latitude: c.latitude - dLat, longitude: c.longitude - dLng),
                CLLocationCoordinate2D(latitude: c.latitude - dLat, longitude: c.longitude + dLng),
                CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLng),
                CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude - dLng),
                CLLocationCoordinate2D(latitude: c.latitude - dLat, longitude: c.longitude - dLng),
            ]
            return MLNPolygon(coordinates: &ring, count: UInt(ring.count))
        }
        return MLNMultiPolygon(polygons: polygons)
    }
}

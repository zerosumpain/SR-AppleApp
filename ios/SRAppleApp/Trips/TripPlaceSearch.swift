import MapKit
import SwiftUI

/// A place found on the trip map: by search, or as something to do near
/// where you are (John, 2026-10-27: "add a search function to find places on
/// the map … plot a route to that location", and "offer alternate
/// suggestions of things to do near where they are").
struct TripFoundPlace: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String?
    let at: TripLatLng
    let symbol: String

    init(_ item: MKMapItem) {
        let c = item.placemark.coordinate
        at = TripLatLng(lat: c.latitude, lng: c.longitude)
        name = item.name ?? "Place"
        detail = [item.placemark.thoroughfare, item.placemark.locality].compactMap { $0 }.joined(separator: ", ").nilIfEmpty
        symbol = TripFoundPlace.symbol(item.pointOfInterestCategory)
        id = "\(name)@\(String(format: "%.5f,%.5f", c.latitude, c.longitude))"
    }

    static func symbol(_ category: MKPointOfInterestCategory?) -> String {
        switch category {
        case .museum?: return "building.columns.fill"
        case .park?, .nationalPark?: return "tree.fill"
        case .cafe?: return "cup.and.saucer.fill"
        case .restaurant?, .bakery?, .foodMarket?: return "fork.knife"
        case .theater?, .movieTheater?: return "theatermasks.fill"
        case .beach?: return "beach.umbrella.fill"
        case .publicTransport?: return "tram.fill"
        case .store?: return "bag.fill"
        default: return "mappin"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Which way into the place sheet: a search, or what is near.
enum TripPlaceSheet: String, Identifiable {
    case search, nearby
    var id: String { rawValue }
}

/// A route to a found place: its line for the map, and how long it takes.
struct TripFoundRoute: Equatable {
    let line: [TripLatLng]
    let seconds: Double
    let metres: Double
    let mode: TravelMode
}

/// Searching, what is near, and routes — Apple Maps' places and directions,
/// which need a signal; the trip's own map and plan do not.
@MainActor
final class TripPlaceSearch: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [TripFoundPlace] = []
    @Published private(set) var nearby: [TripFoundPlace] = []
    @Published private(set) var searching = false
    @Published private(set) var message: String?
    private var running: Task<Void, Never>?

    /// The kinds of place worth suggesting to someone with time to fill.
    static let worthDoing: [MKPointOfInterestCategory] = [
        .museum, .park, .cafe, .restaurant, .bakery, .theater, .beach, .nationalPark, .foodMarket,
    ]

    /// Places matching the words, near `around` first.
    func search(around: TripLatLng?) {
        running?.cancel()
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.count >= 2 else { results = []; return }
        running = Task {
            // A beat after the last keystroke: one search per pause, not one per letter.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = words
            if let around { request.region = Self.region(around, metres: 8_000) }
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                results = Self.sorted(response.mapItems.map(TripFoundPlace.init), from: around)
                message = results.isEmpty ? "Nothing found for “\(words)”." : nil
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                message = "Search needs a signal."
            }
        }
    }

    /// Things to do within a walk of `at`, the nearest first.
    func loadNearby(_ at: TripLatLng) async {
        let request = MKLocalPointsOfInterestRequest(center: CLLocationCoordinate2D(latitude: at.lat, longitude: at.lng), radius: 900)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: Self.worthDoing)
        searching = true
        defer { searching = false }
        if let response = try? await MKLocalSearch(request: request).start() {
            nearby = Array(Self.sorted(response.mapItems.map(TripFoundPlace.init), from: at).prefix(12))
            message = nearby.isEmpty ? "Nothing listed within a walk of here." : nil
        } else {
            message = "Finding what is near needs a signal."
        }
    }

    /// A walk or a drive from `from` to the place, with its line.
    static func route(from: TripLatLng, to place: TripFoundPlace, mode: TravelMode) async -> TripFoundRoute? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: from.lat, longitude: from.lng)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: place.at.lat, longitude: place.at.lng)))
        request.transportType = mode == .drive ? .automobile : .walking
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }
        let polyline = route.polyline
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return TripFoundRoute(line: coords.map { TripLatLng(lat: $0.latitude, lng: $0.longitude) },
                              seconds: route.expectedTravelTime, metres: route.distance, mode: mode)
    }

    static func region(_ at: TripLatLng, metres: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: at.lat, longitude: at.lng), latitudinalMeters: metres, longitudinalMeters: metres)
    }

    static func sorted(_ places: [TripFoundPlace], from: TripLatLng?) -> [TripFoundPlace] {
        guard let from else { return places }
        return places.sorted { TripReplan.haversineM(from, $0.at) < TripReplan.haversineM(from, $1.at) }
    }

    /// "650 m", "2.4 km".
    static func distance(_ metres: Double) -> String {
        metres < 1000 ? "\(Int((metres / 50).rounded()) * 50) m" : String(format: "%.1f km", metres / 1000)
    }
}

/// Search the map, or — with nothing typed — what there is to do near you.
/// Picking one hands it back to the Day screen, which shows it on the map.
struct TripPlaceSearchSheet: View {
    /// Where the list is measured from: you, or the day's map.
    let around: TripLatLng?
    /// Opened as "things to do near me" from an off-plan prompt: the
    /// nearby list first, no keyboard.
    var nearbyFirst = false
    let pick: (TripFoundPlace) -> Void
    @StateObject private var search = TripPlaceSearch()
    @Environment(\.dismiss) private var dismiss
    /// The search field active on open — unless it opened on what is near.
    @State private var typing = false

    var body: some View {
        NavigationStack {
            List {
                if search.query.trimmingCharacters(in: .whitespaces).count >= 2 {
                    Section {
                        ForEach(search.results) { row($0) }
                    }
                } else {
                    Section {
                        ForEach(search.nearby) { row($0) }
                        if search.nearby.isEmpty && search.searching {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    } header: {
                        SRSectionLabel(text: "Things to do near you")
                    }
                }
                if let message = search.message {
                    Text(message).font(SR.Text.secondary()).foregroundStyle(SR.inkMuted)
                }
            }
            .listStyle(.insetGrouped)
            .srGround(.quiet)
            .searchable(text: $search.query, isPresented: $typing, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a place")
            .onChange(of: search.query) { _, _ in search.search(around: around) }
            .navigationTitle(nearbyFirst ? "Near you" : "Find a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task {
                if !nearbyFirst { typing = true }
                if let around { await search.loadNearby(around) }
            }
        }
        .accessibilityIdentifier("trip-place-search")
    }

    private func row(_ place: TripFoundPlace) -> some View {
        Button {
            SRHaptic.select()
            pick(place)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: place.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SR.accentDeep)
                    .frame(width: 34, height: 34)
                    .background(SR.accentDeep.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(SR.Text.title(15)).foregroundStyle(SR.ink).lineLimit(2)
                    if let detail = place.detail {
                        Text(detail).font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if let around {
                    Text(TripPlaceSearch.distance(TripReplan.haversineM(around, place.at)))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .srGlassRow()
        .accessibilityIdentifier("trip-place-\(place.name)")
    }
}

/// A found place over the map: what it is, how far, and the way there —
/// drawn on the map, walked with the app's own guidance, or handed to Maps.
struct TripFoundCard: View {
    let place: TripFoundPlace
    /// Where the route starts: you, or the stop you are at.
    let from: TripLatLng?
    @Binding var route: TripFoundRoute?
    let walk: (TripFoundRoute) -> Void
    let close: () -> Void
    @State private var mode: TravelMode = .walk
    @State private var routing = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: place.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(uiColor: .systemRed)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(SR.Text.title(16)).foregroundStyle(SR.ink).lineLimit(2)
                    Text(summary).font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { SRHaptic.select(); close() } label: {
                    Image(systemName: "xmark").font(SR.Text.label(13)).foregroundStyle(SR.inkSecondary).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("trip-found-close")
            }
            Picker("How", selection: $mode) {
                Text("Walk").tag(TravelMode.walk)
                Text("Drive").tag(TravelMode.drive)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("trip-found-mode")
            HStack(spacing: 8) {
                if let route, route.mode == .walk {
                    Button { SRHaptic.tap(); walk(route) } label: {
                        Label("Walk it", systemImage: "figure.walk").frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SR.accent)
                    .accessibilityIdentifier("trip-found-walk")
                } else if route == nil {
                    Button { SRHaptic.tap(); Task { await plot() } } label: {
                        Label(routing ? "Finding the way…" : "Show the route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SR.accent)
                    .disabled(routing || from == nil)
                    .accessibilityIdentifier("trip-found-route")
                }
                Button { SRHaptic.tap(); openInMaps() } label: {
                    Label("Maps", systemImage: "map").frame(maxWidth: route?.mode == .drive ? .infinity : nil, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("trip-found-maps")
            }
            .font(SR.Text.title(14))
        }
        .padding(14)
        .srGlassCard(.paper)
        .onChange(of: mode) { _, _ in
            guard route != nil else { return }
            route = nil
            Task { await plot() }
        }
        .onChange(of: place) { _, _ in route = nil }
        .accessibilityIdentifier("trip-found-card")
    }

    /// "650 m away · 9 min walk", once there is a route; the distance before.
    private var summary: String {
        if failed { return "No route found — try Maps" }
        if let route {
            let minutes = max(1, Int((route.seconds / 60).rounded()))
            return "\(TripPlaceSearch.distance(route.metres)) · \(minutes) min \(route.mode == .drive ? "drive" : "walk")"
        }
        let far = from.map { TripPlaceSearch.distance(TripReplan.haversineM($0, place.at)) + " away" }
        return [far, place.detail].compactMap { $0 }.joined(separator: " · ")
    }

    private func plot() async {
        guard let from, !routing else { return }
        routing = true
        defer { routing = false }
        route = await TripPlaceSearch.route(from: from, to: place, mode: mode)
        failed = route == nil
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: place.at.lat, longitude: place.at.lng)))
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: TripDirections.directionsMode(mode)])
    }
}

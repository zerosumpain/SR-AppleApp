import SwiftUI
import CoreLocation
import MapKit

/// Drop a pin where you are staying (or parked, or agreed to meet) and an
/// arrow points back to it from anywhere, with the distance and the walk.
///
/// GPS and the compass need no signal, so this is the one that still works
/// lost down a Trastevere side street with no data. The pin also carries its
/// address, looked up once when dropped, for the "take me here" card a taxi
/// driver can read.
///
/// Location is read only while this page is open, and the pins never leave
/// the phone.
struct TravelWayBackScreen: View {
    @StateObject private var compass = TravelCompass()
    @State private var pins: [TravelPin] = TravelPin.load()
    @State private var selectedId: UUID? = TravelPin.load().first?.id
    @State private var naming = false
    @State private var name = ""
    @State private var showing: TravelShowCard?

    private var selected: TravelPin? { pins.first { $0.id == selectedId } ?? pins.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                if let pin = selected {
                    pointer(pin)
                } else {
                    SRCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pin your hotel first")
                                .font(SR.Text.title(17))
                                .foregroundStyle(SR.ink)
                            Text("When you arrive, stand outside and drop a pin. From then on this page points back to it, with or without signal.")
                                .font(SR.Text.secondary(14))
                                .foregroundStyle(SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let problem = compass.problem {
                    Text(problem).font(SR.Text.secondary(14)).foregroundStyle(SR.error)
                }
                SRButton(title: "Drop a pin here", filled: selected == nil) {
                    name = pins.isEmpty ? "Hotel" : ""
                    naming = true
                }
                .disabled(compass.here == nil)
                .accessibilityIdentifier("travel-drop-pin")
                if !pins.isEmpty { pinList }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .navigationTitle("Way back")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { compass.start() }
        .onDisappear { compass.stop() }
        .alert("Name this pin", isPresented: $naming) {
            TextField("Hotel, car, meeting point…", text: $name)
            Button("Save") { drop() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $showing) { TravelShowSheet(card: $0) }
        .accessibilityIdentifier("travel-way-back")
    }

    // MARK: - The arrow

    private func pointer(_ pin: TravelPin) -> some View {
        let distance = compass.here.map { $0.distance(from: pin.location) }
        let bearing = compass.here.map { TravelCompass.bearing(from: $0.coordinate, to: pin.coordinate) }
        let turn = bearing.flatMap { b in compass.heading.map { b - $0 } }
        return SRCard {
            VStack(spacing: 14) {
                Text(pin.name)
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                ZStack {
                    Circle().strokeBorder(SR.line, lineWidth: 2)
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 96, weight: .bold))
                        .foregroundStyle(distance.map { $0 < 30 } == true ? SR.good : SR.accent)
                        .rotationEffect(.degrees(turn ?? 0))
                        .animation(.easeOut(duration: 0.25), value: turn ?? 0)
                        .opacity(turn == nil ? 0.25 : 1)
                }
                .frame(width: 200, height: 200)
                .accessibilityElement()
                .accessibilityLabel(spoken(distance: distance, turn: turn))
                if let distance {
                    Text(distance < 30 ? "You're here" : TravelCompass.describe(distance))
                        .font(SR.Text.figure(32))
                        .foregroundStyle(SR.ink)
                    Text(distance < 30 ? pin.address ?? "" : "about \(TravelCompass.walk(distance)) on foot as the crow flies")
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(SR.inkSecondary)
                } else {
                    Text("Finding you…").font(SR.Text.secondary(14)).foregroundStyle(SR.inkMuted)
                }
                if compass.heading == nil && compass.here != nil {
                    Text("No compass reading: hold the phone flat, away from metal.")
                        .font(SR.Text.secondary(12))
                        .foregroundStyle(SR.warn)
                }
                HStack(spacing: 10) {
                    SRButton(title: "Walk in Maps") { openInMaps(pin) }
                    SRButton(title: "Taxi card") {
                        showing = TravelShowCard(
                            big: "Per favore, mi porti a:\n\(pin.address ?? pin.coordinateText)",
                            small: "Please take me to: \(pin.name)",
                            speech: TravelLanguage.italian.speech
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func spoken(distance: CLLocationDistance?, turn: Double?) -> String {
        guard let distance else { return "Finding your position" }
        guard let turn else { return TravelCompass.describe(distance) + " away" }
        let t = (turn.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let way: String
        switch t {
        case ..<20, 340...: way = "straight ahead"
        case ..<160: way = "to your right"
        case ..<200: way = "behind you"
        default: way = "to your left"
        }
        return "\(TravelCompass.describe(distance)) away, \(way)"
    }

    private var pinList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "Your pins")
            ForEach(pins) { pin in
                Button {
                    SRHaptic.select()
                    selectedId = pin.id
                } label: {
                    HStack {
                        Image(systemName: pin.id == selected?.id ? "mappin.circle.fill" : "mappin.circle")
                            .foregroundStyle(SR.accent)
                            .font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pin.name).font(SR.Text.bodyMedium(16)).foregroundStyle(SR.ink)
                            Text(pin.address ?? pin.coordinateText)
                                .font(SR.Text.secondary(12))
                                .foregroundStyle(SR.inkMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SR.surface))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) { remove(pin) } label: { Label("Delete pin", systemImage: "trash") }
                }
            }
            Text("Touch and hold a pin to delete it.")
                .font(SR.Text.secondary(12))
                .foregroundStyle(SR.inkMuted)
        }
    }

    // MARK: - Pins

    private func drop() {
        guard let here = compass.here else { return }
        let label = name.trimmingCharacters(in: .whitespaces)
        let pin = TravelPin(name: label.isEmpty ? "Pin \(pins.count + 1)" : label, coordinate: here.coordinate)
        pins.insert(pin, at: 0)
        selectedId = pin.id
        TravelPin.save(pins)
        SRHaptic.ok()
        // The address is a nicety for the taxi card; with no signal the pin
        // keeps its coordinates and that is enough to point back.
        Task {
            if let mark = try? await CLGeocoder().reverseGeocodeLocation(here).first {
                var pin = pin
                pin.address = [mark.name, mark.postalCode.map { "\($0) \(mark.locality ?? "")" } ?? mark.locality]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                if let index = pins.firstIndex(where: { $0.id == pin.id }) {
                    pins[index] = pin
                    TravelPin.save(pins)
                }
            }
        }
    }

    private func remove(_ pin: TravelPin) {
        pins.removeAll { $0.id == pin.id }
        if selectedId == pin.id { selectedId = pins.first?.id }
        TravelPin.save(pins)
    }

    private func openInMaps(_ pin: TravelPin) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
        item.name = pin.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

struct TravelPin: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var address: String?

    init(name: String, coordinate: CLLocationCoordinate2D) {
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var location: CLLocation { .init(latitude: latitude, longitude: longitude) }
    var coordinateText: String { String(format: "%.5f, %.5f", latitude, longitude) }

    private static let key = "travel.pins.v1"

    static func load() -> [TravelPin] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([TravelPin].self, from: data)) ?? []
    }

    static func save(_ pins: [TravelPin]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(pins), forKey: key)
    }
}

/// Position and compass heading, only while the Way back page is open.
@MainActor
final class TravelCompass: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var here: CLLocation?
    /// Degrees from true north the top of the phone points.
    @Published private(set) var heading: Double?
    @Published private(set) var problem: String?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.headingFilter = 2
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            problem = "Location is off for SR. Turn it on in Settings → SR → Location to point the way back."
            return
        default: break
        }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            problem = nil
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        case .denied, .restricted:
            problem = "Location is off for SR. Turn it on in Settings → SR → Location to point the way back."
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last, last.horizontalAccuracy >= 0, last.horizontalAccuracy < 200 else { return }
        here = last
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { heading = nil; return }
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    /// Initial great-circle bearing, degrees clockwise from true north.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let θ = atan2(y, x) * 180 / .pi
        return (θ + 360).truncatingRemainder(dividingBy: 360)
    }

    static func describe(_ metres: CLLocationDistance) -> String {
        if metres < 1000 { return "\(Int((metres / 10).rounded()) * 10) m" }
        return String(format: "%.1f km", metres / 1000)
    }

    /// At 4.5 km/h, a family's pace — not a runner's.
    static func walk(_ metres: CLLocationDistance) -> String {
        let minutes = max(1, Int((metres / 75).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}

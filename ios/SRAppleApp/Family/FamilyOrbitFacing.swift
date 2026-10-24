import SwiftUI
import CoreLocation

// The Family tab's Orbit, turned to face the way the phone does.
//
// Home's tile asks "who is where" and is answered home-centred, north up,
// the same every time. The Family tab is where somebody goes to find a
// person, and there the useful picture is the one a person stands in: you in
// the middle, ahead at the top, Sam over your right shoulder. So this tab's
// Orbit turns with the phone, and a button beside it puts the old picture
// back for anybody who prefers it (remembered, like the Orbit/Map choice).
//
// The compass is the cheap part of location — the magnetometer, no GPS, no
// permission of its own — but it is still a sensor running, on an app that has
// had its battery and its heat looked at hard (see `LocationCollector`). So it
// runs only while this Orbit is on screen, turning, with the app in front,
// and stops the moment any of those ends.

/// Which way the phone points, for the turning Orbit only.
///
/// Its own `CLLocationManager`, apart from `LocationCollector`'s: that one is
/// the sharing pipeline and its gate, and heading updates on it would keep
/// alive a manager the gate works hard to put to sleep. This one never asks
/// for permission and never starts location updates: it only reads the fix
/// iOS already has, once, as a fallback centre.
@MainActor
final class DeviceHeadingStore: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    enum State: Equatable {
        /// Not running: off screen, in the background, or not turning.
        case off
        case running
        /// No magnetometer (the simulator, some iPads): north stays up.
        case unavailable
        /// Location is off for the app. A heading would still come, but the
        /// fix in the middle would be one the phone stopped updating.
        case denied
    }

    @Published private(set) var state: State = .off
    /// Radians from north, unwrapped: it keeps counting past a full turn so
    /// the disc never spins the long way (`FamilyOrbitMath.unwrap`). Nil
    /// until the first reading, and kept across a stop so a glance at
    /// Control Centre does not snap the disc back to north.
    @Published private(set) var turn: Double?
    /// The last fix iOS holds for this phone — the centre when the household
    /// view has none for you. Read, never requested.
    @Published private(set) var fix: GeoPoint?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        // Finer than three degrees is a disc that never stops trembling in a
        // hand, and a redraw for every tremble.
        manager.headingFilter = 3
        // The app is portrait only (Info.plist), so the top of the screen is
        // the top of the phone.
        manager.headingOrientation = .portrait
    }

    var denied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    /// The fix iOS already has, if the app may see it. Cheap: a property
    /// read, no GPS.
    func refreshFix() {
        guard !denied, let location = manager.location else { return }
        let next = GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        if next != fix { fix = next }
    }

    /// Start turning. Idempotent.
    func start() {
        guard state != .running else { return }
        guard CLLocationManager.headingAvailable() else { state = .unavailable; return }
        guard !denied else { state = .denied; return }
        state = .running
        manager.startUpdatingHeading()
    }

    /// Stop at once. Idempotent.
    func stop() {
        guard state != .off else { return }
        if state == .running { manager.stopUpdatingHeading() }
        state = .off
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // A negative accuracy is iOS saying the reading is not one.
        guard state == .running, newHeading.headingAccuracy >= 0 else { return }
        // True north when iOS knows where the phone is (it uses its last
        // fix); magnetic otherwise, which is a few degrees out in Britain and
        // still the right way to point.
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let next = FamilyOrbitMath.unwrap(degrees * .pi / 180, after: turn ?? 0)
        if let turn, abs(next - turn) < .pi / 180 { return }
        turn = next
    }

    /// The figure-of-eight calibration sheet is iOS's to show over a map app,
    /// not over a family picture somebody glanced at: an uncalibrated compass
    /// is a few degrees out, and the Orbit is drawn at eight-point accuracy.
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // `.headingFailure` is interference — a magnet, a car — and passes.
        guard (error as? CLError)?.code == .denied else { return }
        if state == .running { manager.stopUpdatingHeading() }
        state = .denied
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if denied, state == .running {
            manager.stopUpdatingHeading()
            state = .denied
        } else if !denied, state == .denied {
            // Back on in Settings: the screen's next sync starts it again.
            state = .off
        }
    }
}

/// The Orbit at the top of the Family tab: turning with the phone by
/// default, home-centred and north up at a tap.
///
/// Its own view so that it alone observes the compass: a heading arrives
/// several times a second while somebody turns, and the tab around it — the
/// cards, the ribbons, the list — must not redraw for each one.
struct FamilyFacingOrbit: View {
    let view: HouseholdView
    /// The home-centred model, which the tab already built to decide whether
    /// there is an Orbit to show at all.
    let classic: FamilyOrbitModel
    let colours: [String: Color]
    let live: Bool
    let openPerson: (String) -> Void
    /// Remembered, like the Orbit/Map choice: it is a way of looking.
    @AppStorage(FamilyFacingOrbit.key) private var facing = true
    static let key = "family-orbit-facing"
    @StateObject private var compass = DeviceHeadingStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = false
    /// Centred on you, when turning is on and this phone has a fix. Held,
    /// not computed in `body`: a heading redraws this view several times a
    /// second and the people have not moved in between.
    @State private var turning: FamilyOrbitModel?

    init(view: HouseholdView, classic: FamilyOrbitModel, colours: [String: Color], live: Bool,
         openPerson: @escaping (String) -> Void) {
        self.view = view
        self.classic = classic
        self.colours = colours
        self.live = live
        self.openPerson = openPerson
        // The first frame already centred on you, rather than home for a
        // frame and then a jump. The phone's own fix comes at `onAppear`.
        let facing = UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true
        _turning = State(initialValue: facing ? FamilyOrbitModel.makeFacing(view: view, watch: view.watch) : nil)
    }

    var body: some View {
        FamilyOrbitView(
            model: turning ?? classic, colours: colours, live: live,
            heading: turning != nil && compass.state != .unavailable && compass.state != .denied ? compass.turn : nil,
            openPerson: openPerson
        )
        .overlay(alignment: .topTrailing) { toggle }
        .overlay(alignment: .bottomLeading) {
            if let note {
                Text(note)
                    .font(SR.Text.mono(11))
                    .foregroundStyle(SR.inkMuted)
                    .frame(maxWidth: 130, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("family-orbit-note")
            }
        }
        .onAppear { onScreen = true; sync() }
        .onDisappear { onScreen = false; sync() }
        .onChange(of: scenePhase) { _, _ in sync() }
        .onChange(of: facing) { _, _ in sync() }
        // A refresh can bring (or take away) your own fix.
        .onChange(of: view) { _, _ in sync() }
        .onChange(of: compass.fix) { _, _ in sync() }
    }

    /// The turning model for what is known now; nil when not turning.
    private func rebuild() -> FamilyOrbitModel? {
        let next = facing ? FamilyOrbitModel.makeFacing(view: view, watch: view.watch, device: compass.fix) : nil
        if next != turning { turning = next }
        return next
    }

    /// The compass runs only for a turning Orbit somebody can see.
    private func sync() {
        if onScreen && facing && scenePhase == .active { compass.refreshFix() }
        let next = rebuild()
        if onScreen && facing && scenePhase == .active && next != nil {
            compass.start()
        } else {
            compass.stop()
        }
    }

    /// Why the picture is not turning, quietly, when it was asked to.
    private var note: String? {
        guard facing else { return nil }
        guard turning != nil else { return "No fix for you yet: home in the middle, north up" }
        switch compass.state {
        case .unavailable: return "No compass here: north is up"
        case .denied: return "Location is off: north is up"
        case .off, .running: return nil
        }
    }

    /// Shows where a tap goes, like the map's look button.
    private var toggle: some View {
        Button {
            SRHaptic.select()
            facing.toggle()
        } label: {
            Image(systemName: facing ? "house" : "location.north.line.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SR.ink)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .srGlass(.paper, in: Circle(), interactive: true)
        .accessibilityLabel(facing ? "Show home in the middle, north up" : "Turn with the phone")
        .accessibilityIdentifier("family-orbit-facing")
    }
}

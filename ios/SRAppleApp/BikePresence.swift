import CoreBluetooth
import Foundation

/// Whether the owner's e-bike is connected to this phone right now.
///
/// The bike (an Avinox drive) talks only to its own app, over a link iOS has
/// already made. iOS shares one Bluetooth connection between every app on the
/// phone, so this app can SEE that link without ever opening one of its own:
/// `retrieveConnectedPeripherals` lists what the system is connected to that
/// offers a named service. That is the whole of the feature — a yes or no,
/// stamped on each location fix as `bike: true`, so /health can tell a ride
/// from a drive. Nothing here connects, reads a characteristic or writes to the
/// bike, and nothing ever should: the link is the motor's, not ours.
///
/// The consequence to remember: if the Avinox app is not holding the link
/// during a ride, the bike is not connected and the ride is not marked. That is
/// what the field test in `docs/BIKE.md` exists to find out.
@MainActor final class BikePresence: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate {
    static let shared = BikePresence()

    /// The bike this phone was told about. `id` is iOS's identifier for the
    /// peripheral, stable on this phone and meaningless on any other — so it
    /// lives in this phone's defaults and never leaves it.
    struct Bike: Codable, Equatable {
        var id: UUID
        var name: String
        /// The services it was found under, which are the ones it must be
        /// looked for under again: iOS lists a connected peripheral only by a
        /// service it offers.
        var services: [String]
    }

    /// Something connected to the phone that could be the bike.
    struct Candidate: Identifiable, Equatable {
        var id: UUID
        var name: String
    }

    /// Device Information and Battery: the two standard services almost every
    /// Bluetooth controller exposes. Generic Access is hidden from apps by iOS,
    /// so it cannot be the net. A bike that offers neither is found by adding
    /// its own service, which the field test reads off nRF Connect.
    static let standardServices = ["180A", "180F"]
    private static let key = "sr.bike"
    /// How long one answer stands. Close tracking records about once a second,
    /// and the connection does not change that fast.
    private static let answerFor: TimeInterval = 10

    @Published private(set) var bike: Bike?
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var searched = false

    private var central: CBCentralManager?
    private var cached: (at: Date, connected: Bool)?
    private var searchWhenOn: [String]?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            bike = try? JSONDecoder().decode(Bike.self, from: data)
        }
        super.init()
    }

    /// Bluetooth permission, as iOS last answered it. Read without creating a
    /// manager, which is the thing that would ask.
    var authorization: CBManagerAuthorization { CBManager.authorization }

    /// On launch, foreground or background. Starts the manager only when a
    /// bike is set up AND permission was already given — creating one before
    /// that is what raises the permission sheet, and iOS never shows a sheet
    /// to an app woken in the background by a location event (the same trap
    /// as Core Motion's).
    func resume() {
        guard bike != nil, CBManager.authorization == .allowedAlways else { return }
        ensureCentral()
    }

    /// `true` when the bike is connected now; `nil` when it is not, when no
    /// bike is set up, or when Bluetooth cannot say. Never `false`: the fix
    /// carries the field only when it is a statement, so a phone with no bike
    /// uploads exactly what it did before.
    ///
    /// `fresh` skips the ten-second answer, for the settings screen's button.
    func connectedNow(at now: Date = Date(), fresh: Bool = false) -> Bool? {
        guard let bike, let central, central.state == .poweredOn else { return nil }
        if !fresh, let cached, now.timeIntervalSince(cached.at) < Self.answerFor { return cached.connected ? true : nil }
        let services = bike.services.compactMap(Self.uuid)
        let connected = Self.contains(central.retrieveConnectedPeripherals(withServices: services).map(\.identifier), bike.id)
        cached = (now, connected)
        return connected ? true : nil
    }

    /// Look for what is connected now. The first call is the one that asks
    /// for Bluetooth permission, so it must come from a button on screen.
    /// `extra` is a service UUID typed by hand, for a bike that offers neither
    /// standard service.
    func search(extra: String? = nil) {
        let services = Self.services(extra: extra)
        ensureCentral()
        guard let central, central.state == .poweredOn else {
            searchWhenOn = services
            return
        }
        candidates = central.retrieveConnectedPeripherals(withServices: services.compactMap(Self.uuid))
            .map { Candidate(id: $0.identifier, name: $0.name ?? "Unnamed device") }
        searched = true
    }

    func choose(_ candidate: Candidate, extra: String? = nil) {
        save(Bike(id: candidate.id, name: candidate.name, services: Self.services(extra: extra)))
    }

    func forget() {
        save(nil)
        candidates = []
        searched = false
    }

    // MARK: - Pure, for the tests

    static func contains(_ connected: [UUID], _ bike: UUID) -> Bool { connected.contains(bike) }

    /// The standard services plus a hand-typed one, if it parses.
    static func services(extra: String?) -> [String] {
        let typed = extra?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        guard !typed.isEmpty, uuid(typed) != nil, !standardServices.contains(typed) else { return standardServices }
        return standardServices + [typed]
    }

    /// A 16-bit short form (`180A`) or a full 128-bit UUID; anything else is
    /// refused here rather than handed to `CBUUID(string:)`, which traps on it.
    static func uuid(_ text: String) -> CBUUID? {
        let short = text.range(of: "^[0-9A-Fa-f]{4}$", options: .regularExpression) != nil
        guard short || UUID(uuidString: text) != nil else { return nil }
        return CBUUID(string: text)
    }

    // MARK: - Private

    private func ensureCentral() {
        guard central == nil else { return }
        // No power alert: a phone with Bluetooth off should go on recording
        // locations without a system dialog about a bike.
        central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    private func save(_ bike: Bike?) {
        self.bike = bike
        cached = nil
        if let bike, let data = try? JSONEncoder().encode(bike) { defaults.set(data, forKey: Self.key) }
        else { defaults.removeObject(forKey: Self.key) }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        cached = nil
        if central.state == .poweredOn, let services = searchWhenOn {
            searchWhenOn = nil
            candidates = central.retrieveConnectedPeripherals(withServices: services.compactMap(Self.uuid))
                .map { Candidate(id: $0.identifier, name: $0.name ?? "Unnamed device") }
            searched = true
        }
    }
}

import SwiftUI
import CoreLocation

/// Hold my location — the owner's alone (John, 2026-10-21).
///
/// For a stretch the owner chooses, this phone stops sending where it is, and
/// the site shows everyone else the owner standing still at a place he picked,
/// seen moments ago, as if nothing had changed. Nothing on another phone says
/// so: there is no flag in their view, no "paused", no stale age (SR-Main's
/// `location-hold`). Only this phone knows, and says so plainly here and on
/// the Family tab.
///
/// The order matters. The site is told FIRST and the phone pauses only once it
/// has agreed: a phone that went quiet without the site holding the place
/// would show the family an old pin going stale — the opposite of the point.
/// Ending is the other way round: the phone resumes at once, and the site is
/// told. The hold ends by itself at `until` on both sides, so a failed "end"
/// costs nothing past that time.
struct LocationHold: Codable, Equatable {
    let lat: Double
    let lon: Double
    let label: String
    let since: String
    let until: String

    var untilDate: Date? { parseTimestamp(until) }

    func isActive(now: Date = Date()) -> Bool { untilDate.map { $0 > now } ?? false }

    /// The hold this phone is keeping, if any — read straight from defaults
    /// so the location collector can ask on every fix without the main actor.
    static func current(now: Date = Date(), defaults: UserDefaults = .standard) -> LocationHold? {
        guard let data = defaults.data(forKey: key),
              let hold = try? JSONDecoder().decode(LocationHold.self, from: data),
              hold.isActive(now: now) else { return nil }
        return hold
    }

    static let key = "location-hold"

    /// How long a hold may be asked for: the site refuses past seven days.
    static let longest: TimeInterval = 7 * 86_400

    /// "Held at Home until 17:30", "… until Thu 08:00".
    func line(now: Date = Date()) -> String {
        guard let end = untilDate else { return "Held at \(label)" }
        let sameDay = Calendar.current.isDate(end, inSameDayAs: now)
        let time = end.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        let day = sameDay ? "" : end.formatted(.dateTime.weekday(.abbreviated)) + " "
        return "Held at \(label) until \(day)\(time)"
    }
}

/// The stretches offered, and when each ends from `now`.
enum LocationHoldLength: String, CaseIterable, Identifiable {
    case halfHour, hour, twoHours, fourHours, tomorrowMorning

    var id: String { rawValue }

    var label: String {
        switch self {
        case .halfHour: return "30 minutes"
        case .hour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        case .tomorrowMorning: return "Until 8am"
        }
    }

    /// When it ends. "Until 8am" is the next 08:00 — tomorrow's, after 8am today.
    func end(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .halfHour: return now.addingTimeInterval(30 * 60)
        case .hour: return now.addingTimeInterval(3600)
        case .twoHours: return now.addingTimeInterval(2 * 3600)
        case .fourHours: return now.addingTimeInterval(4 * 3600)
        case .tomorrowMorning:
            let today = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
            return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
    }
}

@MainActor
final class LocationHoldStore: ObservableObject {
    static let shared = LocationHoldStore()
    static let path = "api/native/family/hold"

    @Published private(set) var hold: LocationHold?
    @Published private(set) var busy = false
    @Published var message: String?
    private var expiry: Task<Void, Never>?

    private init() {
        hold = LocationHold.current()
        scheduleExpiry()
    }

    /// Whether this phone may offer it at all: the REAL owner, not while
    /// viewing the app as somebody, with the site credential the hold lives on.
    /// The showcase draws it so CI can photograph the screen.
    static var offered: Bool {
        let access = AccessStore.shared
        guard access.viewingAs == nil, SiteClient.shared.isPaired else { return false }
        return access.isRealOwner || (SRDemo.isShowcase && access.current.owner)
    }

    private struct Answer: Decodable { let hold: LocationHold? }
    private struct Ask: Encodable { let lat: Double; let lon: Double; let label: String; let until: String }

    /// What the site holds — the source of truth for what the family sees.
    func refresh() async {
        guard Self.offered else { return }
        do {
            let answer: Answer = try await SiteClient.shared.send(Self.path)
            adopt(answer.hold)
        } catch {
            // Unreadable: keep what this phone believes; it ends by itself.
        }
    }

    /// Hold at a point until `until`. The site first; the phone only once it agreed.
    func start(at coordinate: CLLocationCoordinate2D, label: String, until: Date) async -> Bool {
        guard Self.offered, !busy else { return false }
        busy = true
        defer { busy = false }
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        do {
            let body = try JSONEncoder().encode(Ask(lat: coordinate.latitude, lon: coordinate.longitude,
                                                    label: String(label.prefix(60)), until: format.string(from: until)))
            let answer: Answer = try await SiteClient.shared.send(Self.path, method: "PUT", body: body)
            guard let held = answer.hold else {
                message = "The site did not take the hold."
                return false
            }
            adopt(held)
            message = nil
            SRHaptic.ok()
            return true
        } catch {
            SRHaptic.bad()
            if case .status(_, let text)? = error as? SiteError, !text.isEmpty {
                message = text
            } else {
                message = "The hold did not start. Your location is still shared as normal."
            }
            return false
        }
    }

    /// Back to normal: the phone at once, then the site.
    func end() async {
        adopt(nil)
        busy = true
        defer { busy = false }
        do {
            _ = try await SiteClient.shared.call(Self.path, method: "DELETE")
            message = nil
        } catch {
            message = "This phone is sharing again; the site keeps the held place until it ends by itself."
        }
    }

    private func adopt(_ next: LocationHold?) {
        let live = next.flatMap { $0.isActive() ? $0 : nil }
        hold = live
        if let live, let data = try? JSONEncoder().encode(live) {
            UserDefaults.standard.set(data, forKey: LocationHold.key)
        } else {
            UserDefaults.standard.removeObject(forKey: LocationHold.key)
        }
        scheduleExpiry()
    }

    /// Clear the hold the moment it runs out, so the screens stop saying it.
    private func scheduleExpiry() {
        expiry?.cancel()
        guard let end = hold?.untilDate else { return }
        expiry = Task { @MainActor [weak self] in
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            self?.adopt(nil)
        }
    }
}

/// Settings → Hold my location.
struct LocationHoldScreen: View {
    @ObservedObject private var store = LocationHoldStore.shared
    @State private var place: String = LocationHoldScreen.here
    @State private var length: LocationHoldLength = .hour
    @State private var custom = false
    @State private var customEnd = Date().addingTimeInterval(3 * 3600)

    static let here = "here"

    /// Where it can be held: here, or a family place with a centre.
    private var places: [FamilyFavourite] {
        FamilyStore.current?.view.map(FamilyFavourites.make) ?? []
    }

    var body: some View {
        List {
            Section {
                Text("For as long as you choose, this iPhone stops sending where you are. Everyone else in the family sees you standing still at the place you pick, seen moments ago. Nothing on their phones says it is held — only this phone knows.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .srBareRow()
            }

            if let hold = store.hold {
                Section {
                    SRRow(title: hold.line(), subtitle: "Your real location is not being shared", icon: "location.slash.fill", tone: SR.warn)
                        .srGlassRow()
                        .accessibilityIdentifier("location-hold-active")
                    Button(role: .destructive) {
                        Task { await store.end() }
                    } label: {
                        Text("End the hold now").frame(maxWidth: .infinity)
                    }
                    .disabled(store.busy)
                    .srGlassRow()
                    .accessibilityIdentifier("location-hold-end")
                } header: {
                    SRSectionLabel(text: "Held now")
                }
            } else {
                Section {
                    Picker("Where", selection: $place) {
                        Text("Where I am now").tag(Self.here)
                        ForEach(places) { Text($0.name).tag($0.id) }
                    }
                    .srGlassRow()
                    .accessibilityIdentifier("location-hold-place")
                } header: {
                    SRSectionLabel(text: "Show me at")
                }

                Section {
                    Picker("For", selection: $length) {
                        ForEach(LocationHoldLength.allCases) { Text($0.label).tag($0) }
                    }
                    .disabled(custom)
                    .srGlassRow()
                    Toggle("Until a time I choose", isOn: $custom).srGlassRow()
                    if custom {
                        DatePicker("Ends", selection: $customEnd,
                                   in: Date().addingTimeInterval(5 * 60)...Date().addingTimeInterval(LocationHold.longest))
                            .srGlassRow()
                    }
                } header: {
                    SRSectionLabel(text: "For how long")
                }

                Section {
                    Button {
                        Task { await start() }
                    } label: {
                        HStack {
                            Spacer()
                            if store.busy { ProgressView() } else { Text("Hold my location") }
                            Spacer()
                        }
                    }
                    .disabled(store.busy)
                    .srGlassRow()
                    .accessibilityIdentifier("location-hold-start")
                }
            }

            if let message = store.message {
                Section {
                    Text(message).font(SR.Text.secondary()).foregroundStyle(SR.error).srBareRow()
                }
            }
        }
        .listStyle(.insetGrouped)
        .srPaper()
        .navigationTitle("Hold my location")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.refresh() }
        .accessibilityIdentifier("location-hold-screen")
    }

    private func start() async {
        let end = custom ? customEnd : length.end()
        if place == Self.here {
            // The last fix iOS has, without asking for a new one: where the
            // phone already knows it is.
            guard let here = CLLocationManager().location?.coordinate else {
                store.message = "This iPhone has no recent position. Pick a place instead."
                return
            }
            _ = await store.start(at: here, label: "Here", until: end)
        } else if let chosen = places.first(where: { $0.id == place }), let centre = chosen.coordinates.first {
            _ = await store.start(at: centre, label: chosen.name, until: end)
        }
    }
}

/// The owner's own reminder on the Family tab: the family is seeing a held place.
struct LocationHoldBanner: View {
    @ObservedObject private var store = LocationHoldStore.shared
    @EnvironmentObject private var router: Router

    var body: some View {
        if let hold = store.hold, LocationHoldStore.offered {
            Button {
                SRHaptic.tap()
                router.openSettings(.hold)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "location.slash.fill").foregroundStyle(SR.warn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hold.line()).font(SR.Text.title(14)).foregroundStyle(SR.ink)
                        Text("Only you can see this. The family sees you there.")
                            .font(SR.Text.secondary(12)).foregroundStyle(SR.inkMuted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(SR.inkGhost)
                }
                .padding(12)
                .srGlassCard(.paper)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("location-hold-banner")
        }
    }
}

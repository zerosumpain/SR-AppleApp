import Foundation
import CoreLocation
import UIKit
import UserNotifications

/// Notices when someone has gone off the plan, and offers a way back on.
///
/// Battery first: no continuous GPS. While a trip day is running this
/// listens to the two wake-ups iOS gives almost for free — significant
/// location changes and visits — plus the stop geofences (`TripArrivals`)
/// and a single fix whenever the Day screen comes up. Following a walk has
/// its own GPS; nothing here asks for more.
///
/// Each condition (`TripOffPlanRules`) is raised ONCE per stop or place per
/// day, dismissible with "I'm fine". When it fires with the app in the
/// background it becomes a local notification — time-sensitive only when a
/// booked slot is at risk.
@MainActor
final class TripOffPlan: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = TripOffPlan()

    struct Prompt: Identifiable, Equatable {
        let id: String
        let tripId: String
        let date: String
        var observation: Observation
        var headline: String
        var slotAtRisk: Bool
    }

    /// One way back on: a re-plan of today (offline, or the server's day
    /// options) or of the whole trip (the server's, or a local pull-forward).
    enum Choice: Identifiable, Equatable {
        case day(ReplanOption)
        case trip(TripReplanOption)

        var id: String {
            switch self {
            case .day(let o): return "day:\(o.id)"
            case .trip(let o): return "trip:\(o.id)"
            }
        }

        var label: String {
            switch self {
            case .day(let o): return o.label
            case .trip(let o): return o.label
            }
        }

        var detail: String {
            switch self {
            case .day(let o): return TripReplanning.endsLine(o)
            case .trip(let o): return o.explanation
            }
        }
    }

    @Published private(set) var prompt: Prompt?
    @Published private(set) var narrative: String?
    @Published private(set) var choices: [Choice] = []
    @Published private(set) var loading = false
    /// Where the options came from, said under them.
    @Published private(set) var offline = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var fixes: [CLLocation] = []
    private var visitSince: (CLLocation, Date)?
    private var armed = false
    private var started = false
    private static let raisedKey = "trips.offplan.raised"
    private var raised: Set<String> = Set(UserDefaults.standard.stringArray(forKey: raisedKey) ?? [])

    private override init() {
        super.init()
    }

    /// At launch, before any scene: a significant change or a visit can
    /// relaunch the app in the background.
    func start() {
        guard !started else { return }
        started = true
        manager.delegate = self
        if SRDemo.isOn {
            TripDemo.seedOffPlan(into: self)
            return
        }
        refresh()
    }

    /// Arm or disarm for the running day, then look.
    func refresh(now: Date = Date()) {
        guard started, !SRDemo.isOn else { return }
        let running = runningDay(now: now)
        if running != nil && !armed {
            armed = true
            manager.startMonitoringSignificantLocationChanges()
            manager.startMonitoringVisits()
        } else if running == nil && armed {
            armed = false
            manager.stopMonitoringSignificantLocationChanges()
            manager.stopMonitoringVisits()
            fixes = []
            visitSince = nil
        }
        check(now: now)
    }

    /// One fix, when the Day screen comes up: cheap, and the freshest
    /// picture there will be.
    func requestFix() {
        guard armed, !SRDemo.isOn else { return }
        manager.requestLocation()
    }

    func dismiss() {
        prompt = nil
        choices = []
        narrative = nil
    }

    func apply(_ choice: Choice) {
        guard let prompt else { return }
        switch choice {
        case .day(let option): TripStore.shared.apply(option, tripId: prompt.tripId)
        case .trip(let option): TripStore.shared.apply(option, tripId: prompt.tripId)
        }
        dismiss()
    }

    // MARK: Looking

    private func runningDay(now: Date) -> (tripId: String, date: String, day: PlannedDay, clock: TripClock)? {
        let store = TripStore.shared
        guard let running = store.running(now: now),
              let day = store.day(running.bundle.trip.id, running.date),
              let clock = store.clock(running.bundle.trip.id),
              TripLive.isOn(day: day, clock: clock, now: now) else { return nil }
        return (running.bundle.trip.id, running.date, day, clock)
    }

    func check(now: Date = Date()) {
        guard started, !SRDemo.isOn, let r = runningDay(now: now) else { return }
        let store = TripStore.shared
        // v5: its options change the plan, which only the creator and the
        // parents may; anyone else is not prompted.
        guard store.bundles[r.tripId]?.can.canEdit != false else { return }
        guard let progress = store.progress(r.tripId, r.date, now: now) else { return }
        let nowMin = r.clock.minutes(now)
        let recent = fixes
            .filter { r.clock.localDate($0.timestamp) == r.date && now.timeIntervalSince($0.timestamp) < 30 * 60 }
            .map { TripOffPlanRules.Fix(at: TripLatLng(lat: $0.coordinate.latitude, lng: $0.coordinate.longitude), minute: r.clock.minutes($0.timestamp)) }
        var dwell: TripOffPlanRules.Dwell?
        if let visit = visitSince, r.clock.localDate(visit.1) == r.date {
            dwell = TripOffPlanRules.Dwell(
                at: TripLatLng(lat: visit.0.coordinate.latitude, lng: visit.0.coordinate.longitude),
                sinceMin: r.clock.minutes(visit.1)
            )
        }
        let findings = TripOffPlanRules.detect(
            day: r.day, marks: store.marks(r.tripId), progress: progress, nowMin: nowMin,
            fixes: recent, dwell: dwell, clock: r.clock
        )
        guard prompt == nil,
              let finding = findings.first(where: { !raised.contains("\(r.tripId)|\(r.date)|\($0.key)") }) else { return }
        let key = "\(r.tripId)|\(r.date)|\(finding.key)"
        raised.insert(key)
        // Today's only: yesterday's keys are not needed again.
        let today = raised.filter { $0.contains("|\(r.date)|") }
        UserDefaults.standard.set(Array(today), forKey: Self.raisedKey)

        Task {
            var observation = finding.observation
            if observation.kind == .unplannedStop, let place = observation.place {
                observation.place?.name = await placeName(place.location)
            }
            raise(Prompt(
                id: key, tripId: r.tripId, date: r.date, observation: observation,
                headline: TripOffPlanRules.headline(observation, day: r.day, nowMin: nowMin),
                slotAtRisk: finding.slotAtRisk
            ))
        }
    }

    /// Show it (and say it, if nobody is looking), then fetch the options.
    func raise(_ next: Prompt) {
        prompt = next
        narrative = nil
        choices = []
        if UIApplication.shared.applicationState != .active && !SRDemo.isOn { notify(next) }
        Task { await loadChoices() }
    }

    /// The server's trip options and narrative when there is signal; the
    /// local solver's day options and a pull-forward when not.
    func loadChoices() async {
        let store = TripStore.shared
        guard let prompt, let bundle = store.bundles[prompt.tripId], let clock = store.clock(prompt.tripId),
              let progress = store.progress(prompt.tripId, prompt.date) else { return }
        loading = true
        defer { loading = false }
        let position = prompt.observation.place?.location ?? TripPosition.latest
        let nowMin = clock.minutes(Date())
        if TripNetwork.shared.online || SRDemo.isOn {
            let body = TripReplanBody(
                date: prompt.date, nowMin: nowMin.rounded(), position: position, atStopId: progress.atStopId,
                doneStopIds: progress.doneStopIds, scope: "trip", observation: prompt.observation
            )
            if let reply = try? await TripsAPI.replanReply(body, trip: prompt.tripId), self.prompt?.id == prompt.id {
                narrative = reply.narrative
                let trip = (reply.tripOptions ?? []).prefix(3).map(Choice.trip)
                choices = trip.isEmpty ? Array(reply.options.prefix(3).map(Choice.day)) : Array(trip)
                offline = false
                if !choices.isEmpty { return }
            }
        }
        // Offline (or the server had nothing): the phone's own.
        offline = true
        var local: [Choice] = []
        if let position, let pull = TripPullForward.option(TripPullForward.Input(
            bundle: bundle, dayFor: { store.day(prompt.tripId, $0) }, today: prompt.date,
            progress: progress, position: position, nowMin: nowMin
        )) {
            local.append(.trip(pull))
        }
        let request = TripOptionsRequest(tripId: prompt.tripId, date: prompt.date, reason: .behind, nowMin: nil, position: position)
        local += TripReplanning.localOptions(request, store: store).map(Choice.day)
        choices = Array(local.prefix(3))
    }

    /// Demo: a prompt and its choices, as given, with no location at all.
    func adoptDemo(_ prompt: Prompt, narrative: String, choices: [Choice]) {
        self.prompt = prompt
        self.narrative = narrative
        self.choices = choices
        offline = false
    }

    private func placeName(_ at: TripLatLng) async -> String? {
        let placemarks = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: at.lat, longitude: at.lng))
        guard let mark = placemarks?.first else { return nil }
        return mark.areasOfInterest?.first ?? mark.name ?? mark.thoroughfare
    }

    private func notify(_ prompt: Prompt) {
        let content = UNMutableNotificationContent()
        content.title = prompt.slotAtRisk ? "A booking is at risk" : "Off the plan?"
        content.body = prompt.headline + ". Open the day for ways to carry on."
        content.sound = prompt.slotAtRisk ? .default : nil
        content.threadIdentifier = "trip"
        content.userInfo = ["category": TripLink.category, "tripId": prompt.tripId, "date": prompt.date]
        // Time-sensitive only when a booked slot would be missed: everything
        // else can wait for the next glance.
        content.interruptionLevel = prompt.observation.kind == .behind && prompt.slotAtRisk ? .timeSensitive : .active
        let request = UNNotificationRequest(identifier: "trip-offplan-\(prompt.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: Location

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let good = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 200 }
        Task { @MainActor in
            self.fixes = Array((self.fixes + good).filter { Date().timeIntervalSince($0.timestamp) < 40 * 60 }.suffix(60))
            TripTrail.shared.add(good)
            self.check()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let location = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        let arrived = visit.arrivalDate
        let departed = visit.departureDate != Date.distantFuture
        Task { @MainActor in
            self.visitSince = departed || arrived == Date.distantPast ? nil : (location, arrived)
            self.check()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

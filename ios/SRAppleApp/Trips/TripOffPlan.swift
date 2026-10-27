import Foundation
import CoreLocation
import UIKit
import UserNotifications

/// Notices when someone has gone off the plan, and offers a way back on.
///
/// While a trip day is running this listens to the wake-ups iOS gives almost
/// for free — significant location changes and visits — plus the stop
/// geofences (`TripArrivals`) and a single fix whenever the Day screen comes
/// up. Since 2026-10-27 (John: "constantly monitor — 10 minutely location
/// pings") it also keeps a LOW-POWER location session for the day — a
/// hundred metres, nothing until fifty metres moved, so mostly Wi-Fi and
/// cell rather than GPS — and every ten minutes asks `TripKeepUp` whether
/// the person can still keep to the plan: re-timed quietly while they can,
/// asked when they cannot. "Stop prompting the plan today" ends all of it
/// for the day.
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
    /// Days the person asked to stop being prompted about, "<trip>|<date>".
    private static let pausedKey = "trips.offplan.paused"
    @Published private(set) var paused: Set<String> = Set(UserDefaults.standard.stringArray(forKey: pausedKey) ?? [])
    /// "Plan moved 20 min later so you can keep to it", for the Day screen
    /// to say once and clear.
    @Published var retimed: String?
    private var keepUpTimer: Timer?
    private var lastKeepUp: Date?
    /// The day's fixes, handed on to the family trail (the app delegate sets
    /// it to `LocationCollector.recordTripFixes`).
    var relay: (([CLLocation]) -> Void)?

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

    /// Arm or disarm for the running day, then look. A day the person
    /// paused is not watched at all.
    func refresh(now: Date = Date()) {
        guard started, !SRDemo.isOn else { return }
        let watching = runningDay(now: now).map { !isPaused($0.tripId, $0.date) } ?? false
        if watching && !armed {
            armed = true
            manager.startMonitoringSignificantLocationChanges()
            manager.startMonitoringVisits()
            startKeepingUp()
        } else if !watching && armed {
            armed = false
            manager.stopMonitoringSignificantLocationChanges()
            manager.stopMonitoringVisits()
            stopKeepingUp()
            fixes = []
            visitSince = nil
        }
        check(now: now)
    }

    // MARK: Keeping up

    /// The day's low-power session and the ten-minute look. The session is
    /// what keeps the app alive in the background for the timer; a hundred
    /// metres and a fifty-metre filter keep it off GPS most of the time.
    private func startKeepingUp() {
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
        manager.startUpdatingLocation()
        keepUpTimer?.invalidate()
        keepUpTimer = Timer.scheduledTimer(withTimeInterval: TripKeepUp.everySec, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.keepUp() }
        }
    }

    private func stopKeepingUp() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        keepUpTimer?.invalidate()
        keepUpTimer = nil
        lastKeepUp = nil
    }

    /// Ten minutes on: where the person is against the plan. Re-timed without
    /// asking while the plan still holds; asked — with what is near and the
    /// way to stop — once it cannot. Only for whoever may change the plan.
    func keepUp(now: Date = Date()) {
        guard started, !SRDemo.isOn, let r = runningDay(now: now), !isPaused(r.tripId, r.date) else { return }
        let store = TripStore.shared
        guard let bundle = store.bundles[r.tripId], bundle.can.canEdit != false else { return }
        lastKeepUp = now
        guard let fix = fixes.last, now.timeIntervalSince(fix.timestamp) < 15 * 60 else {
            // Nothing recent to go on: one fix, and the look runs again on it.
            manager.requestLocation()
            return
        }
        let nowMin = r.clock.minutes(now)
        let marks = TripProgress.telling(day: r.day, marks: store.marks(r.tripId), nowMin: nowMin)
        let progress = TripProgress.of(day: r.day, marks: marks, nowMin: nowMin, clock: r.clock)
        let position = TripLatLng(lat: fix.coordinate.latitude, lng: fix.coordinate.longitude)
        let slip = TripKeepUp.slip(day: r.day, progress: progress, position: position, nowMin: nowMin)
        let verdict = TripKeepUp.verdict(day: r.day, slip: slip, done: Set(progress.doneStopIds)) {
            TripReplan.replanDay(TripReplan.Input(
                context: TripReplanning.context(bundle, date: r.date), day: r.day, nowMin: nowMin, position: position,
                atStopId: progress.atStopId, doneStopIds: progress.doneStopIds
            ))
        }
        switch verdict {
        case .onPlan:
            return
        case .retime(let option, _):
            store.apply(option, tripId: r.tripId)
            TripLive.shared.refresh(now: now)
            let line = TripKeepUp.retimedLine(option)
            retimed = line
            if UIApplication.shared.applicationState != .active { notifyQuietly(line, tripId: r.tripId, date: r.date) }
        case .cannotKeep(let slipMin):
            guard prompt == nil, let index = progress.retimeFrom ?? progress.currentIndex, index < r.day.stops.count else { return }
            let stop = r.day.stops[index]
            let key = "\(r.tripId)|\(r.date)|keep:\(stop.id)"
            guard !raised.contains(key) else { return }
            raised.insert(key)
            UserDefaults.standard.set(Array(raised.filter { $0.contains("|\(r.date)|") }), forKey: Self.raisedKey)
            raise(Prompt(
                id: key, tripId: r.tripId, date: r.date,
                observation: Observation(kind: .behind, place: Observation.Place(name: nil, location: position),
                                         sinceMin: nowMin - slipMin, motion: "unknown", stopId: stop.id),
                headline: TripKeepUp.cannotKeepLine(slipMin: slipMin),
                slotAtRisk: TripOffPlanRules.lockedAhead(r.day, from: index)
            ))
        }
    }

    /// A re-time said where it will be seen later, without a sound: it needs
    /// nothing from anyone. One at a time — the newest replaces the last.
    private func notifyQuietly(_ line: String, tripId: String, date: String) {
        let content = UNMutableNotificationContent()
        content.title = "Keeping to the plan"
        content.body = line
        content.threadIdentifier = "trip"
        content.interruptionLevel = .passive
        content.userInfo = ["category": TripLink.category, "tripId": tripId, "date": date]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "trip-keepup-\(tripId)-\(date)", content: content, trigger: nil)) { _ in }
    }

    // MARK: Stop prompting

    func isPaused(_ tripId: String, _ date: String) -> Bool { paused.contains("\(tripId)|\(date)") }

    /// "Stop prompting the plan today": no checks, no prompts, no Lock Screen
    /// card for the rest of the day, and what was said is taken back.
    func pauseToday(tripId: String, date: String) {
        paused.insert("\(tripId)|\(date)")
        // Only this week's: a pause is for a day.
        UserDefaults.standard.set(Array(paused.suffix(20)), forKey: Self.pausedKey)
        dismiss()
        let centre = UNUserNotificationCenter.current()
        Task {
            let ids = await centre.deliveredNotifications().map(\.request.identifier).filter {
                ($0.hasPrefix(Self.alertPrefix) && $0.contains("\(tripId)|\(date)")) || $0 == "trip-keepup-\(tripId)-\(date)"
            }
            centre.removeDeliveredNotifications(withIdentifiers: ids)
        }
        refresh()
        TripLive.shared.refresh()
    }

    func resume(tripId: String, date: String) {
        paused.remove("\(tripId)|\(date)")
        UserDefaults.standard.set(Array(paused), forKey: Self.pausedKey)
        refresh()
        TripLive.shared.refresh()
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
        guard started, !SRDemo.isOn, let r = runningDay(now: now), !isPaused(r.tripId, r.date) else { return }
        let store = TripStore.shared
        // v5: its options change the plan, which only the creator and the
        // parents may; anyone else is not prompted.
        guard store.bundles[r.tripId]?.can.canEdit != false else { return }
        let nowMin = r.clock.minutes(now)
        // A slot whose time has gone drops off, ticked or not: nothing is
        // said about it again, and what was said is taken back.
        let marks = TripProgress.telling(day: r.day, marks: store.marks(r.tripId), nowMin: nowMin)
        let progress = TripProgress.of(day: r.day, marks: marks, nowMin: nowMin, clock: r.clock)
        withdrawPast(tripId: r.tripId, date: r.date, day: r.day, marks: marks)
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
            day: r.day, marks: marks, progress: progress, nowMin: nowMin,
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

    /// The prompt on show and the delivered alerts about a stop that is
    /// now done or past — or about another day — are withdrawn.
    private func withdrawPast(tripId: String, date: String, day: PlannedDay, marks: [String: TripStopMark]) {
        let gone = Set(day.stops.filter { marks[$0.id]?.done == true }.map(\.id))
        if let prompt, Self.stale(prompt.id, tripId: tripId, date: date, gone: gone) { dismiss() }
        Task {
            let centre = UNUserNotificationCenter.current()
            let ids = await centre.deliveredNotifications().map(\.request.identifier).filter { id in
                id.hasPrefix(Self.alertPrefix) && Self.stale(String(id.dropFirst(Self.alertPrefix.count)), tripId: tripId, date: date, gone: gone)
            }
            if !ids.isEmpty { centre.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }

    nonisolated static let alertPrefix = "trip-offplan-"

    /// A raised key, "<trip>|<date>|<kind>:<stop>": stale once its day is
    /// not today or its stop is done or past. A place's key (an unplanned
    /// stop) has no stop and stands.
    nonisolated static func stale(_ key: String, tripId: String, date: String, gone: Set<String>) -> Bool {
        let parts = key.split(separator: "|", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == tripId else { return false }
        if parts[1] != date { return true }
        guard let colon = parts[2].firstIndex(of: ":") else { return false }
        return gone.contains(String(parts[2][parts[2].index(after: colon)...]))
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
        let request = UNNotificationRequest(identifier: Self.alertPrefix + prompt.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: Location

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let good = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 200 }
        Task { @MainActor in
            self.fixes = Array((self.fixes + good).filter { Date().timeIntervalSince($0.timestamp) < 40 * 60 }.suffix(60))
            TripTrail.shared.add(good)
            if self.armed { self.relay?(good) }
            // A wake-up is also the Lock Screen's chance to move on.
            TripLive.shared.refresh()
            self.check()
            // And, ten minutes since the last, the look at the plan — on a
            // fix as well as the timer, so a phone iOS let sleep still gets it.
            if !good.isEmpty, self.lastKeepUp.map({ Date().timeIntervalSince($0) >= TripKeepUp.everySec }) ?? true {
                self.keepUp()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let location = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        let arrived = visit.arrivalDate
        let departed = visit.departureDate != Date.distantFuture
        Task { @MainActor in
            self.visitSince = departed || arrived == Date.distantPast ? nil : (location, arrived)
            TripLive.shared.refresh()
            self.check()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

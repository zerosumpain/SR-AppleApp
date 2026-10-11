import Foundation
import MapKit
import SwiftUI

/// The reader's own corrections to Coming up: "that is not where I am going"
/// and "I am not making this journey".
///
/// The site plans each diary event against the family's routes, and it can
/// only guess where an event's location text points — "Castle" may be the
/// clinic or the car park. A correction is held ON THIS PHONE, keyed by the
/// event's id, and applied wherever Coming up is read: the Family list,
/// Today's next leave-by, and the reminders scheduled from them. A dismissed
/// journey schedules no reminder.
///
/// Local, not the site's: there is no route on the site to take a correction
/// yet, so /home/people still shows its own guess. Corrections for events
/// that have gone are dropped after two days.
@MainActor
final class JourneyCorrections: ObservableObject {
    static let shared = JourneyCorrections()
    static let key = "journey-corrections"
    /// Events in Coming up are at most two days out; a week covers any lag.
    static let keep: TimeInterval = 7 * 24 * 3600

    struct Destination: Codable, Equatable {
        let name: String
        let lat: Double
        let lon: Double
        /// Minutes, from Apple Maps, from where the phone was when corrected.
        let minutes: Double
        /// `vehicle` or `active`, as the site's travel modes.
        let mode: String
    }

    struct Correction: Codable, Equatable {
        var dismissed: Bool = false
        var destination: Destination?
        let at: Date
    }

    @Published private(set) var all: [String: Correction]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: Correction].self, from: data) {
            let cutoff = Date().addingTimeInterval(-Self.keep)
            all = decoded.filter { $0.value.at > cutoff }
        } else {
            all = [:]
        }
    }

    func dismiss(_ id: String) {
        all[id] = Correction(dismissed: true, destination: all[id]?.destination, at: Date())
        save()
    }

    func correct(_ id: String, to destination: Destination) {
        all[id] = Correction(dismissed: false, destination: destination, at: Date())
        save()
    }

    /// Put an event back as the site planned it.
    func restore(_ id: String) {
        all[id] = nil
        save()
    }

    func isDismissed(_ id: String) -> Bool { all[id]?.dismissed ?? false }

    /// Coming up with this phone's corrections applied: dismissed journeys
    /// out, corrected destinations in with their own leave-by. PURE over
    /// `corrections`, so the tests can drive it.
    nonisolated static func apply(
        _ upcoming: FamilyForecast.Upcoming?,
        corrections: [String: Correction]
    ) -> FamilyForecast.Upcoming? {
        guard let upcoming else { return nil }
        let items = upcoming.items.compactMap { item -> FamilyForecast.UpcomingItem? in
            guard let fix = corrections[item.id] else { return item }
            if fix.dismissed { return nil }
            guard let to = fix.destination else { return item }
            return corrected(item, to: to)
        }
        return FamilyForecast.Upcoming(available: upcoming.available, items: items)
    }

    /// The item, re-pointed at `to`: its place, a leave-by from Apple Maps'
    /// time with the same allowance the site gives a routed trip (a fifth on
    /// top, at least five minutes), and no issue — the site's warning was
    /// about the journey it guessed.
    nonisolated static func corrected(_ item: FamilyForecast.UpcomingItem, to: Destination) -> FamilyForecast.UpcomingItem {
        let allowance = max(to.minutes * 1.2, to.minutes + 5)
        let leaveBy = parseTimestamp(item.start).map {
            timestamp($0.addingTimeInterval(-allowance * 60))
        }
        return FamilyForecast.UpcomingItem(
            id: item.id,
            title: item.title,
            start: item.start,
            end: item.end,
            place: to.name,
            subjects: item.subjects,
            leaveBy: leaveBy ?? item.leaveBy,
            from: item.from,
            travel: .init(source: "corrected", median: to.minutes, p80: allowance, samples: 0, mode: to.mode),
            issue: nil
        )
    }

    /// The live list, corrected.
    func apply(_ upcoming: FamilyForecast.Upcoming?) -> FamilyForecast.Upcoming? {
        Self.apply(upcoming, corrections: all)
    }

    /// How many of `upcoming`'s journeys this phone has dismissed.
    func dismissedCount(_ upcoming: FamilyForecast.Upcoming?) -> Int {
        upcoming?.items.filter { isDismissed($0.id) }.count ?? 0
    }

    private func save() {
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: Self.key) }
        // A correction moves or removes a leave-by: bring the reminders with it.
        Task { @MainActor in
            let f = FamilyForecastStore.shared.forecast
            guard AccessStore.shared.viewingAs == nil else { return }
            await LeaveByReminders.sync(self.apply(f?.upcoming), names: f?.names ?? [:])
        }
    }
}

// MARK: - Choosing a destination

/// Search for where the journey is really going, then time it with Apple Maps
/// from where this phone is now.
@MainActor
final class DestinationSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" { didSet { completer.queryFragment = query } }
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var working = false
    @Published var failure: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = Array(completer.results.prefix(8))
        Task { @MainActor in self.results = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    /// The completion as a place, timed by road or on foot.
    func resolve(_ completion: MKLocalSearchCompletion, mode: String) async -> JourneyCorrections.Destination? {
        working = true
        defer { working = false }
        failure = nil
        do {
            let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
            guard let item = response.mapItems.first else {
                failure = "Apple Maps could not place that. Try another search."
                return nil
            }
            let request = MKDirections.Request()
            request.source = MKMapItem.forCurrentLocation()
            request.destination = item
            request.transportType = mode == "vehicle" ? .automobile : .walking
            let eta = try await MKDirections(request: request).calculateETA()
            let coordinate = item.placemark.coordinate
            return .init(
                name: item.name ?? completion.title,
                lat: coordinate.latitude,
                lon: coordinate.longitude,
                minutes: (eta.expectedTravelTime / 60).rounded(.up),
                mode: mode
            )
        } catch {
            failure = "Apple Maps could not time that journey from here. Check location access and try again."
            return nil
        }
    }
}

/// The sheet: where is this really going?
struct JourneyDestinationSheet: View {
    let item: FamilyForecast.UpcomingItem
    @StateObject private var search = DestinationSearch()
    @ObservedObject private var corrections = JourneyCorrections.shared
    @Environment(\.dismiss) private var dismiss
    @State private var mode: String

    init(item: FamilyForecast.UpcomingItem) {
        self.item = item
        _mode = State(initialValue: item.travel?.mode == "active" ? "active" : "vehicle")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Travelling", selection: $mode) {
                        Text("By car").tag("vehicle")
                        Text("On foot").tag("active")
                    }
                    .pickerStyle(.segmented)
                    .srGlassRow()
                } footer: {
                    Text("Timed by Apple Maps from where this iPhone is now. The correction stays on this phone and moves the leave-by reminder with it.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
                if let failure = search.failure {
                    Text(failure)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.error)
                        .srGlassRow()
                }
                Section {
                    ForEach(search.results, id: \.self) { result in
                        Button {
                            Task {
                                if let place = await search.resolve(result, mode: mode) {
                                    SRHaptic.ok()
                                    corrections.correct(item.id, to: place)
                                    dismiss()
                                } else {
                                    SRHaptic.bad()
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title).font(SR.Text.title(16)).foregroundStyle(SR.ink)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle).font(SR.Text.secondary(13)).foregroundStyle(SR.inkSecondary)
                                }
                            }
                        }
                        .disabled(search.working)
                        .srGlassRow()
                    }
                } header: {
                    if !search.results.isEmpty { SRSectionLabel(text: "Places") }
                }
            }
            .listStyle(.insetGrouped)
            .srGround(.warm)
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Where is \(item.title) really?")
            .overlay { if search.working { ProgressView().tint(SR.accent) } }
            .navigationTitle("Change destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { search.query = item.place }
        }
    }
}

// MARK: - The countdown

/// Time left to leave, counting down on the right of a journey's row:
/// "42:10" inside the hour, "3:05:00" inside the day, "1d 4h" beyond, and
/// LEAVE NOW in red once it has passed.
struct LeaveCountdown: View {
    let leaveBy: Date
    var size: CGFloat = 20

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let left = leaveBy.timeIntervalSince(context.date)
            VStack(alignment: .trailing, spacing: 0) {
                Group {
                    if left <= 0 {
                        Text("NOW")
                    } else if left < 24 * 3600 {
                        Text(timerInterval: context.date...leaveBy, countsDown: true, showsHours: true)
                    } else {
                        Text(Self.days(left))
                    }
                }
                .font(SR.Text.figure(size))
                .monospacedDigit()
                .foregroundStyle(tint(left))
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
                Text(left <= 0 ? "LEAVE" : "TO LEAVE")
                    .font(SR.Text.label())
                    .tracking(1.1)
                    .foregroundStyle(left <= 0 ? SR.error : SR.inkMuted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(left <= 0 ? "Time to leave now" : "Leave in \(Self.spoken(left))")
        }
    }

    /// Red once it is time, orange inside a quarter of an hour, then ink.
    private func tint(_ left: TimeInterval) -> Color {
        if left <= 0 { return SR.error }
        if left <= 15 * 60 { return SR.accent }
        return SR.ink
    }

    static func days(_ left: TimeInterval) -> String {
        let hours = Int(left / 3600)
        return "\(hours / 24)d \(hours % 24)h"
    }

    static func spoken(_ left: TimeInterval) -> String {
        let minutes = Int((left / 60).rounded(.up))
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        return "\(hours) hour\(hours == 1 ? "" : "s") \(minutes % 60) minutes"
    }
}

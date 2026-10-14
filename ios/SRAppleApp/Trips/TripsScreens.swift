import SwiftUI

// Trips, under Today: the "Trip today" card, the list of trips, one trip's
// days. Planning happens on the site (`/trips`); the phone is the companion
// for the day itself, and everything here reads from what is kept on disk
// (`TripStore`), so it all works in airplane mode.

// MARK: - Navigation

struct TripRef: Hashable { let tripId: String }
struct TripDayRef: Hashable { let tripId: String; let date: String }
struct TripStopRef: Hashable { let tripId: String; let date: String; let stopId: String }
/// The list itself, pushed from Today.
struct TripsListRef: Hashable {}

extension View {
    /// Every trip screen, on Today's stack. Declared on the stack's ROOT —
    /// a destination declared on a pushed page did nothing on a phone (see
    /// the Landgrab note in `ContentView`).
    func tripDestinations() -> some View {
        self
            .navigationDestination(for: TripsListRef.self) { _ in TripsListScreen() }
            .navigationDestination(for: TripRef.self) { TripScreen(tripId: $0.tripId) }
            .navigationDestination(for: TripDayRef.self) { TripDayScreen(tripId: $0.tripId, date: $0.date) }
            .navigationDestination(for: TripStopRef.self) { TripStopScreen(ref: $0) }
    }
}

// MARK: - Today

/// "Trip today": what is next and when to leave, one tap from the day.
/// Before a trip, a quieter line with the countdown; with neither, nothing.
struct TodayTripCard: View {
    @ObservedObject private var store = TripStore.shared

    var body: some View {
        // Re-read every minute: "leave in 8 min" must not sit still.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let running = store.running(now: context.date) {
                NavigationLink(value: TripDayRef(tripId: running.bundle.trip.id, date: running.date)) {
                    runningCard(running.bundle, date: running.date, now: context.date)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-trip")
            } else if let next = store.upcoming(now: context.date) {
                NavigationLink(value: TripsListRef()) {
                    upcomingCard(next, now: context.date)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-trips")
            } else if !store.summaries.isEmpty {
                // Only trips that are over: still one tap to the list.
                NavigationLink(value: TripsListRef()) {
                    SRCard(interactive: true) {
                        SRRow(title: "Trips", subtitle: "\(store.summaries.count) on this phone", icon: "suitcase") {
                            Image(systemName: "chevron.right").foregroundStyle(SR.inkMuted).accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-trips")
            }
        }
    }

    private func runningCard(_ bundle: TripBundle, date: String, now: Date) -> some View {
        let day = store.day(bundle.trip.id, date)
        let progress = store.progress(bundle.trip.id, date, now: now)
        return SRCard(accented: true, interactive: true) {
            VStack(alignment: .leading, spacing: 10) {
                SRSectionLabel(text: "Trip today", trailing: bundle.trip.destination, prominent: true)
                if let day, let progress {
                    ForEach(TripWords.missedSlots(day: day, progress: progress, nowMin: TripClock(bundle.trip.timeZone).minutes(now)), id: \.self) { line in
                        Label(line, systemImage: "exclamationmark.octagon.fill")
                            .font(SR.Text.title(15))
                            .foregroundStyle(SR.error)
                    }
                    TripNextLines(day: day, progress: progress, bundle: bundle)
                } else {
                    Text("No plan for today yet — it is planned on the site.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                }
                Text("Open the day")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.accentDeep)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens today's plan")
    }

    private func upcomingCard(_ trip: TripSummary, now: Date) -> some View {
        let clock = TripClock(trip.timeZone)
        let days = clock.days(from: clock.localDate(now), to: trip.startDate) ?? 0
        return SRCard(interactive: true) {
            HStack(spacing: 12) {
                Image(systemName: "suitcase.rolling")
                    .foregroundStyle(SR.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.title).font(SR.Text.title()).foregroundStyle(SR.ink)
                    Text(days == 1 ? "Tomorrow" : "In \(days) days · \(TripFormat.range(trip.startDate, trip.endDate, zone: clock.zone))")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(SR.inkMuted).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens your trips")
    }
}

/// "Next: Pantheon" and "Leave by 14:20 · 12 min walk", with the booking
/// reference when the next stop has one. Shared by the Today card and the
/// Day screen's Now card.
struct TripNextLines: View {
    let day: PlannedDay
    let progress: TripProgress
    let bundle: TripBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let next = progress.next, next < day.stops.count {
                let stop = day.stops[next]
                Text("Next: \(stop.title)")
                    .font(SR.Text.display(20))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(TripWords.leaveLine(day: day, progress: progress))
                    .font(SR.Text.mono(13))
                    .foregroundStyle(progress.showsBehind ? SR.error : SR.inkSecondary)
                if let booking = bundle.booking(for: stop), let ref = booking.reference, !ref.isEmpty {
                    Text("Booking ref \(ref)")
                        .font(SR.Text.mono(13))
                        .foregroundStyle(SR.accentInk)
                        .textSelection(.enabled)
                }
            } else {
                Text("That's the day done")
                    .font(SR.Text.display(20))
                    .foregroundStyle(SR.ink)
            }
        }
    }
}

/// Sentences built from plan figures, said the same way on every screen.
enum TripWords {
    /// "Leave by 14:20 · 12 min walk"; heading there: "Arrive 14:32 · 12 min walk".
    static func leaveLine(day: PlannedDay, progress: TripProgress) -> String {
        guard let next = progress.next, next < day.stops.count else { return "" }
        let leg = day.leg(before: next).map { " · " + TripFormat.leg($0) } ?? ""
        var line: String
        switch progress.phase {
        case .heading:
            line = "Arrive \(TripFormat.time(day.stops[next].arriveMin))\(leg)"
        default:
            line = "Leave by \(TripFormat.time(progress.leaveMin ?? day.stops[next].arriveMin))\(leg)"
        }
        if progress.showsBehind { line += " · \(Int(progress.behindMin.rounded())) min behind" }
        return line
    }

    /// "09:00–10:30", or one time for a stop with no stay.
    static func span(_ stop: PlannedStop) -> String {
        stop.departMin - stop.arriveMin < 1
            ? TripFormat.time(stop.arriveMin)
            : "\(TripFormat.time(stop.arriveMin))–\(TripFormat.time(stop.departMin))"
    }

    /// Missed booked or locked slots: the solver's own day warnings ("Missed
    /// your 09:30 Colosseum slot", put first by `replanDay`), and — on the
    /// running day — any locked stop not reached by its start plus the
    /// solver's grace, said in the same words before anything is re-planned.
    static func missedSlots(day: PlannedDay, progress: TripProgress?, nowMin: Double?) -> [String] {
        var out = day.warnings.filter { $0.hasPrefix("Missed your ") }
        guard let progress, let nowMin, let from = progress.currentIndex else { return out }
        let done = Set(progress.doneStopIds)
        for (i, stop) in day.stops.enumerated() where i >= from && stop.locked && !done.contains(stop.id) {
            if case .at(let here) = progress.phase, here == i { continue }
            let start = stop.arriveMin + js.round(stop.waitSec / 60)
            guard nowMin > start + TripReplan.missedSlotGraceMin else { continue }
            let line = "Missed your \(TripFormat.time(start)) \(stop.title) slot"
            if !out.contains(line) { out.append(line) }
        }
        return out
    }

    /// Over this, a wait is time to spend, not time to stand in a queue.
    static let freeTimeOverMin = 45.0

    /// "Wait 15 min before it starts", or "Free time · 1 h 10" for a long
    /// gap before a booked slot or an opening.
    static func wait(_ stop: PlannedStop) -> String? {
        let minutes = stop.waitSec / 60
        guard minutes >= 1 else { return nil }
        if minutes > freeTimeOverMin { return "Free time · \(TripFormat.duration(minutes: minutes)) first" }
        return "Wait \(TripFormat.duration(minutes: minutes)) before it starts"
    }

    /// A stop the person made that the plan did not have (`here:<date>:<min>`,
    /// added by an off-plan "stay here"): a wish with no wish behind it.
    static func isHere(_ stop: PlannedStop) -> Bool { stop.id.hasPrefix("here:") && stop.wishId == nil }

    /// "Drop bags": the stay before check-in on an arrival day (v3). Said
    /// plainly — it is a stop, not a sight.
    static func isDropBags(_ stop: PlannedStop) -> Bool {
        stop.title.lowercased().hasPrefix("drop bags") || stop.id.hasSuffix(":bags")
    }

    static func symbol(_ stop: PlannedStop) -> String {
        if isHere(stop) { return "cup.and.saucer" }
        if isDropBags(stop) { return "suitcase.rolling" }
        switch stop.kind {
        case .stay: return "bed.double"
        case .meal: return "fork.knife"
        case .wish: return stop.locked ? "lock" : "mappin"
        case .transport: return "airplane"
        case .unknown: return "mappin"
        }
    }
}

// MARK: - The list

struct TripsListScreen: View {
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var network = TripNetwork.shared

    var body: some View {
        List {
            if store.ownerOnly {
                SREmpty(
                    title: "Trips are owner-only for now",
                    icon: "suitcase",
                    message: "The trip planner is the owner's while it is new. It opens to the family later."
                )
                .srPlainRow()
            } else if store.summaries.isEmpty {
                SREmpty(
                    title: store.loading ? "Looking for trips…" : "No trips yet",
                    icon: "suitcase.rolling",
                    message: "Trips are planned on the site, at strangeramblings.com/trips. Each one appears here, ready to use offline."
                )
                .srPlainRow()
            } else {
                section("Now", trips(.now))
                section("Coming up", trips(.upcoming))
                section("Been", trips(.past))
            }
            footer.srPlainRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .srPaper()
        .navigationTitle("Trips")
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable { await store.refresh() }
        .task { await store.refreshIfStale(after: 60) }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRBanner(text: message, tone: SR.error) }
        }
        .accessibilityIdentifier("trips-screen")
    }

    private enum When { case now, upcoming, past }

    private func trips(_ when: When) -> [TripSummary] {
        let now = Date()
        return store.summaries.filter { trip in
            let today = TripClock(trip.timeZone).localDate(now)
            switch when {
            case .now: return TripClock.within(today, trip.startDate, trip.endDate)
            case .upcoming: return today < trip.startDate
            case .past: return today > trip.endDate
            }
        }
        .sorted { when == .past ? $0.startDate > $1.startDate : $0.startDate < $1.startDate }
    }

    @ViewBuilder
    private func section(_ title: String, _ list: [TripSummary]) -> some View {
        if !list.isEmpty {
            Section {
                ForEach(list) { trip in
                    NavigationLink(value: TripRef(tripId: trip.id)) {
                        SRRow(
                            title: trip.title,
                            subtitle: "\(trip.destination) · \(TripFormat.range(trip.startDate, trip.endDate, zone: TripClock(trip.timeZone).zone))",
                            icon: "suitcase.rolling"
                        ) {
                            if store.bundles[trip.id] == nil {
                                Image(systemName: "icloud.slash")
                                    .foregroundStyle(SR.inkMuted)
                                    .accessibilityLabel("Not on this phone yet")
                            }
                        }
                    }
                    .srPlainRow()
                    .accessibilityIdentifier("trip-row-\(trip.id)")
                }
            } header: {
                SRSectionLabel(text: title)
            }
        }
    }

    private var footer: some View {
        TripSavedLine(refreshedAt: store.refreshedAt, online: network.online)
            .padding(.vertical, 16)
    }
}

/// "Saved on this phone · checked 10 min ago" — so an offline screen says
/// how old it is rather than looking broken.
struct TripSavedLine: View {
    let refreshedAt: Date?
    let online: Bool
    var queued = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
            if queued > 0 {
                Text(queued == 1 ? "1 update waiting to send" : "\(queued) updates waiting to send")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
    }

    private var line: String {
        let when = refreshedAt.map { "checked " + $0.formatted(.relative(presentation: .named)) } ?? "not checked yet this session"
        return online ? "Saved on this phone · \(when)" : "Offline · using what is saved on this phone"
    }
}

// MARK: - One trip

struct TripScreen: View {
    let tripId: String
    @ObservedObject private var store = TripStore.shared

    var body: some View {
        Group {
            if let bundle = store.bundles[tripId] {
                content(bundle)
            } else if store.ownerOnly {
                SREmpty(title: "Trips are owner-only for now", icon: "suitcase")
            } else {
                SREmpty(
                    title: "Not on this phone yet",
                    icon: "icloud.and.arrow.down",
                    message: "Open this with a connection once and the whole trip is kept for offline use.",
                    actionLabel: "Try again",
                    action: { Task { await store.fetch(tripId) } }
                )
            }
        }
        .srPaper()
        .navigationTitle(store.bundles[tripId]?.trip.title ?? "Trip")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.fetch(tripId) }
    }

    private func content(_ bundle: TripBundle) -> some View {
        let clock = TripClock(bundle.trip.timeZone)
        let today = clock.localDate(Date())
        let days = bundle.plan?.plan.days ?? []
        return List {
            VStack(alignment: .leading, spacing: 6) {
                Text(bundle.trip.destination.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.4)
                    .foregroundStyle(SR.inkMuted)
                Text(bundle.trip.title)
                    .font(SR.Text.display(26))
                    .foregroundStyle(SR.ink)
                Text("\(TripFormat.range(bundle.trip.startDate, bundle.trip.endDate, zone: clock.zone)) · \(bundle.trip.pace.rawValue) pace")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
            }
            .padding(.vertical, 12)
            .srPlainRow()

            if days.isEmpty {
                Text("No plan yet. Add wishes and plan the trip on the site.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .srPlainRow()
            }

            Section {
                ForEach(days) { planned in
                    let day = store.day(tripId, planned.date) ?? planned
                    NavigationLink(value: TripDayRef(tripId: tripId, date: day.date)) {
                        VStack(alignment: .leading, spacing: 0) {
                            SRRow(
                                title: TripFormat.day(day.date, zone: clock.zone) + (day.date == today ? " · today" : "")
                                    + (bundle.trip.dayLoads?[day.date] == "light" ? " · easy day" : ""),
                                subtitle: daySummary(day),
                                icon: day.date == today ? "sun.max.fill" : "calendar"
                            )
                            // v4: the day's four stages, in brief.
                            TripStageStrip(day: day, wishes: bundle.wishes)
                        }
                    }
                    .srPlainRow()
                    .accessibilityIdentifier("trip-day-\(day.date)")
                }
            } header: {
                SRSectionLabel(text: "Days")
            }

            let toBook = bundle.bookings.filter { $0.status == .toBook }
            if !toBook.isEmpty {
                Section {
                    ForEach(toBook) { booking in
                        SRRow(title: booking.title, subtitle: booking.date.map { TripFormat.day($0, zone: clock.zone) }, icon: "ticket") {
                            if let link = booking.url.flatMap(URL.init(string:)) {
                                Link("Book", destination: link).font(SR.Text.label())
                            }
                        }
                        .srPlainRow()
                    }
                } header: {
                    SRSectionLabel(text: "Still to book")
                }
            }

            if let profile = bundle.profile {
                TripProfileSection(profile: profile)
            }

            if let plan = bundle.plan, !(plan.plan.dropped.isEmpty && plan.plan.warnings.isEmpty) {
                Section {
                    ForEach(plan.plan.dropped, id: \.wishId) { dropped in
                        SRRow(title: bundle.wish(dropped.wishId)?.title ?? "A wish", subtitle: dropped.reason, icon: "minus.circle", tone: SR.inkMuted)
                            .srPlainRow()
                    }
                    ForEach(plan.plan.warnings, id: \.self) { warning in
                        SRRow(title: warning, icon: "exclamationmark.triangle", tone: SR.warn)
                            .srPlainRow()
                    }
                } header: {
                    SRSectionLabel(text: "Left out and worth knowing")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .srRefreshable { await store.fetch(tripId) }
    }

    /// "6 stops · 09:00–18:40".
    private func daySummary(_ day: PlannedDay) -> String {
        let visits = day.stops.filter { $0.kind != .stay }.count
        guard let first = day.stops.first, let last = day.stops.last else { return "Nothing planned" }
        return "\(visits) stop\(visits == 1 ? "" : "s") · \(TripFormat.time(first.departMin))–\(TripFormat.time(last.arriveMin))"
    }
}

/// "What I know about you": the planner's picture of the people travelling,
/// read-only, each item with where it came from. Corrected by saying so in
/// Edit plan.
struct TripProfileSection: View {
    let profile: TravellerProfile

    var body: some View {
        Section {
            ForEach(profile.travellers, id: \.name) { t in
                SRRow(title: t.name + (t.relation.map { " · \($0)" } ?? ""),
                      subtitle: t.notes.isEmpty ? nil : t.notes.joined(separator: " · "), icon: "person")
                    .srPlainRow()
            }
            ForEach(profile.constraints, id: \.self) { k in
                SRRow(title: k.text, subtitle: Self.source(k), icon: "exclamationmark.shield", tone: SR.warn).srPlainRow()
            }
            ForEach(profile.preferences, id: \.self) { k in
                SRRow(title: k.text, subtitle: Self.source(k), icon: "heart").srPlainRow()
            }
            ForEach(profile.history, id: \.self) { h in
                SRRow(title: h, subtitle: "Past trips", icon: "clock.arrow.circlepath", tone: SR.inkMuted).srPlainRow()
            }
            Text("To change any of this, say so in Edit plan.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .padding(.vertical, 6)
                .srPlainRow()
        } header: {
            SRSectionLabel(text: "What I know about you")
        }
        .accessibilityIdentifier("trip-profile")
    }

    static func source(_ k: TravellerProfile.Known) -> String {
        switch k.source {
        case "memory": return "From your memory"
        case "knowledge": return "From your notes"
        case "family": return "From the family"
        case "conversation": return "You said so"
        default: return k.source
        }
    }
}

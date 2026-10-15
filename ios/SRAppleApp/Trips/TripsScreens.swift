import SwiftUI

// Trips, under Today: the "Trip today" card, the list of trips, one trip's
// days. A trip is planned by talking to the planner — here ("New trip",
// "Edit plan") or on the owner's site studio (`/trips`) — and everything
// shown reads from what is kept on disk (`TripStore`), so it all works in
// airplane mode.

// MARK: - Navigation

struct TripRef: Hashable {
    let tripId: String
    /// v5: just made — open the conversation with the planner straight away.
    var talk = false
}
struct TripDayRef: Hashable { let tripId: String; let date: String }
struct TripStopRef: Hashable { let tripId: String; let date: String; let stopId: String }
/// The list itself, pushed from Today. `start`: open "New trip" at once.
struct TripsListRef: Hashable { var start = false }

extension View {
    /// Every trip screen, on Today's stack. Declared on the stack's ROOT —
    /// a destination declared on a pushed page did nothing on a phone (see
    /// the Landgrab note in `ContentView`).
    func tripDestinations() -> some View {
        self
            .navigationDestination(for: TripsListRef.self) { TripsListScreen(start: $0.start) }
            .navigationDestination(for: TripRef.self) { TripScreen(tripId: $0.tripId, talk: $0.talk) }
            .navigationDestination(for: TripDayRef.self) { TripDayScreen(tripId: $0.tripId, date: $0.date) }
            .navigationDestination(for: TripStopRef.self) { TripStopScreen(ref: $0) }
            .navigationDestination(for: TripStoryRef.self) { TripStoryScreen(tripId: $0.tripId) }
    }
}

// MARK: - Today

/// "Trip today": what is next and when to leave, one tap from the day.
/// Before a trip, a quieter line with the countdown; after them, the list;
/// with no trips at all, "Plan a trip" — the only way in for somebody who
/// has never had one (the list, and its "New trip", sit behind this card).
struct TodayTripCard: View {
    @ObservedObject private var store = TripStore.shared
    @EnvironmentObject private var router: Router

    // Why a Button and a path, not a NavigationLink: the card is glass, and
    // on iOS 26 `glassEffect` is not a hit-testable background. A plain-
    // styled link only answered where text or an icon was drawn, so a tap in
    // the card's empty space did nothing — "press it several times". The
    // whole card is the target now (`contentShape`), and the push goes
    // through `Router.openTrips`, as every other Today card's does.
    var body: some View {
        // Re-read every minute: "leave in 8 min" must not sit still.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let running = store.running(now: context.date) {
                target(id: "today-trip") {
                    router.openTrips(day: TripDayRef(tripId: running.bundle.trip.id, date: running.date))
                } label: {
                    runningCard(running.bundle, date: running.date, now: context.date)
                }
            } else if let next = store.upcoming(now: context.date) {
                target(id: "today-trips") { router.openTrips() } label: {
                    upcomingCard(next, now: context.date)
                }
            } else if !store.summaries.isEmpty {
                // Only trips that are over: still one tap to the list.
                target(id: "today-trips") { router.openTrips() } label: {
                    SRCard(interactive: true) {
                        SRRow(title: "Trips", subtitle: "\(store.summaries.count) on this phone", icon: "suitcase") {
                            Image(systemName: "chevron.right").foregroundStyle(SR.inkMuted).accessibilityHidden(true)
                        }
                    }
                }
            } else if !store.ownerOnly && !store.loading && (SiteClient.shared.isPaired || SRDemo.isOn) {
                // No trips yet: straight into "New trip".
                target(id: "today-plan-trip") { router.openTrips(start: true) } label: {
                    SRCard(interactive: true) {
                        SRRow(title: "Plan a trip", subtitle: "Say where, when and who — the planner drafts the days", icon: "suitcase.rolling") {
                            Image(systemName: "chevron.right").foregroundStyle(SR.inkMuted).accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    /// One reliable tap target: the whole card, rounded as the glass is.
    private func target<Content: View>(id: String, action: @escaping () -> Void, @ViewBuilder label: () -> Content) -> some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            label()
                .contentShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
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
                    Text("No plan for today yet — open the day and use Edit plan.")
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
    /// Open "New trip" as soon as the list shows (Today's "Plan a trip").
    var start = false
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var network = TripNetwork.shared
    @EnvironmentObject private var router: Router
    @State private var starting = false
    /// `start` is acted on once, not again on coming Back to the list.
    @State private var started = false

    var body: some View {
        List {
            if store.ownerOnly {
                SREmpty(
                    title: "Trips are for the family",
                    icon: "suitcase",
                    message: "Ask a parent to add you to the Family Circle, and every family trip appears here."
                )
                .srPlainRow()
            } else if store.summaries.isEmpty {
                SREmpty(
                    title: store.loading ? "Looking for trips…" : "No trips yet",
                    icon: "suitcase.rolling",
                    message: "Tell the planner where, when and who's coming, and it drafts the days. Every family trip appears here, ready to use offline.",
                    actionLabel: store.loading ? nil : "Plan a trip",
                    action: { starting = true }
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
        .toolbar {
            // v5: any family member may start a trip, by talking to the planner.
            if !store.ownerOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { SRHaptic.tap(); starting = true } label: { Label("New trip", systemImage: "plus") }
                        .accessibilityIdentifier("trip-new-button")
                }
            }
        }
        .sheet(isPresented: $starting) {
            TripNewSheet { id in router.today.append(TripRef(tripId: id, talk: true)) }
                .presentationDetents([.large])
        }
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable { await store.refresh() }
        .task {
            if start && !started && !store.ownerOnly {
                started = true
                starting = true
            }
            await store.refreshIfStale(after: 60)
        }
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
    var talk = false
    @ObservedObject private var store = TripStore.shared
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var opened = false

    var body: some View {
        Group {
            if let bundle = store.bundles[tripId] {
                content(bundle)
            } else if store.ownerOnly {
                SREmpty(title: "This trip isn't shared with you", icon: "suitcase")
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
        .toolbar {
            if let bundle = store.bundles[tripId] {
                ToolbarItem(placement: .topBarTrailing) {
                    // The creator and parents change the plan; anyone else asks.
                    Button { SRHaptic.tap(); editing = true } label: {
                        Text(bundle.can.canEdit ? "Edit plan" : "Ask").font(SR.Text.label(13))
                    }
                    .accessibilityIdentifier("trip-edit-plan")
                }
            }
        }
        .sheet(isPresented: $editing) {
            TripConverseSheet(tripId: tripId, date: conversationDate)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await store.fetch(tripId)
            // A trip just made: carry on the conversation that made it.
            if talk && !opened {
                opened = true
                editing = true
            }
        }
    }

    /// Today when the trip is on, else its first day.
    private var conversationDate: String {
        guard let bundle = store.bundles[tripId] else { return "" }
        let today = TripClock(bundle.trip.timeZone).localDate(Date())
        return TripClock.within(today, bundle.trip.startDate, bundle.trip.endDate) ? today : bundle.trip.startDate
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
                if let maker = bundle.trip.createdByName {
                    Text(bundle.can.role == "creator" ? "Your trip" : "\(maker)'s trip")
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkMuted)
                }
            }
            .padding(.vertical, 12)
            .srPlainRow()

            // v7: the trip in brief — who, when, how, what matters.
            TripBriefCard(bundle: bundle, today: today).srPlainRow()

            if days.isEmpty {
                Text(bundle.can.canEdit
                     ? "No plan yet. Tell the planner what you'd like in Edit plan."
                     : "No plan yet.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .srPlainRow()
            } else {
                let shown = days.map { store.day(tripId, $0.date) ?? $0 }
                // The whole trip on one map: a colour a day, each day's
                // number at its first stop. Tap one to open that day.
                TripOverviewMap(scene: TripMapScene.overview(shown, stays: bundle.stays)) { date in
                    router.today.append(TripDayRef(tripId: tripId, date: date))
                }
                .listRowInsets(EdgeInsets(top: 0, leading: SR.gutter, bottom: 8, trailing: SR.gutter))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                // v5: the trip at a glance — a cell a day, its stages and how full it is.
                TripDayTimeline(tripId: tripId, bundle: bundle, days: shown, today: today)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                TripOfflineRow(tripId: tripId, title: bundle.trip.title, days: shown)
                    .srPlainRow()
            }

            if let travellers = bundle.knownProfile?.travellers, !travellers.isEmpty {
                TripTravellersRow(travellers: travellers).srPlainRow()
            }

            if !bundle.segments.isEmpty {
                Section {
                    ForEach(bundle.segments) { segment in
                        SRRow(
                            title: [segment.number, segment.carrier].compactMap { $0 }.joined(separator: " · ").isEmpty
                                ? segment.kind.capitalized : [segment.number, segment.carrier].compactMap { $0 }.joined(separator: " · "),
                            subtitle: "\(segment.from.code ?? segment.from.name) \(TripFormat.time(segment.departMin)) → \(segment.to.code ?? segment.to.name) \(TripFormat.time(segment.arriveMin)) · \(TripFormat.day(segment.departDate, zone: clock.zone))",
                            icon: segment.kind == "flight" ? "airplane" : "train.side.front.car"
                        )
                        .srPlainRow()
                    }
                } header: { SRSectionLabel(text: "Journeys") }
            }

            // The city guide the site writes: getting around, taxis, tickets,
            // tips. Written for the trip and, until now, shown nowhere.
            if let guide = bundle.guide {
                Section {
                    TripCityGuideCard(guide: guide).srPlainRow()
                } header: { SRSectionLabel(text: "Getting around \(TripCityGuideCard.city(bundle.trip.destination))") }
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

            // v7: what to book, by when — from how far ahead each sells out.
            let toBook = TripBookAhead.items(bundle, today: today, clock: clock)
            if !toBook.isEmpty {
                Section {
                    ForEach(toBook) { item in
                        TripBookAheadRow(item: item, zone: clock.zone).srPlainRow()
                    }
                } header: {
                    SRSectionLabel(text: "Still to book", trailing: "soonest first")
                }
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

            // v7: once a day has been, the story so far — when you were
            // where, and the photos you took there.
            if days.contains(where: { $0.date < today }) {
                NavigationLink(value: TripStoryRef(tripId: tripId)) {
                    SRRow(title: today > bundle.trip.endDate ? "How it went" : "How it's going",
                          subtitle: "Each stop, when you were there, and your photos from it", icon: "photo.on.rectangle.angled")
                }
                .srPlainRow()
                .accessibilityIdentifier("trip-story-link")
            }

            // The list is always the page beneath a trip: go back to it.
            Button { dismiss() } label: {
                Label("All trips", systemImage: "suitcase")
                    .font(SR.Text.label(13))
                    .padding(.vertical, 10)
            }
            .srPlainRow()
            .accessibilityIdentifier("trip-all-trips")
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

/// Who is travelling: names and ages. Nothing the planner remembers about
/// them is shown — memories never reach the app (v5).
struct TripTravellersRow: View {
    let travellers: [TravellerProfile.Traveller]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SRSectionLabel(text: "Travelling")
            Text(travellers.map(Self.line).joined(separator: " · "))
                .font(SR.Text.body(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip-travellers")
    }

    /// "Sam, 9".
    static func line(_ t: TravellerProfile.Traveller) -> String {
        t.age.map { "\(t.name), \(Int($0))" } ?? t.name
    }
}

/// The trip as a row of days: each cell its date, the four stages as a
/// strip, and how full the day is (colour and per cent). Tap to open it.
struct TripDayTimeline: View {
    let tripId: String
    let bundle: TripBundle
    let days: [PlannedDay]
    let today: String
    /// So a forecast that lands later shows without a reload.
    @ObservedObject private var weather = TripWeatherStore.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.element.date) { i, day in
                    NavigationLink(value: TripDayRef(tripId: tripId, date: day.date)) {
                        cell(i + 1, day)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trip-timeline-\(day.date)")
                }
            }
            .padding(.horizontal, SR.gutter)
        }
        .accessibilityIdentifier("trip-timeline")
    }

    private func cell(_ number: Int, _ day: PlannedDay) -> some View {
        let full = TripFullness.of(day, bundle: bundle)
        let groups = TripStages.groups(day, wishes: bundle.wishes)
        let zone = TripClock(bundle.trip.timeZone).zone
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // The day's colour on the trip's map.
                Circle().fill(Color(hex: TripMapScene.dayColor(number - 1))).frame(width: 9, height: 9)
                Text("\(number)")
                    .font(SR.Text.display(20))
                    .foregroundStyle(day.date == today ? SR.accent : SR.ink)
                Text(TripFormat.day(day.date, zone: zone))
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(1)
            }
            // The forecast, once the day is near enough to have one.
            if let sky = weather.day(tripId, day.date) {
                HStack(spacing: 4) {
                    Image(systemName: TripWeatherWords.symbol(sky.code)).symbolRenderingMode(.multicolor)
                    Text(sky.highC.map { "\(Int($0.rounded()))°" } ?? TripWeatherWords.words(sky.code))
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkSecondary)
                }
                .accessibilityHidden(true)
            }
            // The four stages, each as wide as the stops it holds.
            HStack(spacing: 2) {
                ForEach(groups, id: \.stage) { g in
                    TripStageMark(stage: g.stage)
                        .frame(width: CGFloat(max(1, g.indexes.count)) * 9, height: 8)
                        .opacity(g.indexes.isEmpty ? 0.3 : 1)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                // How full, as a bar rather than a percentage.
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.inkMuted.opacity(0.18))
                    Capsule().fill(TripFullness.colour(full.band))
                        .frame(width: 96 * CGFloat(min(1, max(0.04, full.pct / 100))))
                }
                .frame(width: 96, height: 5)
                Text(TripFullness.sentence(full.band))
                    .font(SR.Text.secondary(12))
                    .foregroundStyle(full.band == "overfull" ? SR.error : SR.inkSecondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(minWidth: 120, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4, interactive: true)
        .overlay {
            if day.date == today {
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous).stroke(SR.accent, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Day \(number), \(TripFormat.day(day.date, zone: zone)): \(TripFullness.sentence(full.band))")
    }
}

/// The trip's overview map: every day at once, still — a list scrolls over
/// it — but a tapped day number opens that day.
struct TripOverviewMap: View {
    let scene: TripMapScene.Scene
    let open: (String) -> Void

    var body: some View {
        TripSceneMap(scene: scene, interactive: false) { pin in
            // Day pins are named by their date; a stay is not a day.
            guard let pin, !pin.id.hasPrefix("stay:") else { return }
            SRHaptic.tap()
            open(pin.id)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Text("Tap a day's number to open it")
                .font(SR.Text.mono(11))
                .foregroundStyle(SR.inkSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .srGlass(.paper, in: Capsule())
                .padding(8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map of the whole trip, a colour a day")
        .accessibilityIdentifier("trip-overview-map")
    }
}

/// The city guide: how to get about, taxis, tickets and tips, as the site's
/// planner wrote them for this trip (model-written from its sources).
struct TripCityGuideCard: View {
    let guide: TripGuide

    /// "Rome, Italy" → "Rome".
    static func city(_ destination: String) -> String {
        destination.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? destination
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(guide.gettingAround)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let tickets = guide.transitTickets {
                Label(tickets, systemImage: "ticket")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let taxi = guide.taxi {
                Label(taxi.how, systemImage: "car.side")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                TripLinkButtons(links: taxi.links, phone: taxi.phone)
                    .controlSize(.small)
            }
            ForEach(guide.tips, id: \.self) { tip in
                Label(tip, systemImage: "lightbulb")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // v7: the neighbourhoods the trip goes to, and the primer.
            if let areas = guide.neighbourhoods, !areas.isEmpty {
                SRSectionLabel(text: "Where you'll be").padding(.top, 6)
                ForEach(areas, id: \.name) { area in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(area.name).font(SR.Text.title(15)).foregroundStyle(SR.ink)
                        Text(area.line).font(SR.Text.secondary(13)).foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(area.places.joined(separator: " · ")).font(SR.Text.mono(11)).foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let primer = guide.primer {
                SRSectionLabel(text: "Good to know").padding(.top, 6)
                ForEach(primer.customs, id: \.self) { custom in
                    Label(custom, systemImage: "hand.raised")
                        .font(SR.Text.secondary(14)).foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let money = primer.money {
                    Label(money, systemImage: "creditcard")
                        .font(SR.Text.secondary(14)).foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let safety = primer.safety {
                    Label(safety, systemImage: "shield.lefthalf.filled")
                        .font(SR.Text.secondary(14)).foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !primer.phrases.isEmpty {
                    SRSectionLabel(text: "A few words").padding(.top, 4)
                    ForEach(primer.phrases, id: \.local) { phrase in
                        HStack(alignment: .firstTextBaseline) {
                            Text(phrase.local).font(SR.Text.title(14)).foregroundStyle(SR.ink).textSelection(.enabled)
                            Spacer(minLength: 8)
                            Text(phrase.meaning).font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Text("Written by the planner from what it found online — worth a check on the day.")
                .font(SR.Text.mono(11))
                .foregroundStyle(SR.inkMuted)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-city-guide")
    }
}

/// The trip in brief: who is going, the pace, the musts and what is booked,
/// counted down before it starts. What the planner understood, at a glance —
/// "Edit plan" changes it.
struct TripBriefCard: View {
    let bundle: TripBundle
    let today: String

    var body: some View {
        let clock = TripClock(bundle.trip.timeZone)
        let musts = bundle.wishes.filter { $0.priority == .must && !$0.skipped && !$0.suggested }.map(\.title)
        let booked = bundle.bookings.filter { $0.status == .booked }.count
        let travellers = bundle.knownProfile?.travellers ?? []
        VStack(alignment: .leading, spacing: 6) {
            if today < bundle.trip.startDate, let days = clock.days(from: today, to: bundle.trip.startDate) {
                Text(days == 1 ? "Tomorrow" : "In \(days) days")
                    .font(SR.Text.display(20))
                    .foregroundStyle(SR.accentDeep)
            }
            line("person.2", travellers.isEmpty ? nil : travellers.map(TripTravellersRow.line).joined(separator: " · "))
            line("figure.walk", "\(bundle.trip.pace.rawValue.capitalized) pace" + (bundle.trip.modes.isEmpty ? "" : " · " + bundle.trip.modes.map { TripLegPicker.name($0).lowercased() }.joined(separator: ", ")))
            line("star", musts.isEmpty ? nil : "Musts: " + musts.prefix(4).joined(separator: ", ") + (musts.count > 4 ? " +\(musts.count - 4)" : ""))
            line("ticket", booked == 0 ? nil : "\(booked) booked")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip-brief")
    }

    @ViewBuilder
    private func line(_ icon: String, _ text: String?) -> some View {
        if let text {
            Label(text, systemImage: icon)
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Colosseum — book by Tue 13 Oct · sells out about 14 days ahead · for
/// Tue 27 Oct", in red once the day has passed.
struct TripBookAheadRow: View {
    let item: TripBookAhead.Item
    let zone: TimeZone

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.overdue ? "exclamationmark.circle.fill" : "ticket")
                .foregroundStyle(item.overdue ? SR.error : SR.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(SR.Text.title(15)).foregroundStyle(SR.ink)
                if let by = item.bookBy {
                    Text((item.overdue ? "Should have been booked by " : "Book by ") + TripFormat.day(by, zone: zone))
                        .font(SR.Text.mono(12))
                        .foregroundStyle(item.overdue ? SR.error : SR.accentDeep)
                }
                Text([item.aheadDays.map { "sells out about \($0) days ahead" }, item.visitDate.map { "for " + TripFormat.day($0, zone: zone) }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(SR.Text.secondary(12))
                    .foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 8)
            if let link = item.url.flatMap(TripLinkButtons.safeURL) {
                Link("Book", destination: link).font(SR.Text.label())
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip-book-ahead")
    }
}

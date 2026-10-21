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
    /// v8: just made by the guided start — open on its trip shapes.
    var shapes = false
}
struct TripDayRef: Hashable {
    let tripId: String
    let date: String
    /// v8: a proposal to show on the day's map as it opens (Preview).
    var preview: String? = nil
    /// v8: a group of alternatives (a swap) to show in the day's drawer.
    var group: String? = nil
}
/// The city guide, a page of its own.
struct TripGuideRef: Hashable { let tripId: String }
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
            .navigationDestination(for: TripRef.self) { TripScreen(tripId: $0.tripId, talk: $0.talk, shapes: $0.shapes) }
            .navigationDestination(for: TripDayRef.self) { TripDayScreen(tripId: $0.tripId, date: $0.date, preview: $0.preview, group: $0.group) }
            .navigationDestination(for: TripStopRef.self) { TripStopScreen(ref: $0) }
            .navigationDestination(for: TripStoryRef.self) { TripStoryScreen(tripId: $0.tripId) }
            .navigationDestination(for: TripGuideRef.self) { TripGuideScreen(tripId: $0.tripId) }
    }
}

// MARK: - Today

/// "Next: Pantheon" and "Leave by 14:20 · 12 min walk", with the booking
/// reference when the next stop has one. (The old "Trip today" card that
/// shared it went with the Home tiles; P2's Home tile reads the trip now.)
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
    @ObservedObject private var jobs = TripJobs.shared
    @EnvironmentObject private var router: Router
    @State private var starting = false
    /// `start` is acted on once, not again on coming Back to the list.
    @State private var started = false

    var body: some View {
        List {
            // v8: a guided start still researching — the sheet may be closed;
            // this is where it carries on, with its stages.
            if jobs.isRunning(TripJobs.startKey) || jobs.created[TripJobs.startKey] != nil {
                Button { starting = true } label: {
                    SRRow(title: "Planning \(startingWhere)", subtitle: startingLine, icon: "sparkles") {
                        if jobs.isRunning(TripJobs.startKey) { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
                .srPlainRow()
                .accessibilityIdentifier("trips.start.running")
            }
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
            // v8: the guided start (where, when, who, pace, what the notes
            // hold), its research, then the trip opens on its shapes. A trip
            // typed as a sentence opens on the conversation that made it.
            TripStartFlow { id, typed in
                router.today.append(TripRef(tripId: id, talk: typed, shapes: !typed))
            }
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

    private var startingWhere: String {
        if case .running(_, let asked?) = jobs.states[TripJobs.startKey], !asked.isEmpty { return asked }
        return "a trip"
    }

    /// "Checking opening hours on your dates · 3 of 5 done", or ready.
    private var startingLine: String {
        if jobs.created[TripJobs.startKey] != nil { return "Ready — open it to choose how to do it" }
        let progress = TripDecisions.progress(jobs.startJob[TripJobs.startKey])
        guard progress.total > 0 else { return "Getting started…" }
        return [progress.current, progress.count].compactMap { $0 }.joined(separator: " · ")
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

    /// The same, as one sentence for a menu's footer.
    static func words(refreshedAt: Date?, online: Bool, queued: Int) -> String {
        let line = TripSavedLine(refreshedAt: refreshedAt, online: online, queued: queued).line
        guard queued > 0 else { return line }
        return line + (queued == 1 ? " · 1 update waiting to send" : " · \(queued) updates waiting to send")
    }
}

// MARK: - One trip

struct TripScreen: View {
    let tripId: String
    var talk = false
    /// v8: just made by the guided start — open on its shapes.
    var shapes = false
    @ObservedObject private var store = TripStore.shared
    @EnvironmentObject private var router: Router
    @State private var sheet: Sheet?
    @State private var opened = false
    @State private var confirmingDelete = false
    @State private var deleteFailure: String?
    @Environment(\.dismiss) private var dismiss

    /// One sheet at a time — never a sheet over a sheet.
    enum Sheet: Identifiable {
        /// The conversation, at half height; with words to start from.
        case converse(String?)
        /// The brief, at an item.
        case brief(String?)
        case shapes
        case compare(TripProposal, TripProposal)
        case versions

        var id: String {
            switch self {
            case .converse: return "converse"
            case .brief: return "brief"
            case .shapes: return "shapes"
            case .compare(let a, let b): return "compare:\(a.id):\(b.id)"
            case .versions: return "versions"
            }
        }
    }

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
            if let bundle = store.bundles[tripId], bundle.can.mayDelete || (TripDecisions.speaksV8(bundle) && TripDecisions.canDecide(bundle.can)) {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if TripDecisions.speaksV8(bundle) && TripDecisions.canDecide(bundle.can) {
                            Button { sheet = .brief(nil) } label: { Label("The brief", systemImage: "list.bullet.rectangle") }
                            Button { sheet = .versions } label: { Label("Plan history", systemImage: "clock.arrow.circlepath") }
                        }
                        // Only whoever started the trip may delete it (the site's `canDelete`).
                        if bundle.can.mayDelete {
                            Button(role: .destructive) { confirmingDelete = true } label: {
                                Label("Delete trip", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("trip-more")
                }
            }
        }
        .confirmationDialog(
            "Delete \(store.bundles[tripId]?.trip.title ?? "this trip")?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete trip", role: .destructive) {
                Task {
                    if let failure = await store.delete(tripId) {
                        SRHaptic.bad()
                        deleteFailure = failure
                    } else {
                        SRHaptic.ok()
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The plan, the stops, the bookings and the conversation go for everyone in the family. This can't be undone.")
        }
        .alert("The trip was not deleted", isPresented: Binding(get: { deleteFailure != nil }, set: { if !$0 { deleteFailure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteFailure ?? "")
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .converse(let draft):
                TripConverseSheet(tripId: tripId, date: conversationDate, initialDraft: draft) { proposal in
                    // Preview from the conversation: the day's map, with it drawn.
                    sheet = nil
                    if let date = TripDecisions.focusDate(proposal) {
                        router.today.append(TripDayRef(tripId: tripId, date: date, preview: proposal.id))
                    }
                }
                // Half height, so the plan stays in view — and stays usable.
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
            case .brief(let focus):
                TripBriefSheet(tripId: tripId, focus: focus) { words in
                    sheet = .converse(words)
                }
                .presentationDetents([.medium, .large])
            case .shapes:
                NavigationStack { TripShapePager(tripId: tripId) }
                    .presentationDetents([.large])
            case .compare(let a, let b):
                NavigationStack { TripCompareView(left: a, right: b, tripId: tripId) }
                    .presentationDetents([.large])
            case .versions:
                NavigationStack { TripVersionsView(tripId: tripId) }
                    .presentationDetents([.medium, .large])
            }
        }
        .task {
            await store.fetch(tripId)
            guard !opened else { return }
            opened = true
            if shapes {
                // Just made by the guided start: choose how to do it.
                sheet = .shapes
            } else if talk {
                // A trip just made from a sentence: carry on that conversation.
                sheet = .converse(nil)
            }
        }
    }

    /// Today when the trip is on, else its first day.
    private var conversationDate: String {
        guard let bundle = store.bundles[tripId] else { return "" }
        let today = TripClock(bundle.trip.timeZone).localDate(Date())
        return TripClock.within(today, bundle.trip.startDate, bundle.trip.endDate) ? today : bundle.trip.startDate
    }

    /// Where the trip is: what leads the page, and what it leaves out.
    enum Phase { case before, during, after }

    static func phase(_ bundle: TripBundle, today: String) -> Phase {
        if today < bundle.trip.startDate { return .before }
        if today > bundle.trip.endDate { return .after }
        return .during
    }

    /// The page by where the trip is (2026-10-16; v8 2026-10-21). Before: a
    /// planning home — the brief, the quick questions, the planner's
    /// proposals, the days, what to book. During: today, then the days.
    /// After: how it went. Questions and proposals show in any phase they
    /// exist; "Tell the planner…" stays at the bottom throughout.
    private func content(_ bundle: TripBundle) -> some View {
        let clock = TripClock(bundle.trip.timeZone)
        let today = clock.localDate(Date())
        let days = bundle.plan?.plan.days ?? []
        let shown = days.map { store.day(tripId, $0.date) ?? $0 }
        let phase = Self.phase(bundle, today: today)
        let toBook = phase == .after ? [] : TripBookAhead.items(bundle, today: today, clock: clock)
        let pastDays = days.contains { $0.date < today }
        let v8 = TripDecisions.speaksV8(bundle)
        let questions = TripDecisions.openQuestions(bundle.questions, access: bundle.can)
        let groups = TripDecisions.canDecide(bundle.can) ? TripDecisions.groups(bundle.proposals, bundle: bundle, zone: clock.zone) : []
        // A question named by a notification or a link (`sr://trips/<id>/
        // questions/<qid>`) is scrolled to: P2's `tripQuestionFocus`.
        return ScrollViewReader { scroller in
            List {
                header(bundle, phase: phase, today: today, clock: clock)
                    .padding(.top, 12)
                    .srPlainRow()

                if phase == .before {
                    if let brief = bundle.brief {
                        TripBriefStrip(tripId: tripId, brief: brief, onEdit: { sheet = .brief($0.key) }, onTalk: { sheet = .converse($0) })
                            .srPlainRow()
                    } else {
                        TripBriefCard(bundle: bundle, today: today).srPlainRow()
                    }
                }

                // What the last decision changed, with its Undo — kept on the
                // phone, so it is still here after a relaunch.
                if let change = store.lastChange(tripId) {
                    TripChangesCard(change: change, onSeeDay: { date in
                        router.today.append(TripDayRef(tripId: tripId, date: date))
                    }, onRemember: { words in
                        sheet = .converse("Remember for next trips: \(words)")
                    })
                    .padding(.vertical, 4)
                    .srPlainRow()
                }

                switch phase {
                case .before:
                    EmptyView()
                case .during:
                    if let day = shown.first(where: { $0.date == today }) {
                        NavigationLink(value: TripDayRef(tripId: tripId, date: today)) {
                            TripDayListRow(number: (shown.firstIndex(of: day) ?? 0) + 1, day: day, bundle: bundle, today: today, lead: true)
                        }
                        .srPlainRow()
                        .accessibilityIdentifier("trip-today")
                    }
                case .after:
                    if pastDays { storyLink(bundle, today: today, lead: true) }
                }

                if !questions.isEmpty {
                    TripSectionHeading(title: TripDecisions.questionsHeading(questions.count), note: "Each changes the plan")
                        .padding(.top, 8)
                        .srPlainRow()
                    // Every open question has an anchor here; the stack shows them in turn.
                    ForEach(questions.dropFirst()) { q in
                        Color.clear.frame(height: 0)
                            .id(TripQuestionFocus.anchor(q.id))
                            .listRowSeparator(.hidden)
                            .srPlainRow()
                    }
                    TripQuestionStack(questions: questions, tripId: tripId)
                        .padding(.bottom, 4)
                        .id(TripQuestionFocus.anchor(questions[0].id))
                        .srPlainRow()
                }

                ForEach(groups) { group in
                    if group.kind == .shape {
                        shapesRow(group).srPlainRow()
                    } else if group.kind == .swap, let date = group.proposals.first?.scope.date {
                        // A swap is weighed over its day's map, where Preview
                        // draws it: the card opens the day with it in the drawer.
                        swapRow(group, date: date).srPlainRow()
                    } else {
                        TripProposalPager(
                            group: group, tripId: tripId,
                            onPreview: { p in
                                if let date = TripDecisions.focusDate(p) {
                                    router.today.append(TripDayRef(tripId: tripId, date: date, preview: p.id))
                                }
                            },
                            onCompare: { a, b in sheet = .compare(a, b) }
                        )
                        .padding(.vertical, 8)
                        .srPlainRow()
                    }
                }

                if days.isEmpty {
                    Text(bundle.can.canEdit
                         ? "No plan yet. Tell the planner what you'd like, below."
                         : "No plan yet.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .srPlainRow()
                } else if phase == .before && v8 {
                    TripSectionHeading(title: "Days", note: "Tap a day for its map")
                        .padding(.top, 8)
                        .srPlainRow()
                    TripDaysGroup(days: shown, bundle: bundle, today: today) { date in
                        router.today.append(TripDayRef(tripId: tripId, date: date))
                    }
                    .srPlainRow()
                } else {
                    // The whole trip on one map: a colour a day, each day's
                    // number at its first stop. Tap one to open that day.
                    TripOverviewMap(scene: TripMapScene.overview(shown, stays: bundle.stays)) { date in
                        router.today.append(TripDayRef(tripId: tripId, date: date))
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: SR.gutter, bottom: 8, trailing: SR.gutter))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    // The days, in the map's colours — one list, not a strip of
                    // cells and a list of the same days.
                    TripHeading(text: "Days", trailing: "\(days.count)")
                        .padding(.top, 8)
                        .srPlainRow()
                    ForEach(Array(shown.enumerated()), id: \.element.date) { i, day in
                        NavigationLink(value: TripDayRef(tripId: tripId, date: day.date)) {
                            TripDayListRow(number: i + 1, day: day, bundle: bundle, today: today)
                        }
                        .srPlainRow()
                        .accessibilityIdentifier("trip-day-\(day.date)")
                    }
                }

                // Getting ready: what to book by when, and the maps for no signal.
                if !toBook.isEmpty || (phase == .before && !days.isEmpty) {
                    if phase == .before && v8 {
                        TripSectionHeading(title: "To book", note: toBook.isEmpty ? "Nothing yet" : "\(toBook.count), in date order")
                            .padding(.top, 12)
                            .srPlainRow()
                    } else {
                        TripHeading(text: phase == .before ? "Getting ready" : "Still to book", trailing: toBook.isEmpty ? nil : "\(toBook.count) to book")
                            .padding(.top, 12)
                            .srPlainRow()
                    }
                    ForEach(toBook) { item in
                        TripBookAheadRow(item: item, zone: clock.zone).srPlainRow()
                    }
                }
                if phase != .after && !days.isEmpty {
                    TripOfflineRow(tripId: tripId, title: bundle.trip.title, days: shown)
                        .srPlainRow()
                }

                if phase == .during && pastDays { storyLink(bundle, today: today, lead: false) }

                if phase != .after {
                    // The city guide the site writes, as a page of its own.
                    if bundle.guide != nil {
                        NavigationLink(value: TripGuideRef(tripId: tripId)) {
                            SRRow(title: "\(TripCityGuideCard.city(bundle.trip.destination)) guide",
                                  subtitle: "Getting around, customs, money and a few words",
                                  icon: "book.closed")
                        }
                        .srPlainRow()
                        .accessibilityIdentifier("trip-guide-link")
                    }

                    if !bundle.segments.isEmpty {
                        if phase == .before && v8 {
                            TripSectionHeading(title: "Journeys", note: journeysNote(bundle)).padding(.top, 12).srPlainRow()
                        } else {
                            TripHeading(text: "Journeys").padding(.top, 12).srPlainRow()
                        }
                        ForEach(bundle.segments) { segment in
                            SRRow(
                                title: [segment.number, segment.carrier].compactMap { $0 }.joined(separator: " · ").isEmpty
                                    ? segment.kind.capitalized : [segment.number, segment.carrier].compactMap { $0 }.joined(separator: " · "),
                                subtitle: "\(segment.from.code ?? segment.from.name) \(TripFormat.time(segment.departMin)) → \(segment.to.code ?? segment.to.name) \(TripFormat.time(segment.arriveMin)) · \(TripFormat.day(segment.departDate, zone: clock.zone))",
                                icon: segment.kind == "flight" ? "airplane" : "train.side.front.car"
                            )
                            .srPlainRow()
                        }
                    }

                    if let plan = bundle.plan, !(plan.plan.dropped.isEmpty && plan.plan.warnings.isEmpty) {
                        TripHeading(text: "Left out, and worth knowing").padding(.top, 12).srPlainRow()
                        ForEach(plan.plan.dropped, id: \.wishId) { dropped in
                            SRRow(title: bundle.wish(dropped.wishId)?.title ?? "A wish", subtitle: dropped.reason, icon: "minus.circle", tone: SR.inkMuted)
                                .srPlainRow()
                        }
                        ForEach(plan.plan.warnings, id: \.self) { warning in
                            SRRow(title: warning, icon: "exclamationmark.triangle", tone: SR.warn)
                                .srPlainRow()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .srRefreshable {
                await store.fetch(tripId)
                await store.refreshDecisions(tripId)
            }
            .safeAreaInset(edge: .bottom) {
                TripTellPlannerBar(canEdit: bundle.can.canEdit) { sheet = .converse(nil) }
            }
            .tripQuestionFocus(tripId: tripId, scroller: scroller)
            .accessibilityIdentifier(phase == .before ? "trip.planningHome" : "trip-screen")
        }
    }

    /// "Rome" and "in 5 days" before the trip (mockup 4a); otherwise the
    /// title, the dates and whose trip it is.
    @ViewBuilder
    private func header(_ bundle: TripBundle, phase: Phase, today: String, clock: TripClock) -> some View {
        if phase == .before && TripDecisions.speaksV8(bundle) {
            VStack(alignment: .leading, spacing: 4) {
                Text(TripCityGuideCard.city(bundle.trip.destination))
                    .font(SR.Text.hero(34))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let days = clock.days(from: today, to: bundle.trip.startDate) {
                    Text(days == 1 ? "tomorrow" : "in \(days) days")
                        .font(SR.Text.title(17))
                        .foregroundStyle(TripPalette.accent)
                }
                Text(([bundle.trip.title, whose(bundle)].compactMap { $0 }).joined(separator: " · "))
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(bundle.trip.title)
                    .font(SR.Text.display(26))
                    .foregroundStyle(SR.ink)
                Text(([TripFormat.range(bundle.trip.startDate, bundle.trip.endDate, zone: clock.zone), bundle.trip.destination]
                      + [whose(bundle)].compactMap { $0 }).joined(separator: " · "))
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Trip shapes on the planning home: a card that opens the pager.
    private func shapesRow(_ group: TripDecisions.ProposalGroup) -> some View {
        Button { SRHaptic.tap(); sheet = .shapes } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up")
                    .font(SR.Text.title(17))
                    .foregroundStyle(TripPalette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.heading).font(SR.Text.title(17)).foregroundStyle(SR.ink)
                    Text("Each a whole plan, checked — pick one to plan from")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").foregroundStyle(SR.inkMuted).accessibilityHidden(true)
            }
            .padding(16)
            .srGlassCard(.paper, interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .accessibilityIdentifier("trips.shapes.open")
    }

    /// A planner's swap on the planning home: what it replaces, how many
    /// ideas, and Swap — which opens the day with them over its map.
    private func swapRow(_ group: TripDecisions.ProposalGroup, date: String) -> some View {
        let zone = TripClock(store.bundles[tripId]?.trip.timeZone ?? "UTC").zone
        let first = group.proposals.first
        let when = [TripFormat.day(date, zone: zone), TripDecisions.fitParts(first?.tradeoffs.fitText).time].compactMap { $0 }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(SR.Text.title(17))
                    .foregroundStyle(TripPalette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.heading).font(SR.Text.title(17)).foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(when) · \(group.proposals.count == 1 ? "1 idea, checked" : "\(group.proposals.count) ideas, each checked")")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                    if let why = first?.why, !why.isEmpty {
                        Text(why).font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted)
                            .lineLimit(2)
                    }
                }
            }
            Button {
                SRHaptic.tap()
                router.today.append(TripDayRef(tripId: tripId, date: date, group: group.id))
            } label: { TripButtonLabel("Swap", icon: "map", fill: true) }
                .srButton(.regular)
                .accessibilityHint("Opens \(TripFormat.day(date, zone: zone)) with the ideas over its map")
                .accessibilityIdentifier("trip.swap.open")
        }
        .padding(16)
        .srGlassCard(.paper)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    /// "From your notes" when the journeys came from them.
    private func journeysNote(_ bundle: TripBundle) -> String? {
        let fromNotes = bundle.brief?.items.contains { $0.kind == "transport" && $0.origin == .notes } ?? false
        return fromNotes ? "From your notes" : nil
    }

    /// "your trip", "Sam's trip".
    private func whose(_ bundle: TripBundle) -> String? {
        bundle.trip.createdByName.map { bundle.can.role == "creator" ? "your trip" : "\($0)'s trip" }
    }

    /// v7: once a day has been, the story so far — when you were where, and
    /// the photos you took there.
    private func storyLink(_ bundle: TripBundle, today: String, lead: Bool) -> some View {
        NavigationLink(value: TripStoryRef(tripId: tripId)) {
            SRRow(title: today > bundle.trip.endDate ? "How it went" : "How it's going",
                  subtitle: "Each stop, when you were there, and your photos from it", icon: "photo.on.rectangle.angled")
        }
        .srPlainRow()
        .padding(.vertical, lead ? 6 : 0)
        .accessibilityIdentifier("trip-story-link")
    }
}

/// One day in the trip's list, in its colour on the trip's map: its number,
/// its date, the forecast once there is one, how many stops and how full —
/// in words, with the four parts of the day as one thin bar.
struct TripDayListRow: View {
    let number: Int
    let day: PlannedDay
    let bundle: TripBundle
    let today: String
    /// Today, at the head of the page: bigger.
    var lead = false
    /// So a forecast that lands later shows without a reload.
    @ObservedObject private var weather = TripWeatherStore.shared
    /// The number's disc grows with the reader's text size.
    @ScaledMetric(relativeTo: .headline) private var disc: CGFloat = 28

    var body: some View {
        let zone = TripClock(bundle.trip.timeZone).zone
        let full = TripFullness.of(day, bundle: bundle)
        let isToday = day.date == today
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(TripPalette.day(number - 1))
                Text("\(number)")
                    .font(SR.Text.label(lead ? 15 : 13).monospacedDigit())
                    .foregroundStyle(Color.white)
            }
            .frame(width: disc * (lead ? 34.0 / 28 : 1), height: disc * (lead ? 34.0 / 28 : 1))
            .overlay { if isToday && !lead { Circle().stroke(SR.accent, lineWidth: 2).padding(-3) } }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(lead ? "Today" : TripFormat.day(day.date, zone: zone) + (isToday ? " · today" : ""))
                        .font(lead ? SR.Text.display(22) : SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                    Spacer(minLength: 6)
                    if let sky = weather.day(bundle.trip.id, day.date) {
                        Image(systemName: TripWeatherWords.symbol(sky.code)).symbolRenderingMode(.multicolor)
                        if let high = sky.highC {
                            Text("\(Int(high.rounded()))°").font(SR.Text.secondary(13)).foregroundStyle(SR.inkSecondary)
                        }
                    }
                }
                Text(summary(full.band))
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(full.band == "overfull" ? SR.error : SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // The four parts of the day, each as wide as the stops it holds.
                HStack(spacing: 2) {
                    ForEach(TripStages.groups(day, wishes: bundle.wishes), id: \.stage) { g in
                        Capsule()
                            .fill(g.stage.color.opacity(g.indexes.isEmpty ? 0.25 : 1))
                            .frame(width: CGFloat(max(1, g.indexes.count)) * 12, height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, lead ? 10 : 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "6 stops · 09:00–18:40 · a full day".
    private func summary(_ band: String) -> String {
        let visits = day.stops.filter { $0.kind != .stay }.count
        guard let first = day.stops.first, let last = day.stops.last else { return "Nothing planned" }
        let feel = bundle.trip.dayLoads?[day.date] == "light" ? "an easy day" : TripFullness.sentence(band).lowercased()
        return "\(visits) stop\(visits == 1 ? "" : "s") · \(TripFormat.time(first.departMin))–\(TripFormat.time(last.arriveMin)) · \(feel)"
    }
}

/// The city guide the site writes for the trip, as a page of its own:
/// getting around, the neighbourhoods, customs, money, a few words.
struct TripGuideScreen: View {
    let tripId: String
    @ObservedObject private var store = TripStore.shared

    var body: some View {
        Group {
            if let bundle = store.bundles[tripId], let guide = bundle.guide {
                List {
                    TripCityGuideCard(guide: guide)
                        .padding(.top, 8)
                        .srPlainRow()
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .navigationTitle("\(TripCityGuideCard.city(bundle.trip.destination)) guide")
            } else {
                SREmpty(title: "No guide for this trip yet", icon: "book.closed")
            }
        }
        .srPaper()
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("trip-guide")
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
            TripHeading(text: "Getting around")
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
                TripHeading(text: "Where you'll be").padding(.top, 10)
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
                TripHeading(text: "Good to know").padding(.top, 10)
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
                    TripHeading(text: "A few words").padding(.top, 10)
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
            line("person.2", travellers.isEmpty ? nil : travellers.map(Self.traveller).joined(separator: " · "))
            line("figure.walk", "\(bundle.trip.pace.rawValue.capitalized) pace" + (bundle.trip.modes.isEmpty ? "" : " · " + bundle.trip.modes.map { TripLegPicker.name($0).lowercased() }.joined(separator: ", ")))
            line("star", musts.isEmpty ? nil : "Musts: " + musts.prefix(4).joined(separator: ", ") + (musts.count > 4 ? " +\(musts.count - 4)" : ""))
            line("ticket", booked == 0 ? nil : "\(booked) booked")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip-brief")
    }

    /// "Sam, 9". Nothing the planner remembers about them is shown —
    /// memories never reach the app (v5).
    static func traveller(_ t: TravellerProfile.Traveller) -> String {
        t.age.map { "\(t.name), \(Int($0))" } ?? t.name
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

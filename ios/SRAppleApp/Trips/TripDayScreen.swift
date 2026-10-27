import SwiftUI
import CoreLocation

/// One day of a trip, READ-ONLY, MAP-LED (red team 2026-10-15, proposal A).
///
/// The day is a map — numbered pins in the colours of the day's four parts,
/// each leg drawn as it is travelled (dotted walk, petrol transit, solid
/// ride, a faint dashed guess where nothing was routed) — with a drawer over
/// it. Pulled down, the drawer is the glance a person standing in Rome
/// wants: where they are, how long is left, when to leave and how to get to
/// the next stop — or, when something has gone wrong, that instead. Pulled
/// up, it is the day in its four parts, the next leg and what to know at
/// the next stop opened out in place. Each thing is said once (2026-10-16):
/// the weather is a chip on the map, the housekeeping is the ••• menu.
///
/// Tapping a pin brings up that stop; an off-plan choice is shown on the map
/// over the current plan (a dashed ghost) before it is used.
///
/// Changing the plan is "Edit plan": the planning conversation
/// (`TripConverseSheet`). Everything reads from the saved bundle, so it all
/// works offline.
///
/// v8: a stop's Swap asks the server for checked alternatives and shows them
/// in the drawer as the proposal pager; Preview draws one as the day's new
/// route over the plan as it stands (dashed) — Use this, or Keep the plan.
/// "Change this day" asks for a lighter day, a rainy-day version, or a swap
/// with another day, the same way.
struct TripDayScreen: View {
    let tripId: String
    let date: String
    /// v8: a proposal to show on the map as the day opens (Preview from the
    /// trip page or the conversation).
    var preview: String? = nil
    /// v8: a group of alternatives to open the drawer on (a planner's swap
    /// from the trip page).
    var group: String? = nil
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var offPlan = TripOffPlan.shared
    @ObservedObject private var trail = TripTrail.shared
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var following: PlannedRouteDetail?
    /// v8: one sheet at a time — the conversation, or two to compare.
    @State private var sheet: DaySheet?
    /// v8: the group of alternatives shown in the drawer (a swap, a day's versions).
    @State private var shownGroup: String?
    /// v8: a proposal drawn on the map, by id.
    @State private var previewProposal: String?
    @State private var previewTaken = false
    /// v8: asking for alternatives — which stop, or which day variant.
    @State private var asking: String?
    @State private var askFailure: String?
    @State private var toast: TripChangeRecord?
    /// On show, not covered by a pushed stop or a sheet: the map's blue dot
    /// (its own GPS) runs only then.
    @State private var onScreen = false
    @State private var detent: TripDrawerDetent?
    @State private var covered: CGFloat = 230
    /// A stop picked on the map (or "Show on the map").
    @State private var selected: String?
    /// An off-plan choice being looked at on the map, by its id.
    @State private var previewing: String?
    @State private var frameToken = 0
    @State private var followToken = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let bundle = store.bundles[tripId], let day = store.day(tripId, date) {
                content(bundle, day, now: context.date)
            } else {
                SREmpty(
                    title: "This day is not on the phone",
                    icon: "icloud.and.arrow.down",
                    message: "Open the trip with a connection once and every day is saved for offline use."
                )
            }
        }
        .srGround(.warm)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .navigationTitle(store.clock(tripId).map { TripFormat.day(date, zone: $0.zone) } ?? "Day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let bundle = store.bundles[tripId], let day = store.day(tripId, date) {
                ToolbarItem(placement: .topBarTrailing) {
                    TripDayMoreMenu(tripId: tripId, day: day, tripTitle: bundle.trip.title, allDays: { dismiss() })
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // v5: the creator and parents change the plan; anyone else
                // may still ask the planner for advice.
                Button { SRHaptic.tap(); sheet = .converse } label: {
                    Text(store.bundles[tripId]?.can.canEdit == false ? "Ask" : "Edit plan").font(SR.Text.title(15))
                }
                .accessibilityIdentifier("trip-edit-plan")
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .converse:
                TripConverseSheet(tripId: tripId, date: date) { proposal in
                    sheet = nil
                    look(atProposal: proposal)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .compare(let a, let b):
                NavigationStack {
                    TripCompareView(left: a, right: b, tripId: tripId) { change in
                        settled(change)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                TripChangesToast(change: toast).padding(.top, 52)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast?.id)
        .onAppear {
            guard !previewTaken else { return }
            previewTaken = true
            if let preview {
                previewProposal = preview
                detent = .peek
            } else if let group {
                shownGroup = group
                detent = .half
            }
        }
        .fullScreenCover(item: $following) { detail in
            FollowRouteScreen(detail: detail)
        }
        .task {
            if let bundle = store.bundles[tripId] { TripWeatherStore.shared.refresh(bundle) }
            TripLive.shared.refresh()
            TripArrivals.shared.refresh()
            TripOffPlan.shared.refresh()
            TripOffPlan.shared.requestFix()
            await store.refreshIfStale()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            TripJobs.shared.resume()
            TripLive.shared.refresh()
            TripOffPlan.shared.requestFix()
            Task { await store.refreshIfStale() }
        }
        .accessibilityIdentifier("trip-day-screen")
    }

    // MARK: The day

    private func content(_ bundle: TripBundle, _ day: PlannedDay, now: Date) -> some View {
        let clock = TripClock(bundle.trip.timeZone)
        let isToday = clock.localDate(now) == date
        let nowMin = clock.minutes(now)
        let marks = store.marks(tripId)
        let progress = TripProgress.of(day: day, marks: marks, nowMin: nowMin, clock: clock)
        let missed = TripWords.missedSlots(day: day, progress: isToday ? progress : nil, nowMin: isToday ? nowMin : nil)
        // Another day: its first stage (on an arrival day, the transfer).
        let nextIndex = isToday ? progress.next : (day.stops.count > 1 ? 1 : nil)
        let nextId = isToday ? nextIndex.flatMap { $0 < day.stops.count ? day.stops[$0].id : nil } : nil
        let choice = previewChoice
        // v8: a proposal on show takes the map; else an off-plan choice.
        let proposal = previewProposal.flatMap { id in bundle.proposals?.first { $0.id == id } }
        let proposalDay = proposal.flatMap { TripDecisions.previewDay($0, date: date) }
        let preview = proposalDay ?? choice.flatMap(previewDay)
        let shown = preview ?? day
        let group = shownGroup.flatMap { id in
            TripDecisions.groups(bundle.proposals, bundle: bundle, zone: clock.zone).first { $0.id == id }
        }
        let picked = selected.flatMap { id in shown.stops.first { $0.id == id } }
        // A meal's option picked on the map: the meal and the place.
        let pickedMeal: (stop: PlannedStop, option: MealOption)? = selected.flatMap(TripMapScene.mealOption(pinId:)).flatMap { ref in
            guard let stop = shown.stops.first(where: { $0.id == ref.stopId }),
                  let option = stop.mealOptions?.first(where: { $0.id == ref.optionId }) else { return nil }
            return (stop, option)
        }
        // What is behind you is off the map: a day gone by has no route
        // left, and today loses what the phone has walked.
        let gone = date < clock.localDate(now)
        let scene = TripMapScene.day(
            day, bundle: bundle, done: gone ? Set(day.stops.map(\.id)) : Set(progress.doneStopIds), nextId: nextId,
            selectedId: picked?.id ?? (pickedMeal == nil ? nil : selected), preview: preview,
            walked: isToday ? trail.walked(tripId, date) : nil
        )
        // The glance over a big map on the day itself — unless something has
        // gone wrong, which is said first and must not sit under the fold.
        let offPlanToday = isToday ? offPlan.prompt.flatMap { $0.tripId == tripId && $0.date == date ? $0 : nil } : nil
        let alarmed = !missed.isEmpty || offPlanToday != nil
        let drawerAt = Binding<TripDrawerDetent>(
            get: { detent ?? (isToday && !alarmed ? .peek : .half) },
            set: { detent = $0 }
        )
        return ZStack {
            TripSceneMap(
                scene: scene,
                showsUser: isToday && onScreen && scenePhase == .active,
                marker: SRDemo.isOn ? TripDemo.here : nil,
                bottomInset: covered,
                frameToken: frameToken,
                focus: picked?.location ?? pickedMeal?.option.place.location,
                followToken: followToken,
                onTap: { pin in pick(pin?.id) }
            )
            .ignoresSafeArea(edges: .bottom)
            .accessibilityLabel("Map of the day: \(day.stops.filter { $0.kind == .wish }.count) numbered stops")
            .accessibilityIdentifier("trip-day-map")

            mapControls(scene: scene, isToday: isToday)

            if let proposal, proposalDay != nil {
                legend(proposal)
            }

            // The weather and the light: a chip on the map, not lines in the drawer.
            VStack {
                HStack {
                    TripDaySky(tripId: tripId, date: date, bundle: bundle,
                               fromMin: isToday ? nowMin : (day.stops.first?.departMin ?? 480),
                               toMin: day.stops.last?.arriveMin ?? 1320)
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            TripDrawer(detent: drawerAt, covered: $covered) {
                if let proposal, proposalDay != nil {
                    proposalBar(proposal)
                } else if let choice, let preview {
                    previewBar(choice, preview: preview, day: day)
                } else if let asking {
                    askingBar(asking, day: day)
                } else if let group {
                    TripProposalPager(
                        group: group, tripId: tripId,
                        onPreview: { look(atProposal: $0) },
                        onCompare: { a, b in sheet = .compare(a, b) },
                        onChange: { settled($0) },
                        onRegroup: { shownGroup = $0 }
                    )
                    closeGroup
                } else if let pickedMeal {
                    TripMealPeek(
                        tripId: tripId, day: shown, stop: pickedMeal.stop, option: pickedMeal.option, bundle: bundle,
                        close: { pick(nil) }
                    )
                } else if let picked {
                    TripStopPeek(
                        stop: picked, day: preview ?? day, bundle: bundle, date: date, clock: clock,
                        number: TripMapScene.numbers(preview ?? day)[picked.id],
                        stage: stage(of: picked, in: preview ?? day, bundle),
                        canOpen: preview == nil,
                        following: $following,
                        close: { pick(nil) },
                        onSwap: preview == nil && TripDecisions.canSwap(picked, bundle: bundle) ? { swap(picked) } : nil
                    )
                    if let askFailure {
                        Text(askFailure).font(SR.Text.secondary(13)).foregroundStyle(TripPalette.overdue)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !missed.isEmpty {
                    // Something gone wrong takes the glance's place; it is
                    // never one more card above the plan.
                    missedCard(missed)
                } else if let offPlanToday {
                    TripOffPlanCard(prompt: offPlanToday, part: .head)
                } else if isToday {
                    TripHereCard(day: day, progress: progress, nowMin: nowMin, clock: clock)
                    if let next = nextIndex, next > 0, next < day.stops.count, let leg = day.leg(before: next) {
                        TripLegGlance(leg: leg, from: day.stops[next - 1], to: day.stops[next], bundle: bundle, date: date, following: $following)
                    }
                } else {
                    dayHeader(day, clock: clock, past: date < clock.localDate(now))
                }
            } content: {
                // Each thing said once. The next leg and what to know at the
                // next stop open out in the list, where they happen; the
                // offline map, "All days" and how fresh the plan is live in
                // the ••• menu.
                VStack(alignment: .leading, spacing: 20) {
                    notes(bundle)
                    if let offPlanToday {
                        // Its headline is the drawer's header (unless a missed
                        // slot has that); the ways on are here.
                        TripOffPlanCard(prompt: offPlanToday, previewing: previewing, part: missed.isEmpty ? .choices : .all) { picked in look(at: picked) }
                    }
                    // Arriving today: the flight or train is the day's first stage.
                    ForEach(bundle.segments.filter { $0.arriveDate == date && $0.direction != "return" }) { segment in
                        TripTransportCard(segment: segment, arriving: true)
                    }
                    // The next leg opens out today; on another day only an
                    // arrival's transfer does — a plan read ahead stays quiet.
                    let arriving = bundle.segments.contains { $0.arriveDate == date && $0.direction != "return" }
                    rest(bundle, day, marks: marks, progress: isToday ? progress : nil,
                         nextIndex: isToday || arriving ? nextIndex : nil)
                    // Leaving today: the flight or train is the day's last stage.
                    ForEach(bundle.segments.filter { $0.departDate == date && $0.direction != "outbound" }) { segment in
                        TripTransportCard(segment: segment, arriving: false)
                    }
                }
            }
        }
        .srRefreshable {
            await store.fetch(tripId)
            await store.refreshDecisions(tripId)
        }
        // A proposal decided elsewhere stops being shown.
        .onChange(of: bundle.proposals?.map(\.id) ?? []) { _, ids in
            if let previewProposal, !ids.contains(previewProposal) { self.previewProposal = nil; frameToken += 1 }
            if let shownGroup, !(bundle.proposals ?? []).contains(where: { $0.groupId == shownGroup }) { self.shownGroup = nil }
        }
        // A choice that has gone (applied, dismissed, re-worked) stops being shown.
        .onChange(of: offPlan.choices.map(\.id)) { _, ids in
            if let previewing, !ids.contains(previewing) { self.previewing = nil; frameToken += 1 }
        }
    }

    // MARK: The map's own buttons

    /// Fit the day; on the day itself, find me. A note when some lines are
    /// guesses, so a dashed one is not read as the way to go.
    private func mapControls(scene: TripMapScene.Scene, isToday: Bool) -> some View {
        let guessing = scene.lines.contains { $0.style == TripMapScene.guess }
        return VStack(alignment: .trailing, spacing: 8) {
            Spacer()
            HStack(alignment: .bottom) {
                if guessing {
                    Label("Dashed: a straight line, not the route", systemImage: "line.diagonal")
                        .font(SR.Text.mono(11))
                        .foregroundStyle(SR.inkSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .srGlass(.paper, in: Capsule())
                        .accessibilityIdentifier("trip-map-guess-note")
                }
                Spacer()
                VStack(spacing: 8) {
                    if isToday {
                        mapButton("location.fill", label: "Show where I am") { followToken += 1 }
                    }
                    mapButton("arrow.up.left.and.arrow.down.right", label: "Fit the day") { pick(nil); frameToken += 1 }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, covered + 12)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: covered)
    }

    private func mapButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button { SRHaptic.select(); action() } label: {
            Image(systemName: symbol)
                .font(SR.Text.title(15))
                .foregroundStyle(SR.ink)
                .frame(width: 44, height: 44)
                .srGlass(.paper, in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Picking and previewing

    private func pick(_ stopId: String?) {
        if stopId != nil { SRHaptic.select() }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            selected = stopId
            if stopId != nil { detent = .peek }
        }
    }

    /// An off-plan choice: shown on the map first when it changes today;
    /// a whole-trip one that leaves today alone is used straight away.
    private func look(at choice: TripOffPlan.Choice) {
        guard previewDay(choice) != nil else {
            offPlan.apply(choice)
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            previewing = choice.id
            selected = nil
            detent = .peek
        }
        frameToken += 1
    }

    private var previewChoice: TripOffPlan.Choice? {
        previewing.flatMap { id in offPlan.choices.first { $0.id == id } }
    }

    private func previewDay(_ choice: TripOffPlan.Choice) -> PlannedDay? {
        switch choice {
        case .day(let option): return option.day
        case .trip(let option): return option.days.first { $0.date == date }
        }
    }

    /// "Shown on the map: Skip the Pantheon" — use it, or keep the plan.
    private func previewBar(_ choice: TripOffPlan.Choice, preview: PlannedDay, day: PlannedDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proposed — shown on the map")
                .font(SR.Text.label(12))
                .foregroundStyle(SR.accentDeep)
            Text(choice.label)
                .font(SR.Text.display(19))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(choice.detail + " · the dashed line is the plan as it stands")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    SRHaptic.ok()
                    offPlan.apply(choice)
                    previewing = nil
                    frameToken += 1
                } label: { TripButtonLabel("Use this", icon: "checkmark", fill: true) }
                    .srButton(.prominent)
                    .accessibilityIdentifier("trip-preview-use")
                Button {
                    SRHaptic.select()
                    previewing = nil
                    frameToken += 1
                } label: { TripButtonLabel("Keep the plan") }
                    .srButton(.regular)
                    .accessibilityIdentifier("trip-preview-cancel")
            }
            .controlSize(.small)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-preview")
    }

    private func stage(of stop: PlannedStop, in day: PlannedDay, _ bundle: TripBundle) -> DayStage {
        let stages = TripStages.stages(day, wishes: bundle.wishes)
        guard let i = day.index(of: stop.id), i < stages.count else { return .morning }
        return stages[i]
    }

    // MARK: Pieces

    @ViewBuilder
    private func notes(_ bundle: TripBundle) -> some View {
        if let local = store.localDay(tripId, date) {
            Label("Re-planned on this phone: \(local.label)", systemImage: "iphone")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkSecondary)
        }
        ForEach(store.siteChanges(tripId), id: \.self) { change in
            Label(change, systemImage: "exclamationmark.bubble")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A missed booking is the one thing on the day that cannot be caught
    /// up by walking faster: said first, in the error colour.
    private func missedCard(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines, id: \.self) { line in
                Label(line, systemImage: "exclamationmark.octagon.fill")
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("A booked slot can't be moved. Check the booking for a later entry, or change the plan without it.")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.bundles[tripId]?.can.canEdit != false {
                Button { SRHaptic.tap(); sheet = .converse } label: {
                    TripButtonLabel("Edit plan", icon: "bubble.left.and.text.bubble.right")
                }
                .srButton(.prominent)
            }
        }
        // Danger is said by its icon and its red — the coloured bar at a
        // card's edge means a part of the day, and only that.
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip-missed-slot")
    }

    /// Another day than today: what it holds, said once.
    private func dayHeader(_ day: PlannedDay, clock: TripClock, past: Bool) -> some View {
        let visits = day.stops.filter { $0.kind != .stay }.count
        let span = day.stops.first.map { first in
            "\(TripFormat.time(first.departMin))–\(TripFormat.time(day.stops.last?.arriveMin ?? first.departMin))"
        } ?? ""
        let easy = store.bundles[tripId]?.trip.dayLoads?[date] == "light"
        return VStack(alignment: .leading, spacing: 2) {
            Text(past ? "How the day went" : (easy ? "An easy day" : "The plan"))
                .font(SR.Text.secondary(14))
                .foregroundStyle(easy && !past ? SR.good : SR.inkMuted)
            Text("\(visits) stop\(visits == 1 ? "" : "s") · \(span)")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func rest(_ bundle: TripBundle, _ day: PlannedDay, marks: [String: TripStopMark], progress: TripProgress?, nextIndex: Int?) -> some View {
        let numbers = TripMapScene.numbers(day)
        let easy = bundle.trip.dayLoads?[date] == "light"
        return VStack(alignment: .leading, spacing: 0) {
            TripHeading(text: progress == nil ? "The day" : "Today",
                        trailing: "\(day.stops.filter { $0.kind != .stay }.count) stops" + (easy ? " · easy day" : ""))
                .padding(.bottom, 4)
                .accessibilityIdentifier(easy ? "trip-easy-day" : "trip-day-heading")
            // v4: the day in its four stages, each with its own look.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(TripStages.groups(day, wishes: bundle.wishes), id: \.stage) { group in
                    TripStageBand(stage: group.stage, trailing: span(day, group.indexes), empty: group.indexes.isEmpty) {
                        ForEach(group.indexes, id: \.self) { index in
                            stopRow(bundle, day, index, number: numbers[day.stops[index].id], stage: group.stage, marks: marks, progress: progress, nextIndex: nextIndex)
                        }
                        // v5: what the family suggests for this stage, and ideas that fit it.
                        TripSlotPanel(tripId: tripId, day: day, stage: group.stage, indexes: group.indexes, bundle: bundle, showsAsk: false)
                    }
                }
            }
            ForEach(day.warnings.filter { !$0.hasPrefix("Missed your ") }, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.warn)
                    .padding(.top, 8)
            }
            // One way to ask for ideas, for any part of the day.
            HStack(spacing: 10) {
                TripDayIdeasMenu(tripId: tripId, day: day, bundle: bundle)
                // v8: a lighter day, a rainy-day version, a swap with another day.
                if TripDecisions.speaksV8(bundle) && TripDecisions.canDecide(bundle.can) {
                    dayMenu(bundle)
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: v8: alternatives in the drawer

    /// One sheet at a time on the day.
    enum DaySheet: Identifiable {
        case converse
        case compare(TripProposal, TripProposal)

        var id: String {
            switch self {
            case .converse: return "converse"
            case .compare(let a, let b): return "compare:\(a.id):\(b.id)"
            }
        }
    }

    /// "Change this day": the day's own versions, as proposals to preview.
    private func dayMenu(_ bundle: TripBundle) -> some View {
        let others = (bundle.plan?.plan.days ?? []).map(\.date).filter { $0 != date }
        let zone = TripClock(bundle.trip.timeZone).zone
        return Menu {
            Button { ask(.day(.lighter, date: date), key: "day:lighter") } label: { Label(DayVariant.lighter.label, systemImage: DayVariant.lighter.symbol) }
            Button { ask(.day(.rainy, date: date), key: "day:rainy") } label: { Label(DayVariant.rainy.label, systemImage: DayVariant.rainy.symbol) }
            if !others.isEmpty {
                Menu {
                    ForEach(others, id: \.self) { other in
                        Button(TripFormat.day(other, zone: zone)) { ask(.day(.swapDays, date: date, withDate: other), key: "day:swap") }
                    }
                } label: { Label(DayVariant.swapDays.label, systemImage: DayVariant.swapDays.symbol) }
            }
        } label: {
            TripButtonLabel("Change this day", icon: "wand.and.stars")
        }
        .srButton(.regular)
        .disabled(asking != nil || !(TripNetwork.shared.online || SRDemo.isOn))
        .accessibilityIdentifier("trip.day.change")
    }

    /// Swap: checked alternatives for this stop, into the drawer.
    private func swap(_ stop: PlannedStop) {
        ask(.swap(stopId: stop.id, wishId: stop.wishId, date: date), key: "swap:\(stop.id)", label: stop.title)
    }

    private func ask(_ request: ProposalRequest, key: String, label: String? = nil) {
        SRHaptic.tap()
        askFailure = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            asking = label.map { "Finding swaps for \($0)…" } ?? "Working out another version of the day…"
            selected = nil
            shownGroup = nil
            detent = .half
        }
        Task {
            let (group, failure) = await store.requestProposals(request, tripId: tripId, busyKey: key)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                asking = nil
                if let first = group.first {
                    shownGroup = first.groupId
                    detent = .half
                } else {
                    askFailure = failure
                }
            }
        }
    }

    private func askingBar(_ line: String, day: PlannedDay) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(line)
                .font(SR.Text.title(16))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var closeGroup: some View {
        Button {
            SRHaptic.select()
            withAnimation { shownGroup = nil; detent = nil }
        } label: { TripButtonLabel("Keep the plan as it is") }
            .srButton(.regular)
            .controlSize(.small)
            .accessibilityIdentifier("trip.swap.close")
    }

    /// Preview: the proposal's version of the day on the map, the plan as it
    /// stands dashed under it.
    private func look(atProposal p: TripProposal) {
        guard let focus = TripDecisions.focusDate(p) else { return }
        guard focus == date else {
            router.today.append(TripDayRef(tripId: tripId, date: focus, preview: p.id))
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            previewProposal = p.id
            selected = nil
            detent = .peek
        }
        frameToken += 1
    }

    /// "Proposed — shown on the map": Use this, or Keep the plan.
    private func proposalBar(_ p: TripProposal) -> some View {
        let zone = store.clock(tripId)?.zone ?? .current
        return VStack(alignment: .leading, spacing: 8) {
            Text("Proposed — shown on the map")
                .font(SR.Text.label(12))
                .foregroundStyle(TripPalette.accent)
            Text(p.title)
                .font(SR.Text.display(19))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(TripDecisions.summary(p.diff, zone: zone) + " · the dashed line is the plan as it stands")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if TripDecisions.canDecide(store.bundles[tripId]?.can ?? .owner) {
                HStack(spacing: 10) {
                    Button { use(p) } label: {
                        if store.isBusy(p.id) { ProgressView().tint(TripPalette.onAccent).frame(maxWidth: .infinity) } else {
                            TripButtonLabel("Use this", icon: "checkmark", fill: true)
                        }
                    }
                    .tripPrimary()
                    .accessibilityIdentifier("trip-preview-use")
                    Button {
                        SRHaptic.select()
                        previewProposal = nil
                        frameToken += 1
                    } label: { TripButtonLabel("Keep the plan", fill: true) }
                        .srButton(.regular)
                        .accessibilityIdentifier("trip-preview-cancel")
                }
            }
            if let askFailure {
                Text(askFailure).font(SR.Text.secondary(13)).foregroundStyle(TripPalette.overdue)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-preview")
    }

    private func use(_ p: TripProposal) {
        SRHaptic.tap()
        askFailure = nil
        Task {
            switch await store.accept(p, tripId: tripId) {
            case .done(let change):
                SRHaptic.ok()
                previewProposal = nil
                shownGroup = nil
                frameToken += 1
                if let change { settled(change) }
            case .stale:
                // The bundle holds the re-checked one: the map redraws it.
                askFailure = "The plan moved on since — this is the difference now. Use it?"
                frameToken += 1
            case .failed(let why):
                SRHaptic.bad()
                askFailure = why
            }
        }
    }

    /// A decision landed: say so over the map, with Undo, for a few seconds.
    private func settled(_ change: TripChangeRecord) {
        toast = change
        previewProposal = nil
        shownGroup = nil
        let id = change.id
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if toast?.id == id { toast = nil }
        }
    }

    /// What the two lines mean while a proposal is drawn.
    private func legend(_ p: TripProposal) -> some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Capsule().fill(TripPalette.accent).frame(width: 24, height: 3.5)
                        Text("With \(p.title)")
                    }
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in Capsule().fill(SR.ink.opacity(0.45)).frame(width: 6, height: 3) }
                        }
                        .frame(width: 24)
                        Text("Plan now")
                    }
                }
                .font(SR.Text.label(12))
                .foregroundStyle(SR.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .srGlass(.paper, in: RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Solid line: with \(p.title). Dashed line: the plan now.")
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 52)
    }

    @ViewBuilder
    private func stopRow(_ bundle: TripBundle, _ day: PlannedDay, _ index: Int, number: Int?, stage: DayStage, marks: [String: TripStopMark], progress: TripProgress?, nextIndex: Int?) -> some View {
        let stop = day.stops[index]
        // The leg in to the next stop, open: how to get there, by its mode.
        if index == nextIndex, index > 0, let leg = day.leg(before: index) {
            TripNextStageCard(
                leg: leg, from: day.stops[index - 1], to: stop,
                bundle: bundle, date: date, following: $following, inline: true
            )
            .padding(.leading, 60)
            .padding(.vertical, 8)
        }
        HStack(alignment: .center, spacing: 0) {
            NavigationLink(value: TripStopRef(tripId: tripId, date: date, stopId: stop.id)) {
                TripStopRow(
                    stop: stop,
                    mark: marks[stop.id],
                    booking: bundle.booking(for: stop),
                    isNext: progress?.next == index,
                    isHere: progress?.phase == TripProgress.Phase.at(index),
                    number: number,
                    stage: stage
                )
            }
            .buttonStyle(.plain)
            // Corrections in sight, not only behind a long press.
            TripStopMenu(tripId: tripId, stop: stop, showOnMap: { pick(stop.id) })
        }
        // The person knows better than a geofence: a long press, not a
        // control on the plan.
        .contextMenu {
            if stop.location != nil {
                Button { pick(stop.id) } label: { Label("Show on the map", systemImage: "map") }
            }
            TripCorrections(tripId: tripId, stop: stop)
        }
        .accessibilityIdentifier("trip-stop-\(index)")
        // What to know at the next stop, under its row.
        if index == nextIndex {
            TripStopGuideCard(stop: stop, bundle: bundle, inline: true)
                .padding(.leading, 60)
                .padding(.bottom, 6)
        }
        // v7: a meal with no place yet — its real places are pins on the
        // map; one line here, not three cards.
        if stop.awaitsMealChoice, let first = stop.mealOptions?.first {
            Button {
                pick(TripMapScene.mealOptionPinId(stop: stop.id, option: first.id))
            } label: {
                Label("\(stop.mealOptions?.count ?? 1) places to eat nearby — on the map", systemImage: "fork.knife")
                    .font(SR.Text.label(12))
                    .foregroundStyle(SR.accentDeep)
            }
            .buttonStyle(.plain)
            .padding(.leading, 60)
            .padding(.bottom, 6)
            .accessibilityHint("Shows them on the map, to choose one")
            .accessibilityIdentifier("trip-meal-choices-\(stop.mealName ?? "meal")")
        }
        // The leg out, unless it is the next one (opened above that stop).
        if let leg = day.leg(after: index), index + 1 != nextIndex {
            TripLegRow(leg: leg)
        }
    }

    /// "09:00–12:10" for a stage, from its first arrival to its last departure.
    private func span(_ day: PlannedDay, _ indexes: [Int]) -> String? {
        guard let first = indexes.first, let last = indexes.last else { return nil }
        return "\(TripFormat.time(day.stops[first].arriveMin))–\(TripFormat.time(day.stops[last].departMin))"
    }
}

// MARK: - On the map

/// A stop picked on the map, in the drawer: its number and part of the day,
/// when, what it is, its hours that day, and the way there.
struct TripStopPeek: View {
    let stop: PlannedStop
    let day: PlannedDay
    let bundle: TripBundle
    let date: String
    let clock: TripClock
    let number: Int?
    let stage: DayStage
    /// Off while a proposal is shown: its stop may exist only in the proposal.
    var canOpen = true
    @Binding var following: PlannedRouteDetail?
    let close: () -> Void
    /// v8: Swap — checked alternatives for this stop. Nil when it cannot be
    /// swapped (locked, booked, a member's phone, an older server).
    var onSwap: (() -> Void)? = nil

    var body: some View {
        let wish = bundle.wish(stop.wishId)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                if let photo = bundle.photo(for: stop) {
                    TripPhotoThumb(photo: photo, size: 52)
                        .overlay(alignment: .bottomTrailing) {
                            TripNumberBadge(number: number, symbol: TripMapScene.symbol(stop), stage: stage, stay: stop.kind == .stay, size: 22)
                                .offset(x: 6, y: 6)
                        }
                } else {
                    TripNumberBadge(number: number, symbol: TripMapScene.symbol(stop), stage: stage, stay: stop.kind == .stay, size: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stage.label) · \(TripWords.span(stop))")
                        .font(SR.Text.label(12))
                        .foregroundStyle(SR.inkMuted)
                    Text(stop.title)
                        .font(SR.Text.display(20))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                TripStopMenu(tripId: bundle.trip.id, stop: stop)
                Button { SRHaptic.select(); close() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(SR.Text.title(22))
                        .foregroundStyle(SR.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            if let line = summary(wish) {
                Text(line)
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                if canOpen {
                    NavigationLink(value: TripStopRef(tripId: bundle.trip.id, date: date, stopId: stop.id)) {
                        TripButtonLabel("Details", icon: "info.circle", fill: true)
                    }
                    .srButton(.prominent)
                    .accessibilityIdentifier("trip-peek-details")
                }
                if let onSwap {
                    Button { onSwap() } label: { TripButtonLabel("Swap", icon: "arrow.triangle.2.circlepath") }
                        .srButton(.regular)
                        .accessibilityHint("Shows checked alternatives for \(stop.title)")
                        .accessibilityIdentifier("trip.stop.swap")
                }
                if let i = day.index(of: stop.id), let leg = day.leg(before: i) {
                    let from = day.stops[i - 1]
                    if leg.mode == .walk, let route = TripDirections.route(for: leg, from: from, to: stop, tripId: bundle.trip.id, date: date) {
                        Button { SRHaptic.tap(); following = route } label: { TripButtonLabel("Walk there", icon: "figure.walk") }
                            .srButton(.regular)
                    } else if stop.location != nil {
                        Button { SRHaptic.tap(); TripDirections.openInMaps(stop, mode: leg.mode) } label: { TripButtonLabel("Directions", icon: "map") }
                            .srButton(.regular)
                    }
                }
            }
            .controlSize(.small)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-stop-peek")
    }

    /// One line on what it is: its hours that day, else what the research
    /// found, else the leg in.
    private func summary(_ wish: TripWish?) -> String? {
        var parts: [String] = []
        if let facts = wish?.facts {
            if facts.closedDates.contains(date) {
                parts.append("Closed this day")
            } else if let weekday = clock.isoWeekday(date), let ranges = facts.hours?[String(weekday)] {
                parts.append(ranges.isEmpty ? "Closed this day"
                             : "Open " + ranges.map { "\(TripFormat.time($0.openMin))–\(TripFormat.time($0.closeMin))" }.joined(separator: ", "))
            }
            if let s = facts.summary { parts.append(s) }
        } else if let guide = wish?.guide {
            parts.append(guide.summary)
        }
        if parts.isEmpty, let i = day.index(of: stop.id), let leg = day.leg(before: i) {
            parts.append("\(TripFormat.leg(leg)) from \(day.stops[i - 1].title)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The next leg in one line, for the glance: how, how long, and one button.
struct TripLegGlance: View {
    let leg: PlannedLeg
    let from: PlannedStop
    let to: PlannedStop
    let bundle: TripBundle
    let date: String
    @Binding var following: PlannedRouteDetail?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: TripFormat.symbol(leg.mode))
                .font(SR.Text.title(16))
                .foregroundStyle(SR.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text("\(TripFormat.leg(leg)) to \(to.title)")
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkSecondary)
                .lineLimit(2)
            Spacer(minLength: 6)
            if leg.mode == .walk, let route = TripDirections.route(for: leg, from: from, to: to, tripId: bundle.trip.id, date: date) {
                Button { SRHaptic.tap(); following = route } label: { TripButtonLabel("Walk", icon: "figure.walk", fill: true) }
                    .srButton(.prominent)
                    .accessibilityIdentifier("trip-glance-walk")
            } else if to.location != nil {
                Button { SRHaptic.tap(); TripDirections.openInMaps(to, mode: leg.mode) } label: { TripButtonLabel("Maps", icon: "map", fill: true) }
                    .srButton(.prominent)
            }
        }
        .controlSize(.small)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-leg-glance")
    }
}

/// A stop's number in the colour of its part of the day — the same badge as
/// its pin on the map, so the list and the map read as one.
struct TripNumberBadge: View {
    let number: Int?
    let symbol: String
    let stage: DayStage
    var stay = false
    var size: CGFloat = 26
    /// The disc grows with the reader's text size, and its number with it.
    @ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Circle().fill(stay ? Color(hex: TripMapScene.ink) : TripPalette.stage(stage))
            Circle().stroke(Color.white, lineWidth: 2)
            if let number {
                Text("\(number)")
                    .font(SR.Text.label(size * 0.46).monospacedDigit())
                    .foregroundStyle(Color.white)
            } else {
                Image(systemName: symbol)
                    .font(SR.Text.label(size * 0.4))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: size * max(1, scale), height: size * max(1, scale))
        .accessibilityHidden(true)
    }
}

// MARK: - Where you are

/// "At the Pantheon — 25 min left", leave by 14:20 and a countdown; or on
/// the way; or the day not begun or done.
struct TripHereCard: View {
    let day: PlannedDay
    let progress: TripProgress
    let nowMin: Double
    let clock: TripClock

    var body: some View {
        // The drawer is the card: no card inside it.
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if let line = subline {
                    Text(line)
                        .foregroundStyle(progress.showsBehind ? SR.error : SR.inkSecondary)
                }
                if let leave = leaveDate, leave > Date() {
                    Text("·").foregroundStyle(SR.inkMuted).accessibilityHidden(true)
                    Text("leave in")
                        .foregroundStyle(SR.accentDeep)
                    Text(timerInterval: Date()...leave, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(SR.accentDeep)
                }
            }
            .font(SR.Text.mono(13))
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("trip-now")
    }

    private var headline: String {
        switch progress.phase {
        case .at(let i):
            let stop = day.stops[i]
            if i == 0 && stop.kind == .stay && nowMin < stop.departMin {
                return "The day starts at \(TripFormat.time(stop.departMin))"
            }
            let left = stop.departMin - nowMin
            let place = stop.kind == .stay ? "At \(stop.title)" : "At \(stop.title)"
            return left >= 1 ? "\(place) — \(TripFormat.duration(minutes: left)) left" : "\(place) — time to go"
        case .heading(let i):
            return "On the way to \(day.stops[i].title)"
        case .finished:
            return "That's the day done"
        }
    }

    private var subline: String? {
        switch progress.phase {
        case .at:
            guard let leave = progress.leaveMin else { return nil }
            var line = "Leave by \(TripFormat.time(leave))"
            if progress.showsBehind { line += " · \(Int(progress.behindMin.rounded())) min behind" }
            return line
        case .heading(let i):
            var line = "Arrive \(TripFormat.time(day.stops[i].arriveMin))"
            if progress.showsBehind { line += " · \(Int(progress.behindMin.rounded())) min behind" }
            return line
        case .finished:
            return nil
        }
    }

    private var leaveDate: Date? {
        guard case .at = progress.phase, let leave = progress.leaveMin else { return nil }
        return clock.date(day.date, minutes: leave)
    }
}

// MARK: - The next stage

/// How to get to the next stop, by how you are getting there: a walk with
/// its route and steps, a line to catch, a taxi to get, a drive to hand to
/// Maps. Model-written guidance when the site has made it; plain plan
/// figures when it has not.
struct TripNextStageCard: View {
    let leg: PlannedLeg
    let from: PlannedStop
    let to: PlannedStop
    let bundle: TripBundle
    let date: String
    @Binding var following: PlannedRouteDetail?
    /// In the day's list, between two stops: no card — its mode's icon in
    /// the accent says it is the next leg (the coloured bar means a part of
    /// the day, and only that).
    var inline = false

    private var guidance: LegGuidance? { leg.guidance }

    var body: some View {
        if inline {
            inner
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("trip-next-stage")
        } else {
            SRCard { inner }
                .accessibilityIdentifier("trip-next-stage")
        }
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: inline ? 10 : 12) {
            if inline {
                Label("Next · \(TripFormat.leg(leg))", systemImage: TripFormat.symbol(leg.mode))
                    .font(SR.Text.label(12))
                    .foregroundStyle(SR.accentDeep)
            } else {
                SRSectionLabel(text: "Next · \(TripFormat.mode(leg.mode))", trailing: TripFormat.duration(seconds: leg.durationSec), prominent: true)
            }
            Text(guidance?.summary ?? "\(TripFormat.leg(leg)) to \(to.title)")
                .font(SR.Text.title(inline ? 15 : 17))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            switch leg.mode {
            case .walk: walk
            case .transit: transit
            case .taxi: taxi
            default: drive
            }
            ForEach(guidance?.tips ?? [], id: \.self) { tip in
                Label(tip, systemImage: "lightbulb")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let cost = guidance?.costText {
                // The money symbol follows the trip — no euro for Edinburgh.
                Label(cost, systemImage: TripDecisions.currencySymbol(timeZone: bundle.trip.timeZone, costText: cost))
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
            }
            if leg.estimated && guidance == nil {
                Text("Times are estimates.").font(SR.Text.secondary(12)).foregroundStyle(SR.inkMuted)
            }
        }
        .controlSize(inline ? .small : .regular)
    }

    // MARK: Walk

    @ViewBuilder
    private var walk: some View {
        // No map of its own: the day's map draws this walk, and the stop
        // screen's mode picker draws it there — one map a screen.
        let route = TripDirections.route(for: leg, from: from, to: to, tripId: bundle.trip.id, date: date)
        steps
        if let route {
            Button { SRHaptic.tap(); following = route } label: {
                TripButtonLabel("Start walking directions", icon: "figure.walk", fill: true)
            }
            .srButton(.prominent)
            .accessibilityIdentifier("trip-walk")
        }
    }

    @ViewBuilder
    private var steps: some View {
        if let steps = guidance?.steps, !steps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1)").font(SR.Text.mono(12)).foregroundStyle(SR.inkMuted).frame(minWidth: 16)
                        Text(step).font(SR.Text.body(15)).foregroundStyle(SR.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Transit

    @ViewBuilder
    private var transit: some View {
        ForEach(Array((guidance?.transit ?? []).enumerated()), id: \.offset) { _, ride in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: Self.vehicleSymbol(ride.vehicle))
                    .font(SR.Text.title(17))
                    .foregroundStyle(SR.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(ride.vehicle.capitalized) \(ride.line)")
                        .font(SR.Text.title(16)).foregroundStyle(SR.ink)
                    Text("\(ride.fromStop) → \(ride.toStop)" + (ride.stops.map { " · \(Int($0)) stop\(Int($0) == 1 ? "" : "s")" } ?? ""))
                        .font(SR.Text.secondary(14)).foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !ride.departuresMin.isEmpty {
                        Text("Next: " + ride.departuresMin.prefix(4).map(TripFormat.time).joined(separator: ", "))
                            .font(SR.Text.mono(13)).foregroundStyle(SR.accentInk)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
        if guidance?.transit == nil { steps }
        if let tickets = bundle.guide?.transitTickets {
            Label(tickets, systemImage: "ticket")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 10) {
            Button { SRHaptic.tap(); TripDirections.openInMaps(to, mode: .transit) } label: {
                TripButtonLabel("Open in Maps", icon: "map", fill: true)
            }
            .srButton(.prominent)
            if TripDirections.hasCitymapper {
                Button { SRHaptic.tap(); TripDirections.openInCitymapper(to) } label: { TripButtonLabel("Citymapper") }
                    .srButton(.regular)
            }
        }
    }

    static func vehicleSymbol(_ vehicle: String) -> String {
        switch vehicle {
        case "bus": return "bus.fill"
        case "tram": return "tram.fill"
        case "metro": return "tram.fill.tunnel"
        case "train": return "train.side.front.car"
        case "ferry": return "ferry.fill"
        default: return "arrow.triangle.swap"
        }
    }

    // MARK: Taxi

    /// How to get one here: the leg's own booking guidance, else the city's.
    @ViewBuilder
    private var taxi: some View {
        let booking = guidance?.booking ?? bundle.guide?.taxi
        if let booking {
            Text(booking.how)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            TripLinkButtons(links: booking.links, phone: booking.phone)
        } else {
            Text("No taxi advice for here yet. A rank at a big square or the station is the usual bet.")
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Button { SRHaptic.tap(); TripDirections.openInMaps(to, mode: .drive) } label: {
            TripButtonLabel("The route in Maps", icon: "map")
        }
        .srButton(.regular)
    }

    // MARK: Drive, cycle

    @ViewBuilder
    private var drive: some View {
        steps
        Button { SRHaptic.tap(); TripDirections.openInMaps(to, mode: leg.mode) } label: {
            TripButtonLabel("Directions in Maps", icon: "map", fill: true)
        }
        .srButton(.prominent)
    }
}

/// Call and app buttons from guidance. `tel:` links and http(s) only: a
/// link of any other scheme is not opened from a model's text.
struct TripLinkButtons: View {
    let links: [GuideLink]
    let phone: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let phone, let url = TripLinkButtons.telURL(phone) {
                Link(destination: url) {
                    TripButtonLabel("Call \(phone)", icon: "phone.fill", fill: true)
                }
                .srButton(.prominent)
            }
            ForEach(links.filter { TripLinkButtons.safeURL($0.url) != nil }, id: \.url) { link in
                if let url = TripLinkButtons.safeURL(link.url) {
                    Link(destination: url) {
                        TripButtonLabel(link.label, icon: url.scheme == "tel" ? "phone" : "arrow.up.right.square")
                    }
                    .srButton(.regular)
                }
            }
        }
    }

    static func safeURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              ["https", "http", "tel"].contains(scheme) else { return nil }
        return url
    }

    struct SourceLink: Hashable {
        let title: String
        let url: URL
    }

    /// Sources as links, unsafe schemes dropped, each titled.
    static func sourceLinks(_ sources: [TripSource]) -> [SourceLink] {
        sources.compactMap { s in
            safeURL(s.url).map { SourceLink(title: s.title ?? $0.host() ?? s.url, url: $0) }
        }
    }

    static func telURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }
}

/// What to know at the next stop: the guide, its links, and the booking.
struct TripStopGuideCard: View {
    let stop: PlannedStop
    let bundle: TripBundle
    /// Under the stop's own row: its name is already said.
    var inline = false

    var body: some View {
        let guide = bundle.wish(stop.wishId)?.guide
        let booking = bundle.booking(for: stop)
        if guide != nil || booking?.reference != nil {
            VStack(alignment: .leading, spacing: 8) {
                if !inline { SRSectionLabel(text: "At \(stop.title)") }
                if let ref = booking?.reference {
                    Label("Booking ref \(ref)", systemImage: "ticket")
                        .font(SR.Text.mono(13))
                        .foregroundStyle(SR.accentInk)
                        .textSelection(.enabled)
                }
                if let guide {
                    Text(guide.summary)
                        .font(inline ? SR.Text.secondary(14) : SR.Text.body(15))
                        .foregroundStyle(inline ? SR.inkSecondary : SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(inline ? Array(guide.tips.prefix(2)) : guide.tips, id: \.self) { tip in
                        Label(tip, systemImage: "checkmark.circle")
                            .font(SR.Text.secondary(14))
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !inline { TripLinkButtons(links: guide.links, phone: nil) }
                }
            }
            .accessibilityIdentifier("trip-stop-guide")
        }
    }
}

/// "I'm here", "I've left", "Skip it", "Not been yet" — corrections for
/// when arrival detection got it wrong, behind a long press.
struct TripCorrections: View {
    let tripId: String
    let stop: PlannedStop
    @ObservedObject private var store = TripStore.shared

    var body: some View {
        let mark = store.marks(tripId)[stop.id]
        if mark?.arrivedAt == nil {
            Button { store.record(.arrived, tripId: tripId, stop: stop, corrected: true) } label: {
                Label("I'm here", systemImage: "mappin.circle")
            }
        }
        if mark?.arrivedAt != nil && mark?.leftAt == nil {
            Button { store.record(.left, tripId: tripId, stop: stop, corrected: true) } label: {
                Label("I've left", systemImage: "figure.walk.departure")
            }
        }
        if mark?.skipped != true && mark?.leftAt == nil && stop.kind == .wish {
            Button { store.record(.skipped, tripId: tripId, stop: stop, corrected: true) } label: {
                Label("Skip it", systemImage: "forward")
            }
        }
        if let mark {
            Button(role: .destructive) { store.clear(stop.id, tripId: tripId) } label: {
                Label(mark.skipped ? "Not skipped after all" : "Not been yet", systemImage: "arrow.uturn.backward")
            }
        }
    }
}

// MARK: - Getting there and back

/// A flight or train as a stage of the day: number, times in each end's own
/// zone, status and delay, the booking reference, and how sure the times are.
struct TripTransportCard: View {
    let segment: TransportSegment
    /// Arriving today (the first stage) or leaving (the last).
    let arriving: Bool

    var body: some View {
        SRCard(accented: segment.status == "delayed" || segment.status == "cancelled") {
            VStack(alignment: .leading, spacing: 10) {
                SRSectionLabel(text: arriving ? "Arriving" : "Leaving", trailing: statusLine, prominent: true)
                HStack(spacing: 8) {
                    Image(systemName: symbol).foregroundStyle(SR.accent).accessibilityHidden(true)
                    Text([segment.number, segment.carrier].compactMap { $0 }.joined(separator: " · ").ifEmpty(segment.kind.capitalized))
                        .font(SR.Text.title(17))
                        .foregroundStyle(SR.ink)
                }
                HStack(alignment: .top, spacing: 12) {
                    end(segment.from, minutes: segment.departMin, label: "Departs")
                    Image(systemName: "arrow.right").foregroundStyle(SR.inkMuted).padding(.top, 18).accessibilityHidden(true)
                    end(segment.to, minutes: segment.arriveMin + (segment.delayMin ?? 0), label: segment.delayMin.map { $0 > 0 ? "Arrives (late)" : "Arrives" } ?? "Arrives")
                }
                if let ref = segment.bookingRef {
                    Label("Booking ref \(ref)", systemImage: "ticket")
                        .font(SR.Text.mono(13))
                        .foregroundStyle(SR.accentInk)
                        .textSelection(.enabled)
                }
                Text(confidenceLine)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                ForEach(TripLinkButtons.sourceLinks(segment.sources), id: \.url) { link in
                    Link(link.title, destination: link.url)
                        .font(SR.Text.secondary(13))
                }
            }
        }
        .accessibilityIdentifier("trip-transport")
    }

    private func end(_ e: TransportSegment.End, minutes: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(SR.Text.label()).foregroundStyle(SR.inkMuted)
            Text(TripFormat.time(minutes)).font(SR.Text.display(22)).foregroundStyle(SR.ink)
            Text([e.code, e.name].compactMap { $0 }.joined(separator: " · "))
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch segment.kind {
        case "flight": return arriving ? "airplane.arrival" : "airplane.departure"
        case "train": return "train.side.front.car"
        case "coach": return "bus.fill"
        case "ferry": return "ferry.fill"
        default: return "car.fill"
        }
    }

    private var statusLine: String? {
        switch segment.status {
        case "delayed": return segment.delayMin.map { "\(Int($0)) min late" } ?? "Delayed"
        case "cancelled": return "Cancelled"
        case "landed": return "Landed"
        case "departed": return "Departed"
        case "scheduled": return "On time"
        default: return nil
        }
    }

    private var confidenceLine: String {
        switch segment.confidence {
        case "live": return "Live status"
        case "researched": return "Times found online — check your booking"
        case "estimated": return "Estimated arrival — confirm your flight"
        default: return "Times as you gave them"
        }
    }
}

private extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}

// MARK: - Off the plan

/// What was noticed, what the planner makes of it, and up to three ways to
/// carry on — one tap applies one. "I'm fine" puts it away for good.
struct TripOffPlanCard: View {
    let prompt: TripOffPlan.Prompt
    /// The choice shown on the map now, by id.
    var previewing: String? = nil
    /// On the day, the headline and the planner's view are the drawer's
    /// header and the ways on sit under it: each said once.
    var part: Part = .all
    /// Given: a tap shows the choice (the day map's preview) rather than
    /// using it at once.
    var onPick: ((TripOffPlan.Choice) -> Void)? = nil
    @ObservedObject private var offPlan = TripOffPlan.shared

    enum Part { case all, head, choices }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if part != .choices { head }
            if part != .head { choices }
        }
        // Its icon and tint say what it is (red when a booked slot is at
        // risk); the coloured bar at an edge is a part of the day's alone.
        .padding(part == .all ? SR.cardPadding : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(OffPlanChrome(card: part == .all))
        .accessibilityIdentifier(part == .choices ? "trip-offplan-choices" : "trip-offplan")
    }

    private struct OffPlanChrome: ViewModifier {
        let card: Bool
        @ViewBuilder
        func body(content: Content) -> some View {
            if card { content.srGlassCard(.paper) } else { content }
        }
    }

    @ViewBuilder
    private var head: some View {
        Label(prompt.headline, systemImage: prompt.slotAtRisk ? "exclamationmark.triangle.fill" : "location.magnifyingglass")
            .font(SR.Text.title(16))
            .foregroundStyle(prompt.slotAtRisk ? SR.error : SR.ink)
            .fixedSize(horizontal: false, vertical: true)
        if let narrative = offPlan.narrative {
            Text(narrative)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(part == .head ? 3 : nil)
        }
    }

    @ViewBuilder
    private var choices: some View {
        if offPlan.loading && offPlan.choices.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("Working out ways to carry on…").font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted)
            }
        }
        ForEach(offPlan.choices) { choice in
            Button {
                if let onPick {
                    SRHaptic.select()
                    onPick(choice)
                } else {
                    SRHaptic.ok()
                    offPlan.apply(choice)
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    if previewing == choice.id {
                        Text("On the map")
                            .font(SR.Text.label(11))
                            .foregroundStyle(SR.accentDeep)
                    }
                    Text(choice.label)
                        .font(SR.Text.title(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(choice.detail)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .srGlass(.clear, in: RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous), interactive: true)
                .overlay {
                    if previewing == choice.id {
                        RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).stroke(SR.accent, lineWidth: 2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(onPick == nil ? "Applies this to the rest of the trip" : "Shows this on the map before you use it")
            .accessibilityIdentifier("trip-offplan-\(choice.id)")
        }
        HStack {
            if offPlan.offline && !offPlan.choices.isEmpty {
                Text("Worked out on the phone — no signal.").font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
            }
            Spacer()
            Button("I'm fine") { SRHaptic.select(); offPlan.dismiss() }
                .font(SR.Text.label(13))
                .accessibilityIdentifier("trip-offplan-dismiss")
        }
    }
}

// MARK: - Rows

struct TripStopRow: View {
    let stop: PlannedStop
    let mark: TripStopMark?
    let booking: TripBooking?
    let isNext: Bool
    let isHere: Bool
    /// Its number on the day's map, and its part of the day (the pin's colour).
    var number: Int? = nil
    var stage: DayStage? = nil
    /// Inside the evening band: light on dark.
    @Environment(\.tripOnDark) private var onDark

    private var ink: Color { onDark ? SR.cream : SR.ink }
    private var muted: Color { onDark ? SR.creamOnDark : SR.inkMuted }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(TripFormat.time(stop.arriveMin))
                    .font(SR.Text.mono(13))
                    .foregroundStyle(isNext || isHere ? (onDark ? SR.accentOnDark : SR.accentDeep) : ink)
                if stop.departMin - stop.arriveMin >= 1 {
                    Text(TripFormat.time(stop.departMin))
                        .font(SR.Text.mono(12))
                        .foregroundStyle(muted)
                }
            }
            .frame(minWidth: 48, alignment: .trailing)
            status
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.title)
                    .font(SR.Text.title(16))
                    .foregroundStyle(mark?.skipped == true ? muted : ink)
                    .strikethrough(mark?.skipped == true)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(stop.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var status: some View {
        if mark?.skipped == true {
            Image(systemName: "forward.circle").foregroundStyle(muted).accessibilityLabel("Skipped")
        } else if mark?.leftAt != nil {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(SR.good).accessibilityLabel("Done")
        } else if isHere {
            Image(systemName: "location.circle.fill").foregroundStyle(SR.accent).accessibilityLabel("You are here")
        } else if let stage, stop.location != nil {
            // The same badge as the stop's pin on the map.
            TripNumberBadge(number: number, symbol: TripMapScene.symbol(stop), stage: stage, stay: stop.kind == .stay, size: 22)
                .overlay {
                    if isNext { Circle().stroke(SR.accent, lineWidth: 2).padding(-3) }
                }
        } else {
            Image(systemName: TripWords.symbol(stop))
                .foregroundStyle(isNext ? SR.accent : SR.inkMuted)
                .accessibilityHidden(true)
        }
    }

    private var lines: [String] {
        var out: [String] = []
        if TripWords.isHere(stop) { out.append("Your stop — not on the original plan") }
        if TripWords.isDropBags(stop) { out.append("Leave the bags at the stay — the room comes later") }
        if stop.awaitsMealChoice { out.append("No place chosen yet") }
        if let wait = TripWords.wait(stop) { out.append(wait) }
        if let booking, booking.status == .booked {
            out.append("Booked" + (booking.reference.map { " · ref \($0)" } ?? ""))
        }
        if let arrived = mark?.arrivedAt, mark?.leftAt == nil, mark?.skipped != true {
            out.append("Arrived \(arrived.formatted(date: .omitted, time: .shortened))" + (mark?.corrected == true ? "" : " (detected)"))
        }
        return out
    }
}

struct TripLegRow: View {
    let leg: PlannedLeg
    @Environment(\.tripOnDark) private var onDark

    var body: some View {
        HStack(spacing: 12) {
            Color.clear.frame(minWidth: 48, maxHeight: 1)
            Image(systemName: TripFormat.symbol(leg.mode))
                .font(SR.Text.label(12))
                .foregroundStyle(onDark ? SR.creamOnDark : SR.inkMuted)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.secondary(12))
                .foregroundStyle(onDark ? SR.creamOnDark : SR.inkMuted)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// "12 min walk · 850 m", "about 25 min by transit". The other ways and
    /// the route are on the stop's own page.
    private var text: String {
        var out = (leg.estimated ? "about " : "") + TripFormat.leg(leg)
        if let m = leg.distanceM { out += m < 1000 ? " · \(Int((m / 10).rounded()) * 10) m" : String(format: " · %.1f km", m / 1000) }
        return out
    }
}

// MARK: - Position

/// The phone's last known fix, for `replanDay`'s `position`. Read from a
/// throwaway manager: no new permission prompt, no GPS switched on.
enum TripPosition {
    @MainActor
    static var latest: TripLatLng? {
        if SRDemo.isOn { return TripDemo.here.map { TripLatLng(lat: $0.latitude, lng: $0.longitude) } }
        guard let fix = CLLocationManager().location, fix.timestamp.timeIntervalSinceNow > -600 else { return nil }
        return TripLatLng(lat: fix.coordinate.latitude, lng: fix.coordinate.longitude)
    }
}

/// A meal's option picked on the map, in the drawer: the place and Choose.
struct TripMealPeek: View {
    let tripId: String
    let day: PlannedDay
    let stop: PlannedStop
    let option: MealOption
    let bundle: TripBundle
    let close: () -> Void
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var network = TripNetwork.shared
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("\((stop.mealName ?? "meal").capitalized) · \(TripWords.span(stop)) · one of \(stop.mealOptions?.count ?? 1) nearby")
                    .font(SR.Text.label(12))
                    .foregroundStyle(SR.inkMuted)
                Spacer()
                Button { SRHaptic.select(); close() } label: {
                    Image(systemName: "xmark.circle.fill").font(SR.Text.title(22)).foregroundStyle(SR.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            TripMealOptionCard(
                option: option,
                photo: bundle.images?[option.id],
                actionLabel: bundle.can.canEdit || bundle.can.canApprove ? "Choose" : "Suggest",
                busy: busy,
                enabled: !busy && (network.online || SRDemo.isOn),
                choose: choose
            )
            if let message {
                Text(message).font(SR.Text.secondary(12)).foregroundStyle(SR.inkSecondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-meal-peek")
    }

    private func choose() {
        guard let meal = stop.mealName else { return }
        busy = true
        let idea = TripMealChoices.idea(option, meal: meal, stop: stop, date: day.date)
        let stage: DayStage = meal == "lunch" ? .lunch : .evening
        let can = bundle.can
        Task {
            let failure: String?
            if can.canEdit || can.canApprove {
                failure = await store.add(idea, tripId: tripId, date: day.date, stage: stage)
            } else {
                failure = await store.suggest(idea.wish, tripId: tripId, date: day.date, stage: stage, note: idea.why, fitText: idea.fit)
            }
            busy = false
            if let failure {
                SRHaptic.bad()
                message = failure
            } else {
                SRHaptic.ok()
                if can.canEdit || can.canApprove { close() } else { message = "Suggested — a parent will see it." }
            }
        }
    }
}

import SwiftUI
import CoreLocation

/// One day of a trip, READ-ONLY: the plan as it is, with no inputs on it.
///
/// What a person standing in Rome wants, top to bottom (trips spec v2,
/// "Phone views"): anything that has gone wrong (off the plan, a missed
/// booking); where they are and how long is left there, with a leave-by
/// countdown; the NEXT STAGE — how to get there, by mode, with directions
/// and what is useful to know; what to know at the next stop; then the rest
/// of today as a quiet list, and the day on a map.
///
/// Changing the plan is "Edit plan": the planning conversation
/// (`TripConverseSheet`), where running late, skipping and swapping live too.
/// Everything here reads from the saved bundle, so it all works offline.
struct TripDayScreen: View {
    let tripId: String
    let date: String
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var queue = TripEventQueue.shared
    @ObservedObject private var network = TripNetwork.shared
    @ObservedObject private var offPlan = TripOffPlan.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var following: PlannedRouteDetail?
    @State private var editing = false

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
        .navigationTitle(store.clock(tripId).map { TripFormat.day(date, zone: $0.zone) } ?? "Day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { SRHaptic.tap(); editing = true } label: { Text("Edit plan").font(SR.Text.label(13)) }
                    .accessibilityIdentifier("trip-edit-plan")
            }
        }
        .sheet(isPresented: $editing) {
            TripConverseSheet(tripId: tripId, date: date)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $following) { detail in
            FollowRouteScreen(detail: detail)
        }
        .task {
            TripLive.shared.refresh()
            TripArrivals.shared.refresh()
            TripOffPlan.shared.refresh()
            TripOffPlan.shared.requestFix()
            await store.refreshIfStale()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            TripLive.shared.refresh()
            TripOffPlan.shared.requestFix()
            Task { await store.refreshIfStale() }
        }
        .accessibilityIdentifier("trip-day-screen")
    }

    private func content(_ bundle: TripBundle, _ day: PlannedDay, now: Date) -> some View {
        let clock = TripClock(bundle.trip.timeZone)
        let isToday = clock.localDate(now) == date
        let nowMin = clock.minutes(now)
        let marks = store.marks(tripId)
        let progress = TripProgress.of(day: day, marks: marks, nowMin: nowMin, clock: clock)
        let missed = TripWords.missedSlots(day: day, progress: isToday ? progress : nil, nowMin: isToday ? nowMin : nil)
        let nextIndex = isToday ? progress.next : day.stops.firstIndex { $0.kind != .stay }
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                notes(bundle)
                if isToday, let prompt = offPlan.prompt, prompt.tripId == tripId, prompt.date == date {
                    TripOffPlanCard(prompt: prompt)
                }
                if !missed.isEmpty {
                    missedCard(missed)
                }
                if bundle.trip.dayLoads?[date] == "light" {
                    Label("Easy day", systemImage: "leaf")
                        .font(SR.Text.label(13))
                        .foregroundStyle(SR.good)
                        .accessibilityLabel("Easy day: planned light, ending earlier")
                        .accessibilityIdentifier("trip-easy-day")
                }
                if isToday {
                    TripHereCard(day: day, progress: progress, nowMin: nowMin, clock: clock)
                } else {
                    dayHeader(day, clock: clock, past: date < clock.localDate(now))
                }
                if let next = nextIndex, next > 0, next < day.stops.count, let leg = day.leg(before: next) {
                    TripNextStageCard(
                        leg: leg, from: day.stops[next - 1], to: day.stops[next],
                        bundle: bundle, date: date, following: $following
                    )
                    TripStopGuideCard(stop: day.stops[next], bundle: bundle)
                }
                rest(bundle, day, marks: marks, progress: isToday ? progress : nil)
                mapCard(day, progress: progress)
                TripSavedLine(refreshedAt: store.refreshedAt, online: network.online, queued: queue.count(for: tripId))
                    .padding(.top, 4)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 12)
        }
        .srRefreshable { await store.fetch(tripId) }
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
            Text("A booked slot cannot be moved. Check the booking for a later entry, or change the plan without it.")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { SRHaptic.tap(); editing = true } label: {
                SRButtonLabel(title: "Edit plan", icon: "bubble.left.and.text.bubble.right")
            }
            .srButton(.prominent)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Capsule().fill(SR.error).frame(width: 3).padding(.vertical, 14) }
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip-missed-slot")
    }

    /// Another day than today: what it holds, said once.
    private func dayHeader(_ day: PlannedDay, clock: TripClock, past: Bool) -> some View {
        let visits = day.stops.filter { $0.kind != .stay }.count
        let span = day.stops.first.map { first in
            "\(TripFormat.time(first.departMin))–\(TripFormat.time(day.stops.last?.arriveMin ?? first.departMin))"
        } ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            Text(past ? "How the day went" : "The plan")
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
            Text("\(visits) stop\(visits == 1 ? "" : "s") · \(span)")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
        }
    }

    private func rest(_ bundle: TripBundle, _ day: PlannedDay, marks: [String: TripStopMark], progress: TripProgress?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: progress == nil ? "The day" : "The rest of today", trailing: "\(day.stops.filter { $0.kind != .stay }.count) stops")
                .padding(.bottom, 8)
            ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                NavigationLink(value: TripStopRef(tripId: tripId, date: date, stopId: stop.id)) {
                    TripStopRow(
                        stop: stop,
                        mark: marks[stop.id],
                        booking: bundle.booking(for: stop),
                        isNext: progress?.next == index,
                        isHere: progress?.phase == TripProgress.Phase.at(index)
                    )
                }
                .buttonStyle(.plain)
                // The person knows better than a geofence: a long press, not
                // a control on the plan.
                .contextMenu { TripCorrections(tripId: tripId, stop: stop) }
                .accessibilityIdentifier("trip-stop-\(index)")
                if let leg = day.leg(after: index) {
                    TripLegRow(leg: leg)
                }
            }
            ForEach(day.warnings.filter { !$0.hasPrefix("Missed your ") }, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.warn)
                    .padding(.top, 8)
            }
        }
        .opacity(0.92)
    }

    private func mapCard(_ day: PlannedDay, progress: TripProgress) -> some View {
        let nextId = progress.next.flatMap { $0 < day.stops.count ? day.stops[$0].id : nil }
        return VStack(alignment: .leading, spacing: 8) {
            TripDayMap(
                day: day,
                doneIds: Set(progress.doneStopIds),
                nextId: nextId,
                marker: SRDemo.isOn ? TripDemo.here : nil
            )
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous))
            .accessibilityLabel("Map of the day's stops")
            TripMapPackRow(tripId: tripId, day: day, title: "\(store.bundles[tripId]?.trip.title ?? "Trip") · \(date)")
        }
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
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text(headline)
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = subline {
                    Text(line)
                        .font(SR.Text.mono(13))
                        .foregroundStyle(progress.showsBehind ? SR.error : SR.inkSecondary)
                }
                if let leave = leaveDate, leave > Date() {
                    HStack(spacing: 6) {
                        Image(systemName: "timer").accessibilityHidden(true)
                        Text("Leave in")
                        Text(timerInterval: Date()...leave, countsDown: true)
                            .monospacedDigit()
                    }
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.accentDeep)
                    .accessibilityElement(children: .combine)
                }
            }
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

    private var guidance: LegGuidance? { leg.guidance }

    var body: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 12) {
                SRSectionLabel(text: "Next · \(TripFormat.mode(leg.mode))", trailing: TripFormat.duration(seconds: leg.durationSec), prominent: true)
                Text(guidance?.summary ?? "\(TripFormat.leg(leg)) to \(to.title)")
                    .font(SR.Text.title(17))
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
                    Label(cost, systemImage: "eurosign.circle")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                }
                if leg.estimated && guidance == nil {
                    Text("Times are estimates.").font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                }
            }
        }
        .accessibilityIdentifier("trip-next-stage")
    }

    // MARK: Walk

    @ViewBuilder
    private var walk: some View {
        let route = TripDirections.route(for: leg, from: from, to: to, tripId: bundle.trip.id, date: date)
        if let route {
            SRRouteMap(route: route.coordinates, interactive: false)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
                .accessibilityLabel("The walking route")
        }
        steps
        if let route {
            Button { SRHaptic.tap(); following = route } label: {
                SRButtonLabel(title: "Start walking directions", icon: "figure.walk", fill: true)
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
                    .font(.system(size: 17))
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
                SRButtonLabel(title: "Open in Maps", icon: "map", fill: true)
            }
            .srButton(.prominent)
            if TripDirections.hasCitymapper {
                Button { SRHaptic.tap(); TripDirections.openInCitymapper(to) } label: { SRButtonLabel(title: "Citymapper") }
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
            SRButtonLabel(title: "The route in Maps", icon: "map")
        }
        .srButton(.regular)
    }

    // MARK: Drive, cycle

    @ViewBuilder
    private var drive: some View {
        steps
        Button { SRHaptic.tap(); TripDirections.openInMaps(to, mode: leg.mode) } label: {
            SRButtonLabel(title: "Directions in Maps", icon: "map", fill: true)
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
                    SRButtonLabel(title: "Call \(phone)", icon: "phone.fill", fill: true)
                }
                .srButton(.prominent)
            }
            ForEach(links.filter { TripLinkButtons.safeURL($0.url) != nil }, id: \.url) { link in
                if let url = TripLinkButtons.safeURL(link.url) {
                    Link(destination: url) {
                        SRButtonLabel(title: link.label, icon: url.scheme == "tel" ? "phone" : "arrow.up.right.square")
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

    static func telURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }
}

/// What to know at the next stop: the guide, its links, and the booking.
struct TripStopGuideCard: View {
    let stop: PlannedStop
    let bundle: TripBundle

    var body: some View {
        let guide = bundle.wish(stop.wishId)?.guide
        let booking = bundle.booking(for: stop)
        if guide != nil || booking?.reference != nil {
            VStack(alignment: .leading, spacing: 8) {
                SRSectionLabel(text: "At \(stop.title)")
                if let ref = booking?.reference {
                    Label("Booking ref \(ref)", systemImage: "ticket")
                        .font(SR.Text.mono(13))
                        .foregroundStyle(SR.accentInk)
                        .textSelection(.enabled)
                }
                if let guide {
                    Text(guide.summary)
                        .font(SR.Text.body(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(guide.tips, id: \.self) { tip in
                        Label(tip, systemImage: "checkmark.circle")
                            .font(SR.Text.secondary(14))
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    TripLinkButtons(links: guide.links, phone: nil)
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

// MARK: - Off the plan

/// What was noticed, what the planner makes of it, and up to three ways to
/// carry on — one tap applies one. "I'm fine" puts it away for good.
struct TripOffPlanCard: View {
    let prompt: TripOffPlan.Prompt
    @ObservedObject private var offPlan = TripOffPlan.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(prompt.headline, systemImage: prompt.slotAtRisk ? "exclamationmark.triangle.fill" : "location.magnifyingglass")
                .font(SR.Text.title(16))
                .foregroundStyle(prompt.slotAtRisk ? SR.error : SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let narrative = offPlan.narrative {
                Text(narrative)
                    .font(SR.Text.body(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if offPlan.loading && offPlan.choices.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Working out ways to carry on…").font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted)
                }
            }
            ForEach(offPlan.choices) { choice in
                Button {
                    SRHaptic.ok()
                    offPlan.apply(choice)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
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
                    .srGlass(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Applies this to the rest of the trip")
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
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Capsule().fill(prompt.slotAtRisk ? SR.error : SR.accent).frame(width: 3).padding(.vertical, 14)
        }
        .srGlassCard(.paper)
        .accessibilityIdentifier("trip-offplan")
    }
}

// MARK: - Rows

struct TripStopRow: View {
    let stop: PlannedStop
    let mark: TripStopMark?
    let booking: TripBooking?
    let isNext: Bool
    let isHere: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(TripFormat.time(stop.arriveMin))
                    .font(SR.Text.mono(13))
                    .foregroundStyle(isNext || isHere ? SR.accentDeep : SR.ink)
                if stop.departMin - stop.arriveMin >= 1 {
                    Text(TripFormat.time(stop.departMin))
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkMuted)
                }
            }
            .frame(minWidth: 48, alignment: .trailing)
            status
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.title)
                    .font(SR.Text.title(16))
                    .foregroundStyle(mark?.skipped == true ? SR.inkMuted : SR.ink)
                    .strikethrough(mark?.skipped == true)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
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
            Image(systemName: "forward.circle").foregroundStyle(SR.inkMuted).accessibilityLabel("Skipped")
        } else if mark?.leftAt != nil {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(SR.good).accessibilityLabel("Done")
        } else if isHere {
            Image(systemName: "location.circle.fill").foregroundStyle(SR.accent).accessibilityLabel("You are here")
        } else {
            Image(systemName: TripWords.symbol(stop))
                .foregroundStyle(isNext ? SR.accent : SR.inkMuted)
                .accessibilityHidden(true)
        }
    }

    private var lines: [String] {
        var out: [String] = []
        if TripWords.isHere(stop) { out.append("Your stop — not on the original plan") }
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

    var body: some View {
        HStack(spacing: 12) {
            Color.clear.frame(minWidth: 48, maxHeight: 1)
            Image(systemName: TripFormat.symbol(leg.mode))
                .font(.system(size: 12))
                .foregroundStyle(SR.inkMuted)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.inkMuted)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        var out = TripFormat.leg(leg)
        if let m = leg.distanceM { out += m < 1000 ? " · \(Int((m / 10).rounded()) * 10) m" : String(format: " · %.1f km", m / 1000) }
        if leg.estimated { out += " · estimate" }
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

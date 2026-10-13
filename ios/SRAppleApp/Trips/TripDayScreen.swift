import SwiftUI
import CoreLocation

/// One day of a trip: what is now and next, the day as a timeline, the day
/// on a map, and the three things that go wrong on a day out — running
/// late, wanting to skip something, wanting to swap the order.
///
/// Everything is worked out on the phone from the saved bundle, so it all
/// works in airplane mode. With signal the server's options are offered too.
struct TripDayScreen: View {
    let tripId: String
    let date: String
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var queue = TripEventQueue.shared
    @ObservedObject private var network = TripNetwork.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var options: TripOptionsRequest?
    @State private var following: PlannedRouteDetail?
    @State private var askLate = false
    @State private var askSkip = false

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
        .sheet(item: $options) { request in
            TripOptionsSheet(request: request)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $following) { detail in
            FollowRouteScreen(detail: detail)
        }
        .task {
            TripLive.shared.refresh()
            TripArrivals.shared.refresh()
            await store.refreshIfStale()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            TripLive.shared.refresh()
            Task { await store.refreshIfStale() }
        }
        .accessibilityIdentifier("trip-day-screen")
    }

    private func content(_ bundle: TripBundle, _ day: PlannedDay, now: Date) -> some View {
        let clock = TripClock(bundle.trip.timeZone)
        let isToday = clock.localDate(now) == date
        let marks = store.marks(tripId)
        let progress = TripProgress.of(day: day, marks: marks, nowMin: clock.minutes(now), clock: clock)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                notes(bundle, isToday: isToday)
                if isToday {
                    if progress.showsBehind {
                        behindBanner(progress)
                    }
                    nowCard(bundle, day, progress)
                    actions(day, progress, now: now, clock: clock)
                }
                mapCard(day, progress: progress, marks: marks)
                timeline(bundle, day, marks: marks, progress: isToday ? progress : nil)
                TripSavedLine(refreshedAt: store.refreshedAt, online: network.online, queued: queue.count(for: tripId))
                    .padding(.top, 4)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 12)
        }
        .srRefreshable { await store.fetch(tripId) }
        .confirmationDialog("How late?", isPresented: $askLate, titleVisibility: .visible) {
            ForEach([10, 20, 30, 45], id: \.self) { minutes in
                Button("\(minutes) min") { late(minutes, day: day, progress: progress, now: now, clock: clock) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The rest of the day is re-timed from when you can set off.")
        }
        .confirmationDialog("Skip which?", isPresented: $askSkip, titleVisibility: .visible) {
            ForEach(skippable(day, progress), id: \.id) { stop in
                Button(stop.title) { skip(stop, day: day, progress: progress, now: now, clock: clock) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func notes(_ bundle: TripBundle, isToday: Bool) -> some View {
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

    private func behindBanner(_ progress: TripProgress) -> some View {
        Button {
            SRHaptic.tap()
            options = TripOptionsRequest(tripId: tripId, date: date, reason: .behind, nowMin: nil, position: TripPosition.latest)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're \(Int(progress.behindMin.rounded())) min behind")
                        .font(SR.Text.title(16))
                    Text("See ways to catch up")
                        .font(SR.Text.secondary(13))
                }
                Spacer()
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }
            .foregroundStyle(SR.cream)
            .padding(14)
            .srGlass(.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trip-behind")
    }

    private func nowCard(_ bundle: TripBundle, _ day: PlannedDay, _ progress: TripProgress) -> some View {
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 12) {
                SRSectionLabel(text: nowLabel(day, progress), prominent: true)
                TripNextLines(day: day, progress: progress, bundle: bundle)
                if let next = progress.next, next < day.stops.count {
                    getThere(day, to: next, progress: progress)
                }
            }
        }
        .accessibilityIdentifier("trip-now")
    }

    private func nowLabel(_ day: PlannedDay, _ progress: TripProgress) -> String {
        switch progress.phase {
        case .at(let i): return "Now · \(day.stops[i].title)"
        case .heading: return "On the way"
        case .finished: return "Done"
        }
    }

    /// Walk: follow the leg here. Anything else: the apps that do it well.
    @ViewBuilder
    private func getThere(_ day: PlannedDay, to next: Int, progress: TripProgress) -> some View {
        let stop = day.stops[next]
        if let leg = day.leg(before: next) {
            HStack(spacing: 10) {
                if TripDirections.followsInApp(leg), next > 0,
                   let route = TripDirections.route(for: leg, from: day.stops[next - 1], to: stop, tripId: tripId, date: date) {
                    Button {
                        SRHaptic.tap()
                        following = route
                    } label: { SRButtonLabel(title: "Walk there", icon: "figure.walk", fill: true) }
                        .srButton(.prominent)
                        .accessibilityIdentifier("trip-walk")
                } else {
                    Button {
                        SRHaptic.tap()
                        TripDirections.openInMaps(stop, mode: leg.mode)
                    } label: { SRButtonLabel(title: "Directions", icon: TripFormat.symbol(leg.mode), fill: true) }
                        .srButton(.prominent)
                    if leg.mode == .transit, TripDirections.hasCitymapper {
                        Button {
                            SRHaptic.tap()
                            TripDirections.openInCitymapper(stop)
                        } label: { SRButtonLabel(title: "Citymapper") }
                            .srButton(.regular)
                    }
                }
                if case .heading = progress.phase {
                    Button {
                        SRHaptic.ok()
                        store.record(.arrived, tripId: tripId, stop: stop, corrected: true)
                        TripArrivals.shared.refresh()
                    } label: { SRButtonLabel(title: "I'm here") }
                        .srButton(.regular)
                        .accessibilityIdentifier("trip-here")
                }
            }
        }
    }

    private func actions(_ day: PlannedDay, _ progress: TripProgress, now: Date, clock: TripClock) -> some View {
        HStack(spacing: 10) {
            Button { SRHaptic.tap(); askLate = true } label: {
                SRButtonLabel(title: "Running late", icon: "clock")
            }
            .accessibilityIdentifier("trip-late")
            Button { SRHaptic.tap(); askSkip = true } label: {
                SRButtonLabel(title: "Skip", icon: "forward")
            }
            .disabled(skippable(day, progress).isEmpty)
            .accessibilityIdentifier("trip-skip")
            Button { SRHaptic.tap(); swap(day, progress: progress, now: now, clock: clock) } label: {
                SRButtonLabel(title: "Swap", icon: "arrow.up.arrow.down")
            }
            .disabled(swappable(day, progress) == nil)
            .accessibilityIdentifier("trip-swap")
        }
        .srButton(.regular)
        .controlSize(.small)
    }

    private func mapCard(_ day: PlannedDay, progress: TripProgress, marks: [String: TripStopMark]) -> some View {
        let nextId = progress.next.flatMap { $0 < day.stops.count ? day.stops[$0].id : nil }
        return VStack(alignment: .leading, spacing: 8) {
            TripDayMap(
                day: day,
                doneIds: Set(progress.doneStopIds),
                nextId: nextId,
                marker: SRDemo.isOn ? TripDemo.here : nil
            )
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous))
            .accessibilityLabel("Map of the day's stops")
            TripMapPackRow(tripId: tripId, day: day, title: "\(store.bundles[tripId]?.trip.title ?? "Trip") · \(date)")
        }
    }

    private func timeline(_ bundle: TripBundle, _ day: PlannedDay, marks: [String: TripStopMark], progress: TripProgress?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "The day", trailing: "\(day.stops.filter { $0.kind != .stay }.count) stops")
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
                .contextMenu { corrections(stop) }
                .accessibilityIdentifier("trip-stop-\(index)")
                if let leg = day.leg(after: index) {
                    TripLegRow(leg: leg)
                }
            }
            ForEach(day.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.warn)
                    .padding(.top, 8)
            }
        }
    }

    /// The person knows better than a geofence.
    @ViewBuilder
    private func corrections(_ stop: PlannedStop) -> some View {
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
        if mark?.skipped != true && mark?.leftAt == nil && stop.kind != .stay {
            Button { store.record(.skipped, tripId: tripId, stop: stop, corrected: true) } label: {
                Label("Skip it", systemImage: "forward")
            }
        }
        if mark != nil {
            Button(role: .destructive) { store.clear(stop.id, tripId: tripId) } label: {
                Label(mark?.skipped == true ? "Not skipped after all" : "Not been yet", systemImage: "arrow.uturn.backward")
            }
        }
    }

    // MARK: Actions

    private func skippable(_ day: PlannedDay, _ progress: TripProgress) -> [PlannedStop] {
        let done = Set(progress.doneStopIds)
        return day.stops.filter { $0.kind == .wish && !done.contains($0.id) && !$0.locked }
    }

    /// The next two visits, when neither is locked.
    private func swappable(_ day: PlannedDay, _ progress: TripProgress) -> (Int, Int)? {
        guard let from = progress.retimeFrom else { return nil }
        let done = Set(progress.doneStopIds)
        let open = day.stops.indices.filter { $0 >= from && day.stops[$0].kind == .wish && !done.contains(day.stops[$0].id) }
        guard open.count >= 2, !day.stops[open[0]].locked, !day.stops[open[1]].locked else { return nil }
        return (open[0], open[1])
    }

    private func late(_ minutes: Int, day: PlannedDay, progress: TripProgress, now: Date, clock: TripClock) {
        let stop = progress.atStopId.flatMap { id in day.stops.first { $0.id == id } }
        store.record(.delayed, tripId: tripId, stop: stop, detail: ["seconds": .number(Double(minutes * 60))])
        options = TripOptionsRequest(
            tripId: tripId, date: date, reason: .late(minutes),
            nowMin: clock.minutes(now) + Double(minutes), position: TripPosition.latest
        )
    }

    private func skip(_ stop: PlannedStop, day: PlannedDay, progress: TripProgress, now: Date, clock: TripClock) {
        store.record(.skipped, tripId: tripId, stop: stop)
        TripArrivals.shared.refresh()
        options = TripOptionsRequest(tripId: tripId, date: date, reason: .skipped(stop.title), nowMin: nil, position: TripPosition.latest)
    }

    private func swap(_ day: PlannedDay, progress: TripProgress, now: Date, clock: TripClock) {
        guard let pair = swappable(day, progress) else { return }
        options = TripOptionsRequest(
            tripId: tripId, date: date, reason: .swap(pair.0, pair.1), nowMin: nil, position: TripPosition.latest
        )
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

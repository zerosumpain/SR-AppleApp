import SwiftUI
import MapKit

/// One stop as a PLACE CARD (v7): its photograph, why it is in the plan, its
/// hours on the day and the way there — the essentials first (2026-10-16).
/// How to get there by each mode, and everything else the site found (the
/// street in front of it, what's worth knowing, the booking, the facts, the
/// sources and when they were checked), open on a tap. A meal still without
/// a place shows the real places to choose from.
struct TripStopScreen: View {
    let ref: TripStopRef
    @ObservedObject private var store = TripStore.shared
    @State private var following: PlannedRouteDetail?
    @State private var showsRoute = false
    @State private var showsMore = false

    var body: some View {
        Group {
            if let bundle = store.bundles[ref.tripId], let day = store.day(ref.tripId, ref.date),
               let index = day.index(of: ref.stopId) {
                content(bundle, day, index)
            } else {
                SREmpty(title: "This stop is no longer in the plan", icon: "mappin.slash")
            }
        }
        .srPaper()
        .navigationTitle("Stop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Corrections in sight, not only behind a long press on the
            // day's list (plan §5.5): "I'm here", "Skip it" and the rest.
            if let day = store.day(ref.tripId, ref.date), let index = day.index(of: ref.stopId) {
                ToolbarItem(placement: .topBarTrailing) {
                    TripStopMenu(tripId: ref.tripId, stop: day.stops[index])
                }
            }
        }
        .fullScreenCover(item: $following) { FollowRouteScreen(detail: $0) }
    }

    private func content(_ bundle: TripBundle, _ day: PlannedDay, _ index: Int) -> some View {
        let stop = day.stops[index]
        let wish = bundle.wish(stop.wishId)
        let facts = wish?.facts
        let booking = bundle.booking(for: stop)
        let clock = TripClock(bundle.trip.timeZone)
        return List {
            if let photo = bundle.photo(for: stop) {
                TripPhotoView(photo: photo, height: 220)
                    .srPlainRow()
                    .padding(.top, 8)
                    .accessibilityIdentifier("trip-place-photo")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(TripWords.span(stop))
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.accentDeep)
                Text(stop.title)
                    .font(SR.Text.display(26))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let address = wish?.place?.address ?? bundle.stay(day.stayId).flatMap({ stop.kind == .stay ? $0.address : nil }) {
                    Text(address).font(SR.Text.secondary()).foregroundStyle(SR.inkSecondary)
                }
                if let summary = facts?.summary {
                    Text(summary)
                        .font(SR.Text.body(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                ForEach(stop.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.warn)
                }
                if let why = TripPlaceWhy.line(stop: stop, wish: wish, bundle: bundle) {
                    Label(why, systemImage: "heart.text.square")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("trip-place-why")
                }
                TripPlaceChips(chips: TripPlaceWhy.chips(facts: facts, date: day.date, clock: clock, stop: stop, timeZone: bundle.trip.timeZone) + refChip(booking))
                    .padding(.top, 4)
                directions(bundle, day, index)
                    .padding(.top, 8)
            }
            .padding(.vertical, 12)
            .srPlainRow()

            // v7: a meal with no place yet — the places to choose from.
            if stop.awaitsMealChoice {
                Section {
                    TripMealChoices(tripId: ref.tripId, day: day, stop: stop, bundle: bundle, large: true)
                        .srPlainRow()
                } header: { TripHeading(text: "Choose where to eat") }
            }

            gettingThere(bundle, day, index)

            if hasMore(stop: stop, wish: wish, booking: booking) {
                disclosure(showsMore ? "Less about this place" : "More about this place", open: showsMore, id: "trip-place-more") {
                    showsMore.toggle()
                }
            }

            if showsMore {
                // The street in front of it, where Apple has looked around.
                if let at = stop.location {
                    TripLookAround(location: at)
                        .srPlainRow()
                }

                if let guide = wish?.guide {
                    Section {
                        Text(guide.summary)
                            .font(SR.Text.body(15))
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 4)
                            .srPlainRow()
                        ForEach(guide.tips, id: \.self) { tip in
                            Label(tip, systemImage: "checkmark.circle")
                                .font(SR.Text.secondary(14))
                                .foregroundStyle(SR.inkSecondary)
                                .srPlainRow()
                        }
                        ForEach(guide.links.filter { TripLinkButtons.safeURL($0.url) != nil }, id: \.url) { link in
                            if let url = TripLinkButtons.safeURL(link.url) { linkRow(link.label, url) }
                        }
                    } header: { TripHeading(text: "Worth knowing") }
                }

                if let booking {
                    Section {
                        factRow("Status", bookingStatus(booking))
                        if let ref = booking.reference { factRow("Reference", ref) }
                        if let start = booking.startMin { factRow("Time", TripFormat.time(start) + (booking.endMin.map { "–" + TripFormat.time($0) } ?? "")) }
                        if let link = booking.url.flatMap(URL.init(string:)) { linkRow("Booking", link) }
                    } header: { TripHeading(text: "Booking") }
                }

                if let facts {
                    Section {
                        if let text = facts.openingHoursText { factRow("Opening hours", text) }
                        if let today = hoursOn(facts, date: day.date, clock: clock) { factRow(TripFormat.day(day.date, zone: clock.zone), today) }
                        if facts.closedDates.contains(day.date) { factRow("Closed", "on this day (holiday)") }
                        if let price = facts.priceText { factRow("Price", price) }
                        if let visit = facts.typicalVisitSec { factRow("Typical visit", TripFormat.duration(seconds: visit)) }
                        if facts.bookingRequired == true {
                            factRow("Booking", facts.bookAheadDays.map { "Needed · sells out about \(Int($0)) days ahead" } ?? "Needed")
                        }
                        if let link = facts.bookingUrl.flatMap(URL.init(string:)) { linkRow("Book (official)", link) }
                        if let link = facts.officialUrl.flatMap(URL.init(string:)) { linkRow("Official site", link) }
                        if !facts.unknown.isEmpty { factRow("Not found", facts.unknown.joined(separator: ", ")) }
                    } header: {
                        TripHeading(text: "Facts", trailing: checked(facts))
                    }
                    if !facts.sources.isEmpty {
                        Section {
                            ForEach(facts.sources, id: \.url) { source in
                                if let url = URL(string: source.url) {
                                    linkRow(source.title ?? url.host() ?? source.url, url)
                                }
                            }
                        } header: { TripHeading(text: "Sources") }
                    }
                }
            }

            // Read-only, like the Day screen: corrections are the ••• in the
            // bar, and changes go through the planner.
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// How to get there, by each mode: one line until it is opened.
    @ViewBuilder
    private func gettingThere(_ bundle: TripBundle, _ day: PlannedDay, _ index: Int) -> some View {
        if let leg = day.leg(before: index) {
            disclosure("Getting there · \(TripFormat.leg(leg)) from \(day.stops[index - 1].title)", open: showsRoute, id: "trip-place-route") {
                showsRoute.toggle()
            }
            if showsRoute {
                // v5: the leg in, in the mode you'd rather (display only).
                TripLegPicker(tripId: ref.tripId, date: ref.date, leg: leg, from: day.stops[index - 1], to: day.stops[index])
                    .srPlainRow()
                    .padding(.vertical, 6)
                TripNextStageCard(
                    leg: leg, from: day.stops[index - 1], to: day.stops[index],
                    bundle: bundle, date: ref.date, following: $following, inline: true
                )
                .srPlainRow()
                .padding(.vertical, 6)
            }
        }
    }

    /// The one way there, up front: walking directions when the leg in is a
    /// walk, else Maps.
    @ViewBuilder
    private func directions(_ bundle: TripBundle, _ day: PlannedDay, _ index: Int) -> some View {
        let stop = day.stops[index]
        if let leg = day.leg(before: index) {
            let from = day.stops[index - 1]
            if leg.mode == .walk, let route = TripDirections.route(for: leg, from: from, to: stop, tripId: bundle.trip.id, date: ref.date) {
                Button { SRHaptic.tap(); following = route } label: { TripButtonLabel("Walk there", icon: "figure.walk", fill: true) }
                    .srButton(.prominent)
                    .accessibilityIdentifier("trip-place-directions")
            } else if stop.location != nil {
                Button { SRHaptic.tap(); TripDirections.openInMaps(stop, mode: leg.mode) } label: { TripButtonLabel("Directions", icon: "map", fill: true) }
                    .srButton(.prominent)
                    .accessibilityIdentifier("trip-place-directions")
            }
        } else if stop.location != nil {
            Button { SRHaptic.tap(); TripDirections.openInMaps(stop, mode: .walk) } label: { TripButtonLabel("Directions", icon: "map", fill: true) }
                .srButton(.prominent)
                .accessibilityIdentifier("trip-place-directions")
        }
    }

    /// A row that opens or shuts what follows it.
    private func disclosure(_ title: String, open: Bool, id: String, toggle: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.select()
            withAnimation(.snappy(duration: 0.25)) { toggle() }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SR.inkMuted)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(open ? "Open" : "Shut")
        .accessibilityIdentifier(id)
        .srPlainRow()
    }

    /// A booked place's reference, up front: it is read out at the desk.
    private func refChip(_ booking: TripBooking?) -> [TripPlaceWhy.Chip] {
        guard let booking, booking.status == .booked, let ref = booking.reference else { return [] }
        return [TripPlaceWhy.Chip(icon: "ticket.fill", text: "Ref \(ref)")]
    }

    /// Anything to show under "More about this place".
    private func hasMore(stop: PlannedStop, wish: TripWish?, booking: TripBooking?) -> Bool {
        stop.location != nil || wish?.guide != nil || booking != nil || wish?.facts != nil
    }

    /// Every value is selectable: a booking reference is read out at a
    /// ticket desk, and an address is pasted into a taxi app.
    private func factRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
            Text(value)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .srPlainRow()
    }

    private func linkRow(_ title: String, _ url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(title).font(SR.Text.body(15)).foregroundStyle(SR.accentDeep)
                Spacer()
                Image(systemName: "arrow.up.right.square").foregroundStyle(SR.inkMuted).accessibilityHidden(true)
            }
            .padding(.vertical, 6)
        }
        .srPlainRow()
    }

    private func bookingStatus(_ booking: TripBooking) -> String {
        switch booking.status {
        case .booked: return "Booked"
        case .toBook: return "Not booked yet"
        case .cancelled: return "Cancelled"
        }
    }

    /// "Checked 12 Oct", from the facts' ISO timestamp.
    private func checked(_ facts: TripFacts) -> String? {
        guard let raw = facts.checkedAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return nil }
        return "checked " + date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_GB")))
    }

    /// "09:00–19:00" for the stop's weekday, "closed", or nil when unknown.
    private func hoursOn(_ facts: TripFacts, date: String, clock: TripClock) -> String? {
        guard let weekday = clock.isoWeekday(date), let ranges = facts.hours?[String(weekday)] else { return nil }
        if ranges.isEmpty { return "Closed" }
        return ranges.map { "\(TripFormat.time($0.openMin))–\(TripFormat.time($0.closeMin))" }.joined(separator: ", ")
    }
}

// MARK: - Corrections in sight

/// The ••• on a stop: "I'm here", "I've left", "Skip it", "Not been yet" —
/// what the person knows better than a geofence — as a visible menu, not
/// only a long press (plan §5.5). On the stop screen's bar; for a stop's
/// row on the day and the map's peek too (`showOnMap` adds that item).
struct TripStopMenu: View {
    let tripId: String
    let stop: PlannedStop
    var showOnMap: (() -> Void)? = nil

    var body: some View {
        Menu {
            if let showOnMap, stop.location != nil {
                Button { showOnMap() } label: { Label("Show on the map", systemImage: "map") }
            }
            TripCorrections(tripId: tripId, stop: stop)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Mark \(stop.title)")
        .accessibilityHint("I'm here, I've left, skip it")
        .accessibilityIdentifier("trip-stop-menu")
    }
}

// MARK: - The place card's pieces

/// Why a stop is in the plan, and its facts at a glance, in plain words.
enum TripPlaceWhy {
    /// "Sam suggested it" · "A must-do" · "Booked for 09:30" · the note.
    static func line(stop: PlannedStop, wish: TripWish?, bundle: TripBundle) -> String? {
        var parts: [String] = []
        if let wish {
            let by = (bundle.suggestions ?? []).first { $0.status == "approved" && $0.wish.title == wish.title }?.byName
            if let by { parts.append("\(by) suggested it") }
            if bundle.booking(for: stop)?.status == .booked, let start = bundle.booking(for: stop)?.startMin {
                parts.append("Booked for \(TripFormat.time(start))")
            } else if wish.locked || wish.fixedStartMin != nil {
                parts.append("Fixed for this time")
            } else if wish.priority == .must {
                parts.append("A must-do")
            }
            if let meal = wish.replacesMeal, !meal.isEmpty { parts.append("This is \(meal)") }
            if let note = wish.note, !note.isEmpty { parts.append(note) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    struct Chip: Hashable {
        let icon: String
        let text: String
        var warn = false
    }

    /// Its hours that day first, then how long, the price, booking. The
    /// price wears the money of where the trip is (`TripCurrency`).
    static func chips(facts: TripFacts?, date: String, clock: TripClock, stop: PlannedStop, timeZone: String? = nil) -> [Chip] {
        guard let facts else { return [] }
        var out: [Chip] = []
        if facts.closedDates.contains(date) {
            out.append(Chip(icon: "xmark.octagon", text: "Closed this day", warn: true))
        } else if let weekday = clock.isoWeekday(date), let ranges = facts.hours?[String(weekday)] {
            out.append(ranges.isEmpty
                ? Chip(icon: "xmark.octagon", text: "Closed this day", warn: true)
                : Chip(icon: "clock", text: ranges.map { "\(TripFormat.time($0.openMin))–\(TripFormat.time($0.closeMin))" }.joined(separator: ", ")))
        } else if facts.openingHoursText == nil {
            out.append(Chip(icon: "questionmark.circle", text: "Hours unknown", warn: true))
        }
        if let visit = facts.typicalVisitSec { out.append(Chip(icon: "hourglass", text: TripFormat.duration(seconds: visit))) }
        if let price = facts.priceText {
            out.append(Chip(icon: TripCurrency.symbol(price: price, timeZone: timeZone ?? clock.zone.identifier), text: price))
        }
        if facts.bookingRequired == true { out.append(Chip(icon: "ticket", text: "Book ahead")) }
        return out
    }
}

/// The facts at a glance, as small capsules that wrap.
struct TripPlaceChips: View {
    let chips: [TripPlaceWhy.Chip]

    var body: some View {
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Label(chip.text, systemImage: chip.icon)
                            .font(SR.Text.mono(12))
                            .foregroundStyle(chip.warn ? SR.warn : SR.inkSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(SR.inkMuted.opacity(0.10)))
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("trip-place-chips")
        }
    }
}

/// Apple's Look Around at a place, where Apple has it — live on the phone,
/// nothing stored. Nothing at all where there is no imagery, or no signal.
struct TripLookAround: View {
    let location: TripLatLng
    @ObservedObject private var network = TripNetwork.shared
    @State private var scene: MKLookAroundScene?

    var body: some View {
        Group {
            if let scene {
                VStack(alignment: .leading, spacing: 6) {
                    TripHeading(text: "The street")
                    LookAroundPreview(initialScene: scene)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
                }
                .padding(.vertical, 6)
                .accessibilityIdentifier("trip-look-around")
            } else {
                // Something to hang the task on: an empty group never appears.
                Color.clear.frame(height: 1).accessibilityHidden(true)
            }
        }
        // Keyed on the connection too: a look missed offline is tried again online.
        .task(id: "\(location.lat),\(location.lng),\(network.online)") {
            guard scene == nil, network.online, !SRDemo.isOn else { return }
            let request = MKLookAroundSceneRequest(coordinate: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng))
            scene = try? await request.scene
        }
    }
}

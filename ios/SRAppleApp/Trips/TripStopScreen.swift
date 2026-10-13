import SwiftUI

/// One stop: when, how long, and the facts the site found — opening hours,
/// the booking, the official links, the sources and when they were checked.
struct TripStopScreen: View {
    let ref: TripStopRef
    @ObservedObject private var store = TripStore.shared
    @State private var following: PlannedRouteDetail?

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
        .fullScreenCover(item: $following) { FollowRouteScreen(detail: $0) }
    }

    private func content(_ bundle: TripBundle, _ day: PlannedDay, _ index: Int) -> some View {
        let stop = day.stops[index]
        let wish = bundle.wish(stop.wishId)
        let facts = wish?.facts
        let booking = bundle.booking(for: stop)
        let clock = TripClock(bundle.trip.timeZone)
        return List {
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
                if let note = wish?.note, !note.isEmpty {
                    Label(note, systemImage: "note.text")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                }
            }
            .padding(.vertical, 12)
            .srPlainRow()

            gettingThere(day, index)

            if let booking {
                Section {
                    factRow("Status", bookingStatus(booking))
                    if let ref = booking.reference { factRow("Reference", ref) }
                    if let start = booking.startMin { factRow("Time", TripFormat.time(start) + (booking.endMin.map { "–" + TripFormat.time($0) } ?? "")) }
                    if let link = booking.url.flatMap(URL.init(string:)) { linkRow("Booking", link) }
                } header: { SRSectionLabel(text: "Booking") }
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
                    SRSectionLabel(text: "Facts", trailing: checked(facts))
                }
                if !facts.sources.isEmpty {
                    Section {
                        ForEach(facts.sources, id: \.url) { source in
                            if let url = URL(string: source.url) {
                                linkRow(source.title ?? url.host() ?? source.url, url)
                            }
                        }
                    } header: { SRSectionLabel(text: "Sources") }
                }
            }

            Section {
                corrections(stop)
            } header: { SRSectionLabel(text: "Correct the day") }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func gettingThere(_ day: PlannedDay, _ index: Int) -> some View {
        if let leg = day.leg(before: index) {
            let stop = day.stops[index]
            Section {
                factRow("From \(day.stops[index - 1].title)", TripFormat.leg(leg) + (leg.estimated ? " (estimate)" : ""))
                if TripDirections.followsInApp(leg),
                   let route = TripDirections.route(for: leg, from: day.stops[index - 1], to: stop, tripId: ref.tripId, date: ref.date) {
                    Button { SRHaptic.tap(); following = route } label: { Label("Walk there", systemImage: "figure.walk") }
                        .srPlainRow()
                }
                Button { SRHaptic.tap(); TripDirections.openInMaps(stop, mode: leg.mode) } label: {
                    Label("Directions in Maps", systemImage: "map")
                }
                .srPlainRow()
                if leg.mode == .transit, TripDirections.hasCitymapper {
                    Button { SRHaptic.tap(); TripDirections.openInCitymapper(stop) } label: {
                        Label("Open in Citymapper", systemImage: "tram")
                    }
                    .srPlainRow()
                }
            } header: { SRSectionLabel(text: "Getting there") }
        }
    }

    @ViewBuilder
    private func corrections(_ stop: PlannedStop) -> some View {
        let mark = store.marks(ref.tripId)[stop.id]
        if mark?.arrivedAt == nil {
            Button { store.record(.arrived, tripId: ref.tripId, stop: stop, corrected: true) } label: {
                Label("I'm here", systemImage: "mappin.circle")
            }.srPlainRow()
        }
        if mark?.arrivedAt != nil && mark?.leftAt == nil {
            Button { store.record(.left, tripId: ref.tripId, stop: stop, corrected: true) } label: {
                Label("I've left", systemImage: "figure.walk.departure")
            }.srPlainRow()
        }
        if mark?.skipped != true && mark?.leftAt == nil && stop.kind == .wish {
            Button { store.record(.skipped, tripId: ref.tripId, stop: stop, corrected: true) } label: {
                Label("Skip it", systemImage: "forward")
            }.srPlainRow()
        }
        if let mark {
            Button(role: .destructive) { store.clear(stop.id, tripId: ref.tripId) } label: {
                Label(mark.skipped ? "Not skipped after all" : "Not been yet", systemImage: "arrow.uturn.backward")
            }.srPlainRow()
        }
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

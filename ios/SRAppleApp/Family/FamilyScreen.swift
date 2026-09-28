import SwiftUI
import MapKit

/// Family: where everyone is, and — a tap away — how their day has gone.
///
/// The map is pinned above the list rather than scrolled with it: a map you can
/// pan inside a scroll view steals the scroll (see `RouteMap`), and here the
/// map is the point, so it keeps its gestures and the list scrolls beneath it.
/// Today's lines start OFF here, every time — the pins are the question on
/// this page — and the map's corner switches them on for the visit.
///
/// A person is ONE row: pin, name, where, battery. Everything else — the day's
/// figures, the week behind it, their own route — is on the person's page,
/// one tap in.
///
/// Everything on screen is what the site decided this person may see — a card
/// with no day is somebody else's day, not a failure to load one.
struct FamilyScreen: View {
    @ObservedObject var store: FamilyStore
    @ObservedObject var companion: Companion
    @EnvironmentObject private var router: Router
    @ObservedObject private var access = AccessStore.shared
    /// The travel desk's forecast: next moves and what looks off. Optional —
    /// a phone without the site credential sees the positions alone.
    @ObservedObject private var forecast = FamilyForecastStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera: MapCameraPosition = .automatic
    /// Today's lines on the map. Off on arrival, not remembered.
    @State private var showTracks = false

    var body: some View {
        Group {
            if let view = store.view {
                content(view)
            } else if store.loaded {
                empty
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .srGround(.warm)
        .navigationTitle("Family")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { SRBarMark() }
            // Steps and Tasks live in More; with no More (a member with four
            // places or fewer) they are here instead, or there is no way in.
            if access.familyBoards && !access.allows(.more) {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { SRHaptic.tap(); router.openFamilyPage(.steps) } label: { Image(systemName: "figure.walk") }
                        .accessibilityLabel("Steps")
                        .accessibilityIdentifier("family-open-steps")
                    Button { SRHaptic.tap(); router.openFamilyPage(.tasks) } label: { Image(systemName: "checklist") }
                        .accessibilityLabel("Tasks")
                        .accessibilityIdentifier("family-open-tasks")
                }
            }
        }
        .navigationDestination(for: FamilyPersonRoute.self) { route in
            FamilyPersonScreen(store: store, subject: route.subject)
        }
        .task {
            await store.load()
            await forecast.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: FamilyStore.refreshInterval)
                guard !Task.isCancelled else { break }
                await store.load()
                // At most once a minute: the store keeps its own clock.
                await forecast.load()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.load(); await forecast.load() }
        }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRBanner(text: message, tone: SR.error) }
        }
    }

    private func content(_ view: HouseholdView) -> some View {
        VStack(spacing: 0) {
            FamilyMapCanvas(people: view.people, interactive: true, showTrails: showTracks, camera: $camera)
                .frame(height: 320)
                .overlay(alignment: .topTrailing) {
                    FamilyTracksToggle(on: $showTracks).padding(10)
                }
                .accessibilityIdentifier("family-map")
            ScrollView {
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    if let items = forecast.forecast?.watch, !items.isEmpty {
                        FamilyWatchCard(items: items)
                            .padding(.top, 14)
                    }
                    // The owner's phone only (null for anyone else).
                    if let f = forecast.forecast, let upcoming = f.upcoming {
                        FamilyUpcomingCard(upcoming: upcoming, names: f.names)
                            .padding(.top, f.watch.isEmpty ? 14 : 0)
                    }
                    // The counts, not a headline: the map above is the page's
                    // title, and the tab says where you are.
                    SRSectionLabel(text: "Everyone", trailing: view.summary)
                        .padding(.horizontal, 4)
                        .padding(.top, 14)
                    VStack(spacing: 0) {
                        ForEach(Array(view.people.enumerated()), id: \.element.id) { index, person in
                            if index > 0 {
                                Rectangle().fill(SR.divider).frame(height: 1).padding(.leading, 52)
                            }
                            NavigationLink(value: FamilyPersonRoute(subject: person.subject)) {
                                FamilyPersonRow(person: person, next: forecast.forecast?.next(for: person.subject))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("family-person-\(person.subject)")
                        }
                    }
                    .srGlassCard(.paper)
                    footer(view)
                }
                .padding(.horizontal, SR.gutter)
                .padding(.bottom, 28)
            }
            .srRefreshable { await store.load(); await forecast.load(force: true) }
        }
    }

    private func footer(_ view: HouseholdView) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let freshness = store.freshness {
                Text(freshness).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
            }
            Text(view.viewer == "owner"
                 ? "You see everyone's day. Family see where everyone is and their own day."
                 : "You see where everyone is. Only your own day and route are shown to you.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var empty: some View {
        if !companion.paired {
            SREmpty(
                title: "Not paired yet",
                icon: "person.2",
                message: "Pair this iPhone with the family companion to see where everyone is.",
                actionLabel: "Pair",
                action: { router.openSettings(.connections) }
            )
            .frame(maxHeight: .infinity)
        } else {
            SREmpty(
                title: "Nothing to show yet",
                icon: "map",
                message: "The site sends your family view every couple of minutes once you are in the Family Circle. Ask the owner if it never arrives."
            )
            .frame(maxHeight: .infinity)
        }
    }
}

/// Which person's page is open. A value, so the tab's path can hold it.
struct FamilyPersonRoute: Hashable {
    let subject: String
}

/// The map's "tracks" switch, and the key it is kept under.
enum FamilyTracks {
    static let key = "family-show-tracks"
}

/// A small glass switch in the map's corner: today's lines on or off.
struct FamilyTracksToggle: View {
    @Binding var on: Bool

    var body: some View {
        Button {
            SRHaptic.select()
            withAnimation(.snappy) { on.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "point.topleft.down.to.point.bottomright.curvepath.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 13, weight: .semibold))
                Text(on ? "TRACKS ON" : "TRACKS OFF")
                    .font(SR.Text.label())
                    .tracking(1.1)
            }
            .foregroundStyle(on ? SR.accent : SR.inkMuted)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .srGlass(.paper, in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show today's tracks")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("family-tracks-toggle")
    }
}

/// One person, one row: pin, name, where, battery. The day is on their page.
///
/// A row, not a card: five people as cards were a screen of scrolling under
/// a map that already says where everyone is. The line truncates rather than
/// wraps, so every person costs the same height.
struct FamilyPersonRow: View {
    let person: FamilyPerson
    /// Their next likely move, from the forecast — a second line only when
    /// there is one, so a quiet day costs no height.
    var next: FamilyForecast.NextMove? = nil
    @ObservedObject private var places = PlaceNamer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row
            if let next {
                HStack(spacing: 5) {
                    Image(systemName: next.kind == "arriving" ? "location.north.fill" : "clock")
                        .font(.system(size: 11, weight: .semibold))
                    Text(ForecastWords.nextLine(next))
                        .font(SR.Text.mono())
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(SR.accentInk)
                .padding(.leading, 52)
                .padding(.trailing, SR.cardPadding)
                .padding(.bottom, 8)
                .accessibilityIdentifier("family-next-\(person.subject)")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows their day and week")
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 10) {
            FamilyPin(person: person)
            HStack(spacing: 5) {
                Text(person.name)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .layoutPriority(1)
                if person.isSelf {
                    Text("YOU").font(SR.Text.label()).tracking(1.2).foregroundStyle(SR.accent)
                }
            }
            Text(FamilyWords.line(person, places: places))
                .font(SR.Text.secondary())
                .foregroundStyle(person.moving != nil ? SR.accentInk : SR.inkSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let pct = person.batteryPct { FamilyBattery(pct: pct) }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SR.inkGhost)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, SR.cardPadding)
        .frame(minHeight: SR.tapTarget + 8)
    }
}

/// What looks different from someone's own routine right now — a missed
/// departure, a long journey, a phone gone quiet away from home. Read, not
/// alarmed: every item needs a dependable routine AND a fresh reading that
/// contradicts it, so a dead phone or a thin history is silence.
struct FamilyWatchCard: View {
    let items: [FamilyForecast.WatchItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "What looks off").padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(SR.divider).frame(height: 1).padding(.leading, 44) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: ForecastWords.symbol(item))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(item.severity == "alert" ? SR.error : SR.warn)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(SR.Text.title()).foregroundStyle(SR.ink)
                            Text(item.detail)
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                }
            }
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("family-watch")
    }
}

/// The words a card and a page share.
enum FamilyWords {
    /// "Walking near Station Road, Darlington" while moving; the site's own
    /// line otherwise.
    @MainActor
    static func line(_ person: FamilyPerson, places: PlaceNamer) -> String {
        guard let moving = person.moving else { return person.line }
        let verb = moving.verb.prefix(1).uppercased() + moving.verb.dropFirst()
        if let position = person.position, let name = places.name(lat: position.lat, lon: position.lon) {
            return "\(verb) near \(name)"
        }
        return "\(verb) · \(person.line)"
    }
}

/// A battery reading: the glyph and the number, red when low.
struct FamilyBattery: View {
    let pct: Int

    var body: some View {
        let low = BatteryReading.isLow(pct)
        HStack(spacing: 4) {
            Image(systemName: BatteryReading.symbol(pct))
                .font(.system(size: 15, weight: .semibold))
            Text("\(pct)%").font(SR.monoMedium(13))
        }
        .foregroundStyle(low ? SR.error : SR.inkSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(pct) percent\(low ? ", low" : "")")
    }
}

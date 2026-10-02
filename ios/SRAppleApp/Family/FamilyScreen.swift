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
    /// Route walks being shared live that this phone may follow.
    @ObservedObject private var walks = LiveWalksStore.shared
    /// Routes the owner sent this phone to walk.
    @ObservedObject private var gifts = RouteGiftsStore.shared
    /// The family alarm: raise one, and the pull floor for receiving one.
    @ObservedObject private var alarm = FamilyAlarmStore.shared
    /// The map, full screen.
    @State private var mapExpanded = false
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
            // The alarm: on the left, away from Steps and Tasks, so it is
            // never the thing a thumb was reaching past.
            if alarm.available {
                ToolbarItem(placement: .topBarLeading) { FamilyAlarmButton() }
            }
            // Today's lines on the map: a glyph the size of the alarm's,
            // opposite it, instead of a capsule over the map.
            ToolbarItem(placement: .topBarTrailing) { FamilyTracksButton(on: $showTracks) }
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
        .navigationDestination(for: LiveWalkRef.self) { LiveRouteScreen(ref: $0) }
        .task {
            await store.load()
            await forecast.load()
            await walks.load()
            await gifts.load()
            await alarm.poll()
            while !Task.isCancelled {
                try? await Task.sleep(for: FamilyStore.refreshInterval)
                guard !Task.isCancelled else { break }
                await alarm.poll()
                await store.load()
                await walks.load()
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
                // Two thirds of what it was: the people and their moves
                // below are the page now, the map is where.
                .frame(height: 212)
                .overlay(alignment: .bottomTrailing) {
                    FamilyMapExpandButton(expanded: false) { mapExpanded = true }.padding(10)
                }
                .accessibilityIdentifier("family-map")
                .fullScreenCover(isPresented: $mapExpanded) {
                    FamilyFullMap(people: view.people, showTracks: $showTracks, camera: $camera) {
                        mapExpanded = false
                    }
                }
            ScrollView {
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    LiveWalksCard(store: walks)
                        .padding(.top, walks.walks.isEmpty ? 0 : 14)
                    RouteGiftsCard(store: gifts)
                        .padding(.top, gifts.gifts.isEmpty || !walks.walks.isEmpty ? 0 : 14)
                    if let items = forecast.forecast?.watch, !items.isEmpty {
                        FamilyWatchCard(items: items)
                            .padding(.top, 14)
                    }
                    // The owner's phone only (null for anyone else), and only
                    // when there is something in it: an empty diary is no card.
                    if let f = forecast.forecast, let upcoming = f.upcoming,
                       FamilyUpcomingCard.hasContent(upcoming) {
                        FamilyUpcomingCard(upcoming: upcoming, names: f.names)
                            .padding(.top, f.watch.isEmpty ? 14 : 0)
                    }
                    // The counts, not a headline: the map above is the page's
                    // title, and the tab says where you are.
                    SRSectionLabel(text: "Everyone", trailing: view.summary)
                        .padding(.horizontal, 4)
                        .padding(.top, 14)
                    FamilyPlaceStacks(view: view)
                    // Where everyone is going: the travel desk's next moves.
                    if let f = forecast.forecast, !f.next.isEmpty {
                        FamilyMovesCard(moves: f.next, names: f.names)
                            .padding(.top, 14)
                    }
                    footer(view)
                }
                .padding(.horizontal, SR.gutter)
                .padding(.bottom, 28)
            }
            .srRefreshable { await store.load(); await walks.load(); await gifts.load(); await forecast.load(force: true) }
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

/// Today's lines on or off: one glyph in the bar, petrol when on.
struct FamilyTracksButton: View {
    @Binding var on: Bool

    var body: some View {
        Button {
            SRHaptic.select()
            withAnimation(.snappy) { on.toggle() }
        } label: {
            Image(systemName: on ? "point.topleft.down.to.point.bottomright.curvepath.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(on ? SR.accentInk : SR.inkMuted)
        }
        .accessibilityLabel("Show today's tracks")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("family-tracks-toggle")
    }
}

/// The map's corner button: full screen, or back.
struct FamilyMapExpandButton: View {
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(SR.ink)
                .frame(width: 40, height: 40)
                .srGlass(.paper, in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Close the full-screen map" : "Show the map full screen")
        .accessibilityIdentifier(expanded ? "family-map-collapse" : "family-map-expand")
    }
}

/// The family map, full screen: the same camera, the same tracks switch.
struct FamilyFullMap: View {
    let people: [FamilyPerson]
    @Binding var showTracks: Bool
    @Binding var camera: MapCameraPosition
    let close: () -> Void

    var body: some View {
        FamilyMapCanvas(people: people, interactive: true, showTrails: showTracks, camera: $camera)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                FamilyTracksButton(on: $showTracks)
                    .frame(width: 40, height: 40)
                    .srGlass(.paper, in: Circle(), interactive: true)
                    .padding(16)
            }
            .overlay(alignment: .bottomTrailing) {
                FamilyMapExpandButton(expanded: true, action: close).padding(16)
            }
            .accessibilityIdentifier("family-map-full")
    }
}

/// Everyone, grouped by where they are: a place's name, then its people as
/// cards dealt over one another — each a third under the one before — so a
/// crowd at home reads as one pile and somebody out alone stands apart.
/// The piles sit side by side and wrap like words on a line, so two people
/// out alone share a row instead of each taking the full width.
/// Anybody not seen lately is the last pile, with the site's own words.
/// A card opens that person's page.
struct FamilyPlaceStacks: View {
    let view: HouseholdView
    /// A card's width, and how much of it the next one covers.
    static let card: CGFloat = 84
    static let overlap: CGFloat = 0.33

    var body: some View {
        let groups = view.places()
        let absent = view.people.filter { $0.status == "unknown" || $0.status == "off" }
        DaydreamWrap(spacing: 16) {
            ForEach(groups) { place in
                pile(title: place.name, icon: place.isHome ? "house.fill" : place.isMoving ? "arrow.triangle.turn.up.right.circle.fill" : "mappin.circle.fill",
                     people: place.people, id: place.name.lowercased())
            }
            if !absent.isEmpty {
                pile(title: "Not seen lately", icon: "questionmark.circle", people: absent, id: "absent")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("family-people")
    }

    private func pile(title: String, icon: String, people: [FamilyPerson], id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SR.accentInk)
                    .accessibilityHidden(true)
                Text(title)
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    // A long place name truncates rather than pushing its
                    // pile wider than the screen.
                    .frame(maxWidth: 220, alignment: .leading)
                Text("\(people.count)")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
            HStack(spacing: -Self.card * Self.overlap) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    NavigationLink(value: FamilyPersonRoute(subject: person.subject)) {
                        FamilyPersonTile(person: person).frame(width: Self.card)
                    }
                    .buttonStyle(.plain)
                    // The first card on top, the rest dealt under it.
                    .zIndex(Double(people.count - index))
                    .accessibilityIdentifier("family-person-\(person.subject)")
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        // Its own width, not the row's: the wrap measures each pile to
        // decide whether the next one fits beside it.
        .fixedSize()
        .accessibilityIdentifier("family-place-\(id)")
    }
}

struct FamilyPersonTile: View {
    let person: FamilyPerson
    @ObservedObject private var places = PlaceNamer.shared

    var body: some View {
        VStack(spacing: 6) {
            FamilyPin(person: person, emphasised: true)
                .scaleEffect(1.25)
                .frame(width: 52, height: 52)
            Text(person.isSelf ? "You" : person.name)
                .font(SR.Text.title(14))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let pct = person.batteryPct {
                FamilyBattery(pct: pct)
            } else {
                Text("—").font(SR.monoMedium(13)).foregroundStyle(SR.inkGhost)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        // Opaque, edged and lifted: overlapped, a translucent card would
        // show the one beneath through it.
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SR.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(SR.line, lineWidth: 1))
        .shadow(color: SR.ink.opacity(0.14), radius: 4, x: 2, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(person.name). \(FamilyWords.line(person, places: places))\(person.batteryPct.map { ". Battery \($0) percent" } ?? "")")
        .accessibilityHint("Shows their day and week")
        .accessibilityAddTraits(.isButton)
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

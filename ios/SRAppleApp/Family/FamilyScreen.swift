import SwiftUI
import MapKit

/// Family: where everyone is, and — a tap away — how their day has gone.
///
/// The map is pinned above the list rather than scrolled with it: a map you can
/// pan inside a scroll view steals the scroll (see `RouteMap`), and here the
/// map is the point, so it keeps its gestures and the list scrolls beneath it.
/// Today's lines can be switched off from the map's corner, and the choice is
/// kept: some days the pins are the question and the lines are clutter.
///
/// A card is who, where and battery. Everything else — the day's figures, the
/// places, their own route — is on the person's page, one tap in.
///
/// Everything on screen is what the site decided this person may see — a card
/// with no day is somebody else's day, not a failure to load one.
struct FamilyScreen: View {
    @ObservedObject var store: FamilyStore
    @ObservedObject var companion: Companion
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera: MapCameraPosition = .automatic
    /// Today's lines on the map. Kept across launches.
    @AppStorage(FamilyTracks.key) private var showTracks = true

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
        }
        .navigationDestination(for: FamilyPersonRoute.self) { route in
            FamilyPersonScreen(store: store, subject: route.subject)
        }
        .task {
            await store.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: FamilyStore.refreshInterval)
                guard !Task.isCancelled else { break }
                await store.load()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.load() }
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
                    SRPageHeader(kicker: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Where everyone is.", strap: view.summary)
                        .padding(.top, 14)
                    ForEach(view.people) { person in
                        NavigationLink(value: FamilyPersonRoute(subject: person.subject)) {
                            FamilyCard(person: person)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("family-person-\(person.subject)")
                    }
                    footer(view)
                }
                .padding(.horizontal, SR.gutter)
                .padding(.bottom, 28)
            }
            .srRefreshable { await store.load() }
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

/// One person: who, where, battery. The day is on their page.
struct FamilyCard: View {
    let person: FamilyPerson
    @ObservedObject private var places = PlaceNamer.shared

    var body: some View {
        SRCard(interactive: true) {
            HStack(alignment: .center, spacing: 12) {
                FamilyPin(person: person)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(person.name).font(SR.Text.title()).foregroundStyle(SR.ink)
                        if person.isSelf {
                            Text("YOU").font(SR.Text.label()).tracking(1.2).foregroundStyle(SR.accent)
                        }
                    }
                    Text(FamilyWords.line(person, places: places))
                        .font(SR.Text.secondary())
                        .foregroundStyle(person.moving != nil ? SR.accentInk : SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if let pct = person.batteryPct { FamilyBattery(pct: pct) }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SR.inkGhost)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows their day")
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

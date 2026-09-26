import SwiftUI
import MapKit

/// Family: where everyone is, how today has gone, and how much battery they
/// have left to keep telling you.
///
/// The map is pinned above the list rather than scrolled with it: a map you can
/// pan inside a scroll view steals the scroll (see `RouteMap`), and here the
/// map is the point, so it keeps its gestures and the list scrolls beneath it.
/// Tapping a person flies the map to them and dims everyone else's line.
///
/// Everything on screen is what the site decided this person may see — a card
/// with no day is somebody else's day, not a failure to load one.
struct FamilyScreen: View {
    @ObservedObject var store: FamilyStore
    @ObservedObject var companion: Companion
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: String?

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
            if selected != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Everyone") {
                        SRHaptic.select()
                        withAnimation(.snappy) { selected = nil; camera = .automatic }
                    }
                    .accessibilityIdentifier("family-everyone")
                }
            }
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
            FamilyMapCanvas(people: view.people, interactive: true, showTrails: true, selected: selected, camera: $camera)
                .frame(height: 320)
                .accessibilityIdentifier("family-map")
            ScrollView {
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRPageHeader(kicker: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Where everyone is.", strap: view.summary)
                        .padding(.top, 14)
                    ForEach(view.people) { person in
                        FamilyCard(person: person, selected: selected == person.subject) {
                            focus(person)
                        }
                    }
                    footer(view)
                }
                .padding(.horizontal, SR.gutter)
                .padding(.bottom, 28)
            }
            .srRefreshable { await store.load() }
        }
    }

    private func focus(_ person: FamilyPerson) {
        guard let position = person.position else { return }
        SRHaptic.select()
        withAnimation(.snappy) {
            selected = person.subject
            camera = .region(MKCoordinateRegion(center: position.coordinate, latitudinalMeters: 1600, longitudinalMeters: 1600))
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

/// One person: who, where, battery — and, when it is yours to see, their day.
struct FamilyCard: View {
    let person: FamilyPerson
    var selected: Bool = false
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            SRCard(accented: selected, interactive: person.position != nil) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        FamilyPin(person: person)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(person.name).font(SR.Text.title()).foregroundStyle(SR.ink)
                                if person.isSelf {
                                    Text("YOU").font(SR.Text.label()).tracking(1.2).foregroundStyle(SR.accent)
                                }
                            }
                            Text(person.line)
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        if let pct = person.batteryPct { battery(pct) }
                    }
                    if let today = person.today { day(today) }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(person.position == nil)
        .accessibilityIdentifier("family-person-\(person.subject)")
    }

    private func battery(_ pct: Int) -> some View {
        let low = BatteryReading.isLow(pct)
        return HStack(spacing: 4) {
            Image(systemName: BatteryReading.symbol(pct))
                .font(.system(size: 15, weight: .semibold))
            Text("\(pct)%").font(SR.monoMedium(13))
        }
        .foregroundStyle(low ? SR.error : SR.inkSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(pct) percent\(low ? ", low" : "")")
    }

    private func day(_ today: FamilyPerson.Today) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(SR.divider).frame(height: 1)
            HStack(alignment: .top, spacing: 8) {
                figure(today.firstOut ?? "—", "First out")
                figure(today.timeOut, "Time out")
                figure(today.distance, "Moved")
            }
            if !today.stops.isEmpty {
                Text(today.stops.joined(separator: " → "))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Today: \(today.stops.joined(separator: ", then "))")
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(SR.Text.figure(20)).foregroundStyle(SR.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(label.uppercased()).font(SR.Text.label()).tracking(1.1).foregroundStyle(SR.inkMuted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

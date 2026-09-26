import SwiftUI
import MapKit

/// One person, in full: where they are on a map of their own, whether they are
/// moving, their battery — and, when their day is yours to see, how it has
/// gone: when they first went out, how long, how far, and where, in order.
///
/// Read live from the store rather than handed a copy, so the page moves with
/// the 15-second refresh like the tab it was opened from. Somebody who drops
/// out of the view (sharing switched off) leaves a page that says so.
struct FamilyPersonScreen: View {
    @ObservedObject var store: FamilyStore
    let subject: String
    @ObservedObject private var places = PlaceNamer.shared
    @AppStorage(FamilyTracks.key) private var showTracks = true
    @State private var camera: MapCameraPosition = .automatic

    private var person: FamilyPerson? { store.view?.people.first { $0.subject == subject } }

    var body: some View {
        Group {
            if let person {
                content(person)
            } else {
                SREmpty(title: "Not in your family view", icon: "person.crop.circle.badge.questionmark",
                        message: "They may have stopped sharing their location.")
                    .frame(maxHeight: .infinity)
            }
        }
        .srGround(.warm)
        .navigationTitle(person?.name ?? "Family")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ person: FamilyPerson) -> some View {
        VStack(spacing: 0) {
            if person.position != nil {
                FamilyMapCanvas(people: [person], interactive: true, showTrails: showTracks, selected: person.subject, camera: $camera)
                    .frame(height: 280)
                    .overlay(alignment: .topTrailing) {
                        if person.today?.trail.isEmpty == false {
                            FamilyTracksToggle(on: $showTracks).padding(10)
                        }
                    }
                    .accessibilityIdentifier("family-person-map")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    header(person)
                    if let today = person.today {
                        day(today)
                    } else if person.sharing {
                        Text("Their day — when they went out, how far, where — is theirs and the family admins' to see.")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    if let position = person.position {
                        Button {
                            SRHaptic.tap()
                            openInMaps(person, position)
                        } label: {
                            SRButtonLabel(title: "Open in Maps", icon: "map", fill: true)
                        }
                        .srButton()
                        .controlSize(.large)
                        .padding(.top, 4)
                        .accessibilityIdentifier("family-person-open-maps")
                    }
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .srRefreshable { await store.load() }
        }
    }

    private func header(_ person: FamilyPerson) -> some View {
        SRCard(accented: person.moving != nil) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    FamilyPin(person: person, emphasised: true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(person.name).font(SR.Text.display(22)).foregroundStyle(SR.ink)
                            if person.isSelf {
                                Text("YOU").font(SR.Text.label()).tracking(1.2).foregroundStyle(SR.accent)
                            }
                        }
                        Text(FamilyWords.line(person, places: places))
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    if let pct = person.batteryPct { FamilyBattery(pct: pct) }
                }
                if let moving = person.moving {
                    HStack(spacing: 8) {
                        Image(systemName: moving.symbol).foregroundStyle(SR.accent)
                        Text("\(Int(moving.speedKmh.rounded())) km/h\(movingFor(moving))")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let seen = person.lastSeenAt, !shortAgo(seen).isEmpty {
                    Text("LAST FIX \(shortAgo(seen).uppercased()) AGO")
                        .font(SR.Text.mono())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                }
            }
        }
    }

    private func movingFor(_ moving: FamilyPerson.Moving) -> String {
        let ago = shortAgo(moving.since)
        return ago.isEmpty ? "" : " · moving for \(ago)"
    }

    private func day(_ today: FamilyPerson.Today) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Today").padding(.horizontal, 4)
            SRCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 8) {
                        figure(today.firstOut ?? "—", "First out")
                        figure(today.timeOut, "Time out")
                        figure(today.distance, "Moved")
                    }
                    if !today.stops.isEmpty {
                        Rectangle().fill(SR.divider).frame(height: 1)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(today.stops.enumerated()), id: \.offset) { index, stop in
                                stopRow(stop, first: index == 0, last: index == today.stops.count - 1)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Places today: \(today.stops.joined(separator: ", then "))")
                    }
                }
            }
        }
    }

    /// A stop on the day's line: a dot, joined to the next by a rule.
    private func stopRow(_ stop: String, first: Bool, last: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(SR.divider)
                    .frame(width: 2)
                    .padding(.top, first ? 14 : 0)
                    .padding(.bottom, last ? 14 : 0)
                Circle()
                    .fill(last ? SR.accent : SR.inkGhost)
                    .frame(width: 10, height: 10)
            }
            .frame(width: 14, height: 28)
            Text(stop)
                .font(last ? SR.Text.bodyMedium(15) : SR.Text.secondary(15))
                .foregroundStyle(last ? SR.ink : SR.inkSecondary)
            Spacer(minLength: 0)
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

    private func openInMaps(_ person: FamilyPerson, _ position: FamilyPerson.Position) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: position.coordinate))
        item.name = person.name
        item.openInMaps()
    }
}

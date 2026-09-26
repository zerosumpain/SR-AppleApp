import SwiftUI
import MapKit

/// Everyone's pin, and — where the view carries a day — today's line.
///
/// One canvas for both sizes: the mini-map on Today (no gestures, no lines)
/// and the Family tab's map (pan, zoom, today's trails, and a camera that
/// moves to whoever was tapped in the list).
struct FamilyMapCanvas: View {
    let people: [FamilyPerson]
    var interactive: Bool = false
    var showTrails: Bool = false
    var selected: String? = nil
    @Binding var camera: MapCameraPosition

    var body: some View {
        Map(position: $camera, interactionModes: interactive ? MapInteractionModes.all : []) {
            if showTrails {
                ForEach(people) { person in
                    if let today = person.today {
                        ForEach(Array(today.segments().enumerated()), id: \.offset) { _, segment in
                            MapPolyline(coordinates: segment)
                                .stroke(FamilyPin.tone(for: person).opacity(selected == nil || selected == person.subject ? 0.85 : 0.25), lineWidth: 3)
                        }
                    }
                }
            }
            ForEach(people.filter { $0.position != nil }) { person in
                if let position = person.position {
                    Annotation(person.name, coordinate: position.coordinate, anchor: .center) {
                        FamilyPin(person: person, emphasised: selected == person.subject)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
    }
}

/// A person on the map: their initial on a disc, ringed in paper so it holds
/// against any tile. The disc's colour says where they are; the initial says
/// who, so the colour never carries the meaning alone.
struct FamilyPin: View {
    let person: FamilyPerson
    var emphasised: Bool = false

    static func tone(for person: FamilyPerson) -> Color {
        if person.isSelf { return SR.ink }
        switch person.status {
        case "home": return SR.accentInk
        case "out": return SR.accent
        default: return SR.inkGhost
        }
    }

    var body: some View {
        let size: CGFloat = emphasised ? 38 : 30
        Text(person.initial)
            .font(SR.monoBold(emphasised ? 15 : 13))
            .foregroundStyle(SR.paper)
            .frame(width: size, height: size)
            .background(Self.tone(for: person), in: Circle())
            .overlay(Circle().stroke(SR.paper, lineWidth: 2.5))
            .shadow(color: SR.ink.opacity(0.25), radius: 3, y: 1)
            .accessibilityLabel("\(person.name), \(person.line)")
    }
}

/// The Today card: where everyone is, in words — who is on the move and
/// where, then everybody else in one line — and a map glyph into the tab.
///
/// It was a map. A map on Today is a picture of pins you have to read, and at
/// 180 points high it said little a sentence does not say better; the Family
/// tab has the real one. Draws nothing until there is somebody to show.
struct FamilySummary: View {
    @ObservedObject var store: FamilyStore
    @ObservedObject private var places = PlaceNamer.shared
    let open: () -> Void

    var body: some View {
        if let view = store.view, !view.people.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SRSectionLabel(text: "Family", trailing: store.freshness)
                    .padding(.horizontal, 4)
                Button {
                    SRHaptic.tap()
                    open()
                } label: {
                    SRCard(interactive: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(view.moving) { person in movingRow(person) }
                            if !view.moving.isEmpty {
                                Rectangle().fill(SR.divider).frame(height: 1)
                            }
                            HStack(alignment: .center, spacing: 12) {
                                faces(view.people)
                                Text(view.summary)
                                    .font(SR.Text.secondary(15))
                                    .foregroundStyle(SR.ink)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "map")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(SR.accent)
                                    .frame(width: 34, height: 34)
                                    .background(SR.accent.opacity(0.12), in: Circle())
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(view))
                .accessibilityHint("Opens Family")
                .accessibilityIdentifier("today-family")
            }
        }
    }

    private func movingRow(_ person: FamilyPerson) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: person.moving?.symbol ?? "figure.walk")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SR.paper)
                .frame(width: 30, height: 30)
                .background(SR.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(person.movingLead ?? person.name)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                Text(whereLine(person))
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// "near Station Road, Darlington · 5 km/h" — or the site's own line
    /// until the phone has a name for the spot.
    private func whereLine(_ person: FamilyPerson) -> String {
        let speed = person.moving.map { " · \(Int($0.speedKmh.rounded())) km/h" } ?? ""
        if let position = person.position, let name = places.name(lat: position.lat, lon: position.lon) {
            return "near \(name)\(speed)"
        }
        return person.line + speed
    }

    /// Everyone's initial, overlapped, in their map colour.
    private func faces(_ people: [FamilyPerson]) -> some View {
        HStack(spacing: -8) {
            ForEach(people.prefix(5)) { person in
                Text(person.initial)
                    .font(SR.monoBold(11))
                    .foregroundStyle(SR.paper)
                    .frame(width: 26, height: 26)
                    .background(FamilyPin.tone(for: person), in: Circle())
                    .overlay(Circle().stroke(SR.paper, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }

    private func spoken(_ view: HouseholdView) -> String {
        let moving = view.moving.map { "\($0.movingLead ?? $0.name), \(whereLine($0))" }
        return (["Family"] + moving + [view.summary]).joined(separator: ". ")
    }
}

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

/// Today's hero: where everyone is, as places. Each place is a heading —
/// "Home", "School", "Bethesda Terrace" — with the people at it under it as
/// chips; anybody not seen lately or not sharing is a line at the foot.
///
/// No map. A map on Today was a picture of pins to decode, and on a phone the
/// pins for two people in the same house sit on top of each other; grouped by
/// place, the same view reads as a sentence. The Family tab keeps the map, one
/// tap away from "Map" beside the heading. Draws nothing until there is
/// somebody to show.
struct TodayFamilyCard: View {
    @ObservedObject var store: FamilyStore
    @ObservedObject private var places = PlaceNamer.shared
    let open: () -> Void

    var body: some View {
        if let view = store.view, !view.people.isEmpty {
            let groups = view.places()
            let absent = view.absentLines
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    // No counts beside it: the places below are the counts.
                    SRSectionLabel(text: "Family")
                    Button {
                        SRHaptic.tap()
                        open()
                    } label: {
                        Text("Map")
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.accentInk)
                            .padding(.vertical, 6)
                            .padding(.leading, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open the family map")
                    .accessibilityIdentifier("today-family")
                }
                .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, place in
                        if index > 0 {
                            Rectangle().fill(SR.divider).frame(height: 1)
                        }
                        placeSection(place)
                    }
                    if !absent.isEmpty {
                        if !groups.isEmpty {
                            Rectangle().fill(SR.divider).frame(height: 1)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(absent, id: \.self) { line in
                                Text(line)
                                    .font(SR.Text.secondary())
                                    .foregroundStyle(SR.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SR.cardPadding)
                        .padding(.vertical, 12)
                    }
                }
                .srGlassCard(.paper)
            }
        }
    }

    /// One place: its name, how many are there, and a chip each.
    private func placeSection(_ place: FamilyPlace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: place.isHome ? "house" : place.isMoving ? "figure.walk" : "mappin.and.ellipse")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(place.isHome ? SR.accentInk : SR.accentDeep)
                    .accessibilityHidden(true)
                Text(place.name)
                    .font(SR.Text.display(17))
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text("\(place.people.count)")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityLabel(place.people.count == 1 ? "1 person" : "\(place.people.count) people")
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            // Two across, one at a large text size — the grid folds rather
            // than squeezing a name.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(place.people) { person in
                    Button {
                        SRHaptic.tap()
                        open()
                    } label: {
                        chip(person)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today-family-\(person.subject)")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private func chip(_ person: FamilyPerson) -> some View {
        HStack(spacing: 10) {
            Text(person.initial)
                .font(SR.Text.title(15))
                .foregroundStyle(SR.paper)
                .frame(width: 36, height: 36)
                .background(Circle().fill(SR.ink))
                .overlay {
                    if person.moving != nil {
                        Circle().stroke(SR.accent, lineWidth: 2.5).padding(-3)
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(person.name)
                        .font(SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                    if person.isSelf {
                        Text("(you)")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                    }
                }
                HStack(spacing: 6) {
                    if let sub = subline(person) {
                        Text(sub)
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkSecondary)
                            .lineLimit(2)
                    }
                    if let pct = person.batteryPct, BatteryReading.isLow(pct) {
                        HStack(spacing: 3) {
                            Image(systemName: BatteryReading.symbol(pct))
                            Text("\(pct)%")
                        }
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.error)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Battery low, \(pct) percent")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: SR.tapTarget + 12, alignment: .leading)
        .background(SR.Glass.rowFill, in: RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Family")
    }

    /// "Walking · 5 km/h" on the move — "near Station Road" once the phone has
    /// a name for the spot — else when they were seen: "Seen 6m ago".
    private func subline(_ person: FamilyPerson) -> String? {
        guard let moving = person.moving else { return person.seenLine }
        let verb: String = moving.verb.prefix(1).uppercased() + String(moving.verb.dropFirst())
        let speed = "\(Int(moving.speedKmh.rounded())) km/h"
        if let position = person.position, let name = places.name(lat: position.lat, lon: position.lon) {
            return "\(verb) near \(name) · \(speed)"
        }
        return "\(verb) · \(speed)"
    }
}

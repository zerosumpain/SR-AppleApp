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

/// Today's hero: who is where, one row per place.
///
/// Each row is a place — "Home", "School", "Bethesda Terrace" — led by the
/// initials of whoever is there, their circles overlapping so a crowd at home
/// reads as one cluster at a glance. Initials are unique across the household
/// (`HouseholdView.initials`: JK, KK, JeK), so the circles say who without a
/// name beside them. Anybody not seen lately or not sharing is the last row,
/// in dashed circles. The Family tab keeps the map, one tap on any row away.
/// Draws nothing until there is somebody to show.
struct TodayFamilyCard: View {
    @ObservedObject var store: FamilyStore
    @ObservedObject private var places = PlaceNamer.shared
    let open: () -> Void

    /// Past this many, the stack ends in a "+N" circle.
    private static let stackLimit = 4

    var body: some View {
        if let view = store.view, !view.people.isEmpty {
            let groups = view.places()
            let initials = view.initials
            let absent = view.people.filter { $0.status == "unknown" || $0.status == "off" }
            VStack(alignment: .leading, spacing: 10) {
                SRSectionLabel(text: "Family tracking", prominent: true)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, place in
                        if index > 0 { divider }
                        Button {
                            SRHaptic.tap()
                            open()
                        } label: {
                            placeRow(place, initials: initials)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today-family-\(place.name.lowercased())")
                    }
                    if !absent.isEmpty {
                        if !groups.isEmpty { divider }
                        absentRow(absent, lines: view.absentLines, initials: initials)
                    }
                }
                .srGlassCard(.paper)
                // Any row opens the tab. The circles say who; the only words
                // are where (John asked for the card that spare, 2026-10-05) —
                // who is doing what, how fast and how long ago are on Family.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("today-family")
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(SR.divider).frame(height: 1)
    }

    // MARK: Rows

    private func placeRow(_ place: FamilyPlace, initials: [String: String]) -> some View {
        HStack(spacing: 14) {
            stack(place.people, initials: initials)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if place.isHome {
                        Image(systemName: "house")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SR.accentInk)
                            .accessibilityHidden(true)
                    }
                    // DM Sans, not Inter Display: the place is a label for
                    // the circles, and the circles are the headline. One
                    // line, so a row never changes height as names resolve —
                    // a card that grows under the thumb moves every card
                    // below it, and a tap on one of those then misses.
                    Text(place.name)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SR.inkGhost)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 11)
        .frame(minHeight: SR.tapTarget + 22)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(place))
        .accessibilityHint("Opens Family")
    }

    private func absentRow(_ people: [FamilyPerson], lines: [String], initials: [String: String]) -> some View {
        HStack(alignment: .center, spacing: 14) {
            stack(people, initials: initials, ghost: true)
            // Where they are is not known, so that is the place.
            Text("Unknown")
                .font(SR.Text.title())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 11)
        // The full sentences ("Kit was last at The Reservoir, 2h ago") stay
        // for VoiceOver, where they cost no room on the card.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.joined(separator: " "))
    }

    // MARK: The cluster

    /// Overlapping circles, the first on top. A ring in the accent for anyone
    /// on the move, a red dot for a low battery, dashed for someone absent.
    private func stack(_ people: [FamilyPerson], initials: [String: String], ghost: Bool = false) -> some View {
        let shown = Array(people.prefix(Self.stackLimit))
        let extra = people.count - shown.count
        return HStack(spacing: -12) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, person in
                circle(initials[person.subject] ?? person.initial, ghost: ghost,
                       moving: person.moving != nil, low: lowBattery(person))
                    .zIndex(Double(shown.count - index))
            }
            if extra > 0 {
                circle("+\(extra)", ghost: ghost, moving: false, low: false)
            }
        }
        .accessibilityHidden(true)
    }

    private func circle(_ text: String, ghost: Bool, moving: Bool, low: Bool) -> some View {
        Text(text)
            .font(SR.Text.title(text.count > 2 ? 13 : 14))
            .tracking(-0.3)
            .foregroundStyle(ghost ? SR.inkMuted : SR.paper)
            .lineLimit(1)
            .frame(width: 42, height: 42)
            .background {
                if ghost {
                    Circle()
                        .fill(SR.surface)
                        .overlay(Circle().strokeBorder(SR.inkGhost, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                } else {
                    Circle()
                        .fill(SR.ink)
                        .overlay(Circle().strokeBorder(moving ? SR.accent : SR.surface, lineWidth: 2.5))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if low {
                    Circle()
                        .fill(SR.error)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(SR.surface, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }
    }

    // MARK: Words

    private func lowBattery(_ person: FamilyPerson) -> Bool {
        person.batteryPct.map(BatteryReading.isLow) ?? false
    }

    /// "You · walking · 5 km/h", "KK and JeK · seen 4m ago", "Everyone ·
    /// seen 2m ago" — who, then the freshest thing known about them.

    /// "walking · 5 km/h" (near a street, once the phone has a name) for a
    /// group with somebody moving, else "seen 4m ago" from the site's line.
    private func state(_ place: FamilyPlace) -> String {
        if let mover = place.people.first(where: { $0.moving != nil }), let moving = mover.moving {
            let speed = "\(Int(moving.speedKmh.rounded())) km/h"
            if let position = mover.position, let name = places.name(lat: position.lat, lon: position.lon),
               name.lowercased() != place.name.lowercased() {
                return "\(moving.verb) near \(name) · \(speed)"
            }
            return "\(moving.verb) · \(speed)"
        }
        guard let seen = place.people.compactMap(\.seenLine).first else { return "here now" }
        return seen.prefix(1).lowercased() + String(seen.dropFirst())
    }

    /// "Home: Karen Kelly and Jennifer Kelly, seen 4m ago."
    private func spoken(_ place: FamilyPlace) -> String {
        let names = place.people.map { $0.isSelf ? "you" : $0.name }
        let who: String
        if names.count <= 1 {
            who = names.first ?? ""
        } else {
            who = names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
        var sentence = "\(place.name): \(who), \(state(place))."
        for person in place.people where lowBattery(person) {
            sentence += " \(person.name)'s battery is low, \(person.batteryPct ?? 0) percent."
        }
        return sentence
    }
}

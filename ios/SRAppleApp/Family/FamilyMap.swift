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

/// Today's hero: where everyone is. The map on top, then one row per person
/// who is sharing, then a line for anybody who is not.
///
/// Today leads with this now. An earlier version cut the map back to a
/// sentence because a 180-point map of pins said little on its own — true, and
/// the answer is the rows under it, not dropping the map: the map says WHERE at
/// a glance, the rows say WHO and WHAT in words, and the colour of a pin never
/// carries the meaning alone. Draws nothing until there is somebody to show.
struct TodayFamilyCard: View {
    @ObservedObject var store: FamilyStore
    @ObservedObject private var places = PlaceNamer.shared
    let open: () -> Void
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        if let view = store.view, !view.people.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                map(view)
                ForEach(Array(sharing(view).enumerated()), id: \.element.id) { index, person in
                    if index > 0 {
                        Rectangle().fill(SR.divider).frame(height: 1).padding(.leading, 70)
                    } else {
                        Rectangle().fill(SR.divider).frame(height: 1)
                    }
                    Button {
                        SRHaptic.tap()
                        open()
                    } label: {
                        row(person)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today-family-\(person.subject)")
                }
                let hidden = view.people.filter { !$0.sharing }
                if !hidden.isEmpty {
                    Rectangle().fill(SR.divider).frame(height: 1)
                    Text(notSharing(hidden))
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, SR.cardPadding)
                        .padding(.vertical, 12)
                }
            }
            .srGlassCard(.paper)
        }
    }

    /// The map, not interactive: the whole of it is one tap into the Family
    /// tab, which has the one you can pan. The chip names the counts, so the
    /// section needs no heading above it.
    private func map(_ view: HouseholdView) -> some View {
        Button {
            SRHaptic.tap()
            open()
        } label: {
            FamilyMapCanvas(people: view.people, camera: $camera)
                .allowsHitTesting(false)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        Text("FAMILY")
                        Text("·").accessibilityHidden(true)
                        Text(view.summary.uppercased())
                    }
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .srGlass(.paper, in: Capsule())
                    .padding(12)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SR.ink)
                        .frame(width: 34, height: 34)
                        .srGlass(.paper, in: Circle())
                        .padding(12)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(view))
        .accessibilityHint("Opens Family")
        .accessibilityIdentifier("today-family")
    }

    private func row(_ person: FamilyPerson) -> some View {
        HStack(spacing: 14) {
            Text(person.initial)
                .font(SR.Text.title(16))
                .foregroundStyle(person.position == nil ? SR.inkMuted : SR.paper)
                .frame(width: 40, height: 40)
                .background {
                    if person.position == nil {
                        Circle().strokeBorder(SR.inkGhost, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    } else {
                        Circle().fill(FamilyPin.tone(for: person))
                    }
                }
                .overlay {
                    if person.moving != nil {
                        Circle().stroke(SR.accent, lineWidth: 2.5).padding(-3)
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(person.name)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    if person.isSelf {
                        Text("(you)")
                            .font(SR.Text.body())
                            .foregroundStyle(SR.inkMuted)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(whereLine(person))
                        .font(SR.Text.secondary())
                        .foregroundStyle(person.status == "unknown" ? SR.inkMuted : SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SR.inkGhost)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, SR.rowPadding)
        .frame(minHeight: SR.tapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Family")
    }

    /// Whoever is sharing, you first, then whoever is moving, then the rest in
    /// the site's order.
    private func sharing(_ view: HouseholdView) -> [FamilyPerson] {
        let people = view.people.filter(\.sharing)
        return people.filter(\.isSelf)
            + people.filter { !$0.isSelf && $0.moving != nil }
            + people.filter { !$0.isSelf && $0.moving == nil }
    }

    /// "Walking · near Bethesda Terrace · 5 km/h" while moving; the site's own
    /// line ("At School · seen 6m ago") otherwise.
    private func whereLine(_ person: FamilyPerson) -> String {
        guard let moving = person.moving else { return person.line }
        let speed = " · \(Int(moving.speedKmh.rounded())) km/h"
        let verb: String = moving.verb.prefix(1).uppercased() + String(moving.verb.dropFirst())
        if let position = person.position, let name = places.name(lat: position.lat, lon: position.lon) {
            return "\(verb) · near \(name)\(speed)"
        }
        return "\(verb)\(speed)"
    }

    /// "Pat isn't sharing their location." — or a list, for more than one.
    private func notSharing(_ people: [FamilyPerson]) -> String {
        let names = people.map(\.name)
        switch names.count {
        case 1: return "\(names[0]) isn't sharing their location."
        default:
            return "\(names.dropLast().joined(separator: ", ")) and \(names.last ?? "") aren't sharing their location."
        }
    }

    private func spoken(_ view: HouseholdView) -> String {
        "Family map. \(view.summary)"
    }
}

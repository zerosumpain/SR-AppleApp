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

/// The Today card: the whole household at a glance, one tap from the tab.
struct FamilyMiniMap: View {
    @ObservedObject var store: FamilyStore
    let open: () -> Void
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        if let view = store.view, !view.placed.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SRSectionLabel(text: "Family", trailing: store.freshness)
                    .padding(.horizontal, 4)
                Button {
                    SRHaptic.tap()
                    open()
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        FamilyMapCanvas(people: view.people, camera: $camera)
                            .frame(height: 180)
                            // The map is a UIKit view and can swallow a tap
                            // even with interaction off; the button over it
                            // takes the tap instead (same as `RouteMap`).
                            .allowsHitTesting(false)
                        HStack(spacing: 10) {
                            Text(view.summary)
                                .font(SR.Text.secondary(15))
                                .foregroundStyle(SR.ink)
                                .lineLimit(2)
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SR.inkMuted)
                        }
                        .padding(.horizontal, SR.cardPadding)
                        .padding(.vertical, 12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
                    .srGlassCard(.paper, interactive: true)
                    .contentShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Family map. \(view.summary)")
                .accessibilityHint("Opens Family")
                .accessibilityIdentifier("today-family")
            }
            // Re-fit when the pins change, not only on first paint.
            .onChange(of: view.placed.map(\.subject)) { _, _ in camera = .automatic }
        }
    }
}

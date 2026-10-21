import SwiftUI
import MapKit

/// Everyone's pin, and — where the view carries a day — today's line.
///
/// One canvas for every map of the family: still and bare where it is only
/// a picture (no gestures, no lines), and the Family tab's own (pan, zoom,
/// today's trails, and a camera that moves to whoever was tapped in the
/// list). Today draws no map: it lists places (`TodayFamilyCard`).
struct FamilyMapCanvas: View {
    let people: [FamilyPerson]
    var interactive: Bool = false
    var showTrails: Bool = false
    var selected: String? = nil
    /// The closest the map frames its people, across: a neighbourhood for the
    /// family, a little wider for one person's page.
    var minSpanMetres: CLLocationDistance = FamilyMapFraming.familySpan
    /// A place chosen on the strip above the map: frame these points instead
    /// of everyone, and keep them framed as people move. Nil: everyone.
    var focus: [CLLocationCoordinate2D]? = nil
    @Binding var camera: MapCameraPosition
    @AppStorage(FamilyMapLook.key) private var look: FamilyMapLook = .satellite

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
        .mapStyle(look.style)
        // Framed on the people, never the trails, and never closer than
        // `minSpanMetres`. The automatic camera fitted everything drawn: one
        // pin (a person's page, or everyone at home) zoomed to the rooftops,
        // and a long trail zoomed the whole family out. Re-framed as people
        // move until somebody pans or zooms; then the map is theirs.
        .onAppear { frame() }
        .onChange(of: FamilyMapFraming.key(people)) { _, _ in frame() }
        // A place chosen (or "Everyone" again) is a request to look there now,
        // whoever last moved the map.
        .onChange(of: focusKey) { _, _ in frame(force: true) }
    }

    private var focusKey: String {
        guard let focus else { return "everyone" }
        return focus.map { p in "\((p.latitude * 1e4).rounded()),\((p.longitude * 1e4).rounded())" }.joined(separator: "|")
    }

    private func frame(force: Bool = false) {
        let points = focus ?? people.compactMap { $0.position?.coordinate }
        let span = focus == nil ? minSpanMetres : FamilyMapFraming.placeSpan
        guard force || !camera.positionedByUser,
              let region = FamilyMapFraming.region(points, minSpanMetres: span)
        else { return }
        if force {
            withAnimation(.snappy) { camera = .region(region) }
        } else {
            camera = .region(region)
        }
    }
}

/// How a family map frames its people. PURE.
enum FamilyMapFraming {
    /// About a neighbourhood across: the closest the family map comes in.
    static let familySpan: CLLocationDistance = 1_500
    /// One person's page opens a little wider: where they are, and around it.
    static let personSpan: CLLocationDistance = 2_000
    /// One place chosen on the strip: the place and its street.
    static let placeSpan: CLLocationDistance = 600
    /// Room around the outermost pins, as a share of the spread.
    static let margin = 1.35

    /// The region that holds every point with a little margin, and is at least
    /// `minSpanMetres` across both ways. Nil with no points.
    static func region(_ points: [CLLocationCoordinate2D], minSpanMetres: CLLocationDistance) -> MKCoordinateRegion? {
        guard let first = points.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for p in points.dropFirst() {
            minLat = min(minLat, p.latitude); maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }
        let centre = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let metresPerDegreeLat = 111_320.0
        let metresPerDegreeLon = max(1, metresPerDegreeLat * cos(centre.latitude * .pi / 180))
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * margin, minSpanMetres / metresPerDegreeLat),
            longitudeDelta: max((maxLon - minLon) * margin, minSpanMetres / metresPerDegreeLon)
        )
        return MKCoordinateRegion(center: centre, span: span)
    }

    /// Changes when somebody moves far enough to matter (about 100 m), not
    /// with every fix: the camera is not chasing GPS jitter.
    static func key(_ people: [FamilyPerson]) -> String {
        people.compactMap { p in
            p.position.map { "\(p.subject):\(($0.lat * 1000).rounded()),\(($0.lon * 1000).rounded())" }
        }.joined(separator: "|")
    }
}

/// Satellite (imagery with roads and names on top) or the plain street map.
/// Remembered on the phone: it is a way of looking, not a visit.
enum FamilyMapLook: String {
    case satellite, streets

    static let key = "family-map-look"

    var style: MapStyle {
        switch self {
        case .satellite: return .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .streets: return .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
        }
    }
}

/// Flips the family map between satellite and streets. A glyph the size of
/// the tracks switch, beside it.
struct FamilyMapLookButton: View {
    @AppStorage(FamilyMapLook.key) private var look: FamilyMapLook = .satellite

    var body: some View {
        Button {
            SRHaptic.select()
            look = look == .satellite ? .streets : .satellite
        } label: {
            Image(systemName: look == .satellite ? "map" : "globe.europe.africa.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SR.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(look == .satellite ? "Show the street map" : "Show satellite")
        .accessibilityIdentifier("family-map-look")
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
/// (`HouseholdView.initials`: Jo, Ka, Je), so the circles say who without a
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
            let absent = view.absent
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SRSectionLabel(text: "Family tracking", prominent: true)
                    Spacer()
                    TodayLiveDot(updated: store.updated, freshness: store.freshness)
                }
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
                // A slight edge in the site's orange: the one card on Today
                // that is about people, set apart from the doors below it.
                .overlay(
                    RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                        .strokeBorder(SR.accent.opacity(0.7), lineWidth: 1.5)
                        .allowsHitTesting(false)
                )
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

    /// Overlapping circles, the first on top. The edge says how recently each
    /// was seen (`edge`), a red dot is a low battery, dashed is someone absent.
    private func stack(_ people: [FamilyPerson], initials: [String: String], ghost: Bool = false) -> some View {
        let shown = Array(people.prefix(Self.stackLimit))
        let extra = people.count - shown.count
        return HStack(spacing: -12) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, person in
                circle(initials[person.subject] ?? person.initial, ghost: ghost,
                       freshness: person.freshness(), low: lowBattery(person))
                    .zIndex(Double(shown.count - index))
            }
            if extra > 0 {
                circle("+\(extra)", ghost: ghost, freshness: .unknown, low: false)
            }
        }
        .accessibilityHidden(true)
    }

    /// The edge says how recently the site heard from them: green within the
    /// hour, amber one to two hours, red two hours or more. Somebody placed at
    /// their LAST known spot (`FamilyPerson.placed`) reads as where they were,
    /// with the edge saying how long ago.
    static func edge(_ freshness: FamilyPerson.Freshness) -> Color {
        switch freshness {
        case .fresh: return SR.good
        case .aging: return SR.warn
        case .stale: return SR.error
        case .unknown: return SR.surface
        }
    }

    private func circle(_ text: String, ghost: Bool, freshness: FamilyPerson.Freshness, low: Bool) -> some View {
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
                        .overlay(Circle().strokeBorder(Self.edge(freshness), lineWidth: 3))
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

/// The family card's live light: green when the site filed the view in the
/// last five minutes, amber within the hour, grey after. When fresh positions
/// arrive it pulses once — a ring that flashes and spreads — and then sits
/// still until the next ones. Never on a loop: a dot that breathes forever
/// says nothing about whether anything changed.
struct TodayLiveDot: View {
    /// `FamilyStore.updated`: when the site filed the view. The pulse keys
    /// on it, so a re-read that brings nothing new does not flash.
    let updated: String?
    /// `FamilyStore.freshness`: "Updated 2m ago", read out.
    let freshness: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Pulse: CaseIterable {
        case rest, flash, spread

        var scale: CGFloat { self == .spread ? 2.4 : 1 }
        var opacity: Double { self == .flash ? 0.7 : 0 }

        /// The curve INTO this phase. Back to rest is instant: the ring is
        /// already invisible by then.
        var animation: Animation? {
            switch self {
            case .rest: return nil
            case .flash: return .linear(duration: 0.05)
            case .spread: return .easeOut(duration: 0.6)
            }
        }
    }

    /// Green, amber or grey by how long ago the view was filed.
    var tone: Color {
        guard let updated, let at = isoDate(updated) else { return SR.inkGhost }
        let age = Date().timeIntervalSince(at)
        if age < 5 * 60 { return SR.good }
        if age < 60 * 60 { return SR.warn }
        return SR.inkGhost
    }

    var body: some View {
        let tint = tone
        Circle()
            .fill(tint)
            .frame(width: 6, height: 6)
            .overlay {
                if !reduceMotion {
                    Circle()
                        .stroke(tint, lineWidth: 1.5)
                        .phaseAnimator(Pulse.allCases, trigger: updated) { ring, phase in
                            ring
                                .scaleEffect(phase.scale)
                                .opacity(phase.opacity)
                        } animation: { phase in
                            phase.animation
                        }
                }
            }
            .frame(width: 14, height: 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(freshness ?? "Not updated yet")
            .accessibilityIdentifier("today-family-live")
    }
}

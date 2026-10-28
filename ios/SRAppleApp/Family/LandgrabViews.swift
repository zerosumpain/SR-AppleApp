import SwiftUI
import MapKit

// Landgrab on the steps page, and its map.
//
// Two views of one ledger, switched at the top of the section and the map
// (`LandgrabMode`, remembered on the phone):
//
// - Family (the default): everything the family has explored, all time, as
//   one — the total, the day's new ground, everyone's part, the places it
//   spans, and a solid map with the newest ground lit up.
// - This week: the game. This week's ground, won and lost, by person; "See
//   what changed" pushes the map of the hexes that changed owner and the
//   outings that took them.
//
// The family view needs the site's explored answer; without it (an older
// site, Health down) the section is the weekly game exactly as before. Rules
// and words are in `LandgrabModels.swift`; this file only draws.

/// Pushes the map for one week.
struct LandgrabMapRef: Hashable {
    /// The Monday, "2026-09-28".
    let week: String
}

// MARK: - The section on the steps page

/// Landgrab under the step board: the family's ground (the default) or this
/// week's game. Draws nothing at all until there is something to show —
/// never a spinner, never an error on the steps page.
struct LandgrabSection: View {
    @ObservedObject private var store = LandgrabStore.shared
    @AppStorage(LandgrabMode.key) private var modeRaw = LandgrabMode.family.rawValue

    var body: some View {
        let explored = store.explored.flatMap { Landgrab.showsExplored($0) ? $0 : nil }
        let board = store.board.flatMap { Landgrab.shows($0) ? $0 : nil }
        let week = board.flatMap(Landgrab.currentWeek)
        if explored != nil || week != nil {
            let mode = LandgrabMode.effective(modeRaw, hasFamily: explored != nil, hasWeek: week != nil)
            VStack(alignment: .leading, spacing: SR.cardGap) {
                if mode == .family, let explored {
                    SRSectionLabel(text: "Landgrab · all time", trailing: Landgrab.sinceLabel(explored))
                        .padding(.horizontal, 4)
                } else if let week {
                    SRSectionLabel(text: "Landgrab · this week", trailing: Landgrab.weekRange(start: week.start, end: week.end))
                        .padding(.horizontal, 4)
                }
                if explored != nil, week != nil {
                    LandgrabModePicker(mode: mode) { modeRaw = $0.rawValue }
                }
                if mode == .family, let explored {
                    LandgrabFamilyCard(explored: explored, mapWeek: week?.start ?? explored.weekStart)
                } else if let board, let week {
                    weekContent(board, week)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("landgrab-section")
        }
    }

    private func weekContent(_ board: LandgrabBoard, _ week: LandgrabWeek) -> some View {
        let people = Landgrab.ranked(week.people)
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            VStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    if index > 0 { Divider().overlay(SR.divider).padding(.leading, 64) }
                    LandgrabRow(person: person, tied: Landgrab.tied(person, in: people))
                }
                Divider().overlay(SR.divider)
                NavigationLink(value: LandgrabMapRef(week: week.start)) {
                    LandgrabLinkRow(icon: "map", title: "See what changed")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens a map of the ground that changed hands, and the outings that took it")
                .accessibilityIdentifier("landgrab-see-changes")
            }
            .padding(.vertical, 4)
            .srGlassCard(.paper)

            if let line = Landgrab.lastWeekLine(board) {
                Label(line, systemImage: "flag.checkered")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("landgrab-last-week")
            }
        }
    }
}

/// Family or This week, as a segmented control.
struct LandgrabModePicker: View {
    let mode: LandgrabMode
    let choose: (LandgrabMode) -> Void

    var body: some View {
        Picker("Landgrab", selection: Binding(get: { mode }, set: { next in
            guard next != mode else { return }
            SRHaptic.select()
            choose(next)
        })) {
            ForEach(LandgrabMode.allCases, id: \.self) { item in
                Text(item.label).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("landgrab-mode")
    }
}

/// A row that pushes a screen: icon, title, chevron.
struct LandgrabLinkRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SR.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(title)
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SR.inkMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 12)
        .frame(minHeight: SR.tapTarget + 4)
        .contentShape(Rectangle())
    }
}

/// The family's ground on the steps page: the big total, the day's and the
/// week's new ground, everyone's part, the places, and the way to the map.
struct LandgrabFamilyCard: View {
    let explored: LandgrabExplored
    /// The week the map shows if it is switched to the game there.
    let mapWeek: String
    @ObservedObject private var names = LandgrabPlaceNames.shared

    var body: some View {
        VStack(spacing: 0) {
            LandgrabFamilyHeadline(explored: explored, size: 40)
                .padding(.horizontal, SR.cardPadding)
                .padding(.top, 12)
                .padding(.bottom, 10)
            Divider().overlay(SR.divider)
            let people = Landgrab.rankedParts(explored.people)
            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                if index > 0 { Divider().overlay(SR.divider).padding(.leading, 56) }
                LandgrabPartRow(person: person, explored: explored)
            }
            if let line = placesLine {
                Divider().overlay(SR.divider)
                Label(line, systemImage: "mappin.and.ellipse")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("landgrab-places-line")
            }
            Divider().overlay(SR.divider)
            NavigationLink(value: LandgrabMapRef(week: mapWeek)) {
                LandgrabLinkRow(icon: "map", title: "See the map")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a map of everywhere the family has explored, with the newest ground lit up")
            .accessibilityIdentifier("landgrab-see-map")
        }
        .padding(.vertical, 4)
        .srGlassCard(.paper)
        .onAppear { names.ask(explored.places) }
    }

    /// "Darlington, Rome and 3 more places": the three biggest by name.
    private var placesLine: String? {
        let shown = explored.places.prefix(3)
        let named = shown.map { names.name($0) ?? Landgrab.placeFallback($0) }
        return Landgrab.placesLine(named, others: explored.places.count - shown.count + explored.otherPlaces)
    }
}

/// "The Kellys have explored" over the big figure, and the new ground.
struct LandgrabFamilyHeadline: View {
    let explored: LandgrabExplored
    var size: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Landgrab.exploredLead(explored))
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
            Text(Landgrab.area(explored.total.km2))
                .font(SR.Text.hero(size))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            let today = Landgrab.newGround(explored.todayNew, "new today")
            let week = explored.weekNew.cells > explored.todayNew.cells ? Landgrab.newGround(explored.weekNew, "this week") : nil
            if today != nil || week != nil {
                HStack(spacing: 8) {
                    if let today { LandgrabChipText(text: today, dot: Color(landgrab: LandgrabColour.fresh)) }
                    if let week { LandgrabChipText(text: week, dot: nil) }
                }
            } else {
                Text("Nothing new today yet")
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Landgrab.spokenHeadline(explored))
        .accessibilityIdentifier("landgrab-family-total")
    }
}

/// "+1.3 km² new today", in a quiet capsule, with an optional key dot.
struct LandgrabChipText: View {
    let text: String
    let dot: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8).accessibilityHidden(true) }
            Text(text)
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(SR.surface))
        .overlay(Capsule().stroke(SR.line, lineWidth: 1))
    }
}

/// One person's part of the family's ground: colour, name, area, share.
struct LandgrabPartRow: View {
    let person: LandgrabExploredPerson
    let explored: LandgrabExplored
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let share = Landgrab.share(person, of: explored.total)
        HStack(spacing: 12) {
            LandgrabSwatch(name: person.name, colour: person.colour, id: person.id)
            VStack(alignment: .leading, spacing: 6) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    Text(person.me ? "You" : person.name)
                        .font(person.me ? SR.bodyBold(16) : SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                    HStack(spacing: 8) {
                        Text(Landgrab.area(person.km2))
                            .font(SR.Text.mono(14))
                            .foregroundStyle(SR.inkSecondary)
                        Text(Landgrab.percent(share))
                            .font(SR.Text.figure(17))
                            .foregroundStyle(SR.ink)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
                ProgressView(value: share)
                    .tint(LandgrabPaint(person.colour, id: person.id).fill)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: SR.tapTarget + 8)
        .background {
            if person.me { SR.accent.opacity(0.08) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Landgrab.spokenPart(person, of: explored))
        .accessibilityIdentifier("landgrab-part-\(person.id)")
    }
}

/// A person's colour as a disc with their initial on it.
struct LandgrabSwatch: View {
    let name: String
    let colour: String?
    let id: String
    var size: CGFloat = 30
    var icon: String? = nil

    var body: some View {
        let paint = LandgrabPaint(colour, id: id)
        ZStack {
            Circle().fill(paint.fill)
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(paint.onFill)
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(SR.Text.label(13))
                    .foregroundStyle(paint.onFill)
            }
        }
        .frame(width: size, height: size)
        // A rim, so a dark colour on the dark ground still has an edge.
        .overlay(Circle().stroke(SR.line, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// One person's week: place, colour, name, won ▲, lost ▼, net.
struct LandgrabRow: View {
    let person: LandgrabPerson
    let tied: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 10) {
            Text("\(person.rank)")
                .font(SR.Text.label(15))
                .foregroundStyle(person.rank == 1 ? SR.accent : SR.inkMuted)
                .frame(width: 18)
            LandgrabSwatch(name: person.name, colour: person.colour, id: person.id)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                Text(person.me ? "You" : person.name)
                    .font(person.me ? SR.bodyBold(16) : SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                HStack(spacing: 10) {
                    figure("▲", person.won, tone: SR.good)
                    figure("▼", person.lost, tone: SR.error)
                    Text(Landgrab.signed(person.net))
                        .font(SR.Text.figure(19))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                        .frame(minWidth: 44, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: SR.tapTarget + 8)
        .background {
            if person.me { SR.accent.opacity(0.08) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Landgrab.spoken(person, tied: tied))
        .accessibilityIdentifier("landgrab-row-\(person.id)")
    }

    /// "▲ 41" — the arrow carries the meaning, the colour only repeats it.
    private func figure(_ arrow: String, _ value: Int, tone: Color) -> some View {
        HStack(spacing: 3) {
            Text(arrow).font(SR.Text.mono(11)).foregroundStyle(tone)
            Text(Landgrab.figure(value))
                .font(SR.Text.mono(14))
                .foregroundStyle(SR.inkSecondary)
                .monospacedDigit()
        }
    }
}

// MARK: - The map

/// Landgrab's map, in the mode the section was in. Family: everywhere the
/// family has explored, solid, with the newest ground lit up
/// (`LandgrabFamilyMapView`). This week: the hexes that changed hands,
/// filled in the winner's colour, and the outings that took them listed
/// under it — tapping an outing lights its hexes, draws its trace and fits
/// the camera to it.
struct LandgrabMapScreen: View {
    @ObservedObject private var boardStore = LandgrabStore.shared
    @StateObject private var store = LandgrabChangesStore()
    @AppStorage(LandgrabMode.key) private var modeRaw = LandgrabMode.family.rawValue
    @State private var week: String
    @State private var selected: String?
    @State private var selectedHexes: Set<Int> = []
    @State private var camera: MapCameraPosition = .automatic

    init(week: String) {
        _week = State(initialValue: week)
    }

    private var board: LandgrabBoard? { boardStore.board }

    /// The family's ground, when the site sent some and it is ready to draw.
    private var family: (explored: LandgrabExplored, layer: LandgrabExploredLayer)? {
        guard let explored = boardStore.explored, Landgrab.showsExplored(explored),
              let layer = boardStore.exploredLayer else { return nil }
        return (explored, layer)
    }

    private var mode: LandgrabMode {
        LandgrabMode.effective(modeRaw, hasFamily: family != nil, hasWeek: true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                if family != nil {
                    LandgrabModePicker(mode: mode) { modeRaw = $0.rawValue }
                        .padding(.horizontal, 4)
                }
                if mode == .family, let family {
                    LandgrabFamilyMapView(explored: family.explored, layer: family.layer)
                } else {
                    weekContent
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("landgrab-map-screen")
        .srGround(.vital)
        .navigationTitle("Landgrab")
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable {
            if mode == .family {
                await boardStore.load()
            } else {
                await store.load(week: week, force: true)
            }
        }
        // The week's changes are read only when the week is on screen.
        .task(id: "\(mode.rawValue)|\(week)") {
            guard mode == .week else { return }
            clearSelection(animated: false)
            await store.load(week: week)
            fitWeek(animated: false)
        }
    }

    @ViewBuilder
    private var weekContent: some View {
        weekPicker
        if let shown = store.shown {
            mapCard(shown)
            if shown.changes.changes.isEmpty {
                SREmpty(
                    title: "A quiet week",
                    icon: "map",
                    message: "No ground changed hands \(Landgrab.phrase(label(week))). It moves when someone walks, runs or rides somewhere new."
                )
                .accessibilityIdentifier("landgrab-quiet")
            } else {
                changeList(shown)
            }
        } else if let message = store.message {
            SREmpty(title: "No map", icon: "map", message: message,
                    actionLabel: "Try again", action: { Task { await store.load(week: week, force: true) } })
        } else {
            ProgressView().tint(SR.accent).frame(maxWidth: .infinity).padding(.top, 80)
        }
    }

    // MARK: Week

    private struct WeekOption: Hashable {
        let start: String
        let label: String
    }

    /// The weeks the board has, newest first; the asked-for week even when
    /// the board has not loaded.
    private var weeks: [WeekOption] {
        let listed = (board?.weeks ?? []).map {
            WeekOption(start: $0.start, label: Landgrab.weekLabel(start: $0.start, current: $0.current))
        }
        if listed.contains(where: { $0.start == week }) { return listed }
        return [WeekOption(start: week, label: label(week))] + listed
    }

    private func label(_ start: String) -> String {
        let current = board?.weeks.first { $0.start == start }?.current ?? false
        return Landgrab.weekLabel(start: start, current: current)
    }

    private var weekPicker: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label(week))
                    .font(SR.Text.display(20))
                    .foregroundStyle(SR.ink)
                if let range = Landgrab.weekRange(start: week, end: "") {
                    Text(range)
                        .font(SR.Text.mono(13))
                        .foregroundStyle(SR.inkMuted)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Picker("Week", selection: $week) {
                ForEach(weeks, id: \.start) { item in
                    Text(item.label).tag(item.start)
                }
            }
            .pickerStyle(.menu)
            .tint(SR.accent)
            .accessibilityIdentifier("landgrab-week-picker")
        }
        .padding(.horizontal, 4)
    }

    // MARK: Map

    private func mapCard(_ shown: LandgrabChangesStore.Week) -> some View {
        let layer = shown.layer
        let trace: [CLLocationCoordinate2D] = selected.flatMap { layer.traces[$0] } ?? []
        let lineColour = traceColour(in: shown.changes)
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Map(position: $camera, interactionModes: [.pan, .zoom]) {
                    ForEach(layer.hexes) { hex in
                        MapPolygon(coordinates: hex.coordinates)
                            .foregroundStyle(hex.colour.opacity(fillOpacity(hex.id)))
                            // A pale rim on every hex: captured ground has to
                            // stand off the map, light or dark, at a glance.
                            .stroke(Color.white.opacity(strokeOpacity(hex.id)), lineWidth: strokeWidth(hex.id))
                    }
                    if trace.count > 1 {
                        // A pale casing under the line, so it reads over any
                        // fill and on the dark map as well as the light one.
                        MapPolyline(coordinates: trace)
                            .stroke(Color.white.opacity(0.9), lineWidth: 6)
                        MapPolyline(coordinates: trace)
                            .stroke(lineColour, lineWidth: 3)
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Landgrab.mapSummary(shown.changes, weekLabel: label(week)) { name(for: $0, in: shown.changes) })
                .accessibilityIdentifier("landgrab-map")

                if selected != nil {
                    Button {
                        SRHaptic.tap()
                        clearSelection(animated: true)
                        fitWeek(animated: true)
                    } label: {
                        Label(store.shown?.layer.homeRegion == nil ? "Show all" : "Home area",
                              systemImage: store.shown?.layer.homeRegion == nil ? "arrow.up.left.and.arrow.down.right" : "house")
                            .font(SR.Text.label(13))
                    }
                    .srButton(.regular)
                    .padding(10)
                    .accessibilityHint("Shows the home area's changes on the map")
                    .accessibilityIdentifier("landgrab-show-all")
                }
            }
            legend(shown.changes)
            if shown.changes.truncated {
                Text("A big week: only the largest changes are on the map.")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// The selected outing's winner's colour, for its trace.
    private func traceColour(in changes: LandgrabChanges) -> Color {
        guard let id = selected,
              let change = changes.changes.first(where: { $0.id == id }),
              let person = change.personId else { return SR.accent }
        return colour(for: person, in: changes)
    }

    private func fillOpacity(_ id: Int) -> Double {
        guard selected != nil else { return 0.8 }
        return selectedHexes.contains(id) ? 0.95 : 0.3
    }

    private func strokeOpacity(_ id: Int) -> Double {
        guard selected != nil else { return 0.85 }
        return selectedHexes.contains(id) ? 1 : 0.3
    }

    private func strokeWidth(_ id: Int) -> CGFloat {
        guard selected != nil else { return 1.5 }
        return selectedHexes.contains(id) ? 2.5 : 1
    }

    /// Who won ground on the map, by colour — the map's key.
    private func legend(_ changes: LandgrabChanges) -> some View {
        var counts: [String: Int] = [:]
        for hex in changes.hexes { if let owner = hex.owner { counts[owner, default: 0] += 1 } }
        let people = changes.people.filter { counts[$0.id] != nil }.sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(people) { person in
                    HStack(spacing: 6) {
                        LandgrabSwatch(name: person.name, colour: person.colour, id: person.id, size: 14)
                        Text("\(name(for: person.id, in: changes)) \(Landgrab.figure(counts[person.id] ?? 0))")
                            .font(SR.Text.mono(12))
                            .foregroundStyle(SR.inkSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name(for: person.id, in: changes)), \(Landgrab.hexes(counts[person.id] ?? 0)) won")
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: Changes

    private func changeList(_ shown: LandgrabChangesStore.Week) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "What changed", trailing: shown.ordered.count == 1 ? "1 change" : "\(shown.ordered.count) changes")
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(shown.ordered.enumerated()), id: \.element.id) { index, change in
                    if index > 0 { Divider().overlay(SR.divider).padding(.leading, 62) }
                    changeRow(change, in: shown)
                }
            }
            .padding(.vertical, 4)
            .srGlassCard(.paper)
        }
    }

    private func changeRow(_ change: LandgrabChange, in shown: LandgrabChangesStore.Week) -> some View {
        let changes = shown.changes
        let person = change.personId.flatMap { id in changes.people.first { $0.id == id } }
        let isMe = change.personId.map(isMine) ?? false
        let label = Landgrab.activityLabel(change, name: person?.name, me: isMe)
        let namer: (String?) -> String = { name(for: $0, in: changes) }
        let isSelected = selected == change.id
        let detail = [Landgrab.shortTime(change.activity?.startedAt ?? change.at), Landgrab.distance(change.activity?.distanceM)]
            .compactMap { $0 }
        return Button {
            SRHaptic.tap()
            select(change, in: shown.layer)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                LandgrabSwatch(name: person?.name ?? "", colour: person?.colour, id: change.personId ?? change.id,
                               size: 34, icon: icon(for: change))
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    if !detail.isEmpty || change.activity?.loop == true {
                        Text((detail + (change.activity?.loop == true ? ["closed a loop"] : [])).joined(separator: " · "))
                            .font(SR.Text.mono(12))
                            .foregroundStyle(SR.inkMuted)
                    }
                    Text(Landgrab.wonLine(change, name: namer).capitalizedFirst)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SR.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { if isSelected { SR.accent.opacity(0.08) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Landgrab.spokenChange(change, label: label, name: namer))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? "Shows the map again" : "Shows it on the map")
        .accessibilityIdentifier("landgrab-change-\(change.id)")
    }

    private func icon(for change: LandgrabChange) -> String {
        guard let activity = change.activity else { return "square.dashed" }
        switch activity.typeValue {
        case .walk?: return "figure.walk"
        case .run?: return "figure.run"
        case .ride?: return "bicycle"
        case .hike?: return "figure.hiking"
        case nil: return activity.kind == "trail" ? "point.topleft.down.to.point.bottomright.curvepath" : "figure.mixed.cardio"
        }
    }

    // MARK: Selection and camera

    private func select(_ change: LandgrabChange, in layer: LandgrabMapLayer) {
        if selected == change.id {
            clearSelection(animated: true)
            fitWeek(animated: true)
            return
        }
        selected = change.id
        selectedHexes = layer.hexesByChange[change.id] ?? []
        if let region = layer.changeRegions[change.id] {
            withAnimation(.easeInOut(duration: 0.6)) { camera = .region(region) }
        }
    }

    private func clearSelection(animated: Bool) {
        selected = nil
        selectedHexes = []
    }

    /// Home ground when the site sent a focus, else the whole week.
    private func fitWeek(animated: Bool) {
        guard let layer = store.shown?.layer, let region = layer.homeRegion ?? layer.weekRegion else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.6)) { camera = .region(region) }
        } else {
            camera = .region(region)
        }
    }

    // MARK: People

    private func isMine(_ id: String) -> Bool {
        if let person = board?.weeks.lazy.flatMap(\.people).first(where: { $0.id == id }) { return person.me }
        return store.shown?.changes.people.first { $0.id == id }?.me ?? false
    }

    /// "you", the person's name, or "someone"; nil (unclaimed) → "nobody".
    private func name(for id: String?, in changes: LandgrabChanges) -> String {
        guard let id else { return "nobody" }
        if isMine(id) { return "you" }
        if let name = changes.people.first(where: { $0.id == id })?.name, !name.isEmpty { return name }
        if let name = board?.weeks.lazy.flatMap(\.people).first(where: { $0.id == id })?.name, !name.isEmpty { return name }
        return "someone"
    }

    private func colour(for id: String, in changes: LandgrabChanges) -> Color {
        LandgrabPaint(changes.people.first { $0.id == id }?.colour, id: id).fill
    }
}

// MARK: - The family map

/// Everywhere the family has explored, on the map screen: the total, a solid
/// map with the newest day's ground lit up over the rest, a chip for each
/// place to fly to, everyone's part and the places listed.
struct LandgrabFamilyMapView: View {
    let explored: LandgrabExplored
    let layer: LandgrabExploredLayer
    @ObservedObject private var names = LandgrabPlaceNames.shared
    @State private var camera: MapCameraPosition
    /// The chip the camera was last sent to: "fresh", "all" or a place id.
    @State private var focused: String?

    init(explored: LandgrabExplored, layer: LandgrabExploredLayer) {
        self.explored = explored
        self.layer = layer
        _camera = State(initialValue: layer.opening.map { MapCameraPosition.region($0) } ?? .automatic)
        let home = explored.places.first(where: \.home)?.id
        _focused = State(initialValue: layer.freshRegion != nil ? "fresh" : home)
    }

    private var exploredColour: Color { Color(landgrab: LandgrabColour.explored) }
    private var freshColour: Color { Color(landgrab: LandgrabColour.fresh) }

    var body: some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            LandgrabFamilyHeadline(explored: explored)
                .padding(.horizontal, 4)
            mapCard
            parts
            places
        }
        .onAppear { names.ask(explored.places) }
    }

    // MARK: Map

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                ForEach(layer.areas) { area in
                    MapPolygon(area.polygon)
                        .foregroundStyle(exploredColour.opacity(0.5))
                        .stroke(exploredColour, lineWidth: 1)
                }
                // The newest ground over the rest, with a pale rim so it reads
                // on the teal and on the bare map alike.
                ForEach(layer.fresh) { area in
                    MapPolygon(area.polygon)
                        .foregroundStyle(freshColour.opacity(0.85))
                        .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Landgrab.familyMapSummary(explored))
            .accessibilityIdentifier("landgrab-family-map")

            chips
            legend
            if explored.shape.truncated {
                Text("So much ground that the smallest of it is left off the map. The figures count all of it.")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// One chip per place to fly to, the newest ground first.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let fresh = explored.fresh, let region = layer.freshRegion {
                    chip(id: "fresh", icon: "sparkles",
                         label: "\(Landgrab.freshLabel(fresh, today: explored.today)) · \(Landgrab.area(fresh.figure.km2))",
                         region: region)
                }
                ForEach(explored.places) { place in
                    if let region = layer.placeRegions[place.id] {
                        chip(id: place.id, icon: place.home ? "house" : "mappin", label: placeName(place), region: region)
                    }
                }
                if let region = layer.everything, explored.places.count > 1 || explored.otherPlaces > 0 {
                    chip(id: "all", icon: "globe.europe.africa", label: "Everywhere", region: region)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func chip(id: String, icon: String, label: String, region: MKCoordinateRegion) -> some View {
        let on = focused == id
        return Button {
            SRHaptic.tap()
            focused = id
            withAnimation(.easeInOut(duration: 0.6)) { camera = .region(region) }
        } label: {
            Label(label, systemImage: icon)
                .font(SR.Text.label(13))
                .foregroundStyle(on ? SR.ink : SR.inkSecondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: SR.tapTarget)
                .background(Capsule().fill(on ? SR.accent.opacity(0.18) : SR.surface))
                .overlay(Capsule().stroke(on ? SR.accent : SR.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Shows it on the map")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("landgrab-chip-\(id)")
    }

    /// What the two colours mean.
    private var legend: some View {
        HStack(spacing: 16) {
            key(exploredColour.opacity(0.5), "Explored")
            if let fresh = explored.fresh, !fresh.shape.areas.isEmpty {
                let when = Landgrab.freshLabel(fresh, today: explored.today)
                key(freshColour, when == "Today" ? "New today" : "New \(when.lowercased() == "yesterday" ? "yesterday" : "on " + when)")
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func key(_ colour: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(colour).frame(width: 14, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(SR.line, lineWidth: 1))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.inkSecondary)
        }
    }

    // MARK: People and places

    private var parts: some View {
        let people = Landgrab.rankedParts(explored.people)
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Everyone's part", trailing: "of \(Landgrab.area(explored.total.km2))")
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    if index > 0 { Divider().overlay(SR.divider).padding(.leading, 56) }
                    LandgrabPartRow(person: person, explored: explored)
                }
            }
            .padding(.vertical, 4)
            .srGlassCard(.paper)
            Text("Parts overlap: a walk together counts for everyone on it.")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var places: some View {
        if !explored.places.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Where", trailing: explored.places.count == 1 ? "1 place" : "\(explored.places.count) places")
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(explored.places.enumerated()), id: \.element.id) { index, place in
                        if index > 0 { Divider().overlay(SR.divider).padding(.leading, 56) }
                        placeRow(place, index: index)
                    }
                }
                .padding(.vertical, 4)
                .srGlassCard(.paper)
                if explored.otherPlaces > 0 {
                    Text(explored.otherPlaces == 1 ? "And 1 smaller spot on the way." : "And \(explored.otherPlaces) smaller spots on the way.")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func placeRow(_ place: LandgrabPlace, index: Int) -> some View {
        let name = placeName(place)
        let detail = Landgrab.placeDetail(place, today: explored.today)
        return Button {
            SRHaptic.tap()
            if let region = layer.placeRegions[place.id] {
                focused = place.id
                withAnimation(.easeInOut(duration: 0.6)) { camera = .region(region) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: place.home ? "house.fill" : "mappin.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(place.last == explored.today ? freshColour : exploredColour)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    if let detail {
                        Text(detail)
                            .font(SR.Text.mono(12))
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Text(Landgrab.area(place.km2))
                    .font(SR.Text.mono(14))
                    .foregroundStyle(SR.inkSecondary)
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 12)
            .frame(minHeight: SR.tapTarget + 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([name, Landgrab.spokenArea(place.km2), detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Shows it on the map")
        .accessibilityIdentifier("landgrab-place-\(index)")
    }

    private func placeName(_ place: LandgrabPlace) -> String {
        names.name(place) ?? Landgrab.placeFallback(place)
    }
}

private extension String {
    /// "won 18 hexes" → "Won 18 hexes".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

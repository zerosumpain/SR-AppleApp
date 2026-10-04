import SwiftUI
import MapKit

// Landgrab on the steps page, and the map of what changed hands.
//
// The section sits under the step board's "Today" ranking: this week's
// ground, won and lost, by person. "See what changed" pushes the map — the
// hexes that changed owner, filled in the winner's colour, and the outings
// that took them. Rules and words are in `LandgrabModels.swift`; this file
// only draws.

/// Pushes the map for one week.
struct LandgrabMapRef: Hashable {
    /// The Monday, "2026-09-28".
    let week: String
}

// MARK: - The section on the steps page

/// "Landgrab · this week": one row per person, ranked by net ground. Draws
/// nothing at all until there is a board with somebody on it — never a
/// spinner, never an error on the steps page.
struct LandgrabSection: View {
    @ObservedObject private var store = LandgrabStore.shared

    var body: some View {
        if let board = store.board, Landgrab.shows(board), let week = Landgrab.currentWeek(board) {
            content(board, week)
        }
    }

    private func content(_ board: LandgrabBoard, _ week: LandgrabWeek) -> some View {
        let people = Landgrab.ranked(week.people)
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Landgrab · this week", trailing: Landgrab.weekRange(start: week.start, end: week.end))
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    if index > 0 { Divider().overlay(SR.divider).padding(.leading, 64) }
                    LandgrabRow(person: person, tied: Landgrab.tied(person, in: people))
                }
                Divider().overlay(SR.divider)
                NavigationLink(value: LandgrabMapRef(week: week.start)) {
                    HStack(spacing: 12) {
                        Image(systemName: "map")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SR.accent)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        Text("See what changed")
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
        .accessibilityIdentifier("landgrab-section")
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

/// What changed hands in a week: the hexes on a map, filled in the winner's
/// colour, and the outings that took them listed under it. Tapping an outing
/// lights its hexes, draws its trace and fits the camera to it.
struct LandgrabMapScreen: View {
    @ObservedObject private var boardStore = LandgrabStore.shared
    @StateObject private var store = LandgrabChangesStore()
    @State private var week: String
    @State private var selected: String?
    @State private var selectedHexes: Set<Int> = []
    @State private var camera: MapCameraPosition = .automatic

    init(week: String) {
        _week = State(initialValue: week)
    }

    private var board: LandgrabBoard? { boardStore.board }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
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
            .padding(.horizontal, SR.gutter)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("landgrab-map-screen")
        .srGround(.vital)
        .navigationTitle("Landgrab")
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable { await store.load(week: week, force: true) }
        .task(id: week) {
            clearSelection(animated: false)
            await store.load(week: week)
            fitWeek(animated: false)
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
                            .stroke(hex.colour.opacity(strokeOpacity(hex.id)), lineWidth: 0.75)
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
                        Label("Show all", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(SR.Text.label(13))
                    }
                    .srButton(.regular)
                    .padding(10)
                    .accessibilityHint("Shows the whole week on the map")
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
        guard selected != nil else { return 0.45 }
        return selectedHexes.contains(id) ? 0.9 : 0.12
    }

    private func strokeOpacity(_ id: Int) -> Double {
        guard selected != nil else { return 0.85 }
        return selectedHexes.contains(id) ? 1 : 0.2
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
        .accessibilityHint(isSelected ? "Shows the whole week again" : "Shows it on the map")
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

    private func fitWeek(animated: Bool) {
        guard let region = store.shown?.layer.weekRegion else { return }
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

private extension String {
    /// "won 18 hexes" → "Won 18 hexes".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

import SwiftUI

/// The grid: rows from `HomeRows.pack`, each at a fixed (scaled) height.
///
/// Plain stacks, not a lazy grid: twenty tiles never need laziness, and a
/// lazy grid re-negotiating its cells as the safe area moved was work Today
/// already learned to avoid. Fixed heights are the other half of the same
/// lesson — a tile that grows when its data lands moves every tile under it,
/// under a thumb that was already on its way down. The one exception is the
/// adaptive tile (`HomeTileKind.adaptive`), which John asked to grow when it
/// has something to show; it waits for its data before it folds, so it moves
/// once at most (`HomeSizing.resolve`).
struct HomeGrid<Tile: View>: View {
    let kinds: [HomeTileKind]
    /// Each tile's size as drawn now: the reader's, folded if it is empty.
    let sizes: [HomeTileKind: HomeSize]
    @ViewBuilder let tile: (HomeTileKind, HomeSize) -> Tile
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 172
    @ScaledMetric(relativeTo: .body) private var hero: CGFloat = 372
    /// Three of the briefing's lines, whether one came back or three.
    @ScaledMetric(relativeTo: .body) private var briefing: CGFloat = 232
    /// Six of them, when the reader makes it large.
    @ScaledMetric(relativeTo: .body) private var briefingLarge: CGFloat = 420
    /// The gauge beside four figures, and the rings under them.
    @ScaledMetric(relativeTo: .body) private var health: CGFloat = 236
    /// The headline, four lanes and yesterday's winner.
    @ScaledMetric(relativeTo: .body) private var steps: CGFloat = 224
    @ScaledMetric(relativeTo: .body) private var news: CGFloat = 188
    /// The newest line, and the row of one-tap lines under it.
    @ScaledMetric(relativeTo: .body) private var messages: CGFloat = 184
    /// Up to three of the day's entries.
    @ScaledMetric(relativeTo: .body) private var diary: CGFloat = 196
    @ScaledMetric(relativeTo: .body) private var shortcut: CGFloat = 66

    static var gap: CGFloat { 14 }

    var body: some View {
        VStack(spacing: Self.gap) {
            ForEach(HomeRows.pack(kinds, sizes: sizes, folded: typeSize.isAccessibilitySize)) { row in
                Group {
                    switch row {
                    case .full(let kind):
                        tile(kind, size(kind)).frame(height: height(kind))
                    case .pair(let a, let b):
                        HStack(spacing: Self.gap) {
                            tile(a, size(a))
                            tile(b, size(b))
                        }
                        .frame(height: max(height(a), height(b)))
                    case .single(let kind):
                        // A square alone stays a square: the other half of
                        // the row is left empty rather than stretched into.
                        HStack(spacing: Self.gap) {
                            tile(kind, size(kind))
                            Color.clear.accessibilityHidden(true)
                        }
                        .frame(height: height(kind))
                    case .stack(let square, let small):
                        HStack(spacing: Self.gap) {
                            tile(square, size(square))
                            VStack(spacing: Self.gap) {
                                ForEach(small) { tile($0, size($0)) }
                                if small.count == 1 { Color.clear.accessibilityHidden(true) }
                            }
                        }
                        .frame(height: unit)
                    }
                }
                // Tiles settle in as they scroll onto the screen and ease off
                // as they leave: the system's own scroll transition, so it
                // costs nothing while the page is still.
                .scrollTransition(.interactive, axis: .vertical) { content, phase in
                    content
                        .scaleEffect(phase.isIdentity ? 1 : 0.95)
                        .opacity(phase.isIdentity ? 1 : 0.7)
                }
            }
        }
    }

    private func size(_ kind: HomeTileKind) -> HomeSize { sizes[kind] ?? kind.defaultSize }

    /// A tile's row height at the size it is drawn. Squares are one unit,
    /// whatever they are; a wide tile is as tall as what it carries.
    private func height(_ kind: HomeTileKind) -> CGFloat {
        switch size(kind) {
        case .compact: return shortcut
        case .square: return unit
        case .hero: return kind == .briefing ? briefingLarge : hero
        case .wide:
            switch kind {
            case .briefing: return briefing
            case .health: return health
            case .steps: return steps
            case .news: return news
            case .messages: return messages
            case .diary: return diary
            default: return unit
            }
        }
    }
}

/// The top of Home: the greeting, the date, and the day in one line.
///
/// A fixed height — `today-hero` — so nothing under it moves when the
/// family's names arrive.
struct HomeHeader: View {
    let name: String?
    let line: String?
    var now: Date = Date()
    /// One height on every phone, so nothing under it moves when the
    /// family's names arrive. The bat phone that shared the date's row is a
    /// tile of its own now (`HomeBatPhoneTile`); the height is unchanged.
    @ScaledMetric(relativeTo: .largeTitle) private var height: CGFloat = 128

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(SR.Text.label(12))
                .tracking(1.2)
                .foregroundStyle(SR.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(greeting)
                .font(SR.Text.hero(34))
                .foregroundStyle(
                    LinearGradient(colors: [SR.ink, SR.Hue.daydream.base], startPoint: .leading, endPoint: .trailing)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            if let line {
                Text(line)
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .bottomLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-hero")
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        let part = hour < 5 ? "Hello" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        guard let name, let first = name.split(separator: " ").first else { return part }
        return "\(part), \(first)"
    }

    /// "3 home · Sam out · 2 tasks" — the household in a breath. PURE.
    static func line(view: HouseholdView?, tasksToDo: Int?) -> String? {
        var parts: [String] = []
        if let view {
            let home = view.people.filter { $0.status == "home" }.count
            if home > 0 { parts.append("\(home) at home") }
            let out = view.people.filter { $0.status == "out" && !$0.isSelf }
            switch out.count {
            case 0: break
            case 1: parts.append("\(out[0].name.split(separator: " ").first.map(String.init) ?? out[0].name) is out")
            default: parts.append("\(out.count) out")
            }
            let moving = view.moving.count
            if moving > 0 { parts.append("\(moving) on the move") }
        }
        if let tasksToDo, tasksToDo > 0 { parts.append("\(tasksToDo) task\(tasksToDo == 1 ? "" : "s") to do") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Settings → Home: every tile this person may have, shown or not, in the
/// order Home draws them. Drag to arrange, switch to show.
struct HomeCustomizeScreen: View {
    @AppStorage(HomeLayout.key) private var raw = ""
    @ObservedObject private var access = AccessStore.shared
    @EnvironmentObject private var router: Router

    var body: some View {
        let available = HomeTileKind.available(access: access.current, sitePaired: SiteClient.shared.isPaired)
        let layout = HomeLayout.decode(raw)
        List {
            Section {
                Button {
                    SRHaptic.tap()
                    router.openColours()
                } label: {
                    SRRow(title: "Colours", subtitle: "Pick a palette, or change any tile's colour", icon: "paintpalette")
                }
                .buttonStyle(.plain)
                .srGlassRow()
                .accessibilityIdentifier("settings-home-colours")
            }

            Section {
                ForEach(layout.arranged(available)) { kind in
                    Toggle(isOn: Binding(
                        get: { layout.shows(kind) },
                        set: { shown in
                            var next = HomeLayout.decode(raw)
                            next.set(kind, shown: shown)
                            raw = next.raw
                        }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(kind.hue.onFill)
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(kind.hue.gradient))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title).font(SR.Text.title(16)).foregroundStyle(SR.ink)
                                Text(kind.blurb).font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                if kind.sizes.count > 1 {
                                    sizeMenu(kind, current: layout.size(of: kind))
                                }
                            }
                        }
                    }
                    .tint(kind.hue.base)
                    // The bat phone: on every family Home, always.
                    .disabled(kind.alwaysShown)
                    .srGlassRow()
                    .accessibilityIdentifier("settings-home-\(kind.rawValue)")
                }
                .onMove { source, destination in
                    var next = HomeLayout.decode(raw)
                    next.move(available, from: source, to: destination)
                    raw = next.raw
                    SRHaptic.select()
                }
            } header: {
                SRSectionLabel(text: "On Home")
            } footer: {
                Text("Drag to change the order, or press Arrange on Home to move the tiles themselves. Only what you can use is listed; what you switch off stays here to bring back.")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
            }

            Section {
                Button("Back to the standard Home") {
                    SRHaptic.tap()
                    raw = HomeLayout().raw
                }
                .foregroundStyle(SR.accent)
                .srGlassRow()
                .accessibilityIdentifier("settings-home-reset")
            }
        }
        .environment(\.editMode, .constant(.active))
        .srGround(.warm)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Size · Wide 4×2", a menu of the tile's sizes. A tile that folds when
    /// it has nothing to show says so.
    private func sizeMenu(_ kind: HomeTileKind, current: HomeSize) -> some View {
        Menu {
            ForEach(kind.sizes, id: \.self) { size in
                Button {
                    SRHaptic.select()
                    var next = HomeLayout.decode(raw)
                    next.set(kind, size: size)
                    raw = next.raw
                } label: {
                    if size == current {
                        Label("\(size.title) · \(size.cells)", systemImage: "checkmark")
                    } else {
                        Text("\(size.title) · \(size.cells)")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Size · \(current.title) \(current.cells)" + (kind.adaptive ? " · folds when empty" : ""))
                    .font(SR.Text.label(12))
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
            .foregroundStyle(SR.accentDeep)
            .padding(.top, 2)
        }
        .accessibilityLabel("\(kind.title) size, \(current.title)")
        .accessibilityIdentifier("settings-home-size-\(kind.rawValue)")
    }
}

// MARK: - Arrange, on Home itself

/// One tile while Home is being arranged: drawn a touch smaller inside a
/// dashed edge, with − to take it off at the top left and its size at the top
/// right. A long press picks it up; dropped on another tile, it takes that
/// tile's place. The tile underneath does nothing while arranging — a tap
/// meant to pick something up must not open it.
///
/// For VoiceOver the tile is one element with Move up, Move down, Remove and
/// Change size as actions, since a drag is not something it can do.
struct HomeArrangeChrome: ViewModifier {
    let kind: HomeTileKind
    /// The reader's choice, which an empty adaptive tile may be folded from.
    let size: HomeSize
    let remove: (() -> Void)?
    let resize: (() -> Void)?
    let nudge: (Int) -> Void
    let drop: (HomeTileKind) -> Void
    @State private var targeted = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: HomeTileFrame<EmptyView>.corner, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .scaleEffect(targeted ? 0.9 : 0.95)
            .overlay {
                shape
                    .strokeBorder(targeted ? SR.accent : SR.accentDeep.opacity(0.55),
                                  style: StrokeStyle(lineWidth: targeted ? 3 : 2, dash: [7, 5]))
                    .contentShape(shape)
                    .draggable(kind.rawValue) {
                        Label(kind.title, systemImage: kind.symbol)
                            .font(SR.Text.title(15))
                            .foregroundStyle(kind.hue.onFill)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(kind.hue.gradient))
                    }
                    .accessibilityElement()
                    .accessibilityLabel("\(kind.title), \(size.title)")
                    .accessibilityHint("Drag onto another tile to move it there")
                    .accessibilityAction(named: "Move up") { nudge(-1) }
                    .accessibilityAction(named: "Move down") { nudge(1) }
                    .accessibilityActions {
                        if let remove { Button("Remove from Home") { remove() } }
                        if let resize { Button("Change size") { resize() } }
                    }
                    .accessibilityIdentifier("home-arrange-\(kind.rawValue)")
            }
            .overlay(alignment: .topLeading) {
                if let remove {
                    Button {
                        SRHaptic.tap()
                        remove()
                    } label: {
                        Image(systemName: "minus")
                            .font(.footnote.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(SR.error))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -4, y: -4)
                    .accessibilityLabel("Remove \(kind.title)")
                    .accessibilityIdentifier("home-remove-\(kind.rawValue)")
                }
            }
            .overlay(alignment: .topTrailing) {
                if let resize {
                    Button(action: resize) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").imageScale(.small)
                            Text(size.cells).font(SR.Text.label(12))
                        }
                        .foregroundStyle(SR.paper)
                        .padding(.horizontal, 9)
                        .frame(minHeight: 28)
                        .background(Capsule().fill(SR.accentDeep))
                        .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                    .accessibilityLabel("\(kind.title) size, \(size.title). Change")
                    .accessibilityIdentifier("home-resize-\(kind.rawValue)")
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let raw = items.first, let dragged = HomeTileKind(rawValue: raw), dragged != kind else { return false }
                drop(dragged)
                return true
            } isTargeted: { over in
                withAnimation(.snappy) { targeted = over }
            }
    }
}

/// What Arrange is, said once above the tiles.
struct HomeArrangeBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.draw")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SR.accentDeep)
                .accessibilityHidden(true)
            Text("Hold and drag a tile onto another to move it. − takes it off; the size button changes how big it is. Tiles that fold when empty open out again when they have something to show.")
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-arrange-banner")
    }
}

/// While arranging: the tiles this person has that are off Home, each one
/// tap to put back at the foot.
struct HomeAddTiles: View {
    let kinds: [HomeTileKind]
    let add: (HomeTileKind) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Add to Home")
            if kinds.isEmpty {
                Text("Everything you can use is on Home.")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkMuted)
            } else {
                let columns = typeSize.isAccessibilitySize ? 1 : 2
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                    ForEach(kinds) { kind in
                        Button { add(kind) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: kind.symbol)
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(kind.hue.onFill)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(kind.hue.gradient))
                                    .accessibilityHidden(true)
                                Text(kind.title)
                                    .font(SR.Text.title(14))
                                    .foregroundStyle(SR.ink)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                Spacer(minLength: 2)
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(SR.accentDeep)
                                    .accessibilityHidden(true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .srGlassCard(.paper, radius: 16, interactive: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(kind.title)")
                        .accessibilityHint(kind.blurb)
                        .accessibilityIdentifier("home-add-\(kind.rawValue)")
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}

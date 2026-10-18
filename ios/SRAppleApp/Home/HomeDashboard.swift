import SwiftUI

/// The grid: rows from `HomeRows.pack`, each at a fixed (scaled) height.
///
/// Plain stacks, not a lazy grid: fifteen tiles never need laziness, and a
/// lazy grid re-negotiating its cells as the safe area moved was work Today
/// already learned to avoid. Fixed heights are the other half of the same
/// lesson — a tile that grows when its data lands moves every tile under it,
/// under a thumb that was already on its way down.
struct HomeGrid<Tile: View>: View {
    let kinds: [HomeTileKind]
    @ViewBuilder let tile: (HomeTileKind) -> Tile
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 172
    @ScaledMetric(relativeTo: .body) private var hero: CGFloat = 372
    @ScaledMetric(relativeTo: .body) private var ridge: CGFloat = 226

    static var gap: CGFloat { 14 }

    var body: some View {
        VStack(spacing: Self.gap) {
            ForEach(HomeRows.pack(kinds, folded: typeSize.isAccessibilitySize)) { row in
                Group {
                    switch row {
                    case .full(let kind):
                        tile(kind).frame(height: height(kind))
                    case .pair(let a, let b):
                        HStack(spacing: Self.gap) {
                            tile(a)
                            tile(b)
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

    private func height(_ kind: HomeTileKind) -> CGFloat {
        switch kind {
        case .family: return hero
        case .familyDay: return ridge
        default: return unit
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
    @ScaledMetric(relativeTo: .largeTitle) private var height: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(SR.Text.label(12))
                .tracking(1.2)
                .foregroundStyle(SR.accent)
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
        .accessibilityElement(children: .combine)
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

    var body: some View {
        let available = HomeTileKind.available(access: access.current, sitePaired: SiteClient.shared.isPaired)
        let layout = HomeLayout.decode(raw)
        List {
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
                            }
                        }
                    }
                    .tint(kind.hue.base)
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
                Text("Drag to change the order. Only what you can use is listed; what you switch off stays here to bring back.")
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
}

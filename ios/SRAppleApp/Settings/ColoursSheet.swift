import SwiftUI
import UIKit

/// Colours: the reader's palette, chosen while they watch the app change.
///
/// A sheet at half height over whatever was open, with the page behind still
/// live: pick a palette, or re-pick one feature's colour on its wheel, and the
/// app behind redraws a moment later (`SRPaletteStore.epoch`). The sheet is
/// outside what redraws, so the wheel the reader is dragging stays put.
struct SRPaletteSheet: View {
    @ObservedObject private var store = SRPaletteStore.shared
    @ObservedObject private var access = AccessStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let palette = store.palette
        NavigationStack {
            List {
                Section {
                    presets(selected: palette.id)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    SRSectionLabel(text: "Palette")
                } footer: {
                    Text(palette.blurb)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                }

                Section {
                    accentRow(palette)
                    ForEach(Self.keys(access: access.current, sitePaired: SiteClient.shared.isPaired)) { key in
                        hueRow(key, palette)
                    }
                } header: {
                    SRSectionLabel(text: "Colours")
                } footer: {
                    Text("Tap a colour to change it. The accent is darkened or lightened just enough for text to stay readable; tile text picks white or dark for you.")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                }

                Section {
                    Picker(selection: Binding(
                        get: { store.choice.glow },
                        set: { glow in store.update { $0.glow = glow } }
                    )) {
                        ForEach(SRPaletteChoice.Glow.allCases) { Text($0.title).tag($0) }
                    } label: {
                        SRRow(title: "Background glow", subtitle: "The soft colour behind each page", icon: "sparkles")
                    }
                    .pickerStyle(.menu)
                    .tint(SR.accent)
                    .srGlassRow()
                    .accessibilityIdentifier("colours-glow")
                    if UIApplication.shared.supportsAlternateIcons {
                        Toggle(isOn: Binding(
                            get: { store.choice.iconFollows },
                            set: { follows in store.update { $0.iconFollows = follows } }
                        )) {
                            SRRow(title: "Matching app icon", subtitle: "Changed when you close this. iOS will tell you it changed.", icon: "app.badge")
                        }
                        .tint(SR.accent)
                        .srGlassRow()
                        .accessibilityIdentifier("colours-icon")
                    }
                }

                if store.choice.customised {
                    Section {
                        Button("Back to \(palette.name)'s own colours") {
                            SRHaptic.tap()
                            store.update { $0.resetCurrent() }
                        }
                        .foregroundStyle(SR.accent)
                        .srGlassRow()
                        .accessibilityIdentifier("colours-reset")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SR.paper.ignoresSafeArea())
            .navigationTitle("Colours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("colours-done")
                }
            }
        }
        .tint(SR.accentDeep)
        // Half height, with the app behind still live: the point of the
        // sheet is seeing Home change.
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationContentInteraction(.scrolls)
        .accessibilityIdentifier("colours-sheet")
        .onDisappear { store.syncIcon() }
    }

    // MARK: - Presets

    private func presets(selected: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SRPalette.presets) { preset in
                    Button {
                        SRHaptic.select()
                        store.update { $0.preset = preset.id }
                    } label: {
                        SRPaletteCard(palette: SRPalette.resolve(choiceFor(preset)), selected: preset.id == selected)
                    }
                    .buttonStyle(SRPressStyle())
                    .accessibilityLabel(preset.name)
                    .accessibilityHint(preset.blurb)
                    .accessibilityAddTraits(preset.id == selected ? .isSelected : [])
                    .accessibilityIdentifier("colours-preset-\(preset.id)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }

    /// The reader's choice as it would be with `preset` picked: each card
    /// shows the palette WITH whatever the reader did to it.
    private func choiceFor(_ preset: SRPalette) -> SRPaletteChoice {
        var choice = store.choice
        choice.preset = preset.id
        return choice
    }

    // MARK: - Rows

    private func accentRow(_ palette: SRPalette) -> some View {
        let picked = store.choice.accent[palette.id]
        return HStack(spacing: 12) {
            HStack(spacing: 0) {
                Rectangle().fill(SRRGB.color(palette.accent.light))
                Rectangle().fill(SRRGB.color(palette.accent.dark))
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accent").font(SR.Text.title(16)).foregroundStyle(SR.ink)
                Text("Buttons, links and the one thing to press")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if picked != nil {
                resetButton("accent") { store.update { $0.accent[palette.id] = nil } }
            }
            ColorPicker("Accent", selection: Binding(
                get: { SRRGB.color(picked ?? palette.accent.light) },
                set: { colour in
                    let hex = SRRGB.hex(of: colour)
                    store.update { $0.accent[palette.id] = hex }
                }
            ), supportsOpacity: false)
            .labelsHidden()
        }
        .srGlassRow()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("colours-accent")
    }

    private func hueRow(_ key: SR.HueKey, _ palette: SRPalette) -> some View {
        let hue = palette.hue(key)
        let picked = store.choice.picked(key)
        return HStack(spacing: 12) {
            Image(systemName: Self.symbol(key))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SRRGB.color(hue.onFill))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hue.gradient))
                .accessibilityHidden(true)
            Text(key.title).font(SR.Text.title(16)).foregroundStyle(SR.ink)
            Spacer(minLength: 4)
            if picked != nil {
                resetButton(key.title) { store.update { $0.pick(key, nil) } }
            }
            ColorPicker(key.title, selection: Binding(
                get: { SRRGB.color(hue.base) },
                set: { colour in
                    let hex = SRRGB.hex(of: colour)
                    store.update { $0.pick(key, hex) }
                }
            ), supportsOpacity: false)
            .labelsHidden()
        }
        .srGlassRow()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("colours-hue-\(key.rawValue)")
    }

    private func resetButton(_ what: String, _ action: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(SR.inkMuted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to the palette's \(what)")
    }

    // MARK: - Which colours to offer

    /// The hues this person's app actually wears: the tiles they may have,
    /// plus Health's Move ring and, for the owner, the alerts. PURE.
    static func keys(access: AppAccess, sitePaired: Bool) -> [SR.HueKey] {
        var out: [SR.HueKey] = []
        for kind in HomeTileKind.available(access: access, sitePaired: sitePaired) where !out.contains(kind.hueKey) {
            out.append(kind.hueKey)
            if kind == .health { out.append(.move) }
        }
        if access.owner { out.append(.alerts) }
        return out
    }

    static func symbol(_ key: SR.HueKey) -> String {
        switch key {
        case .move: return "flame.fill"
        case .alerts: return "bell.fill"
        default:
            return HomeTileKind.allCases.first { $0.hueKey == key }?.symbol ?? "circle.fill"
        }
    }
}

/// One palette in the picker: its own ground, a few of its tiles, its accent
/// and its icon — drawn from the palette itself, not from the app's current
/// one, so every card shows what it would be.
struct SRPaletteCard: View {
    let palette: SRPalette
    let selected: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let ink = SRRGB.color(dark ? palette.ink.dark : palette.ink.light)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SRAppIconMark(palette: palette)
                    .frame(width: 30, height: 30)
                Spacer(minLength: 0)
                Circle()
                    .fill(SRRGB.color(dark ? palette.accent.dark : palette.accent.light))
                    .frame(width: 12, height: 12)
            }
            VStack(spacing: 4) {
                tile(.family).frame(height: 26)
                HStack(spacing: 4) {
                    tile(.health)
                    tile(.steps)
                }
                .frame(height: 22)
                HStack(spacing: 4) {
                    tile(.trips)
                    tile(.tasks)
                }
                .frame(height: 22)
            }
            HStack(spacing: 3) {
                ForEach(Array(palette.people.prefix(6).enumerated()), id: \.offset) { _, person in
                    Circle().fill(SRRGB.color(person)).frame(width: 7, height: 7)
                }
            }
            Text(palette.name)
                .font(SR.Text.title(14))
                .foregroundStyle(ink)
                .lineLimit(1)
        }
        .padding(10)
        .frame(width: 118)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SRRGB.color(dark ? palette.paper.dark : palette.paper.light))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    selected ? SRRGB.color(dark ? palette.accent.dark : palette.accent.light) : ink.opacity(0.12),
                    lineWidth: selected ? 3 : 1
                )
        )
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, SRRGB.color(dark ? palette.accent.dark : palette.accent.light))
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selected)
    }

    private func tile(_ key: SR.HueKey) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(palette.hue(key).gradient)
    }
}

/// The app icon, drawn: the pixel `SR` and its bar on the palette's ground.
/// The same geometry `scripts/app-icons.py` renders the real icons from, so
/// the picker shows the icon the Home Screen will get.
struct SRAppIconMark: View {
    let palette: SRPalette

    /// The mark's cells on an 11 × 7 grid: `S` in columns 0–4, `R` in 6–10.
    static let cells: [(Int, Int)] = {
        let rows = [
            "#####.####.",
            "#.....#...#",
            "#.....#...#",
            "#####.####.",
            "....#.#.#..",
            "....#.#..#.",
            "#####.#...#",
        ]
        var out: [(Int, Int)] = []
        for (y, row) in rows.enumerated() {
            for (x, cell) in row.enumerated() where cell == "#" { out.append((x, y)) }
        }
        return out
    }()

    var body: some View {
        ZStack {
            ground
            Canvas { context, size in
                let u = size.width / 1024
                let ink = SRRGB.color(palette.iconInk)
                for (x, y) in Self.cells {
                    // `S` starts at 185, `R` at 545: a 70-unit gap, not a cell.
                    let left = (x < 6 ? 185 + CGFloat(x) * 58 : 545 + CGFloat(x - 6) * 58) * u
                    let cell = CGRect(x: left + 4 * u, y: (260 + CGFloat(y) * 58 + 4) * u, width: 50 * u, height: 50 * u)
                    context.fill(Path(roundedRect: cell, cornerRadius: 12 * u, style: .continuous), with: .color(ink))
                }
                let bar = CGRect(x: 185 * u, y: 734 * u, width: 650 * u, height: 26 * u)
                context.fill(Path(roundedRect: bar, cornerRadius: 13 * u, style: .continuous), with: .color(SRRGB.color(palette.iconBar)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }

    /// The four corners blended, as the icon's own ground is.
    @ViewBuilder
    private var ground: some View {
        let corners = palette.iconGround.map { SRRGB.color($0) }
        if #available(iOS 18.0, *) {
            MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]], colors: corners)
        } else {
            LinearGradient(colors: [corners[0], corners[1], corners[2], corners[3]], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

import SwiftUI

// The Build menu (§9.3 step 1) and the lenses (§9.4), as sheets over the map.
//
// The trays come from the wire: what is unlocked and what each thing costs
// (`me.affordances`). Picking an item hands the page its tool and closes the
// sheet; the planning itself — dragging roads, painting zones, dropping
// building ghosts — happens on the map, and the forecast card comes up as
// soon as there is a plan. "Today's builds" is the undo list: a plan built
// today comes back in full while nothing has grown on it. Bramble's builds
// and zoning of today sit apart under it (decision 11) and undo the same way.

struct HometownsBuildSheet: View {
    @ObservedObject var store: HometownsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    wallet
                    today
                    HometownsDeputyUndoList(store: store)
                    ForEach(HometownsCatalogue.trays, id: \.self) { tray in
                        trayView(tray)
                    }
                    // The store holds it: the page stays top-down after the sheet closes, and so does the switch.
                    Toggle(isOn: Binding(get: { store.topDown }, set: { store.setTopDown($0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.level == .kid ? "Flat map for planning" : "Top-down planning view")
                                .font(SR.Text.title())
                                .foregroundStyle(SR.ink)
                            Text("Easier to drag roads and paint zones exactly.")
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkMuted)
                        }
                    }
                    .tint(SR.accent)
                    .accessibilityIdentifier("hometowns-topdown")
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 12)
            }
            .srGround(.warm)
            .navigationTitle("Build")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("hometowns-build")
    }

    /// The money box at the top, so every price below reads against it.
    @ViewBuilder
    private var wallet: some View {
        if let town = store.town {
            HStack(spacing: 12) {
                Image(systemName: "sterlingsign.circle.fill")
                    .font(SR.Text.title(26))
                    .foregroundStyle(Color(hex: 0xE0A030))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.level == .kid ? "IN THE MONEY BOX" : "RESERVES")
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(SR.inkMuted)
                    Text(HometownsText.money(town.money.reserves, store.level))
                        .font(SR.Text.figure(24))
                        .foregroundStyle(town.money.reserves < 0 ? SR.error : SR.ink)
                }
                Spacer(minLength: 8)
                Text(store.level == .kid ? "Pick something, then draw it on the map" : "Pick a tool, then plan on the map")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("hometowns-build-wallet")
        }
    }

    /// One tray as a grid of tiles: two across on a phone, one at the largest text sizes.
    @ViewBuilder
    private func trayView(_ tray: String) -> some View {
        let items = trayItems.filter { $0.tray == tray }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                HStack(spacing: 8) {
                    Image(systemName: trayIcon(tray))
                        .font(SR.Text.label(13))
                        .foregroundStyle(Color.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(trayColour(tray)))
                        .accessibilityHidden(true)
                    SRSectionLabel(text: store.say("tray.\(tray)"), trailing: "\(items.filter { $0.locked == nil }.count) of \(items.count)")
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { item in row(item) }
                }
            }
        }
    }

    private var columns: [GridItem] {
        if typeSize.isAccessibilitySize { return [GridItem(.flexible())] }
        return [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    private func trayIcon(_ tray: String) -> String {
        switch tray {
        case "roads": return "road.lanes"
        case "zones": return "paintbrush.fill"
        case "powerWater": return "bolt.fill"
        case "safety": return "shield.fill"
        case "learning": return "book.fill"
        case "health": return "cross.case.fill"
        case "fun": return "figure.play"
        case "cultureVisitors": return "theatermasks.fill"
        case "transport": return "bus.fill"
        default: return "star.fill"
        }
    }

    private func trayColour(_ tray: String) -> Color {
        switch tray {
        case "roads": return Color(hex: 0x7C7A74)
        case "zones": return HometownsZoneStyle.colour("homes")
        case "powerWater": return Color(hex: 0x3F86CF)
        case "safety": return Color(hex: 0xC2453A)
        case "learning": return Color(hex: 0x6574C8)
        case "health": return Color(hex: 0x3E9A7A)
        case "fun": return Color(hex: 0x7FAE45)
        case "cultureVisitors": return Color(hex: 0xB96BC0)
        case "transport": return Color(hex: 0xE0A030)
        default: return SR.accent
        }
    }

    private var trayItems: [HometownsBuildItem] {
        HometownsCatalogue.items(store.wire?.me?.affordances ?? .empty, town: store.town, copy: store.copy, level: store.level)
    }

    /// Today's plans, with Undo while it still refunds in full.
    @ViewBuilder
    private var today: some View {
        let canUndo = Set(store.wire?.me?.affordances.canUndo ?? [])
        let plans = (store.town?.undo ?? []).filter { canUndo.contains($0.planId) }
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: store.say("undo.title"))
            if plans.isEmpty {
                Text(store.say("undo.empty"))
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                        if index > 0 { Divider().overlay(SR.divider) }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(HometownsText.date(tick: plan.atTick))
                                    .font(SR.Text.title())
                                    .foregroundStyle(SR.ink)
                                Text(store.say("undo.refund", ["cost": .number(plan.cost)]))
                                    .font(SR.Text.secondary())
                                    .foregroundStyle(SR.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Button {
                                store.undo(plan)
                            } label: {
                                SRButtonLabel(title: store.say("undo.button"), icon: "arrow.uturn.backward")
                            }
                            .srButton(.regular)
                            .accessibilityIdentifier("hometowns-undo-\(plan.planId)")
                        }
                        .frame(minHeight: SR.tapTarget)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 4)
                .srGlassCard(.paper)
            }
        }
        .accessibilityIdentifier("hometowns-today")
    }

    /// A tile: the thing's symbol on its colour, its name, its price (amber
    /// when it is more than the money box holds), or why it is locked.
    private func row(_ item: HometownsBuildItem) -> some View {
        let open = item.locked == nil
        let picked = store.tool == item.tool
        let colour = tileColour(item)
        return Button {
            guard open else {
                SRHaptic.bad()
                return
            }
            SRHaptic.select()
            store.setTool(item.tool)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: open ? icon(item) : "lock.fill")
                        .font(SR.Text.title(18))
                        .foregroundStyle(open ? Color.white : SR.inkMuted)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(open ? colour : SR.line))
                        .accessibilityHidden(true)
                    Spacer(minLength: 4)
                    if picked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(SR.Text.title(18))
                            .foregroundStyle(SR.accent)
                            .accessibilityLabel("Picked")
                    }
                }
                Text(item.label)
                    .font(SR.Text.title(16))
                    .foregroundStyle(open ? SR.ink : SR.inkMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let locked = item.locked {
                    Text(locked)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let cost = item.cost {
                    Text(costText(cost, item))
                        .font(SR.Text.title(14).monospacedDigit())
                        .foregroundStyle(affordable(cost) ? SR.inkSecondary : SR.warn)
                } else {
                    Text("Free")
                        .font(SR.Text.title(14).monospacedDigit())
                        .foregroundStyle(SR.good)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius, interactive: open)
            .overlay(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                    .stroke(picked ? SR.accent : Color.clear, lineWidth: 2)
            )
            .opacity(open ? 1 : 0.75)
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityHint(item.locked ?? "")
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("hometowns-item-\(item.id)")
    }

    private func tileColour(_ item: HometownsBuildItem) -> Color {
        if item.tool.kind == "zone" { return HometownsZoneStyle.colour(item.tool.variant ?? "") }
        return trayColour(item.tray)
    }

    private func costText(_ cost: Double, _ item: HometownsBuildItem) -> String {
        let money = HometownsText.money(cost, store.level)
        return item.tool.kind == "road" || item.tool.kind == "upgrade" ? "\(money) a tile" : money
    }

    private func affordable(_ cost: Double) -> Bool {
        (store.town?.money.reserves ?? 0) >= cost
    }

    private func icon(_ item: HometownsBuildItem) -> String {
        switch item.tool.kind {
        case "road", "upgrade": return "road.lanes"
        case "zone": return HometownsZoneStyle.icon(item.tool.variant ?? "")
        case "dezone": return "eraser.fill"
        case "bulldoze": return "xmark.bin.fill"
        case "parcel": return "square.dashed"
        default:
            switch item.tray {
            case "powerWater": return "bolt.fill"
            case "safety": return "shield.fill"
            case "learning": return "book.fill"
            case "health": return "cross.case.fill"
            case "fun": return "figure.play"
            case "cultureVisitors": return "theatermasks.fill"
            case "transport": return "bus.fill"
            default: return "star.fill"
            }
        }
    }
}

/// Bramble's builds and zoning of today (decision 11, §5.18), each with Undo:
/// the ordinary `undo` move with the entry's planId, a build for a full
/// refund and zoning for free, while its lots are as Bramble left them. Shown
/// in the Build sheet under the mayor's own list and in Welcome back under
/// the cards; nothing at all on a day Bramble did nothing.
struct HometownsDeputyUndoList: View {
    @ObservedObject var store: HometownsStore

    var body: some View {
        let plans = store.wire?.deputyToday ?? []
        if !plans.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: store.say("undo.deputyTitle"))
                VStack(spacing: 0) {
                    ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                        if index > 0 { Divider().overlay(SR.divider) }
                        row(plan)
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 4)
                .srGlassCard(.paper)
            }
            .accessibilityIdentifier("hometowns-deputy-today")
        }
    }

    private func row(_ plan: HometownsUndo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .foregroundStyle(SR.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.deputyTitle(store.copy, store.level))
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let refund = plan.refundLine(store.copy, store.level) {
                    Text(refund)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button {
                store.undo(plan)
            } label: {
                SRButtonLabel(title: store.say("undo.button"), icon: "arrow.uturn.backward")
            }
            .srButton(.regular)
            .accessibilityIdentifier("hometowns-deputy-undo-\(plan.planId)")
        }
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 6)
    }
}

/// The lenses (§9.4): a Hamlet has Happy and Land value, a Village all 14.
struct HometownsLensSheet: View {
    @ObservedObject var store: HometownsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("none", title: store.level == .kid ? "Just the town" : "No lens", line: nil)
                    ForEach(HometownsCatalogue.lenses(forTier: store.town?.tier ?? 0), id: \.self) { id in
                        row(id, title: store.copy.say("lensName.\(id)", store.level, or: HometownsCatalogue.humanised(id)),
                            line: store.copy.has("lens.\(id)") ? store.say("lens.\(id)") : nil)
                    }
                } footer: {
                    if (store.town?.tier ?? 0) == 0 {
                        Text("More lenses open when your hamlet becomes a village.")
                            .font(SR.Text.secondary())
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .srGround(.warm)
            .navigationTitle(store.level == .kid ? "Looking glass" : "Lenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("hometowns-lenses")
    }

    private func row(_ id: String, title: String, line: String?) -> some View {
        Button {
            SRHaptic.select()
            store.setLens(id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                swatch(id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    if let line {
                        Text(line)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if store.lens == id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(SR.Text.title(20))
                        .foregroundStyle(SR.accent)
                        .accessibilityLabel("On")
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .srPlainRow()
        .accessibilityIdentifier("hometowns-lens-\(id)")
    }

    /// The lens's colour ramp as a little map tile, as the map will tint it.
    private func swatch(_ id: String) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(LinearGradient(colors: ramp(id), startPoint: .bottomLeading, endPoint: .topTrailing))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: id == "none" ? "house.fill" : "eye.fill")
                    .font(SR.Text.label(13))
                    .foregroundStyle(Color.white.opacity(0.9))
            )
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.black.opacity(0.1), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private func ramp(_ id: String) -> [Color] {
        switch id {
        case "none": return [Color(hex: 0xC9C3AE), Color(hex: 0xE8E4D4)]
        case "happy": return [Color(hex: 0xC2453A), Color(hex: 0xF2C230), Color(hex: 0x5BA35B)]
        case "pollution", "noise", "traffic": return [Color(hex: 0x5BA35B), Color(hex: 0xE0A030), Color(hex: 0x8E3A2E)]
        case "landValue", "desirability": return [Color(hex: 0xE9E1C9), Color(hex: 0xD9A441), Color(hex: 0x8E5BB5)]
        default: return [Color(hex: 0xE9E1C9), Color(hex: 0x6FB0D8), Color(hex: 0x2F5F9E)]
        }
    }
}

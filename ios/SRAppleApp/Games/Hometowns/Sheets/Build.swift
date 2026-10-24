import SwiftUI

// The Build menu (§9.3 step 1) and the lenses (§9.4), as sheets over the map.
//
// The trays come from the wire: what is unlocked and what each thing costs
// (`me.affordances`). Picking an item hands the page its tool and closes the
// sheet; the planning itself — dragging roads, painting zones, dropping
// building ghosts — happens on the map, and the forecast card comes up as
// soon as there is a plan. "Today's builds" is the undo list: a plan built
// today comes back in full while nothing has grown on it.

struct HometownsBuildSheet: View {
    @ObservedObject var store: HometownsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    today
                    ForEach(HometownsCatalogue.trays, id: \.self) { tray in
                        let items = trayItems.filter { $0.tray == tray }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: SR.cardGap) {
                                SRSectionLabel(text: store.say("tray.\(tray)"))
                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                        if index > 0 { Divider().overlay(SR.divider) }
                                        row(item)
                                    }
                                }
                                .padding(.horizontal, SR.cardPadding)
                                .padding(.vertical, 4)
                                .srGlassCard(.paper)
                            }
                        }
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
                                store.undo(plan.planId)
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

    private func row(_ item: HometownsBuildItem) -> some View {
        Button {
            guard item.locked == nil else {
                SRHaptic.bad()
                return
            }
            SRHaptic.select()
            store.setTool(item.tool)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.locked == nil ? icon(item) : "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.locked == nil ? SR.accent : SR.inkGhost)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(SR.Text.title())
                        .foregroundStyle(item.locked == nil ? SR.ink : SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let locked = item.locked {
                        Text(locked)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let cost = item.cost {
                    Text(costText(cost, item))
                        .font(SR.Text.mono())
                        .foregroundStyle(affordable(cost) ? SR.inkSecondary : SR.warn)
                }
                if store.tool == item.tool {
                    Image(systemName: "checkmark").foregroundStyle(SR.accent).accessibilityLabel("Picked")
                }
            }
            .frame(minHeight: SR.tapTarget)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(item.locked ?? "")
        .accessibilityIdentifier("hometowns-item-\(item.id)")
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
        case "zone": return "paintbrush.fill"
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
                    Image(systemName: "checkmark").foregroundStyle(SR.accent).accessibilityLabel("On")
                }
            }
            .frame(minHeight: SR.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .srPlainRow()
        .accessibilityIdentifier("hometowns-lens-\(id)")
    }
}

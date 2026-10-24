import SwiftUI

/// Town Hall (§9.11): the money, the tax dials and the funding, and Bramble's
/// standing orders.
///
/// Controls unlock with the town (§9.6): a Hamlet has four dials, Town Tax
/// and three funding groups; a Village splits homes and business tax and
/// funds each service on its own; a Town sets homes tax by wealth tier and
/// adds Sales tax; a City adds Hotel tax. The dials are a draft until Save,
/// so a child's run of taps is one move and one undoable change, not twenty.
/// Children's dials step half a point; adults' a tenth. The server checks
/// every rate and step again and says why it refuses one.
struct TownHallSheet: View {
    @ObservedObject var store: HometownsStore
    @Environment(\.dismiss) private var dismiss
    @State private var taxes = HometownsTaxes()
    @State private var funding: [Int] = []
    @State private var orders: [HometownsOrder] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    if let town = store.town {
                        money(town)
                        taxSection(town)
                        fundingSection(town)
                        if changed(town) {
                            Button {
                                save(town)
                            } label: {
                                SRButtonLabel(title: store.level == .kid ? "Use these dials" : "Save the budget", icon: "checkmark", fill: true)
                            }
                            .srButton(.prominent)
                            .controlSize(.large)
                            .accessibilityIdentifier("hometowns-budget-save")
                        }
                        ordersSection(town)
                    }
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 12)
            }
            .srGround(.warm)
            .navigationTitle("Town Hall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { load() }
            .onChange(of: store.town) { _, _ in
                // A frame after Save: the dials now say what the server holds.
                if let town = store.town, !changed(town) { load() }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("hometowns-townhall")
    }

    private func load() {
        guard let town = store.town else { return }
        taxes = town.taxes
        funding = town.funding
        orders = town.orders
        loaded = true
    }

    private var step: Int { store.level == .kid ? 50 : 10 }

    // MARK: Money

    private func money(_ town: HometownsTown) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Money")
            SRTileGrid {
                SRStatTile(value: HometownsText.money(town.money.reserves, store.level), label: store.level == .kid ? "In the money box" : "Reserves")
                SRStatTile(value: (town.dayNet >= 0 ? "+" : "") + HometownsText.money(town.dayNet, store.level),
                           label: store.level == .kid ? "Today" : "Since the Regional Day",
                           trend: town.dayNet > 0 ? .up : town.dayNet < 0 ? .down : .flat)
                if town.tier >= 2 {
                    SRStatTile(value: town.money.ratingName, label: "Credit rating")
                }
            }
            if town.money.helper {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.say("helper.title"))
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text(store.say("helper.on"))
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(SR.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .srGlassCard(.paper)
                .accessibilityIdentifier("hometowns-helper")
            }
        }
    }

    // MARK: Taxes

    @ViewBuilder
    private func taxSection(_ town: HometownsTown) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: store.level == .kid ? "Taxes" : "Tax rates")
            VStack(spacing: 0) {
                if town.tier == 0 {
                    dial(store.say("tax.town"), value: taxes.town, range: 0...2000, id: "town") { v in
                        taxes.town = v
                        taxes.homes = [v, v, v]
                    }
                } else if town.tier == 1 {
                    dial(store.say("tax.homes"), value: taxes.homes.first ?? taxes.town, range: 0...2000, id: "homes") { v in
                        taxes.homes = [v, v, v]
                    }
                } else {
                    ForEach(0..<3, id: \.self) { tier in
                        dial("\(store.say("tax.homes")) \(store.say("wealth.\(tier)"))",
                             value: taxes.homes.indices.contains(tier) ? taxes.homes[tier] : taxes.town,
                             range: 0...2000, id: "homes\(tier)") { v in
                            while taxes.homes.count < 3 { taxes.homes.append(taxes.town) }
                            taxes.homes[tier] = v
                        }
                    }
                }
                if town.tier >= 1 {
                    Divider().overlay(SR.divider)
                    dial(store.say("tax.business"), value: taxes.business, range: 0...1200, id: "business") { taxes.business = $0 }
                }
                if town.tier >= 2 {
                    Divider().overlay(SR.divider)
                    dial(store.say("tax.sales"), value: taxes.sales, range: 0...1000, id: "sales") { taxes.sales = $0 }
                }
                if town.tier >= 3 {
                    Divider().overlay(SR.divider)
                    dial(store.say("tax.hotel"), value: taxes.hotel, range: 0...1200, id: "hotel") { taxes.hotel = $0 }
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
            if town.tier == 0 {
                Text(store.level == .kid ? "Business tax follows Town Tax for now." : "A Hamlet has one Town Tax; business pays half of it. Split taxes open at Village.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dial(_ title: String, value: Int, range: ClosedRange<Int>, id: String, set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(HometownsText.rate(value))
                .font(SR.Text.title().monospacedDigit())
                .foregroundStyle(SR.accentInk)
                .accessibilityHidden(true)
            Stepper(title, value: Binding(get: { value }, set: { set(min(range.upperBound, max(range.lowerBound, $0))) }),
                    in: range, step: step)
                .labelsHidden()
                .onChange(of: value) { _, _ in SRHaptic.select() }
        }
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 4)
        // One adjustable element (swipe up or down), said as "Homes tax, 9%":
        // a Stepper folded into a combined element is not reliably adjustable.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(HometownsText.rate(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(min(range.upperBound, value + step))
            case .decrement: set(max(range.lowerBound, value - step))
            @unknown default: break
            }
        }
        .accessibilityIdentifier("hometowns-tax-\(id)")
    }

    // MARK: Funding

    @ViewBuilder
    private func fundingSection(_ town: HometownsTown) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: store.level == .kid ? "Spending" : "Funding")
            VStack(spacing: 0) {
                if town.tier == 0 {
                    ForEach(Array(HometownsCatalogue.fundingGroups.enumerated()), id: \.offset) { index, group in
                        if index > 0 { Divider().overlay(SR.divider) }
                        level(store.say("fundingGroup.\(group.id)"), value: groupLevel(group.keys), id: group.id) { v in
                            for key in group.keys { setFunding(key, v) }
                        }
                    }
                } else {
                    ForEach(Array(HometownsCatalogue.fundingKeys.enumerated()), id: \.offset) { index, key in
                        if index > 0 { Divider().overlay(SR.divider) }
                        level(store.say("funding.\(key)"), value: fundingLevel(key), id: key) { v in setFunding(key, v) }
                    }
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
        }
    }

    private func level(_ title: String, value: Int, id: String, set: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
            Picker(title, selection: Binding(get: { value }, set: { set($0); SRHaptic.select() })) {
                ForEach(0..<3, id: \.self) { l in
                    Text(store.say("fundingLevel.\(l)")).tag(l)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("hometowns-funding-\(id)")
    }

    private func fundingLevel(_ key: String) -> Int {
        guard let i = HometownsCatalogue.fundingKeys.firstIndex(of: key), funding.indices.contains(i) else { return 1 }
        return funding[i]
    }

    /// A Hamlet dial over two services: their level when they agree, else Normal.
    private func groupLevel(_ keys: [String]) -> Int {
        let levels = Set(keys.map(fundingLevel))
        return levels.count == 1 ? levels.first! : 1
    }

    private func setFunding(_ key: String, _ value: Int) {
        guard let i = HometownsCatalogue.fundingKeys.firstIndex(of: key) else { return }
        while funding.count < HometownsCatalogue.fundingKeys.count { funding.append(1) }
        funding[i] = value
    }

    // MARK: Saving

    private func changed(_ town: HometownsTown) -> Bool {
        loaded && (taxes != town.taxes || funding != town.funding)
    }

    /// Only the fields that changed, in the shape this tier may send.
    private func save(_ town: HometownsTown) {
        var tax: [String: Any] = [:]
        if town.tier == 0 {
            if taxes.town != town.taxes.town { tax["town"] = taxes.town }
        } else {
            if taxes.homes != town.taxes.homes {
                tax["homes"] = town.tier >= 2 ? taxes.homes as Any : (taxes.homes.first ?? taxes.town) as Any
            }
            if taxes.business != town.taxes.business { tax["business"] = taxes.business }
            if town.tier >= 2, taxes.sales != town.taxes.sales { tax["sales"] = taxes.sales }
            if town.tier >= 3, taxes.hotel != town.taxes.hotel { tax["hotel"] = taxes.hotel }
        }
        var fund: [String: Int] = [:]
        if town.tier == 0 {
            for group in HometownsCatalogue.fundingGroups {
                let now = groupLevel(group.keys)
                let was = Set(group.keys.compactMap { k in HometownsCatalogue.fundingKeys.firstIndex(of: k).flatMap { town.funding.indices.contains($0) ? town.funding[$0] : nil } })
                if was != [now] { fund[group.id] = now }
            }
        } else {
            for (i, key) in HometownsCatalogue.fundingKeys.enumerated() where funding.indices.contains(i) {
                if !town.funding.indices.contains(i) || funding[i] != town.funding[i] { fund[key] = funding[i] }
            }
        }
        store.budget(taxes: tax.isEmpty ? nil : tax, funding: fund.isEmpty ? nil : fund)
    }

    // MARK: Standing orders (§5.18)

    @ViewBuilder
    private func ordersSection(_ town: HometownsTown) -> some View {
        if !orders.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: store.level == .kid ? "Bramble's jobs" : "Standing orders")
                HStack(alignment: .top, spacing: 10) {
                    HometownsMascot(advisor: "bramble")
                    Text(store.say("bramble.ordersIntro"))
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    ForEach(Array(orders.enumerated()), id: \.element.id) { index, order in
                        if index > 0 { Divider().overlay(SR.divider) }
                        Toggle(isOn: Binding(get: { orders[index].on }, set: { on in
                            orders[index].on = on
                            store.setOrders(orders)
                        })) {
                            Text(orderText(order))
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .tint(SR.accent)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("hometowns-order-\(order.kind)")
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 4)
                .srGlassCard(.paper)
            }
        }
    }

    private func orderText(_ order: HometownsOrder) -> String {
        var data: HometownsData = [:]
        for (i, a) in order.args.enumerated() { data["a\(i)"] = .number(a) }
        return store.say("order.\(order.kind)", data)
    }
}

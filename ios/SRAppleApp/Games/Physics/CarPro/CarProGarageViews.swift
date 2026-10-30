import SwiftUI

/// The garage: the six cars in the showroom (bought or not), the one in
/// focus with its numbers and bars, and for a car you own its upgrade
/// cards (cost, stage and the bars before and after) and its tuning.
struct CarProGarageView: View {
    @ObservedObject var game: CarProGame
    @State private var focus: CarProCarModel?
    @State private var tab: CarProGarageTab = .upgrades

    var body: some View {
        let model = focus ?? game.selectedCar.model
        let owned = game.career.garage.first { $0.model == model }
        return CarProPage {
            SRPageHeader(kicker: "Garage", title: CarProFormat.money(game.career.money),
                         strap: "Buy cars, fit upgrades, tune them. Mind each championship's PI limit.")
            showroom(model)
            CarProCarDetail(model: model, setup: owned?.setup ?? CarProCarSetup(model: model), owned: owned,
                            selected: owned?.id == game.career.selectedCarId, mph: game.settings.mph)
            if let owned {
                ownedActions(owned)
                Picker("Show", selection: $tab) {
                    ForEach(CarProGarageTab.allCases) { option in
                        Text(option.name).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("car-pro-garage-tab")
                if tab == .upgrades {
                    upgrades(owned)
                } else {
                    CarProTuningCard(game: game, car: owned)
                        .id(owned.id)
                }
            } else {
                buyPanel(model)
            }
        }
        .accessibilityIdentifier("car-pro-garage-page")
    }

    // MARK: - Showroom

    private func showroom(_ focusModel: CarProCarModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CarProCarModel.allCases) { model in
                    showroomCard(model, focused: model == focusModel)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, -SR.gutter)
    }

    private func showroomCard(_ model: CarProCarModel, focused: Bool) -> some View {
        let owned = game.career.owns(model)
        let selected = game.selectedCar.model == model
        return Button {
            SRHaptic.select()
            withAnimation(.snappy) { focus = model }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CarProCarPortrait(look: CarProCarLook(setup: CarProCarSetup(model: model)))
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SR.ink.opacity(0.06)))
                Text(model.name)
                    .font(SR.Text.title(14))
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Group {
                    if selected {
                        Label("Driving", systemImage: "checkmark.circle.fill")
                    } else if owned {
                        Label("In the garage", systemImage: "house.fill")
                    } else {
                        Label(CarProFormat.money(model.price), systemImage: "sterlingsign.circle")
                    }
                }
                .font(SR.Text.mono())
                .foregroundStyle(selected ? SR.good : (owned ? SR.inkSecondary : SR.inkMuted))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(10)
            .frame(width: 136, alignment: .leading)
            .srGlassCard(.paper, radius: 20, interactive: true)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(focused ? SR.accent : Color.clear, lineWidth: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(focused ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
        .accessibilityIdentifier("car-pro-model-\(model.rawValue)")
    }

    // MARK: - Owned or not

    private func ownedActions(_ car: CarProOwnedCar) -> some View {
        let selected = car.id == game.career.selectedCarId
        let bought = car.setup.upgrades.bought(for: car.model)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CarProFact(label: "Races", value: "\(car.races)")
                CarProFact(label: "Wins", value: "\(car.wins)")
                CarProFact(label: "Upgrades", value: "\(bought) of \(CarProUpgradeKind.allCases.count * 3 - car.model.factoryTyreStage)")
            }
            if !selected {
                Button {
                    game.select(car.id)
                } label: {
                    SRButtonLabel(title: "Drive this car", icon: "steeringwheel", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("car-pro-drive-car")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private func buyPanel(_ model: CarProCarModel) -> some View {
        let money = game.career.money
        let short = model.price - money
        return VStack(alignment: .leading, spacing: 12) {
            Text(CarProPresent.tierLine(pi: CarProCarSetup(model: model).stats.pi))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
            Button {
                game.buy(model)
                withAnimation(.snappy) { focus = model }
            } label: {
                SRButtonLabel(title: "Buy for \(CarProFormat.money(model.price))", icon: "cart.fill", fill: true)
                    .frame(minHeight: 52)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(short > 0)
            .accessibilityIdentifier("car-pro-buy")
            if short > 0 {
                Text("You need \(CarProFormat.money(short)) more. Win it in the career.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
    }

    // MARK: - Upgrades

    private func upgrades(_ car: CarProOwnedCar) -> some View {
        let stats = car.setup.stats
        return VStack(spacing: SR.cardGap) {
            ForEach(CarProUpgradeKind.allCases) { kind in
                CarProUpgradeCard(kind: kind, setup: car.setup, before: stats, money: game.career.money,
                                  blocked: blockedTier(car, kind)) {
                    game.upgrade(car.id, kind)
                }
            }
        }
    }

    private func blockedTier(_ car: CarProOwnedCar, _ kind: CarProUpgradeKind) -> CarProTier? {
        guard let next = car.setup.withUpgrade(kind) else { return nil }
        return CarProPresent.seasonLimitBreached(career: game.career, carId: car.id, pi: next.stats.pi)
    }
}

enum CarProGarageTab: String, CaseIterable, Identifiable {
    case upgrades
    case tuning

    var id: String { rawValue }

    var name: String {
        switch self {
        case .upgrades: return "Upgrades"
        case .tuning: return "Tuning"
        }
    }
}

/// One car: its picture on the garage floor, its numbers and its bars.
struct CarProCarDetail: View {
    let model: CarProCarModel
    let setup: CarProCarSetup
    let owned: CarProOwnedCar?
    let selected: Bool
    let mph: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stats = setup.stats
        return VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                CarProShowroomFloor(hue: model.hue)
                CarProCarPortrait(look: CarProCarLook(setup: setup), spin: -0.3)
                    .padding(.vertical, 16)
                HStack {
                    CarProPIBadge(pi: stats.pi, large: true)
                    Spacer(minLength: 0)
                    Text(stats.drive.short)
                        .font(SR.Text.label(13))
                        .tracking(1)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                }
                .padding(12)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                Text(model.line)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            facts(stats)
            VStack(spacing: 10) {
                ForEach(CarProStatKind.allCases) { kind in
                    CarProStatBar(name: kind.name, value: stats.value(kind))
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
    }

    private func facts(_ stats: CarProCarStats) -> some View {
        let columns: [GridItem] = typeSize.isAccessibilitySize
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            CarProFact(label: "Power", value: "\(CarProPresent.horsepower(kilowatts: stats.power)) bhp")
            CarProFact(label: "Torque", value: "\(Int(stats.torque.rounded())) Nm")
            CarProFact(label: "Weight", value: CarProPresent.mass(stats.mass))
            CarProFact(label: "Top speed", value: CarProPresent.speedText(stats.topSpeed, mph: mph))
            CarProFact(label: "Cornering", value: String(format: "%.2f g", stats.lateralG))
            CarProFact(label: "Tyres", value: stats.compound.name)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }
}

/// An upgrade line: what it does, the stage it is at, and the next stage's
/// price and what it would do to the bars and the PI.
struct CarProUpgradeCard: View {
    let kind: CarProUpgradeKind
    let setup: CarProCarSetup
    let before: CarProCarStats
    let money: Int
    /// The championship the next stage would break the PI limit of.
    let blocked: CarProTier?
    let buy: () -> Void

    var body: some View {
        let stage = setup.upgrades[kind]
        let next = setup.withUpgrade(kind)
        let cost = setup.upgradeCost(kind)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(SR.Text.title(17))
                    .foregroundStyle(Color.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(next == nil ? SR.good : SR.accentDeep))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.name)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text(kind.stageName(stage) + (next == nil ? " · fully upgraded" : ""))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 6)
                pips(stage)
            }
            Text(kind.blurb)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let next, let cost {
                after(next.stats, stage: stage)
                buyButton(cost: cost, stage: stage)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("car-pro-upgrade-\(kind.rawValue)")
    }

    private func pips(_ stage: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(1...CarProUpgradeKind.maxStage, id: \.self) { step in
                Capsule()
                    .fill(step <= stage ? SR.accent : SR.ink.opacity(0.12))
                    .frame(width: 14, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stage \(stage) of \(CarProUpgradeKind.maxStage)")
    }

    private func after(_ stats: CarProCarStats, stage: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Next: \(kind.stageName(stage + 1))")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                Spacer(minLength: 6)
                CarProPIBadge(pi: before.pi)
                Image(systemName: "arrow.right")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityHidden(true)
                CarProPIBadge(pi: stats.pi)
            }
            ForEach(CarProStatKind.allCases) { stat in
                CarProStatBar(name: stat.name, value: before.value(stat), after: stats.value(stat))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(SR.ink.opacity(0.04)))
    }

    @ViewBuilder
    private func buyButton(cost: Int, stage: Int) -> some View {
        let short = cost - money
        Button {
            buy()
        } label: {
            SRButtonLabel(title: label(cost: cost, short: short), icon: blocked == nil && short <= 0 ? "wrench.fill" : "lock.fill",
                          fill: true)
                .frame(minHeight: 48)
        }
        .srButton(blocked == nil && short <= 0 ? .prominent : .regular)
        .controlSize(.large)
        .disabled(blocked != nil || short > 0)
        .accessibilityIdentifier("car-pro-fit-\(kind.rawValue)")
    }

    private func label(cost: Int, short: Int) -> String {
        if let blocked { return "Over the \(blocked.name) limit" }
        if short > 0 { return "\(CarProFormat.money(cost)) · need \(CarProFormat.money(short)) more" }
        return "Fit for \(CarProFormat.money(cost))"
    }
}

/// The tuning a car takes between races: brake bias, wing and final drive,
/// with what each does to the numbers as the slider moves.
struct CarProTuningCard: View {
    @ObservedObject var game: CarProGame
    let car: CarProOwnedCar
    @State private var draft = CarProTuning(brakeBias: 0.68)
    @State private var loaded = false

    private var hasWing: Bool { car.model.spec.downforceArea > 0 || car.setup.upgrades.aero > 0 }

    var body: some View {
        let trial = CarProCarSetup(model: car.model, upgrades: car.setup.upgrades, tuning: draft)
        let stats = trial.stats
        let breach = CarProPresent.seasonLimitBreached(career: game.career, carId: car.id, pi: stats.pi)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                CarProFact(label: "Top speed", value: CarProPresent.speedText(stats.topSpeed, mph: game.settings.mph))
                CarProFact(label: "Cornering", value: String(format: "%.2f g", stats.lateralG))
                VStack(alignment: .leading, spacing: 2) {
                    Text("PI")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                    CarProPIBadge(pi: stats.pi)
                }
            }
            slider(title: "Brake bias", value: $draft.brakeBias, range: CarProTuning.brakeBiasRange, step: 0.01,
                   reading: "\(CarProPresent.percent(draft.brakeBias)) front", words: CarProPresent.brakeBiasWords(draft.brakeBias),
                   enabled: true, id: "car-pro-tune-bias")
            slider(title: "Wing", value: $draft.wing, range: CarProTuning.wingRange, step: 0.05,
                   reading: CarProPresent.percent(draft.wing),
                   words: hasWing ? CarProPresent.wingWords(draft.wing) : "This car has no wing to set. Fit an aero upgrade first.",
                   enabled: hasWing, id: "car-pro-tune-wing")
            slider(title: "Final drive", value: $draft.finalDrive, range: CarProTuning.finalDriveRange, step: 0.01,
                   reading: String(format: "×%.2f", draft.finalDrive), words: CarProPresent.finalDriveWords(draft.finalDrive),
                   enabled: true, id: "car-pro-tune-final")
            if let breach {
                Label("Over the \(breach.name) limit of PI \(breach.piLimit): this car could not race the next round.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                draft = CarProTuning.factory(for: car.model)
                commit()
            } label: {
                SRButtonLabel(title: "Back to factory settings", icon: "arrow.uturn.backward", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("car-pro-tune-reset")
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = car.setup.tuning
        }
        // A VoiceOver swipe moves a slider without ending an edit: keep what
        // was set when the card goes (another tab, another car, another page).
        .onDisappear { commit() }
    }

    private func slider(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, reading: String,
                        words: String, enabled: Bool, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                Spacer(minLength: 8)
                Text(reading)
                    .font(SR.monoBold(13))
                    .foregroundStyle(SR.accent)
            }
            Slider(value: value, in: range, step: step, onEditingChanged: { editing in
                if !editing { commit() }
            })
            .tint(SR.accent)
            .disabled(!enabled)
            .accessibilityLabel(title)
            .accessibilityValue(reading)
            .accessibilityIdentifier(id)
            Text(words)
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func commit() {
        guard draft != car.setup.tuning else { return }
        game.tune(car.id, draft)
        SRHaptic.select()
    }
}

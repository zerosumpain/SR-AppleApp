import SwiftUI

/// The car the player is taking out, with a way to the garage to change it.
struct CarProCarStrip: View {
    @ObservedObject var game: CarProGame

    var body: some View {
        let car = game.selectedCar
        let stats = car.setup.stats
        return Button {
            game.open(.garage)
        } label: {
            HStack(spacing: 12) {
                CarProCarPortrait(look: CarProCarLook(setup: car.setup))
                    .frame(width: 62, height: 62)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SR.ink.opacity(0.06)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(car.model.name)
                        .font(SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                    HStack(spacing: 8) {
                        CarProPIBadge(pi: stats.pi)
                        Text("\(CarProPresent.horsepower(kilowatts: stats.power)) bhp · \(stats.drive.short)")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                Text("Change")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.accent)
                Image(systemName: "chevron.right")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper, interactive: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Car: \(car.model.name), PI \(stats.pi). Change it in the garage")
        .accessibilityIdentifier("car-pro-car-strip")
    }
}

/// A quick race: pick a circuit, the length, the field and where you start.
struct CarProQuickRaceView: View {
    @ObservedObject var game: CarProGame

    var body: some View {
        CarProPage {
            SRPageHeader(kicker: "Quick race", title: "Race anyone, anywhere",
                         strap: "Rivals in cars close to yours, on \(game.settings.difficulty.name.lowercased()) difficulty.")
            if let outcome = game.quickOutcome { lastRace(outcome) }
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Circuit", trailing: "\(CarProCircuits.all.count) circuits")
                CarProTrackPicker(selected: game.quick.trackId, best: { _ in nil }) { game.quick.trackId = $0 }
                if let track = CarProCircuits.track(game.quick.trackId) {
                    Text("\(track.name): \(track.line)")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            choices
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Your car")
                CarProCarStrip(game: game)
            }
            Button {
                SRHaptic.tap()
                game.startQuickRace()
            } label: {
                SRButtonLabel(title: "To the grid", icon: "flag.checkered", fill: true)
                    .frame(minHeight: 52)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("car-pro-quick-start")
        }
        .accessibilityIdentifier("car-pro-quick-page")
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Laps")
            HStack(spacing: 8) {
                ForEach(CarProQuickSetup.lapChoices, id: \.self) { laps in
                    CarProChip(title: "\(laps)", caption: laps == 1 ? "lap" : "laps", selected: game.quick.laps == laps) {
                        game.quick.laps = laps
                    }
                }
            }
            SRSectionLabel(text: "Rivals")
            HStack(spacing: 8) {
                ForEach(CarProQuickSetup.fieldChoices, id: \.self) { count in
                    CarProChip(title: "\(count)", caption: "cars", selected: game.quick.opponents == count) {
                        game.quick.opponents = count
                    }
                }
            }
            SRSectionLabel(text: "You start")
            HStack(spacing: 8) {
                ForEach(CarProGridStart.allCases) { start in
                    CarProChip(title: start.name, caption: "of the grid", selected: game.quick.start == start) {
                        game.quick.start = start
                    }
                }
            }
        }
    }

    private func lastRace(_ outcome: CarProGame.QuickOutcome) -> some View {
        let mine = outcome.results.first { $0.isPlayer }
        let track = CarProCircuits.track(outcome.trackId)
        let title: String
        if let mine, mine.time != nil {
            title = mine.position == 1 ? "You won" : "You finished \(CarProFormat.ordinal(mine.position))"
        } else {
            title = "You retired"
        }
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Last race", trailing: track?.name ?? "")
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                Spacer(minLength: 8)
                Button {
                    game.clearQuickOutcome()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(SR.Text.title(20))
                        .foregroundStyle(SR.inkMuted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the last race")
            }
            CarProResultsTable(results: outcome.results)
            Button {
                SRHaptic.tap()
                game.startQuickRace()
            } label: {
                SRButtonLabel(title: "Race again", icon: "arrow.clockwise", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("car-pro-quick-again")
        }
    }
}

/// Time trial: one circuit, your car, your ghost, as many laps as you like.
struct CarProTimeTrialView: View {
    @ObservedObject var game: CarProGame

    var body: some View {
        let model = game.selectedCar.model
        return CarProPage {
            SRPageHeader(kicker: "Time trial", title: "Chase the ghost",
                         strap: "A rolling start and a clear track. Your best lap in each car is kept as a ghost to beat.")
            if let outcome = game.trialOutcome { summary(outcome) }
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Circuit", trailing: "Bests in the \(model.name)")
                CarProTrackPicker(selected: game.quick.trialTrackId,
                                  best: { track in game.career.best(track: track.id, model: model) }) {
                    game.quick.trialTrackId = $0
                }
            }
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Your car")
                CarProCarStrip(game: game)
            }
            Button {
                SRHaptic.tap()
                game.startTimeTrial()
            } label: {
                SRButtonLabel(title: "Out on track", icon: "stopwatch.fill", fill: true)
                    .frame(minHeight: 52)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("car-pro-trial-start")
            bestsTable
        }
        .accessibilityIdentifier("car-pro-trial-page")
    }

    private func summary(_ outcome: CarProGame.TrialOutcome) -> some View {
        let track = CarProCircuits.track(outcome.trackId) ?? CarProCircuits.all[0]
        let fastest = outcome.laps.filter(\.valid).map(\.time).min()
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Last session", trailing: track.name)
            HStack(spacing: 12) {
                Image(systemName: outcome.newBest ? "trophy.fill" : "stopwatch.fill")
                    .font(SR.Text.title(22))
                    .foregroundStyle(Color.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(outcome.newBest ? Color(red: 0.95, green: 0.68, blue: 0.12) : SR.accentDeep))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(outcome.best.map { CarProFormat.time($0) } ?? "No clean lap")
                        .font(SR.Text.display(26))
                        .monospacedDigit()
                        .foregroundStyle(SR.ink)
                    Text(summaryLine(outcome))
                        .font(SR.Text.secondary())
                        .foregroundStyle(outcome.newBest ? SR.good : SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    game.clearTrialOutcome()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(SR.Text.title(20))
                        .foregroundStyle(SR.inkMuted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the last session")
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            if !outcome.laps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(outcome.laps) { lap in
                        if lap.id > (outcome.laps.first?.id ?? 0) { Divider().overlay(SR.divider) }
                        HStack {
                            Text("Lap \(lap.id)")
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkSecondary)
                            Spacer(minLength: 8)
                            if !lap.valid {
                                Text("DELETED")
                                    .font(SR.Text.label())
                                    .foregroundStyle(SR.error)
                            } else if lap.time == fastest {
                                Image(systemName: "bolt.fill")
                                    .font(SR.Text.label())
                                    .foregroundStyle(SR.good)
                                    .accessibilityLabel("Fastest")
                            }
                            Text(CarProFormat.time(lap.time))
                                .font(SR.Text.title(15))
                                .monospacedDigit()
                                .foregroundStyle(lap.valid ? SR.ink : SR.inkGhost)
                                .strikethrough(!lap.valid)
                        }
                        .frame(minHeight: 38)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 4)
                .srGlassCard(.paper)
            }
            if let last = outcome.last, !last.speeds.isEmpty {
                SRSectionLabel(text: "Telemetry", trailing: "speed against distance")
                CarProTelemetryChart(last: last, best: outcome.bestTrace, track: track, mph: game.settings.mph)
            }
        }
    }

    private func summaryLine(_ outcome: CarProGame.TrialOutcome) -> String {
        if outcome.newBest {
            if let before = outcome.previousBest, let best = outcome.best {
                return "A new best, \(String(format: "%.3f", before - best)) s quicker. It's your ghost now."
            }
            return "Your first time here in the \(outcome.model.name). It's your ghost now."
        }
        if let before = outcome.previousBest, let best = outcome.best {
            return "\(String(format: "%.3f", best - before)) s off your best of \(CarProFormat.time(before))."
        }
        return "\(outcome.laps.count) lap\(outcome.laps.count == 1 ? "" : "s"), none clean. Keep four wheels on the track."
    }

    private var bestsTable: some View {
        let bests = game.career.bests.sorted { a, b in
            a.trackId == b.trackId ? a.time < b.time : a.trackId < b.trackId
        }
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            if !bests.isEmpty {
                SRSectionLabel(text: "Your bests", trailing: "\(bests.count)")
                VStack(spacing: 0) {
                    ForEach(Array(bests.enumerated()), id: \.offset) { index, best in
                        if index > 0 { Divider().overlay(SR.divider) }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(CarProCircuits.track(best.trackId)?.name ?? best.trackId)
                                    .font(SR.Text.title(15))
                                    .foregroundStyle(SR.ink)
                                Text(best.model.name)
                                    .font(SR.Text.mono())
                                    .foregroundStyle(SR.inkMuted)
                            }
                            Spacer(minLength: 8)
                            Text(CarProFormat.time(best.time))
                                .font(SR.Text.title(15))
                                .monospacedDigit()
                                .foregroundStyle(SR.ink)
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 4)
                .srGlassCard(.paper)
            }
        }
    }
}

/// The aids, the steering, the difficulty, the units and the name.
struct CarProSettingsView: View {
    @ObservedObject var game: CarProGame
    @State private var name = ""
    @State private var confirmReset = false

    var body: some View {
        CarProPage {
            SRPageHeader(kicker: "Settings", title: "Your way to drive",
                         strap: "Turn the aids off one at a time as you get quicker. Every one off is a little faster, and harder.")
            aids
            steering
            race
            driver
            Button(role: .destructive) {
                confirmReset = true
            } label: {
                SRButtonLabel(title: "Start a new career", icon: "arrow.counterclockwise", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("car-pro-reset")
        }
        .onAppear { name = game.settings.playerName }
        .confirmationDialog("Start a new career?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Start again from the Club Cup", role: .destructive) { game.newCareer() }
            Button("Keep my career", role: .cancel) {}
        } message: {
            Text("Your money, cars, upgrades, titles and best laps go. Your settings stay.")
        }
        .accessibilityIdentifier("car-pro-settings-page")
    }

    private func toggle(_ title: String, _ line: String, _ value: Bool, id: String,
                        set: @escaping (inout CarProSettings, Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: { on in game.updateSettings { set(&$0, on) } })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                Text(line)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(SR.accent)
        .padding(.vertical, 6)
        .accessibilityIdentifier(id)
    }

    private var aids: some View {
        let a = game.settings.assists
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Driving aids", trailing: "\(a.count) of 6 on")
            VStack(spacing: 4) {
                toggle("Steering help", "Catches a slide for you and never asks the tyres for more than they have.",
                       a.steering, id: "car-pro-aid-steering") { $0.assists.steering = $1 }
                Divider().overlay(SR.divider)
                toggle("Traction control", "Trims the throttle when the driven wheels spin.", a.traction,
                       id: "car-pro-aid-traction") { $0.assists.traction = $1 }
                Divider().overlay(SR.divider)
                toggle("Anti-lock brakes", "Lets a locking wheel roll so you can brake and steer.", a.abs,
                       id: "car-pro-aid-abs") { $0.assists.abs = $1 }
                Divider().overlay(SR.divider)
                toggle("Automatic gears", "Off: change gear yourself with Up and Down.", a.autoGears,
                       id: "car-pro-aid-gears") { $0.assists.autoGears = $1 }
                Divider().overlay(SR.divider)
                toggle("Braking boards", "Boards and a red bar where to brake for each bend.", a.brakingMarkers,
                       id: "car-pro-aid-boards") { $0.assists.brakingMarkers = $1 }
                Divider().overlay(SR.divider)
                toggle("Racing line", "The quick way round painted on the road.", a.racingLine,
                       id: "car-pro-aid-line") { $0.assists.racingLine = $1 }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 8)
            .srGlassCard(.paper)
            HStack(spacing: 10) {
                Button {
                    game.updateSettings { $0.assists = .full }
                } label: {
                    SRButtonLabel(title: "All on", fill: true).frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                Button {
                    game.updateSettings { $0.assists = .none }
                } label: {
                    SRButtonLabel(title: "All off", fill: true).frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
            }
        }
    }

    private var steering: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Steering")
            HStack(spacing: 8) {
                ForEach(CarProSteeringMode.allCases) { mode in
                    CarProChip(title: mode.name, caption: Self.caption(mode), selected: game.settings.steering == mode) {
                        game.updateSettings { $0.steering = mode }
                    }
                    .disabled(mode == .tilt && !PhysicsTilt.isAvailable)
                    .opacity(mode == .tilt && !PhysicsTilt.isAvailable ? 0.45 : 1)
                    .accessibilityIdentifier("car-pro-steer-\(mode.rawValue)")
                }
            }
            Text(steeringLine)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func caption(_ mode: CarProSteeringMode) -> String {
        switch mode {
        case .tilt: return "the phone"
        case .wheel: return "on screen"
        case .slider: return "thumb"
        }
    }

    private var steeringLine: String {
        switch game.settings.steering {
        case .tilt: return PhysicsTilt.isAvailable ? "Hold the phone like a wheel; the target button sets straight ahead."
            : "This phone can't steer by tilt, so the slider steers instead."
        case .wheel: return "A wheel under your left thumb: turn it, let go and it centres."
        case .slider: return "Slide your left thumb either way from wherever it lands."
        }
    }

    private var race: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Rivals")
            HStack(spacing: 8) {
                ForEach(CarProDifficulty.allCases) { level in
                    CarProChip(title: level.name, caption: "rivals", selected: game.settings.difficulty == level) {
                        game.updateSettings { $0.difficulty = level }
                    }
                    .accessibilityIdentifier("car-pro-difficulty-\(level.rawValue)")
                }
            }
            Text("New seasons and quick races use this. A season under way keeps the drivers it started with.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            SRSectionLabel(text: "Speed in")
            HStack(spacing: 8) {
                CarProChip(title: "mph", caption: "miles", selected: game.settings.mph) {
                    game.updateSettings { $0.mph = true }
                }
                CarProChip(title: "km/h", caption: "kilometres", selected: !game.settings.mph) {
                    game.updateSettings { $0.mph = false }
                }
            }
        }
    }

    private var driver: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Your name on the timing screens")
            TextField("You", text: $name)
                .font(SR.Text.body())
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit { saveName() }
                .onChange(of: name) { _, _ in saveName() }
                .padding(.horizontal, SR.cardPadding)
                .frame(minHeight: 52)
                .srGlassCard(.paper, radius: SR.Glass.innerRadius)
                .accessibilityIdentifier("car-pro-name")
        }
    }

    private func saveName() {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        game.updateSettings { $0.playerName = trimmed.isEmpty ? "You" : trimmed }
    }
}

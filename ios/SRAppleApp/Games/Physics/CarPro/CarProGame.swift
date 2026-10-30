import SwiftUI

/// Car Racer+ as the screens see it: the career (saved after every
/// change), which page is up, the race weekend in progress, the session on
/// the circuit, and what the last quick race and time trial came to.
@MainActor
final class CarProGame: ObservableObject {
    enum Page: Equatable {
        case home
        case career
        case weekend
        case quickRace
        case timeTrial
        case garage
        case settings
    }

    /// A championship round, from the briefing to the result.
    struct Weekend: Equatable {
        enum Stage: Equatable {
            case briefing
            /// Qualifying done (or skipped): the grid.
            case grid(rows: [CarProQualifyingRow], playerLap: Double?)
            case result(results: [CarProResult], reward: CarProRaceReward?)
        }

        var weekend: CarProWeekend
        var stage: Stage
    }

    /// What a quick race came to.
    struct QuickOutcome: Equatable {
        var trackId: String
        var laps: Int
        var results: [CarProResult]
    }

    /// What a time-trial session came to.
    struct TrialOutcome: Equatable {
        var trackId: String
        var model: CarProCarModel
        var laps: [CarProLapLine]
        var best: Double?
        /// The best for this circuit and car before the session.
        var previousBest: Double?
        var newBest: Bool
        var last: CarProTelemetry?
        var bestTrace: CarProTelemetry?
    }

    @Published private(set) var career: CarProCareer
    @Published var page: Page = .home
    @Published private(set) var weekend: Weekend?
    @Published private(set) var race: CarProRaceController?
    @Published var quick: CarProQuickSetup {
        didSet { if quick != oldValue { quick.save() } }
    }
    @Published private(set) var quickOutcome: QuickOutcome?
    @Published private(set) var trialOutcome: TrialOutcome?
    /// A one-line answer to something the career refused.
    @Published private(set) var notice: String?

    /// The intro card's words for the session on the circuit.
    private(set) var raceTitle = ""
    private(set) var raceLine = ""

    private let store = CarProStore()
    private var trialNewBest = false
    private var trialPreviousBest: Double?
    private var noticeTask: Task<Void, Never>?

    init() {
        career = CarProStore().load()
        quick = CarProQuickSetup.load()
    }

    var settings: CarProSettings { career.settings }
    var selectedCar: CarProOwnedCar { career.selectedCar }

    // MARK: - Pages

    func open(_ next: Page) {
        SRHaptic.select()
        page = next
    }

    /// The bar's back button: the weekend goes back to the career, the rest home.
    func back() {
        page = page == .weekend ? .career : .home
    }

    func say(_ words: String) {
        notice = words
        noticeTask?.cancel()
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func clearNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    private func refuse(_ error: Error) {
        SRHaptic.bad()
        if let error = error as? CarProCareerError {
            say(CarProPresent.words(for: error))
        } else {
            say("That didn't work.")
        }
    }

    private func save() { store.save(career) }

    // MARK: - Garage

    func buy(_ model: CarProCarModel) {
        do {
            try career.buy(model)
            save()
            SRHaptic.ok()
            say("The \(model.name) is yours.")
        } catch {
            refuse(error)
        }
    }

    func select(_ carId: String) {
        guard carId != career.selectedCarId else { return }
        do {
            try career.select(carId: carId)
            save()
            SRHaptic.select()
        } catch {
            refuse(error)
        }
    }

    func upgrade(_ carId: String, _ kind: CarProUpgradeKind) {
        guard let car = career.car(carId), let next = car.setup.withUpgrade(kind) else { return }
        if let tier = CarProPresent.seasonLimitBreached(career: career, carId: carId, pi: next.stats.pi) {
            SRHaptic.bad()
            say("That would take it over the \(tier.name) limit of PI \(tier.piLimit) mid-season.")
            return
        }
        do {
            let cost = try career.buyUpgrade(carId: carId, kind: kind)
            save()
            SRHaptic.ok()
            say("\(kind.name): \(kind.stageName(car.setup.upgrades[kind] + 1)) fitted for \(CarProFormat.money(cost)).")
        } catch {
            refuse(error)
        }
    }

    func tune(_ carId: String, _ tuning: CarProTuning) {
        do {
            try career.setTuning(carId: carId, tuning)
            save()
        } catch {
            refuse(error)
        }
    }

    // MARK: - Settings

    func updateSettings(_ change: (inout CarProSettings) -> Void) {
        var next = career.settings
        change(&next)
        guard next != career.settings else { return }
        career.settings = next
        save()
    }

    /// Everything back to a fresh career, keeping the player's settings.
    func newCareer() {
        let settings = career.settings
        career = .newCareer()
        career.settings = settings
        weekend = nil
        save()
        SRHaptic.ok()
        page = .home
    }

    // MARK: - Seasons

    func startSeason(_ tier: CarProTier, carId: String) {
        do {
            try career.startSeason(tier, carId: carId)
            weekend = nil
            save()
            SRHaptic.ok()
        } catch {
            refuse(error)
        }
    }

    func abandonSeason() {
        career.abandonSeason()
        weekend = nil
        save()
    }

    /// The next round's weekend, from its briefing (or where it was left).
    func openWeekend() {
        guard let next = career.nextWeekend() else { return }
        let pi = next.player.setup.stats.pi
        if pi > next.tier.piLimit {
            SRHaptic.bad()
            say("Your car's PI is \(pi), over the \(next.tier.name) limit of \(next.tier.piLimit). Ease its tuning back.")
            return
        }
        if let current = weekend, current.weekend.round == next.round, current.weekend.tier == next.tier,
           current.weekend.player == next.player {
            if case .result = current.stage {} else {
                page = .weekend
                return
            }
        }
        weekend = Weekend(weekend: next, stage: .briefing)
        page = .weekend
    }

    func qualify() {
        guard let current = weekend else { return }
        let w = current.weekend
        let ghost = store.ghost(track: w.trackId, model: w.player.setup.model)
        let config = w.qualifyingConfig(assists: settings.assists, ghost: ghost)
        raceTitle = "Two timed laps"
        raceLine = "Your quicker lap sets your place on the grid for \(w.laps) laps of \(w.track.name)."
        present(.qualifying, config) { [weak self] controller in self?.qualified(controller) }
    }

    /// Straight to the race, from the back of the grid.
    func skipQualifying() {
        guard var current = weekend else { return }
        current.stage = .grid(rows: current.weekend.qualifying(playerLap: nil), playerLap: nil)
        weekend = current
    }

    private func qualified(_ controller: CarProRaceController) {
        guard var current = weekend else { return }
        let lap = controller.session.player.bestLap
        current.stage = .grid(rows: current.weekend.qualifying(playerLap: lap), playerLap: lap)
        weekend = current
        race = nil
    }

    func startRace() {
        guard let current = weekend, case let .grid(rows, _) = current.stage else { return }
        let w = current.weekend
        let config = w.raceConfig(grid: rows.map(\.entrant), assists: settings.assists)
        let slot = (rows.firstIndex { $0.entrant.isPlayer } ?? 0) + 1
        raceTitle = "\(w.laps) laps"
        raceLine = "Round \(w.round + 1) of the \(w.tier.name). You start \(CarProFormat.ordinal(slot)) of \(rows.count)."
        present(.championship, config) { [weak self] controller in self?.raced(controller) }
    }

    private func raced(_ controller: CarProRaceController) {
        guard var current = weekend, case let .grid(rows, _) = current.stage else { race = nil; return }
        let results = controller.results
        let pole = rows.first?.entrant.isPlayer ?? false
        let reward = career.recordRace(results, pole: pole)
        save()
        current.stage = .result(results: results, reward: reward)
        weekend = current
        race = nil
        if let reward, reward.position <= 3 || reward.title { SRHaptic.ok() }
    }

    /// Done with the weekend's result.
    func closeWeekend() {
        weekend = nil
        page = .career
    }

    // MARK: - Quick race

    func startQuickRace() {
        let car = career.selectedCar
        let player = CarProEntrant.player(name: settings.playerName, setup: car.setup)
        let seed = UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF_FFFF
        let opponents = CarProField.quickRace(for: car.setup, count: quick.opponents, difficulty: settings.difficulty,
                                              seed: seed)
        let config = CarProSessionConfig.quickRace(track: quick.trackId, laps: quick.laps, player: player,
                                                   opponents: opponents, assists: settings.assists,
                                                   playerSlot: quick.start.slot(opponents: opponents.count), seed: seed)
        let name = CarProCircuits.track(quick.trackId)?.name ?? "the circuit"
        raceTitle = "\(quick.laps) lap\(quick.laps == 1 ? "" : "s")"
        raceLine = "\(opponents.count) rivals in cars near yours at \(name). Quick races don't pay; the career does."
        present(.quickRace, config) { [weak self] controller in
            guard let self else { return }
            self.quickOutcome = QuickOutcome(trackId: controller.config.trackId, laps: controller.config.laps,
                                             results: controller.results)
            self.race = nil
        }
    }

    func clearQuickOutcome() { quickOutcome = nil }

    // MARK: - Time trial

    func startTimeTrial() {
        let car = career.selectedCar
        let trackId = quick.trialTrackId
        let player = CarProEntrant.player(name: settings.playerName, setup: car.setup)
        let ghost = store.ghost(track: trackId, model: car.model)
        let config = CarProSessionConfig.timeTrial(track: trackId, player: player, assists: settings.assists, ghost: ghost)
        trialPreviousBest = career.best(track: trackId, model: car.model)
        trialNewBest = false
        raceTitle = trialPreviousBest.map { "Beat \(CarProFormat.time($0))" } ?? "Set a time"
        raceLine = ghost == nil ? "A rolling start, as many laps as you like. Your best becomes the ghost to chase."
            : "Your best lap in the \(car.model.name) is out there with you, as a ghost."
        present(.timeTrial, config, onLap: { [weak self] controller, time, valid in
            self?.trialLap(controller, time: time, valid: valid)
        }) { [weak self] controller in
            self?.trialDone(controller)
        }
    }

    private func trialLap(_ controller: CarProRaceController, time: Double, valid: Bool) {
        guard valid else { return }
        let session = controller.session
        let model = session.player.entrant.setup.model
        guard career.recordTimeTrial(track: session.track.id, model: model, lap: time) else { return }
        trialNewBest = true
        save()
        if let ghost = session.bestGhost, abs(ghost.lapTime - time) < 1e-6 { store.saveGhost(ghost) }
    }

    private func trialDone(_ controller: CarProRaceController) {
        let session = controller.session
        trialOutcome = TrialOutcome(trackId: session.track.id, model: session.player.entrant.setup.model,
                                    laps: controller.laps, best: session.player.bestLap, previousBest: trialPreviousBest,
                                    newBest: trialNewBest, last: session.lastTelemetry, bestTrace: session.bestTelemetry)
        race = nil
    }

    func clearTrialOutcome() { trialOutcome = nil }

    // MARK: - On the circuit

    private func present(_ purpose: CarProRaceController.Purpose, _ config: CarProSessionConfig,
                         onLap: (@MainActor (CarProRaceController, Double, Bool) -> Void)? = nil,
                         onFinish: @escaping @MainActor (CarProRaceController) -> Void) {
        race?.stop()
        let controller = CarProRaceController(purpose: purpose, config: config, steering: settings.steering,
                                              mph: settings.mph)
        controller.onLap = onLap
        controller.onFinish = onFinish
        race = controller
    }

    /// Off the circuit without a result: from the intro card, or a screen gone.
    func leaveRace() {
        race?.stop()
        race = nil
    }
}

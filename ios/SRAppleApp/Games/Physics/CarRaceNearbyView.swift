import SwiftUI

/// Car Race over "Play nearby": this phone drives its own car with the same
/// `CarRaceDriver` as a race on one phone, and the room carries everyone's
/// positions. The host's view arrives several times a second; each other car
/// is drawn a third of a second behind the race clock, sliding between the
/// last two positions heard, so a car on a slow link glides rather than jumps.
///
/// Registered in `OfflineCatalogue` as
/// `OfflineCatalogueItem(CarRaceNearbyRules.self) { CarRaceNearbyView(context: $0) }`.
struct CarRaceNearbyView: View {
    let context: OfflineGameContext<CarRaceNearbyRules>
    @StateObject private var driver: CarRaceDriver

    /// How far behind the race clock other cars are drawn, seconds.
    private static let delay = 0.3

    init(context: OfflineGameContext<CarRaceNearbyRules>) {
        self.context = context
        let view = context.view
        let track = CarTrack.named(view.trackId) ?? .paddock
        let me = view.racers.first { $0.id == context.me }
        _driver = StateObject(wrappedValue: CarRaceDriver(
            track: track, laps: view.laps, slot: me?.seat ?? 0, name: me?.name ?? "You",
            useTilt: UserDefaults.standard.object(forKey: "physics.car.tilt") as? Bool ?? true,
            startsAt: context.clock.local(fromHost: view.startsAt)))
    }

    private var view: CarRaceNearbyRules.PlayerView { context.view }
    private var me: CarRaceNearbyRules.Racer? { view.racers.first { $0.id == context.me } }

    var body: some View {
        Group {
            if let me {
                ZStack {
                    CarRaceView(driver: driver, seat: me.seat)
                    if me.finish != nil || driver.phase == .finished {
                        VStack {
                            Spacer()
                            waiting
                                .padding(.horizontal, 16)
                                .padding(.bottom, 96)
                        }
                    }
                }
            } else {
                watching
            }
        }
        .onAppear { follow() }
        .onChange(of: view) { _, _ in follow() }
        .onChange(of: context.clock) { _, _ in follow() }
        .accessibilityIdentifier("offline-car-race")
    }

    /// Hand the latest view to the driver: the start (as this phone's clock
    /// now reads the host's), the callbacks, and every other car's position.
    private func follow() {
        guard me != nil else { return }
        driver.setStart(context.clock.local(fromHost: view.startsAt))
        let send = context.send
        driver.onReport = { car, laps, time in
            send(.position(x: car.x, y: car.y, heading: car.heading, raced: laps.raced, lap: laps.lap, at: time))
        }
        driver.onFinish = { laps, _ in
            guard let time = laps.finishTime else { return }
            send(.finish(time: time, bestLap: laps.bestLap))
        }
        var rivals = driver.rivals
        for racer in view.racers where racer.id != context.me {
            let sample = CarGhost.Sample(t: racer.at, x: racer.x, y: racer.y, heading: racer.heading, raced: racer.raced)
            if let index = rivals.firstIndex(where: { $0.id == racer.id }) {
                rivals[index].ghost.append(sample)
                rivals[index].finished = racer.finish != nil
            } else {
                var ghost = CarGhost(trackId: view.trackId, laps: view.laps, name: racer.name)
                ghost.append(sample)
                rivals.append(CarRival(id: racer.id, name: racer.name, seat: racer.seat, ghost: ghost,
                                       delay: Self.delay, finished: racer.finish != nil))
            }
        }
        if rivals != driver.rivals { driver.rivals = rivals }
    }

    /// Home, with the others still racing: where I came, and the clock on them.
    private var waiting: some View {
        let finishers = view.racers.compactMap(\.finish).sorted()
        let mine = me?.finish ?? driver.counter.finishTime
        let place = mine.map { time in 1 + finishers.filter { $0 < time }.count }
        return VStack(alignment: .leading, spacing: 6) {
            Text(place.map { "FINISHED · P\($0)" } ?? "FINISHED")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.good)
            if let mine {
                Text(CarRaceFormat.time(mine))
                    .font(SR.Text.figure(30))
                    .foregroundStyle(SR.ink)
            }
            HStack(spacing: 6) {
                Text("Waiting for the others —")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                OfflineCountdown(clock: context.clock, until: view.endsAt, font: SR.Text.mono(), tone: SR.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-car-race-waiting")
    }

    /// A spectator: who is on which lap.
    private var watching: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Watching", title: CarTrack.named(view.trackId)?.name ?? "Car Race",
                             strap: "\(view.laps) laps. You're watching this race.")
                VStack(spacing: 0) {
                    ForEach(Array(view.racers.sorted { $0.raced > $1.raced }.enumerated()), id: \.element.id) { index, racer in
                        if index > 0 { Divider().overlay(SR.divider) }
                        HStack(spacing: 10) {
                            Circle().fill(OfflineSeatColour.of(racer.seat)).frame(width: 12, height: 12)
                            Text(racer.name)
                                .font(SR.Text.bodyMedium(15))
                                .foregroundStyle(SR.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(racer.finish.map { CarRaceFormat.time($0) } ?? "Lap \(racer.lap)")
                                .font(SR.Text.mono(15))
                                .foregroundStyle(SR.inkSecondary)
                        }
                        .frame(minHeight: 36)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 6)
                .srGlassCard(.paper)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
    }
}

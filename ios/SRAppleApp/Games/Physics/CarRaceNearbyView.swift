import SwiftUI

/// Car Race over "Play nearby": this phone drives its own car with the same
/// `CarRaceDriver` as a race on one phone, and the room carries everyone's
/// positions. The host's view arrives several times a second; each other car
/// is drawn where it should be NOW — carried on from the last position heard
/// at its speed, with each fresh report's correction eased in — and is solid:
/// this phone bounces its own car off it (`CarRaceDriver.hear`, `isSolid`).
///
/// Registered in `OfflineCatalogue` as
/// `OfflineCatalogueItem(CarRaceNearbyRules.self) { CarRaceNearbyView(context: $0) }`.
struct CarRaceNearbyView: View {
    let context: OfflineGameContext<CarRaceNearbyRules>
    @StateObject private var driver: CarRaceDriver

    init(context: OfflineGameContext<CarRaceNearbyRules>) {
        self.context = context
        let view = context.view
        let track = CarTrack.named(view.trackId) ?? .paddock
        let me = view.racers.first { $0.id == context.me }
        _driver = StateObject(wrappedValue: CarRaceDriver(
            track: track, laps: view.laps, slot: me?.seat ?? 0, name: me?.name ?? "You",
            // Tilt only where there is a sensor to read; without one the arrows steer.
            useTilt: (UserDefaults.standard.object(forKey: "physics.car.tilt") as? Bool ?? true) && PhysicsTilt.isAvailable,
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
        for racer in view.racers where racer.id != context.me {
            let sample = CarGhost.Sample(t: racer.at, x: racer.x, y: racer.y, heading: racer.heading, raced: racer.raced)
            // A car whose phone has left sends no more news: it goes stale,
            // fades and is driven through like any car gone quiet.
            driver.hear(sample, from: racer.id, name: racer.name, seat: racer.seat, finished: racer.finish != nil)
        }
    }

    /// Home, with the others still racing: where I came, who is still out
    /// there and on which lap, and the clock on them.
    private var waiting: some View {
        let finishers = view.racers.compactMap(\.finish).sorted()
        let mine = me?.finish ?? driver.counter.finishTime
        let place = mine.map { time in 1 + finishers.filter { $0 < time }.count }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                if let place {
                    Text("P\(place)")
                        .font(SR.Text.display(22))
                        .foregroundStyle(Color.white)
                        .monospacedDigit()
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(Self.medal(place)))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.map { "FINISHED · P\($0)" } ?? "FINISHED")
                        .font(SR.Text.label())
                        .tracking(SR.inkKickerTracking)
                        .foregroundStyle(SR.good)
                    if let mine {
                        Text(CarRaceFormat.time(mine))
                            .font(SR.Text.figure(30))
                            .foregroundStyle(SR.ink)
                    }
                }
            }
            standings
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
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

    /// Everyone in the order they are running: home first by time, then by how far round.
    private var ordered: [CarRaceNearbyRules.Racer] {
        view.racers.sorted { a, b in
            switch (a.finish, b.finish) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.raced > b.raced
            }
        }
    }

    /// One short line per car: colour, name, and a time or the lap they are on.
    private var standings: some View {
        VStack(spacing: 4) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, racer in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .frame(width: 16, alignment: .leading)
                    Circle().fill(OfflineSeatColour.of(racer.seat)).frame(width: 10, height: 10)
                    Text(racer.id == context.me ? "\(racer.name) (you)" : racer.name)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(racer.finish.map { CarRaceFormat.time($0) } ?? (racer.away ? "Left" : "Lap \(racer.lap)/\(view.laps)"))
                        .font(SR.Text.mono())
                        .foregroundStyle(racer.finish != nil ? SR.good : SR.inkSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(SR.ink.opacity(0.06)))
    }

    /// Gold, silver, bronze; the seat-blue after that.
    private static func medal(_ place: Int) -> Color {
        switch place {
        case 1: return Color(red: 0.90, green: 0.65, blue: 0.10)
        case 2: return Color(red: 0.55, green: 0.58, blue: 0.64)
        case 3: return Color(red: 0.70, green: 0.42, blue: 0.22)
        default: return SR.accent
        }
    }

    /// A spectator: the track, and who is on which lap, with how far round.
    private var watching: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Watching", title: CarTrack.named(view.trackId)?.name ?? "Car Race",
                             strap: "\(view.laps) laps. You're watching this race.")
                if let track = CarTrack.named(view.trackId) {
                    CarRaceTrackMap(track: track)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
                }
                VStack(spacing: 0) {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, racer in
                        if index > 0 { Divider().overlay(SR.divider) }
                        watchRow(index: index, racer: racer)
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

    private func watchRow(index: Int, racer: CarRaceNearbyRules.Racer) -> some View {
        let length = CarTrack.named(view.trackId)?.length ?? 1
        let share = min(1, max(0, racer.raced / max(1, length * Double(max(1, view.laps)))))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(SR.Text.title())
                    .foregroundStyle(index == 0 ? SR.accent : SR.inkGhost)
                    .frame(width: 22, alignment: .leading)
                Circle().fill(OfflineSeatColour.of(racer.seat)).frame(width: 12, height: 12)
                Text(racer.name)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(racer.finish.map { CarRaceFormat.time($0) } ?? "Lap \(racer.lap)")
                    .font(SR.Text.mono(15))
                    .foregroundStyle(racer.finish != nil ? SR.good : SR.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.ink.opacity(0.1))
                    Capsule()
                        .fill(OfflineSeatColour.of(racer.seat))
                        .frame(width: geo.size.width * CGFloat(racer.finish != nil ? 1 : share))
                }
            }
            .frame(height: 5)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

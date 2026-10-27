import SwiftUI

/// How a race on one phone is run.
enum CarRaceMode: String, CaseIterable, Identifiable {
    /// Alone, against the ghost of your best run on the track.
    case timeTrial
    /// Two to four drivers take turns on one phone; each races the ghosts of those before.
    case passAndPlay
    /// Phone to phone over "Play nearby".
    case nearby

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeTrial: return "Time trial"
        case .passAndPlay: return "Pass the phone"
        case .nearby: return "Race nearby"
        }
    }

    var line: String {
        switch self {
        case .timeTrial: return "Just you, against the ghost of your best run."
        case .passAndPlay: return "Two to four of you take turns on this phone, each racing the ghosts of those before."
        case .nearby: return "Two to four phones in the same room, over Bluetooth or a hotspot. No internet needed."
        }
    }

    var icon: String {
        switch self {
        case .timeTrial: return "stopwatch.fill"
        case .passAndPlay: return "person.2.fill"
        case .nearby: return "dot.radiowaves.left.and.right"
        }
    }
}

/// A race on one phone: a time trial, or drivers taking turns. It hands each
/// driver a `CarRaceDriver` with the right ghosts, keeps the results and the
/// bests, and says what comes next.
@MainActor
final class CarRaceSession: ObservableObject {
    enum Stage: Equatable {
        /// Waiting for driver `index` to take the phone and tap Start.
        case ready(Int)
        case racing(Int)
        /// Driver `index` has crossed the line (or given up).
        case finished(Int)
        /// Everyone has driven.
        case table
    }

    let mode: CarRaceMode
    let track: CarTrack
    let laps: Int
    let names: [String]
    let useTilt: Bool
    @Published private(set) var stage: Stage = .ready(0)
    @Published private(set) var driver: CarRaceDriver?
    @Published private(set) var entries: [CarRaceEntry] = []
    @Published private(set) var book: PhysicsScoreBook
    /// The time trial's ghost: the best run on this track, from before this session.
    private(set) var best: CarGhost?
    @Published private(set) var newBest = false
    private var ghosts: [CarGhost] = []
    private let store = PhysicsScoreStore()

    init(mode: CarRaceMode, track: CarTrack, laps: Int, names: [String], useTilt: Bool) {
        self.mode = mode
        self.track = track
        self.laps = laps
        self.names = names.isEmpty ? ["You"] : names
        self.useTilt = useTilt
        let store = PhysicsScoreStore()
        book = store.load()
        best = store.ghost(track: track.id, laps: laps)
    }

    var currentName: String {
        switch stage {
        case .ready(let i), .racing(let i), .finished(let i): return names[min(i, names.count - 1)]
        case .table: return ""
        }
    }

    /// Lights out in three seconds for the driver whose turn it is.
    func go() {
        guard case .ready(let index) = stage else { return }
        let driver = CarRaceDriver(track: track, laps: laps, slot: 0, name: names[index], useTilt: useTilt,
                                   startsAt: OfflineUptime.now() + 3)
        var rivals: [CarRival] = []
        if mode == .timeTrial, let best {
            rivals.append(CarRival(id: "best", name: "Best", seat: 1, ghost: best))
        }
        for (seat, ghost) in ghosts.enumerated() {
            rivals.append(CarRival(id: "ghost-\(seat)", name: ghost.name, seat: seat, ghost: ghost))
        }
        driver.rivals = rivals
        driver.onFinish = { [weak self] laps, ghost in self?.finish(index, laps: laps, ghost: ghost) }
        self.driver = driver
        stage = .racing(index)
        driver.start()
    }

    /// Give up the run: no time, and on to the next driver.
    func retire() {
        guard case .racing(let index) = stage else { return }
        driver?.stop()
        entries.append(CarRaceEntry(id: "\(index)", name: names[index], time: nil, bestLap: driver?.counter.bestLap))
        stage = .finished(index)
    }

    /// After a finish: the next driver, or the table.
    func next() {
        guard case .finished(let index) = stage else { return }
        driver?.stop()
        driver = nil
        if index + 1 < names.count {
            stage = .ready(index + 1)
        } else {
            stage = mode == .timeTrial ? .ready(0) : .table
            if mode == .timeTrial {
                // Another go: the best (perhaps just set) is the ghost now.
                best = store.ghost(track: track.id, laps: laps)
                entries = []
                newBest = false
            }
        }
    }

    func stop() { driver?.stop() }

    var ranked: [CarRaceEntry] { CarRaceEntry.ranked(entries) }

    private func finish(_ index: Int, laps: CarLapCounter, ghost: CarGhost) {
        guard let time = laps.finishTime else { return }
        entries.append(CarRaceEntry(id: "\(index)", name: names[index], time: time, bestLap: laps.bestLap))
        // The pass-the-phone drivers after this one race this run's ghost.
        var mine = ghost
        mine.name = names[index]
        ghosts.append(mine)
        var book = self.book
        let isBest = book.recordRace(track: track.id, time: time, bestLap: laps.bestLap)
        store.save(book)
        if isBest { store.saveGhost(mine) }
        self.book = book
        newBest = isBest
        stage = .finished(index)
    }
}

/// A pass-the-phone driver's name as typed, with an id so a row can be removed safely.
struct CarRaceName: Identifiable, Equatable {
    let id = UUID()
    var text = ""
}

/// Car Race: pick a way to race and a track, then race.
struct CarRaceScreen: View {
    @EnvironmentObject private var router: Router
    @State private var mode: CarRaceMode = .timeTrial
    @State private var trackId = CarTrack.paddock.id
    @State private var laps = 3
    @State private var names = [CarRaceName(), CarRaceName()]
    @AppStorage("physics.car.tilt") private var steerByTilt = true
    @State private var session: CarRaceSession?
    @State private var book = PhysicsScoreStore().load()
    private var tiltAvailable: Bool { PhysicsTilt.isAvailable }

    var body: some View {
        Group {
            if let session {
                CarRaceSessionView(session: session) {
                    session.stop()
                    book = PhysicsScoreStore().load()
                    self.session = nil
                }
            } else {
                setup
            }
        }
        .navigationTitle(GameKind.carRace.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var track: CarTrack { CarTrack.named(trackId) ?? .paddock }

    /// Racing nearby needs Car Race in the Play nearby catalogue; until it is
    /// there the choice would lead nowhere, so it is not offered.
    private var nearbyReady: Bool { OfflineCatalogue.item(CarRaceNearbyRules.info.id) != nil }

    // MARK: - Setup

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Physics", title: GameKind.carRace.title, strap: GameKind.carRace.line)

                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: "How")
                    ForEach(CarRaceMode.allCases.filter { $0 != .nearby || nearbyReady }) { option in
                        choice(title: option.title, line: option.line, icon: option.icon, selected: mode == option,
                               id: "car-race-mode-\(option.rawValue)") { mode = option }
                    }
                }

                if mode == .nearby {
                    nearby
                } else {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "Track")
                        ForEach(CarTrack.all) { option in
                            choice(title: option.name, line: trackLine(option), icon: "flag.checkered",
                                   selected: trackId == option.id, id: "car-race-track-\(option.id)") { trackId = option.id }
                        }
                        Picker("Laps", selection: $laps) {
                            ForEach([1, 3, 5], id: \.self) { Text("\($0) lap\($0 == 1 ? "" : "s")").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("car-race-laps")
                    }

                    if mode == .passAndPlay { drivers }

                    steering

                    Button {
                        SRHaptic.tap()
                        let who = mode == .passAndPlay ? cleanNames : ["You"]
                        session = CarRaceSession(mode: mode, track: track, laps: laps, names: who,
                                                 useTilt: steerByTilt && tiltAvailable)
                    } label: {
                        SRButtonLabel(title: "To the grid", icon: "flag.checkered", fill: true)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .accessibilityIdentifier("car-race-start")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("car-race-setup")
    }

    private func trackLine(_ option: CarTrack) -> String {
        guard let best = book.carBest[option.id] else { return option.line }
        return "\(option.line) Your best: \(CarRaceFormat.time(best))."
    }

    private var cleanNames: [String] {
        names.enumerated().map { index, name in
            let trimmed = name.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Player \(index + 1)" : String(trimmed.prefix(16))
        }
    }

    private var drivers: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Drivers", trailing: "\(names.count) of 4")
            ForEach($names) { $name in
                let index = names.firstIndex { $0.id == name.id } ?? 0
                HStack(spacing: 10) {
                    Circle()
                        .fill(OfflineSeatColour.of(index))
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                    TextField("Player \(index + 1)", text: $name.text)
                        .font(SR.Text.body())
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .accessibilityIdentifier("car-race-driver-\(index)")
                    if names.count > 2 {
                        Button {
                            let gone = name.id
                            names.removeAll { $0.id == gone }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(SR.inkMuted)
                                .frame(width: SR.tapTarget, height: SR.tapTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(name.text.isEmpty ? "Player \(index + 1)" : name.text)")
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .frame(minHeight: SR.tapTarget)
                .srGlassCard(.paper, radius: SR.Glass.innerRadius)
            }
            if names.count < 4 {
                Button {
                    names.append(CarRaceName())
                } label: {
                    SRButtonLabel(title: "Add a driver", icon: "plus")
                }
                .srButton(.regular)
                .accessibilityIdentifier("car-race-add-driver")
            }
            Text("Each driver takes the phone in turn and races the ghosts of the drivers before. Fastest time wins.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var steering: some View {
        if tiltAvailable {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Steering")
                Toggle(isOn: $steerByTilt) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tilt to steer")
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                        Text(steerByTilt ? "Hold the phone like a wheel. Off: arrows on screen." : "Arrows on screen steer.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(SR.accent)
                .padding(SR.cardPadding)
                .srGlassCard(.paper)
                .accessibilityIdentifier("car-race-tilt")
            }
        }
    }

    private var nearby: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Race nearby")
            Text("One phone hosts in Play nearby and picks Car Race; everyone else joins. The track is drawn for you, three laps, and every phone drives its own car — the others appear as ghosts, so a wobbly link can't crash anyone.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SRHaptic.tap()
                router.push(OfflineGamesRef(), on: .games)
            } label: {
                SRButtonLabel(title: "Open Play nearby", icon: "dot.radiowaves.left.and.right", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("car-race-nearby")
        }
    }

    private func choice(title: String, line: String, icon: String, selected: Bool, id: String,
                        action: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            SRCard(accented: selected, interactive: true) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selected ? SR.accent : SR.inkMuted)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                        Text(line)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? SR.accent : SR.inkGhost)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
        .accessibilityIdentifier(id)
    }
}

/// A session under way: whose turn, the race, each finish, the table.
struct CarRaceSessionView: View {
    @ObservedObject var session: CarRaceSession
    let close: () -> Void

    var body: some View {
        switch session.stage {
        case .ready(let index):
            card { readyCard(index) }
        case .racing(let index):
            if let driver = session.driver {
                CarRaceView(driver: driver, seat: session.mode == .passAndPlay ? index : 0,
                            gapRival: session.mode == .timeTrial ? driver.rivals.first : nil) {
                    session.retire()
                }
            }
        case .finished(let index):
            card { finishedCard(index) }
        case .table:
            card { tableCard }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                content()
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
    }

    private func readyCard(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            if session.mode == .passAndPlay {
                SRPageHeader(kicker: "Driver \(index + 1) of \(session.names.count)",
                             title: "Pass the phone to \(session.names[index])",
                             strap: index == 0 ? "\(session.track.name), \(session.laps) lap\(session.laps == 1 ? "" : "s")." : "You're racing the ghosts of the drivers before you.")
            } else {
                SRPageHeader(kicker: "Time trial · \(session.track.name)",
                             title: session.best.map { "Beat \(CarRaceFormat.time($0.time ?? 0))" } ?? "Set a time",
                             strap: session.best == nil ? "Your run becomes the ghost to beat next time." : "Your best run is on the track with you, as a ghost.")
            }
            Text(session.useTilt ? "Tilt to steer. Hold Brake for the bends — brake hard into one to drift." :
                    "Hold the arrows to steer and Brake for the bends — brake hard into one to drift.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    session.go()
                } label: {
                    SRButtonLabel(title: "Start", icon: "flag.checkered", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("car-race-go")
                Button { close() } label: {
                    SRButtonLabel(title: "Back", fill: true)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("car-race-back")
            }
        }
    }

    private func finishedCard(_ index: Int) -> some View {
        let entry = session.entries.last
        let last = index + 1 >= session.names.count
        return VStack(alignment: .leading, spacing: SR.sectionGap) {
            SRPageHeader(kicker: session.newBest ? "New best on \(session.track.name)" : session.names[index],
                         title: entry?.time.map { CarRaceFormat.time($0) } ?? "Retired",
                         strap: entry?.bestLap.map { "Best lap \(CarRaceFormat.time($0))." })
                .accessibilityIdentifier("car-race-finish")
            if let best = session.book.carBest[session.track.id] {
                Text("Best on this track: \(CarRaceFormat.time(best)).")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            HStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    session.next()
                } label: {
                    SRButtonLabel(title: session.mode == .timeTrial ? "Race again" : last ? "Results" : "Next driver",
                                  icon: "arrow.right", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("car-race-next")
                Button { close() } label: {
                    SRButtonLabel(title: "Done", fill: true)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("car-race-done")
            }
        }
    }

    private var tableCard: some View {
        let ranked = session.ranked
        return VStack(alignment: .leading, spacing: SR.sectionGap) {
            SRPageHeader(kicker: "\(session.track.name) · \(session.laps) lap\(session.laps == 1 ? "" : "s")",
                         title: ranked.first?.time != nil ? "\(ranked.first?.name ?? "") wins" : "Nobody finished")
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { place, entry in
                    if place > 0 { Divider().overlay(SR.divider) }
                    HStack(spacing: 12) {
                        Text("\(place + 1)")
                            .font(SR.Text.display(22))
                            .foregroundStyle(place == 0 ? SR.accent : SR.inkGhost)
                            .frame(width: 28, alignment: .leading)
                        Circle()
                            .fill(OfflineSeatColour.of(Int(entry.id) ?? 0))
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(SR.Text.title())
                                .foregroundStyle(SR.ink)
                                .lineLimit(1)
                            if let lap = entry.bestLap {
                                Text("Best lap \(CarRaceFormat.time(lap))")
                                    .font(SR.Text.mono())
                                    .foregroundStyle(SR.inkMuted)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(entry.time.map { CarRaceFormat.time($0) } ?? "Retired")
                            .font(SR.Text.display(20))
                            .foregroundStyle(SR.ink)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
            .accessibilityIdentifier("car-race-table")
            Button { close() } label: {
                SRButtonLabel(title: "Done", icon: "checkmark", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("car-race-done")
        }
    }
}

/// The race itself: the track, the lights, the lap and clock, and the controls.
/// Shared by every mode; a nearby race hands it a driver steered by the room.
struct CarRaceView: View {
    @ObservedObject var driver: CarRaceDriver
    var seat = 0
    /// The ghost to show a gap to (a time trial's best).
    var gapRival: CarRival? = nil
    /// Retire from the race; nil hides the button.
    var retire: (() -> Void)? = nil

    var body: some View {
        ZStack {
            CarRaceTrackView(driver: driver, seat: seat)
                .ignoresSafeArea(edges: .bottom)
            VStack(spacing: 10) {
                instruments
                Spacer(minLength: 0)
                if driver.phase == .grid { lights }
                Spacer(minLength: 0)
                CarRaceControls(driver: driver)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black)
        .onAppear { driver.start() }
        .onDisappear { driver.stop() }
        .accessibilityIdentifier("car-race-view")
    }

    private var instruments: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LAP")
                    .font(SR.Text.label(11))
                    .foregroundStyle(SR.inkMuted)
                Text("\(driver.counter.lap)/\(driver.laps)")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("TIME")
                    .font(SR.Text.label(11))
                    .foregroundStyle(SR.inkMuted)
                Text(CarRaceFormat.time(driver.counter.finishTime ?? max(0, driver.raceTime)))
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .monospacedDigit()
            }
            if let rival = gapRival, let gap = driver.gap(to: rival) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BEST")
                        .font(SR.Text.label(11))
                        .foregroundStyle(SR.inkMuted)
                    Text(Self.gapText(gap))
                        .font(SR.Text.title())
                        .foregroundStyle(gap > 0 ? SR.error : SR.good)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Self.gapLabel(gap))
            } else if !driver.rivals.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLACE")
                        .font(SR.Text.label(11))
                        .foregroundStyle(SR.inkMuted)
                    Text("\(driver.place)/\(driver.rivals.count + 1)")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            if let retire, driver.phase != .finished {
                Button {
                    SRHaptic.tap()
                    retire()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: SR.tapTarget, height: SR.tapTarget)
                }
                .srButton(.regular)
                .accessibilityLabel("Retire from the race")
                .accessibilityIdentifier("car-race-retire")
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 8)
        .srGlassCard(.paper)
        // The track map sits in the top-right corner, beside the instruments.
        .padding(.trailing, 92)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("car-race-instruments")
    }

    /// "+1.4" behind the best, "−0.6" ahead.
    private static func gapText(_ gap: Double) -> String {
        (gap > 0 ? "+" : "−") + String(format: "%.1f", abs(gap))
    }

    private static func gapLabel(_ gap: Double) -> String {
        let seconds = String(format: "%.1f", abs(gap))
        return gap > 0 ? "\(seconds) seconds behind your best" : "\(seconds) seconds ahead of your best"
    }

    /// The start lights: a number counting down, then GO.
    private var lights: some View {
        let left = Int(driver.countdown.rounded(.up))
        return Text(left > 0 ? "\(left)" : "GO")
            .font(SR.Text.hero(72))
            .foregroundStyle(left > 0 ? SR.error : SR.good)
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .srGlassCard(.paper)
            .accessibilityLabel(left > 0 ? "Starting in \(left)" : "Go")
            .accessibilityIdentifier("car-race-lights")
    }
}

/// Brake, and the steering arrows when tilt does not steer.
struct CarRaceControls: View {
    @ObservedObject var driver: CarRaceDriver

    var body: some View {
        HStack(spacing: 12) {
            if !driver.useTilt && !driver.scripted {
                LanderHoldButton(icon: "arrow.left", label: "Steer left") { driver.steerHeld = $0 ? -1 : 0 }
                    .accessibilityIdentifier("car-race-left")
            }
            Spacer(minLength: 0)
            if driver.scripted {
                Text("Autopilot")
                    .font(SR.Text.mono())
                    .foregroundStyle(Color.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
            } else {
                CarRaceBrake { driver.brakeHeld = $0 }
            }
            Spacer(minLength: 0)
            if !driver.useTilt && !driver.scripted {
                LanderHoldButton(icon: "arrow.right", label: "Steer right") { driver.steerHeld = $0 ? 1 : 0 }
                    .accessibilityIdentifier("car-race-right")
            } else if driver.useTilt {
                Button {
                    SRHaptic.tap()
                    driver.tilt.recentre()
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: SR.tapTarget, height: SR.tapTarget)
                }
                .srButton(.regular)
                .accessibilityLabel("Make the way I'm holding the phone straight ahead")
                .accessibilityIdentifier("car-race-recentre")
            }
        }
    }
}

/// The brake pedal: on while a finger holds it.
struct CarRaceBrake: View {
    let changed: (Bool) -> Void
    @State private var held = false

    var body: some View {
        Text("BRAKE")
            .font(SR.Text.label(14))
            .tracking(SR.inkKickerTracking)
            .foregroundStyle(held ? Color.white : SR.ink)
            .frame(width: 120, height: 64)
            .background {
                if held { RoundedRectangle(cornerRadius: 32, style: .continuous).fill(SR.error) }
            }
            .srGlassCard(.paper, radius: 32)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !held { held = true; changed(true) }
                    }
                    .onEnded { _ in
                        held = false
                        changed(false)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Brake")
            .accessibilityHint("Hold to slow down")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("car-race-brake")
    }
}

import SwiftUI

/// How a race on one phone is run.
enum CarRaceMode: String, CaseIterable, Identifiable {
    /// Alone, against the ghost of your best run on the track.
    case timeTrial
    /// Two to four drivers take turns on one phone; each races the ghosts of those before.
    case passAndPlay
    /// Two to four drivers at once on one phone, each with a part of the screen.
    case splitScreen
    /// Phone to phone over "Play nearby".
    case nearby

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeTrial: return "Time trial"
        case .passAndPlay: return "Pass the phone"
        case .splitScreen: return "Split screen"
        case .nearby: return "Race nearby"
        }
    }

    var line: String {
        switch self {
        case .timeTrial: return "Just you, against the ghost of your best run."
        case .passAndPlay: return "Two to four of you take turns on this phone, each racing the ghosts of those before."
        case .splitScreen: return "Two to four of you at once on this phone, each with your own part of the screen. Cars bump."
        case .nearby: return "Two to four phones in the same room, over Bluetooth or a hotspot. No internet needed."
        }
    }

    var icon: String {
        switch self {
        case .timeTrial: return "stopwatch.fill"
        case .passAndPlay: return "person.2.fill"
        case .splitScreen: return "rectangle.split.1x2.fill"
        case .nearby: return "dot.radiowaves.left.and.right"
        }
    }
}

/// A race on one phone: a time trial, drivers taking turns, or everyone at
/// once on a split screen. It hands each driver a `CarRaceDriver` with the
/// right ghosts (or the split screen a `CarSplitDriver`), keeps the results
/// and the bests, and says what comes next.
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

    /// How long the race stays on screen after the line, for the flag and
    /// the confetti, before the results card.
    static let celebration: Double = 1.8

    let mode: CarRaceMode
    let track: CarTrack
    let laps: Int
    let names: [String]
    let useTilt: Bool
    /// Split screen with the phone flat between players sitting opposite:
    /// the far players' parts are turned round.
    let facing: Bool
    @Published private(set) var stage: Stage = .ready(0)
    @Published private(set) var driver: CarRaceDriver?
    @Published private(set) var split: CarSplitDriver?
    @Published private(set) var entries: [CarRaceEntry] = []
    @Published private(set) var book: PhysicsScoreBook
    /// The time trial's ghost: the best run on this track, replaced the
    /// moment a run here beats it.
    private(set) var best: CarGhost?
    @Published private(set) var newBest = false
    /// The last finish against the best on this track before it: negative
    /// is faster. Nil with no best to beat (or a retirement).
    @Published private(set) var lastDelta: Double?
    /// The last finisher's lap times, in order.
    @Published private(set) var lastLapTimes: [Double] = []
    /// Pass the phone: each finished driver's run, by driver, raced as a
    /// ghost by the drivers after. Keyed by driver so a ghost keeps its
    /// driver's colour when someone before them retired.
    private var ghosts: [Int: CarGhost] = [:]
    private let store = PhysicsScoreStore()

    init(mode: CarRaceMode, track: CarTrack, laps: Int, names: [String], useTilt: Bool, facing: Bool = true) {
        self.mode = mode
        self.track = track
        self.laps = laps
        self.names = names.isEmpty ? ["You"] : names
        self.useTilt = useTilt && mode != .splitScreen
        self.facing = facing
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

    /// Lights out in three seconds for the driver whose turn it is (on a
    /// split screen, for everyone).
    func go() {
        guard case .ready(let index) = stage else { return }
        lastDelta = nil
        lastLapTimes = []
        if mode == .splitScreen {
            let split = CarSplitDriver(track: track, laps: laps, names: names, startsAt: OfflineUptime.now() + 3)
            split.onOver = { [weak self] race in self?.finishSplit(race) }
            self.split = split
            entries = []
            newBest = false
            stage = .racing(index)
            split.start()
            return
        }
        let driver = CarRaceDriver(track: track, laps: laps, slot: 0, name: names[index], useTilt: useTilt,
                                   startsAt: OfflineUptime.now() + 3)
        var rivals: [CarRival] = []
        if mode == .timeTrial, let best {
            rivals.append(CarRival(id: "best", name: "Best", seat: 1, ghost: best))
        }
        for (seat, ghost) in ghosts.sorted(by: { $0.key < $1.key }) {
            rivals.append(CarRival(id: "ghost-\(seat)", name: ghost.name, seat: seat, ghost: ghost))
        }
        driver.rivals = rivals
        driver.onFinish = { [weak self] laps, ghost in self?.finish(index, laps: laps, ghost: ghost) }
        self.driver = driver
        newBest = false
        stage = .racing(index)
        driver.start()
    }

    /// Give up the run: no time, and on to the next driver.
    func retire() {
        // Over the line already (the race menu left open at the finish): the
        // time stands, and the card follows the flag as usual.
        guard case .racing(let index) = stage, driver?.phase != .finished else { return }
        driver?.stop()
        entries.append(CarRaceEntry(id: "\(index)", name: names[index], time: nil, bestLap: driver?.counter.bestLap))
        lastDelta = nil
        lastLapTimes = []
        stage = .finished(index)
    }

    /// The same driver back on the grid, the lights counting down again.
    /// Nothing from the abandoned run is kept.
    func restart() {
        guard case .racing(let index) = stage, mode != .splitScreen, driver?.phase != .finished else { return }
        driver?.stop()
        driver = nil
        stage = .ready(index)
        go()
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
                // Another go, against the one best ghost (perhaps just set):
                // never the earlier goes as well.
                entries = []
                newBest = false
            }
        }
    }

    func stop() {
        driver?.stop()
        split?.stop()
    }

    /// Stop a split-screen race for everyone; it goes to the table.
    func endSplit() { split?.end() }

    /// The same drivers on a split screen again.
    func rematch() {
        guard mode == .splitScreen, stage == .table else { return }
        split?.stop()
        split = nil
        entries = []
        newBest = false
        stage = .ready(0)
    }

    var ranked: [CarRaceEntry] { CarRaceEntry.ranked(entries) }

    private func finish(_ index: Int, laps: CarLapCounter, ghost: CarGhost) {
        guard let time = laps.finishTime else { return }
        entries.append(CarRaceEntry(id: "\(index)", name: names[index], time: time, bestLap: laps.bestLap))
        var mine = ghost
        mine.name = names[index]
        // The pass-the-phone drivers after this one race this run's ghost. A
        // time trial races only its one best (`best`), never every earlier go.
        if mode == .passAndPlay { ghosts[index] = mine }
        var book = self.book
        let before = book.carBest[track.id]
        let isBest = book.recordRace(track: track.id, time: time, bestLap: laps.bestLap)
        store.save(book)
        if isBest {
            store.saveGhost(mine)
            if mode == .timeTrial { best = mine }
        }
        self.book = book
        newBest = isBest
        lastDelta = before.map { time - $0 }
        lastLapTimes = laps.lapTimes
        // The flag and the confetti on the track first, then the card.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(CarRaceSession.celebration * 1_000_000_000))
            guard let self, case .racing(let now) = self.stage, now == index else { return }
            self.stage = .finished(index)
        }
    }

    /// A split-screen race is over: the table, and each finisher's time in
    /// the book, fastest first, so the best run's ghost is the one kept.
    private func finishSplit(_ race: CarSplitRace) {
        entries = race.entries
        var book = self.book
        var isBest = false
        for racer in race.order {
            guard let time = racer.laps.finishTime else { continue }
            if book.recordRace(track: track.id, time: time, bestLap: racer.laps.bestLap) {
                isBest = true
                var ghost = racer.ghost
                ghost.time = time
                store.saveGhost(ghost)
            }
        }
        store.save(book)
        self.book = book
        newBest = isBest
        // Everyone home: a moment for the last one's flag. Stopped early: straight to the table.
        let everyoneHome = race.racers.allSatisfy { $0.laps.finished }
        guard everyoneHome else {
            stage = .table
            return
        }
        let racing = stage
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(CarRaceSession.celebration * 1_000_000_000))
            guard let self, self.stage == racing else { return }
            self.stage = .table
        }
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
    @AppStorage("physics.car.facing") private var sitOpposite = true
    @State private var session: CarRaceSession?
    @State private var book = PhysicsScoreStore().load()
    @Environment(\.dynamicTypeSize) private var typeSize
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
                    tracks
                    lapsChoice

                    if mode == .passAndPlay || mode == .splitScreen { drivers }

                    if mode == .splitScreen { seating } else { steering }

                    Button {
                        SRHaptic.tap()
                        let who = mode == .timeTrial ? ["You"] : cleanNames
                        session = CarRaceSession(mode: mode, track: track, laps: laps, names: who,
                                                 useTilt: steerByTilt && tiltAvailable, facing: sitOpposite)
                    } label: {
                        SRButtonLabel(title: "To the grid", icon: "flag.checkered", fill: true)
                            .frame(minHeight: 44)
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

    /// Every track as a card with its lap drawn, two to a row (one at the
    /// largest text sizes), and the chosen one's description under them.
    private var tracks: some View {
        let columns: [GridItem] = typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: SR.cardGap), GridItem(.flexible(), spacing: SR.cardGap)]
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Track", trailing: "\(CarTrack.all.count) circuits")
            LazyVGrid(columns: columns, spacing: SR.cardGap) {
                ForEach(CarTrack.all) { option in
                    CarRaceTrackCard(track: option, selected: trackId == option.id, best: book.carBest[option.id]) {
                        SRHaptic.select()
                        trackId = option.id
                    }
                    .accessibilityIdentifier("car-race-track-\(option.id)")
                }
            }
            Text(trackLine(track))
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(nil, value: trackId)
        }
    }

    /// One, three or five laps, as three big buttons.
    private var lapsChoice: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Laps")
            HStack(spacing: 10) {
                ForEach([1, 3, 5], id: \.self) { count in
                    CarRaceChip(title: "\(count)", caption: count == 1 ? "lap" : "laps", selected: laps == count) {
                        SRHaptic.select()
                        laps = count
                    }
                    .accessibilityLabel("\(count) lap\(count == 1 ? "" : "s")")
                    .accessibilityIdentifier("car-race-laps-\(count)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("car-race-laps")
        }
    }

    private func trackLine(_ option: CarTrack) -> String {
        guard let best = book.carBest[option.id] else { return "\(option.name): \(option.line)" }
        return "\(option.name): \(option.line) Your best: \(CarRaceFormat.time(best))."
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
                    Image(systemName: "car.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(OfflineSeatColour.of(index)))
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
                                .font(.system(size: 20))
                                .foregroundStyle(SR.inkMuted)
                                .frame(width: SR.tapTarget, height: SR.tapTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(name.text.isEmpty ? "Player \(index + 1)" : name.text)")
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .frame(minHeight: 56)
                .srGlassCard(.paper, radius: SR.Glass.innerRadius)
            }
            if names.count < 4 {
                Button {
                    names.append(CarRaceName())
                } label: {
                    SRButtonLabel(title: "Add a driver", icon: "plus")
                        .frame(minHeight: 36)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("car-race-add-driver")
            }
            Text(mode == .splitScreen
                 ? "Everyone races at once, each in their own part of the screen. Four is a squeeze on a phone."
                 : "Each driver takes the phone in turn and races the ghosts of the drivers before. Fastest time wins.")
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

    /// Split screen: steering is by touch (tilt can't steer two cars), so the
    /// only choice is how everyone sits.
    private var seating: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Seating")
            Toggle(isOn: $sitOpposite) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sit opposite")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text(sitOpposite ? "The phone lies flat between you; the far side's screen is turned to face them." :
                            "Everyone looks at the phone from the same side.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(SR.accent)
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityIdentifier("car-race-facing")
            Text("Hold the left or right of your part of the screen to steer, both together to brake, and the middle to boost.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nearby: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Race nearby")
            HStack(spacing: 10) {
                ForEach(CarTrack.nearby) { option in
                    CarRaceTrackMap(track: option, detailed: false)
                        .frame(height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            Text("One phone hosts in Play nearby and picks Car Race; everyone else joins. The track is drawn for you, three laps, and every phone drives its own car. Cars bump, but each phone only ever moves its own, so a wobbly link can't throw anyone off.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SRHaptic.tap()
                router.push(OfflineGamesRef(), on: .games)
            } label: {
                SRButtonLabel(title: "Open Play nearby", icon: "dot.radiowaves.left.and.right", fill: true)
                    .frame(minHeight: 44)
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
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(selected ? SR.paper : SR.inkMuted)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(selected ? SR.accentDeep : SR.ink.opacity(0.07)))
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
                        .font(.system(size: 22))
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

/// A track to pick: its lap drawn in its own scenery, its name, the kind of
/// place, and your best there.
struct CarRaceTrackCard: View {
    let track: CarTrack
    let selected: Bool
    let best: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                map
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name)
                        .font(SR.Text.title(15))
                        .foregroundStyle(SR.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(track.scenery.carRaceTitle, systemImage: track.scenery.carRaceSymbol)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                    Text(best.map { "Best \(CarRaceFormat.time($0))" } ?? "No time yet")
                        .font(SR.Text.mono())
                        .foregroundStyle(best == nil ? SR.inkGhost : SR.good)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper, radius: 22, interactive: true)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selected ? SR.accent : Color.clear, lineWidth: 3)
            }
            .scaleEffect(selected ? 1 : 0.98)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(selected ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
    }

    private var spoken: String {
        var words = "\(track.name), \(track.scenery.carRaceTitle)"
        if let best { words += ", your best \(CarRaceFormat.time(best))" }
        return words
    }

    private var map: some View {
        CarRaceTrackMap(track: track)
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.white, SR.accent)
                        .padding(6)
                }
            }
    }
}

/// A big choice button: a figure and a word under it, lit when chosen.
struct CarRaceChip: View {
    let title: String
    let caption: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title)
                    .font(SR.Text.display(24))
                    .monospacedDigit()
                Text(caption.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.2)
            }
            .foregroundStyle(selected ? SR.paper : SR.ink)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? SR.accentDeep : SR.ink.opacity(0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(SRPressStyle())
        .accessibilityAddTraits(selected ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
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
            if session.mode == .splitScreen, let split = session.split {
                CarSplitView(driver: split, facing: session.facing) { session.endSplit() }
            } else if let driver = session.driver {
                CarRaceView(driver: driver, seat: session.mode == .passAndPlay ? index : 0,
                            gapRival: session.mode == .timeTrial ? driver.rivals.first : nil,
                            retire: { session.retire() },
                            restart: { session.restart() },
                            newBest: session.newBest,
                            pausable: true)
                    .id(ObjectIdentifier(driver))
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

    private var lapsWord: String { "\(session.laps) lap\(session.laps == 1 ? "" : "s")" }

    private func readyCard(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            CarRaceGridPreview(track: session.track, laps: session.laps, best: session.book.carBest[session.track.id],
                               colours: readyColours(index))
            readyHeader(index)
            CarRaceHowTo(mode: session.mode, useTilt: session.useTilt)
            VStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    session.go()
                } label: {
                    SRButtonLabel(title: "Start", icon: "flag.checkered", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("car-race-go")
                Button { close() } label: {
                    SRButtonLabel(title: "Back", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("car-race-back")
            }
        }
    }

    /// The cars on the grid in the preview: everyone on a split screen, the
    /// driver up next (and the ghosts they race) otherwise.
    private func readyColours(_ index: Int) -> [Color] {
        switch session.mode {
        case .splitScreen: return session.names.indices.map { OfflineSeatColour.of($0) }
        case .passAndPlay: return [OfflineSeatColour.of(index)]
        default: return [OfflineSeatColour.of(0)]
        }
    }

    @ViewBuilder
    private func readyHeader(_ index: Int) -> some View {
        if session.mode == .splitScreen {
            SRPageHeader(kicker: "Split screen · \(session.track.name)",
                         title: "\(session.names.count) cars, one phone",
                         strap: "\(lapsWord). First home wins; the rest have \(Int(CarSplitRace.finishGrace)) seconds.")
        } else if session.mode == .passAndPlay {
            SRPageHeader(kicker: "Driver \(index + 1) of \(session.names.count)",
                         title: "Pass the phone to \(session.names[index])",
                         strap: index == 0 ? "\(session.track.name), \(lapsWord)." : "You're racing the ghosts of the drivers before you.")
        } else {
            SRPageHeader(kicker: "Time trial · \(session.track.name)",
                         title: session.best.map { "Beat \(CarRaceFormat.time($0.time ?? 0))" } ?? "Set a time",
                         strap: session.best == nil ? "Your run becomes the ghost to beat next time." : "Your best run is on the track with you, as a ghost.")
        }
    }

    private func finishedCard(_ index: Int) -> some View {
        let entry = session.entries.last
        let last = index + 1 >= session.names.count
        return VStack(alignment: .leading, spacing: SR.sectionGap) {
            CarRaceResultBadge(finished: entry?.time != nil, newBest: session.newBest, colour: OfflineSeatColour.of(
                session.mode == .passAndPlay ? index : 0))
            SRPageHeader(kicker: session.newBest ? "New best on \(session.track.name)" : session.names[index],
                         title: entry?.time.map { CarRaceFormat.time($0) } ?? "Retired",
                         strap: entry?.bestLap.map { "Best lap \(CarRaceFormat.time($0))." })
                .accessibilityIdentifier("car-race-finish")
            if let delta = session.lastDelta {
                CarRaceDeltaLine(delta: delta)
            }
            if !session.lastLapTimes.isEmpty {
                CarRaceLapTable(times: session.lastLapTimes)
            }
            if let best = session.book.carBest[session.track.id] {
                Text("Best on this track: \(CarRaceFormat.time(best)).")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            VStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    session.next()
                } label: {
                    SRButtonLabel(title: session.mode == .timeTrial ? "Race again" : last ? "Results" : "Next driver",
                                  icon: "arrow.right", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("car-race-next")
                Button { close() } label: {
                    SRButtonLabel(title: "Done", fill: true)
                        .frame(minHeight: 44)
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
            SRPageHeader(kicker: "\(session.track.name) · \(lapsWord)",
                         title: ranked.first?.time != nil ? "\(ranked.first?.name ?? "") wins" : "Nobody finished")
            if ranked.count > 1, ranked.first?.time != nil {
                CarRacePodium(ranked: ranked)
            }
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { place, entry in
                    if place > 0 { Divider().overlay(SR.divider) }
                    CarRaceTableRow(place: place, entry: entry)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
            .accessibilityIdentifier("car-race-table")
            if session.newBest {
                Label("A new best on \(session.track.name).", systemImage: "trophy.fill")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.good)
            }
            VStack(spacing: 10) {
                if session.mode == .splitScreen {
                    Button {
                        SRHaptic.tap()
                        session.rematch()
                    } label: {
                        SRButtonLabel(title: "Race again", icon: "arrow.clockwise", fill: true)
                            .frame(minHeight: 44)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .accessibilityIdentifier("car-race-rematch")
                }
                Button { close() } label: {
                    SRButtonLabel(title: "Done", icon: "checkmark", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(session.mode == .splitScreen ? .regular : .prominent)
                .controlSize(.large)
                .accessibilityIdentifier("car-race-done")
            }
        }
    }
}

/// The ready card's picture: the whole lap in its scenery, with the laps,
/// the kind of place and the best time on it, and a car for each driver.
struct CarRaceGridPreview: View {
    let track: CarTrack
    let laps: Int
    let best: Double?
    let colours: [Color]

    var body: some View {
        CarRaceTrackMap(track: track)
            .frame(height: 176)
            .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
            .overlay(alignment: .bottomLeading) { chips }
            .overlay(alignment: .topTrailing) { cars }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var words = "\(track.name), \(track.scenery.carRaceTitle), \(laps) lap\(laps == 1 ? "" : "s")"
        if let best { words += ", best \(CarRaceFormat.time(best))" }
        return words
    }

    private var chips: some View {
        HStack(spacing: 6) {
            chip(icon: "flag.checkered", text: "\(laps) lap\(laps == 1 ? "" : "s")")
            chip(icon: track.scenery.carRaceSymbol, text: track.scenery.carRaceTitle)
            if let best { chip(icon: "stopwatch.fill", text: CarRaceFormat.time(best)) }
        }
        .padding(10)
    }

    private var cars: some View {
        HStack(spacing: -6) {
            ForEach(Array(colours.enumerated()), id: \.offset) { _, colour in
                Image(systemName: "car.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(colour))
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
        }
        .padding(10)
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(SR.Text.label()).lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }
}

/// How to drive in this mode, one icon and line per control.
struct CarRaceHowTo: View {
    let mode: CarRaceMode
    let useTilt: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if mode == .splitScreen {
                row("hand.point.up.left.fill", "Hold the left or right of your part of the screen to steer.")
                row("exclamationmark.octagon.fill", "Hold both together to brake — brake hard into a bend to drift.")
                row("bolt.fill", "Hold the middle to boost. Cars bump — and bump back.")
            } else {
                row(useTilt ? "iphone.landscape" : "arrow.left.arrow.right",
                    useTilt ? "Tilt to steer, like holding a wheel." : "Hold the arrows to steer.")
                row("exclamationmark.octagon.fill", "Hold Brake for the bends — brake hard into one to drift.")
                row("bolt.fill", "Hold Boost down the straights; drifting fills it faster.")
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(SR.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(SR.accent.opacity(0.14)))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The badge over a finish: a chequered flag, a trophy for a new best, or
/// a flag down for a retirement.
struct CarRaceResultBadge: View {
    let finished: Bool
    let newBest: Bool
    let colour: Color
    @State private var popped = false

    var body: some View {
        Image(systemName: newBest ? "trophy.fill" : finished ? "flag.checkered" : "flag.slash.fill")
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 76, height: 76)
            .background(Circle().fill(newBest ? Color(red: 0.95, green: 0.68, blue: 0.12) : finished ? colour : SR.inkMuted))
            .scaleEffect(popped ? 1 : 0.6)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { popped = true }
                if newBest { SRHaptic.ok() }
            }
            .accessibilityHidden(true)
    }
}

/// How the finish compared with the best before it.
struct CarRaceDeltaLine: View {
    let delta: Double

    var body: some View {
        let faster = delta < 0
        let icon: String = faster ? "arrow.down.right.circle.fill" : "arrow.up.right.circle.fill"
        Label(words, systemImage: icon)
            .font(SR.Text.title(15))
            .foregroundStyle(faster ? SR.good : SR.inkSecondary)
    }

    private var words: String {
        let seconds = String(format: "%.2f", abs(delta))
        if delta < 0 { return "\(seconds) s faster than your best" }
        if delta == 0 { return "Level with your best" }
        return "\(seconds) s off your best"
    }
}

/// Each lap's time, the fastest marked.
struct CarRaceLapTable: View {
    let times: [Double]

    var body: some View {
        let fastest = times.min()
        VStack(spacing: 0) {
            ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack {
                    Text("Lap \(index + 1)")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                    Spacer(minLength: 8)
                    if time == fastest && times.count > 1 {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SR.good)
                            .accessibilityLabel("Fastest lap")
                    }
                    Text(CarRaceFormat.time(time))
                        .font(SR.Text.title(15))
                        .foregroundStyle(time == fastest && times.count > 1 ? SR.good : SR.ink)
                        .monospacedDigit()
                }
                .frame(minHeight: 36)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 4)
        .srGlassCard(.paper)
    }
}

/// The top three on blocks of their own height, in their colours.
struct CarRacePodium: View {
    let ranked: [CarRaceEntry]
    @State private var risen = false

    var body: some View {
        let top = Array(ranked.prefix(3).enumerated())
        // Second, first, third: the winner in the middle, highest.
        let order: [(offset: Int, element: CarRaceEntry)] = top.count == 3 ? [top[1], top[0], top[2]]
            : top.count == 2 ? [top[1], top[0]] : top
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(order, id: \.element.id) { place, entry in
                block(place: place, entry: entry)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.1)) { risen = true }
        }
        .accessibilityElement(children: .combine)
    }

    private func block(place: Int, entry: CarRaceEntry) -> some View {
        let heights: [CGFloat] = [118, 84, 62]
        let colour = OfflineSeatColour.of(Int(entry.id) ?? 0)
        return VStack(spacing: 6) {
            Image(systemName: place == 0 ? "crown.fill" : "car.fill")
                .font(.system(size: place == 0 ? 22 : 16, weight: .bold))
                .foregroundStyle(place == 0 ? Color(red: 0.95, green: 0.68, blue: 0.12) : colour)
                .accessibilityHidden(true)
            Text(entry.name)
                .font(SR.Text.title(14))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colour)
                Text("\(place + 1)")
                    .font(SR.Text.display(26))
                    .foregroundStyle(Color.white)
                    .padding(.top, 8)
            }
            .frame(height: risen ? heights[min(place, 2)] : 12)
        }
        .frame(maxWidth: 110)
    }
}

/// One row of the results table.
struct CarRaceTableRow: View {
    let place: Int
    let entry: CarRaceEntry

    var body: some View {
        HStack(spacing: 12) {
            Text("\(place + 1)")
                .font(SR.Text.display(22))
                .foregroundStyle(place == 0 ? SR.accent : SR.inkGhost)
                .frame(width: 28, alignment: .leading)
            Circle()
                .fill(OfflineSeatColour.of(Int(entry.id) ?? 0))
                .frame(width: 14, height: 14)
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

/// The race itself: the track, the lights, the lap and clock, and the controls.
/// Shared by every mode; a nearby race hands it a driver steered by the room.
struct CarRaceView: View {
    @ObservedObject var driver: CarRaceDriver
    var seat = 0
    /// The ghost to show a gap to (a time trial's best).
    var gapRival: CarRival? = nil
    /// Retire from the race; nil hides the race menu.
    var retire: (() -> Void)? = nil
    /// Back to the grid for another go; nil leaves it out of the menu.
    var restart: (() -> Void)? = nil
    /// The finish just set a new best: the flag says so.
    var newBest = false
    /// A race on this phone alone: the menu (and leaving the app) pauses it.
    var pausable = false
    @State private var menu = false
    /// Restart or Retire was picked: the closing menu must not resume.
    @State private var leaving = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            CarRaceTrackView(driver: driver, seat: seat)
                .ignoresSafeArea(edges: .bottom)
            VStack(spacing: 8) {
                instruments
                CarRaceSpeedChip(speed: driver.car.speed, drifting: driver.car.drifting, boosting: driver.car.boosting)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                middle
                Spacer(minLength: 0)
                CarRaceControls(driver: driver)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // Under the lap map (92 points, 12 in from the corner), centred on it.
            .overlay(alignment: .topTrailing) {
                menuButton
                    .padding(.top, 114)
                    .padding(.trailing, 30)
            }
        }
        .background(Color.black)
        .onAppear { driver.start() }
        .onDisappear { driver.stop() }
        .onChange(of: menu) { _, open in
            guard pausable else { return }
            if open {
                driver.pause()
            } else if !leaving {
                driver.resume()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard pausable, phase != .active, driver.phase != .finished else { return }
            driver.pause()
            menu = true
        }
        .confirmationDialog(pausable ? "Paused" : "Race menu", isPresented: $menu, titleVisibility: .visible) {
            if let restart {
                Button("Restart from the grid") {
                    leaving = true
                    restart()
                }
            }
            if let retire {
                Button("Retire", role: .destructive) {
                    leaving = true
                    retire()
                }
            }
            Button("Keep racing", role: .cancel) {}
        } message: {
            Text(pausable ? "The clock is stopped until you carry on." : "The clock keeps running while this is open.")
        }
        .accessibilityIdentifier("car-race-view")
    }

    private var instruments: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LAP")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkMuted)
                Text("\(driver.counter.lap)/\(driver.laps)")
                    .font(SR.Text.title(20))
                    .foregroundStyle(SR.ink)
                    .monospacedDigit()
                progress
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Lap \(driver.counter.lap) of \(driver.laps)")
            VStack(alignment: .leading, spacing: 3) {
                Text("TIME")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkMuted)
                Text(CarRaceFormat.time(driver.counter.finishTime ?? max(0, driver.raceTime)))
                    .font(SR.Text.title(20))
                    .foregroundStyle(SR.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let rival = gapRival, let gap = driver.gap(to: rival) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BEST")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                    Text(Self.gapText(gap))
                        .font(SR.Text.title(20))
                        .foregroundStyle(gap > 0 ? SR.error : SR.good)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Self.gapLabel(gap))
            } else if !driver.rivals.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PLACE")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                    Text("\(driver.place)/\(driver.rivals.count + 1)")
                        .font(SR.Text.title(20))
                        .foregroundStyle(driver.place == 1 ? SR.good : SR.ink)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 8)
        .srGlassCard(.paper)
        // The track map sits in the top-right corner, beside the instruments.
        .padding(.trailing, 92)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("car-race-instruments")
    }

    /// How much of the race is run, as a thin bar under the lap.
    private var progress: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(SR.ink.opacity(0.12))
            Capsule()
                .fill(SR.accent)
                .frame(width: 56 * CGFloat(driver.counter.progress))
        }
        .frame(width: 56, height: 5)
    }

    /// The race menu: restart or retire, under the lap map.
    @ViewBuilder
    private var menuButton: some View {
        HStack(spacing: 0) {
            if retire != nil || restart != nil, driver.phase != .finished {
                Button {
                    SRHaptic.tap()
                    menu = true
                } label: {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(SR.ink)
                        .frame(width: 56, height: 56)
                        .srGlassCard(.paper, radius: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(SRPressStyle())
                .accessibilityLabel("Race menu: restart or retire")
                .accessibilityIdentifier("car-race-retire")
            }
        }
    }

    /// The middle of the screen: the lights on the grid, a banner on each
    /// new lap, the flag at the finish.
    @ViewBuilder
    private var middle: some View {
        if driver.phase == .finished, let time = driver.counter.finishTime {
            if driver.raceTime - time < 4 {
                CarRaceFinishBanner(time: time, place: driver.rivals.isEmpty ? nil : driver.place, newBest: newBest, compact: false)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        } else if driver.phase == .grid || driver.raceTime < 1 {
            CarRaceStartLights(countdown: driver.countdown, sinceStart: driver.raceTime, compact: false)
                .accessibilityIdentifier("car-race-lights")
        } else if let banner = CarRaceLapBanner.words(laps: driver.counter, raceTime: driver.raceTime) {
            CarRaceLapBanner(text: banner, compact: false)
        }
    }

    /// "+1.4" behind the best, "−0.6" ahead.
    private static func gapText(_ gap: Double) -> String {
        (gap > 0 ? "+" : "−") + String(format: "%.1f", abs(gap))
    }

    private static func gapLabel(_ gap: Double) -> String {
        let seconds = String(format: "%.1f", abs(gap))
        return gap > 0 ? "\(seconds) seconds behind your best" : "\(seconds) seconds ahead of your best"
    }
}

/// The speed in km/h, lit orange while the tyres slide and the boost fills
/// faster, flame-coloured while boosting.
struct CarRaceSpeedChip: View {
    let speed: Double
    let drifting: Bool
    let boosting: Bool

    var body: some View {
        let fill: Color = boosting ? CarRaceScene.flame : drifting ? Color(red: 0.95, green: 0.45, blue: 0.1) : Color.black.opacity(0.5)
        HStack(spacing: 6) {
            Image(systemName: boosting ? "bolt.fill" : drifting ? "tornado" : "speedometer")
                .font(.system(size: 13, weight: .bold))
            Text("\(Int((speed * 3.6).rounded()))")
                .font(SR.Text.title(17))
                .monospacedDigit()
            Text(unit)
                .font(SR.Text.label())
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(Capsule().fill(fill))
        .animation(.easeOut(duration: 0.15), value: drifting)
        .animation(.easeOut(duration: 0.15), value: boosting)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var unit: String {
        if boosting { return "BOOST" }
        return drifting ? "DRIFT" : "KM/H"
    }

    private var spoken: String {
        let kmh = Int((speed * 3.6).rounded())
        if boosting { return "\(kmh) kilometres an hour, boosting" }
        if drifting { return "\(kmh) kilometres an hour, drifting" }
        return "\(kmh) kilometres an hour"
    }
}

/// The start gantry: three red lamps light one a second, then all three go
/// green with GO. The number under them counts down for anyone who prefers it.
struct CarRaceStartLights: View {
    /// Seconds until the lights go out.
    let countdown: Double
    /// Seconds since they went out (negative before).
    let sinceStart: Double
    /// A part of a split screen: smaller, and no haptic (one phone, one buzz).
    let compact: Bool

    private static let red = Color(red: 1, green: 0.16, blue: 0.12)
    private static let green = Color(red: 0.2, green: 0.95, blue: 0.4)

    var body: some View {
        let go = countdown <= 0
        let lit = go ? 3 : max(0, min(3, 4 - Int(countdown.rounded(.up))))
        let lamp: CGFloat = compact ? 24 : 38
        VStack(spacing: compact ? 6 : 10) {
            HStack(spacing: compact ? 8 : 12) {
                ForEach(0..<3, id: \.self) { index in
                    let on = index < lit
                    Circle()
                        .fill(on ? (go ? Self.green : Self.red) : Color(white: 0.18))
                        .frame(width: lamp, height: lamp)
                        .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 2))
                        .shadow(color: on ? (go ? Self.green : Self.red).opacity(0.9) : .clear, radius: compact ? 6 : 12)
                }
            }
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 8 : 12)
            .background(RoundedRectangle(cornerRadius: compact ? 14 : 20, style: .continuous).fill(Color(white: 0.06).opacity(0.92)))
            Text(Self.caption(go: go, lit: lit, countdown: countdown))
                .font(SR.Text.hero(compact ? 30 : 52))
                .foregroundStyle(go ? Self.green : Color.white)
                .shadow(color: .black.opacity(0.6), radius: 4)
                .scaleEffect(go ? 1.15 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: go)
        }
        .onChange(of: lit) { _, _ in
            if !compact { SRHaptic.select() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(go ? "Go" : "Starting in \(Int(countdown.rounded(.up)))")
    }

    /// The word under the lamps: GET READY, the seconds left, then GO!
    private static func caption(go: Bool, lit: Int, countdown: Double) -> String {
        if go { return "GO!" }
        if lit == 0 { return "GET READY" }
        return "\(Int(countdown.rounded(.up)))"
    }
}

/// A banner for a couple of seconds after each lap: which lap now, and how
/// long the last one took.
struct CarRaceLapBanner: View {
    let text: String
    let compact: Bool

    /// The banner's words while it is up, or nil: the first seconds of
    /// each lap after the first, until the finish.
    static func words(laps: CarLapCounter, raceTime: Double) -> String? {
        guard !laps.finished, let last = laps.splits.last, raceTime - last < 2.4, let lap = laps.lapTimes.last else { return nil }
        let head = laps.lap == laps.laps ? "Final lap" : "Lap \(laps.lap)"
        let fastest = laps.lapTimes.count > 1 && lap <= (laps.bestLap ?? lap)
        return "\(head) · \(CarRaceFormat.time(lap))\(fastest ? " · fastest" : "")"
    }

    var body: some View {
        Text(text.uppercased())
            .font(compact ? SR.Text.title(15) : SR.Text.display(22))
            .tracking(1)
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, compact ? 12 : 20)
            .padding(.vertical, compact ? 6 : 10)
            .background(Capsule().fill(Color.black.opacity(0.62)))
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel(text)
    }
}

/// The finish: a chequered banner with the time, the place and a new best,
/// and confetti falling over it for a few seconds.
struct CarRaceFinishBanner: View {
    let time: Double
    /// Where I came, when there was anyone to race; nil alone.
    let place: Int?
    let newBest: Bool
    let compact: Bool
    @State private var shown = false
    @State private var settled = false
    @State private var started = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion && !compact { confetti }
            banner
        }
        .onAppear {
            started = Date()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { shown = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_200_000_000)
                settled = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var words = "Finished in \(CarRaceFormat.time(time))"
        if let place { words += ", place \(place)" }
        if newBest { words += ", a new best" }
        return words
    }

    private var banner: some View {
        VStack(spacing: compact ? 2 : 6) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: compact ? 16 : 24, weight: .bold))
                Text(place.map { "P\($0)" } ?? "FINISH")
                    .font(compact ? SR.Text.title(17) : SR.Text.display(26))
                    .tracking(1.5)
            }
            Text(CarRaceFormat.time(time))
                .font(SR.Text.hero(compact ? 28 : 46))
                .monospacedDigit()
            if newBest {
                Text("NEW BEST")
                    .font(SR.Text.label(14))
                    .tracking(2)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(red: 1, green: 0.8, blue: 0.2)))
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, compact ? 14 : 26)
        .padding(.vertical, compact ? 8 : 14)
        .background(
            RoundedRectangle(cornerRadius: compact ? 16 : 24, style: .continuous)
                .fill(Color.black.opacity(0.75))
        )
        .overlay(alignment: .top) {
            CarRaceChequer()
                .frame(height: compact ? 6 : 10)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .padding(.horizontal, compact ? 10 : 16)
        }
        .scaleEffect(shown ? 1 : 0.5)
        .opacity(shown ? 1 : 0)
    }

    private var confetti: some View {
        TimelineView(.animation(minimumInterval: nil, paused: settled)) { timeline in
            let t = timeline.date.timeIntervalSince(started)
            Canvas { context, size in
                CarRaceFinishBanner.drawConfetti(in: context, size: size, time: t)
            }
        }
        .frame(width: 320, height: 300)
        .allowsHitTesting(false)
    }

    private static let confettiColours: [Color] = [
        Color(red: 1, green: 0.8, blue: 0.2), Color(red: 0.95, green: 0.3, blue: 0.35), Color(red: 0.3, green: 0.7, blue: 1),
        Color(red: 0.4, green: 0.9, blue: 0.5), .white, Color(red: 0.75, green: 0.45, blue: 1),
    ]

    static func drawConfetti(in context: GraphicsContext, size: CGSize, time: Double) {
        guard time < 3.2 else { return }
        let w = Double(size.width)
        for i in 0..<44 {
            // A fixed scatter per piece, the same every finish.
            let a = Double((i * 7919) % 997) / 997, b = Double((i * 104_729) % 991) / 991
            let x0 = w * 0.5 + (a - 0.5) * 60
            let vx = (a - 0.5) * 260, vy = -220 - 180 * b
            let x = x0 + vx * time + sin(time * 6 + Double(i)) * 8
            let y = 120 + vy * time + 260 * time * time
            let fade = max(0, min(1, 3.2 - time))
            var piece = context
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .radians(time * (3 + 5 * b) + Double(i)))
            piece.opacity = fade
            let colour = confettiColours[i % confettiColours.count]
            piece.fill(Path(CGRect(x: -3.5, y: -2, width: 7, height: 4)), with: .color(colour))
        }
    }
}

/// A strip of black and white squares: the chequered flag's edge.
struct CarRaceChequer: View {
    var body: some View {
        Canvas { context, size in
            let cell = max(2, Double(size.height) / 2)
            let columns = Int(Double(size.width) / cell) + 1
            for column in 0..<columns {
                for row in 0..<2 {
                    let rect = CGRect(x: Double(column) * cell, y: Double(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color((column + row) % 2 == 0 ? .white : .black))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The pedals: Brake and Boost, and the steering arrows when tilt does not
/// steer. Sized for thumbs mid-race, not for a settings page.
///
/// Tilting, the phone is held like a wheel: Brake under the left thumb,
/// Boost under the right, and between them, out of a thumb's way, the
/// button that makes the way the phone is held straight ahead. Steering by
/// the arrows, the left thumb has both
/// arrows and the right thumb rocks between Boost and Brake, the way a
/// racing game on a phone usually goes.
struct CarRaceControls: View {
    @ObservedObject var driver: CarRaceDriver

    static let pedalHeight: CGFloat = 88
    static let arrowHeight: CGFloat = 116

    var body: some View {
        if driver.scripted {
            Text("Autopilot")
                .font(SR.Text.mono())
                .foregroundStyle(Color.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.35)))
        } else if driver.useTilt {
            HStack(spacing: 12) {
                brake.frame(height: Self.arrowHeight)
                Button {
                    SRHaptic.tap()
                    driver.tilt.recentre()
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SR.ink)
                        .frame(width: 56, height: 56)
                        .srGlassCard(.paper, radius: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(SRPressStyle())
                .accessibilityLabel("Make the way I'm holding the phone straight ahead")
                .accessibilityIdentifier("car-race-recentre")
                boost.frame(height: Self.arrowHeight)
            }
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                HStack(spacing: 10) {
                    CarRacePad(icon: "arrow.left", label: "Steer left", lit: SR.accentDeep) { driver.steerHeld = $0 ? -1 : 0 }
                        .frame(minWidth: 76, maxWidth: 104)
                        .frame(height: Self.arrowHeight)
                        .accessibilityIdentifier("car-race-left")
                    CarRacePad(icon: "arrow.right", label: "Steer right", lit: SR.accentDeep) { driver.steerHeld = $0 ? 1 : 0 }
                        .frame(minWidth: 76, maxWidth: 104)
                        .frame(height: Self.arrowHeight)
                        .accessibilityIdentifier("car-race-right")
                }
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    boost.frame(height: Self.pedalHeight)
                    brake.frame(height: Self.pedalHeight)
                }
                .frame(minWidth: 112, maxWidth: 148)
            }
        }
    }

    private var brake: some View {
        CarRacePad(title: "BRAKE", icon: "exclamationmark.octagon.fill", label: "Brake", hint: "Hold to slow down") { driver.brakeHeld = $0 }
            .accessibilityIdentifier("car-race-brake")
    }

    private var boost: some View {
        CarRacePad(title: "BOOST", icon: "bolt.fill", label: "Boost", hint: "Hold for a burst of speed",
                   lit: CarRaceScene.flame, level: driver.car.boost) { driver.boostHeld = $0 }
            .accessibilityIdentifier("car-race-boost")
    }
}

/// A pad held down with a finger — an arrow, the brake, the boost — lit while
/// it is held. It fills whatever frame it is given, all of it touchable. The
/// boost's pad shows how full the tank is as a level rising behind it, and
/// glows when the tank is full.
struct CarRacePad: View {
    var title: String? = nil
    var icon: String? = nil
    let label: String
    var hint: String? = nil
    /// The colour it lights up when held.
    var lit: Color = SR.error
    /// The boost tank, 0…1: drawn as a level behind the label. Nil for none.
    var level: Double? = nil
    let changed: (Bool) -> Void
    @State private var held = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let full = (level ?? 0) >= 0.999
        VStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: title == nil ? 34 : 22, weight: .bold))
            }
            if let title {
                Text(title)
                    .font(SR.Text.label(16))
                    .tracking(SR.inkKickerTracking)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(held ? Color.white : SR.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack(alignment: .bottom) {
                if let level {
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle()
                                .fill(lit.opacity(held ? 0 : 0.4))
                                .frame(height: geo.size.height * min(1, max(0, level)))
                        }
                    }
                }
                if held { shape.fill(lit) }
            }
            .clipShape(shape)
        }
        .srGlassCard(.paper, radius: 26)
        .overlay(shape.stroke(held || full ? lit : Color.clear, lineWidth: held ? 3 : 2))
        .shadow(color: held ? lit.opacity(0.55) : .clear, radius: 10)
        .contentShape(shape)
        .scaleEffect(held ? 0.95 : 1)
        .animation(.easeOut(duration: 0.08), value: held)
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
        .accessibilityLabel(label)
        .accessibilityValue(level.map { "\(Int(($0 * 100).rounded())) percent" } ?? "")
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

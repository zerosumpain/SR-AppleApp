import SwiftUI
import UIKit

/// One Marble Race room, from lobby to the podium.
///
/// The lobby is every game's (`GameLobby`), with the course and how to play
/// as its panel. Picking is a grid of the course's marbles, drawn as glass
/// marbles in Marbler's colours, under a clock that runs down: tap one to back
/// it; a marble somebody else backs wears their initial and can't be taken.
/// The race is Marbler's own page in a web view, made when picking starts
/// (hidden behind the grid) so the engine is loaded before step 0, under a
/// slim bar saying which marble is mine. The finish is a podium of the first
/// three home, confetti when my marble won, the room's table and this phone's
/// record.
///
/// A room race cannot pause: every phone runs the same race to the room's
/// clock, and a phone that pauses would simply rejoin where the clock is.
struct MarbleRaceScreen: View {
    let roomId: String
    @StateObject private var store: MarbleRaceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: MarbleRaceStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle(store.state?.course.name ?? "Marble Race")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                store.open()
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                store.close()
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.open()
                    // Back from the background: rejoin the race where the room's clock is.
                    store.marbler.sendRoom()
                } else if phase == .background {
                    store.close()
                }
            }
            .overlay(alignment: .top) {
                if let message = store.message { SRBanner(text: message) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "marblerace-ended", done: { dismiss() })
        } else if let room = store.room, let state = store.state {
            switch store.phase {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "marblerace", done: { dismiss() },
                          panel: AnyView(MarbleRaceCourseCard(course: state.course)))
            case .picking, .racing:
                // One web view for both, so the page loads while marbles are picked.
                ZStack {
                    MarbleRaceRaceView(marbler: store.marbler, room: room, state: state,
                                       racing: store.phase == .racing, mine: store.myMarble)
                        .opacity(store.phase == .racing ? 1 : 0)
                        .accessibilityHidden(store.phase != .racing)
                    if store.phase == .picking {
                        MarbleRacePicking(room: room, state: state, store: store)
                    }
                }
                .background(MarblerPaint.ground)
            case .finished:
                MarbleRaceFinished(room: room, state: state, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "marblerace-ended", done: { dismiss() })
            }
        } else {
            VStack(spacing: 16) {
                HStack(spacing: -8) {
                    ForEach(0..<5, id: \.self) { m in
                        MarbleRaceMarbleArt(index: m, size: 36)
                    }
                }
                .accessibilityHidden(true)
                ProgressView()
                    .tint(SR.accent)
                Text("Finding the race…")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .srPaper()
        }
    }
}

// MARK: - A marble

/// One of Marbler's marbles as a glass marble: its colour, darker at the
/// rim, a pale swirl turned a different way for each marble, a highlight top
/// left and a soft shadow under it.
struct MarbleRaceMarbleArt: View {
    let index: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(MarblePalette.color(index))
            Circle()
                .trim(from: 0.08, to: 0.42)
                .stroke(Color.white.opacity(0.38), style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .padding(size * 0.2)
                .rotationEffect(.degrees(Double((index * 47) % 360)))
            Circle()
                .fill(RadialGradient(colors: [Color.clear, Color.black.opacity(0.38)],
                                     center: UnitPoint(x: 0.4, y: 0.36), startRadius: size * 0.12, endRadius: size * 0.62))
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.95), Color.white.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: size * 0.17))
                .frame(width: size * 0.36, height: size * 0.36)
                .offset(x: -size * 0.16, y: -size * 0.18)
            Circle().strokeBorder(Color.black.opacity(0.2), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.25), radius: size * 0.06, x: 0, y: size * 0.05)
    }
}

// MARK: - Lobby

/// The course, in the lobby, with how a race goes.
struct MarbleRaceCourseCard: View {
    let course: MarbleRaceState.Course

    var body: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    HStack(spacing: -10) {
                        ForEach(0..<min(5, max(1, course.marbles)), id: \.self) { m in
                            MarbleRaceMarbleArt(index: m, size: 30)
                        }
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(course.name)
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                        Text("\(course.marbles) marbles · about \(max(1, Int((Double(course.seconds) / 60).rounded()))) min")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Back a marble before the clock runs out. No two people back the same one.")
                    step(2, "Watch the race. Every phone runs exactly the same one.")
                    step(3, "Whoever backed the best-placed marble wins.")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("marblerace-course")
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(SR.Text.label(13))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(SR.accent))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Picking

/// Back a marble before the clock runs out.
struct MarbleRacePicking: View {
    let room: GameRoom
    let state: MarbleRaceState
    @ObservedObject var store: MarbleRaceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(alignment: .leading, spacing: 14) {
                        SRPageHeader(kicker: "Marble Race · \(secondsLeft) s", title: "Back a marble", strap: strap)
                        MarbleRacePickTimer(seconds: secondsLeft, picked: store.myMarble != nil)
                    }
                }
                MarbleRaceMyPick(marble: store.myMarble)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 12) {
                    ForEach(0..<max(0, state.course.marbles), id: \.self) { m in
                        marble(m)
                    }
                }
                if let refusal = store.refusal {
                    Label(refusal, systemImage: "exclamationmark.circle")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Everyone backs a different marble. Whoever hasn't picked when the clock runs out is given one.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 16)
        }
        .srPaper()
        .accessibilityIdentifier("marblerace-picking")
        .onChange(of: store.myMarble) { _, mine in
            if let mine {
                SRHaptic.ok()
                UIAccessibility.post(notification: .announcement, argument: "You back \(MarblePalette.name(mine)).")
            }
        }
    }

    private var strap: String {
        if let mine = store.myMarble { return "You back \(MarblePalette.name(mine))." }
        return "Pick the one you think will win."
    }

    private var secondsLeft: Int {
        guard let ends = room.phaseEndsAt, let now = store.serverNow() else { return 0 }
        return max(0, Int(((ends - now) / 1000).rounded(.up)))
    }

    private func marble(_ m: Int) -> some View {
        let backer = state.backer(of: m)
        let mine = backer == room.meId
        let taken = backer != nil && !mine
        var initial: String? = nil
        if taken, let backer { initial = String(room.name(of: backer).prefix(1)) }
        return Button {
            store.back(m)
        } label: {
            MarbleRacePickCell(index: m, mine: mine, backerInitial: initial)
        }
        .buttonStyle(SRPressStyle())
        .disabled(taken)
        .accessibilityLabel(taken ? "\(MarblePalette.name(m)), \(room.name(of: backer ?? ""))'s" : MarblePalette.name(m))
        .accessibilityAddTraits(mine ? .isSelected : [])
        .accessibilityIdentifier("marblerace-marble-\(m)")
    }
}

/// The picking clock as a bar that drains, amber in the last five seconds,
/// with a tick under the finger for each of the last three when I have not
/// picked. The bar is a share of the most time this phone has seen, as the
/// phone may open the room part-way through.
struct MarbleRacePickTimer: View {
    let seconds: Int
    let picked: Bool

    @State private var most = 0

    var body: some View {
        let fraction = MarbleRacePickClock.fraction(left: Double(seconds), total: Double(max(most, seconds)))
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(seconds <= 5 ? Color(hex: 0xE69500) : SR.accent)
                .accessibilityHidden(true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.ink.opacity(0.08))
                    Capsule()
                        .fill(seconds <= 5 ? Color(hex: 0xFFB300) : SR.accent)
                        .frame(width: max(8, geo.size.width * CGFloat(fraction)))
                        .animation(.linear(duration: 1), value: seconds)
                }
            }
            .frame(height: 12)
            Text("\(seconds) s")
                .font(SR.Text.figure(22))
                .foregroundStyle(seconds <= 5 ? Color(hex: 0xE69500) : SR.ink)
                .monospacedDigit()
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(seconds) seconds left to pick")
        .accessibilityIdentifier("marblerace-pick-clock")
        .onAppear { most = max(most, seconds) }
        .onChange(of: seconds) { _, left in
            most = max(most, left)
            if !picked, left > 0, left <= 3 { SRHaptic.tap() }
        }
    }
}

/// The marble I back, big — or a nudge to pick one.
struct MarbleRaceMyPick: View {
    let marble: Int?

    var body: some View {
        HStack(spacing: 14) {
            if let marble {
                MarbleRaceMarbleArt(index: marble, size: 52)
                    .transition(.scale.combined(with: .opacity))
                    .id(marble)
            } else {
                Circle()
                    .strokeBorder(SR.inkGhost, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR MARBLE")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text(marble.map { MarblePalette.name($0) } ?? "Not picked yet")
                    .font(SR.Text.display(22))
                    .foregroundStyle(marble == nil ? SR.inkMuted : SR.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: marble)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("marblerace-mine")
    }
}

/// One marble in the grid: the marble, its name, and a ring and a tick when
/// it is mine, or the backer's initial when it is somebody else's.
struct MarbleRacePickCell: View {
    let index: Int
    let mine: Bool
    let backerInitial: String?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                MarbleRaceMarbleArt(index: index, size: 54)
                    .scaleEffect(mine ? 1.08 : 1)
                if mine {
                    Circle()
                        .strokeBorder(SR.accent, lineWidth: 4)
                        .frame(width: 66, height: 66)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white, SR.accent)
                        .offset(x: 22, y: -22)
                }
                if let backerInitial {
                    Text(backerInitial.uppercased())
                        .font(SR.Text.title())
                        .foregroundStyle(MarblePalette.isLight(index) ? Color.black : Color.white)
                }
            }
            .frame(width: 68, height: 68)
            Text(MarblePalette.name(index))
                .font(SR.Text.mono())
                .foregroundStyle(mine ? SR.ink : SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .opacity(backerInitial != nil ? 0.45 : 1)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: mine)
    }
}

// MARK: - Racing

/// The race: the page, under a slim bar saying which marble is mine, with a
/// cover while the page loads and a card if it cannot.
struct MarbleRaceRaceView: View {
    @ObservedObject var marbler: MarblerModel
    let room: GameRoom
    let state: MarbleRaceState
    let racing: Bool
    let mine: Int?

    var body: some View {
        VStack(spacing: 0) {
            bar
            MarblerWebView(model: marbler)
                .ignoresSafeArea(edges: .bottom)
                .overlay { cover }
                .overlay(alignment: .top) {
                    if racing {
                        MarblerFinishToast(note: marbler.finishNote, dismiss: { marbler.finishNote = nil })
                    }
                }
        }
    }

    private var bar: some View {
        HStack(spacing: 10) {
            if let mine {
                MarbleRaceMarbleArt(index: mine, size: 28)
                Text("You back \(MarblePalette.name(mine))")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(MarblerPaint.cream)
            } else {
                Image(systemName: "eye")
                    .foregroundStyle(MarblerPaint.cream.opacity(0.8))
                    .accessibilityHidden(true)
                Text("Watching")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(MarblerPaint.cream)
            }
            Spacer(minLength: 8)
            Text(state.course.name.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(MarblerPaint.cream.opacity(0.65))
                .lineLimit(1)
        }
        .padding(.horizontal, SR.gutter)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .background(MarblerPaint.ground)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("marblerace-race-bar")
    }

    @ViewBuilder
    private var cover: some View {
        if let error = marbler.error {
            MarblerErrorCard(message: error, retry: { marbler.reload() })
        } else if !marbler.loaded {
            MarblerLoadingCover(text: "Rolling the marbles out…")
        }
    }
}

// MARK: - Finished

/// The podium, who backed what and where it came, and this phone's record.
struct MarbleRaceFinished: View {
    let room: GameRoom
    let state: MarbleRaceState
    @ObservedObject var store: MarbleRaceStore
    let done: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var risen = false
    @State private var book = MarbleRaceRecordBook()
    @State private var news: MarbleRaceRecordNews?

    private var iWon: Bool { room.winnerIds.contains(room.meId) && !room.solo }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Marble Race · \(state.course.name)", title: title, strap: strap)
                if let order = state.result?.order, !order.isEmpty {
                    podium(order)
                }
                if let line = myLine {
                    Label(line, systemImage: iWon ? "trophy.fill" : "flag.checkered")
                        .font(SR.Text.bodyMedium(16))
                        .foregroundStyle(iWon ? SR.accentInk : SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("marblerace-my-place")
                }
                GameStandingsCard(
                    room: room,
                    label: "Results",
                    id: "marblerace-standings",
                    detail: { row in
                        guard let m = state.marble(of: row.id) else { return "No marble" }
                        let place = state.place(of: m).map { " · came \(MarbleRaceOrdinal.text($0))" } ?? ""
                        return "\(MarblePalette.name(m))\(place)"
                    },
                    figure: { row in (text: "\(row.score)", spoken: "\(row.score) points") }
                )
                if state.result?.disputed == true {
                    Text("Not every phone saw the same finish. The order most of them saw stands.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("marblerace-disputed")
                }
                if book.races > 0 { recordCard }
                GameFinishedButtons(room: room, store: store, prefix: "marblerace", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 16)
        }
        .srPaper()
        .overlay {
            if iWon {
                ChessMarbleConfettiView(seed: UInt64(state.race?.seed ?? 3))
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            if iWon { SRHaptic.ok() }
            record()
            withAnimation(reduceMotion ? nil : Animation.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) { risen = true }
        }
    }

    private var title: String {
        guard let winner = room.winnerIds.first else { return state.result?.order == nil ? "No result" : "Race over" }
        return winner == room.meId ? "You win!" : "\(room.name(of: winner)) wins"
    }

    private var strap: String {
        guard let first = state.result?.order?.first else { return "No phone reported a finish." }
        return "\(MarblePalette.name(first)) was first home."
    }

    private var myLine: String? {
        guard let mine = store.myMarble else { return nil }
        guard let place = state.place(of: mine) else { return "Your \(MarblePalette.name(mine)) has no place." }
        return "Your \(MarblePalette.name(mine)) came \(MarbleRaceOrdinal.text(place))."
    }

    // MARK: The podium

    private func podium(_ order: [Int]) -> some View {
        let steps = MarbleRacePodium.standing(order)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(steps) { step in
                podiumStep(step)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SR.cardPadding)
        .padding(.top, 18)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(podiumSpoken(steps))
        .accessibilityIdentifier("marblerace-podium")
    }

    private func podiumStep(_ step: MarbleRacePodiumStep) -> some View {
        let height: CGFloat = step.place == 1 ? 96 : step.place == 2 ? 70 : 52
        let backer = state.backer(of: step.marble).map { $0 == room.meId ? "You" : room.name(of: $0) }
        return VStack(spacing: 6) {
            if step.place == 1 {
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundStyle(Color(hex: 0xE6A700))
            }
            MarbleRaceMarbleArt(index: step.marble, size: step.place == 1 ? 58 : 46)
            Text(backer ?? MarblePalette.name(step.marble))
                .font(SR.Text.mono())
                .foregroundStyle(backer == "You" ? SR.accentInk : SR.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 10, style: .continuous)
                    .fill(stepColour(step.place))
                Text(MarbleRaceOrdinal.text(step.place))
                    .font(SR.Text.figure(22))
                    .foregroundStyle(Color.white)
                    .padding(.top, 8)
            }
            .frame(height: risen ? height : 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepColour(_ place: Int) -> Color {
        switch place {
        case 1: return Color(hex: 0xD4A017)
        case 2: return Color(hex: 0x8E99A8)
        default: return Color(hex: 0xB0703C)
        }
    }

    private func podiumSpoken(_ steps: [MarbleRacePodiumStep]) -> String {
        let ordered = steps.sorted { $0.place < $1.place }
        return ordered.map { (step: MarbleRacePodiumStep) -> String in
            let backer = state.backer(of: step.marble).map { ", backed by \($0 == room.meId ? "you" : room.name(of: $0))" } ?? ""
            return "\(MarbleRaceOrdinal.spoken(step.place)), \(MarblePalette.name(step.marble))\(backer)"
        }.joined(separator: ". ")
    }

    // MARK: This phone's record

    private var recordCard: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Your races on this phone", trailing: book.races == 1 ? "1 race" : "\(book.races) races")
            HStack(spacing: 0) {
                figure("\(book.wins)", "Wins", tone: SR.good)
                figure("\(book.podiums)", "Top three", tone: SR.accent)
                figure(book.bestPlace.map { MarbleRaceOrdinal.text($0) } ?? "–", "Best", tone: SR.ink)
            }
            .padding(.vertical, 14)
            .srGlassCard(.paper)
            if news?.counted == true, news?.newBest == true, book.races > 1 {
                Label("A new best on this phone.", systemImage: "sparkles")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.accentInk)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("marblerace-record")
    }

    private func figure(_ value: String, _ label: String, tone: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(SR.Text.figure(26))
                .foregroundStyle(tone)
                .monospacedDigit()
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// Count this race in the phone's record, once — only when I backed a marble, never the demo's.
    private func record() {
        let records = MarbleRaceRecordStore(key: MarbleRaceRecordStore.roomKey)
        var loaded = records.load()
        if !SRDemo.isOn, let mine = store.myMarble, let order = state.result?.order {
            let key = "\(room.id)|\(state.race?.seed ?? 0)|\(order.map(String.init).joined(separator: ","))"
            let made = loaded.record(key: key, place: state.place(of: mine))
            if made.counted { records.save(loaded) }
            news = made
        }
        book = loaded
    }
}

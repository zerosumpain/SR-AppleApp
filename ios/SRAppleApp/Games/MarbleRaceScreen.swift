import SwiftUI
import UIKit

/// One Marble Race room, from lobby to the podium.
///
/// The lobby is every game's (`GameLobby`), with the course as its panel.
/// Picking is a grid of the course's marbles in Marbler's colours: tap one to
/// back it; a marble somebody else backs wears their initial and can't be
/// taken. The race is Marbler's own page in a web view, made when picking
/// starts (hidden behind the grid) so the engine is loaded before step 0.
/// The finish is the room's table: who backed what, and where it came.
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
                    MarblerWebView(model: store.marbler)
                        .ignoresSafeArea(edges: .bottom)
                        .opacity(store.phase == .racing ? 1 : 0)
                        .accessibilityHidden(store.phase != .racing)
                    if store.phase == .picking {
                        MarbleRacePicking(room: room, state: state, store: store)
                    }
                }
                .background(Color(red: 0x14 / 255, green: 0x10 / 255, blue: 0x0c / 255))
            case .finished:
                MarbleRaceFinished(room: room, state: state, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "marblerace-ended", done: { dismiss() })
            }
        } else {
            ProgressView()
                .tint(SR.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
        }
    }
}

/// The course, in the lobby.
struct MarbleRaceCourseCard: View {
    let course: MarbleRaceState.Course

    var body: some View {
        SRCard {
            HStack(spacing: 12) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(SR.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.name)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text("\(course.marbles) marbles · about \(max(1, Int((Double(course.seconds) / 60).rounded()))) min")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("marblerace-course")
    }
}

/// Back a marble before the clock runs out.
struct MarbleRacePicking: View {
    let room: GameRoom
    let state: MarbleRaceState
    @ObservedObject var store: MarbleRaceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    SRPageHeader(kicker: "Marble Race · \(secondsLeft) s", title: "Back a marble", strap: strap)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
                    ForEach(0..<state.course.marbles, id: \.self) { m in
                        marble(m)
                    }
                }
                if let refusal = store.refusal {
                    Text(refusal)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.error)
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
        return Button {
            store.back(m)
        } label: {
            ZStack {
                Circle()
                    .fill(MarblePalette.color(m))
                    .frame(width: 52, height: 52)
                    .overlay(Circle().strokeBorder(mine ? SR.accent : .clear, lineWidth: 4))
                if let backer, !mine {
                    Text(String(room.name(of: backer).prefix(1)))
                        .font(SR.Text.title())
                        .foregroundStyle(MarblePalette.isLight(m) ? Color.black : Color.white)
                }
            }
            .opacity(taken ? 0.45 : 1)
            .frame(minWidth: SR.tapTarget, minHeight: SR.tapTarget)
        }
        .buttonStyle(.plain)
        .disabled(taken)
        .accessibilityLabel(taken ? "\(MarblePalette.name(m)), \(room.name(of: backer!))'s" : MarblePalette.name(m))
        .accessibilityAddTraits(mine ? .isSelected : [])
        .accessibilityIdentifier("marblerace-marble-\(m)")
    }
}

/// Who backed what, and where it came.
struct MarbleRaceFinished: View {
    let room: GameRoom
    let state: MarbleRaceState
    @ObservedObject var store: MarbleRaceStore
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Marble Race · \(state.course.name)", title: title, strap: strap)
                GameStandingsCard(
                    room: room,
                    label: "Results",
                    id: "marblerace-standings",
                    detail: { row in
                        guard let m = state.marble(of: row.id) else { return "No marble" }
                        let place = state.place(of: m).map { " · came \(ordinal($0))" } ?? ""
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
                GameFinishedButtons(room: room, store: store, prefix: "marblerace", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 16)
        }
        .srPaper()
    }

    private var title: String {
        guard let winner = room.winnerIds.first else { return state.result?.order == nil ? "No result" : "Race over" }
        return winner == room.meId ? "You win!" : "\(room.name(of: winner)) wins"
    }

    private var strap: String {
        guard let first = state.result?.order?.first else { return "No phone reported a finish." }
        return "\(MarblePalette.name(first)) was first home."
    }

    private func ordinal(_ n: Int) -> String {
        let s = n % 100 >= 11 && n % 100 <= 13 ? "th" : ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
        return "\(n)\(s)"
    }
}

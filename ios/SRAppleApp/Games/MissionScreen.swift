import SwiftUI
import UIKit

/// One Secret Mission room, from lobby to the last mission.
///
/// The talking happens out loud round the table; the phone holds only my
/// secret and my votes. The lobby and the 3-2-1 are every game's. Then my role
/// card — a manila dossier stamped TOP SECRET, face down until I hold it
/// (somebody may be looking over my shoulder) — with the spies I know. Each
/// round: the score and the five-mission route with the rejection meter, then
/// the leader's team picker, everyone's big Approve / Reject, the votes shown
/// together, the team's two cards (Sabotage only works on a spy's phone, but
/// both are drawn on every team phone so the layout gives nothing away), and
/// the cards turned over one by one with a stamp. With the Lookout in play a
/// crew win ends in the hunt: the Tracker names one of the crew. The finish
/// shows the winning side, every role, and this phone's record.
///
/// The room runs on the server's clock for everyone, so there is no pause:
/// the "?" in the bar opens how to play over the game instead.
struct MissionScreen: View {
    let roomId: String
    @StateObject private var store: MissionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingHowTo = false

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: MissionStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Secret Mission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(immersive ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(immersive)
            .onAppear { store.open() }
            .onDisappear { store.close() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.open() } else if phase == .background { store.close() }
            }
            .overlay(alignment: .top) {
                if let message = store.message, !immersive { SRBanner(text: message) }
            }
            .toolbar {
                if showsHelp {
                    ToolbarItem(placement: .topBarTrailing) {
                        TableHelpButton(id: "mission-help") { showingHowTo = true }
                    }
                }
            }
            .sheet(isPresented: $showingHowTo) {
                TableHowToSheet(game: "Secret Mission",
                                steps: MissionHowTo.steps(specials: store.room?.mission?.specials ?? false),
                                note: TableHowToNote.live, id: "mission-how-to")
            }
    }

    private var immersive: Bool {
        guard !store.ended, let room = store.room else { return false }
        return MissionScreenPhase.of(room) == .countdown
    }

    private var showsHelp: Bool {
        guard !store.ended, let room = store.room else { return false }
        switch MissionScreenPhase.of(room) {
        case .roles, .proposing, .voting, .tally, .mission, .outcome, .hunt: return true
        default: return false
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "mission-ended", done: { dismiss() })
        } else if let room = store.room {
            switch MissionScreenPhase.of(room) {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "mission", done: { dismiss() },
                          panel: AnyView(MissionLobbyPanel(room: room)),
                          startBlocked: room.playing.count < MissionRules.minPlayers)
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Keep your screen to yourself: your role is next.",
                                  id: "mission-countdown")
            case .roles:
                MissionRolesPage(room: room, store: store)
            case .proposing, .voting, .tally, .mission, .outcome, .hunt:
                MissionPlaying(room: room, store: store)
            case .finished:
                MissionFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "mission-ended", done: { dismiss() })
            }
        } else {
            VStack(spacing: 14) {
                MissionDossierArt(side: 84)
                Text("Opening the files…")
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(SR.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .srGround(.warm)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("mission-loading")
        }
    }
}

// MARK: - Colours and how to play

/// The game's fixed colours. Fills carry white type, so they are the same in
/// both themes: the crew blue, the spies crimson, yes green and no red, and
/// the dossier's manila.
enum MissionPalette {
    static let crew = Color(hex: 0x2F6FD0)
    static let spies = Color(hex: 0xB3261E)
    static let yes = Color(hex: 0x2E8540)
    static let no = Color(hex: 0xC8372D)
    static let manila = Color(hex: 0xE6C98F)
    static let manilaDeep = Color(hex: 0xCDA661)
    static let manilaInk = Color(hex: 0x4A3415)
    static let stamp = Color(hex: 0xB3261E)
    static let cardBack = Color(hex: 0x2A2340)

    static func side(_ side: MissionSide?) -> Color { side == .spies ? spies : crew }
}

enum MissionHowTo {
    static func steps(specials: Bool) -> [TableHowToStep] {
        var list = [
            TableHowToStep(icon: "person.2.fill", title: "Crew against spies",
                           text: "Hold your card to see your side. The spies know each other; the crew don't know anyone."),
            TableHowToStep(icon: "flag.fill", title: "The leader picks a team",
                           text: "Talk it over out loud. Then everyone votes at once to send the team or turn it down."),
            TableHowToStep(icon: "checkmark.seal.fill", title: "On the mission",
                           text: "The team play cards in secret. The crew can only succeed; a spy can sabotage."),
            TableHowToStep(icon: "trophy.fill", title: "Three wins it",
                           text: "Three missions succeed and the crew win. Three fail — or five teams are turned down in a row — and the spies win."),
        ]
        if specials {
            list.append(TableHowToStep(icon: "binoculars.fill", title: "The Lookout and the Tracker",
                                       text: "The Lookout knows the spies but must stay hidden. If the crew win, the Tracker gets one guess at who the Lookout is."))
        }
        return list
    }
}

// MARK: - Lobby

struct MissionLobbyPanel: View {
    let room: GameRoom

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            MissionTableCard(room: room)
            VStack(alignment: .leading, spacing: 14) {
                SRSectionLabel(text: "How to play")
                TableHowToList(steps: MissionHowTo.steps(specials: room.mission?.specials ?? false),
                               tint: MissionPalette.crew)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mission-howto")
        }
    }
}

/// The table in the lobby: crew and spies at this size, which roles the level
/// adds, and how many more people are needed.
struct MissionTableCard: View {
    let room: GameRoom

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            MissionDossierArt(side: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(MissionSettings.about(room.difficulty).uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text("Crew against spies")
                    .font(SR.Text.title(19))
                    .foregroundStyle(SR.ink)
                Text(MissionRules.tableLine(players: room.playing.count))
                    .font(SR.Text.secondary())
                    .foregroundStyle(room.playing.count < MissionRules.minPlayers ? SR.error : SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mission-table-line")
                Text("Play it in one room: you talk out loud, the phones keep the secrets.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mission-table")
    }
}

/// The game's picture: a manila folder stamped TOP SECRET.
struct MissionDossierArt: View {
    var side: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.10, style: .continuous)
                .fill(MissionPalette.manilaDeep)
                .frame(width: side * 0.86, height: side * 0.66)
                .offset(x: side * 0.03, y: -side * 0.04)
            RoundedRectangle(cornerRadius: side * 0.10, style: .continuous)
                .fill(MissionPalette.manila)
                .frame(width: side * 0.86, height: side * 0.62)
                .offset(y: side * 0.06)
            Text("TOP SECRET")
                .font(.system(size: side * 0.12, weight: .heavy, design: .rounded))
                .foregroundStyle(MissionPalette.stamp)
                .padding(.horizontal, side * 0.04)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(MissionPalette.stamp, lineWidth: max(1.5, side * 0.025)))
                .rotationEffect(.degrees(-12))
                .offset(y: side * 0.06)
            Image(systemName: "eye.slash.fill")
                .font(.system(size: side * 0.16, weight: .bold))
                .foregroundStyle(MissionPalette.manilaInk.opacity(0.7))
                .offset(x: side * 0.26, y: side * 0.24)
        }
        .frame(width: side, height: side)
    }
}

// MARK: - My role

/// My role, face down until held: a dossier nobody beside me can read by
/// accident. Let go and it closes again.
struct MissionRoleCard: View {
    let room: GameRoom
    /// The smaller copy under the round's panel.
    var compact = false
    @State private var shown = false
    @State private var held = false

    private var secret: MissionSecret? { room.mission?.secret }

    var body: some View {
        let visible = shown || held
        VStack(alignment: .leading, spacing: 10) {
            if let secret {
                if visible {
                    face(secret)
                        .transition(.opacity)
                } else {
                    back
                        .transition(.opacity)
                }
            } else {
                Label("You are watching this one: no role.", systemImage: "eye")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background { ground(visible: visible) }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(SR.ink.opacity(0.12), lineWidth: 1)
        )
        .scaleEffect(held ? 1.02 : 1)
        .shadow(color: Color.black.opacity(held ? 0.18 : 0.08), radius: held ? 14 : 6, x: 0, y: held ? 8 : 3)
        .srAnimation(.snappy(duration: 0.22), value: visible)
        .contentShape(Rectangle())
        // Shown only while the finger is down: let go and it is face down again.
        .onLongPressGesture(minimumDuration: 30, maximumDistance: 40) {
        } onPressingChanged: { pressing in
            if pressing, !held { SRHaptic.select() }
            held = pressing
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(visible: visible))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(visible ? "Hides your role" : "Shows your role")
        .accessibilityAction { shown.toggle() }
        .accessibilityIdentifier("mission-role")
    }

    private var minHeight: CGFloat {
        if secret == nil { return 0 }
        return compact ? 92 : 200
    }

    @ViewBuilder
    private func ground(visible: Bool) -> some View {
        if visible || secret == nil {
            Rectangle().fill(SR.surface)
        } else {
            Rectangle().fill(LinearGradient(colors: [MissionPalette.manila, MissionPalette.manilaDeep],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    /// The open dossier: my side, my role, what I know.
    private func face(_ secret: MissionSecret) -> some View {
        let tone = MissionPalette.side(secret.side)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: secret.role.icon)
                    .font(SR.Text.hero(compact ? 22 : 30))
                    .foregroundStyle(Color.white)
                    .frame(width: compact ? 48 : 66, height: compact ? 48 : 66)
                    .background(Circle().fill(tone))
                VStack(alignment: .leading, spacing: 0) {
                    Text(secret.side == .spies ? "SPIES" : "CREW")
                        .font(SR.Text.label(13))
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(tone)
                    Text(secret.role.title)
                        .font(SR.Text.hero(compact ? 26 : 34))
                        .foregroundStyle(SR.ink)
                }
                Spacer(minLength: 0)
            }
            if !compact {
                Text(secret.role.brief)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !secret.spies.isEmpty {
                Text((secret.role == .lookout ? "The spies: " : "Your fellow spies: ")
                     + GameNames.list(secret.spies.map { room.name(of: $0) }))
                    .font(SR.Text.title(15))
                    .foregroundStyle(MissionPalette.spies)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mission-known-spies")
            } else if secret.side == .crew {
                Text("You don't know who anyone is.")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.inkMuted)
            }
        }
    }

    /// The closed dossier.
    private var back: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "touchid")
                .font(SR.Text.hero(compact ? 28 : 40))
                .foregroundStyle(MissionPalette.manilaInk.opacity(0.75))
            VStack(alignment: .leading, spacing: 6) {
                Text("TOP SECRET")
                    .font(SR.Text.hero(compact ? 18 : 26))
                    .tracking(2)
                    .foregroundStyle(MissionPalette.stamp)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(MissionPalette.stamp, lineWidth: 2.5))
                    .rotationEffect(.degrees(-6))
                Text("Hold to see your role")
                    .font(SR.Text.title(compact ? 16 : 18))
                    .foregroundStyle(MissionPalette.manilaInk)
                if !compact {
                    Text("Cup it in your hand. Let go and it closes.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(MissionPalette.manilaInk.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func spoken(visible: Bool) -> String {
        guard let secret else { return "No role" }
        guard visible else { return "Your role, face down" }
        var line = "You are \(secret.role.title), on \(secret.side == .spies ? "the spies" : "the crew")."
        if !secret.spies.isEmpty { line += " Spies: \(GameNames.list(secret.spies.map { room.name(of: $0) }))." }
        return line
    }
}

struct MissionRolesPage: View {
    let room: GameRoom
    @ObservedObject var store: MissionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Secret Mission · \(GameDifficulty.label(for: room.difficulty))",
                             title: "Your role",
                             strap: "Hold the card to read it. Don't let anyone see.")
                MissionRoleCard(room: room)
                Button { store.ready() } label: {
                    SRButtonLabel(title: store.amReady ? "Waiting for the others" : "Got it", icon: "checkmark", fill: true)
                        .frame(minHeight: 56)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(store.amReady || store.sending || room.me?.joined != true)
                .accessibilityIdentifier("mission-ready")
                readyRow
                if let rule = room.mission?.rule {
                    Label(rule, systemImage: "info.circle")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("mission-roles")
    }

    /// Who has read their card: a face per seat, lit once ready.
    private var readyRow: some View {
        let seats = room.mission?.seatsById.filter(\.seated) ?? []
        // Ten faces must fit a 375pt phone.
        let side: CGFloat = seats.count > 7 ? 26 : 34
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(seats) { seat in
                    GameInitial(name: room.name(of: seat.id), filled: seat.ready, tone: MissionPalette.yes, side: side)
                }
            }
            Text("\(seats.filter(\.ready).count) of \(seats.count) ready")
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .srAnimation(.snappy, value: seats.filter(\.ready).count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(seats.filter(\.ready).count) of \(seats.count) ready")
    }
}

// MARK: - The rounds

struct MissionPlaying: View {
    let room: GameRoom
    @ObservedObject var store: MissionStore

    private var state: MissionState? { room.mission }
    private var phase: MissionPhase { MissionScreenPhase.of(room) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                MissionTrack(state: state)
                MissionRejectionMeter(state: state)
                panel
                if let refusal = store.refusal {
                    Label(refusal, systemImage: "exclamationmark.circle.fill")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("mission-refusal")
                }
                MissionRoleCard(room: room, compact: true)
                MissionSeatsTable(room: room, store: store)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .srAnimation(.snappy(duration: 0.3), value: phase)
        }
        .srGround(.warm)
        .accessibilityIdentifier("mission-\(phase.rawValue)")
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: headIcon)
                .font(SR.Text.title(20))
                .foregroundStyle(Color.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(headTone))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(phase == .hunt ? "THE HUNT" : "MISSION \(state?.mission ?? 1) OF 5") · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(headline)
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("mission-headline")
            }
            Spacer(minLength: 0)
        }
    }

    private func who(_ id: String?) -> String {
        guard let id else { return "Someone" }
        return id == room.meId ? "You" : room.name(of: id)
    }

    private var headline: String {
        let size = state?.teamSize ?? 0
        switch phase {
        case .proposing:
            return store.amLeader ? "You lead: pick a team of \(size)" : "\(who(state?.leaderId)) is picking a team of \(size)"
        case .voting:
            return "Send this team?"
        case .tally:
            return state?.lastTally.map(MissionRules.tallyLine) ?? "The votes"
        case .mission:
            return store.onTeam ? "You're on the mission" : "The team is on the mission"
        case .outcome:
            if let o = state?.lastOutcome { return o.succeeded ? "Mission succeeded" : "Mission sabotaged" }
            return "The mission"
        case .hunt:
            return store.amTracker ? "Who is the Lookout?" : "The Tracker is choosing"
        default:
            return ""
        }
    }

    /// What I have to do now, as one picture: a flag to lead, a hand to vote,
    /// a card to play, a scope to hunt — and an hourglass when it is someone
    /// else's move.
    private var headIcon: String {
        switch phase {
        case .proposing: return store.amLeader ? "flag.fill" : "hourglass"
        case .voting: return store.canVote ? "hand.raised.fill" : "envelope.fill"
        case .tally: return "chart.bar.fill"
        case .mission: return store.canPlay ? "rectangle.portrait.on.rectangle.portrait.fill" : "hourglass"
        case .outcome:
            return state?.lastOutcome?.succeeded == false ? "bolt.slash.fill" : "checkmark.seal.fill"
        case .hunt: return "scope"
        default: return "eye.slash.fill"
        }
    }

    private var headTone: Color {
        switch phase {
        case .outcome: return state?.lastOutcome?.succeeded == false ? MissionPalette.spies : MissionPalette.crew
        case .hunt: return MissionPalette.spies
        default:
            let acting = store.amLeader || store.canVote || store.canPlay || store.amTracker
            return acting ? SR.accent : SR.inkMuted
        }
    }

    // MARK: The panel for this phase

    @ViewBuilder
    private var panel: some View {
        switch phase {
        case .proposing: MissionProposePanel(room: room, store: store)
        case .voting: MissionVotePanel(room: room, store: store)
        case .tally: MissionTallyPanel(room: room)
        case .mission: MissionCardsPanel(room: room, store: store)
        case .outcome: MissionOutcomePanel(room: room)
        case .hunt: MissionHuntPanel(room: room, store: store)
        default: EmptyView()
        }
    }
}

/// Names as the table says them: "You" for me.
enum MissionNames {
    static func who(_ id: String?, in room: GameRoom) -> String {
        guard let id else { return "Someone" }
        return id == room.meId ? "You" : room.name(of: id)
    }
}

/// The clock for the phase in hand: a bar that empties and warms, and a tap at
/// ten seconds and five while the move is mine.
struct MissionClockBar: View {
    let room: GameRoom
    @ObservedObject var store: MissionStore
    let totalMs: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            DrawGuessClockTrack(fraction: fraction, seconds: seconds, nudges: nudges)
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("mission-clock")
    }

    private var fraction: Double {
        MissionRules.timeLeft(endsAt: room.phaseEndsAt, totalMs: totalMs, now: store.serverNow())
    }

    private var seconds: Int? { TableClock.secondsLeft(endsAt: room.phaseEndsAt, now: store.serverNow()) }

    private var nudges: Bool { store.amLeader || store.canVote || store.canPlay || store.amTracker }

    /// The clock for a room's phase, or none.
    static func total(_ state: MissionState?, phase: MissionPhase) -> Double {
        switch phase {
        case .proposing: return state?.proposeMs ?? 90_000
        case .voting: return state?.voteMs ?? 45_000
        case .mission: return state?.missionMs ?? 30_000
        case .hunt: return state?.huntMs ?? 90_000
        default: return 0
        }
    }
}

/// The team on its way: a face for each, and their names.
struct MissionTeamLine: View {
    let room: GameRoom

    var body: some View {
        let state = room.mission
        let team = state?.team ?? []
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "The team",
                           trailing: state?.autoTeam == true ? "Picked by the clock" : "\(MissionNames.who(state?.leaderId, in: room)) leads")
            HStack(spacing: -8) {
                ForEach(team, id: \.self) { id in
                    GameInitial(name: room.name(of: id), filled: true, tone: SR.accent, side: 40)
                        .overlay(Circle().strokeBorder(SR.surface, lineWidth: 2))
                }
            }
            .accessibilityHidden(true)
            Text(GameNames.list(team.map { MissionNames.who($0, in: room) }))
                .font(SR.Text.display(20))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mission-team")
        }
    }
}

// MARK: Proposing

struct MissionProposePanel: View {
    let room: GameRoom
    @ObservedObject var store: MissionStore

    private var state: MissionState? { room.mission }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MissionClockBar(room: room, store: store, totalMs: MissionClockBar.total(state, phase: .proposing))
            if store.amLeader {
                leaderPicker
            } else {
                waiting
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private var leaderPicker: some View {
        let size = state?.teamSize ?? 0
        let seated = room.players.filter { state?.seat($0.id)?.seated == true }
        return VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Your team", trailing: "\(store.picked.count) of \(size)")
            slots(size: size)
            VStack(spacing: 8) {
                ForEach(seated) { player in
                    pickRow(player)
                }
            }
            Button { store.propose() } label: {
                SRButtonLabel(title: "Propose this team", icon: "paperplane.fill", fill: true)
                    .frame(minHeight: 56)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(!store.canPropose)
            .accessibilityIdentifier("mission-propose")
            Text("Talk it over out loud first. If you run out of time, a team is picked for you.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The seats on the team, filling as I pick.
    private func slots(size: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<max(size, 1), id: \.self) { index in
                if index < store.picked.count {
                    GameInitial(name: room.name(of: store.picked[index]), filled: true, tone: SR.accent, side: 40)
                        .tablePopIn()
                } else {
                    Circle()
                        .strokeBorder(SR.inkGhost, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        .frame(width: 40, height: 40)
                }
            }
            Spacer(minLength: 0)
        }
        .srAnimation(.snappy(duration: 0.25), value: store.picked)
        .accessibilityHidden(true)
    }

    private func pickRow(_ player: GamePlayer) -> some View {
        let on = store.picked.contains(player.id)
        return Button { store.toggle(player.id) } label: {
            HStack(spacing: 12) {
                GameInitial(name: player.name, filled: on, tone: SR.accent, side: 36)
                Text(player.name + (player.id == room.meId ? " (you)" : ""))
                    .font(SR.Text.title(18))
                    .foregroundStyle(player.joined ? SR.ink : SR.inkMuted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !player.joined {
                    Text("LEFT").font(SR.Text.label()).tracking(1).foregroundStyle(SR.inkMuted)
                }
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(SR.Text.title(24))
                    .foregroundStyle(on ? SR.accent : SR.inkGhost)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                    .fill(on ? SR.accent.opacity(0.12) : SR.surface.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                    .strokeBorder(on ? SR.accent : SR.line, lineWidth: on ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(player.id == room.meId ? "You" : player.name)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("mission-pick-\(player.id)")
    }

    private var waiting: some View {
        let leader = MissionNames.who(state?.leaderId, in: room)
        return HStack(alignment: .center, spacing: 14) {
            ZStack(alignment: .topTrailing) {
                GameInitial(name: leader, filled: true, tone: SR.accent, side: 52)
                Image(systemName: "flag.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(MissionPalette.crew))
                    .offset(x: 6, y: -6)
            }
            .accessibilityHidden(true)
            Text("Argue for who should go. The team goes to a vote when \(leader) proposes it.")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Voting

struct MissionVotePanel: View {
    let room: GameRoom
    @ObservedObject var store: MissionStore

    private var state: MissionState? { room.mission }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MissionTeamLine(room: room)
            MissionClockBar(room: room, store: store, totalMs: MissionClockBar.total(state, phase: .voting))
            if let mine = state?.secret?.vote {
                sealed(mine)
            } else if store.canVote {
                HStack(spacing: 12) {
                    voteButton(approve: false)
                    voteButton(approve: true)
                }
                Text("Everyone votes at once; nobody sees a vote until the last is in. No vote in time counts as approve.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private func voteButton(approve: Bool) -> some View {
        let tone = approve ? MissionPalette.yes : MissionPalette.no
        return Button { store.vote(approve: approve) } label: {
            VStack(spacing: 8) {
                Image(systemName: approve ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .font(SR.Text.hero(32))
                Text(approve ? "APPROVE" : "REJECT")
                    .font(SR.Text.label(15))
                    .tracking(1.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [tone.opacity(0.85), tone], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(SRPressStyle())
        .disabled(!store.canVote)
        .accessibilityLabel(approve ? "Approve" : "Reject")
        .accessibilityIdentifier(approve ? "mission-approve" : "mission-reject")
    }

    /// My vote is in: a sealed envelope, and who the table still waits on.
    private func sealed(_ approve: Bool) -> some View {
        let waiting = MissionRules.stillToVote(room)
        return HStack(alignment: .center, spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "envelope.fill")
                    .font(SR.Text.hero(34))
                    .foregroundStyle(MissionPalette.manilaDeep)
                Image(systemName: approve ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(approve ? MissionPalette.yes : MissionPalette.no))
                    .offset(x: 6, y: 6)
            }
            .tablePopIn()
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Label(approve ? "You voted to approve." : "You voted to reject.",
                      systemImage: approve ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .labelStyle(.titleOnly)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                    .accessibilityIdentifier("mission-my-vote")
                Text(waiting == 0 ? "Counting…" : "Waiting for \(waiting) more. Votes show when everyone is in.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Teams turned down in a row, as pips: the last one is the spies' win.
struct MissionRejectionMeter: View {
    let state: MissionState?

    var body: some View {
        if let state, state.rejections > 0 {
            let danger = state.rejections >= state.maxRejections - 1
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(0..<max(state.maxRejections, 1), id: \.self) { index in
                        pip(index: index, state: state)
                    }
                }
                .accessibilityHidden(true)
                Text("\(state.rejections) of \(state.maxRejections) teams turned down in a row. \(state.maxRejections) and the spies win.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(danger ? SR.error : SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mission-rejections")
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                    .fill(danger ? MissionPalette.no.opacity(0.12) : Color.clear)
            )
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        }
    }

    private func pip(index: Int, state: MissionState) -> some View {
        let filled = index < state.rejections
        let last = index == state.maxRejections - 1
        return ZStack {
            Capsule().fill(filled ? MissionPalette.no : SR.line)
            if last {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(filled ? Color.white : SR.inkMuted)
            }
        }
        .frame(height: 14)
    }
}

// MARK: The tally

struct MissionTallyPanel: View {
    let room: GameRoom

    var body: some View {
        if let t = room.mission?.lastTally {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: t.approved ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(SR.Text.hero(30))
                        .foregroundStyle(t.approved ? MissionPalette.yes : MissionPalette.no)
                        .tablePopIn()
                        .accessibilityHidden(true)
                    Text(t.approved ? "The team goes." : "Turned down. The lead passes on.")
                        .font(SR.Text.display(20))
                        .foregroundStyle(t.approved ? MissionPalette.yes : MissionPalette.no)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 12) {
                    voteColumn("Approve", t.approve, auto: t.auto, tone: MissionPalette.yes, icon: "hand.thumbsup.fill")
                    voteColumn("Reject", t.reject, auto: t.auto, tone: MissionPalette.no, icon: "hand.thumbsdown.fill")
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("mission-tally")
        }
    }

    private func voteColumn(_ title: String, _ ids: [String], auto: [String], tone: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(title.uppercased()) · \(ids.count)", systemImage: icon)
                .font(SR.Text.label(13))
                .tracking(1)
                .foregroundStyle(tone)
            if ids.isEmpty {
                Text("Nobody")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            } else {
                ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                    HStack(spacing: 8) {
                        GameInitial(name: room.name(of: id), filled: true, tone: tone, side: 26)
                        Text(MissionNames.who(id, in: room) + (auto.contains(id) ? " (timed out)" : ""))
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .tablePopIn(delay: 0.05 * Double(index))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(tone.opacity(0.10))
        )
    }
}

// MARK: The mission

/// A mission card's face: a big symbol on its colour, the word under it.
struct MissionCardFace: View {
    let sabotage: Bool
    /// The small copy at the outcome: the symbol only.
    var small = false

    var body: some View {
        let tone = sabotage ? MissionPalette.no : MissionPalette.yes
        VStack(spacing: small ? 0 : 10) {
            Image(systemName: sabotage ? "bolt.slash.fill" : "checkmark.seal.fill")
                .font(small ? Font.system(size: 22, weight: .bold) : SR.Text.hero(38))
            if !small {
                Text(sabotage ? "SABOTAGE" : "SUCCEED")
                    .font(SR.Text.label(15))
                    .tracking(1.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: small ? 8 : 18, style: .continuous)
                .fill(LinearGradient(colors: [tone.opacity(0.82), tone], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: small ? 8 : 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: small ? 1.5 : 2)
                .padding(small ? 3 : 6)
        )
    }
}

/// A card face down: the same back for every card, so nothing shows.
struct MissionCardBack: View {
    var small = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: small ? 8 : 18, style: .continuous)
                .fill(MissionPalette.cardBack)
            RoundedRectangle(cornerRadius: small ? 8 : 18, style: .continuous)
                .strokeBorder(MissionPalette.manila.opacity(0.6), lineWidth: small ? 1.5 : 2)
                .padding(small ? 3 : 6)
            Image(systemName: "eye.slash.fill")
                .font(small ? Font.system(size: 16, weight: .bold) : SR.Text.hero(30))
                .foregroundStyle(MissionPalette.manila.opacity(0.75))
        }
    }
}

struct MissionCardsPanel: View {
    let room: GameRoom
    @ObservedObject var store: MissionStore

    private var state: MissionState? { room.mission }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MissionTeamLine(room: room)
            MissionClockBar(room: room, store: store, totalMs: MissionClockBar.total(state, phase: .mission))
            if store.onTeam {
                if let card = state?.secret?.card {
                    played(card)
                } else {
                    // Both cards and one footnote on every team member's phone:
                    // the layout must not show which side you are on. A crew tap
                    // on Sabotage does nothing (and the server refuses it anyway).
                    HStack(spacing: 12) {
                        playButton(sabotage: true)
                        playButton(sabotage: false)
                    }
                    .frame(height: 140)
                    Text(MissionRules.missionFootnote)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            cardsIn
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private func playButton(sabotage: Bool) -> some View {
        Button { store.play(sabotage: sabotage) } label: {
            MissionCardFace(sabotage: sabotage)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(SRPressStyle())
        .disabled(!store.canPlay)
        .accessibilityLabel(sabotage ? "Sabotage" : "Succeed")
        .accessibilityIdentifier(sabotage ? "mission-sabotage" : "mission-succeed")
    }

    /// My card is down, face down.
    private func played(_ card: String) -> some View {
        HStack(spacing: 14) {
            MissionCardBack(small: true)
                .frame(width: 48, height: 68)
                .tablePopIn()
                .accessibilityHidden(true)
            Label(card == "sabotage" ? "You played Sabotage." : "You played Succeed.",
                  systemImage: card == "sabotage" ? "bolt.slash.fill" : "checkmark.seal.fill")
                .font(SR.Text.title(16))
                .foregroundStyle(SR.ink)
                .accessibilityIdentifier("mission-my-card")
            Spacer(minLength: 0)
        }
    }

    /// Cards in so far, as face-down cards, and what fails it.
    private var cardsIn: some View {
        let cards = MissionRules.cardsIn(room)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<max(cards.of, 0), id: \.self) { index in
                    if index < cards.played {
                        MissionCardBack(small: true)
                            .frame(width: 28, height: 40)
                            .tablePopIn()
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(SR.inkGhost, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .frame(width: 28, height: 40)
                    }
                }
            }
            .accessibilityHidden(true)
            Text("\(cards.played) of \(cards.of) cards in. \(state.map { $0.needed == 1 ? "One sabotage fails it." : "\($0.needed) sabotages fail it." } ?? "")")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .accessibilityIdentifier("mission-cards-in")
        }
    }
}

// MARK: The outcome

/// The team's cards turned over one by one, then the stamp — and a success or
/// a buzz to feel it.
struct MissionOutcomePanel: View {
    let room: GameRoom

    var body: some View {
        if let o = room.mission?.lastOutcome {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    HStack(spacing: 8) {
                        ForEach(0..<o.team.count, id: \.self) { index in
                            MissionFlipCard(sabotage: index >= o.team.count - o.sabotages, index: index)
                        }
                    }
                    stamp(o)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 96)
                .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(o.sabotages)")
                        .font(SR.Text.hero(48))
                        .foregroundStyle(o.succeeded ? MissionPalette.yes : MissionPalette.no)
                        .monospacedDigit()
                    Text(o.sabotages == 1 ? "SABOTAGE" : "SABOTAGES")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                    Spacer(minLength: 0)
                }
                Text(MissionRules.outcomeLine(o))
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Team: \(GameNames.list(o.team.map { MissionNames.who($0, in: room) }))")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("mission-outcome")
            .task(id: o.mission) {
                // Felt as the stamp lands, after the cards have turned.
                let wait = 0.35 + 0.12 * Double(o.team.count)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if o.succeeded { SRHaptic.ok() } else { SRHaptic.bad() }
            }
        }
    }

    private func stamp(_ o: MissionOutcome) -> some View {
        let tone = o.succeeded ? MissionPalette.yes : MissionPalette.stamp
        return Text(o.succeeded ? "SUCCESS" : "SABOTAGED")
            .font(SR.Text.hero(28))
            .tracking(3)
            .foregroundStyle(tone)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SR.surface.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tone, lineWidth: 3.5))
            .rotationEffect(.degrees(-9))
            .tablePopIn(delay: 0.3 + 0.12 * Double(o.team.count))
    }
}

/// One card at the outcome, turning from its back to its face.
struct MissionFlipCard: View {
    let sabotage: Bool
    let index: Int
    @State private var flipped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MissionCardBack(small: true)
                .opacity(flipped ? 0 : 1)
            MissionCardFace(sabotage: sabotage, small: true)
                .opacity(flipped ? 1 : 0)
        }
        .frame(width: 52, height: 74)
        .rotation3DEffect(.degrees(flipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
        .onAppear {
            guard !flipped else { return }
            if reduceMotion {
                flipped = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15 + 0.12 * Double(index))) {
                    flipped = true
                }
            }
        }
    }
}

// MARK: The hunt

struct MissionHuntPanel: View {
    let room: GameRoom
    @ObservedObject var store: MissionStore

    private var state: MissionState? { room.mission }

    var body: some View {
        let spies = (state?.seatsById ?? []).filter { $0.side == .spies }.map(\.id)
        VStack(alignment: .leading, spacing: 14) {
            MissionClockBar(room: room, store: store, totalMs: MissionClockBar.total(state, phase: .hunt))
            HStack(spacing: -8) {
                ForEach(spies, id: \.self) { id in
                    GameInitial(name: room.name(of: id), filled: true, tone: MissionPalette.spies, side: 40)
                        .overlay(Circle().strokeBorder(SR.surface, lineWidth: 2))
                }
            }
            .accessibilityHidden(true)
            Text("The crew won three missions. The spies are \(GameNames.list(spies.map { MissionNames.who($0, in: room) })) — they choose together, out loud, and the Tracker (\(MissionNames.who(state?.trackerId, in: room))) names one of the crew. Find the Lookout and the spies win.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.amTracker {
                trackerPicker(spies: spies)
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private func trackerPicker(spies: [String]) -> some View {
        let crew = room.players.filter { state?.seat($0.id)?.seated == true && !spies.contains($0.id) }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(crew) { player in
                suspectRow(player)
            }
            Button { store.guess() } label: {
                SRButtonLabel(title: store.suspect.map { "Name \(room.name(of: $0))" } ?? "Pick someone", icon: "scope", fill: true)
                    .frame(minHeight: 56)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(store.suspect == nil || store.sending)
            .accessibilityIdentifier("mission-guess")
        }
    }

    private func suspectRow(_ player: GamePlayer) -> some View {
        let on = store.suspect == player.id
        return Button { store.pickSuspect(player.id) } label: {
            HStack(spacing: 12) {
                GameInitial(name: player.name, filled: on, tone: MissionPalette.spies, side: 36)
                Text(player.name)
                    .font(SR.Text.title(18))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: on ? "scope" : "circle")
                    .font(SR.Text.title(24))
                    .foregroundStyle(on ? MissionPalette.spies : SR.inkGhost)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                    .fill(on ? MissionPalette.spies.opacity(0.12) : SR.surface.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                    .strokeBorder(on ? MissionPalette.spies : SR.line, lineWidth: on ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("mission-suspect-\(player.id)")
    }
}

// MARK: The table

struct MissionSeatsTable: View {
    let room: GameRoom
    @ObservedObject var store: MissionStore

    private var state: MissionState? { room.mission }
    private var phase: MissionPhase { MissionScreenPhase.of(room) }

    var body: some View {
        let seated = room.players.filter { state?.seat($0.id)?.seated == true }
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "The table")
            VStack(spacing: 0) {
                ForEach(Array(seated.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Divider().overlay(SR.divider) }
                    seatRow(player)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mission-seats")
    }

    private func seatRow(_ player: GamePlayer) -> some View {
        let seat = state?.seat(player.id)
        let me = player.id == room.meId
        let leads = state?.leaderId == player.id && phase != .hunt
        // Only what the whole table may see: spies are public in the hunt and at
        // the finish. The spies you know privately stay inside the held role card.
        let knownSpy = seat?.side == .spies
        return HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                GameInitial(name: me ? "You" : player.name, tone: seatTone(spy: knownSpy, leads: leads), side: 32)
                if leads {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(MissionPalette.crew))
                        .offset(x: 5, y: -5)
                }
            }
            Text(player.name + (me ? " (you)" : ""))
                .font(SR.Text.title())
                .foregroundStyle(player.joined ? SR.ink : SR.inkGhost)
                .strikethrough(!player.joined, color: SR.inkMuted)
                .lineLimit(1)
            if leads {
                tag("LEADS", tone: SR.accent)
            }
            if knownSpy {
                tag("SPY", tone: MissionPalette.spies)
            }
            Spacer(minLength: 8)
            status(player, seat: seat)
        }
        .frame(minHeight: 52)
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seatSpoken(player, seat: seat, leads: leads, spy: knownSpy))
        .accessibilityIdentifier("mission-seat-\(player.id)")
    }

    private func seatTone(spy: Bool, leads: Bool) -> Color {
        if spy { return MissionPalette.spies }
        return leads ? SR.accent : SR.accentInk
    }

    private func tag(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(SR.Text.label())
            .tracking(1)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tone))
    }

    @ViewBuilder
    private func status(_ player: GamePlayer, seat: MissionSeat?) -> some View {
        if !player.joined {
            Text("LEFT").font(SR.Text.label()).tracking(1).foregroundStyle(SR.inkMuted)
        } else if phase == .voting {
            Image(systemName: seat?.voted == true ? "envelope.fill" : "ellipsis.circle")
                .font(SR.Text.title())
                .foregroundStyle(seat?.voted == true ? MissionPalette.yes : SR.inkGhost)
                .accessibilityHidden(true)
        } else if phase == .mission, seat?.onTeam == true {
            Image(systemName: seat?.played == true ? "rectangle.portrait.fill" : "hourglass")
                .font(SR.Text.title())
                .foregroundStyle(seat?.played == true ? MissionPalette.yes : SR.inkGhost)
                .accessibilityHidden(true)
        } else if seat?.onTeam == true {
            tag("TEAM", tone: SR.accentInk)
        }
    }

    private func seatSpoken(_ player: GamePlayer, seat: MissionSeat?, leads: Bool, spy: Bool) -> String {
        var parts = [player.id == room.meId ? "You" : player.name]
        if leads { parts.append("leading") }
        if spy { parts.append("a spy") }
        if !player.joined { parts.append("left") }
        if phase == .voting { parts.append(seat?.voted == true ? "has voted" : "not voted yet") }
        if phase == .mission, seat?.onTeam == true { parts.append(seat?.played == true ? "card played" : "still to play") }
        else if seat?.onTeam == true { parts.append("on the team") }
        return parts.joined(separator: ", ")
    }
}

/// The score, then five missions along a route: each one's team size, then
/// its result once run; the current one ringed and marked NOW.
struct MissionTrack: View {
    let state: MissionState?

    var body: some View {
        VStack(spacing: 12) {
            score
            route
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Crew \(state?.crewScore ?? 0), spies \(state?.spyScore ?? 0). Mission \(state?.mission ?? 1) of 5.")
        .accessibilityIdentifier("mission-track")
    }

    private var score: some View {
        HStack(alignment: .center, spacing: 10) {
            side("CREW", value: state?.crewScore ?? 0, tone: MissionPalette.crew, icon: "person.3.fill", leading: true)
            Text("FIRST TO 3")
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            side("SPIES", value: state?.spyScore ?? 0, tone: MissionPalette.spies, icon: "eye.slash.fill", leading: false)
        }
    }

    private func side(_ title: String, value: Int, tone: Color, icon: String, leading: Bool) -> some View {
        HStack(spacing: 8) {
            if !leading { Spacer(minLength: 0) }
            if leading {
                Image(systemName: icon).font(SR.Text.title()).foregroundStyle(tone)
            }
            VStack(alignment: leading ? .leading : .trailing, spacing: 0) {
                Text("\(value)")
                    .font(SR.Text.figure(30))
                    .foregroundStyle(tone)
                    .monospacedDigit()
                    .srNumeric(Double(value))
                Text(title)
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.inkMuted)
            }
            if !leading {
                Image(systemName: icon).font(SR.Text.title()).foregroundStyle(tone)
            }
            if leading { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }

    private var route: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(SR.line)
                .frame(height: 4)
                .padding(.horizontal, 30)
                .padding(.top, 22)
            HStack(spacing: 4) {
                ForEach(0..<MissionRules.missions, id: \.self) { i in
                    node(i)
                }
            }
        }
    }

    private func node(_ i: Int) -> some View {
        let sizes = state?.teamSizes ?? []
        let outcome = state?.missions.first { $0.mission == i + 1 }
        let current = outcome == nil && state?.mission == i + 1
        let needsTwo = (state?.sabotagesNeeded.indices.contains(i) ?? false) && state?.sabotagesNeeded[i] == 2
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(nodeFill(outcome))
                Circle()
                    .strokeBorder(current ? SR.accent : SR.ink.opacity(0.15), lineWidth: current ? 3.5 : 1)
                if let outcome {
                    Image(systemName: outcome.succeeded ? "checkmark" : "xmark")
                        .font(SR.Text.title(18))
                        .foregroundStyle(Color.white)
                } else {
                    Text(sizes.indices.contains(i) ? "\(sizes[i])" : "–")
                        .font(SR.Text.figure(18))
                        .foregroundStyle(current ? SR.accent : SR.ink)
                }
            }
            .frame(width: 48, height: 48)
            .scaleEffect(current ? 1.06 : 1)
            Text(caption(current: current, needsTwo: needsTwo))
                .font(SR.Text.label())
                .foregroundStyle(current ? SR.accent : SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func nodeFill(_ outcome: MissionOutcome?) -> Color {
        guard let outcome else { return SR.surface }
        return outcome.succeeded ? MissionPalette.crew : MissionPalette.spies
    }

    private func caption(current: Bool, needsTwo: Bool) -> String {
        if needsTwo { return "2 TO FAIL" }
        return current ? "NOW" : " "
    }
}

// MARK: - Finished

struct MissionFinished: View {
    let room: GameRoom
    @ObservedObject var store: MissionStore
    let done: () -> Void
    @State private var record: TableGameRecord?

    private var state: MissionState? { room.mission }
    private var iWon: Bool { room.winnerIds.contains(room.meId) }
    private var gameKey: String { TableGameKey.finished(roomId: room.id, startedAt: room.startedAt) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Secret Mission · crew \(state?.crewScore ?? 0), spies \(state?.spyScore ?? 0)",
                             title: MissionRules.headline(state?.result, mySide: state?.secret?.side),
                             strap: MissionRules.reasonLine(state?.result) { $0 == room.meId ? "you" : room.name(of: $0) })
                    .accessibilityIdentifier("mission-outcome-headline")
                MissionWinnerBanner(result: state?.result, mySide: state?.secret?.side)
                MissionTrack(state: state)
                GameRecordLine(room: room)
                whoWasWho
                GameFinishedButtons(room: room, store: store, prefix: "mission", done: done)
                if let record {
                    TableRecordCard(record: record, gameKey: gameKey, bestLabel: nil, id: "mission-record")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay {
            if iWon { TableCelebration(colours: TableCheer.colours, bursts: 7, duration: 3.4, seed: 23) }
        }
        .accessibilityIdentifier("mission-finished")
        .onAppear {
            if iWon { SRHaptic.ok() }
            noteRecord()
        }
    }

    private var whoWasWho: some View {
        let seated = room.players.filter { state?.seat($0.id)?.seated == true }
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Who was who")
            VStack(spacing: 0) {
                ForEach(Array(seated.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Divider().overlay(SR.divider) }
                    roleRow(player)
                        .tablePopIn(delay: 0.05 * Double(index))
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mission-standings")
    }

    private func roleRow(_ player: GamePlayer) -> some View {
        let seat = state?.seat(player.id)
        let role = seat?.role
        let won = room.winnerIds.contains(player.id)
        let tone = MissionPalette.side(role?.side)
        return HStack(spacing: 12) {
            Image(systemName: role?.icon ?? "person.fill")
                .font(SR.Text.title())
                .foregroundStyle(Color.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(tone))
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name + (player.id == room.meId ? " (you)" : ""))
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text((role?.title ?? "Crew") + (player.joined ? "" : " · left"))
                    .font(SR.Text.secondary())
                    .foregroundStyle(tone)
            }
            Spacer(minLength: 8)
            if won {
                Image(systemName: "crown.fill")
                    .font(SR.Text.title())
                    .foregroundStyle(Color(hex: 0xE9A800))
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 56)
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(player.id == room.meId ? "You" : player.name): \(role?.title ?? "crew")\(won ? ", won" : "")\(player.joined ? "" : ", left")")
        .accessibilityIdentifier("mission-who-\(player.id)")
    }

    private func noteRecord() {
        guard record == nil, state?.seat(room.meId)?.seated == true else { return }
        let book = TableGameBestStore(gameId: GameKind.mission.rawValue, persists: !SRDemo.isOn)
        record = book.note(variant: GameKind.mission.rawValue, key: gameKey, won: iWon, score: nil)
    }
}

/// The winning side, as a slab in its colour.
struct MissionWinnerBanner: View {
    let result: MissionResult?
    let mySide: MissionSide?

    var body: some View {
        if let winner = result?.winner {
            let tone = MissionPalette.side(winner)
            HStack(spacing: 16) {
                Image(systemName: winner == .spies ? "eye.slash.fill" : "person.3.fill")
                    .font(SR.Text.hero(30))
                    .foregroundStyle(tone)
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(Color.white))
                    .tablePopIn()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mySide.map { $0 == winner ? "YOUR SIDE" : "THE OTHER SIDE" } ?? "THE WINNERS")
                        .font(SR.Text.label(13))
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(Color.white.opacity(0.85))
                    Text("\(winner.title) win")
                        .font(SR.Text.hero(30))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
            }
            .padding(SR.cardPadding + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .fill(LinearGradient(colors: [tone.opacity(0.85), tone], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("mission-winner")
        }
    }
}

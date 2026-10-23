import SwiftUI
import UIKit

/// One Secret Mission room, from lobby to the last mission.
///
/// The talking happens out loud round the table; the phone holds only my
/// secret and my votes. The lobby and the 3-2-1 are every game's. Then my role
/// card, face down until I hold it (somebody may be looking over my shoulder),
/// with the spies I know. Each round: the mission track and the rejection
/// count, then the leader's team picker, everyone's Approve / Reject, the votes
/// shown together, the team's cards (Sabotage only on a spy's phone), and the
/// count of sabotages. With the Lookout in play a crew win ends in the hunt:
/// the Tracker names one of the crew. The finish shows every role.
struct MissionScreen: View {
    let roomId: String
    @StateObject private var store: MissionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

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
    }

    private var immersive: Bool {
        guard !store.ended, let room = store.room else { return false }
        return MissionScreenPhase.of(room) == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "mission-ended", done: { dismiss() })
        } else if let room = store.room {
            switch MissionScreenPhase.of(room) {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "mission", done: { dismiss() },
                          panel: AnyView(MissionTableCard(room: room)),
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
            ProgressView()
                .tint(SR.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
        }
    }
}

// MARK: - Lobby

/// The table in the lobby: crew and spies at this size, which roles the level
/// adds, and how many more people are needed.
struct MissionTableCard: View {
    let room: GameRoom

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "eye.slash.fill")
                .font(SR.Text.display(26))
                .foregroundStyle(SR.accent)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(MissionSettings.about(room.difficulty).uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text("Crew against spies")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(MissionRules.tableLine(players: room.playing.count))
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
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

// MARK: - My role

/// My role, face down until held: a card nobody beside me can read by accident.
struct MissionRoleCard: View {
    let room: GameRoom
    @State private var shown = false
    @State private var held = false

    private var secret: MissionSecret? { room.mission?.secret }

    var body: some View {
        let visible = shown || held
        VStack(alignment: .leading, spacing: 10) {
            if let secret {
                if visible {
                    HStack(spacing: 12) {
                        Image(systemName: secret.role.icon)
                            .font(SR.Text.display(26))
                            .foregroundStyle(secret.side == .spies ? SR.error : SR.good)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(secret.side == .spies ? "SPIES" : "CREW")
                                .font(SR.Text.label())
                                .tracking(SR.kickerTracking)
                                .foregroundStyle(secret.side == .spies ? SR.error : SR.good)
                            Text(secret.role.title)
                                .font(SR.Text.hero(30))
                                .foregroundStyle(SR.ink)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(secret.role.brief)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !secret.spies.isEmpty {
                        Text((secret.role == .lookout ? "The spies: " : "Your fellow spies: ")
                             + GameNames.list(secret.spies.map { room.name(of: $0) }))
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("mission-known-spies")
                    } else if secret.side == .crew {
                        Text("You don't know who anyone is.")
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.inkMuted)
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .font(SR.Text.display(22))
                            .foregroundStyle(SR.paper.opacity(0.85))
                        Text("Hold to see your role")
                            .font(SR.Text.title())
                            .foregroundStyle(SR.paper)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 64)
                }
            } else {
                Text("You are watching this one: no role.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(visible || secret == nil ? SR.paper : SR.accentDeep)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(SR.ink.opacity(0.12), lineWidth: 1)
        )
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
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(store.amReady || store.sending || room.me?.joined != true)
                .accessibilityIdentifier("mission-ready")
                let seats = room.mission?.seatsById.filter(\.seated) ?? []
                Text("\(seats.filter(\.ready).count) of \(seats.count) ready")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .frame(maxWidth: .infinity)
                if let rule = room.mission?.rule {
                    Text(rule)
                        .font(SR.Text.mono())
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
                panel
                if let refusal = store.refusal {
                    Label(refusal, systemImage: "exclamationmark.circle")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("mission-refusal")
                }
                MissionRoleCard(room: room)
                table
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("mission-\(phase.rawValue)")
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SECRET MISSION · \(phase == .hunt ? "THE HUNT" : "MISSION \(state?.mission ?? 1) OF 5") · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.accent)
            Text(headline)
                .font(SR.Text.display(24))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mission-headline")
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

    // MARK: The panel for this phase

    @ViewBuilder
    private var panel: some View {
        switch phase {
        case .proposing: proposing
        case .voting: voting
        case .tally: tally
        case .mission: missionPanel
        case .outcome: outcome
        case .hunt: hunt
        default: EmptyView()
        }
    }

    private var clock: some View {
        let total: Double
        switch phase {
        case .proposing: total = state?.proposeMs ?? 90_000
        case .voting: total = state?.voteMs ?? 45_000
        case .mission: total = state?.missionMs ?? 30_000
        case .hunt: total = state?.huntMs ?? 90_000
        default: total = 0
        }
        return MissionClockBar(room: room, store: store, totalMs: total)
    }

    private var proposing: some View {
        VStack(alignment: .leading, spacing: 12) {
            clock
            if store.amLeader {
                SRSectionLabel(text: "Your team", trailing: "\(store.picked.count) of \(state?.teamSize ?? 0)")
                VStack(spacing: 0) {
                    let seated = room.players.filter { state?.seat($0.id)?.seated == true }
                    ForEach(Array(seated.enumerated()), id: \.element.id) { index, player in
                        if index > 0 { Divider().overlay(SR.divider) }
                        pickRow(player)
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 6)
                .srGlassCard(.paper)
                Button { store.propose() } label: {
                    SRButtonLabel(title: "Propose this team", icon: "paperplane.fill", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(!store.canPropose)
                .accessibilityIdentifier("mission-propose")
                Text("Talk it over out loud first. If you run out of time, a team is picked for you.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Argue for who should go. The team goes to a vote when \(who(state?.leaderId)) proposes it.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private func pickRow(_ player: GamePlayer) -> some View {
        let on = store.picked.contains(player.id)
        return Button { store.toggle(player.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(SR.Text.title())
                    .foregroundStyle(on ? SR.accent : SR.inkGhost)
                Text(player.name + (player.id == room.meId ? " (you)" : ""))
                    .font(SR.Text.title())
                    .foregroundStyle(player.joined ? SR.ink : SR.inkMuted)
                Spacer(minLength: 8)
                if !player.joined {
                    Text("LEFT").font(SR.Text.label()).tracking(1).foregroundStyle(SR.inkMuted)
                }
            }
            .frame(minHeight: SR.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.id == room.meId ? "You" : player.name)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("mission-pick-\(player.id)")
    }

    private var teamLine: some View {
        let team = state?.team ?? []
        return VStack(alignment: .leading, spacing: 6) {
            SRSectionLabel(text: "The team", trailing: state?.autoTeam == true ? "Picked by the clock" : "\(who(state?.leaderId)) leads")
            Text(GameNames.list(team.map(who)))
                .font(SR.Text.display(20))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mission-team")
        }
    }

    private var voting: some View {
        VStack(alignment: .leading, spacing: 12) {
            teamLine
            clock
            if let mine = state?.secret?.vote {
                Label(mine ? "You voted to approve." : "You voted to reject.", systemImage: mine ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .accessibilityIdentifier("mission-my-vote")
                let waiting = MissionRules.stillToVote(room)
                Text(waiting == 0 ? "Counting…" : "Waiting for \(waiting) more. Votes show when everyone is in.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            } else if store.canVote {
                HStack(spacing: 10) {
                    Button { store.vote(approve: false) } label: {
                        SRButtonLabel(title: "Reject", icon: "hand.thumbsdown.fill", fill: true)
                    }
                    .srButton(.regular)
                    .controlSize(.large)
                    .accessibilityIdentifier("mission-reject")
                    Button { store.vote(approve: true) } label: {
                        SRButtonLabel(title: "Approve", icon: "hand.thumbsup.fill", fill: true)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .accessibilityIdentifier("mission-approve")
                }
                Text("Everyone votes at once; nobody sees a vote until the last is in. No vote in time counts as approve.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            rejectionsLine
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    @ViewBuilder
    private var rejectionsLine: some View {
        if let state, state.rejections > 0 {
            Text("\(state.rejections) of \(state.maxRejections) teams turned down in a row. \(state.maxRejections) and the spies win.")
                .font(SR.Text.mono())
                .foregroundStyle(state.rejections >= state.maxRejections - 1 ? SR.error : SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mission-rejections")
        }
    }

    @ViewBuilder
    private var tally: some View {
        if let t = state?.lastTally {
            VStack(alignment: .leading, spacing: 10) {
                Text(t.approved ? "The team goes." : "Turned down. The lead passes on.")
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(t.approved ? SR.good : SR.error)
                voteList("Approve", t.approve, auto: t.auto, tone: SR.good)
                voteList("Reject", t.reject, auto: t.auto, tone: SR.error)
                rejectionsLine
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("mission-tally")
        }
    }

    private func voteList(_ title: String, _ ids: [String], auto: [String], tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title.uppercased()) · \(ids.count)")
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(tone)
            Text(ids.isEmpty ? "Nobody" : GameNames.list(ids.map { who($0) + (auto.contains($0) ? " (timed out)" : "") }))
                .font(SR.Text.secondary())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var missionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            teamLine
            clock
            if store.onTeam {
                if let card = state?.secret?.card {
                    Label(card == "sabotage" ? "You played Sabotage." : "You played Succeed.",
                          systemImage: card == "sabotage" ? "bolt.slash.fill" : "checkmark.seal.fill")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.ink)
                        .accessibilityIdentifier("mission-my-card")
                } else {
                    // Both buttons and one footnote on every team member's phone:
                    // the layout must not show which side you are on. A crew tap
                    // on Sabotage does nothing (and the server refuses it anyway).
                    HStack(spacing: 10) {
                        Button { store.play(sabotage: true) } label: {
                            SRButtonLabel(title: "Sabotage", icon: "bolt.slash.fill", fill: true)
                        }
                        .srButton(.regular)
                        .controlSize(.large)
                        .disabled(!store.canPlay)
                        .accessibilityIdentifier("mission-sabotage")
                        Button { store.play(sabotage: false) } label: {
                            SRButtonLabel(title: "Succeed", icon: "checkmark.seal.fill", fill: true)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .disabled(!store.canPlay)
                        .accessibilityIdentifier("mission-succeed")
                    }
                    Text(MissionRules.missionFootnote)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            let cards = MissionRules.cardsIn(room)
            Text("\(cards.played) of \(cards.of) cards in. \(state.map { $0.needed == 1 ? "One sabotage fails it." : "\($0.needed) sabotages fail it." } ?? "")")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .accessibilityIdentifier("mission-cards-in")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    @ViewBuilder
    private var outcome: some View {
        if let o = state?.lastOutcome {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(o.sabotages)")
                        .font(SR.Text.hero(48))
                        .foregroundStyle(o.succeeded ? SR.good : SR.error)
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
                Text("Team: \(GameNames.list(o.team.map(who)))")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("mission-outcome")
        }
    }

    private var hunt: some View {
        VStack(alignment: .leading, spacing: 12) {
            clock
            let spies = (state?.seatsById ?? []).filter { $0.side == .spies }.map(\.id)
            Text("The crew won three missions. The spies are \(GameNames.list(spies.map(who))) — they choose together, out loud, and the Tracker (\(who(state?.trackerId))) names one of the crew. Find the Lookout and the spies win.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.amTracker {
                VStack(spacing: 0) {
                    let crew = room.players.filter { state?.seat($0.id)?.seated == true && !spies.contains($0.id) }
                    ForEach(Array(crew.enumerated()), id: \.element.id) { index, player in
                        if index > 0 { Divider().overlay(SR.divider) }
                        Button { store.pickSuspect(player.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: store.suspect == player.id ? "scope" : "circle")
                                    .font(SR.Text.title())
                                    .foregroundStyle(store.suspect == player.id ? SR.error : SR.inkGhost)
                                Text(player.name)
                                    .font(SR.Text.title())
                                    .foregroundStyle(SR.ink)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: SR.tapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(store.suspect == player.id ? .isSelected : [])
                        .accessibilityIdentifier("mission-suspect-\(player.id)")
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 6)
                .srGlassCard(.paper)
                Button { store.guess() } label: {
                    SRButtonLabel(title: store.suspect.map { "Name \(room.name(of: $0))" } ?? "Pick someone", icon: "scope", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(store.suspect == nil || store.sending)
                .accessibilityIdentifier("mission-guess")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    // MARK: The table

    private var table: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "The table")
            VStack(spacing: 0) {
                let seated = room.players.filter { state?.seat($0.id)?.seated == true }
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
            GameInitial(name: me ? "You" : player.name, tone: leads ? SR.accent : SR.accentInk)
            Text(player.name + (me ? " (you)" : ""))
                .font(SR.Text.title())
                .foregroundStyle(player.joined ? SR.ink : SR.inkGhost)
                .strikethrough(!player.joined, color: SR.inkMuted)
                .lineLimit(1)
            if leads {
                Text("LEADS").font(SR.Text.label()).tracking(1).foregroundStyle(SR.accent)
            }
            if knownSpy {
                Text("SPY").font(SR.Text.label()).tracking(1).foregroundStyle(SR.error)
            }
            Spacer(minLength: 8)
            if !player.joined {
                Text("LEFT").font(SR.Text.label()).tracking(1).foregroundStyle(SR.inkMuted)
            } else if phase == .voting {
                Image(systemName: seat?.voted == true ? "checkmark.circle.fill" : "ellipsis.circle")
                    .foregroundStyle(seat?.voted == true ? SR.good : SR.inkGhost)
                    .accessibilityHidden(true)
            } else if phase == .mission, seat?.onTeam == true {
                Image(systemName: seat?.played == true ? "checkmark.seal.fill" : "hourglass")
                    .foregroundStyle(seat?.played == true ? SR.good : SR.inkGhost)
                    .accessibilityHidden(true)
            } else if seat?.onTeam == true {
                Text("TEAM").font(SR.Text.label()).tracking(1).foregroundStyle(SR.accentInk)
            }
        }
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seatSpoken(player, seat: seat, leads: leads, spy: knownSpy))
        .accessibilityIdentifier("mission-seat-\(player.id)")
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

/// Five missions in a row: each one's team size, then its result once run;
/// the current one ringed.
struct MissionTrack: View {
    let state: MissionState?

    var body: some View {
        let sizes = state?.teamSizes ?? []
        HStack(spacing: 8) {
            ForEach(0..<MissionRules.missions, id: \.self) { i in
                let outcome = state?.missions.first { $0.mission == i + 1 }
                let current = outcome == nil && state?.mission == i + 1
                let needsTwo = (state?.sabotagesNeeded.indices.contains(i) ?? false) && state?.sabotagesNeeded[i] == 2
                VStack(spacing: 2) {
                    ZStack {
                        Circle()
                            .fill(outcome.map { $0.succeeded ? SR.good : SR.error } ?? SR.paper)
                        Circle()
                            .strokeBorder(current ? SR.accent : SR.ink.opacity(0.15), lineWidth: current ? 3 : 1)
                        if let outcome {
                            Image(systemName: outcome.succeeded ? "checkmark" : "xmark")
                                .font(SR.Text.title())
                                .foregroundStyle(SR.paper)
                        } else {
                            Text(sizes.indices.contains(i) ? "\(sizes[i])" : "–")
                                .font(SR.Text.figure(18))
                                .foregroundStyle(SR.ink)
                        }
                    }
                    .frame(width: 44, height: 44)
                    Text(needsTwo ? "2 TO FAIL" : " ")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Crew \(state?.crewScore ?? 0), spies \(state?.spyScore ?? 0). Mission \(state?.mission ?? 1) of 5.")
        .accessibilityIdentifier("mission-track")
    }
}

/// A clock running out: ticks, not an animation, so the app can go idle.
struct MissionClockBar: View {
    let room: GameRoom
    @ObservedObject var store: MissionStore
    let totalMs: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let left = CGFloat(MissionRules.timeLeft(endsAt: room.phaseEndsAt, totalMs: totalMs, now: store.serverNow()))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.line)
                    Capsule()
                        .fill(left < 0.17 ? SR.error : left < 0.34 ? SR.accent : SR.good)
                        .frame(width: geo.size.width * left)
                }
            }
            .frame(height: 5)
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("mission-clock")
    }
}

// MARK: - Finished

struct MissionFinished: View {
    let room: GameRoom
    @ObservedObject var store: MissionStore
    let done: () -> Void

    private var state: MissionState? { room.mission }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Secret Mission · crew \(state?.crewScore ?? 0), spies \(state?.spyScore ?? 0)",
                             title: MissionRules.headline(state?.result, mySide: state?.secret?.side),
                             strap: MissionRules.reasonLine(state?.result) { $0 == room.meId ? "you" : room.name(of: $0) })
                    .accessibilityIdentifier("mission-outcome-headline")
                MissionTrack(state: state)
                GameRecordLine(room: room)
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: "Who was who")
                    VStack(spacing: 0) {
                        let seated = room.players.filter { state?.seat($0.id)?.seated == true }
                        ForEach(Array(seated.enumerated()), id: \.element.id) { index, player in
                            if index > 0 { Divider().overlay(SR.divider) }
                            roleRow(player)
                        }
                    }
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 6)
                    .srGlassCard(.paper)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("mission-standings")
                GameFinishedButtons(room: room, store: store, prefix: "mission", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("mission-finished")
        .onAppear { if room.winnerIds.contains(room.meId) { SRHaptic.ok() } }
    }

    private func roleRow(_ player: GamePlayer) -> some View {
        let seat = state?.seat(player.id)
        let role = seat?.role
        let won = room.winnerIds.contains(player.id)
        let spy = role?.side == .spies
        return HStack(spacing: 12) {
            Image(systemName: role?.icon ?? "person.fill")
                .font(SR.Text.title())
                .foregroundStyle(spy ? SR.error : SR.good)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name + (player.id == room.meId ? " (you)" : ""))
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text((role?.title ?? "Crew") + (player.joined ? "" : " · left"))
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 8)
            if won {
                Image(systemName: "crown.fill")
                    .foregroundStyle(SR.accent)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(player.id == room.meId ? "You" : player.name): \(role?.title ?? "crew")\(won ? ", won" : "")\(player.joined ? "" : ", left")")
        .accessibilityIdentifier("mission-who-\(player.id)")
    }
}

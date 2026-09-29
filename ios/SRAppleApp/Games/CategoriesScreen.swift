import SwiftUI
import UIKit

/// One Categories room, from lobby to the final table.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the round the host picked — card size and clock — as the lobby's panel.
/// Playing is the letter, big, over the card: one field per category, each
/// warning (never refusing) when its answer doesn't start with the letter.
/// Everyone else is a name and how many lines they have filled. The review
/// reveals every answer, judged, category by category; tapping somebody
/// else's vetoes it. The finish is the table and the same card, settled.
struct CategoriesScreen: View {
    let roomId: String
    @StateObject private var store: CategoriesStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: CategoriesStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Categories")
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
        guard !store.ended, let phase = store.room?.phase else { return false }
        return phase == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "categories-ended", done: { dismiss() })
        } else if let room = store.room {
            switch room.phase {
            case .lobby, .unknown, .armed, .result, .question, .reveal, .show, .input:
                GameLobby(room: room, store: store, prefix: "categories", done: { dismiss() },
                          panel: AnyView(CategoriesRoundCard(room: room)))
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "One answer a category, every one starting with the same letter.",
                                  id: "categories-countdown")
            case .playing:
                CategoriesPlaying(room: room, store: store)
            case .review:
                CategoriesReview(room: room, store: store)
            case .finished:
                CategoriesFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "categories-ended", done: { dismiss() })
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

/// The round the host picked, in the lobby: a blank card beside size and clock.
struct CategoriesRoundCard: View {
    let room: GameRoom

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            card
            VStack(alignment: .leading, spacing: 4) {
                Text(CategoriesSettings.about(room).uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text("A letter and a card")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text("Answer every category with the letter. The same answer as someone else scores nothing; the family can veto a cheeky one.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Round: \(CategoriesSettings.about(room)). Answer every category with the letter. The same answer as someone else scores nothing; the family can veto a cheeky one.")
        .accessibilityIdentifier("categories-round")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<min(room.categoryCount, 6), id: \.self) { _ in
                Capsule().fill(SR.paper.opacity(0.8)).frame(width: 36, height: 3)
            }
        }
        .padding(10)
        .frame(width: 56, height: 64, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(SR.good))
        .accessibilityHidden(true)
    }
}

// MARK: - Playing

struct CategoriesPlaying: View {
    let room: GameRoom
    @ObservedObject var store: CategoriesStore
    @FocusState private var focused: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                CategoriesTimeBar(room: room, store: store, limit: room.timeLimitMs)
                if !room.others.isEmpty {
                    CategoriesOthersStrip(room: room)
                }
                if room.me?.joined != true {
                    Text("You are not playing in this one.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
                VStack(spacing: 10) {
                    ForEach(Array((room.categories ?? []).enumerated()), id: \.offset) { index, category in
                        row(index, category)
                    }
                }
                Text("Answers save as you type. \(room.solo ? "" : "Same as someone else's scores nothing.")")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
        .accessibilityIdentifier("categories-playing")
        .onChange(of: focused) { old, _ in
            if let old { store.commit(old) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            CategoriesLetter(letter: room.letter, side: 68)
            VStack(alignment: .leading, spacing: 4) {
                Text("CATEGORIES · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text(CategoriesRules.filledLine(store.filled, of: room.categories?.count ?? room.categoryCount))
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .monospacedDigit()
                    .accessibilityLabel("\(store.filled) of \(room.categories?.count ?? room.categoryCount) answered")
                    .accessibilityIdentifier("categories-my-count")
            }
            Spacer(minLength: 8)
            WordleTimer(room: room, store: store, id: "categories-timer")
        }
    }

    private func row(_ index: Int, _ category: String) -> some View {
        let text = store.draft(index)
        let warning = CategoriesRules.warning(text, letter: room.letter)
        let count = room.categories?.count ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index + 1)")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkGhost)
                    .monospacedDigit()
                    .frame(minWidth: 18, alignment: .leading)
                Text(category)
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField(room.letter.map { "\($0.uppercased())…" } ?? "…", text: Binding(
                get: { store.draft(index) },
                set: { store.edit(index, $0) }
            ))
            .font(SR.Text.body(17))
            .foregroundStyle(SR.ink)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled(false)
            .submitLabel(index + 1 < count ? .next : .done)
            .focused($focused, equals: index)
            .onSubmit {
                store.commit(index)
                focused = index + 1 < count ? index + 1 : nil
            }
            .disabled(!store.canPlay)
            .padding(.horizontal, 12)
            .frame(minHeight: SR.tapTarget)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
            .accessibilityLabel("\(category), answer")
            .accessibilityIdentifier("categories-field-\(index)")
            if let warning {
                Label(warning, systemImage: "exclamationmark.circle")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.warn)
                    .accessibilityIdentifier("categories-warning-\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("categories-row-\(index)")
    }
}

/// The round's letter, as a tile.
struct CategoriesLetter: View {
    let letter: String?
    var side: CGFloat = 68

    var body: some View {
        Text(letter?.uppercased() ?? "?")
            .font(SR.Text.hero(side * 0.62))
            .foregroundStyle(SR.paper)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous).fill(SR.good))
            .accessibilityLabel(letter.map { "The letter \($0.uppercased())" } ?? "No letter yet")
            .accessibilityIdentifier("categories-letter")
    }
}

/// The clock running out: a bar that empties towards `phaseEndsAt` and warms as it goes.
struct CategoriesTimeBar: View {
    let room: GameRoom
    @ObservedObject var store: CategoriesStore
    let limit: Double?

    var body: some View {
        // Ticks, not an animation: a bar that is always animating keeps the app
        // from ever going idle, and UI tests then cannot read the screen.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let left = fraction
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
    }

    private var fraction: CGFloat {
        guard let end = room.phaseEndsAt, let limit, limit > 0, let now = store.serverNow() else { return 1 }
        return CGFloat(min(1, max(0, (end - now) / limit)))
    }
}

/// Everyone else while playing: a name and how many lines filled. Never the answers.
struct CategoriesOthersStrip: View {
    let room: GameRoom

    var body: some View {
        let count = room.categories?.count ?? room.categoryCount
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(room.others) { player in
                    HStack(spacing: 10) {
                        GameInitial(name: player.name, side: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                                .font(SR.Text.title(14))
                                .foregroundStyle(SR.ink)
                                .lineLimit(1)
                            Text(CategoriesRules.filledLine(player.filled, of: count))
                                .font(SR.Text.label())
                                .foregroundStyle(SR.inkSecondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(player.name), \(player.filled) of \(count) answered")
                    .accessibilityIdentifier("categories-other-\(player.id)")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("categories-others")
    }
}

// MARK: - Review

struct CategoriesReview: View {
    let room: GameRoom
    @ObservedObject var store: CategoriesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                HStack(alignment: .center, spacing: 14) {
                    CategoriesLetter(letter: room.letter, side: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REVIEW · \(room.me?.score ?? 0) SO FAR")
                            .font(SR.Text.label())
                            .tracking(SR.kickerTracking)
                            .foregroundStyle(SR.accent)
                        Text("Any cheeky ones?")
                            .font(SR.Text.display(22))
                            .foregroundStyle(SR.ink)
                    }
                    Spacer(minLength: 8)
                    WordleTimer(room: room, store: store, id: "categories-review-timer")
                }
                CategoriesTimeBar(room: room, store: store, limit: room.reviewMs)
                Text("Tap somebody else's answer to veto it; tap again to take it back. Half the others vetoing strikes it.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                CategoriesCardReview(room: room, store: store)

                doneButton
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("categories-review")
    }

    @ViewBuilder
    private var doneButton: some View {
        if room.me?.joined == true {
            if room.me?.done == true {
                let waiting = CategoriesRules.waitingOn(room).map { $0.id == room.meId ? "you" : $0.name }
                Text(waiting.isEmpty ? "Adding up…" : "Waiting on \(GameNames.list(waiting)).")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("categories-waiting")
            } else {
                Button { store.finishReview() } label: {
                    SRButtonLabel(title: "Done reviewing", icon: "checkmark", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(store.busy)
                .accessibilityIdentifier("categories-done-review")
            }
        }
    }
}

/// Every answer, category by category: who wrote what and how it was judged.
/// In the review, tapping another player's answer vetoes it.
struct CategoriesCardReview: View {
    let room: GameRoom
    @ObservedObject var store: CategoriesStore

    var body: some View {
        let people = CategoriesRules.contenders(room)
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            ForEach(Array((room.categories ?? []).enumerated()), id: \.offset) { index, category in
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: "\(index + 1) · \(category)")
                    VStack(spacing: 0) {
                        ForEach(Array(people.enumerated()), id: \.element.id) { n, person in
                            if n > 0 { Divider().overlay(SR.divider) }
                            answerRow(person, answer(of: person, at: index))
                        }
                    }
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 4)
                    .srGlassCard(.paper)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("categories-category-\(index)")
            }
        }
    }

    private func answer(of person: GamePlayer, at index: Int) -> CategoriesAnswer {
        person.categoryAnswers?.first { $0.index == index } ?? CategoriesAnswer(index: index, text: "", status: .empty)
    }

    private func answerRow(_ person: GamePlayer, _ answer: CategoriesAnswer) -> some View {
        let status = answer.status ?? .empty
        let canVeto = CategoriesRules.canVeto(answer, ownerId: person.id, room: room)
        let isMe = person.id == room.meId
        let traits: AccessibilityTraits = !canVeto ? [] : answer.vetoed ? [.isButton, .isSelected] : .isButton
        return Button {
            store.toggleVeto(owner: person, answer: answer)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                GameInitial(name: isMe ? "You" : person.name, tone: isMe ? SR.accent : SR.accentInk)
                VStack(alignment: .leading, spacing: 2) {
                    Text(answer.text.isEmpty ? "—" : answer.text)
                        .font(SR.Text.title())
                        .foregroundStyle(status.crossed || answer.text.isEmpty ? SR.inkGhost : SR.ink)
                        .strikethrough(status.crossed, color: status == .struck ? SR.error : SR.inkMuted)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if let tag = status.tag {
                            Text(tag)
                                .font(SR.Text.label())
                                .tracking(1)
                                .foregroundStyle(status == .struck ? SR.error : SR.inkMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .overlay(Capsule().strokeBorder(status == .struck ? SR.error : SR.line, lineWidth: 1))
                        }
                        if let line = CategoriesRules.vetoLine(answer), status != .wrongLetter {
                            Text(line)
                                .font(SR.Text.mono())
                                .foregroundStyle(status == .struck ? SR.error : SR.warn)
                        }
                    }
                }
                Spacer(minLength: 8)
                if canVeto {
                    Image(systemName: answer.vetoed ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(SR.Text.title())
                        .foregroundStyle(answer.vetoed ? SR.error : SR.inkGhost)
                        .accessibilityHidden(true)
                }
                Text("\(answer.points)")
                    .font(SR.Text.figure(18))
                    .foregroundStyle(answer.points > 0 ? SR.ink : SR.inkGhost)
                    .monospacedDigit()
                    .frame(minWidth: 22, alignment: .trailing)
            }
            .frame(minHeight: SR.tapTarget)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(answer.vetoed ? SR.error.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canVeto)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(person, answer, isMe: isMe))
        .accessibilityHint(canVeto ? (answer.vetoed ? "Takes your veto back" : "Vetoes it") : "")
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier("categories-answer-\(person.id)-\(answer.index)")
    }

    private func spoken(_ person: GamePlayer, _ answer: CategoriesAnswer, isMe: Bool) -> String {
        let who = isMe ? "You" : person.name
        guard !answer.text.isEmpty else { return "\(who), no answer" }
        var parts = ["\(who), \(answer.text)"]
        switch answer.status ?? .empty {
        case .shared: parts.append("shared, crossed out")
        case .wrongLetter: parts.append("wrong letter")
        case .struck: parts.append("vetoed out")
        default: break
        }
        if let line = CategoriesRules.vetoLine(answer), answer.status != .wrongLetter { parts.append(line) }
        if answer.vetoed { parts.append("you vetoed it") }
        parts.append(answer.points == 1 ? "1 point" : "\(answer.points) points")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Finished

struct CategoriesFinished: View {
    let room: GameRoom
    @ObservedObject var store: CategoriesStore
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Categories · \(room.letter?.uppercased() ?? "?") · final",
                             title: GameResults.title(room, solo: "You scored \(room.me?.score ?? 0)", none: "Nobody scored"),
                             strap: GameResults.strap(room))

                GameStandingsCard(
                    room: room,
                    label: room.solo ? "Your game" : "Standings",
                    id: "categories-standings",
                    detail: detail,
                    figure: { (text: "\($0.score)", spoken: "\($0.score) points") }
                )

                CategoriesCardReview(room: room, store: store)

                GameFinishedButtons(room: room, store: store, prefix: "categories", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("categories-finished")
        .onAppear { if room.winnerIds.contains(room.meId) { SRHaptic.ok() } }
    }

    private func detail(_ row: GameStanding) -> String {
        let count = room.categories?.count ?? room.categoryCount
        let filled = room.players.first { $0.id == row.id }?.filled ?? 0
        return "\(filled) of \(count) answered"
    }
}

import SwiftUI
import UIKit

/// One Categories room, from lobby to the final table.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the round the host picked — card size and clock — as the lobby's panel,
/// drawn as the card itself with the three rules beside it.
/// Playing is the letter, big, over the card: a ring of how many lines are
/// filled, a clock that warms and taps in the last seconds, and one field per
/// category, each badged as filled, warned (never refused) when its answer
/// doesn't start with the letter, or still to do. Everyone else is a name and
/// a little bar of how many lines they have filled. The review reveals every
/// answer, judged, category by category; tapping somebody else's vetoes it,
/// and Done rides at the foot of the screen with my score so far. The finish
/// is my score and place, my best on this phone, the table and the same card,
/// settled.
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
            CategoriesLoading()
        }
    }
}

/// Opening the room: the card art, quietly, rather than a bare spinner.
struct CategoriesLoading: View {
    var body: some View {
        VStack(spacing: 18) {
            CategoriesCardArt(lines: 5, letter: nil)
                .frame(width: 104, height: 124)
            HStack(spacing: 10) {
                ProgressView().tint(SR.accent)
                Text("Opening the card…")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srPaper()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Palette

/// The few colours Categories draws with, from the app's tokens.
enum CategoriesInk {
    /// The letter tile and the card's header strip.
    static var letter: Color { SR.good }
    /// A line filled with the right letter.
    static var done: Color { SR.good }
    /// A line warned for its letter.
    static var warned: Color { SR.warn }

    /// The clock bar: green, then violet, then red as it runs out.
    static func clock(_ left: CGFloat) -> Color {
        if left < 0.17 { return SR.error }
        if left < 0.34 { return SR.accent }
        return SR.good
    }
}

// MARK: - Lobby

/// The round the host picked, in the lobby: the card itself, drawn, beside
/// size and clock, and the three rules under it.
struct CategoriesRoundCard: View {
    let room: GameRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                CategoriesCardArt(lines: min(room.categoryCount, 6), letter: nil)
                    .frame(width: 84, height: 100)
                VStack(alignment: .leading, spacing: 6) {
                    Text(CategoriesSettings.about(room).uppercased())
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(SR.accent)
                    Text("A letter and a card")
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let each = perAnswer {
                        Text(each)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 10) {
                CategoriesRuleLine(icon: "textformat.abc", text: "A letter is drawn. Every answer starts with it.")
                CategoriesRuleLine(icon: "square.and.pencil", text: "Fill as many categories as you can before the clock runs out.")
                CategoriesRuleLine(icon: "person.2.slash", text: "The same answer as someone else scores nothing; the family can veto a cheeky one.")
            }
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Round: \(CategoriesSettings.about(room)). Answer every category with the letter. The same answer as someone else scores nothing; the family can veto a cheeky one.")
        .accessibilityIdentifier("categories-round")
    }

    /// "About 15 seconds an answer", when the clock is known.
    private var perAnswer: String? {
        guard let limit = room.timeLimitMs, room.categoryCount > 0 else { return nil }
        let each = Int((limit / 1000 / Double(room.categoryCount)).rounded())
        return "About \(each) s an answer"
    }
}

/// One rule in the lobby: an icon in a soft disc and a sentence.
struct CategoriesRuleLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(SR.Text.title(15))
                .foregroundStyle(SR.accentInk)
                .frame(width: 34, height: 34)
                .background(Circle().fill(SR.accentInk.opacity(0.12)))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
        }
    }
}

/// The card, drawn: a slightly tilted index card with a coloured header strip
/// and ruled lines, and the letter tile pinned to its corner.
struct CategoriesCardArt: View {
    let lines: Int
    let letter: String?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                // A second card behind, for depth.
                RoundedRectangle(cornerRadius: w * 0.12, style: .continuous)
                    .fill(SR.accentInk.opacity(0.18))
                    .frame(width: w * 0.86, height: h * 0.9)
                    .rotationEffect(.degrees(7))
                    .offset(x: w * 0.1, y: h * 0.06)
                card(w: w * 0.86, h: h * 0.9)
                    .rotationEffect(.degrees(-4))
                tile(side: w * 0.42)
                    .offset(x: w * 0.6, y: -h * 0.04)
            }
        }
        .accessibilityHidden(true)
    }

    private func card(w: CGFloat, h: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(CategoriesInk.letter)
                .frame(height: h * 0.2)
            VStack(alignment: .leading, spacing: h * 0.08) {
                ForEach(0..<max(1, min(lines, 6)), id: \.self) { n in
                    Capsule()
                        .fill(SR.ink.opacity(n == 0 ? 0.32 : 0.16))
                        .frame(width: w * (n % 2 == 0 ? 0.66 : 0.5), height: max(2, h * 0.035))
                }
            }
            .padding(.horizontal, w * 0.12)
            .padding(.top, h * 0.1)
            Spacer(minLength: 0)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .background(SR.surface)
        .clipShape(RoundedRectangle(cornerRadius: w * 0.12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: w * 0.12, style: .continuous).strokeBorder(SR.line, lineWidth: 1))
        .shadow(color: SR.ink.opacity(0.12), radius: 6, y: 3)
    }

    private func tile(side: CGFloat) -> some View {
        Text(letter?.uppercased() ?? "?")
            .font(SR.Text.hero(side * 0.6))
            .foregroundStyle(SR.paper)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: side * 0.24, style: .continuous).fill(SR.accentDeep))
            .rotationEffect(.degrees(8))
            .shadow(color: SR.accentDeep.opacity(0.35), radius: 4, y: 2)
    }
}

// MARK: - Playing

struct CategoriesPlaying: View {
    let room: GameRoom
    @ObservedObject var store: CategoriesStore
    @FocusState private var focused: Int?
    /// The card has been felt full once.
    @State private var cheeredFull = false

    private var count: Int { room.categories?.count ?? room.categoryCount }
    private var full: Bool { count > 0 && store.filled >= count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                CategoriesTimeBar(room: room, store: store, limit: room.timeLimitMs)
                if !room.others.isEmpty {
                    CategoriesOthersStrip(room: room)
                }
                if room.me?.joined != true {
                    Label("You are not playing in this one.", systemImage: "eye")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
                rows
                // Under the card, not over it: a banner arriving above the
                // lines would shove the field being typed in down the screen.
                if full && room.me?.joined == true {
                    fullBanner
                }
                Text(footnote)
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
        .onChange(of: store.filled) { _, now in
            if count > 0, now >= count, !cheeredFull {
                cheeredFull = true
                SRHaptic.ok()
            }
        }
        .srAnimation(.snappy, value: full)
    }

    private var footnote: String {
        room.solo ? "Answers save as you type." : "Answers save as you type. The same as someone else's scores nothing."
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            CategoriesLetter(letter: room.letter, side: 76)
            VStack(alignment: .leading, spacing: 6) {
                Text("CATEGORIES · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 10) {
                    CategoriesProgressRing(filled: store.filled, count: count, side: 44)
                    Text(CategoriesRules.filledLine(store.filled, of: count))
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .srNumeric(Double(store.filled))
                        .accessibilityLabel("\(store.filled) of \(count) answered")
                        .accessibilityIdentifier("categories-my-count")
                }
            }
            Spacer(minLength: 4)
            WordleTimer(room: room, store: store, id: "categories-timer")
        }
    }

    private var fullBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(SR.Text.title(18))
                .foregroundStyle(CategoriesInk.done)
                .accessibilityHidden(true)
            Text("Card full! Polish your answers until the clock runs out.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(CategoriesInk.done.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).strokeBorder(CategoriesInk.done.opacity(0.4), lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("categories-full")
    }

    private var rows: some View {
        VStack(spacing: 12) {
            ForEach(Array((room.categories ?? []).enumerated()), id: \.offset) { index, category in
                row(index, category)
            }
        }
    }

    private func row(_ index: Int, _ category: String) -> some View {
        let text = store.draft(index)
        let warning = CategoriesRules.warning(text, letter: room.letter)
        let state = CategoriesLineState.of(text, warning: warning)
        let isFocused = focused == index
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                CategoriesLineBadge(number: index + 1, state: state)
                Text(category)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            field(index, category, focusedNow: isFocused, state: state)
            if let warning {
                Label(warning, systemImage: "exclamationmark.circle")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.warn)
                    .accessibilityIdentifier("categories-warning-\(index)")
            }
        }
        .padding(12)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                .strokeBorder(isFocused ? SR.accent : Color.clear, lineWidth: 2)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("categories-row-\(index)")
    }

    private func field(_ index: Int, _ category: String, focusedNow: Bool, state: CategoriesLineState) -> some View {
        let count = room.categories?.count ?? 0
        return TextField(room.letter.map { "\($0.uppercased())…" } ?? "…", text: Binding(
            get: { store.draft(index) },
            set: { store.edit(index, $0) }
        ))
        .font(SR.Text.body(18))
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
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(SR.surface.opacity(focusedNow ? 1 : 0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .strokeBorder(state.stroke, lineWidth: state == .empty ? 1 : 1.5)
        )
        .accessibilityLabel("\(category), answer")
        .accessibilityIdentifier("categories-field-\(index)")
    }
}

/// How one line of my card stands while I type.
enum CategoriesLineState: Equatable {
    case empty
    case filled
    case warned

    static func of(_ text: String, warning: String?) -> CategoriesLineState {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return .empty }
        return warning == nil ? .filled : .warned
    }

    var stroke: Color {
        switch self {
        case .empty: return SR.line
        case .filled: return CategoriesInk.done.opacity(0.6)
        case .warned: return CategoriesInk.warned.opacity(0.8)
        }
    }
}

/// A line's number, as a badge: ringed while empty, a green tick once it is
/// filled on the letter, an amber "!" when it isn't. Shape as well as colour.
struct CategoriesLineBadge: View {
    let number: Int
    let state: CategoriesLineState
    @ScaledMetric(relativeTo: .headline) private var side: CGFloat = 30

    var body: some View {
        ZStack {
            switch state {
            case .empty:
                Circle().strokeBorder(SR.line, lineWidth: 1.5)
                Text("\(number)")
                    .font(SR.Text.label(13))
                    .foregroundStyle(SR.inkSecondary)
                    .monospacedDigit()
            case .filled:
                Circle().fill(CategoriesInk.done)
                Image(systemName: "checkmark")
                    .font(SR.Text.label(13))
                    .foregroundStyle(SR.paper)
            case .warned:
                Circle().fill(CategoriesInk.warned)
                Image(systemName: "exclamationmark")
                    .font(SR.Text.label(13))
                    .foregroundStyle(SR.paper)
            }
        }
        .frame(width: side, height: side)
        .srAnimation(.snappy, value: state)
        .accessibilityHidden(true)
    }
}

/// How many lines are filled, as a ring: violet as it fills, green when full.
struct CategoriesProgressRing: View {
    let filled: Int
    let count: Int
    var side: CGFloat = 44

    var body: some View {
        let share = PartyRoomMaths.share(filled, of: count)
        ZStack {
            Circle().stroke(SR.line, lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(share))
                .stroke(share >= 1 ? CategoriesInk.done : SR.accent,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if share >= 1 {
                Image(systemName: "checkmark")
                    .font(SR.Text.label(14))
                    .foregroundStyle(CategoriesInk.done)
            }
        }
        .frame(width: side, height: side)
        .srAnimation(.smooth(duration: 0.4), value: share)
        .accessibilityHidden(true)
    }
}

/// The round's letter, as a tile — and it lands with a little bounce the
/// first time it is shown.
struct CategoriesLetter: View {
    let letter: String?
    var side: CGFloat = 68

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        Text(letter?.uppercased() ?? "?")
            .font(SR.Text.hero(side * 0.62))
            .foregroundStyle(SR.paper)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                    .fill(LinearGradient(colors: [CategoriesInk.letter.opacity(0.82), CategoriesInk.letter],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 1.5)
            )
            .shadow(color: CategoriesInk.letter.opacity(0.35), radius: 6, y: 3)
            .scaleEffect(landed || reduceMotion ? 1 : 0.72)
            .rotationEffect(.degrees(landed || reduceMotion ? 0 : -10))
            .onAppear {
                guard !landed else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.58)) { landed = true }
            }
            .accessibilityLabel(letter.map { "The letter \($0.uppercased())" } ?? "No letter yet")
            .accessibilityIdentifier("categories-letter")
    }
}

/// The clock running out: a bar that empties towards `phaseEndsAt` and warms
/// as it goes, with a tap as it enters the last ten seconds and a tick for
/// each of the last five.
struct CategoriesTimeBar: View {
    let room: GameRoom
    @ObservedObject var store: CategoriesStore
    let limit: Double?
    /// The last seconds tap: while answering, not while reviewing.
    var haptics: Bool = true

    var body: some View {
        // Ticks, not an animation: a bar that is always animating keeps the app
        // from ever going idle, and UI tests then cannot read the screen.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let left = fraction
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.ink.opacity(0.1))
                    Capsule()
                        .fill(CategoriesInk.clock(left))
                        .frame(width: max(0, geo.size.width * left))
                }
            }
            .frame(height: 10)
            .background { CategoriesClockHaptics(seconds: haptics ? secondsLeft : nil) }
        }
        .accessibilityHidden(true)
    }

    private var fraction: CGFloat {
        guard let end = room.phaseEndsAt, let limit, limit > 0, let now = store.serverNow() else { return 1 }
        return CGFloat(min(1, max(0, (end - now) / limit)))
    }

    private var secondsLeft: Int? {
        guard let end = room.phaseEndsAt, let now = store.serverNow() else { return nil }
        return GameCountdown.secondsLeft(until: end, atServer: now)
    }
}

/// Nothing to see: the clock's haptics, fired as the seconds change.
struct CategoriesClockHaptics: View {
    let seconds: Int?

    var body: some View {
        Color.clear
            .onChange(of: seconds) { old, new in
                if let old, let new, old > 10, new == 10 {
                    SRHaptic.tap()
                } else if PartyRoomMaths.tick(from: old, to: new, warnAt: 5) {
                    SRHaptic.select()
                }
            }
    }
}

/// Everyone else while playing: a name and how many lines filled, with a
/// little bar of it. Never the answers.
struct CategoriesOthersStrip: View {
    let room: GameRoom

    var body: some View {
        let count = room.categories?.count ?? room.categoryCount
        let tones = SR.PersonHue.assign(room.players.map(\.id))
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(room.others) { player in
                    chip(player, count: count, tone: tones[player.id] ?? SR.accentInk)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("categories-others")
    }

    private func chip(_ player: GamePlayer, count: Int, tone: Color) -> some View {
        HStack(spacing: 10) {
            GameInitial(name: player.name, tone: tone, side: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(player.name)
                        .font(SR.Text.title(14))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                    Text(CategoriesRules.filledLine(player.filled, of: count))
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkSecondary)
                        .monospacedDigit()
                }
                CategoriesMiniBar(share: PartyRoomMaths.share(player.filled, of: count), tone: tone)
                    .frame(width: 72, height: 5)
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

/// A small filled bar.
struct CategoriesMiniBar: View {
    let share: Double
    let tone: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SR.ink.opacity(0.1))
                Capsule().fill(tone).frame(width: geo.size.width * CGFloat(share))
            }
        }
        .srAnimation(.smooth(duration: 0.4), value: share)
        .accessibilityHidden(true)
    }
}

// MARK: - Review

struct CategoriesReview: View {
    let room: GameRoom
    @ObservedObject var store: CategoriesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    CategoriesTimeBar(room: room, store: store, limit: room.reviewMs, haptics: false)
                }
                instructions
                CategoriesCardReview(room: room, store: store)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .accessibilityIdentifier("categories-review")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            CategoriesLetter(letter: room.letter, side: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text("REVIEW")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text("Any cheeky ones?")
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            WordleTimer(room: room, store: store, id: "categories-review-timer")
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.thumbsdown.fill")
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.error)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(SR.error.opacity(0.12)))
                    .accessibilityHidden(true)
                Text("Tap somebody else's answer to veto it; tap again to take it back. Half the others vetoing strikes it.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                CategoriesTag(text: "SHARED", tone: SR.inkMuted)
                CategoriesTag(text: "WRONG LETTER", tone: SR.inkMuted)
                CategoriesTag(text: "VETOED", tone: SR.error)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Crossed-out answers are tagged shared, wrong letter or vetoed.")
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
    }

    /// My score so far and Done, always in reach at the foot of the screen.
    @ViewBuilder
    private var footer: some View {
        if room.me?.joined == true {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(room.me?.score ?? 0)")
                        .font(SR.Text.figure(28))
                        .foregroundStyle(SR.ink)
                        .srNumeric(Double(room.me?.score ?? 0))
                    Text("SO FAR")
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.inkMuted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(room.me?.score ?? 0) points so far")
                .accessibilityIdentifier("categories-so-far")
                doneButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .srGlassCard(.paper)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var doneButton: some View {
        if room.me?.done == true {
            let waiting = CategoriesRules.waitingOn(room).map { $0.id == room.meId ? "you" : $0.name }
            HStack(spacing: 8) {
                ProgressView().tint(SR.accent)
                Text(waiting.isEmpty ? "Adding up…" : "Waiting on \(GameNames.list(waiting)).")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("categories-waiting")
        } else {
            Button { store.finishReview() } label: {
                SRButtonLabel(title: "Done reviewing", icon: "checkmark", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(store.busy)
            .accessibilityIdentifier("categories-done-review")
        }
    }
}

/// A judged answer's tag: a small capsule, outlined.
struct CategoriesTag: View {
    let text: String
    let tone: Color

    var body: some View {
        Text(text)
            .font(SR.Text.label())
            .tracking(1)
            .foregroundStyle(tone)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(tone.opacity(0.6), lineWidth: 1))
    }
}

/// Every answer, category by category: who wrote what and how it was judged.
/// In the review, tapping another player's answer vetoes it.
struct CategoriesCardReview: View {
    let room: GameRoom
    @ObservedObject var store: CategoriesStore

    var body: some View {
        let people = CategoriesRules.contenders(room)
        let tones = SR.PersonHue.assign(room.players.map(\.id))
        VStack(alignment: .leading, spacing: SR.sectionGap - 6) {
            ForEach(Array((room.categories ?? []).enumerated()), id: \.offset) { index, category in
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    sectionHeader(index, category)
                    VStack(spacing: 0) {
                        ForEach(Array(people.enumerated()), id: \.element.id) { n, person in
                            if n > 0 { Divider().overlay(SR.divider) }
                            answerRow(person, answer(of: person, at: index), tone: tones[person.id] ?? SR.accentInk)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .srGlassCard(.paper)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("categories-category-\(index)")
            }
        }
    }

    private func sectionHeader(_ index: Int, _ category: String) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(SR.Text.label(13))
                .foregroundStyle(SR.paper)
                .monospacedDigit()
                .frame(minWidth: 26, minHeight: 26)
                .background(Circle().fill(SR.accentInk))
                .accessibilityHidden(true)
            Text(category)
                .font(SR.Text.title(16))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(index + 1). \(category)")
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
    }

    private func answer(of person: GamePlayer, at index: Int) -> CategoriesAnswer {
        person.categoryAnswers?.first { $0.index == index } ?? CategoriesAnswer(index: index, text: "", status: .empty)
    }

    private func answerRow(_ person: GamePlayer, _ answer: CategoriesAnswer, tone: Color) -> some View {
        let canVeto = CategoriesRules.canVeto(answer, ownerId: person.id, room: room)
        let isMe = person.id == room.meId
        let traits: AccessibilityTraits = !canVeto ? [] : answer.vetoed ? [.isButton, .isSelected] : .isButton
        return Button {
            store.toggleVeto(owner: person, answer: answer)
        } label: {
            answerLabel(person, answer, isMe: isMe, canVeto: canVeto, tone: tone)
        }
        .buttonStyle(SRPressStyle())
        .disabled(!canVeto)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(person, answer, isMe: isMe))
        .accessibilityHint(canVeto ? (answer.vetoed ? "Takes your veto back" : "Vetoes it") : "")
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier("categories-answer-\(person.id)-\(answer.index)")
    }

    private func answerLabel(_ person: GamePlayer, _ answer: CategoriesAnswer, isMe: Bool, canVeto: Bool, tone: Color) -> some View {
        let status = answer.status ?? .empty
        return HStack(alignment: .center, spacing: 10) {
            GameInitial(name: isMe ? "You" : person.name, tone: isMe ? SR.accent : tone, side: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(answer.text.isEmpty ? "—" : answer.text)
                    .font(SR.Text.title())
                    .foregroundStyle(status.crossed || answer.text.isEmpty ? SR.inkMuted : SR.ink)
                    .strikethrough(status.crossed, color: status == .struck ? SR.error : SR.inkMuted)
                    .lineLimit(2)
                statusLine(answer, status: status)
            }
            Spacer(minLength: 6)
            if canVeto {
                vetoChip(answer.vetoed)
            }
            pointsPill(answer.points)
        }
        .frame(minHeight: 56)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(answer.vetoed ? SR.error.opacity(0.08) : Color.clear))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func statusLine(_ answer: CategoriesAnswer, status: CategoriesStatus) -> some View {
        let line = status != .wrongLetter ? CategoriesRules.vetoLine(answer) : nil
        if status.tag != nil || line != nil {
            HStack(spacing: 6) {
                if let tag = status.tag {
                    CategoriesTag(text: tag, tone: status == .struck ? SR.error : SR.inkMuted)
                }
                if let line {
                    Text(line)
                        .font(SR.Text.mono())
                        .foregroundStyle(status == .struck ? SR.error : SR.warn)
                }
            }
        }
    }

    /// The veto, as something that looks pressable: a capsule that fills red
    /// once I have vetoed.
    private func vetoChip(_ vetoed: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: vetoed ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            Text(vetoed ? "VETOED" : "VETO")
                .tracking(0.8)
        }
        .font(SR.Text.label())
        .foregroundStyle(vetoed ? SR.paper : SR.error)
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(Capsule().fill(vetoed ? SR.error : SR.error.opacity(0.1)))
        .overlay(Capsule().strokeBorder(SR.error.opacity(vetoed ? 0 : 0.5), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private func pointsPill(_ points: Int) -> some View {
        Text(points > 0 ? "+\(points)" : "0")
            .font(SR.Text.figure(17))
            .foregroundStyle(points > 0 ? CategoriesInk.done : SR.inkMuted)
            .monospacedDigit()
            .frame(minWidth: 40, minHeight: 30)
            .background(Capsule().fill(points > 0 ? CategoriesInk.done.opacity(0.14) : SR.ink.opacity(0.06)))
            .accessibilityHidden(true)
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

    /// What this game did to my best on this phone; set once on appearing.
    @State private var best: PartyRoomBestNote?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Categories · \(room.letter?.uppercased() ?? "?") · final",
                             title: GameResults.title(room, solo: "You scored \(myScore)", none: "Nobody scored"),
                             strap: GameResults.strap(room))

                if room.me?.joined == true {
                    CategoriesResultHero(room: room, score: myScore, place: place, best: best)
                }

                GameStandingsCard(
                    room: room,
                    label: room.solo ? "Your game" : "Standings",
                    id: "categories-standings",
                    detail: detail,
                    figure: { (text: "\($0.score)", spoken: "\($0.score) points") }
                )

                GameFinishedButtons(room: room, store: store, prefix: "categories", done: done)

                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: "Every answer", trailing: "\(room.categories?.count ?? room.categoryCount) categories")
                    CategoriesCardReview(room: room, store: store)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("categories-finished")
        .onAppear { recordBest() }
    }

    private var myScore: Int {
        room.standings?.first { $0.id == room.meId }?.score ?? room.me?.score ?? 0
    }

    private var place: Int? {
        guard !room.solo, let rows = room.standings, !rows.isEmpty else { return nil }
        return PartyRoomMaths.place(of: room.meId, ids: rows.map(\.id), scores: rows.map(\.score))
    }

    private func recordBest() {
        guard best == nil, room.me?.joined == true else { return }
        let count = room.categories?.count ?? room.categoryCount
        // Play again keeps the room's id, so the game is told apart by its
        // start, its letter and its card (any one of which may be missing).
        let card = (room.categories ?? []).joined(separator: ",")
        let token = "\(room.id)|\(room.letter ?? "")|\(Int(room.startedAt ?? 0))|\(card)"
        let note = PartyRoomBestStore.categories.record(myScore, kind: "\(count)", token: token)
        best = note
        // The standings card cheers a win; a personal best is felt here.
        let won = room.solo ? room.records[room.meId] != nil : room.winnerIds.contains(room.meId)
        if note.isNew, !won { SRHaptic.ok() }
    }

    private func detail(_ row: GameStanding) -> String {
        let count = room.categories?.count ?? room.categoryCount
        let filled = room.players.first { $0.id == row.id }?.filled ?? 0
        return "\(filled) of \(count) answered"
    }
}

/// My game in one card: the letter, my score, my place, and my best on this
/// phone for a card this size.
struct CategoriesResultHero: View {
    let room: GameRoom
    let score: Int
    let place: Int?
    let best: PartyRoomBestNote?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            CategoriesLetter(letter: room.letter, side: 72)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(score)")
                        .font(SR.Text.hero(44))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                    Text(score == 1 ? "point" : "points")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.inkSecondary)
                }
                if let place {
                    Text("\(PartyRoomMaths.ordinal(place)) of \(room.standings?.count ?? room.playing.count)")
                        .font(SR.Text.title(15))
                        .foregroundStyle(place == 1 ? SR.accent : SR.inkSecondary)
                }
                bestLine
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .scaleEffect(shown || reduceMotion ? 1 : 0.94)
        .opacity(shown || reduceMotion ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7)) { shown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("categories-result")
    }

    @ViewBuilder
    private var bestLine: some View {
        if let best {
            if best.isNew {
                Label("New personal best!", systemImage: "star.fill")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.good)
                    .accessibilityIdentifier("categories-new-best")
            } else if let value = best.best {
                Text("Your best on \(room.categories?.count ?? room.categoryCount) categories: \(value)")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

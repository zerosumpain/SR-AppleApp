import SwiftUI

/// Higher or Lower on one phone: the card everyone is calling against, the
/// face-down card to come, two big buttons, and the table of scores.
///
/// While the timer runs, Higher and Lower each send one call; the call shows
/// here at once (the host's view confirms it) and the buttons lock, because a
/// call cannot be changed. Other players show only a tick until the card
/// turns. Then the face-down card flips to the host's revealed card, every
/// call appears beside its owner with the points it earned, and a ring runs
/// down to the next card. The cards turned so far sit at the bottom, small,
/// for anyone who likes to count.
///
/// The overhaul (2026-10-29) laid the two cards on green baize with the
/// verdict between them, made Higher and Lower two big coloured buttons, and
/// pops "Right! +2" (or the miss) the moment the card turns.
struct HigherLowerView: View {
    let context: OfflineGameContext<HigherLowerRules>
    /// My call this round, shown before the host's echo arrives.
    @State private var local: HigherLowerRules.Call?
    @State private var localRound = 0
    @State private var callout = ""
    @State private var calloutTone: Color = SR.accentDeep
    @State private var calloutIcon: String?
    @State private var calloutToken = 0
    @State private var burstToken = 0

    private var view: HigherLowerRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                banner
                felt
                if playing && view.phase == .calling { callButtons }
                scoreboard
                if !view.history.isEmpty { history }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay {
            ZStack {
                NearbyPlayBurst(token: burstToken)
                NearbyPlayCallout(text: callout, icon: calloutIcon, tone: calloutTone, token: calloutToken)
            }
        }
        .onChange(of: view.round) { _, _ in
            local = nil
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil {
                SRHaptic.bad()
                // The host did not take it; let the buttons work again.
                if view.myCall == nil { local = nil }
            }
        }
        .onChange(of: view.phase) { _, new in
            guard new == .reveal else { return }
            revealed()
        }
    }

    // MARK: - Words

    private var myRow: HigherLowerRules.Row? {
        view.rows.first { $0.id == context.me }
    }

    /// I am in this match and still here (not a spectator).
    private var playing: Bool {
        guard let row = myRow else { return false }
        return !row.away
    }

    /// My call this round: the host's word if it has spoken, else my own.
    private var myCall: HigherLowerRules.Call? {
        view.myCall ?? (localRound == view.round ? local : nil)
    }

    /// The call is mine to make now.
    private var callIsMine: Bool { playing && view.phase == .calling && myCall == nil }

    private var kicker: String {
        "Card \(view.round) of \(view.rounds) · \(view.cardsLeft) in the deck"
    }

    private var title: String {
        switch view.phase {
        case .calling:
            if !playing { return "Watching" }
            return myCall == nil ? "Higher or lower?" : "Called"
        case .reveal:
            switch view.outcome {
            case .higher?: return "Higher"
            case .lower?: return "Lower"
            case .same?: return "Same rank"
            case nil: return "Turned"
            }
        case .over:
            let names = view.champions.map { $0 == context.me ? "You" : context.name(of: $0) }
            if names.count == 1 { return names[0] == "You" ? "You win" : "\(names[0]) wins" }
            return names.isEmpty ? "Nobody scored" : "A tie"
        }
    }

    private var strap: String? {
        switch view.phase {
        case .calling:
            if !playing { return "You are watching this match." }
            if let call = myCall { return "You called \(call.rawValue). Waiting for the others." }
            return "Will the next card beat the \(view.current.name)? Aces are high."
        case .reveal:
            guard playing, let gained = myRow?.gained else { return nil }
            if view.outcome == .same { return "Same rank — wrong for everyone." }
            if gained > 0 { return "Right! +\(gained) point\(gained == 1 ? "" : "s")." }
            return myRow?.call == nil ? "No call in time — that counts as wrong." : "Wrong this time. Streak reset."
        case .over:
            return "All \(view.rounds) cards called."
        }
    }

    private var bannerMark: NearbyPlayMark {
        switch view.phase {
        case .calling: return .symbol("arrow.up.arrow.down")
        case .reveal: return .symbol(HigherLowerTable.symbol(view.outcome))
        case .over: return .symbol("trophy.fill")
        }
    }

    // MARK: - The top

    private var banner: some View {
        NearbyPlayBanner(kicker: kicker, title: title, strap: strap, mine: callIsMine, mark: bannerMark) {
            ringClock
        }
    }

    /// The ring to the end of the calls, then to the next card.
    @ViewBuilder
    private var ringClock: some View {
        switch view.phase {
        case .calling:
            NearbyPlayBannerClock(clock: context.clock, until: view.callEndsAt,
                                  total: HigherLowerRules.callWindow, mine: callIsMine)
                .accessibilityLabel("Calls close soon")
                .accessibilityIdentifier("offline-higher-lower-timer")
        case .reveal:
            NearbyPlayBannerClock(clock: context.clock, until: view.revealUntil,
                                  total: HigherLowerRules.revealPause, mine: false)
                .accessibilityLabel(view.round >= view.rounds ? "Final scores next" : "Next card coming")
                .accessibilityIdentifier("offline-higher-lower-timer")
        case .over:
            EmptyView()
        }
    }

    // MARK: - The table

    private var felt: some View {
        NearbyPlayFelt(tone: .baize) {
            VStack(spacing: 12) {
                HigherLowerTable(current: view.current, revealed: view.revealed, outcome: view.outcome)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    NearbyPlayStat(icon: "rectangle.portrait.on.rectangle.portrait.fill",
                                   text: "\(view.cardsLeft) left", onFelt: true)
                    if let streak = myRow?.streak, streak >= 2 {
                        NearbyPlayStat(icon: "flame.fill", text: "Streak \(streak)", onFelt: true)
                            .nearbyPlayBump(streak)
                    }
                    Spacer(minLength: 0)
                    if let row = myRow {
                        Text("\(row.score)")
                            .font(SR.Text.figure(26))
                            .foregroundStyle(NearbyPlayFeltInk.primary)
                            .contentTransition(.numericText(value: Double(row.score)))
                            .srAnimation(.snappy, value: row.score)
                            .nearbyPlayBump(row.score)
                            .accessibilityLabel("Your score, \(row.score)")
                        Text("pts")
                            .font(SR.Text.mono())
                            .foregroundStyle(NearbyPlayFeltInk.secondary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    // MARK: - Calling

    private var callButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                callButton(.higher, title: "Higher", icon: "arrow.up.circle.fill", kind: .go)
                callButton(.lower, title: "Lower", icon: "arrow.down.circle.fill", kind: .danger)
            }
            Text(myCall == nil ? "Aces are high. The same rank loses for everyone." : "Locked in — calls can't be changed.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func callButton(_ call: HigherLowerRules.Call, title: String, icon: String,
                            kind: NearbyPlayButtonKind) -> some View {
        let chosen = myCall == call
        let locked = myCall != nil
        return NearbyPlayButton(title: title, icon: icon, kind: kind, enabled: !locked,
                                minHeight: NearbyPlayMetrics.bigButton, chosen: chosen) {
            send(call)
        }
        .allowsHitTesting(!locked)
        .accessibilityLabel(chosen ? "You called \(title.lowercased())" : "Call \(title.lowercased())")
        .accessibilityHint(locked ? "" : "The next card will be \(title.lowercased()) than the \(view.current.name).")
        .accessibilityIdentifier("offline-higher-lower-\(call.rawValue)")
    }

    private func send(_ call: HigherLowerRules.Call) {
        guard view.phase == .calling, playing, myCall == nil else { return }
        SRHaptic.select()
        local = call
        localRound = view.round
        context.send(.call(round: view.round, call: call))
    }

    // MARK: - The turn

    /// The card has turned: a buzz and a word for how my call did.
    private func revealed() {
        guard playing, let row = myRow else {
            if let outcome = view.outcome {
                pop(HigherLowerTable.word(outcome), icon: HigherLowerTable.symbol(outcome), tone: SR.accentDeep)
            }
            return
        }
        let gained = row.gained ?? 0
        if view.outcome == .same {
            SRHaptic.bad()
            pop("Same rank!", icon: "equal.circle.fill", tone: SR.warn)
        } else if gained > 0 {
            SRHaptic.ok()
            pop("Right! +\(gained)", icon: "checkmark.circle.fill", tone: SR.good)
            if row.streak >= 3 { burstToken += 1 }
        } else {
            SRHaptic.bad()
            pop(row.call == nil ? "No call" : "Wrong", icon: "xmark.circle.fill", tone: SR.error)
        }
    }

    private func pop(_ text: String, icon: String?, tone: Color) {
        callout = text
        calloutIcon = icon
        calloutTone = tone
        calloutToken += 1
    }

    // MARK: - Scores

    private var scoreboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Table", trailing: "Points")
            VStack(spacing: 0) {
                ForEach(Array(view.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    HigherLowerRowView(row: row, seat: index, isMe: row.id == context.me,
                                       phase: view.phase, myCall: row.id == context.me ? myCall : nil)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("offline-higher-lower-table")
    }

    // MARK: - History

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Turned so far", trailing: "\(view.history.count)")
            OfflineHand(cards: view.history, cardWidth: 40)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Turned so far: " + view.history.map(\.name).joined(separator: ", "))
        }
        .accessibilityIdentifier("offline-higher-lower-history")
    }
}

/// The card showing and the card to come, side by side on the felt, sized
/// from the width available so two cards and the verdict between them always
/// fit. The card to come turns over with a flip when the host reveals it.
struct HigherLowerTable: View {
    let current: OfflineCard
    let revealed: OfflineCard?
    let outcome: HigherLowerRules.Outcome?

    var body: some View {
        GeometryReader { geo in
            let width = cardWidth(for: geo.size.width)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                NearbyPlayFlipCard(card: current, width: width)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Showing: \(current.name)")
                    .accessibilityIdentifier("offline-higher-lower-current")
                verdict(width: width)
                    .frame(width: gap(for: geo.size.width))
                NearbyPlayFlipCard(card: revealed, width: width, selected: revealed != nil)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(revealed.map { "Turned: \($0.name)" } ?? "Next card, face down")
                    .accessibilityIdentifier("offline-higher-lower-next")
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(2.3, contentMode: .fit)
        .frame(maxWidth: 380)
    }

    /// The disc between the cards: a question while calls are open, then
    /// the way the card went, in its colour.
    private func verdict(width: CGFloat) -> some View {
        let side = max(34, width * 0.42)
        return ZStack {
            Circle()
                .fill(outcome == nil ? NearbyPlayFeltInk.chip : HigherLowerTable.tone(outcome))
            Image(systemName: outcome == nil ? "questionmark" : HigherLowerTable.arrow(outcome))
                .font(.system(size: side * 0.5, weight: .heavy))
                .foregroundStyle(Color.white)
        }
        .frame(width: side, height: side)
        .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 2) }
        .shadow(color: Color.black.opacity(0.25), radius: 5, x: 0, y: 3)
        .scaleEffect(outcome == nil ? 0.9 : 1.08)
        .srAnimation(.spring(response: 0.4, dampingFraction: 0.55), value: outcome)
        .accessibilityHidden(true)
    }

    private func gap(for total: CGFloat) -> CGFloat { max(44, total * 0.2) }

    /// Two cards and the gap fit `total`, and their height fits the frame.
    private func cardWidth(for total: CGFloat) -> CGFloat {
        let byWidth = (total - gap(for: total)) / 2
        let byHeight = (total / 2.3) / OfflineCardMetrics.aspect
        return max(20, min(byWidth, byHeight, 130))
    }

    static func arrow(_ outcome: HigherLowerRules.Outcome?) -> String {
        switch outcome {
        case .higher?: return "arrow.up"
        case .lower?: return "arrow.down"
        case .same?: return "equal"
        case nil: return "questionmark"
        }
    }

    static func symbol(_ outcome: HigherLowerRules.Outcome?) -> String {
        switch outcome {
        case .higher?: return "arrow.up.circle.fill"
        case .lower?: return "arrow.down.circle.fill"
        case .same?: return "equal.circle.fill"
        case nil: return "questionmark.circle"
        }
    }

    static func word(_ outcome: HigherLowerRules.Outcome) -> String {
        switch outcome {
        case .higher: return "Higher!"
        case .lower: return "Lower!"
        case .same: return "Same rank!"
        }
    }

    /// Fixed colours: they sit on the felt, which is green in both modes.
    static func tone(_ outcome: HigherLowerRules.Outcome?) -> Color {
        switch outcome {
        case .higher?: return Color(hex: 0x1E9E5A)
        case .lower?: return Color(hex: 0xD6453D)
        case .same?: return Color(hex: 0xD89512)
        case nil: return NearbyPlayFeltInk.chip
        }
    }
}

/// One player's line: name, streak, this round's call (or just a tick before
/// the reveal), the points it earned, and the running score.
struct HigherLowerRowView: View {
    let row: HigherLowerRules.Row
    let seat: Int
    let isMe: Bool
    let phase: HigherLowerRules.Phase
    /// My own call, shown on my row before the reveal.
    let myCall: HigherLowerRules.Call?

    var body: some View {
        HStack(spacing: 10) {
            OfflineInitial(name: row.name, size: 32, tone: OfflineSeatColour.of(seat))
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? "You" : row.name)
                    .font(SR.Text.title(16))
                    .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    if row.streak >= 2 && !row.away {
                        Image(systemName: "flame.fill")
                            .font(SR.Text.label(12))
                            .foregroundStyle(SR.warn)
                            .accessibilityHidden(true)
                    }
                    Text(detail)
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 6)
            callBadge
            if let gained = row.gained, gained > 0 {
                Text("+\(gained)")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.good)
                    .fixedSize()
                    .transition(.scale.combined(with: .opacity))
            }
            Text("\(row.score)")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .contentTransition(.numericText(value: Double(row.score)))
                .frame(minWidth: 30, alignment: .trailing)
                .fixedSize()
        }
        .frame(minHeight: 52)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(isMe ? SR.accent.opacity(0.08) : Color.clear)
                .padding(.horizontal, -8)
        )
        .srAnimation(.snappy(duration: 0.3), value: row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("offline-higher-lower-row-\(row.id)")
    }

    private var detail: String {
        if row.away { return "left" }
        if row.streak >= 2 { return "streak \(row.streak)" }
        return row.streak == 1 ? "1 right in a row" : "no streak"
    }

    /// The call to show: everyone's after the reveal, mine before it.
    private var shownCall: HigherLowerRules.Call? {
        row.call ?? (phase == .calling ? myCall : nil)
    }

    @ViewBuilder
    private var callBadge: some View {
        if let call = shownCall {
            Image(systemName: call == .higher ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(SR.Text.title(20))
                .foregroundStyle(badgeTone)
                .frame(width: 26)
        } else if phase == .calling && row.called {
            Image(systemName: "checkmark.circle.fill")
                .font(SR.Text.title(18))
                .foregroundStyle(SR.inkSecondary)
                .frame(width: 26)
        } else if phase == .calling && !row.away {
            Image(systemName: "ellipsis")
                .font(SR.Text.title(16))
                .foregroundStyle(SR.inkGhost)
                .frame(width: 26)
        } else if phase == .reveal && !row.away {
            Image(systemName: "minus")
                .font(SR.Text.title(16))
                .foregroundStyle(SR.inkGhost)
                .frame(width: 26)
        }
    }

    private var badgeTone: Color {
        guard let gained = row.gained else { return SR.accent }
        return gained > 0 ? SR.good : SR.error
    }

    private var accessibilityText: String {
        var parts = [isMe ? "You" : row.name, "\(row.score) point\(row.score == 1 ? "" : "s")"]
        if row.away { parts.append("left the game") }
        if row.streak >= 2 { parts.append("streak of \(row.streak)") }
        if let call = shownCall {
            parts.append("called \(call.rawValue)")
            if let gained = row.gained { parts.append(gained > 0 ? "right, plus \(gained)" : "wrong") }
        } else if phase == .calling {
            parts.append(row.called ? "has called" : "still deciding")
        } else if phase == .reveal && !row.away {
            parts.append("no call")
        }
        return parts.joined(separator: ", ")
    }
}

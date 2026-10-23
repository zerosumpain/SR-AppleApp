import SwiftUI

/// Higher or Lower on one phone: the card everyone is calling against, the
/// face-down card to come, two buttons, and the table of scores.
///
/// While the timer runs, Higher and Lower each send one call; the call shows
/// here at once (the host's view confirms it) and the buttons lock, because a
/// call cannot be changed. Other players show only a tick until the card
/// turns. Then the face-down card flips to the host's revealed card, every
/// call appears beside its owner with the points it earned, and a countdown
/// runs to the next card. The cards turned so far sit at the bottom, small,
/// for anyone who likes to count.
struct HigherLowerView: View {
    let context: OfflineGameContext<HigherLowerRules>
    /// My call this round, shown before the host's echo arrives.
    @State private var local: HigherLowerRules.Call?
    @State private var localRound = 0

    private var view: HigherLowerRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                HigherLowerTable(current: view.current, revealed: view.revealed, outcome: view.outcome)
                    .frame(maxWidth: .infinity)
                status
                if playing && view.phase == .calling { callButtons }
                scoreboard
                if !view.history.isEmpty { history }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
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
            guard new == .reveal, let right = myRow?.gained else { return }
            if right > 0 { SRHaptic.ok() } else if playing { SRHaptic.bad() }
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
            return nil
        }
    }

    // MARK: - Timer line

    private var status: some View {
        HStack(spacing: 8) {
            switch view.phase {
            case .calling:
                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityHidden(true)
                Text("Calls close in")
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.inkMuted)
                OfflineCountdown(clock: context.clock, until: view.callEndsAt, font: SR.Text.mono(15), tone: SR.ink)
            case .reveal:
                Text(view.round >= view.rounds ? "Final scores in" : "Next card in")
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.inkMuted)
                OfflineCountdown(clock: context.clock, until: view.revealUntil, font: SR.Text.mono(15), tone: SR.inkMuted)
            case .over:
                Text("All \(view.rounds) cards called.")
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-higher-lower-timer")
    }

    // MARK: - Calling

    private var callButtons: some View {
        HStack(spacing: 12) {
            callButton(.higher, title: "Higher", icon: "arrow.up")
            callButton(.lower, title: "Lower", icon: "arrow.down")
        }
    }

    @ViewBuilder
    private func callButton(_ call: HigherLowerRules.Call, title: String, icon: String) -> some View {
        let chosen = myCall == call
        let locked = myCall != nil
        if chosen {
            Button { } label: {
                SRButtonLabel(title: title, icon: icon, fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .allowsHitTesting(false)
            .accessibilityLabel("You called \(title.lowercased())")
            .accessibilityIdentifier("offline-higher-lower-\(call.rawValue)")
        } else {
            Button {
                send(call)
            } label: {
                SRButtonLabel(title: title, icon: icon, fill: true)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(locked)
            .opacity(locked ? 0.45 : 1)
            .accessibilityLabel("Call \(title.lowercased())")
            .accessibilityHint("The next card will be \(title.lowercased()) than the \(view.current.name).")
            .accessibilityIdentifier("offline-higher-lower-\(call.rawValue)")
        }
    }

    private func send(_ call: HigherLowerRules.Call) {
        guard view.phase == .calling, playing, myCall == nil else { return }
        SRHaptic.select()
        local = call
        localRound = view.round
        context.send(.call(round: view.round, call: call))
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

/// The card showing and the card to come, side by side, sized from the
/// width available so two cards and the arrow between them always fit.
struct HigherLowerTable: View {
    let current: OfflineCard
    let revealed: OfflineCard?
    let outcome: HigherLowerRules.Outcome?

    var body: some View {
        GeometryReader { geo in
            let width = cardWidth(for: geo.size.width)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                OfflineCardFace(card: current, width: width)
                    .accessibilityLabel("Showing: \(current.name)")
                    .accessibilityIdentifier("offline-higher-lower-current")
                Image(systemName: arrow)
                    .font(.system(size: width * 0.28, weight: .bold))
                    .foregroundStyle(outcome == nil ? SR.inkGhost : SR.accent)
                    .frame(width: gap(for: geo.size.width))
                    .accessibilityHidden(true)
                Group {
                    if let revealed {
                        OfflineCardFace(card: revealed, width: width, selected: true)
                            .accessibilityLabel("Turned: \(revealed.name)")
                    } else {
                        OfflineCardBack(width: width)
                            .accessibilityLabel("Next card, face down")
                    }
                }
                .accessibilityIdentifier("offline-higher-lower-next")
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(2.4, contentMode: .fit)
        .frame(maxWidth: 360)
    }

    private func gap(for total: CGFloat) -> CGFloat { max(36, total * 0.16) }

    /// Two cards and the gap fit `total`, and their height fits the 2.4:1 frame.
    private func cardWidth(for total: CGFloat) -> CGFloat {
        let byWidth = (total - gap(for: total)) / 2
        let byHeight = (total / 2.4) / OfflineCardMetrics.aspect
        return max(20, min(byWidth, byHeight, 130))
    }

    private var arrow: String {
        switch outcome {
        case .higher?: return "arrow.up.circle.fill"
        case .lower?: return "arrow.down.circle.fill"
        case .same?: return "equal.circle.fill"
        case nil: return "questionmark.circle"
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
            OfflineInitial(name: row.name, size: 28, tone: OfflineSeatColour.of(seat))
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? "You" : row.name)
                    .font(SR.Text.title(16))
                    .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail)
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)
            callBadge
            if let gained = row.gained, gained > 0 {
                Text("+\(gained)")
                    .font(SR.Text.mono(14))
                    .foregroundStyle(SR.good)
                    .fixedSize()
            }
            Text("\(row.score)")
                .font(SR.Text.display(20))
                .foregroundStyle(SR.ink)
                .frame(minWidth: 28, alignment: .trailing)
                .fixedSize()
        }
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 4)
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
            Image(systemName: call == .higher ? "arrow.up" : "arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(badgeTone)
                .frame(width: 22)
        } else if phase == .calling && row.called {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SR.inkSecondary)
                .frame(width: 22)
        } else if phase == .reveal && !row.away {
            Image(systemName: "minus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SR.inkGhost)
                .frame(width: 22)
        }
    }

    private var badgeTone: Color {
        guard let gained = row.gained else { return SR.ink }
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

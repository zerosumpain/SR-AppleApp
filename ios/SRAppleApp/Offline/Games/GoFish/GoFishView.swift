import SwiftUI

/// Go Fish on one phone: whose turn it is, the table (everyone's card count
/// and books), my own hand, and — on my turn — who to ask and for what.
///
/// The view never changes the game: picking a player and a rank is local
/// `@State`, and Ask sends one action and waits for the host's next view.
/// Tapping a card in the hand picks its rank, so the hand and the rank
/// buttons are two ways to make the same choice.
struct GoFishView: View {
    let context: OfflineGameContext<GoFishRules>
    /// The player I mean to ask, before I send it.
    @State private var target: String?
    /// The rank I mean to ask for, before I send it.
    @State private var rank: Int?
    /// The turn number I last sent an ask on, so a double tap sends once.
    @State private var sentTurn: Int?

    private var view: GoFishRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                status
                if myTurn {
                    askPanel
                }
                if let hand = view.myHand, !amAway {
                    handSection(hand)
                }
                tableSection
                if !view.log.isEmpty {
                    logSection
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("offline-go-fish")
        .onChange(of: view.turnNumber) { _, _ in
            sentTurn = nil
        }
        .onChange(of: context.refusal) { _, new in
            // The host turned the ask down, so the turn is still mine:
            // unlock Ask rather than leave it dead until the timer runs out.
            guard new != nil else { return }
            SRHaptic.bad()
            sentTurn = nil
        }
    }

    // MARK: - Who is doing what

    private var myTurn: Bool { view.turn == context.me && view.phase == .playing }

    private var amAway: Bool {
        view.seats.first { $0.id == context.me }?.away ?? false
    }

    private var inGame: Bool { view.myHand != nil }

    private func who(_ id: String) -> String {
        id == context.me ? "You" : context.name(of: id)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRPageHeader(kicker: kicker, title: headline, strap: instruction)
            if view.phase == .playing {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SR.inkMuted)
                        .accessibilityHidden(true)
                    Text(myTurn ? "Your time" : "Turn time")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                    OfflineCountdown(clock: context.clock, until: view.turnEndsAt, font: SR.Text.mono(), tone: SR.inkMuted)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("offline-go-fish-status")
    }

    private var kicker: String {
        let books = view.seats.reduce(0) { $0 + $1.books.count }
        return "Pond \(view.stockCount) · Books \(books) of \(GoFishRules.totalBooks)"
    }

    private var headline: String {
        if view.phase == .over {
            let names = view.champions.map(who)
            if names.count == 1 { return names[0] == "You" ? "You win" : "\(names[0]) wins" }
            return names.isEmpty ? "Nobody won" : "A tie"
        }
        guard let turn = view.turn else { return "Go Fish" }
        return turn == context.me ? "Your turn" : "\(context.name(of: turn)) is asking"
    }

    private var instruction: String? {
        if view.phase == .over { return "Every book is down." }
        if !inGame { return "You are watching this game." }
        if amAway { return "You have left this game." }
        if myTurn {
            if sentTurn == view.turnNumber { return "Asking…" }
            return "Pick a player, then a rank you hold — or tap a card."
        }
        return "Wait for your turn. Anyone may ask you."
    }

    // MARK: - My turn

    /// The target actually in force: my pick if still askable, else the only choice.
    private var chosenTarget: String? {
        if let target, view.askable.contains(target) { return target }
        return view.askable.count == 1 ? view.askable.first : nil
    }

    /// The ranks I hold, lowest first, each once.
    private var myRanks: [Int] {
        var out: [Int] = []
        for card in view.myHand ?? [] where !out.contains(card.rank) { out.append(card.rank) }
        return out
    }

    /// The rank actually in force: my pick if I still hold it.
    private var chosenRank: Int? {
        guard let rank, myRanks.contains(rank) else { return nil }
        return rank
    }

    private var askPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRSectionLabel(text: "Ask who?")
            VStack(spacing: 8) {
                ForEach(view.askable, id: \.self) { id in
                    targetButton(id)
                }
            }
            SRSectionLabel(text: "For which rank?")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: SR.tapTarget, maximum: 64), spacing: 8)], spacing: 8) {
                ForEach(myRanks, id: \.self) { r in
                    rankButton(r)
                }
            }
            Text(askSummary)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                ask()
            } label: {
                SRButtonLabel(title: "Ask", icon: "questionmark.bubble.fill", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(chosenTarget == nil || chosenRank == nil || sentTurn == view.turnNumber)
            .accessibilityHint(askSummary)
            .accessibilityIdentifier("offline-go-fish-ask")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private func targetButton(_ id: String) -> some View {
        let picked = chosenTarget == id
        let seat = view.seats.first { $0.id == id }
        let index = view.seats.firstIndex { $0.id == id } ?? 0
        return Button {
            SRHaptic.select()
            target = id
        } label: {
            HStack(spacing: 10) {
                OfflineInitial(name: context.name(of: id), size: 28, tone: OfflineSeatColour.of(index))
                Text(context.name(of: id))
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(picked ? SR.paper : SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(cardsText(seat?.cards ?? 0))
                    .font(SR.Text.mono())
                    .foregroundStyle(picked ? SR.paper : SR.inkMuted)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: SR.tapTarget)
            .background(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                    .fill(picked ? SR.accent : SR.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                    .stroke(picked ? SR.accent : SR.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask \(context.name(of: id)), \(cardsText(seat?.cards ?? 0))")
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("offline-go-fish-target-\(id)")
    }

    private func rankButton(_ r: Int) -> some View {
        let picked = chosenRank == r
        let held = (view.myHand ?? []).filter { $0.rank == r }.count
        return Button {
            SRHaptic.select()
            rank = r
        } label: {
            VStack(spacing: 0) {
                Text(GoFishRules.rankText(r))
                    .font(SR.Text.display(20))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("×\(held)")
                    .font(SR.Text.mono())
                    .lineLimit(1)
            }
            .foregroundStyle(picked ? SR.paper : SR.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(picked ? SR.accent : SR.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(picked ? SR.accent : SR.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(GoFishRules.rankName(r, plural: true)), you hold \(held)")
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("offline-go-fish-rank-\(r)")
    }

    private var askSummary: String {
        switch (chosenTarget, chosenRank) {
        case let (t?, r?):
            return "Ask \(context.name(of: t)) for \(GoFishRules.rankName(r, plural: true))."
        case (nil, _?):
            return "Now pick who to ask."
        case (_?, nil):
            return "Now pick a rank you hold."
        case (nil, nil):
            return "Pick who to ask and a rank you hold."
        }
    }

    private func ask() {
        guard myTurn, let t = chosenTarget, let r = chosenRank, sentTurn != view.turnNumber else { return }
        SRHaptic.tap()
        sentTurn = view.turnNumber
        context.send(.ask(turn: view.turnNumber, target: t, rank: r))
    }

    // MARK: - My hand

    private func handSection(_ hand: [OfflineCard]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Your hand", trailing: cardsText(hand.count))
            if hand.isEmpty {
                Text(view.stockCount > 0 ? "No cards — you draw five on your turn." : "No cards left to play.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if myTurn {
                OfflineHand(cards: hand, cardWidth: 60,
                            selected: Set(hand.filter { $0.rank == chosenRank }.map(\.id)),
                            onTap: { card in rank = card.rank })
                    .accessibilityIdentifier("offline-go-fish-hand")
            } else {
                OfflineHand(cards: hand, cardWidth: 60)
                    .accessibilityIdentifier("offline-go-fish-hand")
            }
            if let fished = view.myFished {
                Label("You fished the \(fished.name).", systemImage: "fish.fill")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("offline-go-fish-fished")
            }
        }
    }

    // MARK: - The table

    private var tableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "The table", trailing: "Pond \(view.stockCount)")
            VStack(spacing: 0) {
                ForEach(Array(view.seats.enumerated()), id: \.element.id) { index, seat in
                    if index > 0 { Divider().overlay(SR.divider) }
                    seatRow(seat, index: index)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("offline-go-fish-table")
    }

    private func seatRow(_ seat: GoFishRules.Seat, index: Int) -> some View {
        let asking = view.turn == seat.id
        return HStack(alignment: .top, spacing: 10) {
            OfflineInitial(name: seat.name, size: 30, tone: OfflineSeatColour.of(index))
                .opacity(seat.away ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(seat.id == context.me ? "You" : seat.name)
                        .font(SR.Text.title())
                        .foregroundStyle(seat.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if asking {
                        Image(systemName: "arrowtriangle.left.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SR.accent)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 6)
                    Text(seat.away ? "left" : cardsText(seat.cards))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(booksText(seat.books))
                    .font(SR.Text.mono())
                    .foregroundStyle(seat.books.isEmpty ? SR.inkGhost : SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("\(seat.books.count)")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .frame(minWidth: 26, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seatAccessibility(seat, asking: asking))
    }

    private func seatAccessibility(_ seat: GoFishRules.Seat, asking: Bool) -> String {
        var parts = [seat.id == context.me ? "You" : seat.name]
        if asking { parts.append("asking now") }
        parts.append(seat.away ? "left the game" : cardsText(seat.cards))
        let books = seat.books.sorted().map { GoFishRules.rankName($0, plural: true) }
        parts.append(books.isEmpty ? "no books" : "\(books.count) \(books.count == 1 ? "book" : "books"): \(books.joined(separator: ", "))")
        return parts.joined(separator: ", ")
    }

    private func booksText(_ books: [Int]) -> String {
        if books.isEmpty { return "No books yet" }
        return "Books: " + books.sorted().map(GoFishRules.rankText).joined(separator: " ")
    }

    private func cardsText(_ count: Int) -> String {
        count == 1 ? "1 card" : "\(count) cards"
    }

    // MARK: - The log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "What happened")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(view.log.reversed().enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().overlay(SR.divider) }
                    Text(sentence(entry))
                        .font(index == 0 ? SR.Text.bodyMedium(15) : SR.Text.secondary())
                        .foregroundStyle(index == 0 ? SR.ink : SR.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("offline-go-fish-log")
    }

    /// One ask, as a sentence: "Ann asked you for sevens and got 2."
    private func sentence(_ entry: GoFishRules.LogEntry) -> String {
        let asker = who(entry.asker)
        let target = entry.target == context.me ? "you" : context.name(of: entry.target)
        let ranks = GoFishRules.rankName(entry.rank, plural: true)
        var text = entry.timedOut ? "Time ran out. " : ""
        text += "\(asker) asked \(target) for \(ranks)"
        if entry.got > 0 {
            text += " and got \(entry.got)."
        } else if entry.luckyDraw {
            let one = GoFishRules.rankName(entry.rank, plural: false)
            let article = one == "ace" || one == "eight" ? "an" : "a"
            text += ". Go fish — and drew \(article) \(one)!"
        } else if entry.fished {
            text += ". Go fish."
        } else {
            text += ". Go fish — but the pond is empty."
        }
        if !entry.books.isEmpty {
            let made = entry.books.map { GoFishRules.rankName($0, plural: true) }.joined(separator: " and ")
            text += " Booked \(made)."
        }
        return text
    }
}

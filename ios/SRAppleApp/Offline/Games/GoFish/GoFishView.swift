import SwiftUI

/// Go Fish on one phone: whose turn it is, the pond with everyone sat round
/// it, my own hand, and — on my turn — who to ask and for what.
///
/// The view never changes the game: picking a player and a rank is local
/// `@State`, and Ask sends one action and waits for the host's next view.
/// Tapping a card in the hand picks its rank, so the hand and the rank
/// tiles are two ways to make the same choice.
///
/// The overhaul (2026-10-29) put the game on a pond-blue felt: the players
/// sit round the pond with their cards and books on their discs, the
/// latest ask is a speech bubble in the middle, and the moments that matter
/// — "Go fish!", a book made, cards taken from you — pop up and buzz.
struct GoFishView: View {
    let context: OfflineGameContext<GoFishRules>
    /// The player I mean to ask, before I send it.
    @State private var target: String?
    /// The rank I mean to ask for, before I send it.
    @State private var rank: Int?
    /// The turn number I last sent an ask on, so a double tap sends once.
    @State private var sentTurn: Int?
    /// The newest log entry already reacted to, so a redraw never re-pops.
    @State private var seenLog: Int?
    /// The pop-up words and what makes them pop.
    @State private var callout = ""
    @State private var calloutIcon: String?
    @State private var calloutTone: Color = SR.accentDeep
    @State private var calloutToken = 0
    @State private var burstToken = 0

    private var view: GoFishRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                status
                pond
                if myTurn {
                    askPanel
                }
                if let hand = view.myHand, !amAway {
                    handSection(hand)
                }
                if !view.log.isEmpty {
                    logSection
                }
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
                    .padding(.horizontal, SR.gutter)
            }
        }
        .accessibilityIdentifier("offline-go-fish")
        .onAppear { seenLog = view.log.last?.id }
        .onChange(of: view.turnNumber) { _, _ in
            sentTurn = nil
            if myTurn { SRHaptic.tap() }
        }
        .onChange(of: view.log.last?.id) { _, _ in
            reactToNewest()
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

    private func seatIndex(_ id: String) -> Int {
        view.seats.firstIndex { $0.id == id } ?? 0
    }

    private var status: some View {
        NearbyPlayBanner(kicker: kicker, title: headline, strap: instruction, mine: myTurn,
                         tone: OfflineSeatColour.of(seatIndex(view.turn ?? "")),
                         mark: bannerMark) {
            if view.phase == .playing {
                NearbyPlayBannerClock(clock: context.clock, until: view.turnEndsAt,
                                      total: GoFishRules.turnSeconds, mine: myTurn)
            }
        }
        .accessibilityIdentifier("offline-go-fish-status")
    }

    private var bannerMark: NearbyPlayMark {
        if view.phase == .over { return .symbol("trophy.fill") }
        guard let turn = view.turn else { return .symbol("fish.fill") }
        return .person(context.name(of: turn))
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

    // MARK: - The pond

    /// The felt: everyone round the pond, the pond itself, and the latest ask.
    private var pond: some View {
        NearbyPlayFelt(tone: .pond) {
            VStack(spacing: 14) {
                NearbyPlaySeatStrip(seats: stripSeats)
                HStack(alignment: .center, spacing: 16) {
                    GoFishPondArt(count: view.stockCount)
                        .frame(width: 96, height: 84)
                    VStack(alignment: .leading, spacing: 8) {
                        NearbyPlayStat(icon: "drop.fill", text: view.stockCount == 0 ? "Pond empty" : "Pond \(view.stockCount)", onFelt: true)
                        NearbyPlayStat(icon: "rectangle.stack.fill", text: "Books \(booksDown) of \(GoFishRules.totalBooks)", onFelt: true)
                    }
                    Spacer(minLength: 0)
                }
                if let last = view.log.last {
                    NearbyPlayBubble(text: sentence(last), icon: icon(for: last))
                        .id(last.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let mine = view.seats.first(where: { $0.id == context.me }), !mine.books.isEmpty {
                    myBooks(mine.books)
                }
            }
            .srAnimation(.snappy(duration: 0.3), value: view.log.last?.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-go-fish-table")
    }

    private var booksDown: Int { view.seats.reduce(0) { $0 + $1.books.count } }

    private var stripSeats: [NearbyPlaySeat] {
        view.seats.enumerated().map { pair -> NearbyPlaySeat in
            let index = pair.offset
            let seat = pair.element
            let asking = view.turn == seat.id && view.phase == .playing
            let champion = view.phase == .over && view.champions.contains(seat.id)
            return NearbyPlaySeat(
                id: seat.id, name: seat.name, tone: OfflineSeatColour.of(index),
                isMe: seat.id == context.me, acting: asking, faded: seat.away,
                badge: seat.away ? nil : "\(seat.cards)",
                detail: seat.away ? "left" : (seat.books.count == 1 ? "1 book" : "\(seat.books.count) books"),
                mark: champion ? "crown.fill" : nil,
                spoken: seatAccessibility(seat, asking: asking)
            )
        }
    }

    /// My books as little face-up stacks, so I can see what I have made.
    private func myBooks(_ books: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR BOOKS")
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(NearbyPlayFeltInk.secondary)
            // Wraps: thirteen books do not fit one line of a 375pt phone.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 40), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(books.sorted(), id: \.self) { r in
                Text(GoFishRules.rankText(r))
                    .font(SR.Text.title(15))
                    .foregroundStyle(Color(hex: 0x1F1D2B))
                    .frame(minWidth: 26, minHeight: 32)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(hex: 0xFFFDF8)))
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(hex: 0xFFFDF8).opacity(0.6))
                            .offset(x: 3, y: -3)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your books: " + books.sorted().map { GoFishRules.rankName($0, plural: true) }.joined(separator: ", "))
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
            stepLabel(1, "Ask who?", done: chosenTarget != nil)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(view.askable, id: \.self) { id in
                    targetButton(id)
                }
            }
            stepLabel(2, "For which rank?", done: chosenRank != nil)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 76), spacing: 8)], spacing: 10) {
                ForEach(myRanks, id: \.self) { r in
                    rankButton(r)
                }
            }
            NearbyPlayButton(title: askTitle, icon: "questionmark.bubble.fill", kind: .primary,
                             enabled: chosenTarget != nil && chosenRank != nil && sentTurn != view.turnNumber,
                             minHeight: 64) {
                ask()
            }
            .accessibilityHint(askSummary)
            .accessibilityIdentifier("offline-go-fish-ask")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func stepLabel(_ number: Int, _ text: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle.fill")
                .font(SR.Text.title(18))
                .foregroundStyle(done ? SR.good : SR.accent)
                .accessibilityHidden(true)
            Text(text.uppercased())
                .font(SR.Text.label())
                .tracking(1.3)
                .foregroundStyle(SR.inkMuted)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var askTitle: String {
        if sentTurn == view.turnNumber { return "Asking…" }
        guard let t = chosenTarget, let r = chosenRank else { return "Ask" }
        // "Ask Ann for aces", not "for As".
        return "Ask \(context.name(of: t)) for \(GoFishRules.rankName(r, plural: true))"
    }

    private func targetButton(_ id: String) -> some View {
        let picked = chosenTarget == id
        let seat = view.seats.first { $0.id == id }
        let index = seatIndex(id)
        let shape = RoundedRectangle(cornerRadius: NearbyPlayMetrics.radius, style: .continuous)
        return Button {
            SRHaptic.select()
            target = id
        } label: {
            HStack(spacing: 10) {
                OfflineInitial(name: context.name(of: id), size: 36, tone: OfflineSeatColour.of(index))
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.name(of: id))
                        .font(SR.Text.title(16))
                        .foregroundStyle(picked ? SR.paper : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(cardsText(seat?.cards ?? 0))
                        .font(SR.Text.mono())
                        .foregroundStyle(picked ? SR.paper.opacity(0.85) : SR.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(shape.fill(picked ? SR.accentDeep : SR.surface))
            .overlay(shape.strokeBorder(picked ? SR.accentDeep : SR.line, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel("Ask \(context.name(of: id)), \(cardsText(seat?.cards ?? 0))")
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("offline-go-fish-target-\(id)")
    }

    /// A rank as a little card: its letter, and how many of it I hold.
    private func rankButton(_ r: Int) -> some View {
        let picked = chosenRank == r
        let held = (view.myHand ?? []).filter { $0.rank == r }.count
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            SRHaptic.select()
            rank = r
        } label: {
            VStack(spacing: 2) {
                Text(GoFishRules.rankText(r))
                    .font(SR.Text.display(24))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("×\(held)")
                    .font(SR.Text.mono())
                    .lineLimit(1)
            }
            .foregroundStyle(picked ? SR.paper : Color(hex: 0x1F1D2B))
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(shape.fill(picked ? SR.accentDeep : Color(hex: 0xFFFDF8)))
            .overlay(shape.strokeBorder(picked ? SR.accentDeep : Color.black.opacity(0.16), lineWidth: picked ? 2 : 1))
            .shadow(color: Color.black.opacity(picked ? 0.25 : 0.1), radius: picked ? 6 : 2, x: 0, y: picked ? 4 : 1)
            .offset(y: picked ? -4 : 0)
            .contentShape(shape)
        }
        .buttonStyle(SRPressStyle())
        .srAnimation(.snappy(duration: 0.2), value: picked)
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
                OfflineHand(cards: hand, cardWidth: 66,
                            selected: Set(hand.filter { $0.rank == chosenRank }.map(\.id)),
                            onTap: { card in rank = card.rank })
                    .accessibilityIdentifier("offline-go-fish-hand")
            } else {
                OfflineHand(cards: hand, cardWidth: 66)
                    .accessibilityIdentifier("offline-go-fish-hand")
            }
            if let fished = view.myFished {
                HStack(spacing: 10) {
                    Image(systemName: "fish.fill")
                        .font(SR.Text.title(18))
                        .foregroundStyle(Color(hex: 0x2E8FCB))
                        .accessibilityHidden(true)
                    OfflineCardFace(card: fished, width: 34)
                    Text("You fished the \(fished.name).")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("You fished the \(fished.name).")
                .accessibilityIdentifier("offline-go-fish-fished")
            }
        }
    }

    // MARK: - The log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "What happened")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(view.log.reversed().enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().overlay(SR.divider) }
                    logRow(entry, newest: index == 0)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("offline-go-fish-log")
    }

    private func logRow(_ entry: GoFishRules.LogEntry, newest: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: entry))
                .font(SR.Text.title(15))
                .foregroundStyle(tone(for: entry))
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(sentence(entry))
                .font(newest ? SR.Text.bodyMedium(15) : SR.Text.secondary())
                .foregroundStyle(newest ? SR.ink : SR.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func icon(for entry: GoFishRules.LogEntry) -> String {
        if !entry.books.isEmpty { return "rectangle.stack.fill" }
        if entry.got > 0 { return "hand.raised.fill" }
        if entry.luckyDraw { return "sparkles" }
        return "fish.fill"
    }

    private func tone(for entry: GoFishRules.LogEntry) -> Color {
        if !entry.books.isEmpty || entry.got > 0 || entry.luckyDraw { return SR.good }
        return SR.accentInk
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

    // MARK: - Moments

    /// The newest ask, felt and seen: a book, a catch, a fish, a loss.
    private func reactToNewest() {
        guard let entry = view.log.last else { return }
        if let seen = seenLog, entry.id <= seen { return }
        seenLog = entry.id
        let ranks = GoFishRules.rankName(entry.rank, plural: true)
        if entry.asker == context.me {
            if !entry.books.isEmpty {
                let made = entry.books.map { GoFishRules.rankName($0, plural: true) }.joined(separator: " and ")
                pop("Book of \(made)!", icon: "rectangle.stack.fill", tone: SR.good)
                burstToken += 1
                SRHaptic.ok()
            } else if entry.got > 0 {
                pop("You got \(entry.got)!", icon: "hand.raised.fill", tone: SR.good)
                SRHaptic.ok()
            } else if entry.luckyDraw {
                pop("Lucky draw!", icon: "sparkles", tone: SR.good)
                SRHaptic.ok()
            } else {
                pop("Go fish!", icon: "fish.fill", tone: Color(hex: 0x1F6FB2))
                SRHaptic.tap()
            }
        } else if entry.target == context.me && entry.got > 0 {
            pop("\(context.name(of: entry.asker)) took your \(ranks)", icon: "hand.raised.fill", tone: SR.error)
            SRHaptic.bad()
        } else if !entry.books.isEmpty {
            pop("\(context.name(of: entry.asker)) made a book", icon: "rectangle.stack.fill", tone: SR.accentDeep)
        }
    }

    private func pop(_ text: String, icon: String?, tone: Color) {
        callout = text
        calloutIcon = icon
        calloutTone = tone
        calloutToken += 1
    }

    // MARK: - Words

    private func seatAccessibility(_ seat: GoFishRules.Seat, asking: Bool) -> String {
        var parts = [seat.id == context.me ? "You" : seat.name]
        if asking { parts.append("asking now") }
        parts.append(seat.away ? "left the game" : cardsText(seat.cards))
        let books = seat.books.sorted().map { GoFishRules.rankName($0, plural: true) }
        parts.append(books.isEmpty ? "no books" : "\(books.count) \(books.count == 1 ? "book" : "books"): \(books.joined(separator: ", "))")
        return parts.joined(separator: ", ")
    }

    private func cardsText(_ count: Int) -> String {
        count == 1 ? "1 card" : "\(count) cards"
    }
}

/// The pond: a few card backs fanned on the water, fewer as it empties,
/// with the count on a float. Art, hidden from VoiceOver (the count is in
/// the stat beside it).
struct GoFishPondArt: View {
    let count: Int

    var body: some View {
        ZStack {
            Ellipse()
                .fill(RadialGradient(colors: [Color(hex: 0x5BB6EA).opacity(0.55), Color(hex: 0x0B2A4C).opacity(0.2)],
                                     center: .center, startRadius: 4, endRadius: 52))
                .frame(width: 96, height: 56)
                .offset(y: 16)
            ForEach(0..<shown, id: \.self) { index in
                OfflineCardBack(width: 34)
                    .rotationEffect(.degrees(Double(index - shown / 2) * 12))
                    .offset(x: CGFloat(index - shown / 2) * 9, y: CGFloat(abs(index - shown / 2)) * 2)
            }
            if count == 0 {
                Image(systemName: "fish")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(NearbyPlayFeltInk.faint)
            }
        }
        .srAnimation(.snappy(duration: 0.3), value: shown)
        .accessibilityHidden(true)
    }

    private var shown: Int {
        if count <= 0 { return 0 }
        if count < 6 { return 1 }
        if count < 15 { return 2 }
        if count < 25 { return 3 }
        return 4
    }
}

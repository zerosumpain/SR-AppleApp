import SwiftUI

/// Sea Battle on one phone: placing your fleet, then the battle, one grid at
/// a time.
///
/// Five 8 × 8 grids side by side cannot fit a 375-point phone, so the battle
/// shows ONE grid — yours or an opponent's — chosen from a list of fleets
/// above it. Each grid is sized from the width it is given (a square of
/// about 33 points on the narrowest phone), never from its content.
///
/// While placing, your own grid is the editor: tap a ship to pick it, tap an
/// empty square to move its bow there, Rotate turns it about the bow. Each
/// change goes to the host at once, so the layout the minute runs out on is
/// the last one you made. While shooting, tap a square on an opponent's grid
/// to aim, then Fire (or tap the same square again), so a mis-tap costs
/// nothing.
///
/// Only your own phone is ever sent your ships; other grids show nothing but
/// shots and the ships that have sunk.
///
/// The overhaul (2026-10-29) put the grids on open sea: ships are drawn as
/// hulls with a bow and a stern rather than grey squares, a miss is a
/// splash, a hit burns, a sunk ship is a wreck (on enemy grids too, so you
/// can see what went down), the aim is a gold crosshair, and "Hit!",
/// "Miss" and "Sunk!" pop with the right buzz.
struct SeaBattleView: View {
    let context: OfflineGameContext<SeaBattleRules>
    /// My edited layout, shown until the host's view echoes it back.
    @State private var draft: [SeaBattleRules.Placement]?
    /// The ship picked for moving or turning, by its place in the fleet.
    @State private var chosenShip: Int? = 0
    /// The grid the player picked to look at; nil means the sensible default.
    @State private var boardChoice: String?
    /// The square aimed at but not yet fired on.
    @State private var aimed: Int?
    /// A shot or Ready has gone to the host and its answer has not come back.
    @State private var waiting = false
    /// I have told the host my phone is back after being marked away.
    @State private var sentBack = false
    @State private var callout = ""
    @State private var calloutTone: Color = SR.accentDeep
    @State private var calloutIcon: String?
    @State private var calloutToken = 0
    @State private var burstToken = 0

    private var view: SeaBattleRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                banner
                switch view.phase {
                case .placing:
                    placingSection
                case .firing, .done, .over:
                    battleSection
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
                NearbyPlayCallout(text: callout, icon: calloutIcon, tone: calloutTone, token: calloutToken, hold: 1.2)
            }
        }
        .onAppear { comeBackIfAway() }
        .onChange(of: view) { _, _ in
            waiting = false
            comeBackIfAway()
        }
        .onChange(of: view.myFleet) { _, new in
            if new == draft { draft = nil }
        }
        .onChange(of: view.phase) { _, new in
            draft = nil
            aimed = nil
            if new == .done {
                if view.winner == context.me {
                    SRHaptic.ok()
                    burstToken += 1
                } else if view.winner != nil {
                    SRHaptic.bad()
                }
            }
        }
        .onChange(of: view.turnNumber) { _, _ in
            aimed = nil
            if myTurn {
                SRHaptic.tap()
                // A new turn of mine: look at a fleet I can fire on.
                if let shown = shownBoard, shown.id == context.me || shown.out { boardChoice = nil }
            }
        }
        .onChange(of: view.lastShot) { _, new in
            guard let shot = new, view.phase != .placing else { return }
            if shot.target == context.me && shot.hit { SRHaptic.bad() }
            if shot.shooter == context.me && shot.sunk != nil { SRHaptic.ok() }
            popShot(shot)
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil {
                SRHaptic.bad()
                draft = nil
                waiting = false
            }
        }
        .task(id: waiting) {
            // A lost answer must not leave the grid locked: give up waiting
            // after a while.
            guard waiting else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { waiting = false }
        }
    }

    // MARK: - Who and what

    private var myBoard: SeaBattleRules.Board? {
        view.boards.first { $0.id == context.me }
    }

    /// I hold a fleet in this match and am still here.
    private var playing: Bool {
        guard let mine = myBoard else { return false }
        return !mine.away
    }

    private var iAmReady: Bool { myBoard?.ready ?? false }

    private var myTurn: Bool { view.phase == .firing && view.turnPlayer == context.me }

    /// The layout to draw for me: my edit if one is pending, else the host's.
    private var myFleet: [SeaBattleRules.Placement] { draft ?? view.myFleet ?? [] }

    private var canPlace: Bool { view.phase == .placing && playing && !iAmReady && !waiting }

    private func who(_ id: String) -> String {
        id == context.me ? "You" : context.name(of: id)
    }

    /// "your", "Ann's".
    private func whose(_ id: String) -> String {
        id == context.me ? "your" : "\(context.name(of: id))'s"
    }

    private var afloat: Int { view.boards.filter { !$0.out }.count }

    private var kicker: String {
        "Sea Battle · \(afloat) of \(view.boards.count) fleets afloat"
    }

    private var title: String {
        switch view.phase {
        case .placing:
            if !playing { return "Fleets are setting sail" }
            return iAmReady ? "Ready to sail" : "Place your fleet"
        case .firing:
            guard let turn = view.turnPlayer else { return "Sea Battle" }
            return turn == context.me ? "Your shot" : "\(context.name(of: turn))'s shot"
        case .done, .over:
            guard let winner = view.winner else { return "Battle over" }
            return winner == context.me ? "You win" : "\(context.name(of: winner)) wins"
        }
    }

    /// What to do now, in one sentence.
    private var strap: String? {
        switch view.phase {
        case .placing:
            if !playing { return "You are watching. The shooting starts when everyone is ready." }
            if iAmReady { return "Waiting for the others to place their ships." }
            return "Tap a ship, then a square to move it. Rotate turns it. Say Ready when you are happy."
        case .firing:
            if !playing { return "You are watching this battle." }
            if myBoard?.out == true { return "Your fleet is sunk. Watch the others finish it." }
            guard myTurn else { return "Wait for your turn. Keep an eye on your own grid." }
            let left = view.maxShots - view.shotsThisTurn
            if aimed != nil { return "Tap Fire, or the same square again, to shoot." }
            return left == view.maxShots
                ? "Pick a fleet, then tap a square to aim. A hit earns another shot."
                : "A hit! Fire again — \(left == 1 ? "1 shot" : "\(left) shots") left this turn."
        case .done, .over:
            return "The last fleet afloat takes the battle."
        }
    }

    private func seatTone(_ id: String?) -> Color {
        guard let id, let board = view.boards.first(where: { $0.id == id }) else { return SR.accent }
        return OfflineSeatColour.of(board.seat)
    }

    // MARK: - The top

    private var bannerMark: NearbyPlayMark {
        switch view.phase {
        case .placing: return .symbol("ferry.fill")
        case .firing: return view.turnPlayer.map { NearbyPlayMark.person(context.name(of: $0)) } ?? .symbol("scope")
        case .done, .over: return .symbol("trophy.fill")
        }
    }

    private var bannerMine: Bool {
        switch view.phase {
        case .placing: return canPlace
        case .firing: return myTurn
        case .done, .over: return view.winner == context.me
        }
    }

    private var banner: some View {
        NearbyPlayBanner(kicker: kicker, title: title, strap: strap, mine: bannerMine,
                         tone: seatTone(view.turnPlayer), mark: bannerMark) {
            bannerClock
        }
    }

    @ViewBuilder
    private var bannerClock: some View {
        switch view.phase {
        case .placing:
            NearbyPlayBannerClock(clock: context.clock, until: view.placeEndsAt,
                                  total: SeaBattleRules.placeSeconds, mine: canPlace)
                .accessibilityLabel("Ships sail soon")
                .accessibilityIdentifier("offline-sea-battle-place-clock")
        case .firing:
            NearbyPlayBannerClock(clock: context.clock, until: view.turnEndsAt,
                                  total: SeaBattleRules.turnSeconds, mine: myTurn)
        case .done:
            NearbyPlayBannerClock(clock: context.clock, until: view.doneUntil,
                                  total: SeaBattleRules.donePause, mine: false)
                .accessibilityLabel("Results soon")
        case .over:
            EmptyView()
        }
    }

    // MARK: - Placing

    @ViewBuilder
    private var placingSection: some View {
        if playing, let mine = myBoard {
            NearbyPlayFelt(tone: .ocean, padding: 8) {
                SeaBattleGrid(
                    size: view.size,
                    squares: squares(for: mine, fleet: myFleet, chosen: canPlace ? chosenShip : nil),
                    hulls: hullMarks(fleet: myFleet, sunk: []),
                    chosenShip: canPlace ? chosenShip : nil,
                    aimed: nil,
                    accessibilityName: "Your grid",
                    onTap: { placeTap($0) }
                )
            }
            .accessibilityIdentifier("offline-sea-battle-my-grid")
            if canPlace {
                shipPicker
                placeControls
            }
        }
        readinessCard
    }

    /// The four ships as buttons, two to a row, each with its hull drawn.
    private var shipPicker: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Array(view.fleetNames.enumerated()), id: \.offset) { index, name in
                shipButton(index, name: name)
            }
        }
    }

    private func shipButton(_ index: Int, name: String) -> some View {
        let length = view.fleetLengths.indices.contains(index) ? view.fleetLengths[index] : 0
        let picked = chosenShip == index
        let shape = RoundedRectangle(cornerRadius: NearbyPlayMetrics.radius, style: .continuous)
        return Button {
            SRHaptic.select()
            chosenShip = index
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(SR.Text.title(15))
                    .foregroundStyle(picked ? SR.paper : SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                SeaBattleShipIcon(length: length, tone: picked ? SR.paper : SR.inkSecondary)
                    .frame(height: 12)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(shape.fill(picked ? SR.accentDeep : SR.surface))
            .overlay(shape.strokeBorder(picked ? SR.accentDeep : SR.line, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel("\(name), \(length) squares")
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("offline-sea-battle-ship-\(index)")
    }

    private var placeControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                NearbyPlayButton(title: "Rotate", icon: "rotate.right", kind: .secondary, enabled: chosenShip != nil) {
                    rotate()
                }
                .accessibilityLabel(chosenShip.map { "Rotate the \(shipName($0))" } ?? "Rotate")
                .accessibilityIdentifier("offline-sea-battle-rotate")

                NearbyPlayButton(title: "Shuffle", icon: "shuffle", kind: .secondary) {
                    SRHaptic.tap()
                    draft = nil
                    context.send(.shuffle)
                }
                .accessibilityLabel("Shuffle: place my ships at random")
                .accessibilityIdentifier("offline-sea-battle-shuffle")
            }
            NearbyPlayButton(title: "Ready", icon: "checkmark", kind: .primary, minHeight: 64) {
                SRHaptic.ok()
                waiting = true
                context.send(.ready)
            }
            .accessibilityLabel("Ready: lock my fleet in")
            .accessibilityIdentifier("offline-sea-battle-ready")
        }
    }

    /// Who has said Ready.
    private var readinessCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(view.boards.enumerated()), id: \.element.id) { index, board in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    OfflineInitial(name: board.name, size: 30, tone: OfflineSeatColour.of(board.seat))
                    Text(who(board.id))
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(board.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    Text(board.away ? "left" : (board.ready ? "ready" : "placing"))
                        .font(SR.Text.mono(13))
                        .foregroundStyle(board.ready ? SR.good : SR.inkSecondary)
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: board.ready ? "checkmark.circle.fill" : "circle.dashed")
                        .font(SR.Text.title(17))
                        .foregroundStyle(board.ready ? SR.good : SR.inkMuted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 48)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(who(board.id)), \(board.away ? "left the game" : (board.ready ? "ready" : "still placing"))")
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-sea-battle-readiness")
    }

    // MARK: - The battle

    @ViewBuilder
    private var battleSection: some View {
        if view.phase == .firing, let turn = view.turnPlayer {
            shotsLine(turn)
        }
        if let line = lastShotText {
            NearbyPlayBubble(text: line, icon: lastShotIcon)
                .id(line)
                .transition(.opacity)
                .accessibilityIdentifier("offline-sea-battle-last-shot")
        }
        fleetPicker
        if let board = shownBoard {
            VStack(alignment: .leading, spacing: 10) {
                SRSectionLabel(text: board.id == context.me ? "Your waters" : "\(board.name)'s waters",
                               trailing: board.sunk.isEmpty ? nil : "\(board.sunk.count) sunk")
                    .lineLimit(1)
                NearbyPlayFelt(tone: .ocean, padding: 8) {
                    SeaBattleGrid(
                        size: view.size,
                        squares: squares(for: board, fleet: board.id == context.me ? view.myFleet : nil, chosen: nil),
                        hulls: hullMarks(fleet: board.id == context.me ? (view.myFleet ?? []) : [], sunk: board.sunk),
                        chosenShip: nil,
                        aimed: canFire(at: board) ? aimed : nil,
                        accessibilityName: board.id == context.me ? "Your grid" : "\(board.name)'s grid",
                        onTap: { aim($0, at: board) }
                    )
                }
                .accessibilityIdentifier("offline-sea-battle-grid")
                if let sunk = sunkSummary(board) {
                    Text(sunk)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("offline-sea-battle-sunk")
                }
            }
            if canFire(at: board) { fireControls(board) }
        }
    }

    /// "Your shot · 2 of 3" with a pip per shot.
    private func shotsLine(_ turn: String) -> some View {
        let shot = min(view.shotsThisTurn + 1, view.maxShots)
        return HStack(spacing: 10) {
            Text(turnText(turn))
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            HStack(spacing: 5) {
                ForEach(0..<max(1, view.maxShots), id: \.self) { index in
                    Image(systemName: index < shot ? "circle.fill" : "circle")
                        .font(SR.Text.label(12))
                        .foregroundStyle(index < view.shotsThisTurn ? SR.inkGhost : SR.accent)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, SR.cardPadding)
        .frame(minHeight: SR.tapTarget)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-sea-battle-turn")
    }

    private func turnText(_ turn: String) -> String {
        let shot = min(view.shotsThisTurn + 1, view.maxShots)
        let base = turn == context.me ? "Your shot" : "\(context.name(of: turn)) is aiming"
        return "\(base) · \(shot) of \(view.maxShots)"
    }

    /// The fleets as a list of rows — the picker for which grid to show.
    private var fleetPicker: some View {
        VStack(spacing: 0) {
            ForEach(Array(view.boards.enumerated()), id: \.element.id) { index, board in
                if index > 0 { Divider().overlay(SR.divider) }
                Button {
                    SRHaptic.select()
                    aimed = nil
                    boardChoice = board.id
                } label: {
                    fleetRow(board)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(fleetLabel(board))
                .accessibilityHint("Shows this grid")
                .accessibilityAddTraits(shownBoard?.id == board.id ? .isSelected : [])
                .accessibilityIdentifier("offline-sea-battle-fleet-\(index)")
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-sea-battle-fleets")
    }

    private func fleetRow(_ board: SeaBattleRules.Board) -> some View {
        let shown = shownBoard?.id == board.id
        return HStack(spacing: 10) {
            OfflineInitial(name: board.name, size: 32, tone: board.out ? SR.inkGhost : OfflineSeatColour.of(board.seat))
                .overlay { Circle().strokeBorder(shown ? SR.accent : Color.clear, lineWidth: 2.5).padding(-3) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(board.id == context.me ? "Your fleet" : board.name)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(board.out ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if view.turnPlayer == board.id {
                        Image(systemName: "scope")
                            .font(SR.Text.label(13))
                            .foregroundStyle(SR.accent)
                    }
                    if view.winner == board.id {
                        Image(systemName: "crown.fill")
                            .font(SR.Text.label(13))
                            .foregroundStyle(SR.warn)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(0..<max(0, min(board.shipsLeft, 6)), id: \.self) { _ in
                        SeaBattleShipIcon(length: 3, tone: SR.inkSecondary)
                            .frame(width: 22, height: 7)
                    }
                }
                .accessibilityHidden(true)
            }
            Spacer(minLength: 6)
            Text(fleetStatus(board))
                .font(SR.Text.mono(13))
                .foregroundStyle(board.out ? SR.error : SR.inkSecondary)
                .lineLimit(1)
                .fixedSize()
            Image(systemName: shown ? "eye.fill" : "chevron.right")
                .font(SR.Text.label(13))
                .foregroundStyle(shown ? SR.accent : SR.inkGhost)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func fleetStatus(_ board: SeaBattleRules.Board) -> String {
        if board.away { return "left" }
        if board.out { return "sunk" }
        return board.shipsLeft == 1 ? "1 ship" : "\(board.shipsLeft) ships"
    }

    private func fleetLabel(_ board: SeaBattleRules.Board) -> String {
        var parts = [board.id == context.me ? "Your fleet" : "\(board.name)'s fleet"]
        if board.away {
            parts.append("left the game")
        } else if board.out {
            parts.append("all ships sunk")
        } else {
            parts.append(board.shipsLeft == 1 ? "1 ship afloat" : "\(board.shipsLeft) ships afloat")
        }
        if view.turnPlayer == board.id { parts.append("aiming now") }
        if view.winner == board.id { parts.append("winner") }
        return parts.joined(separator: ", ")
    }

    private func sunkSummary(_ board: SeaBattleRules.Board) -> String? {
        if board.sunk.isEmpty { return nil }
        return "Sunk so far: " + board.sunk.map(\.name).joined(separator: ", ") + "."
    }

    /// The grid on show: the player's pick if it is still there, else the
    /// first opponent still afloat, else the first grid.
    private var shownBoard: SeaBattleRules.Board? {
        if let id = boardChoice, let picked = view.boards.first(where: { $0.id == id }) { return picked }
        return view.boards.first { $0.id != context.me && !$0.out } ?? view.boards.first
    }

    private func canFire(at board: SeaBattleRules.Board) -> Bool {
        myTurn && playing && !waiting && board.id != context.me && !board.out
    }

    private func fireControls(_ board: SeaBattleRules.Board) -> some View {
        HStack(spacing: 10) {
            NearbyPlayButton(title: aimed.map { "Fire at \(SeaBattleRules.coordinate($0))" } ?? "Fire",
                             icon: "scope", kind: .danger, enabled: aimed != nil, minHeight: 64) {
                if let cell = aimed { fire(cell, at: board) }
            }
            .accessibilityLabel(aimed.map { "Fire at \(SeaBattleRules.coordinate($0)) on \(whose(board.id)) grid" } ?? "Fire")
            .accessibilityIdentifier("offline-sea-battle-fire")

            NearbyPlayButton(title: "Clear", icon: "xmark", kind: .secondary, enabled: aimed != nil, minHeight: 64) {
                SRHaptic.select()
                aimed = nil
            }
            .frame(maxWidth: 130)
            .accessibilityLabel("Clear the aimed square")
            .accessibilityIdentifier("offline-sea-battle-clear")
        }
    }

    private var lastShotText: String? {
        guard let shot = view.lastShot else { return nil }
        let square = "\(whose(shot.target)) \(SeaBattleRules.coordinate(shot.cell))"
        let opening = shot.timedOut
            ? "Time ran out, so a shot went off for \(shot.shooter == context.me ? "you" : context.name(of: shot.shooter)) at \(square)"
            : "\(who(shot.shooter)) fired at \(square)"
        guard shot.hit else { return "\(opening) — a miss." }
        guard let sunk = shot.sunk else { return "\(opening) — a hit!" }
        if shot.knockedOut {
            let out = shot.target == context.me ? "your fleet is gone." : "\(context.name(of: shot.target)) is out."
            return "\(opening) and sank the \(sunk.lowercased()) — \(out)"
        }
        return "\(opening) and sank the \(sunk.lowercased())."
    }

    private var lastShotIcon: String {
        guard let shot = view.lastShot else { return "scope" }
        if shot.sunk != nil { return "flame.fill" }
        return shot.hit ? "burst.fill" : "drop.fill"
    }

    // MARK: - Shared

    private func shipName(_ index: Int) -> String {
        view.fleetNames.indices.contains(index) ? view.fleetNames[index].lowercased() : "ship"
    }

    /// What each square of `board` shows: my own ships only when `fleet` is
    /// given (my grid), then shots on top, then sunk ships on top of those.
    private func squares(for board: SeaBattleRules.Board, fleet: [SeaBattleRules.Placement]?, chosen: Int?) -> [SeaBattleSquare] {
        let count = view.size * view.size
        var out = Array(repeating: SeaBattleSquare.water, count: count)
        if let fleet {
            for (index, ship) in fleet.enumerated() {
                for cell in SeaBattleRules.cells(of: ship, ship: index) ?? [] where out.indices.contains(cell) {
                    out[cell] = index == chosen ? .chosen : .ship
                }
            }
        }
        for shot in board.shots where out.indices.contains(shot.cell) {
            out[shot.cell] = shot.hit ? .hit : .miss
        }
        for ship in board.sunk {
            for cell in ship.cells where out.indices.contains(cell) { out[cell] = .sunk }
        }
        return out
    }

    /// The hull each ship square belongs to: my own fleet, and every sunk
    /// ship (whose squares everyone has been shown).
    private func hullMarks(fleet: [SeaBattleRules.Placement], sunk: [SeaBattleRules.Sunk]) -> [Int: SeaBattleHullMark] {
        var ships: [[Int]] = fleet.enumerated().map { pair -> [Int] in
            SeaBattleRules.cells(of: pair.element, ship: pair.offset) ?? []
        }
        let offset = ships.count
        ships += sunk.map { $0.cells.sorted() }
        var marks = SeaBattleHull.marks(ships: ships, size: view.size)
        // Sunk wrecks are numbered after the fleet so a pick never lands on one.
        for (cell, mark) in marks where mark.ship >= offset {
            marks[cell] = SeaBattleHullMark(part: mark.part, across: mark.across, ship: -1)
        }
        return marks
    }

    // MARK: - Moments

    private func popShot(_ shot: SeaBattleRules.LastShot) {
        let mine = shot.shooter == context.me
        let atMe = shot.target == context.me
        guard mine || atMe else { return }
        if let sunk = shot.sunk {
            callout = mine ? "Sunk the \(sunk.lowercased())!" : "They sank your \(sunk.lowercased())"
            calloutIcon = "flame.fill"
            calloutTone = mine ? SR.good : SR.error
            if mine { burstToken += 1 }
        } else if shot.hit {
            callout = mine ? "Hit! Go again" : "You've been hit"
            calloutIcon = "burst.fill"
            calloutTone = mine ? Color(hex: 0xE4572E) : SR.error
        } else {
            callout = mine ? "Splash — a miss" : "They missed"
            calloutIcon = "drop.fill"
            calloutTone = Color(hex: 0x1C7C99)
        }
        calloutToken += 1
    }

    // MARK: - Acting

    /// The host marked me away while my phone was gone; seeing views again
    /// means I am back, so say so once.
    private func comeBackIfAway() {
        guard let seat = view.boards.first(where: { $0.id == context.me }) else { return }
        if seat.away {
            guard !sentBack, view.phase == .placing || view.phase == .firing else { return }
            sentBack = true
            context.send(.back)
        } else {
            sentBack = false
        }
    }

    /// A tap on my grid while placing: a ship's square picks that ship; an
    /// empty square moves the picked ship's bow there.
    private func placeTap(_ cell: Int) {
        guard canPlace else { return }
        var fleet = myFleet
        guard fleet.count == view.fleetLengths.count else { return }
        if let hit = fleet.indices.first(where: { (SeaBattleRules.cells(of: fleet[$0], ship: $0) ?? []).contains(cell) }) {
            SRHaptic.select()
            chosenShip = hit
            return
        }
        guard let index = chosenShip, fleet.indices.contains(index) else { return }
        let keep = fleet[index].across
        for across in [keep, !keep] {
            fleet[index] = SeaBattleRules.Placement(bow: cell, across: across)
            if SeaBattleRules.isValidFleet(fleet) {
                commit(fleet)
                return
            }
        }
        SRHaptic.bad()
    }

    /// Turn the picked ship about its bow, sliding it back if it would run
    /// off the grid.
    private func rotate() {
        guard canPlace, let index = chosenShip else { return }
        var fleet = myFleet
        guard fleet.indices.contains(index), view.fleetLengths.indices.contains(index) else { return }
        let old = fleet[index]
        let across = !old.across
        let step = across ? 1 : view.size
        for back in 0..<view.fleetLengths[index] {
            let bow = old.bow - back * step
            guard bow >= 0 else { break }
            if across && bow / view.size != old.bow / view.size { break }
            fleet[index] = SeaBattleRules.Placement(bow: bow, across: across)
            if SeaBattleRules.isValidFleet(fleet) {
                commit(fleet)
                return
            }
        }
        SRHaptic.bad()
    }

    private func commit(_ fleet: [SeaBattleRules.Placement]) {
        SRHaptic.select()
        draft = fleet
        context.send(.place(ships: fleet))
    }

    /// A tap on a grid while shooting: aim, or fire on a second tap.
    private func aim(_ cell: Int, at board: SeaBattleRules.Board) {
        guard canFire(at: board) else { return }
        if board.shots.contains(where: { $0.cell == cell }) {
            SRHaptic.bad()
            return
        }
        if aimed == cell {
            fire(cell, at: board)
        } else {
            SRHaptic.select()
            aimed = cell
        }
    }

    private func fire(_ cell: Int, at board: SeaBattleRules.Board) {
        guard canFire(at: board) else { return }
        SRHaptic.tap()
        waiting = true
        aimed = nil
        context.send(.fire(turn: view.turnNumber, target: board.id, cell: cell))
    }
}

/// What one square of a Sea Battle grid shows.
enum SeaBattleSquare: Equatable {
    case water
    /// One of my ships, not hit.
    case ship
    /// One of my ships, picked for moving.
    case chosen
    case miss
    case hit
    /// Part of a ship that has gone down.
    case sunk

    var spoken: String {
        switch self {
        case .water: return "water"
        case .ship: return "your ship"
        case .chosen: return "your ship, picked"
        case .miss: return "miss"
        case .hit: return "hit"
        case .sunk: return "sunk"
        }
    }
}

/// A ship as a little hull of `length` segments, for the pickers.
struct SeaBattleShipIcon: View {
    let length: Int
    let tone: Color

    var body: some View {
        GeometryReader { geo in
            let segment = geo.size.width / CGFloat(max(1, length))
            HStack(spacing: 0) {
                ForEach(0..<max(1, length), id: \.self) { index in
                    SeaBattleHullShape(part: SeaBattleHull.parts(count: max(1, length))[index], across: true,
                                       radius: geo.size.height / 2)
                        .fill(tone)
                        .frame(width: segment, height: geo.size.height)
                        .overlay(alignment: .trailing) {
                            if index < length - 1 {
                                Rectangle().fill(Color.black.opacity(0.15)).frame(width: 1)
                            }
                        }
                }
            }
        }
        .frame(maxWidth: 80)
        .accessibilityHidden(true)
    }
}

/// One square's piece of a hull: rounded at the bow and the stern, square
/// where it joins the next square of the same ship.
struct SeaBattleHullShape: Shape {
    let part: SeaBattleHullPart
    let across: Bool
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        var tl: CGFloat = 0, bl: CGFloat = 0, br: CGFloat = 0, tr: CGFloat = 0
        switch part {
        case .single:
            tl = r; bl = r; br = r; tr = r
        case .start:
            if across { tl = r; bl = r } else { tl = r; tr = r }
        case .end:
            if across { tr = r; br = r } else { bl = r; br = r }
        case .middle:
            break
        }
        return UnevenRoundedRectangle(topLeadingRadius: tl, bottomLeadingRadius: bl,
                                      bottomTrailingRadius: br, topTrailingRadius: tr,
                                      style: .continuous).path(in: rect)
    }
}

/// An 8 × 8 grid of sea with row letters and column numbers, sized from the
/// width it is given: the square side is the width over nine-and-a-bit
/// squares, and the aspect ratio fixes the height, so it never runs off a
/// phone. Ships are hulls across their squares; shots are splashes, fires
/// and wrecks. Fixed colours: it is the sea, the same in light and dark.
struct SeaBattleGrid: View {
    let size: Int
    let squares: [SeaBattleSquare]
    /// The hull piece each ship square shows, by square.
    var hulls: [Int: SeaBattleHullMark] = [:]
    /// The ship picked for moving, drawn in the accent.
    var chosenShip: Int? = nil
    let aimed: Int?
    /// "Your grid", "Ann's grid".
    let accessibilityName: String
    let onTap: (Int) -> Void

    /// The label row and column, as a fraction of a square.
    private static let rim: CGFloat = 0.6

    private var n: Int { max(size, 1) }

    var body: some View {
        GeometryReader { geo in
            let unit = max(1, geo.size.width / (CGFloat(n) + Self.rim))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: unit * Self.rim, height: unit * Self.rim)
                    ForEach(0..<n, id: \.self) { col in
                        Text("\(col + 1)")
                            .font(.system(size: max(8, unit * 0.32), weight: .semibold, design: .rounded))
                            .foregroundStyle(NearbyPlayFeltInk.secondary)
                            .frame(width: unit, height: unit * Self.rim)
                    }
                }
                .accessibilityHidden(true)
                ForEach(0..<n, id: \.self) { row in
                    HStack(spacing: 0) {
                        Text(SeaBattleGrid.letter(row))
                            .font(.system(size: max(8, unit * 0.32), weight: .semibold, design: .rounded))
                            .foregroundStyle(NearbyPlayFeltInk.secondary)
                            .frame(width: unit * Self.rim, height: unit)
                            .accessibilityHidden(true)
                        ForEach(0..<n, id: \.self) { col in
                            square(row * n + col, unit: unit)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(accessibilityName), \(n) by \(n)")
    }

    static func letter(_ row: Int) -> String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"]
        return letters.indices.contains(row) ? letters[row] : "?"
    }

    private func square(_ index: Int, unit: CGFloat) -> some View {
        let kind = squares.indices.contains(index) ? squares[index] : .water
        let isAimed = aimed == index
        return Button {
            onTap(index)
        } label: {
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .overlay { Rectangle().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5) }
                content(kind, index: index, unit: unit)
                if isAimed {
                    RoundedRectangle(cornerRadius: unit * 0.14, style: .continuous)
                        .strokeBorder(NearbyPlayFeltInk.gold, lineWidth: max(2, unit * 0.09))
                        .padding(unit * 0.04)
                    Image(systemName: "scope")
                        .font(.system(size: unit * 0.56, weight: .bold))
                        .foregroundStyle(NearbyPlayFeltInk.gold)
                        .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
                }
            }
            .frame(width: unit, height: unit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(SeaBattleRules.coordinate(index)), \(kind.spoken)\(isAimed ? ", aimed" : "")")
        .accessibilityIdentifier("offline-sea-battle-square-\(index)")
    }

    @ViewBuilder
    private func content(_ kind: SeaBattleSquare, index: Int, unit: CGFloat) -> some View {
        switch kind {
        case .water:
            EmptyView()
        case .miss:
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.65), lineWidth: max(1, unit * 0.06))
                    .frame(width: unit * 0.56, height: unit * 0.56)
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: unit * 0.18, height: unit * 0.18)
            }
        case .ship, .chosen:
            hull(index: index, unit: unit, fill: kind == .chosen ? SeaBattleGrid.chosenHull : SeaBattleGrid.steelHull)
        case .hit:
            ZStack {
                if hulls[index] != nil {
                    hull(index: index, unit: unit, fill: SeaBattleGrid.damagedHull)
                } else {
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: 0xFFD166), Color(hex: 0xE4572E)],
                                             center: .center, startRadius: 0, endRadius: unit * 0.4))
                        .frame(width: unit * 0.74, height: unit * 0.74)
                }
                Image(systemName: "flame.fill")
                    .font(.system(size: unit * 0.44, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFFF3D6))
                    .shadow(color: Color(hex: 0xE4572E), radius: 3, x: 0, y: 0)
            }
        case .sunk:
            ZStack {
                if hulls[index] != nil {
                    hull(index: index, unit: unit, fill: SeaBattleGrid.wreckHull)
                } else {
                    RoundedRectangle(cornerRadius: unit * 0.14, style: .continuous)
                        .fill(SeaBattleGrid.wreckHull)
                        .padding(unit * 0.08)
                }
                Image(systemName: "xmark")
                    .font(.system(size: unit * 0.36, weight: .heavy))
                    .foregroundStyle(Color(hex: 0xFF8A80))
            }
        }
    }

    /// A ship square's piece of hull, inset only across the ship so the
    /// pieces join into one boat along it.
    private func hull(index: Int, unit: CGFloat, fill: LinearGradient) -> some View {
        let mark = hulls[index] ?? SeaBattleHullMark(part: .single, across: true, ship: -1)
        let thin = unit * 0.16
        let end = unit * 0.06
        let leading: CGFloat = mark.across ? ((mark.part == .start || mark.part == .single) ? end : 0) : thin
        let trailing: CGFloat = mark.across ? ((mark.part == .end || mark.part == .single) ? end : 0) : thin
        let top: CGFloat = mark.across ? thin : ((mark.part == .start || mark.part == .single) ? end : 0)
        let bottom: CGFloat = mark.across ? thin : ((mark.part == .end || mark.part == .single) ? end : 0)
        return SeaBattleHullShape(part: mark.part, across: mark.across, radius: unit * 0.4)
            .fill(fill)
            .overlay {
                SeaBattleHullShape(part: mark.part, across: mark.across, radius: unit * 0.4)
                    .stroke(Color.black.opacity(0.25), lineWidth: 0.75)
            }
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .padding(.top, top)
            .padding(.bottom, bottom)
    }

    static let steelHull = LinearGradient(colors: [Color(hex: 0xC3CDD9), Color(hex: 0x6E7B90)],
                                          startPoint: .top, endPoint: .bottom)
    static let chosenHull = LinearGradient(colors: [Color(hex: 0xA48BFF), Color(hex: 0x5B3FD9)],
                                           startPoint: .top, endPoint: .bottom)
    static let damagedHull = LinearGradient(colors: [Color(hex: 0x9C6B5A), Color(hex: 0x5A3328)],
                                            startPoint: .top, endPoint: .bottom)
    static let wreckHull = LinearGradient(colors: [Color(hex: 0x3B4150), Color(hex: 0x1C1F28)],
                                          startPoint: .top, endPoint: .bottom)
}

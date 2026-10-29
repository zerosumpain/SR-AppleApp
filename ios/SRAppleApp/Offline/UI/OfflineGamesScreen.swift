import SwiftUI

/// Navigation value for the Play nearby page, pushed from the Games page and
/// from More.
struct OfflineGamesRef: Hashable {}

/// Play offline: games for this phone alone or for phones in the same room,
/// with no internet at all.
///
/// Nothing here needs Strange Ramblings. Alone, the phone runs the game and
/// fills any empty seats with computer players. Together, one phone hosts —
/// it runs the game and is the "server" — and up to four more join it over
/// Bluetooth, phone-to-phone Wi-Fi or a shared Wi-Fi or hotspot, all at once,
/// so nobody has to agree which. So it is open to everyone with the app,
/// paired or not, with games access or not. Results wait on the phone and go
/// to the family leaderboard when there is internet again.
///
/// The page is the front door: Play together first (your name, host or
/// join, over a drawing of phones in a room), the games you can play alone —
/// the ones played most here first — and the whole shelf, each game in its
/// shelf's colour. Once a room is open the room takes the whole screen as a
/// cover until somebody leaves.
struct OfflineGamesScreen: View {
    @ObservedObject private var session = OfflineSession.shared
    @ObservedObject private var results = OfflineResultStore.shared
    /// The game whose card was tapped: its how-to-play sheet.
    @State private var reading: OfflineCatalogueItem?
    /// A start chosen in the sheet, made once the sheet has gone — a cover
    /// cannot rise while a sheet is still leaving.
    @State private var pending: OfflinePendingStart?
    @State private var category: OfflineGameCategory?
    @FocusState private var naming: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(
                    kicker: "Play offline",
                    title: "Offline games",
                    strap: "No internet needed. Play alone against the phone, or with up to \(OfflineRoom.capacity - 1) more phones in the room. Results join the leaderboard when you are back online."
                )

                if let problem = session.problem, session.stage == .idle {
                    SRBanner(text: problem, tone: SR.error)
                        .onTapGesture { session.dismissProblem() }
                        .accessibilityIdentifier("offline-problem")
                }

                togetherCard
                if let line = results.statusLine { syncCard(line) }
                soloShelf
                catalogue
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("offline-games-screen")
        .srGround(.warm)
        .navigationTitle("Play offline")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reading, onDismiss: startPending) { item in
            OfflineHowToSheet(item: item) { start in
                pending = start
                reading = nil
            }
        }
        .fullScreenCover(isPresented: roomShown) {
            OfflineRoomScreen()
        }
    }

    /// The room covers the screen whenever there is one; it closes only by
    /// leaving.
    private var roomShown: Binding<Bool> {
        Binding(
            get: { session.inRoom },
            set: { shown in if !shown && session.inRoom { session.leave() } }
        )
    }

    private func startPending() {
        guard let start = pending else { return }
        pending = nil
        start.run(session)
    }

    // MARK: - Play together

    /// The front door: who you are, then Host or Find, over a drawing of
    /// phones talking to each other.
    private var togetherCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            OfflineNearbyArt(initial: artInitial)
                .frame(height: 104)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                Text("Play together")
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("One phone hosts, the others join. Bluetooth or Wi-Fi — whichever is on.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            nameField
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { hostButton; joinButton }
                VStack(spacing: 10) { hostButton; joinButton }
            }
            tips
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill(LinearGradient(colors: [SR.accent.opacity(0.12), Color.clear],
                                     startPoint: .top, endPoint: .bottom))
        )
        .srGlassCard(.paper)
    }

    /// Your initial, on the host phone in the middle of the drawing.
    private var artInitial: String {
        let mine = session.nickname.trimmingCharacters(in: .whitespaces)
        return mine.isEmpty ? "?" : String(mine.prefix(1)).uppercased()
    }

    private var nameField: some View {
        HStack(spacing: 12) {
            OfflineInitial(name: session.nickname.isEmpty ? "?" : session.nickname, size: 40, tone: SR.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR NAME")
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.inkMuted)
                TextField("Your name", text: $session.nickname)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($naming)
                    .onSubmit { naming = false }
                    .accessibilityLabel("Your name")
                    .accessibilityHint("Others see this name in the room")
                    .accessibilityIdentifier("offline-nickname")
            }
            Image(systemName: "pencil")
                .font(SR.Text.title(15))
                .foregroundStyle(SR.inkMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: OfflineKitMetrics.bigButton)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(SR.surface.opacity(0.7))
        )
        .overlay {
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .strokeBorder(naming ? SR.accent : SR.line, lineWidth: naming ? 1.5 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { naming = true }
    }

    private var tips: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.tips, id: \.self) { tip in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(SR.Text.label(13))
                            .foregroundStyle(SR.accent)
                            .accessibilityHidden(true)
                        Text(tip)
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("If phones cannot find each other", systemImage: "questionmark.circle")
                .font(SR.Text.bodyMedium(14))
                .foregroundStyle(SR.ink)
                .frame(minHeight: SR.tapTarget, alignment: .leading)
        }
        .tint(SR.accent)
        .accessibilityIdentifier("offline-tips")
    }

    private static let tips = [
        "Everyone needs the same version of the app — update together.",
        "Allow Local Network for SR Companion: Settings › Privacy & Security › Local Network.",
        "Turn Bluetooth and Wi-Fi on (Wi-Fi does not need to be joined to anything).",
        "Stay within a few metres, and keep the app open on the host's phone.",
        "Use Test connection in the room to check the link before a fast game.",
    ]

    private var hostButton: some View {
        OfflineKitButton(title: "Host a room", icon: "person.3.fill", prominent: true, id: "offline-host") {
            naming = false
            session.host()
        }
    }

    private var joinButton: some View {
        OfflineKitButton(title: "Find a room", icon: "magnifyingglass", prominent: false, id: "offline-join") {
            naming = false
            session.browse()
        }
    }

    // MARK: - Sync later

    private func syncCard(_ line: String) -> some View {
        SRCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: results.state == .syncing ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up")
                    .font(SR.Text.title(17))
                    .foregroundStyle(SR.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(SR.accent.opacity(0.14)))
                    .symbolEffect(.pulse, options: .repeating, isActive: results.state == .syncing)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(line)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if results.state != .syncing {
                        Button("Sync now") {
                            SRHaptic.tap()
                            results.syncSoon(force: true)
                        }
                        .font(SR.Text.bodyMedium(14))
                        .tint(SR.accent)
                        .frame(minHeight: SR.tapTarget)
                        .accessibilityIdentifier("offline-sync-now")
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("offline-sync")
    }

    // MARK: - Play alone

    /// Every game that can be played alone, the ones played most here first.
    private var soloItems: [OfflineCatalogueItem] {
        let solo = OfflineCatalogue.soloGames
        let order = OfflineShell.shelfOrder(solo.map(\.id), mostPlayed: results.mostPlayed(limit: solo.count))
        return order.compactMap { id in solo.first { $0.id == id } }
    }

    private var shelfColumns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 10)]
            : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    private var soloShelf: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Play alone", trailing: "\(soloItems.count)")
            LazyVGrid(columns: shelfColumns, spacing: 10) {
                ForEach(soloItems) { item in
                    Button {
                        SRHaptic.tap()
                        naming = false
                        session.playSolo(item.id)
                    } label: {
                        OfflineSoloTile(item: item, tally: results.queue.tallies[item.id])
                    }
                    .buttonStyle(SRPressStyle())
                    .accessibilityIdentifier("offline-solo-\(item.id)")
                }
            }
        }
    }

    // MARK: - Every game

    private var shownCategories: [OfflineGameCategory] {
        OfflineGameCategory.allCases.filter { category == nil || category == $0 }
    }

    private var catalogue: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Every game", trailing: "\(OfflineCatalogue.items.count)")
            filters
            ForEach(shownCategories) { section in
                catalogueSection(section)
            }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(nil, title: "All", count: OfflineCatalogue.items.count)
                ForEach(OfflineGameCategory.allCases) { option in
                    filterChip(option, title: option.title, count: OfflineCatalogue.games(in: option).count)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("offline-filter")
    }

    @ViewBuilder
    private func catalogueSection(_ section: OfflineGameCategory) -> some View {
        let items = OfflineCatalogue.games(in: section)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                OfflineShelfHeading(category: section, count: items.count)
                ForEach(items) { item in
                    Button {
                        SRHaptic.tap()
                        reading = item
                    } label: {
                        OfflineGameCard(item: item, tally: results.queue.tallies[item.id])
                    }
                    .buttonStyle(SRPressStyle())
                    .accessibilityIdentifier("offline-game-\(item.id)")
                }
            }
            .padding(.top, 4)
        }
    }

    private func filterChip(_ option: OfflineGameCategory?, title: String, count: Int) -> some View {
        let on = category == option
        let tone: Color = option.map { OfflineGameArt.hue($0).base } ?? SR.accent
        return Button {
            SRHaptic.select()
            category = option
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(SR.Text.bodyMedium(15))
                Text("\(count)")
                    .font(SR.Text.mono())
                    .opacity(0.75)
            }
            .foregroundStyle(on ? Color.white : SR.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: SR.tapTarget)
            .background(Capsule().fill(on ? tone : SR.surface.opacity(0.8)))
            .overlay(Capsule().stroke(on ? Color.clear : SR.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(SRPressStyle())
        .srAnimation(.snappy(duration: 0.2), value: on)
        .accessibilityLabel("\(title), \(count) games")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A start chosen in the how-to sheet, waiting for the sheet to go.
enum OfflinePendingStart: Equatable {
    case solo(String)
    case host(String)

    @MainActor
    func run(_ session: OfflineSession) {
        switch self {
        case .solo(let game): session.playSolo(game)
        case .host(let game): session.host(game: game)
        }
    }
}

// MARK: - Art

/// Three phones in a room, the middle one yours, with the air between them
/// humming: the Play together card's picture. Drawn once, still — nothing
/// here moves while the page sits idle.
struct OfflineNearbyArt: View {
    /// The letter on the middle phone's screen: yours.
    let initial: String

    var body: some View {
        let people: [Color] = [OfflineSeatColour.of(1), SR.accent, OfflineSeatColour.of(2)]
        let line = SR.ink.opacity(0.55)
        let wave = SR.accent.opacity(0.55)
        let phoneFill = SR.surface
        ZStack {
            Canvas { context, size in
                OfflineNearbyArt.draw(in: &context, size: size, people: people, line: line, wave: wave, shell: phoneFill)
            }
            GeometryReader { geo in
                let host = OfflineNearbyArt.phoneCentres(geo.size)[1]
                Text(initial)
                    .font(.system(size: host.size * 0.42, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                    .position(x: host.x, y: host.y)
            }
        }
        .accessibilityHidden(true)
    }

    struct Phone {
        let x: CGFloat
        let y: CGFloat
        /// The phone's width.
        let size: CGFloat
    }

    /// Where each phone sits: two guests either side, the host a little
    /// larger in the middle.
    static func phoneCentres(_ size: CGSize) -> [Phone] {
        let base = min(size.height * 0.48, size.width * 0.14)
        let y = size.height * 0.5
        return [
            Phone(x: size.width * 0.2, y: y + size.height * 0.06, size: base),
            Phone(x: size.width * 0.5, y: y, size: base * 1.2),
            Phone(x: size.width * 0.8, y: y + size.height * 0.06, size: base),
        ]
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, people: [Color], line: Color, wave: Color, shell fill: Color) {
        let phones = phoneCentres(size)
        // The air between: three arcs each way from the host.
        let host = phones[1]
        for side in [-1.0, 1.0] {
            for ring in 1...3 {
                let r = host.size * (0.75 + 0.32 * CGFloat(ring))
                var arc = Path()
                let centre = CGPoint(x: host.x, y: host.y)
                let mid: Double = side < 0 ? 180 : 0
                arc.addArc(center: centre, radius: r, startAngle: .degrees(mid - 28), endAngle: .degrees(mid + 28), clockwise: false)
                context.stroke(arc, with: .color(wave.opacity(1.0 - 0.25 * Double(ring))),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        for (index, phone) in phones.enumerated() {
            let w = phone.size, h = phone.size * 1.9
            let rect = CGRect(x: phone.x - w / 2, y: phone.y - h / 2, width: w, height: h)
            let outline = Path(roundedRect: rect, cornerRadius: w * 0.22, style: .continuous)
            context.fill(outline, with: .color(fill))
            context.stroke(outline, with: .color(line), lineWidth: 2)
            let screen = rect.insetBy(dx: w * 0.1, dy: w * 0.16)
            let tone = index < people.count ? people[index] : line
            context.fill(Path(roundedRect: screen, cornerRadius: w * 0.14, style: .continuous), with: .color(tone))
            let disc = CGRect(x: phone.x - w * 0.3, y: phone.y - w * 0.3, width: w * 0.6, height: w * 0.6)
            context.fill(Path(ellipseIn: disc), with: .color(Color.white.opacity(0.22)))
        }
    }
}

/// A shelf's heading: its colour, its name, how many games.
struct OfflineShelfHeading: View {
    let category: OfflineGameCategory
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(OfflineGameArt.hue(category).gradient)
                .frame(width: 18, height: 6)
                .accessibilityHidden(true)
            SRSectionLabel(text: category.title, trailing: "\(count)")
        }
    }
}

/// A game on the Play alone shelf: its badge, its name, who it is against,
/// and this phone's record.
struct OfflineSoloTile: View {
    let item: OfflineCatalogueItem
    let tally: OfflineTally?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                OfflineGameBadge(info: item.info, size: 46)
                Spacer(minLength: 4)
                Image(systemName: "play.circle.fill")
                    .font(SR.Text.display(24))
                    .foregroundStyle(OfflineGameArt.hue(item.info.category).base)
                    .accessibilityHidden(true)
            }
            Text(item.info.title)
                .font(SR.Text.title(16))
                .foregroundStyle(SR.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.opponentLine)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            if let tally, let played = OfflineShell.playedLine(tally.played) {
                HStack(spacing: 6) {
                    Text(played)
                    if let best = tally.best {
                        Text("· best \(best)")
                    }
                }
                .font(SR.Text.label())
                .tracking(0.6)
                .foregroundStyle(SR.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4, interactive: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Starts a game on this phone")
        .accessibilityAddTraits(.isButton)
    }
}

/// One game's card on the shelf: its badge, name, one line, and how it can
/// be played — alone, nearby, how many.
struct OfflineGameCard: View {
    let item: OfflineCatalogueItem
    var tally: OfflineTally? = nil

    private var info: OfflineGameInfo { item.info }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            OfflineGameBadge(info: info, size: 56)
            VStack(alignment: .leading, spacing: 5) {
                Text(info.title)
                    .font(SR.Text.display(20))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(info.blurb)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                OfflineTagRow(tags: item.modeTags, tone: OfflineGameArt.hue(info.category).base)
                    .padding(.top, 2)
                if let tally, let played = OfflineShell.playedLine(tally.played) {
                    Text(OfflineGameCard.recordLine(played, best: tally.best))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(SR.Text.label(13))
                .foregroundStyle(SR.inkGhost)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, interactive: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows how to play")
        .accessibilityAddTraits(.isButton)
    }

    /// "Played 3× · best 42".
    static func recordLine(_ played: String, best: Int?) -> String {
        guard let best else { return played }
        return played + " · best \(best)"
    }

    static func fill(_ category: OfflineGameCategory) -> Color {
        OfflineGameArt.hue(category).base
    }
}

/// A game's rules before anyone commits, and the ways to play it.
struct OfflineHowToSheet: View {
    let item: OfflineCatalogueItem
    let start: (OfflinePendingStart) -> Void
    @ObservedObject private var results = OfflineResultStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    OfflineGameHero(item: item, kicker: "\(item.info.category.title) · \(item.info.playersLabel)")
                    if let tally = results.queue.tallies[item.id], tally.played > 0 {
                        OfflineTallyStrip(tally: tally)
                    }
                    OfflinePlayButtons(item: item, start: start)
                    OfflineHowToCard(info: item.info)
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .srGround(.warm)
            .navigationTitle(item.info.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

/// A game's masthead: its badge large, a kicker, the title, its line and tags.
struct OfflineGameHero: View {
    let item: OfflineCatalogueItem
    let kicker: String
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Badge beside the title; above it at the accessibility sizes, where a
    /// 32pt title beside an 84pt badge would be one word a line.
    private var mast: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            mast {
                OfflineGameBadge(info: item.info, size: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(kicker.uppercased())
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(OfflineGameArt.hue(item.info.category).base)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.info.title)
                        .font(SR.Text.hero(32))
                        .tracking(-0.6)
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            Text(item.info.blurb)
                .font(SR.Text.body(16))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            OfflineTagRow(tags: item.modeTags, tone: OfflineGameArt.hue(item.info.category).base)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// This phone's record at a game: played, won, best.
struct OfflineTallyStrip: View {
    let tally: OfflineTally

    var body: some View {
        HStack(spacing: 10) {
            figure("\(tally.played)", label: "played", icon: "gamecontroller.fill")
            if tally.won > 0 { figure("\(tally.won)", label: "won", icon: "trophy.fill") }
            if let best = tally.best { figure("\(best)", label: "best", icon: "star.fill") }
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon)
                .font(SR.Text.label(13))
                .foregroundStyle(SR.accent)
                .accessibilityHidden(true)
            Text(value)
                .font(SR.Text.figure(26))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
    }
}

/// Play alone (when the game allows it) and Host nearby.
struct OfflinePlayButtons: View {
    let item: OfflineCatalogueItem
    let start: (OfflinePendingStart) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if item.canPlaySolo {
                OfflineKitButton(title: item.soloButtonTitle, icon: "person.fill", prominent: true,
                                 id: "offline-howto-solo") {
                    start(.solo(item.id))
                }
            }
            OfflineKitButton(title: "Host nearby", icon: OfflineTransport.auto.symbol, prominent: !item.canPlaySolo,
                             id: "offline-howto-host-nearby") {
                start(.host(item.id))
            }
            Text(item.canPlaySolo
                 ? "Alone, the phone plays the other seats. Nearby, others join from Find a room."
                 : "Others join from Find a room on their phones.")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The numbered rules of a game, in a card.
struct OfflineHowToCard: View {
    let info: OfflineGameInfo

    var body: some View {
        let tone = OfflineGameArt.hue(info.category).base
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "How to play")
            ForEach(Array(info.howToPlay.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(SR.Text.label(13))
                        .foregroundStyle(Color.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(tone))
                        .accessibilityHidden(true)
                    Text(line)
                        .font(SR.Text.body(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1). \(line)")
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
    }
}

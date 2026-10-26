import SwiftUI

/// Wildmind: the site's "Meanwhile, in the valley" chapter, native, as a page
/// in More — the owner's alone.
///
/// Wildmind is a small world where JKai and a companion have Claude for minds
/// and have to invent whatever they need. The page keeps the chapter's content
/// — the heading, a lede naming the two, the valley's map, and the readings
/// under it (what they have invented, what the referee threw out, the places
/// they have found, the family tree) — in the app's own paper-under-glass
/// look: section labels, glass cards and stat tiles, like Daydream beside it.
/// The map is drawn by the phone rather than shown in a web view, so it can be
/// pinched, panned and tapped, and it is polled only while it is on screen.
///
/// The data is `GET api/native/wildmind` (`WildmindStore`); the words follow
/// the site's rules (`WildmindWords`); the map is `WildmindMap`. Under the
/// heading, "Whisper to JKai" and the pages for what the map cannot show —
/// Talk, Chronicle and Inventions (`WildmindPages.swift`), read from the
/// owner-only lane.
struct WildmindScreen: View {
    @ObservedObject private var store = WildmindStore.shared
    /// "View as" hides the whisper button: the site refuses writes then.
    @ObservedObject private var access = AccessStore.shared
    @Environment(\.scenePhase) private var scenePhase
    /// The person whose card is shown under the map.
    @State private var selected: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                header
                if showsLinks { links }
                content
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("wildmind-screen")
        .srGround(.wire)
        .navigationTitle("Wildmind")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SRBarMark() } }
        // Polled while the page is up and the app is in front, and not
        // otherwise: SwiftUI cancels the task when either stops being true.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await store.poll()
        }
        .srRefreshable { await store.load() }
    }

    private var snapshot: WildmindSnapshot? { store.answer?.snapshot }
    private var mainName: String { snapshot?.main?.name ?? "JKai" }
    private var companionName: String { snapshot?.companion?.name ?? "Wren" }

    // MARK: - Header

    /// The page's head: the kicker, the heading, the lede naming the two, and
    /// the aside about the shirt with a dot of the orange it means.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRPageHeader(kicker: "wildmind", title: "Meanwhile, in the valley")
            Text(WildmindWords.lede(main: mainName, companion: companionName))
                .font(SR.Text.body(17))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(SR.accent)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(sentence(WildmindWords.shirt(main: mainName)))
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Talk, Chronicle, Inventions

    /// Not for a phone the site refused: those pages would refuse it too.
    private var showsLinks: Bool {
        if case .refused = store.phase { return false }
        return true
    }

    /// "Whisper to JKai" (not while viewing as someone else, when the site
    /// refuses writes), then the three pages the valley's words live on.
    private var links: some View {
        VStack(alignment: .leading, spacing: 12) {
            if access.viewingAs == nil {
                enterValley
                NavigationLink(value: WildmindPage.talk(compose: true)) {
                    SRButtonLabel(title: "Whisper to \(mainName)", icon: "ear", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("wildmind-whisper")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { pageLinks }
                VStack(alignment: .leading, spacing: 10) { pageLinks }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wildmind-links")
    }

    /// The way into the world itself: the desktop's valley, in 3D, full-screen.
    private var enterValley: some View {
        NavigationLink(value: WildmindPage.world) {
            HStack(spacing: 14) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(SR.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enter the valley")
                        .font(SR.Text.title(18))
                        .foregroundStyle(SR.ink)
                    Text("The world in 3D, with every panel, the economy and the controls")
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wildmind-enter-valley")
    }

    @ViewBuilder
    private var pageLinks: some View {
        pageLink("Talk", icon: "text.bubble", page: .talk(compose: false), id: "wildmind-open-talk")
        pageLink("Chronicle", icon: "book", page: .chronicle, id: "wildmind-open-chronicle")
        pageLink("Inventions", icon: "lightbulb", page: .inventions, id: "wildmind-open-inventions")
    }

    /// A small glass tile: the icon over the page's name. Three go across;
    /// at the larger text sizes they stack.
    private func pageLink(_ title: String, icon: String, page: WildmindPage, id: String) -> some View {
        NavigationLink(value: page) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(SR.accent)
                    .accessibilityHidden(true)
                Text(title.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 76)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    // MARK: - What there is to show

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .notOnSite:
            SREmpty(
                title: "Not on the site yet",
                icon: "map",
                message: "The valley isn\u{2019}t on this build of the site yet. It\u{2019}ll be drawn here once the site catches up."
            )
        case .refused:
            SREmpty(
                title: "Not on this phone",
                icon: "lock",
                message: "The valley is watched from the owner\u{2019}s phone."
            )
        case .failed(let message):
            SREmpty(
                title: "The valley didn\u{2019}t answer",
                icon: "wifi.slash",
                message: message,
                actionLabel: "Try again",
                action: retry
            )
        case .ready:
            if let snapshot {
                chapter(snapshot, state: store.state)
            } else {
                SREmpty(
                    title: "The valley\u{2019}s quiet",
                    icon: "moon.zzz",
                    message: "Wildmind isn\u{2019}t answering just now, so there\u{2019}s nothing to draw. The map comes back when it does."
                )
            }
        }
    }

    private func retry() {
        Task { await store.load() }
    }

    private func chapter(_ snapshot: WildmindSnapshot, state: WildmindState) -> some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            figure(snapshot, state: state)
            readings(snapshot, state: state)
        }
    }

    // MARK: - The map

    private func figure(_ snapshot: WildmindSnapshot, state: WildmindState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: WildmindWords.figureLabel(state, main: mainName))
            if let note = WildmindWords.stateNote(state, snapshot: snapshot) {
                Text(sentence(note))
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let grid = store.grid {
                WildmindMap(snapshot: snapshot, grid: grid, state: state, selected: $selected)
                    // Accessibility text past this size would cover the
                    // valley it names; the summary carries it for VoiceOver.
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("wildmind-map")
                if let person = snapshot.people.first(where: { $0.id == selected }) {
                    personCard(person, state: state)
                        .transition(.opacity)
                }
                WildmindKey()
                    .padding(.top, 4)
            } else {
                Text(store.fromPublicChapter
                     ? "The map needs a newer site than this one, so here are the valley\u{2019}s words without it."
                     : "Nobody\u{2019}s explored anywhere yet, so there\u{2019}s no map to draw.")
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(WildmindWords.caption(snapshot, state: state))
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    /// The card for the person tapped on the map.
    private func personCard(_ person: WildmindPerson, state: WildmindState) -> some View {
        let tone = WildmindTone.of(person)
        return SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Circle()
                        .fill(person.alive ? tone : tone.opacity(0.14))
                        .overlay { Circle().stroke(tone, lineWidth: 1.5) }
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    Text(person.name)
                        .font(SR.Text.display(22))
                        .tracking(-22 * 0.02)
                        .foregroundStyle(SR.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button {
                        SRHaptic.tap()
                        selected = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SR.inkMuted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(-12)
                    .accessibilityLabel("Close \(person.name)\u{2019}s card")
                    .accessibilityIdentifier("wildmind-person-card-close")
                }
                Text(sentence(WildmindWords.doingNear(person)))
                    .font(SR.Text.body(16))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    ledgerRow("Doing", person.alive ? person.doing : "dead")
                    ledgerRow("Near", person.near)
                    ledgerRow("Morale", WildmindWords.morale(person.morale))
                    ledgerRow("Mind", WildmindWords.mind(person))
                }
                .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wildmind-person-card")
    }

    /// A label…value line, as `SRRow` sets one. A value the site did not send
    /// is a dash, read as "not known".
    private func ledgerRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.inkMuted)
            Spacer(minLength: 8)
            Text(value ?? "\u{2014}")
                .font(SR.Text.body(15))
                .foregroundStyle(value == nil ? SR.inkMuted : SR.ink)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value ?? "not known")")
    }

    // MARK: - The readings

    private func readings(_ snapshot: WildmindSnapshot, state: WildmindState) -> some View {
        let stats = snapshot.stats
        return VStack(alignment: .leading, spacing: SR.sectionGap) {
            invented(stats)
            builtAndTamed(stats)
            familyTree(stats, state: state, time: snapshot.time)
            fairCopy(stats)
            Text("I\u{2019}ll write up how it works once it stops surprising me.")
                .font(SR.Text.secondary(15))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The four figures as tiles, then the newest inventions by name and how
    /// they think. A figure the site did not send is a dash, never 0.
    private func invented(_ stats: WildmindStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "What they\u{2019}ve made of it")
            SRTileGrid {
                SRStatTile(value: figureText(stats.invented), label: "Invented", caption: "in this valley")
                SRStatTile(value: stats.refused.map { "\u{00D7} \(WildmindWords.figure($0))" } ?? "\u{2014}",
                           label: "Turned down", caption: "by the referee")
                SRStatTile(value: figureText(stats.placesFound), label: "Places found", caption: "each one named")
                SRStatTile(value: figureText(stats.exploredTiles), unit: "tiles", label: "Explored",
                           caption: stats.exploredTiles.map(Self.area))
            }
            let parts = WildmindWords.latestParts(stats.latest)
            if !parts.isEmpty {
                parts.enumerated().reduce(Text("")) { text, item in
                    let part = item.element
                    return text + Text(item.offset == 0 && !part.isName ? sentence(part.text) : part.text)
                        .font(part.isName ? SR.Text.bodyMedium(15) : SR.Text.secondary(15))
                }
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            }
            if let line = WildmindWords.habitAndModels(stats) {
                Text(sentence(line))
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wildmind-readings")
    }

    private func figureText(_ value: Int?) -> String {
        value.map(WildmindWords.figure) ?? "\u{2014}"
    }

    /// "about two hectares": a tile is two metres a side.
    private static func area(_ tiles: Int) -> String {
        let hectares = Double(tiles) * 4 / 10_000
        if hectares < 0.75 { return "under a hectare" }
        if hectares < 1.5 { return "about a hectare" }
        // A word while it is short; past twenty a figure, so the tile's
        // one-line caption is never cut.
        let n = Int(hectares.rounded())
        return "about \(n < 20 ? WildmindWords.count(n) : WildmindWords.figure(n)) ha"
    }

    /// What they have built and tamed, one line each.
    private func builtAndTamed(_ stats: WildmindStats) -> some View {
        let built = stats.built
        let rows: [(one: String, many: String, count: Int)] = [
            ("shelter", "shelters", built.shelter),
            ("store", "stores", built.store),
            ("fire", "fires", built.fire),
            ("pen", "pens", built.pen),
            ("other thing", "other things", built.other),
            ("animal tamed", "animals tamed", stats.tamed ?? 0),
        ].filter { $0.count > 0 }
        return VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Built and tamed")
            if rows.isEmpty {
                Text("Nothing built yet, and nothing tamed.")
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.inkMuted)
            } else {
                SRCard {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows, id: \.many) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(sentence(row.count == 1 ? row.one : row.many))
                                    .font(SR.Text.body(15))
                                    .foregroundStyle(SR.ink)
                                Spacer(minLength: 8)
                                Text(WildmindWords.figure(row.count))
                                    .font(SR.Text.mono(13))
                                    .monospacedDigit()
                                    .foregroundStyle(SR.accent)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(row.count) \(row.count == 1 ? row.one : row.many)")
                        }
                    }
                }
            }
        }
    }

    /// The family tree: the last few lives in lower-case roman numerals, any
    /// older ones faded, and this one with its dot.
    private func familyTree(_ stats: WildmindStats, state: WildmindState, time: WildmindTime) -> some View {
        let shown = Array(stats.earlierLives.prefix(3).reversed())
        let earlier = max(stats.earlierLives.count, (stats.generation ?? 1) - 1)
        let older = max(0, earlier - shown.count)
        // Number by place in the line when the site numbered every life;
        // otherwise as a plain list, this life following the ones shown. The
        // "and n before them" row carries no numeral, so it does not shift
        // the count.
        let numbered = stats.generation != nil && shown.allSatisfy { $0.n != nil }
        let first = shown.count + 1
        return VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "The family tree")
            SRCard {
                VStack(alignment: .leading, spacing: 8) {
                    if older > 0 {
                        treeRow(nil, "and \(WildmindWords.count(older)) before them", ghost: true)
                    }
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, life in
                        treeRow(numbered ? life.n : index + 1, WildmindWords.lifeLine(life))
                    }
                    treeRow(numbered ? stats.generation : first, WildmindWords.thisLife(state, time: time),
                            living: state != .betweenLives)
                }
            }
            Text("When one dies, Claude reads back over the life and leaves the next a few lessons, which is roughly how families work too.")
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func treeRow(_ number: Int?, _ text: String, ghost: Bool = false, living: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number.map(WildmindWords.roman) ?? "")
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.accent)
                .frame(width: 34, alignment: .trailing)
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.body(16))
                .foregroundStyle(ghost ? SR.inkGhost : SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            if living {
                Circle()
                    .fill(SR.accent)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The line and the minds, as a short ledger.
    private func fairCopy(_ stats: WildmindStats) -> some View {
        SRCard {
            VStack(alignment: .leading, spacing: 8) {
                ledgerRow("Generation", WildmindWords.generation(stats.generation))
                ledgerRow("Minds", minds(stats.models))
            }
        }
    }

    private func minds(_ models: WildmindModels) -> String? {
        switch (models.mind, models.designer) {
        case let (mind?, designer?): return mind == designer ? mind : "\(mind) to think, \(designer) to invent"
        case let (mind?, nil): return "\(mind) to think"
        case let (nil, designer?): return "\(designer) to invent"
        case (nil, nil): return nil
        }
    }

    /// The site writes its asides in lower case (a notes rule); the app's
    /// copy is sentence case, so the first letter is raised here.
    private func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

/// The map's key: a swatch per ground in the map's own colours, then the
/// marks. Open ground is plain paper and has no entry, as on the site.
struct WildmindKey: View {
    private enum Swatch: Hashable {
        case ground(WildmindGround)
        case unexplored
        case hut
        case animal
    }

    private let items: [(String, Swatch)] = [
        ("woods", .ground(.wood)), ("marsh", .ground(.wet)), ("water", .ground(.fresh)),
        ("sea", .ground(.sea)), ("sand", .ground(.shore)), ("high ground", .ground(.high)),
        ("not explored yet", .unexplored), ("a hut", .hut), ("an animal", .animal),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12, alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 8) {
                    swatch(item.1)
                        .frame(width: 14, height: 14)
                    // Mono 12 at 0.06em in the softer ink, lower case, as
                    // the site sets its key.
                    Text(item.0)
                        .font(SR.Text.mono(12))
                        .tracking(12 * 0.06)
                        .foregroundStyle(SR.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        // The map's summary says what it shows; the key is for eyes.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func swatch(_ kind: Swatch) -> some View {
        switch kind {
        case .ground(let ground):
            let raw = Int(ground.rawValue)
            Rectangle()
                .fill(Color(light: WildmindPalette.light.grounds[raw], dark: WildmindPalette.night.grounds[raw]))
                .overlay {
                    if ground == .wood || ground == .high {
                        Canvas { context, size in
                            var hatch = Path()
                            var x: CGFloat = -size.height
                            while x < size.width {
                                hatch.move(to: CGPoint(x: x, y: size.height))
                                hatch.addLine(to: CGPoint(x: x + size.height, y: 0))
                                x += 4
                            }
                            context.stroke(hatch, with: .color(ground == .wood ? SR.good.opacity(0.55) : SR.ink.opacity(0.3)),
                                           lineWidth: 0.8)
                        }
                    }
                }
                .clipped()
                .overlay { Rectangle().stroke(SR.inkGhost, lineWidth: 1.5) }
        case .unexplored:
            ZStack {
                SR.paper
                SR.line.frame(height: 1)
            }
            .overlay { Rectangle().stroke(SR.inkGhost, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])) }
        case .hut:
            Rectangle()
                .fill(SR.inkSecondary)
                .frame(width: 7, height: 7)
        case .animal:
            Circle()
                .fill(SR.inkMuted)
                .frame(width: 5, height: 5)
        }
    }
}

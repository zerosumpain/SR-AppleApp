import SwiftUI
import UIKit

/// One Hometowns county, from the lobby to a town that keeps growing.
///
/// The lobby is every game's (`GameLobby`), with the county's settings as its
/// panel. A mayor with no town yet founds one (`HometownsFoundingView`). A
/// town is the Town screen (§9.2): the top bar and the Wants bar over the
/// map, the toolbar under it — Build · Lenses · Town Hall · People · County —
/// and, while a plan is on the map, the forecast card above the toolbar.
/// During the Founding Fortnight the bar over the toolbar is "Next week ▶",
/// and Bramble walks through the first three steps.
struct HometownsScreen: View {
    let roomId: String
    @StateObject private var store: HometownsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: HometownsStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                if store.wire?.town != nil {
                    ToolbarItem(placement: .topBarTrailing) { menu }
                }
            }
            .onAppear { store.open() }
            .onDisappear { store.close() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.open()
                    store.setPaused(false)
                } else if phase == .background {
                    store.setPaused(true)
                    store.close()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                store.thermalChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)) { _ in
                store.thermalChanged()
            }
            .overlay(alignment: .top) {
                if let message = store.message { SRBanner(text: message) }
            }
            .accessibilityIdentifier("hometowns-screen")
    }

    private var title: String {
        if let town = store.wire?.town { return town.name }
        return store.wire?.county?.name ?? "Hometowns"
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "hometowns-ended", done: { dismiss() })
        } else if let wire = store.wire, let room = store.room {
            switch wire.phase {
            case "lobby":
                GameLobby(room: room, store: store, prefix: "hometowns", done: { dismiss() },
                          panel: AnyView(HometownsCountyCard(wire: wire)))
            case "running":
                if wire.me == nil {
                    SREmpty(title: "You are not a mayor here", icon: "house",
                            message: "Ask a parent in the county to invite you.", actionLabel: "Done", action: { dismiss() })
                        .frame(maxHeight: .infinity)
                        .srPaper()
                } else if wire.town == nil {
                    HometownsFoundingView(store: store, wire: wire)
                } else {
                    HometownsTownView(store: store)
                }
            default:
                GameEndedView(id: "hometowns-ended", done: { dismiss() })
            }
        } else {
            ProgressView()
                .tint(SR.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
        }
    }

    private var menu: some View {
        Menu {
            Button {
                store.sheet = .welcomeBack
            } label: {
                Label(store.level == .kid ? "Today's news" : "Bulletin", systemImage: "newspaper")
            }
            Button {
                store.sheet = .county
            } label: {
                Label(store.wire?.county?.name ?? "The county", systemImage: "map")
            }
            if store.isParent {
                Button {
                    store.sheet = .parent
                } label: {
                    Label("Parent settings", systemImage: "person.2.badge.gearshape")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("hometowns-menu")
    }
}

// MARK: - Lobby

/// The county the host set up: its name and the Regional Day.
struct HometownsCountyCard: View {
    let wire: HometownsWire

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: GameKind.hometowns.icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(SR.good)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("A YEAR A DAY · UP TO SIX TOWNS")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Text(wire.county?.name ?? "Kingsport County")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text("Everyone builds a town around Kingsport. Towns grow while you're away, and the county settles up once a day at the Regional Day. A county of one is a real game.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hometowns-county-card")
    }
}

// MARK: - The Town screen (§9.2)

struct HometownsTownView: View {
    @ObservedObject var store: HometownsStore

    var body: some View {
        VStack(spacing: 0) {
            HometownsTopBar(store: store)
            HometownsWantsBar(store: store)
            map
            if store.plan != nil {
                HometownsForecastCard(store: store)
            } else if store.town?.inFortnight == true {
                HometownsSprintBar(store: store)
            }
            HometownsToolbar(store: store)
        }
        .srGround(.warm)
        .sheet(item: $store.sheet) { sheet in
            switch sheet {
            case .build: HometownsBuildSheet(store: store)
            case .lenses: HometownsLensSheet(store: store)
            case .townHall: TownHallSheet(store: store)
            case .people: PeopleSheet(store: store)
            case .county: HometownsCountyView(store: store)
            case .welcomeBack: WelcomeBackSheet(store: store)
            case .parent: ParentSettingsSheet(store: store)
            }
        }
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
        .accessibilityIdentifier("hometowns-town")
    }

    private var map: some View {
        HometownsMapView(store: store)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if let refusal = store.refusal {
                        Label(refusal, systemImage: "exclamationmark.circle")
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.paper)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(SR.error.opacity(0.92)))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("hometowns-refusal")
                    }
                    if let notice = store.notice {
                        Label(notice, systemImage: "checkmark.circle")
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.paper)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(SR.good.opacity(0.92)))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("hometowns-notice")
                    }
                    if store.town?.inFortnight == true, store.tutorial.step < 3 {
                        HometownsBrambleCard(store: store)
                    } else if store.plan == nil {
                        HometownsAdvisorStrip(store: store)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .overlay(alignment: .bottomTrailing) {
                if store.tool != .none {
                    Button {
                        store.setTool(.none)
                    } label: {
                        SRButtonLabel(title: "Done", icon: "checkmark")
                    }
                    .srButton(.regular)
                    .padding(12)
                    .accessibilityIdentifier("hometowns-tool-done")
                }
            }
            .sheet(item: $store.inspect) { card in
                InspectorSheet(store: store, card: card)
            }
    }
}

/// Town name and flag, the date, money with the day's ± arrow, population,
/// the mood face, and the mail envelope with a badge.
struct HometownsTopBar: View {
    @ObservedObject var store: HometownsStore
    @ScaledMetric(relativeTo: .headline) private var flagSize: CGFloat = 14

    var body: some View {
        if let town = store.town {
            HStack(spacing: 12) {
                Circle()
                    .fill(HometownsColour.flag(town.flag))
                    .overlay(Circle().stroke(SR.line, lineWidth: 1))
                    .frame(width: flagSize, height: flagSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(HometownsText.date(tick: town.tick))
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                    Text(store.copy.say("tier.\(town.tier)", store.level, or: HometownsCatalogue.tierName(town.tier)))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.accentInk)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("hometowns-date")
                Spacer(minLength: 4)
                Button { store.sheet = .townHall } label: { money(town) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hometowns-money")
                Button { store.sheet = .people } label: { people(town) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hometowns-people")
                Button { store.sheet = .welcomeBack } label: { mail }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hometowns-mail")
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 8)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius)
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }

    private func money(_ town: HometownsTown) -> some View {
        HStack(spacing: 3) {
            Text(HometownsText.money(town.money.reserves, store.level))
                .font(SR.Text.title(15).monospacedDigit())
                .foregroundStyle(town.money.reserves < 0 ? SR.error : SR.ink)
            if town.dayNet != 0 {
                Image(systemName: town.dayNet > 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(town.dayNet > 0 ? SR.good : SR.warn)
            }
        }
        .frame(minHeight: SR.tapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Money \(HometownsNumber.pounds(town.money.reserves))"
            + (town.dayNet == 0 ? "" : ", \(town.dayNet > 0 ? "up" : "down") \(HometownsNumber.pounds(abs(town.dayNet))) today"))
    }

    private func people(_ town: HometownsTown) -> some View {
        let mood = HometownsText.mood(town)
        return HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SR.inkMuted)
            Text(HometownsText.people(town.population))
                .font(SR.Text.title(15).monospacedDigit())
                .foregroundStyle(SR.ink)
            Image(systemName: HometownsText.moodSymbol(mood))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(mood >= 45 ? SR.good : SR.inkMuted)
        }
        .frame(minHeight: SR.tapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(HometownsText.people(town.population)) people, mood \(Int(mood.rounded())) out of 100")
    }

    private var mail: some View {
        let count = (store.wire?.me?.inbox.count ?? 0) + (store.wire?.county?.bulletin.isEmpty == false ? 1 : 0)
        return Image(systemName: "envelope.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(SR.accent)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text("\(min(count, 9))")
                        .font(SR.Text.label(12))
                        .foregroundStyle(SR.paper)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(SR.error))
                        .offset(x: 8, y: -8)
                }
            }
            .frame(minWidth: SR.tapTarget, minHeight: SR.tapTarget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(count > 0 ? "Mail, \(count) new" : "Mail")
    }
}

/// Six short bars under the top bar (§9.2): what the town wants to grow.
/// Homes shows the strongest of its three tiers, with a tick for each.
struct HometownsWantsBar: View {
    @ObservedObject var store: HometownsStore
    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 6

    var body: some View {
        let meters = store.wire?.me?.derived.meters ?? []
        if meters.count >= 8 {
            HStack(spacing: 8) {
                ForEach(bars(meters), id: \.key) { bar in
                    Button { store.sheet = .people } label: { cell(bar) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("hometowns-want-\(bar.key)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("What the town wants")
        }
    }

    struct Bar {
        let key: String
        let label: String
        /// −100 … 100.
        let value: Double
        let ticks: [Double]
    }

    private func bars(_ m: [Double]) -> [Bar] {
        let unlocked = Set(store.wire?.me?.affordances.unlocked ?? [])
        let copy = store.copy
        let level = store.level
        func name(_ zone: String) -> String { copy.say("zoneName.\(zone)", level, or: zone.capitalized) }
        var out = [Bar(key: "homes", label: name("homes"), value: m[0...2].max() ?? 0, ticks: Array(m[0...2]))]
        let rest: [(String, Int)] = [("shops", 3), ("leisure", 4), ("industry", 5), ("offices", 6), ("farms", 7)]
        for (zone, i) in rest where unlocked.contains("zone:\(zone)") || zone == "shops" || zone == "farms" {
            out.append(Bar(key: zone, label: name(zone), value: m[i], ticks: []))
        }
        return out
    }

    private func cell(_ bar: Bar) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(bar.label.uppercased())
                .font(SR.Text.label(12))
                .tracking(0.6)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { geo in
                let share = max(0, min(1, bar.value / 100))
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.line)
                    Capsule().fill(bar.value > 35 ? SR.accent : SR.accentInk.opacity(0.6))
                        .frame(width: geo.size.width * share)
                    ForEach(Array(bar.ticks.enumerated()), id: \.offset) { _, tick in
                        Rectangle()
                            .fill(SR.ink.opacity(0.5))
                            .frame(width: 1.5)
                            .offset(x: geo.size.width * max(0, min(1, tick / 100)))
                    }
                }
            }
            .frame(height: barHeight)
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bar.label): \(bar.value > 35 ? "wanted" : bar.value > 0 ? "a little wanted" : "not wanted now")")
    }
}

/// Build · Lenses · Town Hall · People · County.
struct HometownsToolbar: View {
    @ObservedObject var store: HometownsStore
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 19

    var body: some View {
        HStack(spacing: 0) {
            item("Build", "hammer.fill", .build, id: "build")
            item(store.level == .kid ? "Looking glass" : "Lenses", "eye.fill", .lenses, id: "lenses")
            item("Town Hall", "building.columns.fill", .townHall, id: "townhall")
            item("People", "person.3.fill", .people, id: "people")
            item("County", "map.fill", .county, id: "county")
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .accessibilityIdentifier("hometowns-toolbar")
    }

    private func item(_ title: String, _ icon: String, _ sheet: HometownsSheet, id: String) -> some View {
        Button {
            SRHaptic.tap()
            store.sheet = sheet
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(active(sheet) ? SR.accent : SR.ink)
                Text(title)
                    .font(SR.Text.label(12))
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: SR.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hometowns-toolbar-\(id)")
    }

    private func active(_ sheet: HometownsSheet) -> Bool {
        switch sheet {
        case .build: return store.tool != .none
        case .lenses: return store.lens != "none"
        default: return false
        }
    }
}

// MARK: - The Founding Fortnight (§2.3)

/// "Next week ▶" up to twelve times, ten seconds apart; adults may "Play it all".
struct HometownsSprintBar: View {
    @ObservedObject var store: HometownsStore

    var body: some View {
        if let town = store.town {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let wait = store.sprintWait()
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.say("sprint.left", ["n": .number(Double(town.sprintLeft))]))
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if town.sprintAuto {
                            Text(store.level == .kid ? "Playing the weeks for you…" : "Playing it all: a week every 15 seconds")
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                        } else if wait > 0 {
                            Text(store.say("sprint.wait"))
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                        }
                    }
                    Spacer(minLength: 6)
                    if store.level == .adult && !town.sprintAuto {
                        Button { store.playItAll() } label: { SRButtonLabel(title: store.say("sprint.playAll")) }
                            .srButton(.regular)
                            .accessibilityIdentifier("hometowns-play-all")
                    }
                    Button { store.nextWeek() } label: {
                        SRButtonLabel(title: wait > 0 ? "\(wait) s" : store.say("sprint.next"))
                            .monospacedDigit()
                    }
                    .srButton(.prominent)
                    .disabled(wait > 0 || town.sprintAuto || town.sprintLeft <= 0)
                    .accessibilityIdentifier("hometowns-next-week")
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 10)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .accessibilityIdentifier("hometowns-sprint")
        }
    }
}

/// Bramble's three steps (§1.5): a lane from the signpost, 12 Homes, 2 Farms and a Well.
struct HometownsBrambleCard: View {
    @ObservedObject var store: HometownsStore

    var body: some View {
        let lines = store.tutorial.lines(store.copy, store.level)
        let line = lines.0
        let hint = lines.1
        HStack(alignment: .top, spacing: 10) {
            HometownsMascot(advisor: "bramble")
            VStack(alignment: .leading, spacing: 4) {
                Text(line)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint {
                    Text(hint)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button { store.setTool(stepTool) } label: { SRButtonLabel(title: stepButton, icon: "hand.point.up.left.fill") }
                        .srButton(.prominent)
                        .accessibilityIdentifier("hometowns-tutorial-go")
                    Button { store.readAloud([line, hint].compactMap { $0 }.joined(separator: " ")) } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .srButton(.regular)
                    .accessibilityLabel("Read aloud")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hometowns-tutorial-\(store.tutorial.step)")
    }

    private var stepTool: HometownsTool {
        switch store.tutorial.step {
        case 0: return HometownsTool(kind: "road", variant: "lane")
        case 1: return HometownsTool(kind: "zone", variant: "homes")
        default:
            return store.tutorial.farms < 2 ? HometownsTool(kind: "zone", variant: "farms") : HometownsTool(kind: "place", id: "well", rot: 0)
        }
    }

    private var stepButton: String {
        switch store.tutorial.step {
        case 0: return "Draw a lane"
        case 1: return "Paint homes"
        default: return store.tutorial.farms < 2 ? "Paint farms" : "Place a well"
        }
    }
}

// MARK: - Advisors (§9.7)

/// At most three cards: one sentence, one button, read aloud on request.
struct HometownsAdvisorStrip: View {
    @ObservedObject var store: HometownsStore
    @State private var dismissed: Set<String> = []

    var body: some View {
        let cards = (store.wire?.me?.derived.advisors ?? []).filter { !dismissed.contains($0.key) }.prefix(3)
        if !cards.isEmpty {
            TabView {
                ForEach(Array(cards)) { card in
                    advisor(card).padding(.horizontal, 2).padding(.bottom, cards.count > 1 ? 22 : 0)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: cards.count > 1 ? .always : .never))
            .frame(height: 150)
            .accessibilityIdentifier("hometowns-advisors")
        }
    }

    private func advisor(_ card: HometownsAdvisorCard) -> some View {
        let line = store.say("advisor.\(card.key)")
        let button = card.action.map { store.say("action.\($0)") }
        return HStack(alignment: .top, spacing: 10) {
            HometownsMascot(advisor: card.advisor)
            VStack(alignment: .leading, spacing: 6) {
                Text(store.say("advisorName.\(card.advisor)").uppercased())
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.accent)
                Text(line)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    if let action = card.action, let button {
                        Button { store.follow(action) } label: { SRButtonLabel(title: button) }
                            .srButton(.prominent)
                            .accessibilityIdentifier("hometowns-advisor-\(card.key)")
                    }
                    Button { store.readAloud(line) } label: { Image(systemName: "speaker.wave.2.fill") }
                        .srButton(.regular)
                        .accessibilityLabel("Read aloud")
                    Button { dismissed.insert(card.key) } label: { Image(systemName: "xmark") }
                        .srButton(.regular)
                        .accessibilityLabel("Not now")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
    }
}

/// A mascot's badge: the animal's initial on its colour, until the art lands.
struct HometownsMascot: View {
    let advisor: String
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(SR.paper)
            .frame(width: size, height: size)
            .background(Circle().fill(colour))
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch advisor {
        case "penny": return "sterlingsign"
        case "mo": return "person.2.fill"
        case "zia": return "sparkles"
        default: return "pawprint.fill"
        }
    }

    private var colour: Color {
        switch advisor {
        case "penny": return SR.accentInk
        case "mo": return SR.good
        case "zia": return SR.accentDeep
        default: return SR.ink
        }
    }
}

// MARK: - The forecast card (§9.8)

/// Cost now, the change in monthly money and in people (p10–p90), happiness
/// by face, and "ready in". Children see arrows; adults the numbers.
struct HometownsForecastCard: View {
    @ObservedObject var store: HometownsStore

    var body: some View {
        if let plan = store.plan {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(store.say("forecast.cost", ["cost": .number(plan.cost)]))
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Spacer(minLength: 6)
                    afford(plan)
                }
                if let f = plan.forecast {
                    if let refused = f.refused {
                        Label(store.say("forecast.refused") + " " + refused, systemImage: "exclamationmark.triangle")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.error)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        lines(f)
                    }
                } else {
                    Text(store.say("forecast.working"))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
                HStack(spacing: 8) {
                    Button { store.planEdit("undo") } label: { Image(systemName: "arrow.uturn.backward") }
                        .srButton(.regular)
                        .accessibilityLabel("Take back the last ghost")
                        .accessibilityIdentifier("hometowns-plan-undo")
                    Button { store.planEdit("clear") } label: { SRButtonLabel(title: "Clear") }
                        .srButton(.regular)
                        .accessibilityIdentifier("hometowns-plan-clear")
                    Spacer(minLength: 0)
                    Button { store.planEdit("commit") } label: {
                        if store.committing {
                            ProgressView().tint(SR.paper)
                        } else {
                            SRButtonLabel(title: store.say("forecast.buildIt"), icon: "hammer.fill")
                        }
                    }
                    .srButton(.prominent)
                    .disabled(store.committing || plan.forecast?.refused != nil)
                    .accessibilityIdentifier("hometowns-build-it")
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("hometowns-forecast")
        }
    }

    @ViewBuilder
    private func afford(_ plan: HometownsPlan) -> some View {
        if let reserves = store.town?.money.reserves {
            // "Affordable in N" needs the monthly forecast; until the card has
            // one, an unaffordable plan just says so.
            Text(plan.cost <= reserves ? store.say("forecast.afford")
                 : (store.level == .kid ? "We need more coins first" : "More than the reserves"))
                .font(SR.Text.mono())
                .foregroundStyle(plan.cost <= reserves ? SR.good : SR.warn)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func lines(_ f: HometownsForecast) -> some View {
        let money = HometownsForecast.ends(f.monthly)
        let people = HometownsForecast.ends(f.people)
        let mLo = money.0, mHi = money.1, pLo = people.0, pHi = people.1
        let kid = store.level == .kid
        VStack(alignment: .leading, spacing: 4) {
            if kid {
                Text(kidLine(money: (mLo + mHi) / 2, people: (pLo + pHi) / 2))
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(store.say("forecast.money", ["lo": .number(mLo), "hi": .number(mHi)]))
                Text(store.say("forecast.people", ["lo": .number(pLo), "hi": .number(pHi)]))
            }
            Text(faces(f))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if f.readyTicks > 0 { Text(store.say("forecast.ready", ["ms": .number(f.readyMs)])) }
                if f.isEstimate { Text("· " + store.say("forecast.estimate")).foregroundStyle(SR.inkMuted) }
            }
            .font(SR.Text.mono())
            if f.seeds < 5 {
                Text(store.say("forecast.working")).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
            }
        }
        .font(SR.Text.secondary())
        .foregroundStyle(SR.ink)
    }

    /// "More people ↑ · money ↓ a little".
    private func kidLine(money: Double, people: Double) -> String {
        let p = people > 0.5 ? "More people ↑" : people < -0.5 ? "Fewer people ↓" : "About the same people"
        let m = money > 50 ? "money ↑" : money < -500 ? "money ↓" : money < -50 ? "money ↓ a little" : "money about the same"
        return "\(p) · \(m)"
    }

    /// Each face's change, as words: happier, a bit less happy, about the same.
    private func faces(_ f: HometownsForecast) -> String {
        let faces = ["workers", "professionals", "families", "retirees", "students"]
        let counts = store.wire?.myCard?.faces ?? []
        var parts: [String] = []
        for (i, range) in f.happy.enumerated() where i < faces.count {
            if counts.indices.contains(i), counts[i] == 0 { continue }
            let mid = range.count >= 2 ? range[1] : (range.first ?? 0)
            let key = mid > 0.5 ? "forecast.happier" : mid < -0.5 ? "forecast.lessHappy" : "forecast.sameHappy"
            parts.append(store.say(key, ["face": .text(faces[i])]))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Colours

enum HometownsColour {
    /// A town's flag colour (`flag.<n>` in the copy).
    static func flag(_ n: Int) -> Color {
        let colours = HometownsCatalogue.flagColours
        return Color(hex: colours[((n % colours.count) + colours.count) % colours.count])
    }
}

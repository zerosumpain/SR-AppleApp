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
///
/// The big moments — the town founded, a new tier, a round number of people —
/// stop the map for a card (`HometownsMomentCard`). Which ones this phone has
/// already shown is kept on the phone (`HometownsMilestoneStore`), so each is
/// celebrated once; a demo never shows one, so its screenshots stay still.
struct HometownsScreen: View {
    let roomId: String
    @StateObject private var store: HometownsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// This screen is the one showing (not covered by another pushed screen):
    /// coming back to the app reopens the county's stream only then, which is
    /// also what lets its pushes through while it is not being looked at.
    @State private var visible = false
    @State private var moment: HometownsMoment?
    @State private var howToPlay = false

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: HometownsStore(roomId: roomId))
    }

    var body: some View {
        framed
            .onAppear {
                visible = true
                store.open()
            }
            .onDisappear {
                visible = false
                store.close()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    if visible { store.open() }
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
            .onChange(of: stage) { old, new in
                // No town, then a town: this phone just founded it.
                if old == 1 && new == 2 { founded() }
            }
            .onChange(of: milestoneKey, initial: true) { _, _ in checkMilestones() }
            .accessibilityIdentifier("hometowns-screen")
    }

    /// The content in its navigation chrome, the banner and the moment over it.
    private var framed: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                if store.wire?.town != nil {
                    ToolbarItem(placement: .topBarTrailing) { menu }
                }
            }
            .overlay(alignment: .top) {
                if let message = store.message { SRBanner(text: message) }
            }
            .overlay { momentLayer }
            .sheet(isPresented: $howToPlay) {
                HometownsHowToPlaySheet(level: store.level)
            }
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
            HometownsLoadingView()
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
            Button {
                howToPlay = true
            } label: {
                Label("How to play", systemImage: "questionmark.circle")
            }
            .accessibilityIdentifier("hometowns-menu-how")
            if store.canPause {
                pauseButton
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
                .frame(minWidth: SR.tapTarget, minHeight: SR.tapTarget)
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("hometowns-menu")
    }

    /// Solo only: the sole mayor pauses or resumes their own county.
    @ViewBuilder
    private var pauseButton: some View {
        if store.countyPaused {
            Button {
                store.pause(false)
            } label: {
                Label("Resume the county", systemImage: "play.circle")
            }
            .accessibilityIdentifier("hometowns-menu-resume")
        } else {
            Button {
                store.pause(true)
            } label: {
                Label("Pause the county", systemImage: "pause.circle")
            }
            .accessibilityIdentifier("hometowns-menu-pause")
        }
    }

    // MARK: Moments

    /// 0 no frame yet, 1 a frame with no town of mine, 2 my town.
    private var stage: Int {
        guard let wire = store.wire else { return 0 }
        return wire.town == nil ? 1 : 2
    }

    /// Free for a card: no moment up, no sheet, and nothing being planned. A
    /// milestone that lands mid-drag waits (unrecorded) until the mayor is done,
    /// so a card never snatches the map from under a finger.
    private var idle: Bool {
        moment == nil && store.sheet == nil && store.inspect == nil && store.plan == nil && store.tool == .none
    }

    /// What the milestones watch: the tier, the head-count, and whether the
    /// screen is free (so a held-back milestone shows once it is).
    private var milestoneKey: [Int] {
        guard let town = store.town else { return [] }
        return [town.tier, town.population, idle ? 1 : 0]
    }

    @ViewBuilder
    private var momentLayer: some View {
        if let moment {
            HometownsMomentCard(moment: moment, level: store.level, openBuild: buildAction(moment), done: { closeMoment() })
                .transition(.opacity)
                .zIndex(10)
        }
    }

    private func closeMoment() {
        withAnimation(.easeOut(duration: 0.2)) { moment = nil }
    }

    /// After a new tier, "See what's new" opens Build.
    private func buildAction(_ m: HometownsMoment) -> (() -> Void)? {
        guard case .tierUp = m.kind else { return nil }
        return {
            closeMoment()
            store.sheet = .build
        }
    }

    private func founded() {
        guard !SRDemo.isOn, let town = store.town else { return }
        // The first look at the new town: recorded, so its founding numbers are not a milestone too.
        if let seat = store.wire?.me?.seat {
            _ = HometownsMilestoneStore().observe(roomId: roomId, seat: seat, tier: town.tier, population: town.population)
        }
        let title = store.level == .kid ? "Welcome to \(town.name)!" : "Welcome to \(town.name)"
        moment = HometownsMoment(kind: .founded, title: title, line: store.say("founding.done"),
                                 animal: town.avatar, flag: town.flag, tier: town.tier)
    }

    private func checkMilestones() {
        guard !SRDemo.isOn, idle, let town = store.town, let seat = store.wire?.me?.seat else { return }
        let milestones = HometownsMilestoneStore()
        guard let event = milestones.observe(roomId: roomId, seat: seat, tier: town.tier, population: town.population) else { return }
        let kid = store.level == .kid
        switch event {
        case .tierUp(let tier):
            let name = store.copy.say("tier.\(tier)", store.level, or: HometownsCatalogue.tierName(tier))
            moment = HometownsMoment(kind: .tierUp(tier),
                                     title: kid ? "\(town.name) is a \(name) now!" : "\(town.name) is now a \(name)",
                                     line: kid ? "More people means more to build. Have a look in Build!"
                                         : "New buildings, zones and lenses have opened. See what's new in Build.",
                                     animal: town.avatar, flag: town.flag, tier: tier)
        case .population(let n):
            let people = HometownsText.people(n)
            moment = HometownsMoment(kind: .population(n),
                                     title: kid ? "\(people) people live in \(town.name)!" : "\(town.name) passes \(people) people",
                                     line: kid ? "Your town keeps growing. Keep everyone happy!"
                                         : "Keep an eye on the Wants bar to keep the growth coming.",
                                     animal: town.avatar, flag: town.flag, tier: town.tier)
        }
    }
}

/// The county on its way: the drawn town under a quiet spinner, not a blank page.
struct HometownsLoadingView: View {
    var body: some View {
        ZStack {
            HometownsMapStandIn(town: nil)
                .opacity(0.45)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                ProgressView().tint(SR.accent)
                Text("Opening the county…")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srPaper()
        .accessibilityIdentifier("hometowns-loading")
    }
}

// MARK: - Lobby

/// The county the host set up: a little drawing of it, its name, and how a
/// county plays in three steps.
struct HometownsCountyCard: View {
    let wire: HometownsWire

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                HometownsMascot(advisor: "bramble", size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text("A YEAR A DAY · UP TO SIX TOWNS")
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(SR.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(wire.county?.name ?? "Kingsport County")
                        .font(SR.Text.display(21))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if wire.county != nil {
                HometownsRing(wire: wire)
                    .frame(height: 210)
                    .accessibilityHidden(true)
            }
            Text("Everyone builds a town around Kingsport. Towns grow while you're away, and the county settles up once a day at the Regional Day. A county of one is a real game.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                step("flag.fill", Color(hex: 0xD6463A), "Found a town on a free site")
                step("hammer.fill", HometownsZoneStyle.colour("shops"), "Plan roads and zones, then Build it!")
                step("sun.max.fill", Color(hex: 0xE0A030), "Come back after each Regional Day")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hometowns-county-card")
    }

    private func step(_ icon: String, _ colour: Color, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(SR.Text.label(13))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(colour))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - The Town screen (§9.2)

struct HometownsTownView: View {
    @ObservedObject var store: HometownsStore

    var body: some View {
        VStack(spacing: 0) {
            HometownsTopBar(store: store)
            if store.countyPaused {
                HometownsPausedBanner(store: store)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            HometownsWantsBar(store: store)
            map
            bottom
            HometownsToolbar(store: store)
        }
        .srAnimation(.snappy, value: store.plan != nil)
        .srAnimation(.snappy, value: store.countyPaused)
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
        // The store itself buzzes and reads a refusal or a notice aloud.
        .accessibilityIdentifier("hometowns-town")
    }

    /// The forecast card while a plan is on the map; else, in the founding fortnight, Next week.
    @ViewBuilder
    private var bottom: some View {
        if store.plan != nil {
            HometownsForecastCard(store: store)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if store.town?.inFortnight == true {
            HometownsSprintBar(store: store)
                .transition(.opacity)
        }
    }

    private var map: some View {
        HometownsMapView(store: store)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { mapTop }
            .overlay(alignment: .bottom) { toolStrip }
            .sheet(item: $store.inspect) { card in
                InspectorSheet(store: store, card: card)
            }
    }

    /// The map's top edge: a refusal or a notice, then Bramble or the advisors.
    private var mapTop: some View {
        VStack(spacing: 8) {
            if let refusal = store.refusal {
                HometownsMapToast(text: refusal, icon: "exclamationmark.circle.fill", tone: SR.error)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("hometowns-refusal")
            }
            if let notice = store.notice {
                HometownsMapToast(text: notice, icon: "checkmark.circle.fill", tone: SR.good)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("hometowns-notice")
            }
            if store.town?.inFortnight == true, store.tutorial.step < 3 {
                HometownsBrambleCard(store: store)
            } else if store.plan == nil {
                HometownsAdvisorStrip(store: store)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .srAnimation(.snappy, value: store.refusal)
        .srAnimation(.snappy, value: store.notice)
    }

    /// While a tool is in hand: what it is, and a big Done.
    @ViewBuilder
    private var toolStrip: some View {
        if store.tool != .none {
            HStack(spacing: 10) {
                Label(toolName, systemImage: toolIcon)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .srGlass(.paper, in: Capsule())
                    .accessibilityLabel("Using \(toolName)")
                    .accessibilityIdentifier("hometowns-tool-name")
                Spacer(minLength: 0)
                Button {
                    SRHaptic.tap()
                    store.setTool(.none)
                } label: {
                    HometownsBigLabel(title: "Done", icon: "checkmark")
                }
                .srButton(.prominent)
                .accessibilityIdentifier("hometowns-tool-done")
            }
            .padding(12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// The tool in hand, in words: "Homes", "Lane", "Well", "Bulldoze".
    private var toolName: String {
        let tool = store.tool
        switch tool.kind {
        case "zone":
            let zone = tool.variant ?? "homes"
            return store.copy.say("zoneName.\(zone)", store.level, or: zone.capitalized)
        case "road", "upgrade": return HometownsCatalogue.humanised(tool.variant ?? tool.id ?? "road")
        case "place": return HometownsCatalogue.humanised(tool.id ?? "building")
        case "dezone": return store.level == .kid ? "Rub out paint" : "Clear zoning"
        case "bulldoze": return "Bulldoze"
        case "parcel": return store.level == .kid ? "More land" : "New parcel"
        default: return HometownsCatalogue.humanised(tool.kind)
        }
    }

    private var toolIcon: String {
        let tool = store.tool
        switch tool.kind {
        case "zone": return HometownsZoneStyle.icon(tool.variant ?? "homes")
        case "road", "upgrade": return "road.lanes"
        case "dezone": return "eraser.fill"
        case "bulldoze": return "xmark.bin.fill"
        case "parcel": return "square.dashed"
        default: return "hammer.fill"
        }
    }
}

/// A short line over the map: a refusal in red, a notice in green.
struct HometownsMapToast: View {
    let text: String
    let icon: String
    let tone: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(SR.Text.bodyMedium(15))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(tone.opacity(0.94)))
            .shadow(color: Color.black.opacity(0.16), radius: 6, y: 2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The mayor and their tier, money with the day's arrow, people with the mood
/// face, and the mail with a badge; under them, the date and how far the town
/// is from its next tier. One row where it fits, two where it does not (a
/// small phone, a large text size).
struct HometownsTopBar: View {
    @ObservedObject var store: HometownsStore
    @ScaledMetric(relativeTo: .headline) private var badgeSize: CGFloat = 36
    @ScaledMetric(relativeTo: .caption) private var growthHeight: CGFloat = 6

    var body: some View {
        if let town = store.town {
            VStack(spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        identity(town)
                        Spacer(minLength: 2)
                        money(town)
                        people(town)
                        mail
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            identity(town)
                            Spacer(minLength: 2)
                            mail
                        }
                        HStack(spacing: 6) {
                            money(town)
                            people(town)
                            Spacer(minLength: 0)
                        }
                    }
                }
                growth(town)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius)
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }

    private func tierName(_ tier: Int) -> String {
        store.copy.say("tier.\(tier)", store.level, or: HometownsCatalogue.tierName(tier))
    }

    private func identity(_ town: HometownsTown) -> some View {
        HStack(spacing: 8) {
            HometownsCritterBadge(animal: town.avatar, ground: HometownsColour.flag(town.flag), size: badgeSize)
            Text(tierName(town.tier))
                .font(SR.Text.title(15))
                .foregroundStyle(SR.accentInk)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(town.name), \(tierName(town.tier))")
        .accessibilityIdentifier("hometowns-tier")
    }

    /// The date, then a bar to the next tier and how many more people it takes.
    private func growth(_ town: HometownsTown) -> some View {
        let g = HometownsGrowth.of(population: town.population, tier: town.tier)
        return HStack(spacing: 8) {
            Text(HometownsText.date(tick: town.tick))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .fixedSize()
                .accessibilityIdentifier("hometowns-date")
            if let next = g.nextTier {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SR.line)
                        Capsule()
                            .fill(LinearGradient(colors: [SR.good, SR.accent], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(growthHeight, geo.size.width * CGFloat(g.fraction)))
                    }
                }
                .frame(height: growthHeight)
                .srAnimation(.smooth(duration: 0.6), value: g.fraction)
                .accessibilityHidden(true)
                Text(g.needed > 0 ? "\(HometownsText.people(g.needed)) to \(tierName(next))" : "\(tierName(next)) soon")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(growthLabel(town, g))
        .accessibilityIdentifier("hometowns-growth")
    }

    private func growthLabel(_ town: HometownsTown, _ g: HometownsGrowth) -> String {
        let date = HometownsText.date(tick: town.tick)
        guard let next = g.nextTier else { return date }
        if g.needed == 0 { return "\(date). Nearly a \(tierName(next))" }
        return "\(date). About \(HometownsText.people(g.needed)) more people to become a \(tierName(next))"
    }

    private func money(_ town: HometownsTown) -> some View {
        Button {
            SRHaptic.tap()
            store.sheet = .townHall
        } label: {
            HStack(spacing: 4) {
                Text(HometownsText.money(town.money.reserves, store.level))
                    .font(SR.Text.title(15).monospacedDigit())
                    .foregroundStyle(town.money.reserves < 0 ? SR.error : SR.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .srNumeric(town.money.reserves)
                if town.dayNet != 0 {
                    Image(systemName: town.dayNet > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(SR.Text.label(12))
                        .foregroundStyle(town.dayNet > 0 ? SR.good : SR.warn)
                }
            }
            .padding(.horizontal, 9)
            .frame(minHeight: SR.tapTarget)
            .background(Capsule().fill(SR.ink.opacity(0.06)))
            .contentShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(moneyLabel(town))
        }
        .buttonStyle(SRPressStyle())
        .accessibilityHint("Opens Town Hall")
        .accessibilityIdentifier("hometowns-money")
    }

    private func moneyLabel(_ town: HometownsTown) -> String {
        let reserves = "Money \(HometownsNumber.pounds(town.money.reserves))"
        guard town.dayNet != 0 else { return reserves }
        return reserves + ", \(town.dayNet > 0 ? "up" : "down") \(HometownsNumber.pounds(abs(town.dayNet))) today"
    }

    private func people(_ town: HometownsTown) -> some View {
        let mood = HometownsText.mood(town)
        return Button {
            SRHaptic.tap()
            store.sheet = .people
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(SR.Text.label(12))
                    .foregroundStyle(SR.inkMuted)
                Text(HometownsText.people(town.population))
                    .font(SR.Text.title(15).monospacedDigit())
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .srNumeric(Double(town.population))
                Image(systemName: HometownsText.moodSymbol(mood))
                    .font(SR.Text.title(16))
                    .foregroundStyle(mood >= 45 ? SR.good : SR.inkMuted)
            }
            .padding(.horizontal, 9)
            .frame(minHeight: SR.tapTarget)
            .background(Capsule().fill(SR.ink.opacity(0.06)))
            .contentShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(HometownsText.people(town.population)) people, mood \(Int(mood.rounded())) out of 100")
        }
        .buttonStyle(SRPressStyle())
        .accessibilityHint("Opens People")
        .accessibilityIdentifier("hometowns-people")
    }

    private var mail: some View {
        let count = (store.wire?.me?.inbox.count ?? 0) + (store.wire?.county?.bulletin.isEmpty == false ? 1 : 0)
        return Button {
            SRHaptic.tap()
            store.sheet = .welcomeBack
        } label: {
            Image(systemName: "envelope.fill")
                .font(SR.Text.title(18))
                .foregroundStyle(SR.accent)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(min(count, 9))")
                            .font(SR.Text.label(12))
                            .foregroundStyle(Color.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Circle().fill(SR.error))
                            .offset(x: 10, y: -10)
                    }
                }
                .frame(minWidth: SR.tapTarget, minHeight: SR.tapTarget)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(count > 0 ? "Mail, \(count) new" : "Mail")
        }
        .buttonStyle(SRPressStyle())
        .accessibilityIdentifier("hometowns-mail")
    }
}

/// Six short bars under the top bar (§9.2): what the town wants to grow,
/// each in its zone's colour with its symbol. Homes shows the strongest of
/// its three tiers, with a tick for each.
struct HometownsWantsBar: View {
    @ObservedObject var store: HometownsStore
    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 8

    var body: some View {
        let meters = store.wire?.me?.derived.meters ?? []
        if meters.count >= 8 {
            HStack(spacing: 8) {
                ForEach(bars(meters), id: \.key) { bar in
                    Button {
                        SRHaptic.tap()
                        store.sheet = .people
                    } label: {
                        cell(bar)
                    }
                    .buttonStyle(SRPressStyle())
                    .accessibilityIdentifier("hometowns-want-\(bar.key)")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
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
        let wanted = bar.value > 35
        let colour = HometownsZoneStyle.colour(bar.key)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: HometownsZoneStyle.icon(bar.key))
                    .font(SR.Text.label(12))
                    .foregroundStyle(colour)
                Text(bar.label)
                    .font(SR.Text.label(12))
                    .foregroundStyle(wanted ? SR.ink : SR.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            meter(bar, colour: colour, wanted: wanted)
        }
        .frame(maxWidth: .infinity, minHeight: SR.tapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bar.label): \(bar.value > 35 ? "wanted" : bar.value > 0 ? "a little wanted" : "not wanted now")")
    }

    private func meter(_ bar: Bar, colour: Color, wanted: Bool) -> some View {
        GeometryReader { geo in
            let width: CGFloat = geo.size.width
            let share: CGFloat = CGFloat(max(0, min(1, bar.value / 100)))
            ZStack(alignment: .leading) {
                Capsule().fill(SR.line)
                Capsule()
                    .fill(colour.opacity(wanted ? 1 : 0.5))
                    .frame(width: width * share)
                    .shadow(color: colour.opacity(wanted ? 0.55 : 0), radius: 3)
                ForEach(Array(bar.ticks.enumerated()), id: \.offset) { _, tick in
                    Rectangle()
                        .fill(SR.ink.opacity(0.5))
                        .frame(width: 1.5)
                        .offset(x: width * CGFloat(max(0, min(1, tick / 100))))
                }
            }
        }
        .frame(height: barHeight)
        .srAnimation(.smooth(duration: 0.5), value: bar.value)
    }
}

/// Build first, as the big accent key; then Lenses · Town Hall · People · County.
struct HometownsToolbar: View {
    @ObservedObject var store: HometownsStore
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 21
    @ScaledMetric(relativeTo: .body) private var keyHeight: CGFloat = 56

    var body: some View {
        HStack(spacing: 4) {
            build
            item(store.level == .kid ? "Looking glass" : "Lenses", "eye.fill", .lenses, id: "lenses")
            item("Town Hall", "building.columns.fill", .townHall, id: "townhall")
            item("People", "person.3.fill", .people, id: "people")
            item("County", "map.fill", .county, id: "county")
        }
        .padding(6)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .accessibilityIdentifier("hometowns-toolbar")
    }

    private var build: some View {
        let holding = store.tool != .none
        let value: String = holding ? "A tool is in hand" : ""
        return Button {
            SRHaptic.tap()
            store.sheet = .build
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: iconSize, weight: .bold))
                    .accessibilityHidden(true)
                Text("Build")
                    .font(SR.Text.label(13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(Color.white)
            .frame(minWidth: 72, minHeight: keyHeight)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [SR.accent, SR.accentDeep], startPoint: .top, endPoint: .bottom))
            )
            .overlay(alignment: .topTrailing) {
                if holding {
                    Circle().fill(Color.white).frame(width: 8, height: 8).padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel("Build")
        .accessibilityValue(value)
        .accessibilityIdentifier("hometowns-toolbar-build")
    }

    private func item(_ title: String, _ icon: String, _ sheet: HometownsSheet, id: String) -> some View {
        let on = active(sheet)
        return Button {
            SRHaptic.tap()
            store.sheet = sheet
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(on ? SR.accent : SR.ink)
                    // VoiceOver reads the title, not the symbol's name first.
                    .accessibilityHidden(true)
                Text(title)
                    .font(SR.Text.label(12))
                    .foregroundStyle(on ? SR.accentInk : SR.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: keyHeight)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(on ? SR.accent.opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
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

/// The county is paused: nothing grows or is lost until it resumes. The sole
/// mayor of a solo county (`canPause`) resumes it from here.
struct HometownsPausedBanner: View {
    @ObservedObject var store: HometownsStore

    private var line: String {
        if store.level == .kid { return "Paused — your town is having a rest" }
        return "Paused — nothing changes until you resume"
    }

    var body: some View {
        HStack(spacing: 10) {
            label
            Spacer(minLength: 6)
            if store.canPause {
                resume
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hometowns-paused")
    }

    private var label: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .font(SR.Text.title(17))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(SR.accentInk))
                .accessibilityHidden(true)
            Text(line)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resume: some View {
        Button {
            SRHaptic.tap()
            store.pause(false)
        } label: {
            HometownsBigLabel(title: "Resume", icon: "play.fill")
        }
        .srButton(.prominent)
        .accessibilityIdentifier("hometowns-paused-resume")
    }
}

/// "Next week ▶" up to twelve times, ten seconds apart; adults may "Play it
/// all". The weeks are a row of dots, and while the button rests a ring runs
/// down round its count. The countdown ticks once a second only while there is
/// something to count; at rest nothing runs.
struct HometownsSprintBar: View {
    @ObservedObject var store: HometownsStore

    var body: some View {
        if let town = store.town {
            TimelineView(ExplicitTimelineSchedule(countdown())) { _ in
                row(town, wait: store.sprintWait())
            }
            .id("\(store.sprintWaitUntil)-\(town.sprintAt)")
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .accessibilityIdentifier("hometowns-sprint")
        }
    }

    /// One date a second until the button may be pressed again, then none.
    private func countdown() -> [Date] {
        let wait = store.sprintWait()
        guard wait > 0 else { return [] }
        let now = Date()
        return (0...wait).map { now.addingTimeInterval(Double($0)) }
    }

    private func row(_ town: HometownsTown, wait: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(store.say("sprint.left", ["n": .number(Double(town.sprintLeft))]))
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if town.sprintAuto {
                    Text(store.level == .kid ? "Playing the weeks for you…" : "Playing it all: a week every 15 seconds")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .multilineTextAlignment(.trailing)
                } else if wait > 0 {
                    Text(store.say("sprint.wait"))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .multilineTextAlignment(.trailing)
                }
            }
            // The dots and both keys on one row where they fit; the keys on
            // their own row under the dots where they do not (a small phone).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    weeks(town)
                    Spacer(minLength: 4)
                    keys(town, wait: wait)
                }
                VStack(alignment: .leading, spacing: 8) {
                    weeks(town)
                    HStack(spacing: 10) {
                        keys(town, wait: wait)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keys(_ town: HometownsTown, wait: Int) -> some View {
        if store.level == .adult && !town.sprintAuto {
            Button {
                SRHaptic.tap()
                store.playItAll()
            } label: {
                HometownsBigLabel(title: store.say("sprint.playAll"))
            }
            .srButton(.regular)
            .accessibilityIdentifier("hometowns-play-all")
        }
        next(town, wait: wait)
    }

    /// A dot a week: played ones filled.
    private func weeks(_ town: HometownsTown) -> some View {
        let w = HometownsSprintWeeks.of(left: town.sprintLeft)
        return HStack(spacing: 3) {
            ForEach(0..<w.total, id: \.self) { i in
                Circle()
                    .fill(i < w.done ? SR.accent : SR.line)
                    .frame(width: 7, height: 7)
            }
        }
        .srAnimation(.snappy, value: w.done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(w.done) of \(w.total) founding weeks played")
    }

    private func next(_ town: HometownsTown, wait: Int) -> some View {
        let resting = wait > 0
        return Button {
            SRHaptic.tap()
            store.nextWeek()
        } label: {
            HStack(spacing: 8) {
                if resting {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.35), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: CGFloat(max(0, min(1, 1 - Double(wait) / 10))))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .srAnimation(.linear(duration: 1), value: wait)
                    }
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                }
                HometownsBigLabel(title: resting ? "\(wait) s" : store.say("sprint.next"))
            }
        }
        .srButton(.prominent)
        .disabled(resting || town.sprintAuto || town.sprintLeft <= 0)
        .accessibilityLabel(resting ? "Next week, ready in \(wait) seconds" : store.say("sprint.next"))
        .accessibilityIdentifier("hometowns-next-week")
    }
}

/// Bramble's three steps (§1.5): a lane from the signpost, 12 Homes, 2 Farms
/// and a Well, as three chips that tick off, with a count of the homes.
struct HometownsBrambleCard: View {
    @ObservedObject var store: HometownsStore

    var body: some View {
        let lines = store.tutorial.lines(store.copy, store.level)
        let line = lines.0
        let hint = lines.1
        HStack(alignment: .top, spacing: 10) {
            HometownsMascot(advisor: "bramble", size: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text("BRAMBLE · STEP \(min(store.tutorial.step + 1, 3)) OF 3")
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.accent)
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
                steps
                HStack(spacing: 8) {
                    Button {
                        SRHaptic.tap()
                        store.setTool(stepTool)
                    } label: {
                        HometownsBigLabel(title: stepButton, icon: "hand.point.up.left.fill")
                    }
                    .srButton(.prominent)
                    .accessibilityIdentifier("hometowns-tutorial-go")
                    Button {
                        store.readAloud([line, hint].compactMap { $0 }.joined(separator: " "))
                    } label: {
                        HometownsIconLabel(icon: "speaker.wave.2.fill")
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

    private var steps: some View {
        let t = store.tutorial
        return HStack(spacing: 6) {
            chip(0, "road.lanes", store.level == .kid ? "Lane" : "Road", detail: nil)
            chip(1, "house.fill", "Homes", detail: t.step == 1 ? "\(min(t.homes, 12))/12" : nil)
            chip(2, "drop.fill", store.level == .kid ? "Food & water" : "Farms & well", detail: nil)
        }
        .srAnimation(.snappy, value: t.step)
    }

    private func chip(_ index: Int, _ icon: String, _ title: String, detail: String?) -> some View {
        let step = store.tutorial.step
        let done = index < step
        let now = index == step
        return HStack(spacing: 4) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .font(SR.Text.label(12))
            Text(detail.map { "\(title) \($0)" } ?? title)
                .font(SR.Text.label(12))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(done ? SR.good : (now ? SR.ink : SR.inkMuted))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(now ? SR.accent.opacity(0.16) : SR.line.opacity(0.5)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(done ? "done" : now ? "now" : "next")")
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
    @Environment(\.dynamicTypeSize) private var typeSize
    /// A paged strip needs a height; it grows with the reader's text size.
    @ScaledMetric(relativeTo: .body) private var stripHeight: CGFloat = 168

    var body: some View {
        // A child sees only advisors this build has words for: a rule newer than its copy file waits for the next build.
        let cards = (store.wire?.me?.derived.advisors ?? [])
            .filter { !dismissed.contains($0.key) && (store.level == .adult || store.copy.has("advisor.\($0.key)")) }
            .prefix(3)
        if !cards.isEmpty {
            if typeSize.isAccessibilitySize {
                // At the largest sizes no fixed height fits a card: the first one, at its own height.
                advisor(cards[cards.startIndex])
                    .accessibilityIdentifier("hometowns-advisors")
            } else {
                TabView {
                    ForEach(Array(cards)) { card in
                        advisor(card).padding(.horizontal, 2).padding(.bottom, cards.count > 1 ? 22 : 0)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: cards.count > 1 ? .always : .never))
                .frame(height: stripHeight)
                .accessibilityIdentifier("hometowns-advisors")
            }
        }
    }

    private func advisor(_ card: HometownsAdvisorCard) -> some View {
        let line = store.say("advisor.\(card.key)")
        let button = card.action.map { store.say("action.\($0)") }
        return HStack(alignment: .top, spacing: 10) {
            HometownsMascot(advisor: card.advisor, size: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text(store.say("advisorName.\(card.advisor)").uppercased())
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(line)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    if let action = card.action, let button {
                        Button {
                            SRHaptic.tap()
                            store.follow(action)
                        } label: {
                            HometownsBigLabel(title: button)
                        }
                        .srButton(.prominent)
                        .accessibilityIdentifier("hometowns-advisor-\(card.key)")
                    }
                    Spacer(minLength: 0)
                    Button { store.readAloud(line) } label: { HometownsIconLabel(icon: "speaker.wave.2.fill") }
                        .srButton(.regular)
                        .accessibilityLabel("Read aloud")
                    Button {
                        SRHaptic.select()
                        dismissed.insert(card.key)
                    } label: {
                        HometownsIconLabel(icon: "xmark")
                    }
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

/// An advisor's face on their colour: Bramble the badger, Mo the hedgehog,
/// Penny the magpie and Zia the otter, drawn (`HometownsCritterFace`).
struct HometownsMascot: View {
    let advisor: String
    var size: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        HometownsCritterBadge(animal: HometownsCritter.advisorAnimal(advisor), ground: colour, size: size * min(scale, 1.6))
    }

    private var colour: Color {
        switch advisor {
        case "penny": return Color(hex: 0x3F6FA8)
        case "mo": return Color(hex: 0xD9A441)
        case "zia": return Color(hex: 0x3E9A9A)
        default: return Color(hex: 0x6E8F5A)
        }
    }
}

// MARK: - The forecast card (§9.8)

/// Cost now, the change in monthly money and in people (p10–p90), happiness
/// by face, and "ready in". Children see arrows; adults the numbers. Build it!
/// is the big key, with take-back and Clear beside it.
struct HometownsForecastCard: View {
    @ObservedObject var store: HometownsStore

    var body: some View {
        if let plan = store.plan {
            VStack(alignment: .leading, spacing: 10) {
                header(plan)
                if let f = plan.forecast {
                    if let refused = f.refused {
                        Label(store.say("forecast.refused") + " " + refused, systemImage: "exclamationmark.triangle.fill")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.error)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        lines(f)
                    }
                } else {
                    working
                }
                buttons(plan)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("hometowns-forecast")
        }
    }

    private func header(_ plan: HometownsPlan) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "square.dashed.inset.filled")
                .font(SR.Text.title(18))
                .foregroundStyle(SR.accent)
                .accessibilityHidden(true)
            Text(store.say("forecast.cost", ["cost": .number(plan.cost)]))
                .font(SR.Text.title(18))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            afford(plan)
        }
    }

    private var working: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(SR.accent)
            Text(store.say("forecast.working"))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
        }
    }

    private func buttons(_ plan: HometownsPlan) -> some View {
        HStack(spacing: 8) {
            Button {
                SRHaptic.select()
                store.planEdit("undo")
            } label: {
                HometownsIconLabel(icon: "arrow.uturn.backward")
            }
            .srButton(.regular)
            .accessibilityLabel("Take back the last ghost")
            .accessibilityIdentifier("hometowns-plan-undo")
            Button {
                SRHaptic.select()
                store.planEdit("clear")
            } label: {
                HometownsBigLabel(title: "Clear")
            }
            .srButton(.regular)
            .accessibilityIdentifier("hometowns-plan-clear")
            Button {
                store.planEdit("commit")
            } label: {
                if store.committing {
                    ProgressView().tint(Color.white).frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    HometownsBigLabel(title: store.say("forecast.buildIt"), icon: "hammer.fill", fill: true)
                }
            }
            .srButton(.prominent)
            .disabled(store.committing || plan.forecast?.refused != nil)
            .accessibilityIdentifier("hometowns-build-it")
        }
    }

    @ViewBuilder
    private func afford(_ plan: HometownsPlan) -> some View {
        if let reserves = store.town?.money.reserves {
            // "Affordable in N" needs the monthly forecast; until the card has
            // one, an unaffordable plan just says so.
            let ok = plan.cost <= reserves
            Label(ok ? store.say("forecast.afford") : (store.level == .kid ? "We need more coins first" : "More than the reserves"),
                  systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(SR.Text.mono())
                .foregroundStyle(ok ? SR.good : SR.warn)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill((ok ? SR.good : SR.warn).opacity(0.12)))
        }
    }

    @ViewBuilder
    private func lines(_ f: HometownsForecast) -> some View {
        let money = HometownsForecast.ends(f.monthly)
        let people = HometownsForecast.ends(f.people)
        let mLo = money.0, mHi = money.1, pLo = people.0, pHi = people.1
        let kid = store.level == .kid
        VStack(alignment: .leading, spacing: 5) {
            if kid {
                Text(kidLine(money: (mLo + mHi) / 2, people: (pLo + pHi) / 2))
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(store.say("forecast.money", ["lo": .number(mLo), "hi": .number(mHi)]), systemImage: "sterlingsign.circle")
                Label(store.say("forecast.people", ["lo": .number(pLo), "hi": .number(pHi)]), systemImage: "person.2")
            }
            Label(faces(f), systemImage: "face.smiling")
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

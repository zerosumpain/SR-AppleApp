import SwiftUI

/// The hub: everything that is not a tab — News, Flows, Daydream, the family
/// boards — and Settings at the foot. Opened by the ⊞ at the top left of every
/// page (`SRHubButton`), the same for everyone (John, 2026-10-21: "one layout
/// for all"); there is no More tab.
///
/// Not iOS's More. That is a navigation controller wrapping each tab's own
/// `NavigationStack`, so a page opened from it had two bars and two back
/// buttons. The hub is pushed onto the tab you are on (`Router.openHub`), and
/// what it opens is pushed above it on the same stack: one bar, one back
/// button, the tab bar where it was.
///
/// A grid of doors, every one the same size, the ones this phone opens most
/// first (`HubUsage`; John, 2026-10-27). Each says what is waiting behind it
/// in one line. Games are a tab now, so their invitations are on the tab's
/// badge and page, not repeated here.
struct MoreScreen: View {
    /// What sits in More for this person, in bar order.
    let places: [Router.Tab]
    @ObservedObject var games: GamesStore
    /// Sync now lives here (and in Settings), off Today.
    @ObservedObject var companion: Companion
    @ObservedObject private var daydream = DaydreamStore.shared
    @ObservedObject private var feedback = NoticedFeedback.shared
    @ObservedObject private var commissions = CommissionStore.shared
    @ObservedObject private var steps = FamilyStepsStore.shared
    @ObservedObject private var tasks = FamilyTasksStore.shared
    @ObservedObject private var backlog = FamilyBacklogStore.shared
    @ObservedObject private var landgrab = LandgrabStore.shared
    @ObservedObject private var trips = TripStore.shared
    @ObservedObject private var access = AccessStore.shared
    @ObservedObject private var wildmind = WildmindStore.shared
    @ObservedObject private var offline = OfflineSession.shared
    @ObservedObject private var captures = CaptureStore.shared
    @ObservedObject private var recorder = CaptureRecorder.shared
    @EnvironmentObject private var router: Router
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Every door the same size (John, 2026-10-27: "always the same size"):
    /// three across, the mark, the name and one live line.
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 112
    /// The order this visit opened with. Counting a tap must not move the
    /// doors under the thumb on the way out; the next visit has the new order.
    @State private var order: [String] = []

    /// News, for whoever has it (John, 2026-10-05).
    private var showsNews: Bool { access.allows(.news) }

    /// Trips, so hiding the Home tile never hides them: the same rule as the
    /// Home tile (`HomeTileKind.trips`) — the family, over the site.
    private var showsTrips: Bool {
        (access.current.owner || access.current.family) && (SiteClient.shared.isPaired || SRDemo.isOn)
    }

    var body: some View {
        let entries = arranged
        ScrollView {
            // A plain stack: a handful of rows need no laziness, and a lazy
            // stack whose last child is measured at a different height than
            // it was estimated at loops at the bottom.
            VStack(alignment: .leading, spacing: SR.cardGap) {
                Text("Most used first")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .padding(.horizontal, 2)
                    .accessibilityHidden(true)
                ForEach(Array(rows(entries).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: SR.cardGap) {
                        ForEach(row) { entry in
                            HubTile(entry: entry) {
                                HubUsage.opened(entry.id)
                                entry.open()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        // A short last row keeps its doors the size of the rest.
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: typeSize.isAccessibilitySize ? nil : tileHeight)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("more-screen")
        .srGround(.warm)
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SRBarMark() } }
        .onAppear { order = HubUsage.load().ordered(items.map(\.id), now: Date()) }
        .task {
            if access.familyBoards {
                if steps.board == nil { await steps.load() }
                if tasks.board == nil { await tasks.load() }
                if backlog.board == nil { await backlog.load() }
                if landgrab.board == nil { await landgrab.load() }
            }
        }
        .srRefreshable {
            if access.familyBoards {
                await steps.load()
                await tasks.load()
                await backlog.load()
                await landgrab.load()
            }
        }
    }

    /// Three across; two from the largest standard text sizes, where a third
    /// of the width clips the names; one at the accessibility sizes.
    private var columns: Int {
        if typeSize.isAccessibilitySize { return 1 }
        return typeSize >= .xxLarge ? 2 : 3
    }

    private func rows(_ entries: [HubEntry]) -> [[HubEntry]] {
        stride(from: 0, to: entries.count, by: columns).map { Array(entries[$0..<min($0 + columns, entries.count)]) }
    }

    /// The doors in this visit's order. One gained since the visit began
    /// (access arriving) goes at the end rather than reshuffling the rest.
    private var arranged: [HubEntry] {
        let all = items.map(entry)
        let rank = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
        return all.enumerated()
            .sorted { (rank[$0.element.id] ?? order.count + $0.offset, $0.offset) < (rank[$1.element.id] ?? order.count + $1.offset, $1.offset) }
            .map(\.element)
    }

    private func taskStatus(_ summary: FamilyTasksSummary) -> String? {
        if summary.parent && summary.awaiting > 0 {
            return summary.awaiting == 1 ? "1 to confirm" : "\(summary.awaiting) to confirm"
        }
        return summary.toDo > 0 ? "\(summary.toDo) to do" : nil
    }

    /// Recording now, waiting on the phone, or follow-ups to decide.
    private var captureStatus: String? {
        if recorder.recording { return "Recording" }
        if !captures.queue.isEmpty { return captures.queue.count == 1 ? "1 waiting to send" : "\(captures.queue.count) waiting to send" }
        let open = captures.items.reduce(0) { $0 + $1.actionsOpen }
        return open > 0 ? (open == 1 ? "1 to decide" : "\(open) to decide") : nil
    }

    private var toDecide: Int {
        daydream.toDecide(feedback: feedback, commissions: commissions)
    }

    /// What sits in More, as doors.
    enum Item: Hashable {
        case trips, news, daydream, wildmind, captures, steps, tasks, backlog, messages, landgrab, travel, offline, sync, settings
        case place(Router.Tab)

        /// The door's identifier (`more-<id>`, which the UI tests find it
        /// by) and its key in `HubUsage`.
        var id: String {
            switch self {
            case .place(let tab): return tab.rawValue
            case .settings: return "settings"
            default: return String(describing: self)
            }
        }
    }

    /// Every door this person has, in the hub's own order — the order a new
    /// install sees, and the tie-break for doors used equally.
    private var items: [Item] {
        var all: [Item] = []
        if showsTrips { all.append(.trips) }
        if showsNews { all.append(.news) }
        // The daydream loop is the owner's, over the site, and so is the
        // Wildmind valley beside it.
        if AccessStore.ownerSite { all += [.daydream, .wildmind] }
        // Captures — dictation and conversations, read on the phone and by
        // the site — are the owner's too, for now.
        if AccessStore.ownerSite { all.append(.captures) }
        // The family's step board and task list: pages, not tabs, for
        // everyone with the family and the site credential.
        if access.familyBoards { all += [.steps, .tasks, .backlog] }
        // "msg family" lives in Chat; somebody without Chat finds it here.
        if access.familyBoards && !access.allows(.chat) { all.append(.messages) }
        // Landgrab, once its board has somebody on it — hidden, like the
        // section on Steps, when the site says no or has nothing.
        if access.familyBoards && landgrab.visible { all.append(.landgrab) }
        all += places.filter { $0 != .news }.map(Item.place)
        // The Travel kit and Play nearby are everyone's: they run on the phone.
        all += [.travel, .offline]
        all += [.sync, .settings]
        return all
    }

    /// One door: what it shows, and where it goes.
    private func entry(_ item: Item) -> HubEntry {
        switch item {
        case .trips:
            let next = trips.upcoming()
            let questions = HomeTripWords.openQuestions(next.flatMap { trips.bundles[$0.id] })
            return HubEntry(id: item.id, icon: HomeTileKind.trips.symbol, fill: HomeTileKind.trips.hue.base, title: "Trips",
                            status: tripStatus(next: next, questions: questions.count), count: questions.count,
                            hint: "Plan a trip, or open the one on now") {
                if let next, let first = questions.first, trips.running() == nil {
                    router.openTrip(TripLink(tripId: next.id, date: nil, questionId: first.id))
                } else if trips.summaries.isEmpty {
                    router.openTrips(start: true)
                } else {
                    router.openTrips()
                }
            }
        case .news:
            return HubEntry(id: item.id, icon: "newspaper.fill", fill: SR.accentInk, title: "News", status: nil,
                            hint: "The wire, ranked by what is moving") { router.pushFromHub(Router.Tab.news) }
        case .daydream:
            return HubEntry(id: item.id, icon: "sparkles", fill: SR.accentInk, title: "Daydream",
                            status: toDecide > 0 ? "\(toDecide) to decide" : nil, count: toDecide,
                            hint: "What jkai spotted in your days, and your call on each") { router.pushFromHub(Router.MorePage.daydream) }
        case .wildmind:
            // The day of this life, once the page has been opened — More does
            // not ask the valley on its own.
            return HubEntry(id: item.id, icon: "mountain.2", fill: SR.good, title: "Wildmind",
                            status: wildmind.answer?.snapshot?.time.day.map { "Day \($0)" },
                            hint: "Two Claude minds in a valley, inventing whatever they need") { router.pushFromHub(Router.MorePage.wildmind) }
        case .captures:
            return HubEntry(id: item.id, icon: "waveform.badge.mic", fill: SR.accent, title: "Captures", status: captureStatus,
                            hint: "Record a thought or a conversation") { router.pushFromHub(CapturesRef()) }
        case .steps:
            return HubEntry(id: item.id, icon: "figure.walk", fill: SR.good, title: "Steps", status: steps.shown.flatMap(FamilySteps.place),
                            hint: "Today's family step board") { router.pushFromHub(FamilyPage.steps) }
        case .tasks:
            return HubEntry(id: item.id, icon: "checklist", fill: SR.accentDeep, title: "Tasks", status: tasks.summary.flatMap { taskStatus($0) },
                            hint: "Jobs for the family, with a reward when a parent confirms them") { router.pushFromHub(FamilyPage.tasks) }
        case .backlog:
            return HubEntry(id: item.id, icon: "tray.full", fill: SR.accentInk, title: "Backlog", status: backlog.board.flatMap(FamilyBacklogRules.status),
                            hint: "Videos, links and ideas to watch or do together") { router.pushFromHub(FamilyPage.backlog) }
        case .messages:
            return HubEntry(id: item.id, icon: "bubble.left.and.text.bubble.right", fill: SR.accent, title: "msg family", status: nil,
                            hint: "One line to everyone's phone") { router.pushFromHub(FamilyPage.messages) }
        case .landgrab:
            return HubEntry(id: item.id, icon: "hexagon.fill", fill: SR.accent, title: "Landgrab", status: Landgrab.moreStatus(landgrab.board),
                            hint: "Ground the family has won") {
                if let week = landgrab.board.flatMap(Landgrab.currentWeek) { router.pushFromHub(LandgrabMapRef(week: week.start)) }
            }
        case .place(let place):
            let card = MorePlaceCard(place: place, games: games)
            return HubEntry(id: item.id, icon: card.icon, fill: card.fill, title: card.title, status: card.status,
                            count: place == .games ? games.invites.count : 0, hint: card.blurb) { router.pushFromHub(place) }
        case .travel:
            return HubEntry(id: item.id, icon: "airplane", fill: SR.accentDeep, title: "Travel kit", status: nil,
                            hint: "Live translation, signs, phrases, money and the way back") { router.pushFromHub(TravelKitRef()) }
        case .offline:
            return HubEntry(id: item.id, icon: "dot.radiowaves.left.and.right", fill: SR.accent, title: "Play nearby",
                            status: offline.inRoom ? "In a room" : nil,
                            hint: "Games for phones in the same room, no internet needed") { router.pushFromHub(OfflineGamesRef()) }
        case .sync:
            return HubEntry(id: item.id, icon: "arrow.triangle.2.circlepath", fill: SR.good, title: companion.busy ? "Syncing…" : "Sync now",
                            status: companion.lastUpload.map { "Synced \($0.formatted(date: .omitted, time: .shortened))" },
                            hint: companion.message) {
                Task { await companion.sync() }
            }
        case .settings:
            return HubEntry(id: item.id, icon: "gearshape.fill", fill: SR.inkSecondary, title: "Settings", status: nil,
                            identifier: "open-settings", hint: "Notifications, connections, Apple Health and this iPhone") { router.openSettings() }
        }
    }

    /// The trip on now, the next one, or nothing yet — the door's one line.
    private func tripStatus(next: TripSummary?, questions: Int) -> String? {
        if trips.running() != nil { return "On now" }
        if questions > 0 { return questions == 1 ? "1 question" : "\(questions) questions" }
        guard let next else { return nil }
        let clock = TripClock(next.timeZone)
        guard let days = clock.days(from: clock.localDate(Date()), to: next.startDate) else { return nil }
        return days <= 0 ? "Soon" : days == 1 ? "Tomorrow" : "In \(days) days"
    }
}

/// One door on the hub.
struct HubEntry: Identifiable {
    let id: String
    let icon: String
    let fill: Color
    let title: String
    let status: String?
    var count = 0
    /// What the UI tests and VoiceOver find it by; `more-<id>` unless said.
    var identifier: String? = nil
    /// What is behind it, for VoiceOver (the tile has no room to say).
    var hint: String = ""
    let open: () -> Void
}

/// A door: the mark on its own colour, a count on it when something waits,
/// the name, and one live line. Every one the same size.
struct HubTile: View {
    let entry: HubEntry
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            SRCard(interactive: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: entry.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(LinearGradient(colors: [entry.fill.opacity(0.8), entry.fill], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .overlay(alignment: .topTrailing) {
                            if entry.count > 0 {
                                Text("\(entry.count)")
                                    .font(SR.Text.label(11))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(Capsule().fill(SR.error))
                                    .offset(x: 7, y: -7)
                            }
                        }
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    Text(entry.title)
                        .font(SR.Text.title(15))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    // Always a line, so every name sits at the same height.
                    Text(entry.status ?? " ")
                        .font(SR.Text.secondary(12))
                        .foregroundStyle(entry.status == nil ? .clear : SR.accentDeep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([entry.title, entry.status].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(entry.hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(entry.identifier ?? "more-\(entry.id)")
    }
}

/// Navigation value for the hub, pushed onto whichever tab it is opened on.
struct HubRef: Hashable {}

/// The ⊞ at the top left of every tab's first page: the hub, one tap away,
/// in the same place on every page and for everyone.
struct SRHubButton: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        Button {
            SRHaptic.tap()
            router.openHub()
        } label: {
            Image(systemName: "square.grid.2x2")
        }
        .accessibilityLabel("More")
        .accessibilityHint("News, Flows, the family boards and Settings")
        .accessibilityIdentifier("open-hub")
    }
}

/// One place's card: an icon on its own colour, the name, what is in it now.
struct MorePlaceCard: View {
    let place: Router.Tab
    @ObservedObject var games: GamesStore

    var body: some View {
        // No row of game marks: the Games page lists them, once. Ten marks
        // also ran past the edge of a phone.
        MoreCard(icon: icon, fill: fill, title: title, blurb: blurb, status: status)
    }

    var title: String {
        switch place {
        case .games: return "Games"
        case .news: return "News"
        case .flows: return "Flows"
        default: return place.rawValue.capitalized
        }
    }

    var icon: String {
        switch place {
        case .games: return "gamecontroller.fill"
        case .news: return "newspaper.fill"
        case .flows: return "point.3.connected.trianglepath.dotted"
        default: return "square.grid.2x2"
        }
    }

    var fill: Color {
        switch place {
        case .games: return SR.accent
        case .news: return SR.accentInk
        default: return SR.good
        }
    }

    var blurb: String {
        switch place {
        case .games:
            return "\(GameKind.allCases.count) quick games to play together, live, from any phone in the family."
        case .news: return "The wire, ranked by what is moving. Save and keep stories."
        case .flows: return "Your workflows: run, pause, change a step, or ask jkai to build one."
        default: return ""
        }
    }

    /// Something live to say, or nothing.
    var status: String? {
        guard place == .games else { return nil }
        let invites = games.invites.count
        let rooms = games.rooms.count
        if invites > 0 { return invites == 1 ? "1 invitation" : "\(invites) invitations" }
        if rooms > 0 { return rooms == 1 ? "1 game in progress" : "\(rooms) games in progress" }
        return nil
    }
}

/// A card in More: an icon on its own colour, the name, what is in it, and
/// anything live to say.
struct MoreCard<Extra: View>: View {
    let icon: String
    let fill: Color
    let title: String
    let blurb: String
    var status: String? = nil
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        SRCard(interactive: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SR.paper)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(fill))
                        .accessibilityHidden(true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SR.inkGhost)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(SR.Text.display(19))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(blurb)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                extra()
                if let status {
                    SRGlassChip(text: status, tone: SR.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

extension MoreCard where Extra == EmptyView {
    init(icon: String, fill: Color, title: String, blurb: String, status: String? = nil) {
        self.init(icon: icon, fill: fill, title: title, blurb: blurb, status: status) { EmptyView() }
    }
}

import SwiftUI

/// The top of Home: the three things worth knowing, each a figure, what it
/// means and where it came from — and each a tap into that place.
///
/// The ranking is `HomeBriefing`, pure. This view only gathers the facts from
/// the stores the tiles already fill (it asks the site for nothing of its
/// own) and draws the lines. A fixed height, like every tile: three rows'
/// room whether one line or three came back, so nothing under it moves.
struct HomeBriefingTile: View {
    let health: TodayHealth?
    let rings: ActivityRingsStore.Rings?
    let news: TodayNews?
    let household: HouseholdView?
    @ObservedObject var flows: FlowAttentionStore
    let open: (HomeInsight) -> Void
    var hide: (() -> Void)? = nil
    var customise: (() -> Void)? = nil

    @ObservedObject private var steps = FamilyStepsStore.shared
    @ObservedObject private var tasks = FamilyTasksStore.shared
    @ObservedObject private var forecast = FamilyForecastStore.shared
    @ObservedObject private var trips = TripStore.shared
    @ObservedObject private var daydream = DaydreamStore.shared
    @ObservedObject private var messages = FamilyMessagesStore.shared
    @EnvironmentObject private var games: GamesStore
    @Environment(\.homeColours) private var colours
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Once a minute: "leaves in 25 min" must not sit still.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            // Two lines at the larger text sizes: the tile grows with the type,
            // but a third line of big type would be cut at the foot.
            let lines = HomeBriefing.rank(facts(now: context.date), limit: typeSize >= .xxLarge ? 2 : 3)
            HomeTileFrame(kind: .briefing, look: .glass, badge: context.date.formatted(date: .omitted, time: .shortened)) {
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        if index > 0 { Divider().overlay(SR.divider) }
                        HomeInsightRow(line: line) { open(line) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .contextMenu {
            if let hide {
                Button { hide() } label: { Label("Hide from Home", systemImage: "eye.slash") }
            }
            if let customise {
                Button { customise() } label: { Label("Arrange Home…", systemImage: "square.grid.2x2") }
            }
            if let colours {
                Button { colours() } label: { Label("Colours…", systemImage: "paintpalette") }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Worth knowing")
        .accessibilityIdentifier("home-briefing")
    }

    // MARK: - The facts

    private func facts(now: Date) -> HomeBriefing.Facts {
        var f = HomeBriefing.Facts(now: now)
        if let readiness = health?.readiness {
            f.readiness = .init(score: readiness.score, label: readiness.label, recommendation: readiness.recommendation)
        }
        // Steps is the race's, which is today's; the site's figure is yesterday's.
        f.vitals = (health?.figures ?? []).filter { $0.measured && $0.key != "steps" }.map {
            .init(key: $0.key, label: $0.label, value: $0.value, shown: $0.displayWithUnit,
                  delta: $0.delta, deltaDisplay: $0.deltaDisplay, improving: $0.improving)
        }
        f.rings = (rings?.all ?? []).compactMap { $0 }.map {
            .init(key: $0.key, label: $0.label, value: $0.value, goal: $0.goal, unit: $0.unit)
        }
        f.steps = (steps.shown?.people ?? []).map {
            .init(name: $0.name.split(separator: " ").first.map(String.init) ?? $0.name, steps: $0.steps, me: $0.me)
        }
        if let board = tasks.board {
            let summary = FamilyTasksSummary.make(board, now: now, limit: 50)
            let overdue = summary.next.filter(\.overdue)
            f.tasks = .init(toDo: summary.toDo, overdue: overdue.count, awaiting: summary.awaiting, parent: summary.parent,
                            owedPence: summary.owedPence, overdueTitle: overdue.first?.title,
                            nextTitle: summary.next.first?.title, nextDue: summary.next.first?.due)
        }
        if let desk = forecast.forecast {
            let me = household?.people.first(where: \.isSelf)?.subject
            let names = desk.names
            f.watch = desk.watch.map { .init(title: $0.title, detail: $0.detail, alert: $0.severity == "alert") }
            f.moves = desk.next.compactMap { move -> HomeBriefing.Move? in
                guard let leave = parseTimestamp(move.leaveAt) else { return nil }
                let name = names[move.subject].map { $0.split(separator: " ").first.map(String.init) ?? $0 } ?? "Someone"
                return .init(name: name, isSelf: move.subject == me, to: move.to, leaveAt: leave,
                             arriving: move.kind == "arriving", arriveFrom: parseTimestamp(move.arriveFrom))
            }
            if let upcoming = desk.upcoming, upcoming.available {
                f.diary = upcoming.items.compactMap { item -> HomeBriefing.Diary? in
                    guard let start = parseTimestamp(item.start) else { return nil }
                    return .init(title: item.title, start: start, leaveBy: item.leaveBy.flatMap(parseTimestamp),
                                 place: item.place.isEmpty ? nil : item.place)
                }
            }
        }
        f.trip = trip(now: now)
        f.failingFlows = flows.all.filter(FlowStats.isFailing).map(\.title)
        f.toDecide = daydream.pipeline?.decide ?? 0
        f.decideTitle = daydream.notes.first?.title
        f.newsUnseen = news?.unseen ?? 0
        f.topStory = news?.stories.first?.title
        f.invites = games.invites.map { .init(host: $0.hostName, game: GameNames.title($0.game)) }
        if let line = messages.latestLine, let at = messages.lastActivity {
            f.message = .init(line: line, at: at, mine: line.hasPrefix("You: "))
        }
        return f
    }

    /// The running trip's next stop, or the next trip's countdown.
    private func trip(now: Date) -> HomeBriefing.Trip? {
        if let running = trips.running(now: now) {
            let id = running.bundle.trip.id
            let stops = trips.day(id, running.date)?.stops ?? []
            let progress = trips.progress(id, running.date, now: now)
            let next = progress?.next.flatMap { stops.indices.contains($0) ? stops[$0] : nil }
            let clock = TripClock(running.bundle.trip.timeZone)
            let leave = progress?.leaveMin.map { Int(($0 - clock.minutes(now)).rounded()) }
            return .init(place: HomeTripWords.place(running.bundle.trip.destination), days: nil, questions: 0,
                         nextStop: next?.title, leaveInMinutes: leave)
        }
        guard let next = trips.upcoming(now: now) else { return nil }
        let clock = TripClock(next.timeZone)
        let days = clock.days(from: clock.localDate(now), to: next.startDate)
        return .init(place: HomeTripWords.place(next.destination), days: days,
                     questions: HomeTripWords.openQuestions(trips.bundles[next.id]).count, nextStop: nil, leaveInMinutes: nil)
    }
}

/// One line of the briefing: the source's mark in its hue, the figure set
/// large in the line's tone, what it means, and the quieter detail under it.
struct HomeInsightRow: View {
    let line: HomeInsight
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var mark: CGFloat = 32

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: Self.symbol(line.source))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(hue.onFill)
                    .frame(width: mark, height: mark)
                    .background(Circle().fill(hue.gradient))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    headline
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let detail = line.detail {
                        Text(detail)
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                Spacer(minLength: 0)
                if line.source != .calm {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SR.inkGhost)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(line.source == .calm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.spoken)
        .accessibilityAddTraits(line.source == .calm ? [] : .isButton)
        .accessibilityIdentifier("home-insight-\(line.source.rawValue)")
    }

    /// The figure and the words as one run of text, so a long line wraps or
    /// shrinks as a sentence rather than as two boxes side by side.
    private var headline: Text {
        let words = Text(line.text).font(SR.Text.title(15)).foregroundStyle(SR.ink)
        guard let figure = line.figure else { return words }
        return Text(figure).font(SR.Text.figure(18)).foregroundStyle(tone) + Text(" ") + words
    }

    private var tone: Color {
        switch line.tone {
        case .good: return SR.good
        case .warn: return SR.warn
        case .bad: return SR.error
        case .plain: return SR.ink
        }
    }

    private var hue: SR.Hue {
        switch line.source {
        case .watch, .moves: return SR.Hue.family
        case .diary, .trip: return SR.Hue.trips
        case .tasks: return SR.Hue.tasks
        case .readiness, .vitals, .calm: return SR.Hue.health
        case .rings: return SR.Hue.move
        case .steps: return SR.Hue.steps
        case .flows: return SR.Hue.flows
        case .games: return SR.Hue.games
        case .messages: return SR.Hue.messages
        case .daydream: return SR.Hue.daydream
        case .news: return SR.Hue.news
        }
    }

    static func symbol(_ source: HomeInsight.Source) -> String {
        switch source {
        case .watch: return "exclamationmark.triangle.fill"
        case .diary: return "calendar"
        case .trip: return "suitcase.rolling.fill"
        case .moves: return "clock.arrow.2.circlepath"
        case .tasks: return "checklist"
        case .readiness: return "gauge.with.dots.needle.67percent"
        case .vitals: return "waveform.path.ecg"
        case .rings: return "flame.fill"
        case .steps: return "figure.walk"
        case .flows: return "point.3.connected.trianglepath.dotted"
        case .games: return "gamecontroller.fill"
        case .messages: return "bubble.left.and.text.bubble.right.fill"
        case .daydream: return "cloud.fill"
        case .news: return "newspaper.fill"
        case .calm: return "checkmark"
        }
    }
}

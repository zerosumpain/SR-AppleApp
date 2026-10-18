import SwiftUI

// Home's tiles, one view per feature.
//
// Each tile observes ITS OWN store, so a step-board refresh redraws the steps
// tile and nothing else — Today learned that the hard way when one shared
// observed store redrew the whole page on every upload. Every tile has a
// fixed height (the dashboard sets it), and every tile draws something on
// its first frame, even if that is a quiet "nothing yet": a tile that
// appeared late would push the ones under it down under a thumb.

// MARK: - Family

struct HomeFamilyTile: View {
    @ObservedObject var store: FamilyStore
    let watch: [WatchedPlace]?
    let live: Bool
    var openPerson: ((String) -> Void)? = nil

    var body: some View {
        HomeTileFrame(kind: .family, look: .glass, badge: badge) {
            if let view = store.view, let model = FamilyOrbitModel.make(view: view, watch: watch) {
                let colours = SR.PersonHue.assign(view.people.map(\.subject))
                VStack(alignment: .leading, spacing: 6) {
                    FamilyOrbitView(model: model, colours: colours, live: live, openPerson: openPerson)
                    FamilyOrbitLegend(view: view, model: model, colours: colours)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "house.and.flag.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(SR.Hue.family.gradient)
                    Text(store.loaded ? "Nobody is sharing a place yet" : "Finding everyone…")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var badge: String? {
        guard let view = store.view else { return nil }
        let moving = view.moving.count
        return moving > 0 ? "\(moving) MOVING" : nil
    }
}

/// Who is where, in words, under the Orbit: one chip per person in their
/// colour. The picture says how far; this says where.
struct FamilyOrbitLegend: View {
    let view: HouseholdView
    let model: FamilyOrbitModel
    let colours: [String: Color]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.people) { person in
                    HStack(spacing: 5) {
                        Circle().fill(colours[person.subject] ?? SR.accent).frame(width: 8, height: 8)
                        Text(person.isSelf ? "You" : person.name.split(separator: " ").first.map(String.init) ?? person.name)
                            .font(SR.Text.label(12))
                            .foregroundStyle(SR.ink)
                        Text(where_(person))
                            .font(SR.Text.mono(12))
                            .foregroundStyle(SR.inkMuted)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill((colours[person.subject] ?? SR.accent).opacity(0.12)))
                }
                if !model.missing.isEmpty {
                    Text("\(model.missing.count) not sharing")
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkMuted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().strokeBorder(SR.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
            }
        }
        .scrollClipDisabled()
        .accessibilityHidden(true)
    }

    private func where_(_ person: FamilyOrbitModel.Person) -> String {
        if person.atHome { return "home" }
        if let place = person.place, place.count <= 16 { return place }
        return FamilyOrbitMath.formatKm(person.km)
    }
}

struct HomeFamilyDayTile: View {
    @ObservedObject var store: FamilyStore
    let watch: [WatchedPlace]?

    var body: some View {
        HomeTileFrame(kind: .familyDay, look: .glass) {
            if let view = store.view, let model = FamilyRibbonsModel.make(view: view, watch: watch) {
                FamilyRibbonsView(model: FamilyRibbonsModel(rows: Array(model.rows.prefix(3)), start: model.start, end: model.end, maxKm: model.maxKm),
                                  colours: SR.PersonHue.assign(view.people.map(\.subject)))
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                Text(store.loaded ? "No trails yet today — a day at home is a flat line." : "Reading the day…")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Health

struct HomeHealthTile: View {
    let health: TodayHealth?
    let move: MoveRingStore.Reading?
    /// The owner's readiness is drawn; anybody else has the Move ring alone.
    let showsReadiness: Bool

    var body: some View {
        HomeTileFrame(kind: .health) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Spacer(minLength: 0)
                    if let readiness = shownReadiness {
                        HomeFigure(value: "\(Int(readiness.score.rounded()))", caption: readiness.label)
                    } else if let move {
                        HomeFigure(value: "\(Int(move.value.rounded()))", unit: move.unit, caption: "of \(Int(move.goal.rounded())) Move")
                    } else {
                        HomeFigure(value: "—", caption: "Move ring")
                    }
                }
                Spacer(minLength: 0)
                Group {
                    if let readiness = shownReadiness, !readiness.factors.isEmpty {
                        ReadinessRose(petals: readiness.factors.map(\.score), move: move?.fraction)
                    } else {
                        MoveGlass(fraction: move?.fraction ?? 0)
                    }
                }
                .frame(width: 84, height: 84)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var shownReadiness: HealthReadiness? { showsReadiness ? health?.readiness : nil }

    /// "Readiness 78, steady. Move 412 of 600 kcal." — a member's says Move
    /// only, never the owner's readiness.
    private var spoken: String {
        var parts: [String] = []
        if let readiness = shownReadiness { parts.append("Readiness \(Int(readiness.score.rounded())), \(readiness.label)") }
        if let move { parts.append("Move \(Int(move.value.rounded())) of \(Int(move.goal.rounded())) \(move.unit)") } else { parts.append("Move ring not read yet") }
        return "Health. " + parts.joined(separator: ". ")
    }
}

// MARK: - Steps

struct HomeStepsTile: View {
    @ObservedObject private var store = FamilyStepsStore.shared

    var body: some View {
        HomeTileFrame(kind: .steps, badge: place) {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading) {
                    Spacer(minLength: 0)
                    if let me = store.shown?.people.first(where: \.me) {
                        HomeFigure(value: me.steps.formatted(), caption: leaderLine)
                    } else {
                        HomeFigure(value: "—", caption: store.loaded ? "No board today" : "Reading the board…")
                    }
                }
                Spacer(minLength: 0)
                StepsLanes(lanes: lanes)
                    .frame(width: 78, height: 78)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var lanes: [StepsLanes.Lane] {
        (store.shown?.people ?? []).sorted { $0.steps > $1.steps }.prefix(4)
            .map { StepsLanes.Lane(id: $0.id, steps: $0.steps, me: $0.me) }
    }

    private var place: String? {
        guard let board = store.shown, let me = board.people.first(where: \.me), me.rank > 0 else { return nil }
        return "#\(me.rank)"
    }

    private var leaderLine: String {
        guard let board = store.shown, let top = board.people.max(by: { $0.steps < $1.steps }) else { return "" }
        return top.me ? "You lead" : "\(top.name.split(separator: " ").first.map(String.init) ?? top.name) leads"
    }

    private var spoken: String {
        guard let board = store.shown, let me = board.people.first(where: \.me) else {
            return store.loaded ? "Steps. No board today" : "Steps. Reading the board"
        }
        return "Steps. You have \(me.steps) steps, \(me.rank > 0 ? "number \(me.rank) of \(board.people.count)" : "unranked"). \(leaderLine)"
    }
}

// MARK: - Tasks

struct HomeTasksTile: View {
    @ObservedObject private var store = FamilyTasksStore.shared

    var body: some View {
        HomeTileFrame(kind: .tasks, badge: owed) {
            VStack(alignment: .leading, spacing: 8) {
                if let board = store.board {
                    let summary = FamilyTasksSummary.make(board)
                    TaskWaffle(done: board.completed.count, awaiting: summary.awaiting, toDo: summary.toDo,
                               overdue: summary.next.filter(\.overdue).count, columns: 8, limit: 16)
                    Spacer(minLength: 0)
                    HomeFigure(value: "\(summary.toDo)", unit: "to do",
                               caption: summary.next.first?.title ?? (summary.awaiting > 0 ? "\(summary.awaiting) to confirm" : "All done"))
                } else {
                    Spacer(minLength: 0)
                    HomeFigure(value: "—", caption: store.loaded ? "No list yet" : "Reading the list…")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var owed: String? {
        guard let board = store.board else { return nil }
        let pence = FamilyTasksSummary.make(board).owedPence
        return pence > 0 ? String(format: "£%.2f", Double(pence) / 100) : nil
    }

    private var spoken: String {
        guard let board = store.board else { return "Tasks" }
        let s = FamilyTasksSummary.make(board)
        return "Tasks. \(s.toDo) to do, \(s.awaiting) to confirm, \(board.completed.count) done" + (s.next.first.map { ". Next: \($0.title)" } ?? "")
    }
}

// MARK: - Trips

struct HomeTripsTile: View {
    @ObservedObject private var store = TripStore.shared
    var hide: (() -> Void)? = nil
    var customise: (() -> Void)? = nil
    let open: (HomeTripTarget) -> Void

    var body: some View {
        // Once a minute: "leave in 8 min" must not sit still.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            if let running = store.running(now: now) {
                HomeTileButton(kind: .trips, id: "today-trip", action: {
                    open(.day(TripDayRef(tripId: running.bundle.trip.id, date: running.date)))
                }, hide: hide, customise: customise) {
                    runningTile(running.bundle, date: running.date, now: now)
                }
            } else if let next = store.upcoming(now: now) {
                HomeTileButton(kind: .trips, id: "today-trips", action: { open(.list) }, hide: hide, customise: customise) {
                    upcomingTile(next, now: now)
                }
            } else if !store.summaries.isEmpty {
                HomeTileButton(kind: .trips, id: "today-trips", action: { open(.list) }, hide: hide, customise: customise) {
                    HomeTileFrame(kind: .trips) {
                        Spacer(minLength: 0)
                        HomeFigure(value: "\(store.summaries.count)", unit: store.summaries.count == 1 ? "trip" : "trips", caption: "On this phone")
                    }
                }
            } else {
                HomeTileButton(kind: .trips, id: "today-plan-trip", action: { open(.plan) }, hide: hide, customise: customise) {
                    HomeTileFrame(kind: .trips) {
                        Spacer(minLength: 0)
                        HomeFigure(value: "Plan a trip", caption: "Say where, when and who", size: 24)
                    }
                }
            }
        }
    }

    private func runningTile(_ bundle: TripBundle, date: String, now: Date) -> some View {
        let day = store.day(bundle.trip.id, date)
        let progress = store.progress(bundle.trip.id, date, now: now)
        let stops = day?.stops ?? []
        let done = Set(progress?.doneStopIds ?? [])
        let currentIndex: Int? = {
            switch progress?.phase {
            case .at(let i)?: return i
            case .heading(let i)?: return i
            default: return nil
            }
        }()
        let next = progress?.next.flatMap { stops.indices.contains($0) ? stops[$0] : nil }
        let clock = TripClock(bundle.trip.timeZone)
        let leaveIn = progress?.leaveMin.map { Int(($0 - clock.minutes(now)).rounded()) }
        return HomeTileFrame(kind: .trips, badge: bundle.trip.destination.uppercased()) {
            VStack(alignment: .leading, spacing: 10) {
                MetroLine(stations: stops.prefix(9).enumerated().map { index, stop in
                    MetroLine.Station(id: stop.id, done: done.contains(stop.id), current: index == currentIndex)
                })
                Spacer(minLength: 0)
                HomeFigure(
                    value: next?.title ?? (stops.isEmpty ? "No plan yet" : "Day done"),
                    caption: leaveIn.map { $0 > 0 ? "Leave in \($0) min" : "Time to go" } ?? "\(stops.count) stops today",
                    size: 22
                )
            }
        }
    }

    private func upcomingTile(_ trip: TripSummary, now: Date) -> some View {
        let clock = TripClock(trip.timeZone)
        let days = clock.days(from: clock.localDate(now), to: trip.startDate) ?? 0
        return HomeTileFrame(kind: .trips, badge: trip.destination.uppercased()) {
            Spacer(minLength: 0)
            HomeFigure(value: days == 1 ? "Tomorrow" : "\(days) days", caption: trip.title, size: 30)
        }
    }
}

enum HomeTripTarget {
    case day(TripDayRef)
    case list
    case plan
}

// MARK: - Coming up (the travel desk's next moves)

struct HomeMovesTile: View {
    @ObservedObject private var forecast = FamilyForecastStore.shared
    let colours: [String: Color]
    let initials: [String: String]

    var body: some View {
        let now = Date()
        let moves = (forecast.forecast?.next ?? [])
            .compactMap { move -> (FamilyForecast.NextMove, Date)? in
                guard let at = isoDate(move.leaveAt), at > now.addingTimeInterval(-600) else { return nil }
                return (move, at)
            }
            .sorted { $0.1 < $1.1 }
        let names = forecast.forecast?.names ?? [:]
        HomeTileFrame(kind: .moves) {
            if let first = moves.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(names[first.0.subject] ?? "Someone") → \(first.0.to)")
                        .font(SR.Text.title(16))
                        .lineLimit(1)
                    Text("Leaves about \(first.1.formatted(date: .omitted, time: .shortened))")
                        .font(SR.Text.secondary(13))
                        .opacity(0.9)
                    MovesAxis(marks: moves.prefix(6).map { move, at in
                        MovesAxis.Mark(id: move.correctionKey, at: at, colour: colours[move.subject] ?? .white,
                                       initials: initials[move.subject] ?? String((names[move.subject] ?? "?").prefix(2)))
                    }, from: now)
                }
            } else {
                Spacer(minLength: 0)
                HomeFigure(value: "All quiet", caption: "Nobody is due anywhere for a while", size: 24)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(moves.isEmpty ? "Coming up: all quiet" : "Coming up: " + moves.prefix(3).map {
            "\(names[$0.0.subject] ?? "Someone") to \($0.0.to) about \($0.1.formatted(date: .omitted, time: .shortened))"
        }.joined(separator: ". "))
    }
}

// MARK: - msg family

struct HomeMessagesTile: View {
    @ObservedObject private var store = FamilyMessagesStore.shared

    var body: some View {
        HomeTileFrame(kind: .messages) {
            VStack(alignment: .leading, spacing: 8) {
                if let line = store.latestLine {
                    Text(line)
                        .font(SR.Text.secondary(14))
                        .lineLimit(3)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 4, bottomTrailingRadius: 14, topTrailingRadius: 14, style: .continuous)
                                .fill(.white.opacity(0.22))
                        )
                    Spacer(minLength: 0)
                    if let at = store.lastActivity {
                        Text(at, style: .relative)
                            .font(SR.Text.label(12))
                            .opacity(0.9)
                    }
                } else {
                    Spacer(minLength: 0)
                    HomeFigure(value: "Say hi", caption: "To everyone at once", size: 24)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("msg family. " + (store.latestLine ?? "No messages yet"))
    }
}

// MARK: - Backlog

struct HomeBacklogTile: View {
    @ObservedObject private var store = FamilyBacklogStore.shared

    var body: some View {
        let line = store.board.map(FamilyBacklogRules.todayLine)
        HomeTileFrame(kind: .backlog, badge: (line?.forYou ?? 0) > 0 ? "\(line!.forYou) FOR YOU" : nil) {
            VStack(alignment: .leading, spacing: 8) {
                SpineShelf(count: line?.waiting ?? 0, fresh: line?.forYou ?? 0)
                Spacer(minLength: 0)
                HomeFigure(value: "\(line?.waiting ?? 0)", unit: "saved", caption: line?.newest.first?.title ?? "Nothing saved yet")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Backlog. \(line?.waiting ?? 0) saved, \(line?.forYou ?? 0) for you")
    }
}

// MARK: - Games

struct HomeGamesTile: View {
    @EnvironmentObject private var games: GamesStore

    var body: some View {
        let invites = games.invites.count
        HomeTileFrame(kind: .games, badge: invites > 0 ? "\(invites) INVITE\(invites == 1 ? "" : "S")" : nil) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading) {
                    Spacer(minLength: 0)
                    if let invite = games.invites.first {
                        HomeFigure(value: GameNames.title(invite.game), caption: "\(invite.hostName) invited you", size: 20)
                    } else {
                        HomeFigure(value: games.rooms.isEmpty ? "Play" : "\(games.rooms.count)", unit: games.rooms.isEmpty ? nil : "in play",
                                   caption: "Ten family games", size: 26)
                    }
                }
                Spacer(minLength: 0)
                DieFace(pips: max(1, min(invites + games.rooms.count, 6)))
                    .frame(width: 52, height: 52)
                    .symbolEffect(.bounce, value: invites)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(invites > 0 ? "Games. \(invites) invites" : "Games")
    }
}

// MARK: - Ask jkai

struct HomeChatTile: View {
    let lastThread: TodayThread?

    var body: some View {
        HomeTileFrame(kind: .chat) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: -10) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(.white.opacity(0.95 - Double(index) * 0.25))
                            .frame(width: 26, height: 26)
                            .overlay(Image(systemName: ["sparkles", "text.bubble.fill", "magnifyingglass"][index])
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(SR.Hue.chat.base))
                    }
                }
                Spacer(minLength: 0)
                HomeFigure(value: "Ask", caption: lastThread?.title.map { "Last: \($0)" } ?? "Anything, any time", size: 28)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("JkAi and messages")
    }
}

// MARK: - News

struct HomeNewsTile: View {
    let news: TodayNews?

    var body: some View {
        HomeTileFrame(kind: .news, badge: (news?.unseen ?? 0) > 0 ? "\(news!.unseen) NEW" : nil) {
            VStack(alignment: .leading, spacing: 8) {
                let heats = (news?.stories ?? []).map { $0.heat ?? 0 }
                if heats.count > 1 {
                    HeatStripes(heats: heats)
                        .frame(height: 44)
                }
                Spacer(minLength: 0)
                Text(news?.stories.first?.title ?? "The desk is quiet")
                    .font(SR.Text.title(15))
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("News. " + (news?.stories.first?.title ?? "Quiet"))
    }
}

// MARK: - Daydream

struct HomeDaydreamTile: View {
    @ObservedObject private var store = DaydreamStore.shared

    var body: some View {
        let decide = store.pipeline?.decide ?? 0
        HomeTileFrame(kind: .daydream, look: .aurora(decide > 0 ? 1 : 0.45), badge: decide > 0 ? "\(decide) TO DECIDE" : nil) {
            VStack(alignment: .leading) {
                Spacer(minLength: 0)
                HomeFigure(value: decide > 0 ? "\(decide)" : "Calm", unit: decide > 0 ? "noticed" : nil,
                           caption: store.notes.first?.title ?? "What the loop noticed", size: 28)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(decide > 0 ? "Daydream. \(decide) to decide" : "Daydream")
    }
}

// MARK: - Flows

struct HomeFlowsTile: View {
    @ObservedObject var store: FlowAttentionStore

    var body: some View {
        let stats = store.stats(now: Date())
        HomeTileFrame(kind: .flows, badge: stats.failing > 0 ? "\(stats.failing) FAILING" : nil) {
            VStack(alignment: .leading, spacing: 8) {
                FlowDots(working: stats.working, failing: stats.failing)
                Spacer(minLength: 0)
                HomeFigure(value: store.loaded ? "\(stats.working)" : "—", unit: "working",
                           caption: stats.next.map { "Next \($0.at.formatted(date: .omitted, time: .shortened))" } ?? "Nothing scheduled")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flows. \(stats.working) working, \(stats.failing) failing")
    }
}

// MARK: - Wildmind

struct HomeWildmindTile: View {
    var body: some View {
        HomeTileFrame(kind: .wildmind) {
            VStack(alignment: .leading) {
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { index in
                        Image(systemName: index % 3 == 0 ? "tree.fill" : index % 3 == 1 ? "mountain.2.fill" : "flame.fill")
                            .font(.system(size: 12 + CGFloat(index % 2) * 6, weight: .bold))
                            .opacity(0.5 + Double(index % 3) * 0.2)
                    }
                }
                Spacer(minLength: 0)
                HomeFigure(value: "Visit", caption: "The world it is building", size: 26)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wildmind")
    }
}

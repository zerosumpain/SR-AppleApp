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

/// The owner's morning in one tile: readiness on a dial, each of the site's
/// figures against the person's own week (a tap opens that figure's chart),
/// and today's three rings as bars along the foot. Anybody else gets the
/// rings, which are theirs, from this phone.
///
/// Glass, not the hue's own fill: four numbers with arrows that are green
/// when they are going the right way need a ground green can be read on.
struct HomeHealthTile: View {
    let health: TodayHealth?
    let rings: ActivityRingsStore.Rings?
    /// The owner's readiness and figures are drawn; anybody else has the rings alone.
    let showsReadiness: Bool
    /// A figure's row tapped: open its chart.
    var openFigure: ((HealthFigure) -> Void)? = nil
    @ScaledMetric(relativeTo: .body) private var dial: CGFloat = 104
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The figures the tile lists, in this order. Steps is the step race's.
    static let figureKeys = ["recovery", "hrv", "rhr", "sleep"]

    var body: some View {
        HomeTileFrame(kind: .health, look: .glass) {
            VStack(alignment: .leading, spacing: 12) {
                if let readiness = shownReadiness {
                    HStack(alignment: .center, spacing: 14) {
                        ReadinessDial(score: readiness.score, label: readiness.label)
                            .frame(width: dial, height: dial)
                        if figures.isEmpty {
                            Text("Figures not in yet")
                                .font(SR.Text.secondary(14))
                                .foregroundStyle(SR.inkMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(figures) { figure in
                                    HomeVitalRow(figure: figure, open: openFigure)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    HomeRingBars(rings: rings)
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        HomeRingsDial(rings: rings)
                            .frame(width: dial, height: dial)
                        HomeRingRows(rings: rings)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        // The owner's figure rows are buttons of their own, so they stay
        // reachable; a member's tile is one element that says it all.
        .accessibilityElement(children: shownReadiness == nil ? .ignore : .contain)
        .accessibilityLabel(spoken)
    }

    private var shownReadiness: HealthReadiness? { showsReadiness ? health?.readiness : nil }

    private var figures: [HealthFigure] {
        guard showsReadiness else { return [] }
        let all = health?.figures ?? []
        // Three at the larger text sizes, so the rows keep their size.
        return Array(Self.figureKeys.compactMap { key in all.first { $0.key == key && $0.measured } }
            .prefix(typeSize >= .xxLarge ? 3 : 4))
    }

    /// "Health. Readiness 72, Primed. HRV 64 ms, +5 vs 7d. Move 412 of 600
    /// kcal." — a member's says the rings only, never the owner's readiness.
    private var spoken: String {
        var parts: [String] = []
        if let readiness = shownReadiness { parts.append("Readiness \(Int(readiness.score.rounded())), \(readiness.label)") }
        for figure in figures {
            parts.append("\(figure.label) \(figure.displayWithUnit)" + (figure.deltaDisplay.map { ", \($0)" } ?? ""))
        }
        let ringWords = (rings?.all ?? []).compactMap { $0?.spoken }
        if ringWords.isEmpty { parts.append("Move ring not read yet") } else { parts.append(contentsOf: ringWords) }
        return "Health. " + parts.joined(separator: ". ")
    }
}

/// One of the site's figures against the person's week: "HRV  64 ms  ▲ 5".
/// A button of its own inside the tile — the drill into that figure.
struct HomeVitalRow: View {
    let figure: HealthFigure
    var open: ((HealthFigure) -> Void)?

    var body: some View {
        Button {
            SRHaptic.tap()
            open?(figure)
        } label: {
            HStack(spacing: 8) {
                Text(figure.label)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                Text(figure.displayWithUnit)
                    .font(SR.Text.figure(16))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                HomeDeltaChip(delta: figure.delta, display: figure.deltaDisplay, improving: figure.improving)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(open == nil)
        .accessibilityLabel("\(figure.label) \(figure.displayWithUnit)" + (figure.deltaDisplay.map { ", \($0)" } ?? ""))
        .accessibilityHint("Opens its chart")
        .accessibilityIdentifier("home-vital-\(figure.key)")
    }
}

/// "▲ 5" in green when it is going the right way, amber when not, grey when
/// the direction means nothing. Sized to its words: it never squeezes them.
struct HomeDeltaChip: View {
    let delta: Double?
    let display: String?
    let improving: Bool?

    var body: some View {
        if let delta, delta != 0, let size = HomeBriefing.magnitude(display) {
            let tone = improving == true ? SR.good : improving == false ? SR.warn : SR.inkMuted
            HStack(spacing: 2) {
                Image(systemName: delta > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .imageScale(.small)
                    .font(SR.Text.label(9))
                Text(size)
                    .font(SR.Text.mono(12))
                    .lineLimit(1)
            }
            .foregroundStyle(tone)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tone.opacity(0.12)))
            .fixedSize()
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Steps

/// The family's step race as a bar chart: everyone's count written at the end
/// of their bar, the caller's own row strongest, and over it the one thing
/// the race means for you — "1,240 behind Sam".
///
/// A wide tile: on a square the count, the lanes and the leader's name were
/// three things fighting for 140 points, and the count lost (John, 2026-10-27).
struct HomeStepsTile: View {
    @ObservedObject private var store = FamilyStepsStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HomeTileFrame(kind: .steps, look: .glass, badge: place) {
            if let board = store.shown, let me = board.mine {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(FamilySteps.figure(me.steps))
                            .font(SR.Text.figure(30))
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .layoutPriority(1)
                        Text(FamilySteps.gap(board) ?? "steps today")
                            .font(SR.Text.secondary(14))
                            .foregroundStyle(SR.inkSecondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    StepsRace(rows: Self.rows(board, lanes: typeSize >= .xxLarge ? 3 : 4))
                    Spacer(minLength: 0)
                    if let yesterday = FamilySteps.yesterdayLine(board) {
                        Text(yesterday)
                            .font(SR.Text.mono(12))
                            .foregroundStyle(SR.inkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .font(.title.weight(.bold))
                        .foregroundStyle(SR.Hue.steps.gradient)
                    Text(store.loaded ? "No board today" : "Reading the board…")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// Up to `lanes` lanes: the top of the board, and you, wherever you are. PURE.
    static func rows(_ board: FamilyStepsBoard, lanes: Int = 4) -> [StepsRace.Row] {
        let ranked = FamilySteps.ranked(board.people)
        var shown = Array(ranked.prefix(lanes))
        if !shown.contains(where: \.me), let me = ranked.first(where: \.me) {
            shown = Array(ranked.prefix(max(lanes - 1, 0))) + [me]
        }
        return shown.map { person in
            StepsRace.Row(id: person.id, name: person.me ? "You" : (person.name.split(separator: " ").first.map(String.init) ?? person.name),
                          steps: person.steps, me: person.me)
        }
    }

    private var place: String? {
        guard let board = store.shown, board.people.count > 1 else { return nil }
        return FamilySteps.place(board)?.uppercased()
    }

    private var spoken: String {
        guard let board = store.shown, let me = board.mine else {
            return store.loaded ? "Steps. No board today" : "Steps. Reading the board"
        }
        let gap = FamilySteps.gap(board).map { ". \($0)" } ?? ""
        return "Steps. You have \(me.steps) steps, \(me.rank > 0 ? "number \(me.rank) of \(board.people.count)" : "unranked")\(gap)"
    }
}

// MARK: - Tasks

struct HomeTasksTile: View {
    @ObservedObject private var store = FamilyTasksStore.shared

    var body: some View {
        HomeTileFrame(kind: .tasks, badge: owed) {
            VStack(alignment: .leading, spacing: 6) {
                if let board = store.board {
                    let summary = FamilyTasksSummary.make(board, limit: 50)
                    let overdue = summary.next.filter(\.overdue).count
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(summary.toDo)")
                            .font(SR.Text.figure(30))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("to do")
                            .font(SR.Text.label(13))
                            .lineLimit(1)
                            .opacity(0.85)
                    }
                    TaskWaffle(done: board.completed.count, awaiting: summary.awaiting, toDo: summary.toDo,
                               overdue: overdue, columns: 8, limit: 16)
                    Spacer(minLength: 0)
                    Text(Self.line(summary, overdue: overdue))
                        .font(SR.Text.secondary(13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(0.92)
                } else {
                    Spacer(minLength: 0)
                    HomeFigure(value: "—", caption: store.loaded ? "No list yet" : "Reading the list…")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// "2 overdue · Bins", "1 to confirm", "Next: Bins", "All done". PURE.
    static func line(_ summary: FamilyTasksSummary, overdue: Int) -> String {
        if overdue > 0 { return "\(overdue) overdue" + (summary.next.first(where: \.overdue).map { " · \($0.title)" } ?? "") }
        if summary.awaiting > 0 && summary.parent { return "\(summary.awaiting) to confirm" }
        if let next = summary.next.first { return "Next: \(next.title)" }
        return summary.awaiting > 0 ? "\(summary.awaiting) waiting to be checked" : "All done"
    }

    private var owed: String? {
        guard let board = store.board else { return nil }
        let pence = FamilyTasksSummary.make(board).owedPence
        return pence > 0 ? String(format: "£%.2f", Double(pence) / 100) : nil
    }

    private var spoken: String {
        guard let board = store.board else { return "Tasks" }
        let s = FamilyTasksSummary.make(board, limit: 50)
        return "Tasks. \(s.toDo) to do, \(s.awaiting) to confirm, \(board.completed.count) done. " + Self.line(s, overdue: s.next.filter(\.overdue).count)
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
                // v8: open questions make the trip itself the target — its
                // planning home, at the first of them.
                let questions = HomeTripWords.openQuestions(store.bundles[next.id])
                HomeTileButton(kind: .trips, id: "today-trips", action: {
                    if let first = questions.first {
                        open(.questions(tripId: next.id, questionId: first.id))
                    } else {
                        open(.list)
                    }
                }, hide: hide, customise: customise) {
                    upcomingTile(next, questions: questions.count, now: now)
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

    /// The next trip: "in 5 days", where and when — and, while the planner
    /// has questions open, "2 quick questions" with Answer (mockup 10).
    private func upcomingTile(_ trip: TripSummary, questions: Int, now: Date) -> some View {
        let clock = TripClock(trip.timeZone)
        let days = clock.days(from: clock.localDate(now), to: trip.startDate)
        return HomeTileFrame(kind: .trips, badge: HomeTripWords.place(trip.destination)) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                HomeFigure(
                    value: HomeTripWords.countdown(days: days),
                    caption: HomeTripWords.caption(destination: trip.destination, start: trip.startDate, end: trip.endDate),
                    size: questions > 0 ? 26 : 30
                )
                if let asked = HomeTripWords.questions(questions) {
                    HomeTripQuestionsBar(text: asked)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trips. " + HomeTripWords.spoken(destination: trip.destination, days: days, questions: questions))
        .accessibilityHint(questions > 0 ? "Opens the trip at its questions" : "Opens your trips")
    }
}

/// "2 quick questions · Answer", across the foot of the Trips tile. Part of
/// the tile's one button: Answer is its label, not a second target.
struct HomeTripQuestionsBar: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.subheadline.weight(.semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.title(14))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text("Answer")
                .font(SR.Text.label(13))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(HomeTileKind.trips.hue.onFill.opacity(0.92)))
                .foregroundStyle(HomeTileKind.trips.hue.base)
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .background(Capsule().fill(HomeTileKind.trips.hue.onFill.opacity(0.18)))
        .accessibilityIdentifier("today-trip-questions")
    }
}

enum HomeTripTarget {
    case day(TripDayRef)
    case list
    case plan
    /// v8: the trip's planning home, scrolled to this question.
    case questions(tripId: String, questionId: String)
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
                        HomeFigure(value: GameNames.title(invite.game), caption: "\(invite.hostName) invited you", size: 20, captionLines: 2)
                    } else {
                        HomeFigure(value: games.rooms.isEmpty ? "Play" : "\(games.rooms.count)", unit: games.rooms.isEmpty ? nil : "in play",
                                   caption: games.rooms.isEmpty ? "Start one for the family" : "Rooms still open", size: 26, captionLines: 2)
                    }
                }
                Spacer(minLength: 0)
                DieFace(pips: max(1, min(invites + games.rooms.count, 6)))
                    .frame(width: 44, height: 44)
                    .symbolEffect(.bounce, value: invites)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(invites > 0 ? "Games. \(invites) invites" : "Games")
    }
}

// MARK: - Shortcuts: Ask jkai and Wildmind

/// A feature with nothing to chart, kept on Home as a shortcut: its mark, its
/// name and one line, at a third of a tile's height, two to a row.
struct HomeShortcutTile: View {
    let kind: HomeTileKind
    let line: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(kind.hue.onFill)
                .frame(width: 34, height: 34)
                .background(Circle().fill(kind.hue.gradient))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(line)
                    .font(SR.Text.secondary(12))
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(SR.inkGhost)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background { Color.clear.srGlass(.paper, in: shape) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.5), lineWidth: 1))
        .shadow(color: SR.ink.opacity(0.06), radius: 10, y: 4)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title). \(line)")
    }
}

// MARK: - News

/// The desk's top three, each with its heat as a stripe beside it — Ed
/// Hawkins's warming colours, cool to hot by how fast the story is moving.
struct HomeNewsTile: View {
    let news: TodayNews?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stories = Array((news?.stories ?? []).prefix(typeSize >= .xxLarge ? 2 : 3))
        let top = max(stories.compactMap(\.heat).max() ?? 1, 0.0001)
        HomeTileFrame(kind: .news, look: .glass, badge: (news?.unseen ?? 0) > 0 ? "\(news!.unseen) NEW" : nil) {
            if stories.isEmpty {
                Text("The desk is quiet")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(stories) { story in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(HeatStripes.ramp((story.heat ?? 0) / top))
                                .frame(width: 6)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(story.title)
                                    .font(SR.Text.title(14))
                                    .foregroundStyle(SR.ink)
                                    .lineLimit(1)
                                Text(story.sourceLabel)
                                    .font(SR.Text.mono(11))
                                    .foregroundStyle(SR.inkMuted)
                                    .lineLimit(1)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("News. " + (stories.isEmpty ? "Quiet" : stories.map(\.title).joined(separator: ". ")))
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
                           caption: store.notes.first?.title ?? "What the loop noticed", size: 28, captionLines: 2)
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
        let failing = store.all.filter(FlowStats.isFailing).map(\.title)
        HomeTileFrame(kind: .flows, badge: stats.failing > 0 ? "\(stats.failing) FAILING" : nil) {
            VStack(alignment: .leading, spacing: 8) {
                FlowDots(working: stats.working, failing: stats.failing)
                Spacer(minLength: 0)
                HomeFigure(value: store.loaded ? "\(stats.working)" : "—", unit: "working",
                           caption: failing.first.map { "Failing: \($0)" }
                               ?? stats.next.map { "Next \(FlowStats.when($0.at, now: Date()))" } ?? "Nothing scheduled")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flows. \(stats.working) working, \(stats.failing) failing" + (failing.isEmpty ? "" : ": " + failing.joined(separator: ", ")))
    }
}

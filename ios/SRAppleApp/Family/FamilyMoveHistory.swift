import SwiftUI

/// One person's moves, looked back over: where they go, when they leave, the
/// trips they make regularly and whether they leave on time, how long each
/// route takes and whether it is getting quicker, and the trips themselves.
/// Opened by tapping a name under "Next moves" (John, 2026-10-21).
///
/// The site's `GET /api/native/family/forecast/history?subject=&days=` — the
/// same learned trips the forecast stands on (`move-history.ts`), scoped as
/// the forecast is: the owner anyone's, a member their own and their wards'.
/// Names of places only; never a coordinate.
struct FamilyMoveHistory: Decodable, Equatable {
    let subject: String
    let name: String
    let days: Int
    let totals: Totals
    let places: [Place]
    let routes: [Route]
    let routines: [Routine]
    let trips: [Trip]
    /// Departures by local weekday (Monday first) and hour: 7 × 24.
    let pattern: [[Int]]

    struct Totals: Decodable, Equatable {
        let trips: Int
        let places: Int
        let minutes: Double
        let perWeek: Double
    }

    struct Place: Decodable, Equatable, Identifiable {
        let name: String
        let trips: Int
        let share: Double
        var id: String { name }
    }

    struct Route: Decodable, Equatable, Identifiable {
        let id: String
        let from: String
        let to: String
        let mode: String
        let trips: Int
        let median: Double
        let low: Double
        let high: Double
        let departure: String
        /// Median minutes over the newer half of the trips, and the older.
        let recentMedian: Double?
        let earlierMedian: Double?
        let lastAt: String?
    }

    struct Routine: Decodable, Equatable, Identifiable {
        let id: String
        let from: String
        let to: String
        let dayType: String
        let departure: String
        let window: [Int]
        let days: Int
        let of: Int
        let punctuality: Punctuality?
    }

    /// Runs that left over ten minutes before the usual time, within ten
    /// either side, and over ten after.
    struct Punctuality: Decodable, Equatable {
        let early: Int
        let onTime: Int
        let late: Int
        var total: Int { early + onTime + late }
    }

    struct Trip: Decodable, Equatable, Identifiable {
        let from: String
        let to: String
        let start: String
        let minutes: Double
        let mode: String
        /// The trail lost them part way: the time is not a journey time.
        let broken: Bool
        var id: String { "\(start)|\(from)|\(to)" }
    }

    private enum CodingKeys: String, CodingKey { case subject, name, days, totals, places, routes, routines, trips, pattern }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subject = try c.decode(String.self, forKey: .subject)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? subject.capitalized
        days = (try? c.decodeIfPresent(Int.self, forKey: .days)) ?? 90
        totals = (try? c.decodeIfPresent(Totals.self, forKey: .totals)) ?? Totals(trips: 0, places: 0, minutes: 0, perWeek: 0)
        places = (try? c.decodeIfPresent([Place].self, forKey: .places)) ?? []
        routes = (try? c.decodeIfPresent([Route].self, forKey: .routes)) ?? []
        routines = (try? c.decodeIfPresent([Routine].self, forKey: .routines)) ?? []
        trips = (try? c.decodeIfPresent([Trip].self, forKey: .trips)) ?? []
        let grid = (try? c.decodeIfPresent([[Int]].self, forKey: .pattern)) ?? []
        // Exactly 7 × 24, whatever was sent: a short row is zeros, not a crash.
        pattern = (0..<7).map { d in (0..<24).map { h in d < grid.count && h < grid[d].count ? grid[d][h] : 0 } }
    }

    var isEmpty: Bool { trips.isEmpty && routes.isEmpty }
}

/// The words the history page uses. PURE.
enum MoveHistoryWords {
    /// "4.2 a week", "1 a week", "under 1 a week".
    static func perWeek(_ n: Double) -> String {
        if n < 1 { return "under 1 a week" }
        let rounded = (n * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded)) a week" : String(format: "%.1f a week", rounded)
    }

    /// "31 h", "45 min".
    static func duration(_ minutes: Double) -> String {
        minutes >= 120 ? "\(Int((minutes / 60).rounded())) h" : "\(Int(minutes.rounded())) min"
    }

    /// Whether a route is getting quicker or slower: nil when the halves are
    /// within a minute (or under 4 trips were clean), else the sentence.
    static func trend(_ route: FamilyMoveHistory.Route) -> (text: String, quicker: Bool)? {
        guard let recent = route.recentMedian, let earlier = route.earlierMedian, abs(recent - earlier) >= 1 else { return nil }
        let quicker = recent < earlier
        return ("\(quicker ? "Quicker" : "Slower") lately: \(Int(earlier.rounded())) → \(Int(recent.rounded())) min", quicker)
    }

    /// "On time 9 of 12 · 2 late · 1 early".
    static func punctuality(_ p: FamilyMoveHistory.Punctuality) -> String {
        var parts = ["On time \(p.onTime) of \(p.total)"]
        if p.late > 0 { parts.append("\(p.late) late") }
        if p.early > 0 { parts.append("\(p.early) early") }
        return parts.joined(separator: " · ")
    }

    /// "Mon 20 Oct · 08:24".
    static func when(_ iso: String) -> String {
        guard let date = parseTimestamp(iso) else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " · "
            + date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func symbol(mode: String) -> String {
        switch mode {
        case "vehicle": return "car.fill"
        case "active": return "figure.walk"
        default: return "arrow.triangle.turn.up.right.circle"
        }
    }
}

@MainActor
final class FamilyMoveHistoryStore: ObservableObject {
    @Published private(set) var history: FamilyMoveHistory?
    @Published private(set) var loading = false
    @Published private(set) var failure: String?

    static let windows = [7, 28, 90]

    func load(subject: String, days: Int) async {
        loading = true
        defer { loading = false }
        let safe = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))) ?? subject
        do {
            history = try await SiteClient.shared.send("api/native/family/forecast/history?subject=\(safe)&days=\(days)")
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            switch error as? SiteError {
            case .status(403, _)?: failure = "Their history is theirs, and their guardian's."
            case .status(404, _)?: failure = "No trips of theirs in this stretch yet."
            case .status(_, let text)? where !text.isEmpty: failure = text
            default: failure = "Their history did not load. Pull to try again."
            }
        }
    }
}

/// Navigation value for one person's move history.
struct FamilyMoveHistoryRef: Hashable {
    let subject: String
}

struct FamilyMoveHistoryScreen: View {
    let ref: FamilyMoveHistoryRef
    @StateObject private var store = FamilyMoveHistoryStore()
    @State private var days = 90
    /// How many of the trips are listed; "Show more" adds to it.
    @State private var shown = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                Picker("Stretch", selection: $days) {
                    Text("Week").tag(7)
                    Text("4 weeks").tag(28)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("move-history-window")

                if let history = store.history, history.subject == ref.subject {
                    if history.isEmpty {
                        SREmpty(title: "No trips yet", icon: "point.topleft.down.to.point.bottomright.curvepath",
                                message: "Nothing in this stretch: the trail needs a few journeys before it has anything to say.")
                    } else {
                        content(history)
                    }
                } else if let failure = store.failure {
                    SREmpty(title: "Not available", icon: "clock.arrow.circlepath", message: failure)
                } else {
                    ProgressView().tint(SR.accent).frame(maxWidth: .infinity).padding(.vertical, 60)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .navigationTitle(store.history.map { "\($0.name)'s moves" } ?? "Moves")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: days) { await store.load(subject: ref.subject, days: days) }
        .srRefreshable { await store.load(subject: ref.subject, days: days) }
        .accessibilityIdentifier("move-history-screen")
    }

    @ViewBuilder
    private func content(_ history: FamilyMoveHistory) -> some View {
        let colour = FamilyFaces().colour(subject: history.subject, id: history.subject)
        summary(history)
        if !history.places.isEmpty { places(history, colour: colour) }
        pattern(history, colour: colour)
        if !history.routines.isEmpty { routines(history) }
        if !history.routes.isEmpty { routes(history) }
        if !history.trips.isEmpty { trips(history) }
    }

    // MARK: - The figures

    private func summary(_ h: FamilyMoveHistory) -> some View {
        HStack(spacing: 0) {
            figure("\(h.totals.trips)", h.totals.trips == 1 ? "trip" : "trips")
            figure(MoveHistoryWords.perWeek(h.totals.perWeek).replacingOccurrences(of: " a week", with: ""), "a week")
            figure(MoveHistoryWords.duration(h.totals.minutes), "on the move")
            figure("\(h.totals.places)", h.totals.places == 1 ? "place" : "places")
        }
        .padding(.vertical, 14)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("move-history-summary")
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(SR.monoMedium(20)).foregroundStyle(SR.ink).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(SR.Text.label()).foregroundStyle(SR.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Where

    /// Bars by share of arrivals, labelled with the count: the commonest first.
    private func places(_ h: FamilyMoveHistory, colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Where they go", trailing: "arrivals")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(h.places.prefix(6)) { place in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(place.name).font(SR.Text.bodyMedium(14)).foregroundStyle(SR.ink).lineLimit(1)
                            Spacer()
                            Text("\(place.trips)").font(SR.monoMedium(13)).foregroundStyle(SR.inkSecondary)
                        }
                        GeometryReader { geo in
                            Capsule().fill(SR.ink.opacity(0.06))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(colour).frame(width: max(6, geo.size.width * min(1, place.share)))
                                }
                        }
                        .frame(height: 8)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(place.name): \(place.trips) arrivals, \(Int((place.share * 100).rounded())) percent")
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("move-history-places")
    }

    // MARK: - When

    /// Departures by weekday and hour: one cell an hour, darker for more.
    private func pattern(_ h: FamilyMoveHistory, colour: Color) -> some View {
        let peak = max(1, h.pattern.flatMap { $0 }.max() ?? 1)
        let labels = ["M", "T", "W", "T", "F", "S", "S"]
        return VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "When they leave", trailing: "by hour")
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<7, id: \.self) { day in
                    HStack(spacing: 2) {
                        Text(labels[day])
                            .font(SR.Text.label(11))
                            .foregroundStyle(SR.inkMuted)
                            .frame(width: 14, alignment: .leading)
                        ForEach(0..<24, id: \.self) { hour in
                            let n = h.pattern[day][hour]
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(n == 0 ? SR.ink.opacity(0.05) : colour.opacity(0.2 + 0.8 * Double(n) / Double(peak)))
                                .frame(height: 14)
                        }
                    }
                }
                HStack(spacing: 0) {
                    Color.clear.frame(width: 16)
                    ForEach([0, 6, 12, 18], id: \.self) { hour in
                        Text(String(format: "%02d", hour))
                            .font(SR.Text.label(10))
                            .foregroundStyle(SR.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.patternSummary(h.pattern))
        }
        .accessibilityIdentifier("move-history-pattern")
    }

    /// For VoiceOver: the busiest hour of the week, in words.
    static func patternSummary(_ grid: [[Int]]) -> String {
        let names = ["Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays"]
        var best = (day: 0, hour: 0, n: 0)
        for (d, row) in grid.enumerated() { for (hr, n) in row.enumerated() where n > best.n { best = (d, hr, n) } }
        guard best.n > 0 else { return "No departures in this stretch." }
        return "Most often leaves on \(names[best.day]) around \(String(format: "%02d:00", best.hour)), \(best.n) times."
    }

    // MARK: - Regular trips

    private func routines(_ h: FamilyMoveHistory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Regular trips", trailing: "leaving on time")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(h.routines.enumerated()), id: \.element.id) { index, r in
                    if index > 0 { Rectangle().fill(SR.divider).frame(height: 1) }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(r.from) → \(r.to)").font(SR.Text.title(15)).foregroundStyle(SR.ink)
                        Text("\(r.dayType == "weekend" ? "Weekends" : "Weekdays") · usually \(r.departure)"
                             + (r.window.count == 2 ? " (\(ForecastWords.hhmm(r.window[0]))–\(ForecastWords.hhmm(r.window[1])))" : ""))
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                        Text(ForecastWords.ofDays(r.days, r.of, r.dayType))
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                        if let p = r.punctuality, p.total > 0 {
                            punctualityBar(p)
                            Text(MoveHistoryWords.punctuality(p))
                                .font(SR.Text.secondary(13))
                                .foregroundStyle(SR.inkSecondary)
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("move-history-routines")
    }

    /// Early · on time · late, as one bar in three parts.
    private func punctualityBar(_ p: FamilyMoveHistory.Punctuality) -> some View {
        GeometryReader { geo in
            let total = CGFloat(max(1, p.total))
            HStack(spacing: 2) {
                if p.early > 0 { Rectangle().fill(SR.accentInk).frame(width: geo.size.width * CGFloat(p.early) / total) }
                if p.onTime > 0 { Rectangle().fill(SR.good).frame(width: geo.size.width * CGFloat(p.onTime) / total) }
                if p.late > 0 { Rectangle().fill(SR.warn).frame(width: geo.size.width * CGFloat(p.late) / total) }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    // MARK: - Routes

    private func routes(_ h: FamilyMoveHistory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Routes", trailing: "typical time")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(h.routes.prefix(8).enumerated()), id: \.element.id) { index, route in
                    if index > 0 { Rectangle().fill(SR.divider).frame(height: 1).padding(.leading, 32) }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: MoveHistoryWords.symbol(mode: route.mode))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SR.accentInk)
                            .frame(width: 20)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(route.from) → \(route.to)").font(SR.Text.title(15)).foregroundStyle(SR.ink)
                            Text("\(route.trips) \(route.trips == 1 ? "trip" : "trips") · usually leaves \(route.departure)"
                                 + (route.lastAt.map { " · last \(MoveHistoryWords.when($0))" } ?? ""))
                                .font(SR.Text.secondary(13))
                                .foregroundStyle(SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let trend = MoveHistoryWords.trend(route) {
                                Label(trend.text, systemImage: trend.quicker ? "arrow.down.right" : "arrow.up.right")
                                    .font(SR.Text.secondary(13))
                                    .foregroundStyle(trend.quicker ? SR.good : SR.warn)
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(route.median.rounded())) min").font(SR.monoMedium(15)).foregroundStyle(SR.ink)
                            Text("\(Int(route.low.rounded()))–\(Int(route.high.rounded()))").font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("move-history-routes")
    }

    // MARK: - The trips

    private func trips(_ h: FamilyMoveHistory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Recent moves", trailing: "\(h.trips.count)")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(h.trips.prefix(shown).enumerated()), id: \.element.id) { index, trip in
                    if index > 0 { Rectangle().fill(SR.divider).frame(height: 1).padding(.leading, 32) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: MoveHistoryWords.symbol(mode: trip.mode))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SR.inkMuted)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(trip.from) → \(trip.to)").font(SR.Text.bodyMedium(14)).foregroundStyle(SR.ink)
                            Text(MoveHistoryWords.when(trip.start)).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                        }
                        Spacer(minLength: 8)
                        Text(trip.broken ? "trail lost" : "\(Int(trip.minutes.rounded())) min")
                            .font(SR.monoMedium(13))
                            .foregroundStyle(trip.broken ? SR.inkGhost : SR.inkSecondary)
                    }
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .combine)
                }
                if h.trips.count > shown {
                    Button {
                        SRHaptic.tap()
                        withAnimation(.snappy) { shown += 20 }
                    } label: {
                        Text("Show more").font(SR.Text.bodyMedium(14)).foregroundStyle(SR.accentDeep)
                            .frame(maxWidth: .infinity, minHeight: SR.tapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("move-history-more")
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("move-history-trips")
    }
}

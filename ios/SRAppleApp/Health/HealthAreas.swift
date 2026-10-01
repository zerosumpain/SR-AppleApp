import SwiftUI

// MARK: - Colour, across Health
//
// Every screen on the Health stack speaks the same two colours, and says the
// same thing with each:
//
// - BROWN — the ink band — is the screen's headline. One band, at the top, on
//   every screen: readiness on the tab, the week on Activities, form on
//   Segments, your routes on Routes, the read on Insights, the outing, the
//   stretch or the route on a detail. Everything under it is paper. A second
//   band would be a second headline, and a tall one reads as intensity.
// - ORANGE ON BROWN (`accentOnDark`) is the kicker and the ONE lit figure: the
//   number the screen is about. Distance for a week, best time for a segment,
//   how many are improving. If two figures are lit, neither is.
// - ORANGE ON PAPER (`accent`) is what you can act on, or what is yours to
//   celebrate: the glyph of a way in, the one primary button, a best effort, a
//   live flag, the selected filter. Never body copy, never decoration.
// - Olive stays "the right way" and red stays "tripped". Neither is orange's
//   job, and orange is neither of theirs.

// MARK: - The four areas

/// The four ways off the Health tab, two by two under the ink hero:
/// Activities, Segments, Routes, Insights.
///
/// The tab used to stack the read, the tripwires, the moves, recent
/// activities and "The full picture" under the hero — nine sections a thumb
/// scrolled past to reach the one it wanted. Now the hero answers "how am I
/// doing" and these four say where everything else lives, each one push away.
struct HealthAreasGrid: View {
    let week: HealthWeek?
    let hub: HubDigest?
    let noticed: Int

    var body: some View {
        SRTileGrid {
            HealthAreaTile(
                title: "Activities",
                icon: "figure.run",
                detail: activitiesLine,
                route: .activities,
                identifier: "health-all-activities"
            )
            HealthAreaTile(
                title: "Segments",
                icon: "flag.checkered",
                detail: segmentsLine,
                route: .segments,
                identifier: "health-segments"
            )
            HealthAreaTile(
                title: "Routes",
                icon: "point.topleft.down.to.point.bottomright.curvepath",
                detail: "Plan, save and follow",
                route: .routes,
                identifier: "health-routes"
            )
            HealthAreaTile(
                title: "Insights",
                icon: "sparkles",
                detail: insightsLine,
                route: .insights,
                identifier: "health-insights",
                flagged: liveTripwires > 0
            )
        }
    }

    private var activitiesLine: String {
        guard let week else { return "Every workout" }
        if week.activities == 0 { return "None this week" }
        return "\(week.activities) this week · \(TrailFormat.km(fromKm: week.distanceKm)) km"
    }

    private var segmentsLine: String {
        guard let segments = hub?.segments else { return "Your efforts, compared" }
        if let near = segments.gettable.first {
            // The thing worth going out for, first.
            return "Best in reach: \(near.name)"
        }
        return "\(segments.improving) improving · \(segments.slipping) slipping"
    }

    private var liveTripwires: Int { hub?.tripwires.filter(\.live).count ?? 0 }

    private var insightsLine: String {
        guard let hub else { return "The read, forecasts, verdict" }
        if liveTripwires > 0 {
            return liveTripwires == 1 ? "1 tripwire live" : "\(liveTripwires) tripwires live"
        }
        if noticed > 0 { return noticed == 1 ? "1 thing noticed" : "\(noticed) things noticed" }
        if !hub.tripwires.isEmpty { return "All clear" }
        return "The read, forecasts, verdict"
    }
}

/// One area: a glyph, its name, and a line on what is in it.
///
/// A Button that pushes, not a NavigationLink — inside a List row a
/// NavigationLink earns a disclosure chevron, and the hero's tiles found that
/// four of them draw chevrons in the gutters between tiles.
struct HealthAreaTile: View {
    let title: String
    let icon: String
    let detail: String
    let route: HealthRoute
    let identifier: String
    /// Something inside wants a look: the glyph takes the accent's dot.
    var flagged = false
    @EnvironmentObject private var router: Router

    var body: some View {
        Button {
            SRHaptic.tap()
            router.health.append(route)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SR.accent)
                        .frame(width: 28, height: 28, alignment: .leading)
                        .overlay(alignment: .topTrailing) {
                            if flagged {
                                Circle().fill(SR.accent).frame(width: 7, height: 7).offset(x: 2, y: -2)
                            }
                        }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SR.inkGhost)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(SR.Text.display(19))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                    // Two lines reserved, so the four tiles stand the same
                    // height whatever each has to say.
                    Text(detail)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SR.cardPadding)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(detail)")
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Days

/// An activity's day as it was lived, `yyyy-MM-dd`.
///
/// `startDateLocal` is read, not parsed through a Date, for the reason
/// `TrailFormat.date` gives: an evening run abroad must not slide into the
/// next day. The ISO instant, in the phone's zone, is the fallback.
enum ActivityDay {
    static func key(_ row: ActivityRow) -> String? {
        if let local = row.startDateLocal?.trimmingCharacters(in: .whitespaces), local.count >= 10 {
            let day = String(local.prefix(10))
            if isDayKey(day) { return day }
        }
        guard let date = isoDate(row.startDate) else { return nil }
        return formatter.string(from: date)
    }

    static func key(_ date: Date) -> String { formatter.string(from: date) }

    /// "2026-09-30" or "2026-09" → "September 2026".
    static func month(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else {
            return "Earlier"
        }
        return "\(monthNames[month - 1]) \(year)"
    }

    private static func isDayKey(_ value: String) -> Bool {
        let c = Array(value)
        return c.count == 10 && c[4] == "-" && c[7] == "-"
            && Int(String(c[0..<4])) != nil && Int(String(c[5..<7])) != nil && Int(String(c[8..<10])) != nil
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
}

/// One day of the last seven, for the week's bars.
struct ActivityWeekDay: Identifiable, Hashable {
    let key: String
    /// "M", "T" — the weekday under its bar.
    let initial: String
    let km: Double
    let count: Int
    let today: Bool
    var id: String { key }

    /// The seven days ending today, oldest first, from whatever rows are
    /// loaded. The list's first page is thirty, which always reaches back a
    /// week; a day with nothing on it is a real zero.
    static func lastSeven(_ rows: [ActivityRow], now: Date = Date()) -> [ActivityWeekDay] {
        var km: [String: Double] = [:]
        var count: [String: Int] = [:]
        for row in rows {
            guard let key = ActivityDay.key(row) else { continue }
            km[key, default: 0] += (row.distanceM ?? 0) / 1000
            count[key, default: 0] += 1
        }
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        return (0..<7).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: now) else { return nil }
            let key = ActivityDay.key(date)
            let weekday = calendar.component(.weekday, from: date)
            return ActivityWeekDay(
                key: key,
                initial: symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "",
                km: km[key] ?? 0,
                count: count[key] ?? 0,
                today: back == 0
            )
        }
    }
}

// MARK: - The week, on ink

/// Seven bars, one a day, on the band.
///
/// In accent-on-dark because they ARE the lit figure above them — the week's
/// distance, laid out by day — and one colour for one quantity is how the eye
/// joins the number to its shape. Today is marked by its letter, in full
/// cream, not by a second colour.
struct SRInkWeekBars: View {
    let days: [ActivityWeekDay]
    var height: CGFloat = 52

    var body: some View {
        let peak = max(days.map(\.km).max() ?? 0, 0.1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SR.onInk(.fill))
                        if day.count > 0 {
                            // An outing with no distance (a swim logged by
                            // time, a gym session) still gets a stub: it
                            // happened.
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(SR.accentOnDark)
                                .frame(height: max(4, height * CGFloat(day.km / peak)))
                        }
                    }
                    .frame(height: height)
                    Text(day.initial)
                        .font(SR.Text.label())
                        .foregroundStyle(day.today ? SR.onInk(.primary) : SR.onInk(.label))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLine)
    }

    private var accessibilityLine: String {
        let active = days.filter { $0.count > 0 }
        if active.isEmpty { return "Nothing in the last seven days" }
        return "Active on \(active.count) of the last seven days"
    }
}

/// The Activities screen's headline: the week, in figures and by day.
struct ActivitiesWeekBand: View {
    let week: HealthWeek?
    let days: [ActivityWeekDay]

    var body: some View {
        SRInkBand(kicker: "This week", meta: "The last seven days", inset: 0) {
            if let week {
                SRInkCellGrid(figures: [
                    // Distance lit: it is what the bars below are drawn in.
                    SRInkFigure(label: "Distance", value: TrailFormat.km(fromKm: week.distanceKm), unit: "km", lit: true),
                    SRInkFigure(label: "Activities", value: "\(week.activities)"),
                    SRInkFigure(label: "Moving", value: TrailFormat.minutes(week.durationMinutes)),
                    SRInkFigure(label: "Climbed", value: "\(week.elevationM)", unit: "m"),
                ])
            }
            if days.contains(where: { $0.count > 0 }) {
                SRInkWeekBars(days: days)
            }
        }
    }
}

// MARK: - Records

/// Personal records as a strip of cards that scrolls sideways — a row each
/// would push the history a screen down to show three numbers.
///
/// The trophy is orange: a record is the reader's to celebrate.
struct RecordsStrip: View {
    let records: [HealthRecordHighlight]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SR.cardGap) {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(SR.accent)
                            Text(record.label.uppercased())
                                .font(SR.Text.label())
                                .tracking(1.2)
                                .foregroundStyle(SR.inkMuted)
                                .lineLimit(1)
                        }
                        Text(record.display)
                            .font(SR.Text.figure(22))
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                        if let date = record.date, !date.isEmpty {
                            Text(date)
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                                .lineLimit(1)
                        }
                    }
                    .padding(14)
                    .frame(minWidth: 150, alignment: .leading)
                    .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Filter chips

struct HealthChip: Identifiable, Hashable {
    /// nil is "all".
    let key: String?
    let label: String
    let count: Int
    var id: String { key ?? "all" }
}

/// A row of filters. The selected one is the accent, filled — a filter is a
/// thing the reader acts on — in the deep accent, which is the one that holds
/// cream text.
struct HealthChips: View {
    let chips: [HealthChip]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let on = chip.key == selection
                    Button {
                        SRHaptic.select()
                        withAnimation(.easeOut(duration: 0.15)) { selection = chip.key }
                    } label: {
                        HStack(spacing: 6) {
                            Text(chip.label.uppercased())
                                .font(SR.Text.label())
                                .tracking(1)
                            Text("\(chip.count)")
                                .font(SR.Text.mono())
                                .opacity(0.75)
                        }
                        .foregroundStyle(on ? SR.paper : SR.inkSecondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(on ? SR.accentDeep : SR.Glass.rowFill))
                        .overlay(Capsule().strokeBorder(on ? Color.clear : SR.line, lineWidth: 1))
                        .frame(minHeight: SR.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(chip.label), \(chip.count)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("chip-\(chip.id)")
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Segments, on ink

/// The Segments screen's headline: which way your form is going.
///
/// Counted from the list itself, so the band and the rows under it can never
/// disagree. Improving is the lit figure — the question a segment answers is
/// "am I getting quicker".
struct SegmentsFormBand: View {
    let rows: [SegmentRow]

    var body: some View {
        SRInkBand(kicker: "Form", meta: "Recent efforts against earlier ones", inset: 0) {
            SRInkCellGrid(figures: [
                SRInkFigure(label: "Improving", value: "\(count("improving"))", lit: true),
                SRInkFigure(label: "Holding", value: "\(count("holding"))"),
                SRInkFigure(label: "Slipping", value: "\(count("slipping"))"),
                SRInkFigure(label: "No read yet", value: "\(unread)"),
            ])
            if let newest {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SR.accentOnDark)
                    Text(newestLine(newest))
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.onInk(.note))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func count(_ direction: String) -> Int {
        rows.filter { $0.form?.direction == direction }.count
    }

    private var unread: Int {
        rows.filter { $0.form?.known != true }.count
    }

    /// The segment whose best is freshest.
    private var newest: SegmentRow? {
        rows.filter { $0.form?.daysSincePb != nil }
            .min { ($0.form?.daysSincePb ?? .max) < ($1.form?.daysSincePb ?? .max) }
    }

    private func newestLine(_ row: SegmentRow) -> String {
        let days = row.form?.daysSincePb ?? 0
        let when = days == 0 ? "today" : days == 1 ? "yesterday" : "\(days) days ago"
        return "Newest best: \(row.name), \(when)."
    }
}

/// A best within reach, as /health judged it: how far off, and on what.
struct WithinReachRow: View {
    let gettable: HubDigest.Segments.Gettable

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SR.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(gettable.name)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                if let detail = gettable.detail, !detail.isEmpty {
                    Text(detail.uppercased())
                        .font(SR.Text.mono())
                        .tracking(0.6)
                        .foregroundStyle(SR.inkMuted)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f%%", gettable.gapPct))
                    .font(SR.Text.mono(15))
                    .foregroundStyle(SR.accent)
                Text("OFF BEST")
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Routes, on ink

/// The Routes screen's headline: what you have saved, what works with no
/// signal, and the one thing to do here — plan another. That button is the
/// screen's one orange action.
struct RoutesBand: View {
    let saved: [PlannedRouteSummary]
    let loaded: Bool
    let offline: Int
    let waiting: Int
    @EnvironmentObject private var router: Router

    var body: some View {
        SRInkBand(kicker: "Routes", meta: meta, inset: 0) {
            SRInkCellGrid(figures: figures)
            Button {
                SRHaptic.tap()
                router.health.append(HealthRoute.planRoute)
            } label: {
                Label("Plan a route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(SR.Text.bodyMedium(16))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .srButton(.prominent)
            .accessibilityIdentifier("routes-plan")
        }
    }

    private var meta: String? {
        waiting > 0 ? (waiting == 1 ? "1 walk waiting to upload" : "\(waiting) walks waiting to upload") : nil
    }

    private var figures: [SRInkFigure] {
        let longest = saved.map(\.distanceM).max()
        return [
            SRInkFigure(label: "Saved", value: loaded ? "\(saved.count)" : "—", lit: true),
            SRInkFigure(label: "Offline", value: "\(offline)"),
            SRInkFigure(label: "Longest", value: longest.map { TrailFormat.km($0) } ?? "—", unit: longest == nil ? nil : "km"),
            SRInkFigure(label: "Published", value: "\(saved.filter { $0.source == "imported" }.count)"),
        ]
    }
}

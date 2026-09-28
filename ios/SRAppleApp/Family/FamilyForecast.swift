import Foundation
import SwiftUI

/// The travel desk's forecast, from the site (`GET /api/native/family/forecast`)
/// — the same computation /home/people draws: each person's next likely move,
/// what looks off right now, and the routines behind those guesses, learned
/// from the family's own trail. Nothing here is a model's guess; every figure
/// says how many trips it stands on.
///
/// Scoped by the site like the page: the owner's phone gets everyone sharing;
/// a Family Circle member's phone gets themselves and their wards. Fields the
/// phone does not draw (arrivals, the departure grid) are left undecoded.
struct FamilyForecast: Decodable, Equatable {
    let generatedAt: String
    let days: Int
    let routines: [Routine]
    let next: [NextMove]
    let watch: [WatchItem]
    let people: [Person]

    struct Person: Decodable, Equatable {
        let subject: String
        let name: String
        /// Share of the window the trail actually observed, 0…1.
        let coverage: Double
    }

    struct Minutes: Decodable, Equatable {
        let median: Double
        let low: Double
        let high: Double
        /// Four trips in five arrive inside this: what a leave-by is set against.
        let p80: Double
    }

    /// "Home → School, weekdays, leaves 08:24" — a route someone takes at a
    /// regular time.
    struct Routine: Decodable, Equatable, Identifiable {
        let id: String
        let subject: String
        let person: String
        let from: String
        let to: String
        /// `vehicle` or `active` (on foot or by bike) — GPS cannot say which.
        let mode: String
        /// `weekday` or `weekend`.
        let dayType: String
        /// Usual departure, local "HH:MM".
        let departure: String
        /// Where 80% of departures fall, as minutes of the day.
        let window: [Int]
        let days: Int
        let of: Int
        let minutes: Minutes
    }

    /// A live arrival window (`arriving`), or the routine due from where they
    /// are now (`routine`).
    struct NextMove: Decodable, Equatable {
        let subject: String
        let kind: String
        let from: String
        let to: String
        let leaveAt: String
        let arriveFrom: String
        let arriveTo: String
        let days: Int
        let of: Int
        let dayType: String?
        let confidence: String
    }

    /// Something different from the person's own routine: `overdue`,
    /// `running-long` or `quiet`.
    struct WatchItem: Decodable, Equatable, Identifiable {
        let key: String
        let kind: String
        let subject: String
        /// `watch` or `alert`.
        let severity: String
        let title: String
        let detail: String
        var id: String { key }
    }

    func next(for subject: String) -> NextMove? { next.first { $0.subject == subject } }
    func routines(for subject: String) -> [Routine] { routines.filter { $0.subject == subject } }
    func watch(for subject: String) -> [WatchItem] { watch.filter { $0.subject == subject } }
    func coverage(for subject: String) -> Double? { people.first { $0.subject == subject }?.coverage }
}

/// The forecast's words, shared by the Family tab and a person's page.
/// Clocks are the phone's own zone: the site sends instants.
enum ForecastWords {
    static func clock(_ iso: String) -> String? {
        guard let date = parseTimestamp(iso) else { return nil }
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// Minutes of the day as "HH:MM".
    static func hhmm(_ minuteOfDay: Int) -> String {
        let m = ((minuteOfDay % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// "11 of 18 weekdays".
    static func ofDays(_ days: Int, _ of: Int, _ dayType: String?) -> String {
        switch dayType {
        case "weekday": return "\(days) of \(of) weekdays"
        case "weekend": return "\(days) of \(of) weekend days"
        default: return "\(days) similar trips"
        }
    }

    /// One line under a person's row. "Leaves 08:24 for School · there
    /// 08:38–08:42" before the time; "Due to leave for School (08:24)" once it
    /// has passed; "Arriving School 08:35–08:40" on the way.
    static func nextLine(_ move: FamilyForecast.NextMove, now: Date = Date()) -> String {
        let from = clock(move.arriveFrom) ?? "", to = clock(move.arriveTo) ?? ""
        if move.kind == "arriving" {
            return "Arriving \(move.to) \(from)–\(to)"
        }
        let leave = clock(move.leaveAt) ?? ""
        if let at = parseTimestamp(move.leaveAt), at < now {
            return "Due to leave for \(move.to) (usually \(leave))"
        }
        return "Leaves \(leave) for \(move.to) · there \(from)–\(to)"
    }

    /// "Weekdays · leaves 08:17–08:32, usually 08:24"
    static func routineWhen(_ r: FamilyForecast.Routine) -> String {
        let days = r.dayType == "weekend" ? "Weekends" : "Weekdays"
        guard r.window.count == 2 else { return "\(days) · usually \(r.departure)" }
        return "\(days) · leaves \(hhmm(r.window[0]))–\(hhmm(r.window[1])), usually \(r.departure)"
    }

    /// "16 min" and "13–18 · 11 of 18 weekdays"
    static func routineTime(_ r: FamilyForecast.Routine) -> (headline: String, detail: String) {
        ("\(Int(r.minutes.median.rounded())) min",
         "\(Int(r.minutes.low.rounded()))–\(Int(r.minutes.high.rounded())) min · \(ofDays(r.days, r.of, r.dayType))")
    }

    /// "Leave 18 min ahead to arrive on time four times in five."
    static func leaveAhead(_ r: FamilyForecast.Routine) -> String {
        "Leave \(Int(r.minutes.p80.rounded(.up))) min ahead to be on time four trips in five."
    }

    static func symbol(_ w: FamilyForecast.WatchItem) -> String {
        switch w.kind {
        case "overdue": return "clock.badge.exclamationmark"
        case "running-long": return "hourglass"
        default: return "antenna.radiowaves.left.and.right.slash"
        }
    }
}

/// The forecast, from the site. Shared, so the tab and a person's page read
/// one copy. The Family tab refreshes every 15 seconds for positions; the
/// forecast is a month of trail on the site, so it is re-read at most once a
/// minute unless the reader pulls to refresh.
@MainActor
final class FamilyForecastStore: ObservableObject {
    static let shared = FamilyForecastStore()
    static let minimumGap: TimeInterval = 60

    @Published private(set) var forecast: FamilyForecast?
    @Published private(set) var loading = false
    private var lastLoad: Date?

    /// Only where the site will answer: family, with the site credential — the
    /// same rule as the step board (`AccessPolicy.familyBoards`).
    var available: Bool { AccessStore.shared.familyBoards }

    func load(force: Bool = false) async {
        guard available, !loading else { return }
        if !force, let lastLoad, Date().timeIntervalSince(lastLoad) < Self.minimumGap { return }
        loading = true
        defer { loading = false }
        do {
            let fetched: FamilyForecast = try await SiteClient.shared.send("api/native/family/forecast")
            forecast = fetched
            lastLoad = Date()
        } catch {
            // The forecast is an extra over the positions: a failed read keeps
            // the last one (or none) and says nothing — the tab stands without it.
            if forecast == nil { lastLoad = Date() }
        }
    }

    /// "View as" changed: the forecast was somebody else's.
    func reset() {
        forecast = nil
        lastLoad = nil
    }
}

/// Today's line on the family's day ahead: what looks off, then the next few
/// moves by time — "Sam · Leaves 15:40 for Home · there 16:02–16:10". Draws
/// NOTHING when nobody has a move due and nothing looks off, so a quiet day
/// costs Today no space. Tap → the Family tab.
struct TodayForecastCard: View {
    @ObservedObject private var store = FamilyForecastStore.shared
    let open: () -> Void

    static let movesShown = 3
    static let flagsShown = 2

    var body: some View {
        if let f = store.forecast, !(f.next.isEmpty && f.watch.isEmpty) {
            let names = Dictionary(f.people.map { ($0.subject, $0.name) }, uniquingKeysWith: { a, _ in a })
            let moves = f.next.sorted { (parseTimestamp($0.leaveAt) ?? .distantFuture) < (parseTimestamp($1.leaveAt) ?? .distantFuture) }
            Button {
                SRHaptic.tap()
                open()
            } label: {
                SRCard(interactive: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        SRSectionLabel(text: "Family · next", trailing: f.watch.isEmpty ? nil : "\(f.watch.count) to look at")
                        ForEach(f.watch.prefix(Self.flagsShown)) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: ForecastWords.symbol(item))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(item.severity == "alert" ? SR.error : SR.warn)
                                Text(item.title)
                                    .font(SR.Text.bodyMedium(15))
                                    .foregroundStyle(SR.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        ForEach(Array(moves.prefix(Self.movesShown).enumerated()), id: \.offset) { _, move in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(names[move.subject] ?? move.subject.capitalized)
                                    .font(SR.Text.bodyMedium(15))
                                    .foregroundStyle(SR.ink)
                                    .frame(minWidth: 52, alignment: .leading)
                                Text(ForecastWords.nextLine(move))
                                    .font(SR.Text.mono(13))
                                    .foregroundStyle(move.kind == "arriving" ? SR.accentInk : SR.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens Family")
            .accessibilityIdentifier("today-forecast")
        }
    }
}

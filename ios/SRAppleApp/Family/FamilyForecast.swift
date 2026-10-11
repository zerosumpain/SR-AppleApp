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
    /// `var`: a move somebody says is wrong comes off at once (`correct`).
    var next: [NextMove]
    let watch: [WatchItem]
    let people: [Person]
    /// The owner's next two days with leave-by times — null on anyone else's
    /// phone (it is the owner's calendar), and absent from an older site.
    let upcoming: Upcoming?

    struct Upcoming: Decodable, Equatable {
        /// False when the diary could not be read: say so, never "nothing on".
        let available: Bool
        let items: [UpcomingItem]
    }

    struct UpcomingItem: Decodable, Equatable, Identifiable {
        let id: String
        let title: String
        let start: String
        let end: String?
        let place: String
        let subjects: [String]
        let leaveBy: String?
        let from: String?
        let travel: Travel?
        let issue: Issue?

        struct Travel: Decodable, Equatable {
            /// `person`, `household` or `routed`.
            let source: String
            let median: Double
            let p80: Double
            let samples: Int
            let mode: String
        }
        struct Issue: Decodable, Equatable {
            let kind: String
            let text: String
        }
    }

    var names: [String: String] { Dictionary(people.map { ($0.subject, $0.name) }, uniquingKeysWith: { a, _ in a }) }

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
        /// The routine it came from (`kind: "routine"`); null for a live journey.
        var routineId: String? = nil
        let from: String
        let to: String
        let leaveAt: String
        let arriveFrom: String
        let arriveTo: String
        let days: Int
        let of: Int
        let dayType: String?
        let confidence: String

        /// Which move this is, for "that's wrong": the routine, or the
        /// journey by when it left.
        var correctionKey: String {
            kind == "routine" ? "routine:\(subject):\(routineId ?? to)" : "arriving:\(subject):\(leaveAt)"
        }
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

    /// "16 min · from 11 of Sam's trips", "12 min by car · routed, nobody has made this trip yet".
    static func travelLine(_ item: FamilyForecast.UpcomingItem, names: [String: String]) -> String? {
        guard let t = item.travel else { return nil }
        let minutes = "\(Int(t.median.rounded())) min"
        switch t.source {
        case "person":
            let who = item.subjects.first.map { names[$0] ?? $0.capitalized } ?? "their"
            return "\(minutes) · from \(t.samples) of \(who)'s trips"
        case "household": return "\(minutes) · from the family's trips"
        case "corrected": return "\(minutes) \(t.mode == "vehicle" ? "by car" : "on foot") · your destination, timed by Apple Maps"
        default: return "\(minutes) \(t.mode == "vehicle" ? "by car" : "on foot") · routed, nobody has made this trip yet"
        }
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
    /// Said after a correction landed, for a moment, under the moves.
    @Published var thanks: String?
    private var lastLoad: Date?
    /// Moves called wrong this session: kept off even if a read races the
    /// site's own (which leaves them out for the day anyway).
    private var corrected: Set<String> = []

    /// Only where the site will answer: family, with the site credential — the
    /// same rule as the step board (`AccessPolicy.familyBoards`).
    var available: Bool { AccessStore.shared.familyBoards }

    func load(force: Bool = false) async {
        guard available, !loading else { return }
        if !force, let lastLoad, Date().timeIntervalSince(lastLoad) < Self.minimumGap { return }
        loading = true
        defer { loading = false }
        do {
            var fetched: FamilyForecast = try await SiteClient.shared.send("api/native/family/forecast")
            fetched.next.removeAll { corrected.contains($0.correctionKey) }
            forecast = fetched
            lastLoad = Date()
            // Only this phone's own view: "View as" is somebody else's seat,
            // and their diary is not yours to be reminded of.
            if AccessStore.shared.viewingAs == nil {
                // With this phone's corrections: a dismissed journey must
                // not ring, and a corrected one rings at its own time.
                await LeaveByReminders.sync(JourneyCorrections.shared.apply(fetched.upcoming), names: fetched.names)
            }
        } catch {
            // The forecast is an extra over the positions: a failed read keeps
            // the last one (or none) and says nothing — the tab stands without it.
            if forecast == nil { lastLoad = Date() }
        }
    }

    /// "That's wrong" — a long press on a next move ("Katie isn't going to
    /// the station"). The site takes it off for today and counts the day
    /// against the routine, so the forecast learns. Nil when it landed;
    /// otherwise why not.
    func correct(_ move: FamilyForecast.NextMove, note: String? = nil) async -> String? {
        var body: [String: String] = ["subject": move.subject, "kind": move.kind]
        if move.kind == "routine" { body["routineId"] = move.routineId ?? "" } else { body["departedAt"] = move.leaveAt }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { body["note"] = String(note.prefix(280)) }
        do {
            let data = try JSONEncoder().encode(body)
            let _: EmptyReply = try await SiteClient.shared.send("api/native/family/forecast/feedback", method: "POST", body: data)
        } catch SiteError.status(let code, _) where code == 404 {
            // Already gone from the site's forecast: take it off here too.
        } catch {
            SRHaptic.bad()
            return FamilyTasksStore.sentence(for: error)
        }
        SRHaptic.ok()
        corrected.insert(move.correctionKey)
        forecast?.next.removeAll { $0.correctionKey == move.correctionKey }
        let name = forecast?.names[move.subject] ?? move.subject.capitalized
        thanks = "Noted — \(name) isn't heading to \(move.to). The forecast learns from that."
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.thanks = nil
        }
        return nil
    }

    /// "View as" changed: the forecast was somebody else's.
    func reset() {
        forecast = nil
        lastLoad = nil
        corrected = []
        thanks = nil
    }
}

/// Where everyone is going: each person's next likely move, soonest first —
/// "Sam · Leaves 15:40 for Home · there 16:02–16:10", or "Arriving Office
/// 08:35–08:40" while they are on the way. Each line says how many trips it
/// stands on. Lived on Today until 2026-10-02; the Family tab is where the
/// people are, so it is here now.
struct FamilyMovesCard: View {
    let moves: [FamilyForecast.NextMove]
    let names: [String: String]
    @ObservedObject private var store = FamilyForecastStore.shared

    var body: some View {
        let sorted = moves.sorted { (parseTimestamp($0.leaveAt) ?? .distantFuture) < (parseTimestamp($1.leaveAt) ?? .distantFuture) }
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "Next moves", trailing: "from the family's own trips").padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.offset) { index, move in
                    if index > 0 { Rectangle().fill(SR.divider).frame(height: 1).padding(.leading, 44) }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: move.kind == "arriving" ? "location.north.fill" : "clock")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(move.kind == "arriving" ? SR.accentInk : SR.inkMuted)
                            .frame(width: 20)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(names[move.subject] ?? move.subject.capitalized)
                                .font(SR.Text.title(16))
                                .foregroundStyle(SR.ink)
                            Text(ForecastWords.nextLine(move))
                                .font(SR.Text.secondary())
                                .foregroundStyle(move.kind == "arriving" ? SR.accentInk : SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(ForecastWords.ofDays(move.days, move.of, move.dayType))
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    // A long press says the guess is wrong, so it learns.
                    .forecastCorrection(move, name: names[move.subject] ?? move.subject.capitalized)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("family-next-\(move.subject)")
                }
            }
            .srGlassCard(.paper)
            if let thanks = store.thanks {
                Text(thanks)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: store.thanks)
        .accessibilityIdentifier("family-moves")
    }
}

/// The long press on a next move: "Not going to <place>", straight away or
/// with a note ("off sick", "dropped the class"). See
/// `FamilyForecastStore.correct`.
struct ForecastCorrectionMenu: ViewModifier {
    let move: FamilyForecast.NextMove
    let name: String
    @State private var noting = false
    @State private var note = ""
    @State private var failed: String?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button(role: .destructive) { send(nil) } label: {
                    Label("\(name) isn't going to \(move.to)", systemImage: "hand.thumbsdown")
                }
                Button {
                    note = ""
                    noting = true
                } label: {
                    Label("Wrong — add a note…", systemImage: "text.bubble")
                }
            }
            .alert("Why is it wrong?", isPresented: $noting) {
                TextField("e.g. off sick today", text: $note)
                Button("Send") { send(note) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The forecast said \(name) is heading to \(move.to). Your note is kept with the correction.")
            }
            .alert("Not sent", isPresented: Binding(get: { failed != nil }, set: { if !$0 { failed = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failed ?? "")
            }
            .accessibilityAction(named: "Say this is wrong") { send(nil) }
    }

    private func send(_ note: String?) {
        Task {
            if let reason = await FamilyForecastStore.shared.correct(move, note: note) { failed = reason }
        }
    }
}

extension View {
    func forecastCorrection(_ move: FamilyForecast.NextMove, name: String) -> some View {
        modifier(ForecastCorrectionMenu(move: move, name: name))
    }
}

/// Coming up, on the owner's phone: the next two days of diary events with a
/// location, each with who is going, what the time stands on and — on the
/// right — a countdown to leaving. A diary that could not be read says so —
/// an empty list would read as a free day.
///
/// A row is a proposal, and the reader can overrule it: tap to point it at
/// the right place (re-timed by Apple Maps) or to dismiss it as not a journey
/// being made. See `JourneyCorrections`.
struct FamilyUpcomingCard: View {
    let upcoming: FamilyForecast.Upcoming
    let names: [String: String]
    @ObservedObject private var corrections = JourneyCorrections.shared
    @State private var choosing: FamilyForecast.UpcomingItem?
    @State private var correcting: FamilyForecast.UpcomingItem?
    static let shown = 5

    /// Worth a card: something to travel to, or (all of it dismissed) a
    /// journey to put back. An empty diary — or one that could not be
    /// read — is no card.
    static func hasContent(_ upcoming: FamilyForecast.Upcoming) -> Bool {
        upcoming.available && !upcoming.items.isEmpty
    }

    var body: some View {
        let shown = corrections.apply(upcoming) ?? upcoming
        let dismissed = upcoming.items.filter { corrections.isDismissed($0.id) }
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "Coming up", trailing: "next two days").padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                if !shown.available {
                    note("Your calendar could not be read just now, so nothing is planned and no reminder is set. That is not the same as a free diary.")
                } else if shown.items.isEmpty {
                    note(dismissed.isEmpty
                         ? "Nothing with a location in the next two days."
                         : "Nothing left to travel to in the next two days.")
                } else {
                    ForEach(Array(shown.items.prefix(Self.shown).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Rectangle().fill(SR.divider).frame(height: 1).padding(.leading, SR.cardPadding) }
                        Button {
                            SRHaptic.tap()
                            choosing = item
                        } label: {
                            row(item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Change the destination or dismiss this journey")
                        .accessibilityIdentifier("family-upcoming-\(item.id)")
                    }
                }
                if !dismissed.isEmpty {
                    Rectangle().fill(SR.divider).frame(height: 1)
                    Button {
                        SRHaptic.tap()
                        for item in dismissed { corrections.restore(item.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11, weight: .semibold))
                            Text("\(dismissed.count) dismissed · put back")
                                .font(SR.Text.mono())
                        }
                        .foregroundStyle(SR.inkMuted)
                        .padding(.horizontal, SR.cardPadding)
                        .frame(maxWidth: .infinity, minHeight: SR.tapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("family-upcoming-restore")
                }
            }
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("family-upcoming")
        .confirmationDialog(
            choosing.map { "\($0.title) · \($0.place)" } ?? "",
            isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }),
            titleVisibility: .visible,
            presenting: choosing
        ) { item in
            Button("Change destination…") { correcting = item }
            if corrections.all[item.id]?.destination != nil {
                Button("Put back as planned") { corrections.restore(item.id) }
            }
            Button("Not going — dismiss this journey", role: .destructive) {
                SRHaptic.ok()
                withAnimation(.snappy) { corrections.dismiss(item.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Corrections stay on this iPhone and move its leave-by reminder.")
        }
        .sheet(item: $correcting) { item in
            JourneyDestinationSheet(item: item)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(SR.Text.secondary())
            .foregroundStyle(SR.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(SR.cardPadding)
    }

    private func row(_ item: FamilyForecast.UpcomingItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(ForecastWords.clock(item.start) ?? "")  \(item.title)")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    if item.travel?.source == "corrected" {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SR.accentInk)
                            .accessibilityLabel("Corrected destination")
                    }
                    Text("\(item.subjects.map { names[$0] ?? $0.capitalized }.joined(separator: ", ")) · \(item.place)\(item.from.map { " · from \($0)" } ?? "")")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                }
                if let line = ForecastWords.travelLine(item, names: names) {
                    Text(line).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let issue = item.issue {
                    Text(issue.text).font(SR.Text.mono()).foregroundStyle(SR.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let leave = item.leaveBy.flatMap(parseTimestamp) {
                LeaveCountdown(leaveBy: leave)
                    .fixedSize()
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI
import HealthKit

/// Navigation value for one person's walking page.
struct FamilyWalkingRef: Hashable {
    let subject: String
    /// Your own page also reads this phone's Health data.
    let isSelf: Bool
}

@MainActor
final class FamilyWalkingStore: ObservableObject {
    @Published private(set) var movement: FamilyMovement?
    @Published private(set) var loading = false
    @Published private(set) var failure: String?

    func load(subject: String, days: Int) async {
        loading = true
        defer { loading = false }
        let safe = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))) ?? subject
        do {
            movement = try await SiteClient.shared.send("api/native/family/movement?subject=\(safe)&days=\(days)")
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            switch error as? SiteError {
            case .status(403, _)?, .status(404, _)?: failure = "These figures are theirs, and their guardian's."
            case .status(_, let text)? where !text.isEmpty: failure = text
            default: failure = "The figures did not load. Pull to try again."
            }
        }
    }
}

/// How you walk, from this phone's Health data: the last 30 days against the
/// 30 before. Only ever your own — HealthKit on this phone is its owner's.
@MainActor
final class FamilyWalkingHealth: ObservableObject {
    struct Figure: Equatable {
        let value: Double
        let previous: Double?
    }

    @Published private(set) var speed: Figure?
    @Published private(set) var stepLength: Figure?
    @Published private(set) var dailyDistance: Figure?
    @Published private(set) var steadiness: Double?
    @Published private(set) var read = false

    private let store = HKHealthStore()

    private static let types: [HKQuantityTypeIdentifier] = [.walkingSpeed, .walkingStepLength, .distanceWalkingRunning, .appleWalkingSteadiness]

    func load(now: Date = Date()) async {
        guard HKHealthStore.isHealthDataAvailable() else { read = true; return }
        let toRead = Set(Self.types.compactMap { HKQuantityType.quantityType(forIdentifier: $0) as HKObjectType? })
        // Asks only for what was never asked; already answered, no sheet.
        try? await store.requestAuthorization(toShare: [], read: toRead)
        let day: TimeInterval = 86_400
        let recent = (now.addingTimeInterval(-30 * day), now)
        let before = (now.addingTimeInterval(-60 * day), now.addingTimeInterval(-30 * day))
        let mps = HKUnit.meter().unitDivided(by: .second())
        async let s1 = statistic(.walkingSpeed, .discreteAverage, unit: mps, recent)
        async let s0 = statistic(.walkingSpeed, .discreteAverage, unit: mps, before)
        async let l1 = statistic(.walkingStepLength, .discreteAverage, unit: .meterUnit(with: .centi), recent)
        async let l0 = statistic(.walkingStepLength, .discreteAverage, unit: .meterUnit(with: .centi), before)
        async let d1 = statistic(.distanceWalkingRunning, .cumulativeSum, unit: .meter(), recent)
        async let d0 = statistic(.distanceWalkingRunning, .cumulativeSum, unit: .meter(), before)
        let (v1, v0, w1, w0, x1, x0) = await (s1, s0, l1, l0, d1, d0)
        speed = v1.map { Figure(value: $0, previous: v0) }
        stepLength = w1.map { Figure(value: $0, previous: w0) }
        dailyDistance = x1.map { Figure(value: $0 / 30, previous: x0.map { $0 / 30 }) }
        steadiness = await latest(.appleWalkingSteadiness, unit: .percent())
        read = true
    }

    private func statistic(_ id: HKQuantityTypeIdentifier, _ options: HKStatisticsOptions, unit: HKUnit,
                           _ window: (Date, Date)) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: window.0, end: window.1)
        return await withCheckedContinuation { done in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, stats, _ in
                let quantity = options.contains(.cumulativeSum) ? stats?.sumQuantity() : stats?.averageQuantity()
                done.resume(returning: quantity?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { done in
            let newest = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            // Steadiness is measured every week or so; one older than four
            // months is not how they walk now.
            let recent = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-120 * 86_400), end: nil)
            let query = HKSampleQuery(sampleType: type, predicate: recent, limit: 1, sortDescriptors: [newest]) { _, samples, _ in
                done.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}

/// One person's walking, given back to them: their pace and whether it is
/// changing, the journeys they repeat with how long and how fast, how they
/// get about, and — on their own phone — how they walk.
struct FamilyWalkingScreen: View {
    let ref: FamilyWalkingRef
    @StateObject private var store = FamilyWalkingStore()
    @StateObject private var health = FamilyWalkingHealth()
    @EnvironmentObject private var router: Router
    @State private var days = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                Picker("Stretch", selection: $days) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("walking-days")

                if let m = store.movement {
                    paceCard(m)
                    journeys(m)
                    modes(m)
                } else if let failure = store.failure {
                    Text(failure)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .padding(.horizontal, 4)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                if ref.isSelf { healthCard }
                Button {
                    SRHaptic.tap()
                    router.push(FamilyMoveHistoryRef(subject: ref.subject), on: router.tab)
                } label: {
                    Label("Every trip, and when you head out", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .srButton(.regular)
                .accessibilityIdentifier("walking-history")
                Text("From your phone's location trail between named places, and — on your own phone — Apple Health. Speeds are inferred from GPS: a bus in traffic can read as a walk.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .navigationTitle(ref.isSelf ? "Your walking" : "\(store.movement?.name ?? "Their") walking")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: days) { await store.load(subject: ref.subject, days: days) }
        .task { if ref.isSelf && !SRDemo.isOn { await health.load() } }
        .srRefreshable { await store.load(subject: ref.subject, days: days) }
        .accessibilityIdentifier("family-walking")
    }

    // MARK: Pace

    private func paceCard(_ m: FamilyMovement) -> some View {
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR USUAL WALKING PACE").font(SR.Text.label()).tracking(1.2).foregroundStyle(SR.accent)
                if let pace = m.stats.walkingPace {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(WalkingWords.pace(mps: pace.medianMps))
                            .font(SR.Text.display(30))
                            .foregroundStyle(SR.ink)
                        Text("\(WalkingWords.speed(mps: pace.medianMps)) · \(WalkingWords.band(mps: pace.medianMps))")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    }
                    Text("The middle of \(pace.n) walks over 500 m. On a good day: \(WalkingWords.pace(mps: pace.p75Mps)).")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if pace.weekly.count > 1 { weekly(pace.weekly) }
                    if let trend = WalkingWords.trend(pace.weekly) {
                        Label(trend.text, systemImage: trend.quicker ? "arrow.up.right" : "arrow.down.right")
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(trend.quicker ? SR.good : SR.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("No walks long enough to time yet — anything over 500 m on foot counts.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("walking-pace")
    }

    /// One bar a week, taller for quicker: the pace in km/h, so up is better.
    private func weekly(_ weeks: [FamilyMovement.Pace.Week]) -> some View {
        let shown = Array(weeks.suffix(13))
        let top = max(shown.map(\.medianMps).max() ?? 1, 0.1)
        let floor = (shown.map(\.medianMps).min() ?? 0) * 0.8
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(shown, id: \.weekStart) { week in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(week.medianMps >= WalkingWords.briskMps ? SR.accent : SR.accent.opacity(0.45))
                    .frame(height: max(4, 46 * (week.medianMps - floor) / max(0.01, top - floor)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 46, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pace by week: " + shown.map { WalkingWords.speed(mps: $0.medianMps) }.joined(separator: ", "))
    }

    // MARK: Journeys

    @ViewBuilder
    private func journeys(_ m: FamilyMovement) -> some View {
        let (walked, other) = WalkingWords.ordered(m.stats.commonTrips)
        if !walked.isEmpty || !other.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SRSectionLabel(text: "Journeys you repeat", trailing: "last \(m.days) days").padding(.horizontal, 4)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array((walked + other).enumerated()), id: \.element.id) { index, trip in
                        if index > 0 { Rectangle().fill(SR.divider).frame(height: 1).padding(.leading, SR.cardPadding) }
                        tripRow(trip)
                    }
                }
                .srGlassCard(.paper)
                if let loops = m.stats.roundTrips, loops.count > 0 {
                    Text("And \(loops.count) out-and-back loop\(loops.count == 1 ? "" : "s"), usually \(WalkingWords.duration(loops.medianSeconds)).")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .padding(.horizontal, 4)
                }
            }
            .accessibilityIdentifier("walking-journeys")
        }
    }

    private func tripRow(_ trip: FamilyMovement.Trip) -> some View {
        let mode = WalkingWords.modes.first { $0.key == trip.mode }
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: mode?.symbol ?? "arrow.triangle.turn.up.right.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(trip.mode == "foot" ? SR.accent : SR.inkMuted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(trip.fromLabel) → \(trip.toLabel)").font(SR.Text.title()).foregroundStyle(SR.ink)
                Text(WalkingWords.tripLine(trip)).font(SR.Text.secondary()).foregroundStyle(SR.inkSecondary)
                Text(WalkingWords.tripWhen(trip)).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: How you get about

    @ViewBuilder
    private func modes(_ m: FamilyMovement) -> some View {
        let rows = WalkingWords.modes.compactMap { mode -> (title: String, symbol: String, totals: FamilyMovement.ModeTotals)? in
            guard let t = m.stats.byMode[mode.key], t.count > 0 else { return nil }
            return (mode.title, mode.symbol, t)
        }
        if !rows.isEmpty {
            let most = rows.map(\.totals.metres).max() ?? 1
            VStack(alignment: .leading, spacing: 10) {
                SRSectionLabel(text: "How you get about",
                               trailing: m.stats.byMode["foot"].map { WalkingWords.perWeek(metres: $0.metres, days: m.days) + " walked" })
                    .padding(.horizontal, 4)
                SRCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(rows, id: \.title) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label(row.title, systemImage: row.symbol).font(SR.Text.bodyMedium(15)).foregroundStyle(SR.ink)
                                    Spacer()
                                    Text("\(WalkingWords.distance(row.totals.metres)) · \(row.totals.count) trips")
                                        .font(SR.Text.mono()).foregroundStyle(SR.inkSecondary)
                                }
                                GeometryReader { geo in
                                    Capsule().fill(SR.accent.opacity(row.symbol == "figure.walk" ? 1 : 0.4))
                                        .frame(width: max(6, geo.size.width * row.totals.metres / max(1, most)))
                                }
                                .frame(height: 6)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .accessibilityIdentifier("walking-modes")
        }
    }

    // MARK: How you walk (this phone)

    @ViewBuilder
    private var healthCard: some View {
        if health.read, health.speed != nil || health.stepLength != nil || health.dailyDistance != nil || health.steadiness != nil {
            VStack(alignment: .leading, spacing: 10) {
                SRSectionLabel(text: "How you walk", trailing: "Apple Health · 30 days").padding(.horizontal, 4)
                SRCard {
                    VStack(alignment: .leading, spacing: 12) {
                        if let s = health.speed {
                            healthRow("Walking speed", WalkingWords.speed(mps: s.value), change: s.previous.map { (s.value - $0) * 3.6 }, unit: "km/h")
                        }
                        if let l = health.stepLength {
                            healthRow("Step length", "\(Int(l.value.rounded())) cm", change: l.previous.map { l.value - $0 }, unit: "cm")
                        }
                        if let d = health.dailyDistance {
                            healthRow("Walked a day", WalkingWords.distance(d.value), change: d.previous.map { (d.value - $0) / 1000 }, unit: "km")
                        }
                        if let steady = health.steadiness {
                            healthRow("Walking steadiness", "\(Int((steady * 100).rounded()))%", change: nil, unit: "")
                        }
                    }
                }
            }
            .accessibilityIdentifier("walking-health")
        }
    }

    private func healthRow(_ title: String, _ value: String, change: Double?, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(SR.Text.bodyMedium(15)).foregroundStyle(SR.ink)
            Spacer()
            Text(value).font(SR.Text.figure(18)).foregroundStyle(SR.ink)
            if let change, abs(change) >= 0.05 {
                Text(String(format: "%@%.1f %@", change > 0 ? "+" : "−", abs(change), unit))
                    .font(SR.Text.mono(12))
                    .foregroundStyle(change > 0 ? SR.good : SR.warn)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

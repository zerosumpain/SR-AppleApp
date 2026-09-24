import SwiftUI
import Charts

// MARK: - Tone

extension HubTone {
    /// What the server's verdict looks like. Words travel with every dot — a
    /// colour alone is not a reading anybody colour-blind can take.
    var color: Color {
        switch self {
        case .good: return SR.good
        case .watch: return SR.accent
        case .bad: return SR.error
        case .none: return SR.inkGhost
        }
    }
}

// MARK: - Heart rate, today

/// The last twenty-four hours of heart rate, as a line — the samples the tab
/// used to list eight at a time.
///
/// Sleep and workouts are shaded behind it because they are what explain its
/// shape: the trough is the night, the spike is the run. Without them a reader
/// has to remember when they slept to read their own chart.
struct HeartRateCard: View {
    let timeline: HeartTimeline

    private struct Span: Identifiable {
        let start: Date
        let end: Date
        let kind: String
        var id: String { "\(kind)-\(start.timeIntervalSince1970)" }
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private static func date(_ raw: String) -> Date? { iso.date(from: raw) ?? isoPlain.date(from: raw) }

    /// Sleep is UNIONED before it is drawn. Stages from two sources overlap, and
    /// stacking translucent bands darkens exactly the hours that were counted
    /// twice — which is the /health sleep bug again, in paint.
    private var spans: [Span] {
        let window = (Date(timeIntervalSince1970: TimeInterval(timeline.from)), Date(timeIntervalSince1970: TimeInterval(timeline.to)))
        func clip(_ s: Date, _ e: Date) -> (Date, Date)? {
            let a = max(s, window.0), b = min(e, window.1)
            return a < b ? (a, b) : nil
        }
        var sleep: [(Date, Date)] = timeline.sleep
            .filter { ($0.stage ?? "") != "awake" && ($0.stage ?? "") != "inBed" }
            .compactMap { s in Self.date(s.start).flatMap { a in Self.date(s.end).flatMap { clip(a, $0) } } }
            .sorted { $0.0 < $1.0 }
        var merged: [(Date, Date)] = []
        for s in sleep {
            if let last = merged.last, s.0 <= last.1.addingTimeInterval(20 * 60) {
                merged[merged.count - 1].1 = max(last.1, s.1)
            } else {
                merged.append(s)
            }
        }
        sleep = merged
        let workouts = timeline.workouts.compactMap { w in Self.date(w.start).flatMap { a in Self.date(w.end).flatMap { clip(a, $0) } } }
        return sleep.map { Span(start: $0.0, end: $0.1, kind: "Sleep") }
            + workouts.map { Span(start: $0.0, end: $0.1, kind: "Workout") }
    }

    var body: some View {
        let points = timeline.points
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HEART RATE")
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.inkMuted)
                    if let last = points.last {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(last.bpm))").font(SR.Text.figure(26)).foregroundStyle(SR.ink)
                            Text("bpm").font(SR.Text.mono(13)).foregroundStyle(SR.inkMuted)
                            Text(last.at.formatted(date: .omitted, time: .shortened))
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                        }
                    }
                }
                Spacer()
                if let low = points.map(\.bpm).min(), let high = points.map(\.bpm).max() {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("RANGE").font(SR.Text.label()).tracking(1.2).foregroundStyle(SR.inkMuted)
                        Text("\(Int(low))–\(Int(high))").font(SR.Text.mono(15)).foregroundStyle(SR.ink)
                    }
                }
            }

            if points.isEmpty {
                Text("No heart rate from this iPhone in the last day. It arrives with the next sync from Apple Health.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Chart {
                    ForEach(spans) { span in
                        RectangleMark(xStart: .value("From", span.start), xEnd: .value("To", span.end))
                            .foregroundStyle(span.kind == "Sleep" ? SR.accentInk.opacity(0.10) : SR.accent.opacity(0.12))
                    }
                    if let resting = timeline.restingHeartRate {
                        RuleMark(y: .value("Resting", resting.value))
                            .foregroundStyle(SR.inkMuted)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("resting \(Int(resting.value))")
                                    .font(SR.Text.mono(11))
                                    .foregroundStyle(SR.inkMuted)
                            }
                    }
                    ForEach(points) { p in
                        LineMark(x: .value("Time", p.at), y: .value("bpm", p.bpm))
                            .foregroundStyle(SR.accent)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                }
                // Fitted to the readings. The shaded bands have no y of their
                // own and pull an automatic domain down to zero, which spent
                // half the card on beats per minute nobody's heart reaches.
                .chartYScale(domain: yDomain(points))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisGridLine().foregroundStyle(SR.line)
                        AxisValueLabel(format: .dateTime.hour()).font(SR.mono(11)).foregroundStyle(SR.inkMuted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(SR.line)
                        AxisValueLabel().font(SR.mono(11)).foregroundStyle(SR.inkMuted)
                    }
                }
                .frame(height: 170)
                .accessibilityLabel("Heart rate over the last 24 hours")

                HStack(spacing: 14) {
                    legend(SR.accentInk.opacity(0.35), "Sleep")
                    legend(SR.accent.opacity(0.4), "Workout")
                    Spacer()
                    Text("15-min averages").font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                }
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
    }

    private func yDomain(_ points: [HeartTimeline.Point]) -> ClosedRange<Double> {
        var values = points.map(\.bpm)
        if let resting = timeline.restingHeartRate?.value { values.append(resting) }
        let low = (values.min() ?? 40) - 8
        let high = (values.max() ?? 160) + 8
        return max(0, low)...max(low + 20, high)
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
        }
    }
}

// MARK: - The read

/// The one-line read, readiness's four factors, and what the planner would
/// commission — /health's "State of play" minus the figures the hero already
/// shows.
struct HubReadCard: View {
    let hub: HubDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let lede = hub.lede, !lede.isEmpty {
                Text(lede)
                    .font(SR.Text.body(17))
                    .foregroundStyle(SR.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let readiness = hub.readiness, !readiness.factors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(readiness.factors) { factor in
                        FactorBar(factor: factor)
                    }
                }
            }
            if let planner = hub.planner {
                VStack(alignment: .leading, spacing: 3) {
                    Text("THE PLANNER WOULD COMMISSION")
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.inkMuted)
                    Text(planner.headline)
                        .font(SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                    if let detail = planner.detail {
                        Text(detail)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
    }
}

private struct FactorBar: View {
    let factor: HubDigest.Readiness.Factor

    var body: some View {
        HStack(spacing: 10) {
            Text(factor.label)
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkSecondary)
                .frame(width: 110, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.line)
                    Capsule().fill(SR.accent)
                        .frame(width: geo.size.width * CGFloat(min(max(factor.score, 0), 100) / 100))
                }
            }
            .frame(height: 6)
            Text("\(Int(factor.score.rounded()))")
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.ink)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(factor.label): \(Int(factor.score.rounded())) out of 100")
    }
}

// MARK: - Today's plan

struct HubPlanCard: View {
    let plan: HubDigest.Plan
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY · \(plan.sport.uppercased())")
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.accent)
                Spacer()
            }
            Text(plan.headline)
                .font(SR.Text.title(17))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !plan.evidence.isEmpty {
                SRTileGrid {
                    ForEach(plan.evidence) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.label.uppercased())
                                .font(SR.Text.label(11))
                                .tracking(1)
                                .foregroundStyle(SR.inkMuted)
                            Text(item.display)
                                .font(SR.Text.mono(15))
                                .foregroundStyle(SR.ink)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if !plan.why.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { open.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                        Text("Why").font(SR.Text.label()).tracking(1)
                    }
                    .foregroundStyle(SR.inkMuted)
                    .frame(minHeight: 30)
                }
                .buttonStyle(.plain)
                if open {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(plan.why, id: \.self) { line in
                            Text("•  \(line)")
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
    }
}

// MARK: - Rows

/// One tripwire: a state word, the signal, where it stands now.
struct TripwireRow: View {
    let tripwire: HubDigest.Tripwire
    var showsMeaning = true

    private var stateWord: String {
        switch tripwire.state {
        case "tripped": return "TRIPPED"
        case "close": return "CLOSE"
        case "clear": return "CLEAR"
        default: return "NO READ"
        }
    }

    private var stateColor: Color {
        switch tripwire.state {
        case "tripped": return SR.error
        case "close": return SR.accent
        case "clear": return SR.good
        default: return SR.inkGhost
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(stateWord)
                    .font(SR.Text.label(11))
                    .tracking(1)
                    .foregroundStyle(stateColor)
                    .frame(minWidth: 62, alignment: .leading)
                Text(tripwire.signal)
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                Spacer(minLength: 6)
                Text(tripwire.now)
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.ink)
            }
            Text("\(tripwire.window) · trips at \(tripwire.trigger)")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
            if showsMeaning, !tripwire.meaning.isEmpty {
                Text(tripwire.meaning)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A ranked move: the numeral, the move, what it buys and what it costs.
struct MoveRow: View {
    let move: HubDigest.Move

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(format: "%02d", move.rank))
                .font(SR.Text.mono(15))
                .foregroundStyle(SR.accent)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(move.title)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                labelled("Buys", move.buys)
                labelled("Costs", move.costs)
                Text(move.leverage)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func labelled(_ label: String, _ text: String) -> some View {
        (Text("\(label)  ").font(SR.Text.label(11)).foregroundColor(SR.inkMuted)
            + Text(text).font(SR.Text.secondary()).foregroundColor(SR.inkSecondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// An instrument, laid flat: figure, window, the reading and what it means.
struct InstrumentRow: View {
    let instrument: HubDigest.Instrument

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(instrument.tone.color).frame(width: 8, height: 8)
                Text(instrument.label)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                Spacer(minLength: 6)
                Text(instrument.window)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(instrument.display).font(SR.Text.figure(24)).foregroundStyle(SR.ink)
                if let unit = instrument.unit, instrument.display != "—" {
                    Text(unit).font(SR.Text.mono(13)).foregroundStyle(SR.inkMuted)
                }
            }
            Text(instrument.reading)
                .font(SR.Text.mono(13))
                .foregroundStyle(instrument.tone == .none ? SR.inkMuted : instrument.tone.color)
            Text(instrument.meaning)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Deeper screens

struct InstrumentsScreen: View {
    let hub: HubDigest

    var body: some View {
        List {
            Section {
                ForEach(hub.instruments) { InstrumentRow(instrument: $0).srGlassRow() }
            } footer: {
                Text("Each panel reads only the window it needs. A dash is no reading, not a zero.")
                    .font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.vital)
        .navigationTitle("Instruments")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TripwiresScreen: View {
    let hub: HubDigest

    var body: some View {
        List {
            Section {
                ForEach(hub.tripwires) { TripwireRow(tripwire: $0).srGlassRow() }
            } footer: {
                Text("A tripwire is a line agreed in advance. Tripped means it was crossed; close means within reach of it.")
                    .font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.vital)
        .navigationTitle("Tripwires")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MovesScreen: View {
    let hub: HubDigest

    var body: some View {
        List {
            Section {
                ForEach(hub.moves) { MoveRow(move: $0).srGlassRow() }
            } footer: {
                Text("Ranked by leverage: what each would buy for what it costs, over the numbers on this page.")
                    .font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.vital)
        .navigationTitle("Ranked moves")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ForecastScreen: View {
    let hub: HubDigest

    var body: some View {
        List {
            ForEach(hub.forecasts) { forecast in
                Section {
                    ForecastCard(forecast: forecast).srBareRow()
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text("A trend with its cone: the band widens because the future is less certain than the past, not because the line is wrong.")
                    .font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.vital)
        .navigationTitle("Forecast")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ForecastCard: View {
    let forecast: HubDigest.Forecast

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func date(_ raw: String) -> Date? { Self.day.date(from: String(raw.prefix(10))) }

    private struct Dated: Identifiable {
        let at: Date
        let value: Double
        let low: Double
        let high: Double
        var id: Date { at }
    }

    /// Parsed once, before the chart: a result builder is the wrong place to
    /// discover that a date did not parse.
    private var history: [Dated] {
        forecast.history.compactMap { p in date(p.date).map { Dated(at: $0, value: p.value, low: p.value, high: p.value) } }
    }
    private var yDomain: ClosedRange<Double> {
        let values = history.map(\.value) + cone.flatMap { [$0.low, $0.high] }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max((high - low) * 0.1, abs(high) * 0.02, 0.01)
        return (low - pad)...(high + pad)
    }

    private var cone: [Dated] {
        forecast.cone.compactMap { p in date(p.date).map { Dated(at: $0, value: p.value, low: p.low, high: p.high) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(forecast.label.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.inkMuted)
                Spacer()
                Text("\(forecast.horizonDays) days")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            Text(forecast.reading)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !forecast.history.isEmpty || !forecast.cone.isEmpty {
                Chart {
                    ForEach(cone) { p in
                        AreaMark(x: .value("Day", p.at), yStart: .value("Low", p.low), yEnd: .value("High", p.high))
                            .foregroundStyle(SR.accent.opacity(0.14))
                    }
                    ForEach(history) { p in
                        LineMark(x: .value("Day", p.at), y: .value(forecast.label, p.value), series: .value("Line", "Observed"))
                            .foregroundStyle(SR.ink)
                            .interpolationMethod(.monotone)
                    }
                    ForEach(cone) { p in
                        LineMark(x: .value("Day", p.at), y: .value(forecast.label, p.value), series: .value("Line", "Projected"))
                            .foregroundStyle(SR.accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
                    }
                }
                // Fitted, as on the heart chart: `.automatic(includesZero:
                // false)` still chose 0–10 for a night's sleep of 5 to 9 hours.
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(SR.line)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(SR.mono(11)).foregroundStyle(SR.inkMuted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(SR.line)
                        AxisValueLabel().font(SR.mono(11)).foregroundStyle(SR.inkMuted)
                    }
                }
                .frame(height: 150)
                .accessibilityLabel("\(forecast.label) forecast: \(forecast.reading)")
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
    }
}

struct ExperimentsScreen: View {
    let hub: HubDigest

    var body: some View {
        List {
            ForEach(hub.experiments) { experiment in
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(experiment.live ? "LIVE" : "QUEUED")
                                .font(SR.Text.label(11))
                                .tracking(1)
                                .foregroundStyle(experiment.live ? SR.accent : SR.inkMuted)
                            Spacer()
                            if let counter = experiment.counter {
                                Text(counter).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                            }
                        }
                        Text(experiment.title)
                            .font(SR.Text.title(17))
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        field("Change", experiment.change)
                        field("Hold constant", experiment.hold)
                        field("Measure", experiment.measure)
                        field("Stop when", experiment.stop)
                    }
                    .padding(.vertical, 6)
                    .srGlassRow()
                }
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.vital)
        .navigationTitle("Experiments")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(SR.Text.label(11)).tracking(1).foregroundStyle(SR.inkMuted)
            Text(text).font(SR.Text.secondary()).foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The verdict: the page's last word, and the one place a headline is set big.
struct VerdictScreen: View {
    let verdict: HubDigest.Verdict

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // An ARRAY OF LINES, as on the page: where it folds was decided.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(verdict.headline.enumerated()), id: \.offset) { _, line in
                        Text(line.uppercased())
                            .font(SR.Text.display(26))
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(Array(verdict.body.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(SR.Text.body(17))
                        .foregroundStyle(SR.ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let quote = verdict.quote {
                    HStack(alignment: .top, spacing: 12) {
                        Rectangle().fill(SR.accent).frame(width: 3)
                        Text(quote)
                            .font(SR.Text.body(17))
                            .italic()
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let review = verdict.reviewOn {
                    Text("REVIEW \(review)")
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.inkMuted)
                }
            }
            .padding(SR.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .srGround(.vital)
        .navigationTitle("The verdict")
        .navigationBarTitleDisplayMode(.inline)
    }
}

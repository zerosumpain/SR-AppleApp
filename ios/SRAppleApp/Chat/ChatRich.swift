import SwiftUI
import Charts

// MARK: - What a turn made
//
// The site reduces a turn's charts, tables and diagrams for the phone
// (`$lib/jkai/native-rich` in SR-Main): a Vega-Lite chart with one mark and an
// x and a y field arrives as the fields and the rows, and anything richer
// arrives as `simple: false` with its caption. So this file never reads
// Vega-Lite, and a chart it cannot draw faithfully says so and offers the web
// rather than drawing something close.

/// One cell of a chart or table row. The server sends strings, numbers and
/// nulls, and a table may also send a bool.
enum ChatCell: Decodable, Hashable {
    case text(String)
    case number(Double)
    case bool(Bool)
    case none

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .none }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let s = try? c.decode(String.self) { self = .text(s) }
        else { self = .none }
    }

    var number: Double? {
        switch self {
        case .number(let n): return n
        case .text(let s): return Double(s)
        default: return nil
        }
    }

    var display: String {
        switch self {
        case .text(let s): return s
        case .number(let n):
            return n.rounded() == n && abs(n) < 1e15 ? String(Int(n)) : n.formatted(.number.precision(.fractionLength(0...2)))
        case .bool(let b): return b ? "Yes" : "No"
        case .none: return "—"
        }
    }
}

struct ChartAxis: Decodable, Hashable {
    let field: String
    let title: String
    let type: String
}

struct TableColumn: Decodable, Hashable {
    let key: String
    let label: String
    let align: String
}

enum ChatArtifact: Decodable, Hashable {
    case chart(mark: String, x: ChartAxis, y: ChartAxis, color: String?, rows: [[String: ChatCell]], caption: String?)
    case table(columns: [TableColumn], rows: [[String: ChatCell]], totalRows: Int, caption: String?)
    /// A chart too rich to redraw here, or a diagram.
    case webOnly(kind: String, caption: String?)

    private enum Keys: String, CodingKey {
        case type, simple, mark, x, y, color, rows, caption, columns, totalRows
    }
    private struct ColorEnc: Decodable { let field: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decode(String.self, forKey: .type)
        let caption = try c.decodeIfPresent(String.self, forKey: .caption)
        switch type {
        case "chart" where (try c.decodeIfPresent(Bool.self, forKey: .simple)) == true:
            self = .chart(
                mark: try c.decode(String.self, forKey: .mark),
                x: try c.decode(ChartAxis.self, forKey: .x),
                y: try c.decode(ChartAxis.self, forKey: .y),
                color: try c.decodeIfPresent(ColorEnc.self, forKey: .color)?.field,
                rows: try c.decode([[String: ChatCell]].self, forKey: .rows),
                caption: caption
            )
        case "table":
            let rows = try c.decode([[String: ChatCell]].self, forKey: .rows)
            self = .table(
                columns: try c.decode([TableColumn].self, forKey: .columns),
                rows: rows,
                totalRows: try c.decodeIfPresent(Int.self, forKey: .totalRows) ?? rows.count,
                caption: caption
            )
        default:
            self = .webOnly(kind: type, caption: caption)
        }
    }
}

struct ChatSource: Decodable, Hashable, Identifiable {
    let kind: String
    let title: String
    let passage: String
    let url: String?
    let domain: String?

    var id: String { "\(kind)|\(title)|\(url ?? "")|\(passage.prefix(40))" }
}

// MARK: - Charts

/// A chart, drawn natively. The one piece of real colour in a transcript.
struct ChatChartView: View {
    let mark: String
    let x: ChartAxis
    let y: ChartAxis
    let color: String?
    let rows: [[String: ChatCell]]
    var height: CGFloat = 200

    private struct Point: Identifiable {
        let id: Int
        let label: String
        let date: Date?
        let value: Double?
        let y: Double
        let series: String
    }

    private static let isoDay: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
    private static let isoFull = ISO8601DateFormatter()

    private static func date(_ cell: ChatCell?) -> Date? {
        guard case .text(let s)? = cell else { return nil }
        return isoFull.date(from: s) ?? isoDay.date(from: String(s.prefix(10)))
    }

    private var points: [Point] {
        rows.enumerated().compactMap { index, row in
            guard let yv = row[y.field]?.number else { return nil }
            return Point(
                id: index,
                label: row[x.field]?.display ?? "",
                date: x.type == "temporal" ? Self.date(row[x.field]) : nil,
                value: x.type == "quantitative" ? row[x.field]?.number : nil,
                y: yv,
                series: color.flatMap { row[$0]?.display } ?? ""
            )
        }
    }

    private var seriesOrder: [String] {
        var seen: [String] = []
        for p in points where !seen.contains(p.series) { seen.append(p.series) }
        return seen
    }

    /// How x is plotted. A temporal field whose values do not parse as dates is
    /// drawn as labels rather than dropped.
    private enum XKind { case date, number, label }
    private var xKind: XKind {
        let pts = points
        if x.type == "temporal", !pts.isEmpty, pts.allSatisfy({ $0.date != nil }) { return .date }
        if x.type == "quantitative", !pts.isEmpty, pts.allSatisfy({ $0.value != nil }) { return .number }
        return .label
    }

    var body: some View {
        Group {
            switch xKind {
            case .date: Chart(points) { p in plot(p, x: PlottableValue.value(x.title, p.date!)) }
            case .number: Chart(points) { p in plot(p, x: PlottableValue.value(x.title, p.value!)) }
            case .label: Chart(points) { p in plot(p, x: PlottableValue.value(x.title, p.label)) }
            }
        }
        // Accent first, then ink: never accent against `--good`, which is the
        // pair colour-blind readers cannot separate. By position in the data,
        // so the first series is always the accent.
        .chartForegroundStyleScale(mapping: { (name: String) -> Color in
            let palette = [SR.accent, SR.ink, SR.inkMuted, SR.accentInk]
            let index = seriesOrder.firstIndex(of: name) ?? 0
            return palette[index % palette.count]
        })
        .chartLegend(color == nil ? .hidden : .visible)
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(SR.line)
                AxisValueLabel().font(SR.mono(11)).foregroundStyle(SR.inkMuted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(SR.line)
                AxisValueLabel().font(SR.mono(11)).foregroundStyle(SR.inkMuted)
            }
        }
        .frame(height: height)
        .accessibilityLabel("\(y.title) by \(x.title)")
    }

    @ChartContentBuilder
    private func plot<X: Plottable>(_ p: Point, x xValue: PlottableValue<X>) -> some ChartContent {
        let yValue = PlottableValue.value(y.title, p.y)
        let series = PlottableValue.value(color ?? "Series", p.series)
        switch mark {
        case "line":
            LineMark(x: xValue, y: yValue).foregroundStyle(by: series).interpolationMethod(.monotone)
        case "area":
            AreaMark(x: xValue, y: yValue).foregroundStyle(by: series)
        case "point":
            PointMark(x: xValue, y: yValue).foregroundStyle(by: series)
        default:
            BarMark(x: xValue, y: yValue).foregroundStyle(by: series)
        }
    }
}

// MARK: - Cards in the transcript

/// A chart, a table, or a pointer to the web — one quiet card each.
struct ArtifactCard: View {
    let artifact: ChatArtifact
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch artifact {
            case .chart(let mark, let x, let y, let color, let rows, let caption):
                captionLine(caption)
                ChatChartView(mark: mark, x: x, y: y, color: color, rows: rows)
                    .contentShape(Rectangle())
                    .onTapGesture { expanded = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens the chart full screen")
                    .sheet(isPresented: $expanded) {
                        ArtifactSheet(title: caption ?? "Chart") {
                            ChatChartView(mark: mark, x: x, y: y, color: color, rows: rows, height: 420)
                        }
                    }

            case .table(let columns, let rows, let totalRows, let caption):
                captionLine(caption)
                ChatTableView(columns: columns, rows: Array(rows.prefix(5)))
                if rows.count > 5 || totalRows > rows.count {
                    Button { expanded = true } label: {
                        Text("All \(totalRows) rows")
                            .font(SR.Text.label())
                            .tracking(1)
                            .foregroundStyle(SR.accent)
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $expanded) {
                        ArtifactSheet(title: caption ?? "Table") {
                            ChatTableView(columns: columns, rows: rows)
                            if totalRows > rows.count {
                                Text("The first \(rows.count) of \(totalRows) rows. The rest are on the web.")
                                    .font(SR.Text.secondary())
                                    .foregroundStyle(SR.inkMuted)
                            }
                        }
                    }
                }

            case .webOnly(let kind, let caption):
                HStack(spacing: 12) {
                    Image(systemName: kind == "diagram" ? "point.3.connected.trianglepath.dotted" : "chart.xyaxis.line")
                        .foregroundStyle(SR.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(caption ?? (kind == "diagram" ? "A diagram" : "A chart"))
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.ink)
                        Text(kind == "diagram" ? "Diagrams draw on the web." : "Too detailed to redraw here.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                    }
                    Spacer(minLength: 0)
                    Link(destination: SiteClient.shared.webURL("jkai")) {
                        Image(systemName: "safari").foregroundStyle(SR.accent)
                    }
                    .accessibilityLabel("Open on the web")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
    }

    @ViewBuilder
    private func captionLine(_ caption: String?) -> some View {
        if let caption, !caption.isEmpty {
            Text(caption)
                .font(SR.Text.bodyMedium(14))
                .foregroundStyle(SR.inkSecondary)
        }
    }
}

struct ChatTableView: View {
    let columns: [TableColumn]
    let rows: [[String: ChatCell]]

    var body: some View {
        // Scrolls sideways rather than squeezing: a ten-column table folded into
        // 350 points is a column of ellipses.
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(columns, id: \.key) { column in
                        Text(column.label.uppercased())
                            .font(SR.Text.label(11))
                            .tracking(1)
                            .foregroundStyle(SR.inkMuted)
                            .gridColumnAlignment(alignment(column))
                    }
                }
                Divider().overlay(SR.line)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(columns, id: \.key) { column in
                            Text(row[column.key]?.display ?? "—")
                                .font(column.align == "right" ? SR.Text.mono(13) : SR.Text.body(14))
                                .foregroundStyle(SR.ink)
                                .lineLimit(2)
                                .frame(maxWidth: 220, alignment: frameAlignment(column))
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func alignment(_ column: TableColumn) -> HorizontalAlignment {
        switch column.align { case "right": return .trailing; case "center": return .center; default: return .leading }
    }

    private func frameAlignment(_ column: TableColumn) -> Alignment {
        switch column.align { case "right": return .trailing; case "center": return .center; default: return .leading }
    }
}

/// A chart or table given the whole screen.
struct ArtifactSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(SR.gutter)
            }
            .srGround(.quiet)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Sources

/// "3 sources", under an answer. One line; the list is a tap away.
struct SourcesLine: View {
    let sources: [ChatSource]
    @State private var open = false

    var body: some View {
        Button {
            SRHaptic.tap()
            open = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "text.book.closed").font(.system(size: 11))
                Text(sources.count == 1 ? "1 source" : "\(sources.count) sources")
                    .font(SR.Text.label())
                    .tracking(1)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(SR.accent)
            .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) {
            NavigationStack {
                List(sources) { source in
                    SourceRow(source: source).srGlassRow()
                }
                .listStyle(.insetGrouped)
                .srGround(.quiet)
                .navigationTitle("Sources")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { open = false } }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct SourceRow: View {
    let source: ChatSource

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: source.kind == "research" ? "globe" : "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(SR.accent)
                Text(source.title)
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
            }
            if let domain = source.domain {
                Text(domain).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
            }
            if !source.passage.isEmpty {
                Text(source.passage)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)

        if let raw = source.url, let url = URL(string: raw) {
            Link(destination: url) { content }
        } else {
            content
        }
    }
}

// MARK: - Folded steps

/// "4 steps", folded. What ran is there for whoever wants it, and out of the
/// way of whoever wanted the answer.
struct FoldedSteps: View {
    let steps: [ToolStep]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(label)
                        .font(SR.Text.label())
                        .tracking(1)
                    if steps.contains(where: \.failed) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(SR.error)
                    }
                }
                .foregroundStyle(SR.inkMuted)
                .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Hide steps" : "Show \(label)")

            if open { ToolStepList(steps: steps) }
        }
    }

    private var label: String { steps.count == 1 ? "1 step" : "\(steps.count) steps" }
}

// MARK: - An empty thread

/// Four ways in, on a thread with nothing in it — the web's starter prompts,
/// same words, so the two surfaces teach the same things. One tap sends.
///
/// Rows of text, not tiles. The web shows them as a hero because a desk has a
/// screen to fill; a phone has the keyboard coming up under them.
struct StarterPrompts: View {
    let send: (String) -> Void

    static let prompts: [(label: String, icon: String, text: String)] = [
        ("Check the house", "house", "Give me a quick status of my home — is everything secure, and is anything off or needing attention?"),
        ("Today's health", "heart", "Summarise my health data for today — sleep, recovery and strain."),
        ("What's running?", "bolt", "What workflows and scheduled tasks do I have running right now?"),
        ("What can you do?", "sparkle", "What can you help me with? Give me a short tour of your capabilities."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SRLabel(text: "Start with")
                .padding(.bottom, 6)
            ForEach(Self.prompts, id: \.label) { prompt in
                Button {
                    SRHaptic.tap()
                    send(prompt.text)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: prompt.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(SR.accent)
                            .frame(width: 22)
                        Text(prompt.label)
                            .font(SR.Text.body())
                            .foregroundStyle(SR.ink)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SR.inkMuted)
                    }
                    .frame(minHeight: SR.tapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(prompt.text)
            }
        }
        .padding(.top, 24)
    }
}

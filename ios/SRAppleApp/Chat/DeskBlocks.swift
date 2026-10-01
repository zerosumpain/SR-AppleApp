import SwiftUI
import Charts

// MARK: - The desk's blocks, drawn natively
//
// One view per block type in `DeskModels.swift`, in the desk's register: mono
// labels, Archivo Black figures and card titles, DM Sans reading copy, petrol
// for "up" and the accent for "down" (the /health/analytics convention — a
// direction is not a verdict, so never good/error). The desk's 12-column grid
// collapses to one column at this width, exactly as the web desk does under
// 440 points, so `span` is read and ignored.

/// What a block's buttons do. Set once by the drawer; a block never reaches
/// for the composer itself.
struct DeskActions {
    /// Hand a prompt to the composer. Never sends.
    var ask: (String) -> Void = { _ in }
    /// Open an `href` from a page.
    var open: (String) -> Void = { _ in }
}

private struct DeskActionsKey: EnvironmentKey {
    static let defaultValue = DeskActions()
}

extension EnvironmentValues {
    var deskActions: DeskActions {
        get { self[DeskActionsKey.self] }
        set { self[DeskActionsKey.self] = newValue }
    }
}

/// The desk's palette, named for what it means rather than for its hue.
enum DeskInk {
    /// `--card`: a block lifted off the desk's surface.
    static let card = Color(hex: 0xF3EBDD)
    /// `up` — petrol. `--accent-ink`.
    static let up = SR.accentInk
    /// `down` — the accent.
    static let down = SR.accent

    static func direction(_ value: String?) -> Color {
        switch value {
        case "up": return up
        case "down": return down
        default: return SR.inkMuted
        }
    }

    static func tone(_ value: String?) -> Color? {
        switch value {
        case "good": return SR.good
        case "warn": return SR.warn
        case "bad": return SR.error
        case "accent": return SR.accent
        default: return nil
        }
    }
}

/// One block, with its card when it has one.
struct DeskBlockView: View {
    let block: PanelBlock
    @Environment(\.deskActions) private var actions

    var body: some View {
        if block.isCard {
            VStack(alignment: .leading, spacing: 10) {
                header
                DeskBlockBody(block: block)
                footer
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DeskInk.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(SR.line, lineWidth: 0.75))
            .accessibilityElement(children: .contain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                DeskBlockBody(block: block)
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var header: some View {
        if block.title != nil || block.note != nil || block.href != nil {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let title = block.title {
                    Text(title.uppercased())
                        .font(SR.Text.display(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 4)
                if let note = block.note {
                    Text(note)
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkMuted)
                        .multilineTextAlignment(.trailing)
                }
                if let href = block.href {
                    Button { actions.open(href) } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SR.accent)
                            .frame(minWidth: 28, minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(block.title ?? "this")")
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let foot = block.foot {
            Text(foot)
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let ask = block.ask {
            DeskAskButton(ask: ask)
        }
        if let source = block.source {
            Text(source)
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.inkGhost)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The body of a block, by type. Split from the envelope so a group can draw
/// its children the same way.
struct DeskBlockBody: View {
    let block: PanelBlock

    var body: some View {
        switch block.content {
        case .figures(let items):
            DeskFigures(items: items)
        case .series(let series, let unit, let zero):
            DeskSeriesChart(series: series, unit: unit, zero: zero)
        case .bars(let rows):
            DeskBars(rows: rows)
        case .heat(let columns, let rows, _):
            DeskHeat(columns: columns, rows: rows)
        case .rows(let rows, let numbered, let empty):
            DeskRows(rows: rows, numbered: numbered, empty: empty)
        case .table(let columns, let rows, let pick):
            DeskTable(columns: columns, rows: rows, pick: pick)
        case .timeline(let events):
            DeskTimeline(events: events)
        case .kv(let items):
            DeskKV(items: items)
        case .prose(let markdown, let tone):
            DeskProse(markdown: markdown, tone: tone)
        case .entity(let name, let kind, let summary):
            DeskEntity(name: name, kind: kind, summary: summary)
        case .actions(let items):
            DeskActionRow(items: items)
        case .group(let blocks):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(blocks) { DeskBlockView(block: $0) }
            }
        case .unknown:
            EmptyView()
        }
    }
}

// MARK: - Figures

struct DeskFigures: View {
    let items: [PanelFigure]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                DeskFigureCell(item: item)
            }
        }
    }
}

struct DeskFigureCell: View {
    let item: PanelFigure

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.label.uppercased())
                .font(SR.Text.label(12))
                .tracking(0.8)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(item.value)
                    .font(SR.Text.figure(22))
                    .foregroundStyle(DeskInk.tone(item.tone) ?? SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = item.unit {
                    Text(unit)
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkMuted)
                }
            }
            if let delta = item.delta {
                Text(delta)
                    .font(SR.Text.label(12))
                    .foregroundStyle(DeskInk.direction(item.direction))
                    .lineLimit(2)
            }
            if item.spark.count > 1 {
                DeskSpark(values: item.spark, color: item.direction == "down" ? DeskInk.down : DeskInk.up)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(DeskInk.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SR.line, lineWidth: 0.75))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.label, item.value + (item.unit.map { " \($0)" } ?? ""), item.delta].compactMap { $0 }.joined(separator: ", "))
    }
}

/// A figure's sparkline: the line and a dot on the latest reading.
struct DeskSpark: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("Reading", index), y: .value("Value", value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .foregroundStyle(color)
            }
            if let last = values.last {
                PointMark(x: .value("Reading", values.count - 1), y: .value("Value", last))
                    .symbolSize(18)
                    .foregroundStyle(color)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 24)
        .accessibilityHidden(true)
    }
}

// MARK: - Series

struct DeskSeriesChart: View {
    let series: [PanelSeries]
    let unit: String?
    let zero: Bool

    private struct Point: Identifiable {
        let id: Int
        let series: Int
        let name: String
        let x: String
        let y: Double
    }

    private static let palette: [Color] = [SR.accent, SR.accentInk, SR.inkMuted]

    private var points: [Point] {
        var out: [Point] = []
        for (s, line) in series.enumerated() {
            for point in line.points {
                out.append(Point(id: out.count, series: s, name: line.label, x: point.x, y: point.y))
            }
        }
        return out
    }

    /// Every category, in first-seen order, thinned to about five ticks.
    private var ticks: [String] {
        var seen: [String] = []
        for p in points where !seen.contains(p.x) { seen.append(p.x) }
        guard seen.count > 5 else { return seen }
        let step = Int((Double(seen.count) / 4).rounded(.up))
        var out = stride(from: 0, to: seen.count, by: step).map { seen[$0] }
        if let last = seen.last, out.last != last { out.append(last) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chart
            if series.count > 1 { legend }
        }
    }

    private var chart: some View {
        let all = points
        let first = all.filter { $0.series == 0 }
        return Chart {
            if zero {
                ForEach(first) { p in
                    AreaMark(x: .value("x", p.x), y: .value(unit ?? "Value", p.y))
                        .foregroundStyle(SR.accent.opacity(0.14))
                        .interpolationMethod(.monotone)
                }
            }
            ForEach(all) { p in
                LineMark(x: .value("x", p.x), y: .value(unit ?? "Value", p.y), series: .value("Series", p.name))
                    .foregroundStyle(Self.palette[p.series % Self.palette.count])
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: .automatic(includesZero: zero))
        .chartXAxis {
            AxisMarks(values: ticks) { _ in
                AxisValueLabel().font(SR.Text.mono(12)).foregroundStyle(SR.inkMuted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(SR.divider)
                AxisValueLabel().font(SR.Text.mono(12)).foregroundStyle(SR.inkMuted)
            }
        }
        .chartLegend(.hidden)
        .frame(height: 150)
        .accessibilityLabel(series.map(\.label).joined(separator: ", ") + (unit.map { ", \($0)" } ?? ""))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(Array(series.enumerated()), id: \.offset) { index, line in
                HStack(spacing: 6) {
                    Capsule()
                        .fill(Self.palette[index % Self.palette.count])
                        .frame(width: 14, height: 3)
                    Text(line.label)
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkSecondary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Bars

struct DeskBars: View {
    let rows: [PanelBar]
    @Environment(\.deskActions) private var actions

    var body: some View {
        let top = max(rows.map(\.value).max() ?? 1, 0.000_1)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let content = VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label)
                            .font(row.highlight ? SR.Text.bodyMedium(14) : SR.Text.body(14))
                            .foregroundStyle(SR.ink)
                        Spacer(minLength: 8)
                        Text(row.display ?? PanelCell.format(row.value))
                            .font(SR.Text.mono(12))
                            .foregroundStyle(row.highlight ? SR.accent : SR.inkMuted)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(SR.divider)
                            Capsule()
                                .fill(row.highlight ? SR.accent : SR.ink.opacity(0.42))
                                .frame(width: max(4, geo.size.width * CGFloat(row.value / top)))
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.label), \(row.display ?? PanelCell.format(row.value))")

                if let href = row.href {
                    Button { actions.open(href) } label: { content.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                } else {
                    content
                }
            }
        }
    }
}

// MARK: - Heat

struct DeskHeat: View {
    let columns: [String]
    let rows: [PanelHeatRow]

    var body: some View {
        let values = rows.flatMap { $0.values.compactMap { $0 } }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    Text("")
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        Text(column)
                            .font(SR.Text.mono(12))
                            .foregroundStyle(SR.inkMuted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.label)
                            .font(SR.Text.mono(12))
                            .foregroundStyle(SR.inkSecondary)
                            .lineLimit(1)
                            .fixedSize()
                        ForEach(0..<columns.count, id: \.self) { index in
                            let value = index < row.values.count ? row.values[index] : nil
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(fill(value, low: low, high: high))
                                .frame(minWidth: 24, minHeight: 20)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Heat map, \(rows.count) rows by \(columns.count) columns")
    }

    private func fill(_ value: Double?, low: Double, high: Double) -> Color {
        guard let value else { return SR.divider }
        let share = high > low ? (value - low) / (high - low) : 0.5
        return SR.accent.opacity(0.12 + 0.78 * share)
    }
}

// MARK: - Rows

struct DeskRows: View {
    let rows: [PanelRow]
    let numbered: Bool
    let empty: String?
    @Environment(\.deskActions) private var actions

    var body: some View {
        if rows.isEmpty {
            Text(empty ?? "Nothing here.")
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkMuted)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    if let ask = row.ask {
                        Button { actions.ask(ask.detail) } label: { line(row, index: index) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Puts a question in the composer")
                    } else if let href = row.href {
                        Button { actions.open(href) } label: { line(row, index: index) }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(.isLink)
                    } else {
                        line(row, index: index)
                    }
                }
            }
        }
    }

    private func line(_ row: PanelRow, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if numbered {
                Text("\(index + 1)")
                    .font(SR.Text.display(15))
                    .foregroundStyle(SR.accent)
                    .frame(minWidth: 18, alignment: .leading)
            } else if let tone = DeskInk.tone(row.tone) {
                Circle().fill(tone).frame(width: 7, height: 7).padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = row.sub {
                    Text(sub)
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(SR.inkMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if let meta = row.meta {
                Text(meta)
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkMuted)
                    .multilineTextAlignment(.trailing)
            }
            if row.href != nil || row.ask != nil {
                Image(systemName: row.ask != nil ? "text.bubble" : (row.external ? "arrow.up.right" : "chevron.right"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SR.inkGhost)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 9)
        .frame(minHeight: SR.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Table

struct DeskTable: View {
    let columns: [String]
    let rows: [[PanelCell]]
    let pick: Int?

    /// A phone draws the first sixty. The rest are on the web desk.
    private static let cap = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                            Text(column.uppercased())
                                .font(SR.Text.label(12))
                                .tracking(0.8)
                                .foregroundStyle(index == pick ? DeskInk.up : SR.inkMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxHeight: .infinity, alignment: .leading)
                                .background(index == pick ? DeskInk.up.opacity(0.12) : Color.clear)
                        }
                    }
                    Divider().overlay(SR.line)
                    ForEach(Array(rows.prefix(Self.cap).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(0..<columns.count, id: \.self) { index in
                                let cell = index < row.count ? row[index] : PanelCell.none
                                Text(cell.display)
                                    .font(isNumber(cell) ? SR.Text.mono(13) : SR.Text.body(14))
                                    .fontWeight(index == pick ? .semibold : .regular)
                                    .foregroundStyle(index == pick ? DeskInk.up : SR.ink)
                                    .lineLimit(3)
                                    .frame(maxWidth: 220, maxHeight: .infinity, alignment: isNumber(cell) ? .trailing : .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 7)
                                    .background(index == pick ? DeskInk.up.opacity(0.12) : Color.clear)
                            }
                        }
                        Divider().overlay(SR.divider)
                    }
                }
            }
            if rows.count > Self.cap {
                Text("The first \(Self.cap) of \(rows.count) rows. The rest are on the web.")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
            }
        }
    }

    private func isNumber(_ cell: PanelCell) -> Bool {
        if case .number = cell { return true }
        return false
    }
}

// MARK: - Timeline

struct DeskTimeline: View {
    let events: [PanelEvent]
    @Environment(\.deskActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                let row = HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(event.hot ? SR.accent : SR.paper)
                            .overlay(Rectangle().strokeBorder(event.hot ? SR.accent : SR.ink, lineWidth: 1))
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        if index < events.count - 1 {
                            Rectangle().fill(SR.line).frame(width: 1).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 8)
                    Text(event.when)
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkMuted)
                        .frame(minWidth: 52, alignment: .leading)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.what)
                            .font(SR.Text.body(15))
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let sub = event.sub {
                            Text(sub)
                                .font(SR.Text.secondary(13))
                                .foregroundStyle(SR.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.bottom, 10)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                if let href = event.href {
                    Button { actions.open(href) } label: { row.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                } else {
                    row
                }
            }
        }
    }
}

// MARK: - Key / value

struct DeskKV: View {
    let items: [PanelKV]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                GridRow {
                    Text(item.label.uppercased())
                        .font(SR.Text.label(12))
                        .tracking(0.8)
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.value)
                        .font(SR.Text.mono(13))
                        .foregroundStyle(DeskInk.tone(item.tone) ?? SR.ink)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Prose, entity, actions

struct DeskProse: View {
    let markdown: String
    let tone: String?

    var body: some View {
        if let color = DeskInk.tone(tone) {
            MarkdownText(raw: markdown)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 2) }
        } else {
            MarkdownText(raw: markdown)
        }
    }
}

struct DeskEntity: View {
    let name: String
    let kind: String?
    let summary: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 14))
                .foregroundStyle(SR.accent)
                .frame(width: 30, height: 30)
                .background(SR.accent.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                if let kind {
                    Text(kind.uppercased())
                        .font(SR.Text.label(12))
                        .tracking(0.8)
                        .foregroundStyle(SR.inkMuted)
                }
                Text(name)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                if let summary {
                    Text(summary)
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct DeskActionRow: View {
    let items: [PanelAction]
    @Environment(\.deskActions) private var actions

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    SRHaptic.tap()
                    if item.kind == "ask", let ask = item.ask {
                        actions.ask(ask.detail)
                    } else if let href = item.href {
                        actions.open(href)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.kind == "ask" ? "text.bubble" : "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.label.uppercased())
                            .font(SR.Text.label(12))
                            .tracking(0.8)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(index == 0 ? SR.paper : SR.ink)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: SR.tapTarget, alignment: .leading)
                    .background(index == 0 ? SR.ink : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(index == 0 ? SR.ink : SR.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(item.kind == "ask" ? "Puts a question in the composer" : "Opens a link")
                .accessibilityIdentifier("desk-action-\(item.id)")
            }
        }
    }
}

/// A block's own `ask`: a quiet line under the card.
struct DeskAskButton: View {
    let ask: PanelAsk
    @Environment(\.deskActions) private var actions

    var body: some View {
        Button {
            SRHaptic.tap()
            actions.ask(ask.detail)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble").font(.system(size: 11, weight: .semibold))
                Text(ask.label.uppercased())
                    .font(SR.Text.label(12))
                    .tracking(0.8)
            }
            .foregroundStyle(SR.accent)
            .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Puts a question in the composer")
    }
}

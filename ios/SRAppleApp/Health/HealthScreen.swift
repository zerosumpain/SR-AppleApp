import SwiftUI
import MapKit

/// The health tab.
///
/// /health has nine sections and is read top to bottom at a desk. A phone is
/// opened for one question — "how am I doing" — so the order here is the
/// answer, then the evidence, then everything else: readiness, four figures,
/// the week, the records, and then the things only this app knows, which are
/// what the phone uploaded and where the family is.
struct HealthScreen: View {
    @ObservedObject var companion: Companion
    @StateObject private var store = HealthStore()
    @EnvironmentObject private var router: Router

    var body: some View {
        List {
            if let summary = store.summary {
                if summary.isMock { mockNotice }
                readiness(summary)
                figures(summary)
                if let week = summary.week { weekSection(week) }
                if !summary.records.isEmpty { records(summary.records) }
            } else if store.unavailable {
                SREmpty(
                    title: "Health is not answering",
                    icon: "heart.slash",
                    message: "The health service did not reply. Your uploaded records are still here.",
                    action: (label: "Try again", run: { Task { await store.load(fresh: true) } })
                )
                .srPlainRow()
            } else if store.loading {
                HStack { Spacer(); ProgressView().tint(SR.accent); Spacer() }
                    .srPlainRow().padding(.vertical, 40)
            }

            uploaded
            family
        }
        .listStyle(.plain)
        .srPaper()
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await store.load(fresh: true)
            try? await companion.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.openSettings(.health) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Health settings")
            }
        }
        .navigationDestination(for: HealthFigure.self) { FigureDetail(figure: $0) }
        .task { await store.load() }
    }

    // MARK: - Sections

    private var mockNotice: some View {
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 6) {
                SRSectionLabel(text: "Demonstration data")
                Text("No real measurement landed in this window, so these figures are synthetic. They are not you.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .srPlainRow()
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func readiness(_ summary: HealthSummary) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                if let readiness = summary.readiness {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(Int(readiness.score.rounded()))")
                            .font(SR.Text.hero(52))
                            .foregroundStyle(SR.ink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(readiness.label.uppercased())
                                .font(SR.Text.label())
                                .tracking(1.4)
                                .foregroundStyle(SR.accent)
                            Text("Readiness")
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                        }
                    }
                    Text(readiness.recommendation)
                        .font(SR.Text.body(15))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(summary.strap)
                        .font(SR.Text.body(15))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 8)
            .srPlainRow()
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func figures(_ summary: HealthSummary) -> some View {
        Section {
            SRTileGrid {
                ForEach(summary.figures) { figure in
                    NavigationLink(value: figure) {
                        FigureTile(figure: figure)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 6)
            .srPlainRow()
            .listRowSeparator(.hidden)
        } header: {
            SRSectionLabel(text: "Today", trailing: shortAgo(summary.generatedAt))
                .srPlainRow()
                .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func weekSection(_ week: HealthWeek) -> some View {
        Section {
            SRTileGrid {
                SRStatTile(value: "\(week.activities)", label: "Activities", caption: "7 days")
                SRStatTile(value: distance(week.distanceKm), unit: "km", label: "Distance", caption: "7 days")
                SRStatTile(value: duration(week.durationMinutes), label: "Moving", caption: "7 days")
                SRStatTile(value: "\(week.elevationM)", unit: "m", label: "Climbed", caption: "7 days")
            }
            .padding(.bottom, 6)
            .srPlainRow()
            .listRowSeparator(.hidden)
        } header: {
            SRSectionLabel(text: "This week").srPlainRow().padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func records(_ records: [HealthRecordHighlight]) -> some View {
        Section {
            ForEach(records) { record in
                SRRow(title: record.label, subtitle: record.date) {
                    Text(record.display)
                        .font(SR.Text.mono(14))
                        .foregroundStyle(SR.ink)
                }
                .srPlainRow()
            }
        } header: {
            SRSectionLabel(text: "Personal records").srPlainRow().padding(.vertical, 6)
        }
    }

    /// What this phone has sent up. Only the last few — the website holds the
    /// archive and a phone scrolling a thousand rows is not reading any of them.
    @ViewBuilder
    private var uploaded: some View {
        Section {
            if companion.records.isEmpty {
                Text(companion.paired
                     ? "Nothing uploaded yet. Choose categories under Settings → Apple Health."
                     : "Connect the companion to upload from Apple Health.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .srPlainRow()
                    .padding(.vertical, 10)
            } else {
                ForEach(companion.records.prefix(8)) { record in
                    SRRow(
                        title: HealthCollector.labels[record.kind] ?? record.kind,
                        subtitle: "\(record.source) · \(shortAgo(record.start))"
                    ) {
                        if let value = record.value {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(value.formatted())
                                    .font(SR.Text.mono(15))
                                    .foregroundStyle(SR.ink)
                                if let unit = record.unit {
                                    Text(unit).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                                }
                            }
                        }
                    }
                    .srPlainRow()
                }
            }
        } header: {
            SRSectionLabel(text: "From this iPhone", trailing: companion.queueCount > 0 ? "\(companion.queueCount) waiting" : nil)
                .srPlainRow()
                .padding(.vertical, 6)
        } footer: {
            Text("Only you can see these. Heart rate is not a live feed, and sleep records can overlap between sources.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .srPlainRow()
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var family: some View {
        if !companion.family.isEmpty {
            Section {
                ForEach(companion.family) { member in
                    FamilyRow(member: member).srPlainRow()
                }
            } header: {
                SRSectionLabel(text: "Family").srPlainRow().padding(.vertical, 6)
            } footer: {
                Text("Family members see a location you chose to share, and nothing else.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .srPlainRow()
                    .padding(.vertical, 8)
            }
        }
    }

    private func distance(_ km: Double) -> String {
        km >= 100 ? "\(Int(km.rounded()))" : String(format: "%.1f", km)
    }

    private func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// A figure, as a tappable tile with its movement.
struct FigureTile: View {
    let figure: HealthFigure

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(figure.label.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)

            Text(figure.displayWithUnit)
                .font(SR.Text.figure(30))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: 5) {
                if let delta = figure.deltaDisplay {
                    Image(systemName: figure.direction == "down" ? "arrow.down.right" : "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(delta).font(SR.Text.mono())
                } else {
                    Text(figure.caption).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                }
            }
            .foregroundStyle(tone)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SR.cardPadding)
        .frame(minHeight: 104, alignment: .topLeading)
        .background(SR.surface)
        .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(figure.label): \(figure.displayWithUnit)"
            + (figure.deltaDisplay.map { ", \($0) \(figure.caption)" } ?? ", \(figure.caption)")
            + (figure.improving == nil ? "" : figure.improving! ? ", improving" : ", worse")
        )
    }

    /// The accent's counterpart, not the accent. Colour here means "the number
    /// moved in the good direction for THIS metric", which is not the same
    /// question as "this is the important thing on the screen".
    private var tone: Color {
        guard let improving = figure.improving else { return SR.inkGhost }
        return improving ? SR.good : SR.accent
    }
}

/// One figure, thirty days of it.
struct FigureDetail: View {
    let figure: HealthFigure

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(figure.displayWithUnit)
                        .font(SR.Text.hero(48))
                        .foregroundStyle(SR.ink)
                    Text(figure.caption)
                        .font(SR.Text.mono())
                        .tracking(1.1)
                        .foregroundStyle(SR.inkMuted)
                    if let delta = figure.deltaDisplay {
                        Text(delta + (figure.improving == true ? " — the good direction" : ""))
                            .font(SR.Text.secondary())
                            .foregroundStyle(figure.improving == true ? SR.good : SR.accent)
                    }
                }

                if let series = figure.series, series.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        SRSectionLabel(text: "Last \(series.count) days", trailing: range(series))
                        SRSparkline(values: series)
                            .frame(height: 120)
                    }
                } else {
                    Text("No history for this figure yet.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }

                Text("Measured and derived on the website. The phone shows what /health computed; it does not recompute anything.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .srPaper()
        .navigationTitle(figure.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func range(_ series: [Double]) -> String {
        guard let low = series.min(), let high = series.max() else { return "" }
        return "\(Int(low.rounded()))–\(Int(high.rounded()))"
    }
}

/// A line, and the band it moves in. No axes, no grid.
///
/// A sparkline is read for its SHAPE; a chart small enough to sit under a
/// figure has no room for the furniture that would let it be read for its
/// values, and half-drawn furniture invites exactly the precision it cannot
/// support. The low and the high are printed as text above it instead.
struct SRSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let low = values.min() ?? 0
            let high = values.max() ?? 1
            // A flat series has zero span, and dividing by it puts every point
            // at NaN — which draws nothing at all, silently.
            let span = max(high - low, 0.0001)
            let step = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : 0

            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) * step,
                    y: geo.size.height - CGFloat((value - low) / span) * geo.size.height
                )
            }

            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    for point in points { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(SR.accent.opacity(0.12))

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(SR.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let last = points.last {
                    Circle()
                        .fill(SR.accentInk)
                        .frame(width: 7, height: 7)
                        .position(last)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trend over \(values.count) days")
    }
}

/// One family member's latest position.
struct FamilyRow: View {
    let member: FamilyMember

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(member.name).font(SR.Text.title()).foregroundStyle(SR.ink)
                Spacer(minLength: 6)
                if let point = member.location {
                    let stale = (parseTimestamp(point.recorded)?.timeIntervalSinceNow ?? -.infinity) < -1200
                    // The glyph carries the hue; the word carries the meaning.
                    // `--warn` measures 2.58:1 on cream and cannot hold 12pt
                    // copy on its own — a second encoding is what makes the
                    // colour legal here rather than decorative.
                    HStack(spacing: 4) {
                        Image(systemName: stale ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(stale ? SR.warn : SR.good)
                        Text(stale ? "STALE" : "LATEST")
                            .font(SR.Text.mono())
                            .tracking(1)
                            .foregroundStyle(SR.inkSecondary)
                    }
                }
            }
            if let point = member.location {
                Text("±\(Int(point.accuracy)) m · \(point.moving ? "Moving" : "Stationary") · \(shortAgo(point.recorded))")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                Button {
                    SRHaptic.tap()
                    MKMapItem(placemark: MKPlacemark(
                        coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                    )).openInMaps()
                } label: {
                    Label("Open in Maps", systemImage: "map")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.accent)
                }
                .buttonStyle(.plain)
                .frame(minHeight: SR.tapTarget, alignment: .leading)
            } else {
                Text(member.sharing ? "Waiting for a location" : "Location sharing paused")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(.vertical, 8)
    }
}

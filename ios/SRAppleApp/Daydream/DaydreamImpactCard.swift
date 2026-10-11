import SwiftUI
import Charts

/// Whether the notes are worth having — the score the loop learns from.
///
/// The share you called worth knowing over the last 28 days, how that moved
/// against the 28 before, how much of what it wrote got an answer, and what
/// came of the answers. Under it, twelve weeks of answers as stacked bars:
/// worth knowing in ink blue, not for me in orange, not answered pale.
/// The site's `/jkai/daydreams/impact` has the full picture.
struct DaydreamImpactCard: View {
    let impact: DaydreamImpact
    @Environment(\.openURL) private var openURL

    var body: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("IMPACT")
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(SR.accent)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Text("LAST \(impact.windowDays) DAYS")
                        .font(SR.Text.mono())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                }

                headline
                facts

                if !segments.isEmpty {
                    chart
                    legend
                }

                Button {
                    SRHaptic.tap()
                    openURL(SiteClient.shared.webURL("/jkai/daydreams/impact"))
                } label: {
                    SRButtonLabel(title: "Full picture on the site", icon: "safari")
                }
                .srButton()
                .accessibilityIdentifier("daydream-impact-site")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daydream-impact")
    }

    // MARK: - Figures

    private var headline: some View {
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Worth knowing")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                Text(impact.hitRateText ?? "—")
                    .font(SR.Text.figure(36))
                    .foregroundStyle(SR.accentInk)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Worth knowing, \(impact.hitRateText ?? "not enough answers yet")")
            if let delta = impact.deltaPoints {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if delta != 0 {
                            Image(systemName: delta > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: 10, weight: .bold))
                                .accessibilityHidden(true)
                        }
                        Text(delta == 0 ? "No change" : "\(abs(delta)) \(abs(delta) == 1 ? "point" : "points")")
                            .font(SR.Text.label(13))
                    }
                    .foregroundStyle(delta > 0 ? SR.good : delta < 0 ? SR.error : SR.inkMuted)
                    Text("vs the \(impact.windowDays) days before")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(deltaSpoken(delta))
            }
            Spacer(minLength: 0)
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let share = impact.answeredShare {
                fact("Answered", "\(impact.rated) of \(impact.noticed) · \(Int((share * 100).rounded()))%")
            }
            fact("Acted on", "\(impact.actedOn)")
            fact("Results back", "\(impact.result)")
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func deltaSpoken(_ delta: Int) -> String {
        if delta == 0 { return "No change against the \(impact.windowDays) days before" }
        return "\(delta > 0 ? "Up" : "Down") \(abs(delta)) points against the \(impact.windowDays) days before"
    }

    // MARK: - Twelve weeks

    private struct Segment: Identifiable {
        let id: String
        let week: Date
        let answer: String
        let count: Int
    }

    static let worth = "Worth knowing"
    static let notForMe = "Not for me"
    static let unanswered = "Not answered"

    /// Each week as three stacked pieces, in the legend's order. The last
    /// twelve weeks the site sent; a week whose date cannot be read is left off.
    private var segments: [Segment] {
        impact.weeks.suffix(12).flatMap { week -> [Segment] in
            guard let date = week.date else { return [] }
            return [
                Segment(id: "\(week.start)-u", week: date, answer: Self.worth, count: week.useful),
                Segment(id: "\(week.start)-n", week: date, answer: Self.notForMe, count: week.notUseful),
                Segment(id: "\(week.start)-o", week: date, answer: Self.unanswered, count: week.undecided),
            ]
        }
    }

    private var chart: some View {
        Chart(segments) { segment in
            BarMark(
                x: .value("Week", segment.week, unit: .weekOfYear),
                y: .value("Notes", segment.count)
            )
            .foregroundStyle(by: .value("Answer", segment.answer))
        }
        .chartForegroundStyleScale([
            Self.worth: SR.accentInk,
            Self.notForMe: SR.accent,
            Self.unanswered: SR.ink.opacity(0.12),
        ])
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(SR.mono(11)).foregroundStyle(SR.inkMuted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(SR.line)
                AxisValueLabel().font(SR.mono(11)).foregroundStyle(SR.inkMuted)
            }
        }
        .frame(height: 140)
        .accessibilityLabel("Answers to notes, week by week, over the last \(min(impact.weeks.count, 12)) weeks")
    }

    private var legend: some View {
        HStack(spacing: 14) {
            swatch(SR.accentInk, Self.worth)
            swatch(SR.accent, Self.notForMe)
            swatch(SR.ink.opacity(0.12), Self.unanswered, outlined: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func swatch(_ color: Color, _ label: String, outlined: Bool = false) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(outlined ? SR.inkMuted : Color.clear, lineWidth: 1))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(label)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

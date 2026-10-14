import SwiftUI

// v4: the four stages of a day, each with its own look — the trip designer
// studio's bands, on the phone. Paint from the SR palette only (no new
// hues): a warm accent morning, an olive lunch, a teal afternoon, an ink
// evening. The site studio was not built when this was drawn; when it is,
// these should be matched to its tokens.

struct TripStageStyle {
    let symbol: String
    /// The heading's colour, and the band's edge.
    let tone: Color
    /// The band's wash under its stops.
    let wash: Color
    /// The heading strip: filled (evening) or quiet.
    let filledHeader: Bool

    static func of(_ stage: DayStage) -> TripStageStyle {
        switch stage {
        case .morning: return TripStageStyle(symbol: "sunrise", tone: SR.accentDeep, wash: SR.accent.opacity(0.07), filledHeader: false)
        case .lunch: return TripStageStyle(symbol: "fork.knife", tone: SR.good, wash: SR.good.opacity(0.09), filledHeader: false)
        case .afternoon: return TripStageStyle(symbol: "sun.max", tone: SR.accentInk, wash: SR.accentInk.opacity(0.07), filledHeader: false)
        case .evening: return TripStageStyle(symbol: "moon.stars", tone: SR.ink, wash: SR.ink.opacity(0.06), filledHeader: true)
        }
    }
}

/// One stage of the day as a band: its heading, then whatever it holds.
struct TripStageBand<Content: View>: View {
    let stage: DayStage
    var trailing: String? = nil
    var empty = false
    @ViewBuilder var content: Content

    var body: some View {
        let style = TripStageStyle.of(stage)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: style.symbol).accessibilityHidden(true)
                Text(stage.label.uppercased())
                    .font(SR.Text.sectionTitle(13))
                    .tracking(1.2)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).font(SR.Text.mono())
                }
            }
            .foregroundStyle(style.filledHeader ? SR.cream : style.tone)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(style.filledHeader ? AnyShapeStyle(SR.band) : AnyShapeStyle(style.wash))
            .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                if empty {
                    Text("Nothing planned — free time")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .padding(.vertical, 10)
                } else {
                    content
                }
            }
            .padding(.horizontal, 10)
            .background(style.wash)
        }
        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(style.filledHeader ? SR.band : style.tone).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
        .accessibilityIdentifier("trip-stage-\(stage.rawValue)")
    }
}

/// A day's four stages in brief, for the trip's days list: one line each,
/// in its stage's colour.
struct TripStageStrip: View {
    let day: PlannedDay
    let wishes: [TripWish]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(TripStages.groups(day, wishes: wishes), id: \.stage) { group in
                let style = TripStageStyle.of(group.stage)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: style.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(style.tone)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(TripStages.brief(day, group.indexes))
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(group.stage.label): \(TripStages.brief(day, group.indexes))")
            }
        }
        .padding(.leading, 36)
        .padding(.bottom, 6)
    }
}

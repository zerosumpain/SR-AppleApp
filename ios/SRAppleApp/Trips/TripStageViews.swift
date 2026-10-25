import SwiftUI

// The four parts of a day — breakfast & morning, lunch, afternoon, dinner &
// evening — as ONE design (red team 2026-10-15, proposal E): the light
// through the day. Each part wears its colour as a thin rule and a dot —
// petrol morning, orange noon, ochre afternoon, ink evening — the same
// colours as its pins on the day's map (`TripMapScene.stageColor`), on the
// same paper. (It was four treatments: a dot grain, an orange wash, a hatch
// behind the text and a dark band, each with its own heading style.)

/// Rows inside a dark band draw light on dark. No band is dark now; the key
/// stays so the rows' light-on-dark path keeps working where one is.
private struct TripOnDarkKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var tripOnDark: Bool {
        get { self[TripOnDarkKey.self] }
        set { self[TripOnDarkKey.self] = newValue }
    }
}

extension DayStage {
    /// Its colour: the light at that time of day, as on the map.
    /// v8: the trip palette's, so the evening lifts in dark mode (#5A55A8).
    var color: Color { TripPalette.stage(self) }

    /// "the morning", for sentences.
    var phrase: String {
        switch self {
        case .morning: return "the morning"
        case .lunch: return "lunch"
        case .afternoon: return "the afternoon"
        case .evening: return "the evening"
        }
    }
}

/// One part of the day: its heading, then whatever it holds.
struct TripStageBand<Content: View>: View {
    let stage: DayStage
    var trailing: String? = nil
    var empty = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(stage.color).frame(width: 9, height: 9)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    .accessibilityHidden(true)
                Text(stage.label)
                    .font(SR.Text.title(17))
                    .foregroundStyle(SR.ink)
                if let trailing {
                    Text(trailing)
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if empty {
                Text("Free — nothing planned.")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkMuted)
            }
            content
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Capsule().fill(stage.color.opacity(empty ? 0.35 : 1)).frame(width: 3)
        }
        .accessibilityIdentifier("trip-stage-\(stage.rawValue)")
    }
}

extension TripFullness {
    /// From quiet to warning, in the SR palette.
    static func colour(_ band: String) -> Color {
        switch band {
        case "empty": return SR.inkGhost
        case "light": return SR.accentInk
        case "balanced": return SR.good
        case "full": return SR.accent
        default: return SR.error
        }
    }
}

/// A trip page's own heading: sentence case, in the reading colour, a figure
/// beside it in the muted ink — not the shouted mono eyebrow, which used to
/// head every block and made each page read as a form.
struct TripHeading: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(SR.Text.title(17))
                .foregroundStyle(SR.ink)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

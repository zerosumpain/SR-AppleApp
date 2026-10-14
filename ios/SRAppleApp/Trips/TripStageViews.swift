import SwiftUI

// v4: the four stages of a day, each with its own look — the site's trip
// studio (`/trips/[id]`), matched on the phone:
//
//   Breakfast & morning  paper with a petrol dot grain and a petrol rule down
//                        the left; a mono, tracked petrol heading
//   Lunch                an orange wash under an orange top rule; an orange
//                        display heading
//   Afternoon            a hatched band; an ink display heading, underlined
//   Dinner & evening     dark ink, an orange heading and light text
//
// All from the SR palette: accent (orange), accent ink (petrol), ink, paper.

/// Rows inside the evening band draw light on dark.
private struct TripOnDarkKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var tripOnDark: Bool {
        get { self[TripOnDarkKey.self] }
        set { self[TripOnDarkKey.self] = newValue }
    }
}

/// One stage of the day as a band: its heading, then whatever it holds.
struct TripStageBand<Content: View>: View {
    let stage: DayStage
    var trailing: String? = nil
    var empty = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading
            if empty {
                Text("Free — nothing planned.")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(stage == .evening ? SR.creamOnDark : SR.inkMuted)
            } else {
                content
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { ground }
        .overlay(alignment: .leading) {
            if stage == .morning { Rectangle().fill(SR.accentInk).frame(width: 4) }
        }
        .overlay(alignment: .top) {
            if stage == .lunch { Rectangle().fill(SR.accent).frame(height: 3) }
        }
        .overlay {
            if stage != .evening { Rectangle().stroke(SR.line, lineWidth: 1) }
        }
        .environment(\.tripOnDark, stage == .evening)
        .accessibilityIdentifier("trip-stage-\(stage.rawValue)")
    }

    @ViewBuilder
    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            switch stage {
            case .morning:
                Text(stage.label.uppercased())
                    .font(SR.Text.mono(13))
                    .tracking(1.6)
                    .foregroundStyle(SR.accentInk)
            case .lunch:
                Text(stage.label)
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.accent)
            case .afternoon:
                Text(stage.label)
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .underline(true, color: SR.ink)
            case .evening:
                Text(stage.label)
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.accentOnDark)
            }
            if let trailing {
                Text(trailing)
                    .font(SR.Text.mono(12))
                    .foregroundStyle(stage == .evening ? SR.creamOnDark : SR.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var ground: some View {
        switch stage {
        case .morning:
            ZStack {
                SR.paper
                TripGrain(color: SR.accentInk.opacity(0.22), spacing: 9, kind: .dots)
            }
        case .lunch:
            SR.accent.opacity(0.13)
        case .afternoon:
            ZStack {
                SR.paper
                TripGrain(color: SR.ink.opacity(0.09), spacing: 9, kind: .hatch)
            }
        case .evening:
            SR.band
        }
    }
}

/// The studio's textures: a dot grain or a diagonal hatch, drawn once.
struct TripGrain: View {
    enum Kind { case dots, hatch }
    let color: Color
    let spacing: CGFloat
    let kind: Kind

    var body: some View {
        Canvas { context, size in
            switch kind {
            case .dots:
                var y: CGFloat = spacing / 2
                while y < size.height {
                    var x: CGFloat = spacing / 2
                    while x < size.width {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(color))
                        x += spacing
                    }
                    y += spacing
                }
            case .hatch:
                var path = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += spacing
                }
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A day's four stages in brief, for the trip's days list: one line each,
/// marked in its stage's colour.
struct TripStageStrip: View {
    let day: PlannedDay
    let wishes: [TripWish]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(TripStages.groups(day, wishes: wishes), id: \.stage) { group in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TripStageMark(stage: group.stage)
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

/// A small swatch of a stage's treatment, for lists.
struct TripStageMark: View {
    let stage: DayStage

    var body: some View {
        Group {
            switch stage {
            case .morning: Rectangle().fill(SR.accentInk)
            case .lunch: Rectangle().fill(SR.accent)
            case .afternoon: ZStack { SR.paper; TripGrain(color: SR.ink.opacity(0.5), spacing: 3, kind: .hatch) }.overlay(Rectangle().stroke(SR.ink.opacity(0.5), lineWidth: 1))
            case .evening: Rectangle().fill(SR.band)
            }
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

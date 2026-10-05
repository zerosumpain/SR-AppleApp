import SwiftUI
import WidgetKit
import ActivityKit

// The family journey, drawn. Nothing here fetches: every word and figure
// arrives in the push (`JourneyAttributes.ContentState`), and the site decides
// what they say. See SR-Main `$lib/home/presence/live-journey`.
//
// The same extension carries the family's Home Screen widgets — the step
// board and the task list (`FamilyWidgets.swift`) — so they ride on the
// profile CI already mints for it rather than needing a target of their own.

@main
struct SRLiveBundle: WidgetBundle {
    var body: some Widget {
        JourneyLiveActivity()
        FamilyStepsWidget()
        FamilyTasksWidget()
    }
}

// The site palette's day values, from the shared tokens (`Shared/SRTokens.swift`):
// an extension cannot see the app's `SR`.
private enum Ink {
    private typealias T = SRTokens.Colour
    static let paper = Color(token: T.bg.light)
    static let ink = Color(token: T.textPrimary.light)
    static let muted = Color(token: T.textMuted.light)
    static let accent = Color(token: T.accent.light)
    static let accentOnDark = Color(token: T.accentOnDark.light)
    static let cream = Color(token: T.chromeInk.light)
    static let creamMuted = Color(token: T.onInk70.light)
    static let good = Color(token: T.good.light)
    static let goodOnDark = Color(token: T.goodOnDark.light)
    static let line = Color(token: T.cardBorder.light)
}

private extension Font {
    /// Inter Display: the headline face. Falls back to a heavy system font if
    /// the file did not register, which reads close enough.
    static func display(_ size: CGFloat) -> Font { .custom("InterDisplay-ExtraBold", size: size, relativeTo: .headline) }
    /// JetBrains Mono: labels and figures.
    static func mono(_ size: CGFloat) -> Font { .custom("JetBrainsMono-Medium", size: size, relativeTo: .caption) }
}

struct JourneyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyAttributes.self) { context in
            LockScreenJourney(attributes: context.attributes, state: context.state, stale: context.isStale)
                .activityBackgroundTint(Ink.paper)
                .activitySystemActionForegroundColor(Ink.ink)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.symbol)
                        .font(.title2)
                        .foregroundStyle(state.arrived ? Ink.goodOnDark : Ink.accentOnDark)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let eta = state.etaMinutes {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("~\(eta)").font(.display(22)).foregroundStyle(Ink.cream)
                            Text("MIN").font(.mono(10)).foregroundStyle(Ink.creamMuted)
                        }
                        .padding(.trailing, 4)
                    } else if let distance = state.shortDistance {
                        Text(distance).font(.mono(15)).foregroundStyle(Ink.cream).padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.headline)
                        .font(.display(15))
                        .foregroundStyle(Ink.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.detail)
                            .font(.mono(12))
                            .foregroundStyle(Ink.creamMuted)
                            .lineLimit(2)
                        if let progress = state.progress {
                            JourneyBar(progress: progress, fill: state.arrived ? Ink.goodOnDark : Ink.accentOnDark, track: Ink.cream.opacity(0.18))
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: state.symbol)
                    .foregroundStyle(state.arrived ? Ink.goodOnDark : Ink.accentOnDark)
            } compactTrailing: {
                Text(state.arrived ? "Home" : (state.etaMinutes.map { "~\($0)m" } ?? state.shortDistance ?? context.attributes.name))
                    .font(.mono(12))
                    .foregroundStyle(Ink.cream)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: state.symbol)
                    .foregroundStyle(state.arrived ? Ink.goodOnDark : Ink.accentOnDark)
            }
            .keylineTint(Ink.accentOnDark)
        }
    }
}

/// The Lock Screen card: who and where from, how it is going, and a bar home.
struct LockScreenJourney: View {
    let attributes: JourneyAttributes
    let state: JourneyAttributes.ContentState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.arrived ? "ARRIVED" : (state.moving ? "ON THE WAY" : "JOURNEY"))
                    .font(.mono(11))
                    .tracking(1.2)
                    .foregroundStyle(state.arrived ? Ink.good : Ink.accent)
                Spacer()
                Text(state.updated, style: .time)
                    .font(.mono(11))
                    .foregroundStyle(Ink.muted)
            }
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: state.symbol)
                    .font(.title3)
                    .foregroundStyle(state.arrived ? Ink.good : Ink.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.headline)
                        .font(.display(18))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(stale ? "\(state.detail) · not updated lately" : state.detail)
                        .font(.mono(12))
                        .foregroundStyle(Ink.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if let eta = state.etaMinutes, state.moving {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("~\(eta)").font(.display(24)).foregroundStyle(Ink.ink)
                        Text("MIN").font(.mono(10)).foregroundStyle(Ink.muted)
                    }
                }
            }
            if let progress = state.progress {
                JourneyBar(progress: progress, fill: state.arrived ? Ink.good : Ink.accent, track: Ink.line)
            }
        }
        .padding(16)
        .opacity(stale ? 0.7 : 1)
    }
}

/// From where they left to home, as far as they have got.
struct JourneyBar: View {
    let progress: Double
    let fill: Color
    let track: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: max(8, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Progress home")
        .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100)) percent")
    }
}

import SwiftUI
import WidgetKit
import ActivityKit

// The family journey, drawn. Nothing here fetches: every word and figure
// arrives in the push (`JourneyAttributes.ContentState`), and the site decides
// what they say. See SR-Main `$lib/home/presence/live-journey`.

@main
struct SRLiveBundle: WidgetBundle {
    var body: some Widget {
        JourneyLiveActivity()
    }
}

// The site palette (`Theme.swift`), repeated: an extension cannot see the app.
private enum Ink {
    static let paper = Color(red: 0xED / 255, green: 0xE4 / 255, blue: 0xD4 / 255)
    static let ink = Color(red: 0x1A / 255, green: 0x10 / 255, blue: 0x08 / 255)
    static let muted = Color(red: 0x1A / 255, green: 0x10 / 255, blue: 0x08 / 255).opacity(0.65)
    static let accent = Color(red: 0xC4 / 255, green: 0x57 / 255, blue: 0x0A / 255)
    static let accentOnDark = Color(red: 0xE8 / 255, green: 0x86 / 255, blue: 0x3A / 255)
    static let cream = Color(red: 0xED / 255, green: 0xE4 / 255, blue: 0xD4 / 255)
    static let creamMuted = Color(red: 0xED / 255, green: 0xE4 / 255, blue: 0xD4 / 255).opacity(0.7)
    static let good = Color(red: 0x55 / 255, green: 0x66 / 255, blue: 0x3A / 255)
    static let goodOnDark = Color(red: 0x8A / 255, green: 0x9A / 255, blue: 0x5B / 255)
    static let line = Color(red: 0x1A / 255, green: 0x10 / 255, blue: 0x08 / 255).opacity(0.18)
}

private extension Font {
    /// Archivo Black: the headline face. Falls back to a heavy system font if
    /// the file did not register, which reads close enough.
    static func display(_ size: CGFloat) -> Font { .custom("ArchivoBlack-Regular", size: size, relativeTo: .headline) }
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

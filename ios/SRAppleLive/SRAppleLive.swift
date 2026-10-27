import SwiftUI
import WidgetKit
import ActivityKit

// The family journey, drawn. Nothing here fetches: every word and figure
// arrives in the push (`JourneyAttributes.ContentState`), and the site decides
// what they say. See SR-Main `$lib/home/presence/live-journey`.
//
// It also draws a capture while it records, and carries the Capture control
// for Control Center (iOS 18).
//
// The same extension carries the family's Home Screen widgets — the step
// board and the task list (`FamilyWidgets.swift`) — so they ride on the
// profile CI already mints for it rather than needing a target of their own.

@main
struct SRLiveBundle: WidgetBundle {
    var body: some Widget {
        JourneyLiveActivity()
        TripLiveActivity()
        FamilyStepsWidget()
        FamilyTasksWidget()
        // A capture recording (`Captures/CaptureRecorder.swift` starts it).
        CaptureLiveActivity()
        // Start or stop a capture from Control Center or the Lock Screen.
        if #available(iOS 18.0, *) {
            CaptureControl()
        }
    }
}

// The reader's palette, as the app left it on the shelf (`SRWidgetPalette`):
// an extension cannot see the app. Read fresh for each render — a Live
// Activity redraws only when it is updated, and a stale palette would outlive
// the reader's change by a whole journey.
//
// Prism: the Lock Screen card is the feature's Home tile — the family's hue
// for a journey, the trips' hue for a trip day — with its type on top. The
// Dynamic Island is always black, so it takes the hue's bright stop.
struct LiveInk {
    let hue: SRHueSpec
    let good: SRTone

    /// Type on the card.
    var on: Color { SRRGB.color(hue.onFill) }
    var onSoft: Color { SRRGB.color(hue.onFill, alpha: 0.78) }
    var track: Color { SRRGB.color(hue.onFill, alpha: 0.25) }
    /// The card's own colour, for the system's tint behind it.
    var tint: Color { SRRGB.color(hue.base) }
    /// On the black island.
    var bright: Color { SRRGB.color(hue.glow) }
    var goodBright: Color { SRRGB.color(good.dark) }
    static let cream = Color.white
    static let creamMuted = Color.white.opacity(0.7)

    static func journey() -> LiveInk {
        let palette = SRWidgetPalette.load()
        return LiveInk(hue: palette.family, good: palette.good)
    }

    static func trip() -> LiveInk {
        let palette = SRWidgetPalette.load()
        return LiveInk(hue: palette.trips, good: palette.good)
    }
}

/// The Live Activities' faces: SF Pro Rounded, as the app's.
extension Font {
    static func display(_ size: CGFloat) -> Font { FamilyWidgetFont.rounded(size, .heavy, .headline) }
    static func mono(_ size: CGFloat) -> Font { FamilyWidgetFont.rounded(size, .semibold, .caption1).monospacedDigit() }
}

struct JourneyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyAttributes.self) { context in
            let ink = LiveInk.journey()
            return LockScreenJourney(attributes: context.attributes, state: context.state, stale: context.isStale, ink: ink)
                .activityBackgroundTint(ink.tint)
                .activitySystemActionForegroundColor(ink.on)
        } dynamicIsland: { context in
            let state = context.state
            let ink = LiveInk.journey()
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.symbol)
                        .font(.title2)
                        .foregroundStyle(state.arrived ? ink.goodBright : ink.bright)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let eta = state.etaMinutes {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("~\(eta)").font(.display(22)).foregroundStyle(LiveInk.cream)
                            Text("MIN").font(.mono(10)).foregroundStyle(LiveInk.creamMuted)
                        }
                        .padding(.trailing, 4)
                    } else if let distance = state.shortDistance {
                        Text(distance).font(.mono(15)).foregroundStyle(LiveInk.cream).padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.headline)
                        .font(.display(15))
                        .foregroundStyle(LiveInk.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.detail)
                            .font(.mono(12))
                            .foregroundStyle(LiveInk.creamMuted)
                            .lineLimit(2)
                        if let progress = state.progress {
                            JourneyBar(progress: progress, fill: state.arrived ? ink.goodBright : ink.bright, track: LiveInk.cream.opacity(0.18))
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: state.symbol)
                    .foregroundStyle(state.arrived ? ink.goodBright : ink.bright)
            } compactTrailing: {
                Text(state.arrived ? "Home" : (state.etaMinutes.map { "~\($0)m" } ?? state.shortDistance ?? context.attributes.name))
                    .font(.mono(12))
                    .foregroundStyle(LiveInk.cream)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: state.symbol)
                    .foregroundStyle(state.arrived ? ink.goodBright : ink.bright)
            }
            .keylineTint(ink.bright)
        }
    }
}

/// The Lock Screen card: who and where from, how it is going, and a bar home.
struct LockScreenJourney: View {
    let attributes: JourneyAttributes
    let state: JourneyAttributes.ContentState
    let stale: Bool
    var ink: LiveInk = .journey()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(
                    state.arrived ? "ARRIVED" : (state.moving ? "ON THE WAY" : "JOURNEY"),
                    systemImage: state.arrived ? "checkmark.circle.fill" : "location.fill"
                )
                .font(.mono(11))
                .tracking(1)
                .foregroundStyle(ink.on)
                Spacer()
                Text(state.updated, style: .time)
                    .font(.mono(11))
                    .foregroundStyle(ink.onSoft)
            }
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: state.symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ink.tint)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(ink.on))
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.headline)
                        .font(.display(18))
                        .foregroundStyle(ink.on)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(stale ? "\(state.detail) · not updated lately" : state.detail)
                        .font(.mono(12))
                        .foregroundStyle(ink.onSoft)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if let eta = state.etaMinutes, state.moving {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("~\(eta)").font(.display(26)).foregroundStyle(ink.on)
                        Text("MIN").font(.mono(10)).foregroundStyle(ink.onSoft)
                    }
                }
            }
            if let progress = state.progress {
                JourneyBar(progress: progress, fill: ink.on, track: ink.track)
            }
        }
        .padding(16)
        .background(FamilyWidgetGround(hue: ink.hue))
        .opacity(stale ? 0.75 : 1)
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

import SwiftUI
import WidgetKit
import ActivityKit

// A trip day, drawn: "Next: Pantheon · leave in 8 min · 12 min walk".
//
// Nothing here fetches. The app starts and updates the activity
// (`Trips/TripLive.swift`) whenever what comes next changes, and the
// countdown runs on its own between updates — `Text(timerInterval:)` and
// `Text(_:style:)` tick without the app.

struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripAttributes.self) { context in
            let ink = LiveInk.trip()
            return LockScreenTrip(attributes: context.attributes, state: context.state, stale: context.isStale, ink: ink)
                .activityBackgroundTint(ink.tint)
                .activitySystemActionForegroundColor(ink.on)
                // A tap opens the day, not wherever the app was left.
                .widgetURL(context.attributes.link)
        } dynamicIsland: { context in
            let state = context.state
            let ink = LiveInk.trip()
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.symbol)
                        .font(.title2)
                        .foregroundStyle(ink.bright)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(state.leave, style: .time)
                            .font(.display(20))
                            .foregroundStyle(LiveInk.cream)
                        Text("LEAVE BY").font(.mono(10)).foregroundStyle(LiveInk.creamMuted)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("Next: \(state.nextTitle)")
                        .font(.display(15))
                        .foregroundStyle(LiveInk.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        TripCountdown(state: state)
                        Text("· \(state.legLine) · \(state.stopLine)")
                    }
                    .font(.mono(12))
                    .foregroundStyle(LiveInk.creamMuted)
                    .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: state.symbol).foregroundStyle(ink.bright)
            } compactTrailing: {
                Text(state.leave, style: .time)
                    .font(.mono(12))
                    .foregroundStyle(LiveInk.cream)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: state.symbol).foregroundStyle(ink.bright)
            }
            .keylineTint(ink.bright)
            .widgetURL(context.attributes.link)
        }
    }
}

/// "leave in 8:12" while there is time; "leave now" once there is not.
/// A timer the system runs, so it is right between the app's updates.
struct TripCountdown: View {
    let state: TripAttributes.ContentState

    var body: some View {
        if state.leave > Date() {
            HStack(spacing: 4) {
                Text("leave in")
                Text(timerInterval: Date()...state.leave, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 56, alignment: .leading)
            }
        } else {
            Text("leave now")
        }
    }
}

/// The Lock Screen card: what is next, when to go, how, and where in the day.
struct LockScreenTrip: View {
    let attributes: TripAttributes
    let state: TripAttributes.ContentState
    let stale: Bool
    var ink: LiveInk = .trip()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(attributes.title.uppercased())
                    .font(.mono(11))
                    .tracking(1)
                    .foregroundStyle(ink.on)
                    .lineLimit(1)
                Spacer()
                Text(state.stopLine.uppercased())
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
                    Text("Next: \(state.nextTitle)")
                        .font(.display(18))
                        .foregroundStyle(ink.on)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    HStack(spacing: 4) {
                        TripCountdown(state: state)
                        Text("· \(state.legLine)")
                    }
                    .font(.mono(12))
                    .foregroundStyle(ink.onSoft)
                    .lineLimit(1)
                    if stale {
                        Text("Open the app to bring this up to date")
                            .font(.mono(11))
                            .foregroundStyle(ink.onSoft)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(state.leave, style: .time).font(.display(22)).foregroundStyle(ink.on)
                    Text("LEAVE BY").font(.mono(10)).foregroundStyle(ink.onSoft)
                }
            }
        }
        .padding(16)
        .background(FamilyWidgetGround(hue: ink.hue))
        .opacity(stale ? 0.75 : 1)
        .accessibilityElement(children: .combine)
    }
}

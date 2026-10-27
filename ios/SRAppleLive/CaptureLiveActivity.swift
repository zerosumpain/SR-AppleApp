import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

// A capture recording, drawn: a red dot, a running timer and Stop.
//
// Nothing here fetches or ticks: the timer is `Text(timerInterval:)`, which
// the system runs, and Stop is `StopCaptureIntent`, performed in the app's
// process (it is compiled into both targets). The app ends the activity at
// Stop, so the card never outlives the recording.

struct CaptureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CaptureAttributes.self) { context in
            CaptureLockScreen(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.link)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(.red)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CaptureStopButton(saving: state.saving)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    CaptureTimer(state: state)
                        .font(.display(22))
                        .foregroundStyle(LiveInk.cream)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(state.withScreenshot ? "Capturing, with a screenshot" : "Capturing")
                        .font(.mono(12))
                        .foregroundStyle(LiveInk.creamMuted)
                }
            } compactLeading: {
                Image(systemName: "waveform").foregroundStyle(.red)
            } compactTrailing: {
                CaptureTimer(state: state)
                    .font(.mono(12))
                    .foregroundStyle(LiveInk.cream)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "waveform").foregroundStyle(.red)
            }
            .keylineTint(.red)
            .widgetURL(context.attributes.link)
        }
    }
}

/// Counting up from the press.
struct CaptureTimer: View {
    let state: CaptureAttributes.ContentState

    var body: some View {
        if state.saving {
            Text("Saving")
        } else {
            Text(timerInterval: state.started...state.started.addingTimeInterval(4 * 3600), countsDown: false)
                .monospacedDigit()
        }
    }
}

struct CaptureStopButton: View {
    let saving: Bool

    var body: some View {
        Button(intent: StopCaptureIntent()) {
            Label("Stop", systemImage: "stop.fill")
                .font(.mono(13))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(saving)
    }
}

/// The Lock Screen card.
struct CaptureLockScreen: View {
    let state: CaptureAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.withScreenshot ? "CAPTURING · SCREENSHOT" : "CAPTURING")
                    .font(.mono(11))
                    .tracking(1)
                    .foregroundStyle(LiveInk.creamMuted)
                CaptureTimer(state: state)
                    .font(.display(26))
                    .foregroundStyle(LiveInk.cream)
            }
            Spacer(minLength: 0)
            CaptureStopButton(saving: state.saving)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

/// Control Center and the Lock Screen (iOS 18): one press starts a capture,
/// the next stops it — `StartCaptureIntent` toggles.
@available(iOS 18.0, *)
struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.strangeramblings.captures.control") {
            ControlWidgetButton(action: StartCaptureIntent()) {
                Label("Capture", systemImage: "waveform.badge.mic")
            }
        }
        .displayName("Capture")
        .description("Start or stop a capture in SR.")
    }
}

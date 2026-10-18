import SwiftUI

/// How things move, said once.
///
/// Until Today's sky every animation in the app was written where it was
/// used, which is fine for one and wrong for a screen with five: the sun, the
/// rings, the sky's minute tick and a figure rolling to its new value all need
/// to feel like one hand moved them. So the curves live here, and so does the
/// one rule they share — under Reduce Motion nothing eases, it simply changes.
///
/// No bounce anywhere. A sun that overshoots the horizon and settles back is
/// a toy, and this is a glance at the morning.
enum SRMotion {
    /// The sun coming up on the first Today of the launch.
    static let rise = Animation.smooth(duration: 1.1)
    /// The rings drawing themselves in, one after another.
    static let sweep = Animation.smooth(duration: 0.9)
    /// The once-a-minute drift of the sun and the sky: slow enough that you
    /// never see it move, only find it moved.
    static let tick = Animation.easeInOut(duration: 2)
    /// Back to now after a scrub along the horizon.
    static let settle = Animation.smooth(duration: 0.35)
    /// What replaces a movement under Reduce Motion, where one is needed at all.
    static let fadeIn = Animation.easeOut(duration: 0.2)
}

extension View {
    /// `.animation(_:value:)`, except that under Reduce Motion the change is
    /// made with no animation at all.
    func srAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(SRAnimationModifier(animation: animation, value: value))
    }

    /// A number that rolls to its new value, digit by digit, when it changes
    /// — and simply changes under Reduce Motion.
    func srNumeric(_ value: Double) -> some View {
        modifier(SRNumericModifier(value: value))
    }
}

private struct SRAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct SRNumericModifier: ViewModifier {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .numericText(value: value))
            .animation(reduceMotion ? nil : .snappy, value: value)
    }
}

/// A press you can feel without a haptic: the thing under the finger gives
/// a little. Under Reduce Motion it dims instead of shrinking.
///
/// For Today's doors and the sun. The rest of the app keeps `.plain`, which
/// is right for rows in a list.
struct SRPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pressed(configuration: configuration)
    }

    /// Its own view so it can read the environment.
    private struct Pressed: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .opacity(configuration.isPressed && reduceMotion ? 0.85 : 1)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
        }
    }
}

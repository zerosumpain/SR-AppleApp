import SwiftUI

/// The bar under the sky while playing: two big arrows to hold (buttons,
/// no sensor, VoiceOver), or a reminder to tilt with a recentre button, or
/// the demo's autopilot label.
struct SkyHopperControlBar: View {
    @ObservedObject var session: SkyHopperSession
    let buttons: Bool
    let height: CGFloat

    var body: some View {
        Group {
            if session.scripted {
                autopilot
            } else if buttons {
                arrows
            } else {
                tiltBar
            }
        }
        .opacity(session.isSteering ? 1 : 0.5)
    }

    private var arrows: some View {
        HStack(spacing: 12) {
            SkyHopperSteerButton(left: true, height: height, session: session)
                .accessibilityIdentifier("sky-hopper-left")
            SkyHopperSteerButton(left: false, height: height, session: session)
                .accessibilityIdentifier("sky-hopper-right")
        }
    }

    private var tiltBar: some View {
        HStack(spacing: 12) {
            Label("Tilt the phone to steer", systemImage: "rotate.right")
                .font(SR.Text.title(15))
                .foregroundStyle(SR.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .padding(.horizontal, 14)
                .srGlassCard(.paper, radius: 18)
            Button {
                SRHaptic.tap()
                session.recentre()
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(SR.ink)
                    .frame(width: 56, height: 56)
                    .srGlassCard(.paper, radius: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(SRPressStyle())
            .accessibilityLabel("Make the way I'm holding the phone straight")
            .accessibilityIdentifier("sky-hopper-recentre")
        }
    }

    private var autopilot: some View {
        Label("Autopilot", systemImage: "sparkles")
            .font(SR.Text.title(15))
            .foregroundStyle(SR.inkSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 56)
            .srGlassCard(.paper, radius: 18)
            .accessibilityIdentifier("sky-hopper-autopilot")
    }
}

/// One big arrow, "on" while a finger holds it. The first press also
/// starts the run.
struct SkyHopperSteerButton: View {
    let left: Bool
    let height: CGFloat
    let session: SkyHopperSession
    @State private var held = false
    /// True only while a finger is on it: a gesture the system cancels never
    /// reaches `onEnded`, but this resets itself, so Hop cannot be left
    /// steering with nobody touching.
    @GestureState private var touching = false

    var body: some View {
        Image(systemName: left ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill")
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(held ? SR.paper : SR.ink)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(face)
            .srGlassCard(.paper, radius: 22)
            .scaleEffect(held ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: held)
            .contentShape(Rectangle())
            .gesture(press)
            .onChange(of: touching) { _, now in
                if !now { release() }
            }
            .onDisappear { release() }
            .accessibilityElement()
            .accessibilityLabel(left ? "Steer left" : "Steer right")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { session.nudge(left: left) }
    }

    private var face: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(held ? SR.accentDeep : Color.clear)
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { _ in
                guard !held else { return }
                held = true
                SRHaptic.select()
                session.hold(left: left, down: true)
            }
            .onEnded { _ in release() }
    }

    private func release() {
        guard held else { return }
        held = false
        session.hold(left: left, down: false)
    }
}

/// A figure in the HUD with its label.
struct SkyHopperStatBox: View {
    let title: String
    let value: Int
    var strong = false
    /// Rolling digits for a figure that changes now and then (stars). Score
    /// and Best count up with every metre, several times a second: rolled,
    /// each roll would start before the last one ended and the HUD would
    /// never be still while Hop climbs.
    var rolls = true

    private var transition: ContentTransition { rolls ? .numericText() : .identity }
    private var roll: Animation? { rolls ? .snappy(duration: 0.25) : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(value)")
                .font(SR.Text.figure(strong ? 24 : 20))
                .foregroundStyle(strong ? SR.accent : SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(transition)
                .animation(roll, value: value)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .srGlassCard(.paper, radius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}

/// The power-ups running, as small chips: seconds left, or the bubble.
struct SkyHopperPowerChips: View {
    let powers: SkyHopperPowers

    var body: some View {
        HStack(spacing: 6) {
            if powers.propeller > 0 {
                chip(icon: "fanblades.fill", text: "\(powers.propeller)s", tint: SkyHopperInk.cap)
            }
            if powers.magnet > 0 {
                chip(icon: "star.circle.fill", text: "\(powers.magnet)s", tint: SkyHopperInk.magnet)
            }
            if powers.bubble {
                chip(icon: "circle.dotted", text: "Bubble", tint: SR.accent)
            }
        }
    }

    private func chip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(SR.ink.opacity(0.07)))
    }
}

import SwiftUI

/// The on-screen stick, for a phone with no tilt sensor or a player who
/// would rather not tilt: drag the knob the way the marble should roll.
/// Springs back to the middle when let go.
struct TiltMazeJoystick: View {
    /// Across, in points: smaller on a short phone, so the board keeps its room.
    var size: CGFloat = TiltMazeJoystick.fullSize
    let changed: (TiltMazeVector) -> Void
    @State private var knob: CGSize = .zero
    @State private var held = false

    static let fullSize: CGFloat = 148
    static let compactSize: CGFloat = 120

    private var knobSize: CGFloat { (size * 0.4).rounded() }
    private var reach: CGFloat { size / 2 - knobSize * 0.45 }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.28))
                .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1.5))
            // A cross so the middle is easy to find by eye.
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 2, height: size * 0.6)
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: size * 0.6, height: 2)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xF6DC8B), Color(hex: 0xB9862A)], center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 2, endRadius: knobSize * 0.66))
                .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 1))
                .frame(width: knobSize, height: knobSize)
                .shadow(color: Color.black.opacity(0.4), radius: held ? 2 : 5, y: held ? 1 : 3)
                .offset(knob)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !held { SRHaptic.select() }
                    held = true
                    let dx = value.location.x - size / 2
                    let dy = value.location.y - size / 2
                    let length = max(1, (dx * dx + dy * dy).squareRoot())
                    let scale = min(1, reach / length)
                    knob = CGSize(width: dx * scale, height: dy * scale)
                    changed(TiltMazeVector(x: Double(knob.width / reach), y: Double(knob.height / reach)))
                }
                .onEnded { _ in
                    held = false
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { knob = .zero }
                    changed(.zero)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Joystick")
        .accessibilityHint("Drag the way you want the marble to roll")
        .accessibilityIdentifier("tilt-maze-joystick")
    }
}

/// A round button big enough for a thumb mid-game.
struct TiltMazeRoundButton: View {
    let icon: String
    let label: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SR.ink)
                .frame(width: 58, height: 58)
                .srGlassCard(.paper, radius: 29)
                .contentShape(Circle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// One to three stars, lit or not, popping in one after another when shown
/// on a results card.
struct TiltMazeStars: View {
    let lit: Int
    var size: CGFloat = 16
    /// Pop the lit ones in, one by one.
    var celebrate = false
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(0..<3, id: \.self) { i in
                star(i)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(lit == 1 ? "1 star" : "\(lit) stars")
        .task(id: lit) { await reveal() }
    }

    private func star(_ i: Int) -> some View {
        let on = i < (celebrate ? shown : lit)
        return Image(systemName: on ? "star.fill" : "star")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(on ? Color(hex: 0xF2B632) : SR.inkGhost)
            .scaleEffect(on && celebrate && !reduceMotion ? 1 : (celebrate && !reduceMotion ? 0.7 : 1))
            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: shown)
    }

    @MainActor
    private func reveal() async {
        guard celebrate else { return }
        shown = 0
        try? await Task.sleep(nanoseconds: 250_000_000)
        for i in 0..<lit {
            if Task.isCancelled { return }
            shown = i + 1
            SRHaptic.select()
            try? await Task.sleep(nanoseconds: 280_000_000)
        }
    }
}

/// The strip over the board: which maze, the clock, the time for three
/// stars (or the marbles left), and the pause button.
struct TiltMazeHUD: View {
    /// Not observed here: only the clock redraws every frame.
    let engine: TiltMazeEngine
    let kicker: String
    let title: String
    /// Campaign: the clock to beat for three stars and two.
    let par: TiltMazePar?
    /// Endless: marbles left.
    let lives: Int?
    let pause: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker)
                    .font(SR.Text.label())
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            TiltMazeHUDClock(engine: engine, par: par, lives: lives)
            TiltMazeRoundButton(icon: "pause.fill", label: "Pause", id: "tilt-maze-pause", action: pause)
        }
        .padding(.leading, SR.cardPadding)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .srGlassCard(.paper)
        // The strip sits over the play field: it grows with the text, but
        // not so far that the board is squeezed to nothing.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tilt-maze-hud")
    }
}

/// The HUD's clock and what it is racing: the one part of the strip that
/// changes while the marble rolls, so the one part that watches the engine.
struct TiltMazeHUDClock: View {
    @ObservedObject var engine: TiltMazeEngine
    let par: TiltMazePar?
    let lives: Int?

    var body: some View {
        let time = engine.run.time
        VStack(alignment: .trailing, spacing: 2) {
            Text(TiltMazeFormat.time(time))
                .font(SR.Text.figure(26))
                .foregroundStyle(clockColour(time))
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("Time \(TiltMazeFormat.spoken(time))")
            target(time)
        }
    }

    /// Green while three stars are still on, amber for two, then plain.
    private func clockColour(_ t: Double) -> Color {
        guard let par else { return SR.ink }
        if t <= par.three { return SR.good }
        if t <= par.two { return SR.warn }
        return SR.ink
    }

    @ViewBuilder
    private func target(_ t: Double) -> some View {
        if let par {
            let stars = par.stars(for: t)
            let next = stars == 3 ? par.three : par.two
            HStack(spacing: 4) {
                TiltMazeStars(lit: stars, size: 11)
                if stars > 1 {
                    Text("\(Int(next))s")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stars > 1 ? "\(stars) stars if you finish within \(Int(next)) seconds" : "1 star")
        } else if let lives {
            TiltMazeMarbles(count: lives)
        }
    }
}

/// Endless: a little steel ball for each marble left.
struct TiltMazeMarbles: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(count, 0), id: \.self) { _ in
                Circle()
                    .fill(RadialGradient(colors: [Color.white, Color(hex: 0x8A929E)], center: UnitPoint(x: 0.35, y: 0.3),
                                         startRadius: 0, endRadius: 7))
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 11, height: 11)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? "1 marble left" : "\(count) marbles left")
    }
}

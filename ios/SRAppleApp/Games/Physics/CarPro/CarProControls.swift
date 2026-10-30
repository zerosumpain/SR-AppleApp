import SwiftUI

// Car Racer+ controls, sized for thumbs mid-race: two analogue pedals (the
// higher up a pedal the finger is, the harder it presses), steering by
// tilt, an on-screen wheel or a slider, and shift paddles when the gears
// are the driver's. Every control is its own view with its own gesture,
// so two thumbs work at once.

/// The pedals, the steering and the paddles, laid out for the chosen steering.
struct CarProControlDeck: View {
    @ObservedObject var race: CarProRaceController

    private var manual: Bool { !race.config.assists.autoGears }
    private var pedalHeight: CGFloat { manual && race.steering != .tilt ? 124 : 150 }

    var body: some View {
        if race.scripted {
            Text("Autopilot")
                .font(SR.Text.mono())
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.4)))
        } else {
            switch race.steering {
            case .tilt: tiltDeck
            case .wheel: touchDeck(wheel: true)
            case .slider: touchDeck(wheel: false)
            }
        }
    }

    /// Tilting, the phone is the wheel: brake under the left thumb, throttle
    /// under the right, the paddles between them.
    private var tiltDeck: some View {
        HStack(spacing: 10) {
            brakePedal
            if manual {
                VStack(spacing: 10) {
                    CarProPaddle(up: true) { race.shift(up: true) }
                    CarProPaddle(up: false) { race.shift(up: false) }
                }
            }
            throttlePedal
        }
        .frame(height: pedalHeight)
    }

    /// Steering by touch: the wheel or slider under the left thumb, the two
    /// pedals side by side under the right, and the paddles over them.
    private func touchDeck(wheel: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Group {
                if wheel {
                    CarProWheelControl(steer: race.touchSteer) { race.touchSteer = $0 }
                        .frame(width: 150, height: 150)
                } else {
                    CarProSteerSlider(steer: race.touchSteer) { race.touchSteer = $0 }
                        .frame(height: 96)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                if manual {
                    HStack(spacing: 8) {
                        CarProPaddle(up: false) { race.shift(up: false) }
                        CarProPaddle(up: true) { race.shift(up: true) }
                    }
                }
                HStack(spacing: 8) {
                    brakePedal.frame(width: 66)
                    throttlePedal.frame(width: 66)
                }
                .frame(height: pedalHeight)
            }
        }
    }

    private var brakePedal: some View {
        CarProPedal(title: "BRAKE", icon: "exclamationmark.octagon.fill", tint: Color(red: 0.95, green: 0.26, blue: 0.24),
                    amount: race.brake, hint: "Press higher up the pedal to brake harder") { race.brake = $0 }
            .accessibilityIdentifier("car-pro-brake")
    }

    private var throttlePedal: some View {
        CarProPedal(title: "THROTTLE", icon: "bolt.fill", tint: Color(red: 0.25, green: 0.85, blue: 0.42),
                    amount: race.throttle, hint: "Press higher up the pedal for more throttle") { race.throttle = $0 }
            .accessibilityIdentifier("car-pro-throttle")
    }
}

/// An analogue pedal: pressed lightly at its foot, flat out in its top
/// third, the fill showing how hard.
struct CarProPedal: View {
    let title: String
    let icon: String
    let tint: Color
    let amount: Double
    let hint: String
    let set: (Double) -> Void
    @State private var held = false

    var body: some View {
        GeometryReader { geo in
            let height = Double(geo.size.height)
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            ZStack(alignment: .bottom) {
                shape.fill(Color.black.opacity(0.5))
                Rectangle()
                    .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(height: geo.size.height * CGFloat(CarProMath.clamp(amount, 0, 1)))
                ticks
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(SR.Text.title(22))
                    Text(title)
                        .font(SR.Text.label(13))
                        .tracking(1.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(shape)
            .overlay(shape.stroke(held ? tint : Color.white.opacity(0.22), lineWidth: held ? 3 : 1.5))
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        held = true
                        set(CarProControlMath.pedal(touchY: Double(value.location.y), height: height))
                    }
                    .onEnded { _ in
                        held = false
                        set(0)
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel(title.capitalized)
        .accessibilityValue("\(Int((amount * 100).rounded())) percent")
        .accessibilityHint(hint)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(min(1, amount + 0.25))
            case .decrement: set(max(0, amount - 0.25))
            @unknown default: break
            }
        }
    }

    /// Three marks up the pedal: a quarter, a half, flat out.
    private var ticks: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(0..<3, id: \.self) { _ in
                Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .allowsHitTesting(false)
    }
}

/// A steering wheel on the screen: grab it anywhere and turn it; let go
/// and it centres.
struct CarProWheelControl: View {
    let steer: Double
    let set: (Double) -> Void
    /// The wheel's width and height, points.
    var side: CGFloat = 150
    @State private var turn: Double = 0
    @State private var lastAngle: Double?

    var body: some View {
        ZStack {
            CarProWheelArt()
                .frame(width: side, height: side)
                .rotationEffect(.radians(steer * CarProControlMath.wheelLock))
        }
        .frame(width: side, height: side)
        .contentShape(Circle())
        .gesture(turning)
        .accessibilityElement()
        .accessibilityLabel("Steering wheel")
        .accessibilityValue(spokenTurn)
        .accessibilityAdjustableAction { direction in adjust(direction) }
        .accessibilityIdentifier("car-pro-wheel")
    }

    private var spokenTurn: String {
        if steer < -0.05 { return "Left" }
        return steer > 0.05 ? "Right" : "Straight"
    }

    private var turning: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in dragged(to: value.location) }
            .onEnded { _ in released() }
    }

    /// The finger has moved round the wheel: turn it by the angle swept.
    private func dragged(to location: CGPoint) {
        let half = Double(side) / 2
        let dx = Double(location.x) - half, dy = Double(location.y) - half
        // Too near the hub to tell which way the finger is turning.
        guard dx * dx + dy * dy > 144 else { return }
        let angle = atan2(dy, dx)
        if let last = lastAngle {
            let limit = CarProControlMath.wheelLock * 1.05
            turn = CarProMath.clamp(turn + CarProControlMath.angleChange(from: last, to: angle), -limit, limit)
        }
        lastAngle = angle
        set(CarProControlMath.wheel(turn: turn))
    }

    private func released() {
        lastAngle = nil
        turn = 0
        set(0)
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: set(min(1, steer + 0.34))
        case .decrement: set(max(-1, steer - 0.34))
        @unknown default: break
        }
    }
}

/// The wheel itself: a rim, three spokes and a mark at the top.
struct CarProWheelArt: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.62), lineWidth: 22)
                .padding(11)
            Circle()
                .stroke(Color.white.opacity(0.85), lineWidth: 2)
                .padding(22)
            Capsule()
                .fill(Color.black.opacity(0.62))
                .frame(height: 14)
                .padding(.horizontal, 18)
            Capsule()
                .fill(Color.black.opacity(0.62))
                .frame(width: 14)
                .padding(.vertical, 18)
                .offset(y: 30)
            Circle()
                .fill(Color.black.opacity(0.75))
                .frame(width: 40, height: 40)
            Image(systemName: "steeringwheel")
                .font(SR.Text.title(16))
                .foregroundStyle(Color.white.opacity(0.8))
            VStack {
                Capsule()
                    .fill(Color(red: 0.95, green: 0.26, blue: 0.24))
                    .frame(width: 8, height: 18)
                    .padding(.top, 4)
                Spacer(minLength: 0)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Steering by sliding a thumb left and right from wherever it lands; let go
/// and the wheels straighten.
struct CarProSteerSlider: View {
    let steer: Double
    let set: (Double) -> Void
    @State private var held = false

    var body: some View {
        GeometryReader { geo in
            let width = Double(geo.size.width)
            let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
            ZStack {
                shape.fill(Color.black.opacity(0.5))
                HStack {
                    Image(systemName: "chevron.left.2")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right.2")
                }
                .font(SR.Text.title(18))
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.horizontal, 18)
                Circle()
                    .fill(Color.white.opacity(held ? 0.95 : 0.8))
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: "steeringwheel").font(SR.Text.title(18)).foregroundStyle(Color.black.opacity(0.7)))
                    .offset(x: CGFloat(steer * width * 0.38))
            }
            .overlay(shape.stroke(held ? Color.white.opacity(0.7) : Color.white.opacity(0.22), lineWidth: held ? 2.5 : 1.5))
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        held = true
                        set(CarProControlMath.slider(offset: Double(value.translation.width), width: width))
                    }
                    .onEnded { _ in
                        held = false
                        set(0)
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Steering")
        .accessibilityValue(steer < -0.05 ? "Left" : (steer > 0.05 ? "Right" : "Straight"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(min(1, steer + 0.34))
            case .decrement: set(max(-1, steer - 0.34))
            @unknown default: break
            }
        }
        .accessibilityIdentifier("car-pro-slider")
    }
}

/// A shift paddle: up or down a gear.
struct CarProPaddle: View {
    let up: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(systemName: up ? "plus" : "minus")
                    .font(SR.Text.title(20))
                Text(up ? "UP" : "DOWN")
                    .font(SR.Text.label(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Color.white)
            .frame(width: 58, height: 58)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(up ? "Shift up a gear" : "Shift down a gear")
        .accessibilityIdentifier(up ? "car-pro-shift-up" : "car-pro-shift-down")
    }
}

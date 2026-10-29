import SwiftUI

// Car Racer+ instruments over the circuit: the timing panel (place, lap,
// lap time, delta), the dashboard (speed, gear, rev bar with shift lights,
// the four tyres, the aids at work), the minimap, the start lights and the
// banners. They sit on smoked panels because the circuit under them is the
// same in light and dark mode.

enum CarProHUDStyle {
    static let panel = Color.black.opacity(0.55)
    static let rim = Color.white.opacity(0.16)
    static let dim = Color.white.opacity(0.62)
    static let good = Color(red: 0.30, green: 0.90, blue: 0.45)
    static let best = Color(red: 0.78, green: 0.45, blue: 1.0)
    static let warning = Color(red: 1.0, green: 0.80, blue: 0.25)
    static let bad = Color(red: 1.0, green: 0.35, blue: 0.32)

    static func tone(_ tone: CarProTone) -> Color {
        switch tone {
        case .neutral: return .white
        case .good: return good
        case .best: return best
        case .warning: return warning
        case .bad: return bad
        }
    }
}

extension View {
    /// A smoked panel over the circuit.
    func carProPanel(radius: CGFloat = 16) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(CarProHUDStyle.panel))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(CarProHUDStyle.rim, lineWidth: 1))
    }
}

/// Place, lap, the clock and the delta to the best lap.
struct CarProTimingPanel: View {
    let hud: CarProHUD
    let isRace: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if isRace {
                    Text("P\(hud.position)")
                        .font(SR.Text.figure(24))
                        .foregroundColor(hud.position == 1 ? CarProHUDStyle.warning : Color.white)
                    + Text("/\(hud.cars)")
                        .font(SR.Text.mono(13))
                        .foregroundColor(CarProHUDStyle.dim)
                }
                Text(lapText)
                    .font(SR.Text.label(12))
                    .tracking(1)
                    .foregroundStyle(CarProHUDStyle.dim)
                Spacer(minLength: 0)
                if !hud.lapValid {
                    Image(systemName: "xmark.octagon.fill")
                        .font(SR.Text.label(13))
                        .foregroundStyle(CarProHUDStyle.bad)
                        .accessibilityLabel("This lap will not count")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CarProFormat.time(hud.lapTime))
                    .font(SR.Text.figure(19))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let delta = hud.delta {
                    Text(CarProFormat.delta(delta))
                        .font(SR.monoBold(13))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(delta <= 0 ? CarProHUDStyle.good : CarProHUDStyle.bad))
                }
            }
            Text(footnote)
                .font(SR.Text.mono(12))
                .foregroundStyle(CarProHUDStyle.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .carProPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var lapText: String {
        hud.laps > 0 ? "LAP \(hud.lap)/\(hud.laps)" : "LAP \(hud.lap)"
    }

    private var footnote: String {
        if isRace, let ahead = hud.gapAhead {
            return "Ahead " + String(format: "%.1f s", abs(ahead)) + (hud.penalty > 0 ? " · +\(Int(hud.penalty)) s" : "")
        }
        if let corner = hud.nextCorner { return "Next: \(corner)" }
        return "Best " + CarProFormat.time(hud.bestLap)
    }

    private var spoken: String {
        var words = isRace ? "Position \(hud.position) of \(hud.cars). " : ""
        words += hud.laps > 0 ? "Lap \(hud.lap) of \(hud.laps). " : "Lap \(hud.lap). "
        words += "Lap time \(CarProFormat.time(hud.lapTime))."
        if let delta = hud.delta {
            words += delta <= 0 ? " \(String(format: "%.2f", -delta)) seconds up on your best."
                : " \(String(format: "%.2f", delta)) seconds down on your best."
        }
        return words
    }
}

/// Speed, gear, revs and the tyres: the dashboard over the pedals.
struct CarProDashboard: View {
    let hud: CarProHUD
    let mph: Bool
    let assists: CarProAssists
    let compound: CarProTyreCompound
    /// Flashes the shift lights at the limiter.
    let tick: Int

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(CarProPresent.speed(hud.speed, mph: mph))")
                    .font(SR.Text.figure(34))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(CarProPresent.speedUnit(mph: mph))
                    .font(SR.Text.label(12))
                    .tracking(1)
                    .foregroundStyle(CarProHUDStyle.dim)
            }
            .frame(minWidth: 66, alignment: .leading)
            Text(hud.gear)
                .font(SR.Text.hero(30))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(hud.shiftLight >= 0.98 ? Color.black : Color.white)
                .frame(width: 48, height: 52)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hud.shiftLight >= 0.98 ? CarProHUDStyle.warning : Color.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 6) {
                CarProRevBar(rpm: hud.rpm, redline: hud.redline, limiter: hud.limiter, shiftLight: hud.shiftLight,
                             flash: tick / 6 % 2 == 0)
                    .frame(height: 26)
                CarProAidLights(assists: assists, traction: hud.tractionActive, abs: hud.absActive)
            }
            CarProTyreWidget(temperatures: hud.tyreTemperatures, wear: hud.tyreWear, compound: compound)
                .frame(width: 40, height: 56)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .carProPanel(radius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(CarProPresent.speed(hud.speed, mph: mph)) \(CarProPresent.spokenUnit(mph: mph)), gear \(hud.gear)")
    }
}

/// The rev bar: green, then amber, then red to the limiter, with five
/// shift lights over it that fill as the change-up point comes and flash
/// at the limiter.
struct CarProRevBar: View {
    let rpm: Double
    let redline: Double
    let limiter: Double
    let shiftLight: Double
    let flash: Bool

    var body: some View {
        Canvas { context, size in
            let w = Double(size.width), h = Double(size.height)
            let segments = 20
            let gap = 2.0
            let segW = (w - gap * Double(segments - 1)) / Double(segments)
            let top = h * 0.36
            let fill = CarProMath.clamp(rpm / max(1, limiter), 0, 1)
            for i in 0..<segments {
                let start = Double(i) / Double(segments)
                let at = start * limiter
                let colour: Color = at > redline - 300 ? CarProHUDStyle.bad
                    : (at > redline - 1500 ? CarProHUDStyle.warning : CarProHUDStyle.good)
                let lit = start < fill
                let rect = CGRect(x: Double(i) * (segW + gap), y: top, width: segW, height: h - top)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(lit ? colour : Color.white.opacity(0.12)))
            }
            let lights = 5
            let lightW = (w - 4 * Double(lights - 1)) / Double(lights)
            let full = shiftLight >= 0.98
            for i in 0..<lights {
                let on = full ? flash : shiftLight > Double(i) / Double(lights)
                let colour: Color = full ? Color(red: 0.35, green: 0.6, blue: 1.0)
                    : (i < 2 ? CarProHUDStyle.good : (i < 4 ? CarProHUDStyle.warning : CarProHUDStyle.bad))
                let rect = CGRect(x: Double(i) * (lightW + 4), y: 0, width: lightW, height: top - 3)
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(on ? colour : Color.white.opacity(0.1)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The aids switched on, lit while they work.
struct CarProAidLights: View {
    let assists: CarProAssists
    let traction: Bool
    let abs: Bool

    var body: some View {
        HStack(spacing: 5) {
            if assists.traction { lamp("TC", on: traction) }
            if assists.abs { lamp("ABS", on: abs) }
            if !assists.autoGears { lamp("MAN", on: false) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var words: [String] = []
        if traction { words.append("traction control working") }
        if abs { words.append("anti-lock brakes working") }
        return words.isEmpty ? "" : words.joined(separator: ", ")
    }

    private func lamp(_ text: String, on: Bool) -> some View {
        Text(text)
            .font(SR.monoBold(12))
            .foregroundStyle(on ? Color.black : CarProHUDStyle.dim)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(on ? CarProHUDStyle.warning : Color.white.opacity(0.1)))
            .lineLimit(1)
            .fixedSize()
    }
}

/// The four tyres from above: blue cold, green in their window, red hot,
/// each filled to the tread it has left.
struct CarProTyreWidget: View {
    let temperatures: [Double]
    let wear: [Double]
    let compound: CarProTyreCompound

    static func colour(heat: Double) -> Color {
        if heat < 0 {
            let t = min(1, -heat * 1.6)
            return Color(red: 0.3 + 0.0 * t, green: 0.88 - 0.3 * t, blue: 0.45 + 0.55 * t)
        }
        let t = min(1, heat * 1.6)
        return Color(red: 0.3 + 0.7 * t, green: 0.88 - 0.55 * t, blue: 0.45 - 0.2 * t)
    }

    var body: some View {
        Canvas { context, size in
            let w = Double(size.width), h = Double(size.height)
            let chassis = CGRect(x: w * 0.3, y: h * 0.08, width: w * 0.4, height: h * 0.84)
            context.fill(Path(roundedRect: chassis, cornerRadius: 5), with: .color(Color.white.opacity(0.14)))
            let tw = w * 0.26, th = h * 0.34
            let spots: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: w - tw, y: 0),
                                    CGPoint(x: 0, y: h - th), CGPoint(x: w - tw, y: h - th)]
            for i in 0..<4 {
                let temperature = i < temperatures.count ? temperatures[i] : compound.optimalTemperature
                let worn = i < wear.count ? wear[i] : 0
                let colour = CarProTyreWidget.colour(heat: CarProPresent.tyreHeat(temperature, compound: compound))
                let rect = CGRect(x: Double(spots[i].x), y: Double(spots[i].y), width: tw, height: th)
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(colour.opacity(0.3)))
                let left = CarProMath.clamp(1 - worn, 0.05, 1)
                let tread = CGRect(x: rect.minX, y: rect.maxY - rect.height * left, width: rect.width, height: rect.height * left)
                context.fill(Path(roundedRect: tread, cornerRadius: 3), with: .color(colour))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let heats = temperatures.map { CarProPresent.tyreHeat($0, compound: compound) }
        let average = heats.isEmpty ? 0 : heats.reduce(0, +) / Double(heats.count)
        let worn = wear.max() ?? 0
        let state = average < -0.45 ? "cold" : (average > 0.45 ? "too hot" : "in their window")
        return "Tyres \(state), \(Int((worn * 100).rounded())) percent worn"
    }
}

/// The whole circuit small, with every car on it.
struct CarProMinimap: View {
    let world: CarProRaceWorld
    let tick: Int

    var body: some View {
        Canvas { context, size in
            let side = Double(min(size.width, size.height))
            let inset = 8.0
            let map = world.scene.map
            let outline = map.path(side: side, inset: inset)
            context.stroke(outline, with: .color(Color.black.opacity(0.6)), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
            context.stroke(outline, with: .color(Color.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
            let k = side - 2 * inset
            func place(_ p: CarProVec) -> CGPoint {
                let u = map.unit(p)
                return CGPoint(x: inset + Double(u.x) * k, y: inset + Double(u.y) * k)
            }
            let start = place(world.session.track.samples[0].centre)
            context.fill(Path(CGRect(x: start.x - 1.5, y: start.y - 4, width: 3, height: 8)), with: .color(CarProHUDStyle.warning))
            let session = world.session
            if let ghost = session.ghostPose {
                let g = place(ghost.position)
                context.stroke(Path(ellipseIn: CGRect(x: g.x - 3.5, y: g.y - 3.5, width: 7, height: 7)),
                               with: .color(Color(red: 0.6, green: 0.9, blue: 1)), lineWidth: 1.5)
            }
            for (i, racer) in session.racers.enumerated() where i != session.playerIndex {
                let p = place(racer.vehicle.position)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                             with: .color(CarProCarArt.livery(racer.entrant.hue)))
            }
            let me = place(session.player.vehicle.position)
            context.fill(Path(ellipseIn: CGRect(x: me.x - 5, y: me.y - 5, width: 10, height: 10)), with: .color(.white))
            context.fill(Path(ellipseIn: CGRect(x: me.x - 3, y: me.y - 3, width: 6, height: 6)),
                         with: .color(CarProCarArt.livery(session.player.entrant.hue)))
        }
        .carProPanel(radius: 16)
        .accessibilityHidden(true)
    }
}

/// The start gantry: five red lights on one by one, then out — go.
struct CarProStartLights: View {
    let lit: Int
    let out: Bool

    private static let red = Color(red: 1, green: 0.14, blue: 0.1)

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { index in
                    let on = !out && index < lit
                    VStack(spacing: 6) {
                        lamp(on: on)
                        lamp(on: on)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.07)))
                }
            }
            Text(out ? "GO!" : (lit == 0 ? "GET READY" : "\(lit)"))
                .font(SR.Text.hero(out ? 52 : 34))
                .foregroundStyle(out ? CarProHUDStyle.good : Color.white)
                .shadow(color: .black.opacity(0.6), radius: 4)
        }
        .padding(14)
        .carProPanel(radius: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(out ? "Go" : "Start lights, \(lit) of 5 on")
    }

    private func lamp(on: Bool) -> some View {
        Circle()
            .fill(on ? Self.red : Color(white: 0.2))
            .frame(width: 22, height: 22)
            .shadow(color: on ? Self.red.opacity(0.9) : .clear, radius: 8)
    }
}

/// A banner over the race: a sector, a lap, a warning.
struct CarProBannerView: View {
    let banner: CarProBanner

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner.icon)
                .font(SR.Text.title(18))
                .foregroundStyle(CarProHUDStyle.tone(banner.tone))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(banner.title.uppercased())
                    .font(SR.Text.label(14))
                    .tracking(1.2)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let detail = banner.detail {
                    Text(detail)
                        .font(SR.Text.mono(13))
                        .foregroundStyle(CarProHUDStyle.tone(banner.tone))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .overlay(Capsule().stroke(CarProHUDStyle.tone(banner.tone).opacity(0.5), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}

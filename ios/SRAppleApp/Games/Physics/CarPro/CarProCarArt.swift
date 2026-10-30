import SwiftUI

// Car Racer+ cars drawn from above, in the car's own frame (x forward, y to
// its right, metres): the same drawing on the circuit, in the garage and on
// the cards. Each model has its own nose and tail, the GT and the
// prototype their wings, and every car its livery, lights and, under hard
// braking, glowing discs.

/// How one car looks this frame.
struct CarProCarLook {
    var model: CarProCarModel
    var length: Double
    var width: Double
    /// Front axle ahead of the centre, rear behind it, and the track between the wheels.
    var toFront: Double
    var toRear: Double
    var trackWidth: Double
    /// Livery hue, 0…1.
    var hue: Double
    var steerAngle: Double = 0
    /// 0…1 pedal: the brake lights.
    var brake: Double = 0
    /// 0…1 glow of the front and rear discs.
    var glowFront: Double = 0
    var glowRear: Double = 0
    /// A translucent ghost of a best lap.
    var ghost = false

    init(model: CarProCarModel, length: Double, width: Double, toFront: Double, toRear: Double, trackWidth: Double,
         hue: Double) {
        self.model = model
        self.length = length
        self.width = width
        self.toFront = toFront
        self.toRear = toRear
        self.trackWidth = trackWidth
        self.hue = hue
    }

    /// A car as it stands in the garage.
    init(setup: CarProCarSetup, hue: Double? = nil) {
        let p = setup.params
        self.init(model: setup.model, length: p.length, width: p.width, toFront: p.toFront, toRear: p.toRear,
                  trackWidth: p.trackWidth, hue: hue ?? setup.model.hue)
    }

    /// A racer as it is on the circuit now.
    init(racer: CarProRacer) {
        let p = racer.params
        let v = racer.vehicle
        self.init(model: p.model, length: p.length, width: p.width, toFront: p.toFront, toRear: p.toRear,
                  trackWidth: p.trackWidth, hue: racer.entrant.hue)
        steerAngle = v.steerAngle
        brake = v.brake
        let glow = v.brakeGlow
        glowFront = glow.front
        glowRear = glow.rear
    }
}

enum CarProCarArt {
    static func livery(_ hue: Double) -> Color { Color(hue: hue, saturation: 0.78, brightness: 0.86) }
    static func liveryDark(_ hue: Double) -> Color { Color(hue: hue, saturation: 0.85, brightness: 0.52) }
    static func liveryLight(_ hue: Double) -> Color { Color(hue: hue, saturation: 0.45, brightness: 0.98) }

    /// How pinched the nose and tail are, 1 square … 0 a point.
    private static func taper(_ model: CarProCarModel) -> (nose: Double, tail: Double) {
        switch model {
        case .hatch: return (0.82, 0.92)
        case .roadster: return (0.6, 0.8)
        case .touring: return (0.8, 0.9)
        case .rally: return (0.78, 0.9)
        case .gt: return (0.58, 0.82)
        case .prototype: return (0.36, 0.72)
        }
    }

    /// The body's outline.
    static func body(_ model: CarProCarModel, length: Double, width: Double) -> Path {
        let hl = length / 2, hw = width / 2
        let t = taper(model)
        var p = Path()
        p.move(to: CGPoint(x: hl, y: -hw * t.nose))
        p.addQuadCurve(to: CGPoint(x: hl - length * 0.2, y: -hw), control: CGPoint(x: hl, y: -hw))
        p.addLine(to: CGPoint(x: -hl + length * 0.08, y: -hw))
        p.addQuadCurve(to: CGPoint(x: -hl, y: -hw * t.tail), control: CGPoint(x: -hl, y: -hw))
        p.addLine(to: CGPoint(x: -hl, y: hw * t.tail))
        p.addQuadCurve(to: CGPoint(x: -hl + length * 0.08, y: hw), control: CGPoint(x: -hl, y: hw))
        p.addLine(to: CGPoint(x: hl - length * 0.2, y: hw))
        p.addQuadCurve(to: CGPoint(x: hl, y: hw * t.nose), control: CGPoint(x: hl, y: hw))
        p.closeSubpath()
        return p
    }

    /// The shadow a car casts, drawn first and offset by the caller.
    static func shadow(_ look: CarProCarLook) -> Path {
        body(look.model, length: look.length * 1.02, width: look.width * 1.04)
    }

    /// Draws the car into `g`, already moved to the car and turned to its heading.
    static func draw(in g: inout GraphicsContext, look: CarProCarLook) {
        let L = look.length, W = look.width
        let hl = L / 2, hw = W / 2
        if look.ghost { g.opacity = 0.42 }
        drawWheels(in: g, look: look)

        let outline = body(look.model, length: L, width: W)
        let base = look.ghost ? Color(red: 0.75, green: 0.92, blue: 1.0) : livery(look.hue)
        let dark = look.ghost ? Color(red: 0.45, green: 0.70, blue: 0.85) : liveryDark(look.hue)
        let light = look.ghost ? Color.white : liveryLight(look.hue)
        let shade = Gradient(colors: [dark, base, light, base, dark])
        g.fill(outline, with: .linearGradient(shade, startPoint: CGPoint(x: 0, y: -hw), endPoint: CGPoint(x: 0, y: hw)))
        g.stroke(outline, with: .color(Color.black.opacity(0.45)), lineWidth: 0.06)

        // Two racing stripes nose to tail.
        if !look.ghost {
            var stripes = Path()
            stripes.addRect(CGRect(x: -hl + 0.1, y: -0.26, width: L - 0.2, height: 0.13))
            stripes.addRect(CGRect(x: -hl + 0.1, y: 0.13, width: L - 0.2, height: 0.13))
            var inside = g
            inside.clip(to: outline)
            inside.fill(stripes, with: .color(Color.white.opacity(0.78)))
        }
        drawCabin(in: g, look: look)
        drawAero(in: g, look: look)
        drawLights(in: g, look: look)
        if !look.ghost { drawGlow(in: g, look: look) }
    }

    private static func drawWheels(in g: GraphicsContext, look: CarProCarLook) {
        let tyre = Color(red: 0.07, green: 0.07, blue: 0.08)
        let side = look.width / 2 - 0.1
        let tyreL = look.model == .prototype ? 0.7 : 0.62
        let tyreW = look.model == .prototype ? 0.34 : 0.26
        let spots: [(Double, Double, Bool)] = [(look.toFront, -side, true), (look.toFront, side, true),
                                               (-look.toRear, -side, false), (-look.toRear, side, false)]
        for (x, y, front) in spots {
            var w = g
            w.translateBy(x: x, y: y)
            if front { w.rotate(by: .radians(look.steerAngle)) }
            let rect = CGRect(x: -tyreL / 2, y: -tyreW / 2, width: tyreL, height: tyreW)
            w.fill(Path(roundedRect: rect, cornerRadius: 0.08), with: .color(tyre))
        }
    }

    private static func drawCabin(in g: GraphicsContext, look: CarProCarLook) {
        let L = look.length, W = look.width
        let glass = Color(red: 0.10, green: 0.14, blue: 0.20)
        let shine = Color(red: 0.55, green: 0.70, blue: 0.85)
        switch look.model {
        case .prototype:
            // A teardrop canopy just ahead of the middle.
            let canopy = Path(ellipseIn: CGRect(x: -L * 0.12, y: -W * 0.17, width: L * 0.34, height: W * 0.34))
            g.fill(canopy, with: .color(glass))
            g.fill(Path(ellipseIn: CGRect(x: L * 0.06, y: -W * 0.08, width: L * 0.1, height: W * 0.1)),
                   with: .color(shine.opacity(0.6)))
        case .roadster:
            // Open-topped: a windscreen and two seats.
            var screen = Path()
            screen.addLines([CGPoint(x: L * 0.12, y: -W * 0.38), CGPoint(x: L * 0.17, y: -W * 0.3),
                             CGPoint(x: L * 0.17, y: W * 0.3), CGPoint(x: L * 0.12, y: W * 0.38)])
            screen.closeSubpath()
            g.fill(screen, with: .color(glass))
            for y in [-W * 0.18, W * 0.18] {
                g.fill(Path(roundedRect: CGRect(x: -L * 0.14, y: y - W * 0.12, width: L * 0.2, height: W * 0.24),
                            cornerRadius: 0.1), with: .color(Color(red: 0.12, green: 0.10, blue: 0.10)))
            }
        default:
            // A roof between the windscreen and the rear window.
            let front = look.model == .gt ? 0.02 : 0.12
            let back = look.model == .hatch ? -0.36 : (look.model == .gt ? -0.3 : -0.28)
            var screen = Path()
            screen.addLines([CGPoint(x: L * (front + 0.1), y: -W * 0.38), CGPoint(x: L * front, y: -W * 0.42),
                             CGPoint(x: L * front, y: W * 0.42), CGPoint(x: L * (front + 0.1), y: W * 0.38)])
            screen.closeSubpath()
            g.fill(screen, with: .color(glass))
            g.fill(Path(roundedRect: CGRect(x: L * back, y: -W * 0.4, width: L * (front - back), height: W * 0.8),
                        cornerRadius: 0.2), with: .color(Color.black.opacity(0.22)))
            var rear = Path()
            rear.addLines([CGPoint(x: L * back, y: -W * 0.38), CGPoint(x: L * (back - 0.06), y: -W * 0.34),
                           CGPoint(x: L * (back - 0.06), y: W * 0.34), CGPoint(x: L * back, y: W * 0.38)])
            rear.closeSubpath()
            g.fill(rear, with: .color(glass))
            g.fill(Path(CGRect(x: L * front + 0.02, y: -W * 0.3, width: L * 0.03, height: W * 0.25)),
                   with: .color(shine.opacity(0.5)))
        }
    }

    private static func drawAero(in g: GraphicsContext, look: CarProCarLook) {
        let L = look.length, W = look.width
        let wing = Color(red: 0.08, green: 0.08, blue: 0.10)
        switch look.model {
        case .gt:
            g.fill(Path(roundedRect: CGRect(x: -L / 2 + 0.05, y: -W * 0.46, width: 0.3, height: W * 0.92), cornerRadius: 0.05),
                   with: .color(wing))
        case .prototype:
            g.fill(Path(roundedRect: CGRect(x: -L / 2 - 0.12, y: -W * 0.5, width: 0.42, height: W), cornerRadius: 0.05),
                   with: .color(wing))
            g.fill(Path(roundedRect: CGRect(x: L / 2 - 0.3, y: -W * 0.48, width: 0.26, height: W * 0.96), cornerRadius: 0.05),
                   with: .color(wing))
        case .rally:
            g.fill(Path(roundedRect: CGRect(x: -L / 2 + 0.08, y: -W * 0.4, width: 0.24, height: W * 0.8), cornerRadius: 0.05),
                   with: .color(wing.opacity(0.85)))
        default:
            break
        }
    }

    private static func drawLights(in g: GraphicsContext, look: CarProCarLook) {
        let L = look.length, W = look.width
        let head = Color(red: 1.0, green: 0.97, blue: 0.82)
        for y in [-W * 0.36, W * 0.36] {
            g.fill(Path(roundedRect: CGRect(x: L / 2 - 0.22, y: y - 0.16, width: 0.16, height: 0.32), cornerRadius: 0.05),
                   with: .color(head))
        }
        let braking = look.brake > 0.08
        let tail = braking ? Color(red: 1.0, green: 0.12, blue: 0.10) : Color(red: 0.55, green: 0.05, blue: 0.05)
        for y in [-W * 0.36, W * 0.36] {
            let rect = CGRect(x: -L / 2 + 0.02, y: y - 0.18, width: 0.14, height: 0.36)
            g.fill(Path(roundedRect: rect, cornerRadius: 0.04), with: .color(tail))
            if braking && !look.ghost {
                let centre = CGPoint(x: -L / 2 - 0.1, y: y)
                let glow = Gradient(colors: [Color(red: 1, green: 0.15, blue: 0.1).opacity(0.75 * min(1, look.brake + 0.3)),
                                             Color(red: 1, green: 0.15, blue: 0.1).opacity(0)])
                g.fill(Path(ellipseIn: CGRect(x: centre.x - 0.9, y: centre.y - 0.9, width: 1.8, height: 1.8)),
                       with: .radialGradient(glow, center: centre, startRadius: 0, endRadius: 0.9))
            }
        }
    }

    /// Discs glowing orange through the wheels after hard braking.
    private static func drawGlow(in g: GraphicsContext, look: CarProCarLook) {
        let side = look.width / 2 - 0.1
        let axles: [(Double, Double)] = [(look.toFront, look.glowFront), (-look.toRear, look.glowRear)]
        for (x, glow) in axles where glow > 0.02 {
            for y in [-side, side] {
                let centre = CGPoint(x: x, y: y)
                let colours = Gradient(colors: [Color(red: 1, green: 0.55, blue: 0.1).opacity(0.85 * glow),
                                                Color(red: 1, green: 0.3, blue: 0.05).opacity(0)])
                g.fill(Path(ellipseIn: CGRect(x: x - 0.55, y: y - 0.55, width: 1.1, height: 1.1)),
                       with: .radialGradient(colours, center: centre, startRadius: 0, endRadius: 0.55))
            }
        }
    }
}

/// A car on its own, pointing up, for the garage and the cards.
struct CarProCarPortrait: View {
    let look: CarProCarLook
    /// Radians turned from pointing straight up (the showroom's turntable).
    var spin: Double = 0

    var body: some View {
        Canvas { context, size in
            let w = Double(size.width), h = Double(size.height)
            let scale = min(w / (look.width * 2.1), h / (look.length * 1.25))
            var g = context
            g.translateBy(x: w / 2, y: h / 2)
            g.rotate(by: .radians(-Double.pi / 2 + spin))
            g.scaleBy(x: scale, y: scale)
            var shadow = g
            shadow.translateBy(x: -0.15, y: 0.35)
            shadow.fill(CarProCarArt.shadow(look), with: .color(Color.black.opacity(0.25)))
            CarProCarArt.draw(in: &g, look: look)
        }
        .accessibilityHidden(true)
    }
}

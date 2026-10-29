import SwiftUI

// Hometowns' drawn pieces: the animals (mayors and advisors), the terrain of
// a site, the zone colours, a flag pennant, the confetti for a big moment and
// the big thumb-sized button labels the town screen uses.
//
// Everything is drawn with SwiftUI shapes and `Canvas`, so nothing needs the
// asset catalogue. The drawings are static: a `Canvas` here redraws only when
// its size or input changes, except the confetti, which runs on a
// `TimelineView(.animation)` for three seconds and then removes itself.

// MARK: - Animals

/// An animal face (`HometownsCritter`), drawn in a unit square.
struct HometownsCritterFace: View {
    let animal: String

    var body: some View {
        Canvas { context, size in
            HometownsCritterFace.draw(HometownsCritter.of(animal), in: context, size: size)
        }
        .accessibilityHidden(true)
    }

    // One function, top to bottom in painting order: ears, spines, head,
    // patch, stripes, eyes, cheeks, snout.
    static func draw(_ c: HometownsCritter, in context: GraphicsContext, size: CGSize) {
        let s: CGFloat = min(size.width, size.height)
        let ox: CGFloat = (size.width - s) / 2
        let oy: CGFloat = (size.height - s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: ox + (x - w / 2) * s, y: oy + (y - h / 2) * s, width: w * s, height: h * s))
        }
        func poly(_ points: [CGPoint]) -> Path {
            var path = Path()
            path.addLines(points)
            path.closeSubpath()
            return path
        }
        let head = Color(hex: c.head)
        let patch = Color(hex: c.patchColour)
        let snout = Color(hex: c.snoutColour)
        let earColour = c.stripes ? Color(hex: 0x55524D) : head
        let headPath = oval(0.5, 0.56, 0.68, 0.66)

        // Ears, behind the head.
        switch c.ears {
        case .pointy:
            context.fill(poly([p(0.16, 0.14), p(0.2, 0.5), p(0.45, 0.3)]), with: .color(earColour))
            context.fill(poly([p(0.84, 0.14), p(0.8, 0.5), p(0.55, 0.3)]), with: .color(earColour))
            context.fill(poly([p(0.21, 0.24), p(0.24, 0.43), p(0.37, 0.33)]), with: .color(patch))
            context.fill(poly([p(0.79, 0.24), p(0.76, 0.43), p(0.63, 0.33)]), with: .color(patch))
        case .round:
            context.fill(oval(0.25, 0.28, 0.24, 0.24), with: .color(earColour))
            context.fill(oval(0.75, 0.28, 0.24, 0.24), with: .color(earColour))
            context.fill(oval(0.26, 0.29, 0.12, 0.12), with: .color(c.stripes ? Color(hex: 0x2A2622) : patch))
            context.fill(oval(0.74, 0.29, 0.12, 0.12), with: .color(c.stripes ? Color(hex: 0x2A2622) : patch))
        case .long:
            context.fill(oval(0.37, 0.2, 0.15, 0.42), with: .color(earColour))
            context.fill(oval(0.63, 0.2, 0.15, 0.42), with: .color(earColour))
            context.fill(oval(0.37, 0.21, 0.07, 0.3), with: .color(snout.opacity(0.55)))
            context.fill(oval(0.63, 0.21, 0.07, 0.3), with: .color(snout.opacity(0.55)))
        case .tufts:
            context.fill(poly([p(0.2, 0.12), p(0.23, 0.38), p(0.42, 0.28)]), with: .color(earColour))
            context.fill(poly([p(0.8, 0.12), p(0.77, 0.38), p(0.58, 0.28)]), with: .color(earColour))
        case .none:
            break
        }

        // Spines (the hedgehog), a ring of points round the face.
        if c.spines {
            var spines = Path()
            let count = 22
            for i in 0..<(count * 2) {
                let angle = Double(i) * Double.pi / Double(count) - Double.pi / 2
                let r: CGFloat = i % 2 == 0 ? 0.47 : 0.36
                let point = p(0.5 + r * CGFloat(cos(angle)), 0.54 + r * CGFloat(sin(angle)))
                if i == 0 { spines.move(to: point) } else { spines.addLine(to: point) }
            }
            spines.closeSubpath()
            context.fill(spines, with: .color(head))
        }

        // The head, with a soft light on its upper left.
        context.fill(headPath, with: .color(c.spines ? patch : head))
        context.fill(oval(0.38, 0.38, 0.22, 0.12), with: .color(Color.white.opacity(0.16)))

        // The patch: a muzzle, a mask or a breast, kept inside the head.
        var inHead = context
        inHead.clip(to: headPath)
        switch c.patch {
        case .muzzle: inHead.fill(oval(0.5, 0.71, 0.42, 0.3), with: .color(patch))
        case .mask: if !c.spines { inHead.fill(oval(0.5, 0.58, 0.54, 0.5), with: .color(patch)) }
        case .bib: inHead.fill(oval(0.5, 0.84, 0.62, 0.36), with: .color(patch))
        case .none: break
        }
        if c.stripes {
            inHead.fill(oval(0.36, 0.44, 0.13, 0.44), with: .color(Color(hex: 0x2A2622)))
            inHead.fill(oval(0.64, 0.44, 0.13, 0.44), with: .color(Color(hex: 0x2A2622)))
        }

        // Eyes.
        let eye = c.paleEyes || c.stripes ? Color(hex: 0xF7F3EA) : Color(hex: 0x1E1A16)
        if c.bigEyes {
            let frog = c.snout == .smile
            let y: CGFloat = frog ? 0.36 : 0.5
            for x in [CGFloat(0.36), CGFloat(0.64)] {
                if frog { context.fill(oval(x, y, 0.26, 0.24), with: .color(head)) }
                context.fill(oval(x, y, 0.2, 0.2), with: .color(Color(hex: 0xFBF8F0)))
                context.fill(oval(x, y + 0.01, 0.1, 0.1), with: .color(Color(hex: 0x1E1A16)))
                context.fill(oval(x + 0.025, y - 0.015, 0.035, 0.035), with: .color(Color.white))
            }
        } else {
            for x in [CGFloat(0.39), CGFloat(0.61)] {
                context.fill(oval(x, 0.53, 0.075, 0.085), with: .color(eye))
                if !c.paleEyes && !c.stripes {
                    context.fill(oval(x + 0.015, 0.515, 0.025, 0.025), with: .color(Color.white.opacity(0.9)))
                }
            }
        }

        // Rosy cheeks on the furry ones.
        if c.snout == .nose || c.snout == .smile {
            context.fill(oval(0.27, 0.66, 0.1, 0.07), with: .color(Color(hex: 0xEE8FB5).opacity(0.4)))
            context.fill(oval(0.73, 0.66, 0.1, 0.07), with: .color(Color(hex: 0xEE8FB5).opacity(0.4)))
        }

        // The snout.
        let line = StrokeStyle(lineWidth: max(1, s * 0.025), lineCap: .round, lineJoin: .round)
        switch c.snout {
        case .nose:
            context.fill(oval(0.5, 0.66, 0.13, 0.09), with: .color(snout))
            var mouth = Path()
            mouth.move(to: p(0.43, 0.735))
            mouth.addQuadCurve(to: p(0.5, 0.725), control: p(0.465, 0.775))
            mouth.addQuadCurve(to: p(0.57, 0.735), control: p(0.535, 0.775))
            context.stroke(mouth, with: .color(Color(hex: 0x2A211C).opacity(0.55)), style: line)
        case .beak:
            context.fill(poly([p(0.43, 0.62), p(0.57, 0.62), p(0.5, 0.75)]), with: .color(snout))
        case .tallBeak:
            context.fill(poly([p(0.41, 0.6), p(0.59, 0.6), p(0.5, 0.83)]), with: .color(snout))
            context.fill(poly([p(0.44, 0.66), p(0.56, 0.66), p(0.545, 0.7), p(0.455, 0.7)]), with: .color(Color(hex: 0xF2C230)))
        case .wideBeak:
            let r = CGRect(x: ox + 0.32 * s, y: oy + 0.61 * s, width: 0.36 * s, height: 0.15 * s)
            context.fill(Path(roundedRect: r, cornerRadius: 0.075 * s), with: .color(snout))
            context.fill(oval(0.44, 0.65, 0.04, 0.025), with: .color(Color(hex: 0x2A211C).opacity(0.5)))
            context.fill(oval(0.56, 0.65, 0.04, 0.025), with: .color(Color(hex: 0x2A211C).opacity(0.5)))
        case .longBeak:
            context.fill(poly([p(0.54, 0.6), p(0.54, 0.69), p(0.99, 0.7)]), with: .color(snout))
            var stripe = Path()
            stripe.move(to: p(0.62, 0.46))
            stripe.addLine(to: p(0.86, 0.38))
            context.stroke(stripe, with: .color(Color(hex: 0x24272C)), style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))
        case .smile:
            var smile = Path()
            smile.move(to: p(0.3, 0.66))
            smile.addQuadCurve(to: p(0.7, 0.66), control: p(0.5, 0.8))
            context.stroke(smile, with: .color(snout), style: StrokeStyle(lineWidth: max(1.5, s * 0.035), lineCap: .round))
        }
    }
}

/// An animal on a round badge: a mayor on their flag colour, an advisor on theirs.
struct HometownsCritterBadge: View {
    let animal: String
    var ground: Color = SR.accent
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(ground)
            Circle().fill(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0)],
                                         startPoint: .top, endPoint: .center))
            HometownsCritterFace(animal: animal)
                .padding(size * 0.07)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.black.opacity(0.14), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// MARK: - Zones

/// The colour and symbol of each zone, the same on the Wants bar, the Build
/// trays and the demo's map drawing.
enum HometownsZoneStyle {
    static func colour(_ zone: String) -> Color {
        switch zone {
        case "homes": return Color(hex: 0xD9805E)
        case "shops": return Color(hex: 0x3F86CF)
        case "leisure": return Color(hex: 0xB96BC0)
        case "industry": return Color(hex: 0xB8902C)
        case "offices": return Color(hex: 0x6574C8)
        case "farms": return Color(hex: 0x7FAE45)
        default: return SR.accent
        }
    }

    static func icon(_ zone: String) -> String {
        switch zone {
        case "homes": return "house.fill"
        case "shops": return "bag.fill"
        case "leisure": return "theatermasks.fill"
        case "industry": return "gearshape.2.fill"
        case "offices": return "building.2.fill"
        case "farms": return "leaf.fill"
        default: return "square.fill"
        }
    }
}

// MARK: - Sites

/// A site's ground in miniature: the river, the coast, the hills, the forest or the flat.
struct HometownsSiteTile: View {
    let kind: String
    var taken = false

    var body: some View {
        Canvas { context, size in
            HometownsSiteTile.draw(kind, in: context, size: size)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.black.opacity(0.1), lineWidth: 1))
        .saturation(taken ? 0.15 : 1)
        .opacity(taken ? 0.55 : 1)
        .accessibilityHidden(true)
    }

    static func draw(_ kind: String, in context: GraphicsContext, size: CGSize) {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let all = Path(CGRect(origin: .zero, size: size))
        let grass = Color(hex: 0x9CC47A)
        let grassDark = Color(hex: 0x76A458)
        switch kind {
        case "river":
            context.fill(all, with: .color(grass))
            var river = Path()
            river.move(to: CGPoint(x: -4, y: h * 0.28))
            river.addCurve(to: CGPoint(x: w + 4, y: h * 0.74),
                           control1: CGPoint(x: w * 0.45, y: h * 0.02), control2: CGPoint(x: w * 0.5, y: h * 1.02))
            context.stroke(river, with: .color(Color(hex: 0x4F93C9)), style: StrokeStyle(lineWidth: h * 0.22, lineCap: .round))
            context.stroke(river, with: .color(Color.white.opacity(0.4)),
                           style: StrokeStyle(lineWidth: max(1, h * 0.035), lineCap: .round, dash: [h * 0.08, h * 0.16]))
        case "coast":
            context.fill(all, with: .color(Color(hex: 0xEAD7A4)))
            var sea = Path()
            sea.move(to: CGPoint(x: w * 0.42, y: h + 2))
            sea.addCurve(to: CGPoint(x: w + 2, y: h * 0.18),
                         control1: CGPoint(x: w * 0.62, y: h * 0.62), control2: CGPoint(x: w * 0.72, y: h * 0.3))
            sea.addLine(to: CGPoint(x: w + 2, y: h + 2))
            sea.closeSubpath()
            context.fill(sea, with: .color(Color(hex: 0x3D8FC4)))
            context.fill(Path(CGRect(x: 0, y: 0, width: w * 0.36, height: h * 0.5)), with: .color(grass.opacity(0.85)))
            for k in 0..<3 {
                var wave = Path()
                let y = h * (0.52 + CGFloat(k) * 0.16)
                let x = w * (0.66 + CGFloat(k) * 0.06)
                wave.move(to: CGPoint(x: x, y: y))
                wave.addQuadCurve(to: CGPoint(x: x + w * 0.18, y: y), control: CGPoint(x: x + w * 0.09, y: y - h * 0.07))
                context.stroke(wave, with: .color(Color.white.opacity(0.7)), style: StrokeStyle(lineWidth: max(1, h * 0.03), lineCap: .round))
            }
        case "hills":
            context.fill(all, with: .color(Color(hex: 0xB5D08E)))
            context.fill(Path(ellipseIn: CGRect(x: -w * 0.25, y: h * 0.42, width: w * 0.9, height: h * 0.9)), with: .color(grassDark))
            context.fill(Path(ellipseIn: CGRect(x: w * 0.35, y: h * 0.3, width: w * 0.9, height: h * 1.0)), with: .color(Color(hex: 0x86B266)))
            context.fill(Path(ellipseIn: CGRect(x: w * 0.55, y: h * 0.36, width: w * 0.3, height: h * 0.12)), with: .color(Color.white.opacity(0.25)))
        case "forest":
            context.fill(all, with: .color(Color(hex: 0x86B266)))
            let trees: [(CGFloat, CGFloat, CGFloat)] = [(0.2, 0.3, 0.2), (0.5, 0.22, 0.24), (0.8, 0.34, 0.2), (0.32, 0.66, 0.24),
                                                         (0.66, 0.7, 0.22), (0.9, 0.8, 0.18), (0.08, 0.84, 0.18)]
            for (x, y, r) in trees {
                let trunk = CGRect(x: w * x - w * 0.025, y: h * y, width: w * 0.05, height: h * r * 0.7)
                context.fill(Path(trunk), with: .color(Color(hex: 0x6B4E33)))
                let canopy = CGRect(x: w * (x - r / 2), y: h * (y - r / 2), width: w * r, height: h * r)
                context.fill(Path(ellipseIn: canopy), with: .color(Color(hex: 0x3F7A43)))
                context.fill(Path(ellipseIn: canopy.insetBy(dx: w * r * 0.22, dy: h * r * 0.22).offsetBy(dx: -w * r * 0.1, dy: -h * r * 0.1)),
                             with: .color(Color(hex: 0x58985A)))
            }
        default:
            context.fill(all, with: .color(grass))
            let bands = 5
            for k in 0..<bands where k % 2 == 0 {
                let y = h * CGFloat(k) / CGFloat(bands)
                context.fill(Path(CGRect(x: 0, y: y, width: w, height: h / CGFloat(bands))), with: .color(Color(hex: 0xC8DA8C)))
            }
            context.fill(Path(ellipseIn: CGRect(x: w * 0.62, y: h * 0.12, width: w * 0.22, height: h * 0.22)), with: .color(Color(hex: 0x3F7A43)))
        }
    }
}

// MARK: - Flags

/// A swallow-tailed pennant, for a town's flag.
struct HometownsPennant: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A flag on its pole.
struct HometownsFlagPole: View {
    let colour: Color
    var height: CGFloat = 34

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Capsule()
                .fill(Color(hex: 0x6B5A48))
                .frame(width: max(2, height * 0.07), height: height)
            HometownsPennant()
                .fill(colour)
                .overlay(HometownsPennant().stroke(Color.black.opacity(0.18), lineWidth: 1))
                .frame(width: height * 0.72, height: height * 0.46)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Big moments

/// Confetti falling for three seconds, then gone. Never shown under Reduce Motion (the caller checks).
struct HometownsConfetti: View {
    var colours: [Color] = [Color(hex: 0xD6463A), Color(hex: 0xF2C230), Color(hex: 0x5BA35B), Color(hex: 0x2F7FC1),
                            Color(hex: 0x8E5BB5), Color(hex: 0xEE8FB5)]
    @State private var start = Date()
    @State private var finished = false

    struct Piece {
        let x: Double
        let delay: Double
        let speed: Double
        let sway: Double
        let spin: Double
        let colour: Int
        let width: Double
    }

    /// The same shower every time: a small linear-congruential sequence, not `random()`.
    static let pieces: [Piece] = {
        var seed: UInt64 = 0x5EED_1234
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFF) / Double(0xFFFF)
        }
        var out: [Piece] = []
        for _ in 0..<64 {
            out.append(Piece(x: next(), delay: next() * 0.6, speed: 0.55 + next() * 0.45, sway: 0.5 + next() * 1.5,
                             spin: 2 + next() * 6, colour: Int(next() * 100), width: 6 + next() * 5))
        }
        return out
    }()

    var body: some View {
        Group {
            if !finished {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSince(start)
                        HometownsConfetti.draw(t: t, colours: colours, in: context, size: size)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            finished = true
        }
    }

    static func draw(t: Double, colours: [Color], in context: GraphicsContext, size: CGSize) {
        guard !colours.isEmpty else { return }
        for piece in pieces {
            let age = t - piece.delay
            if age < 0 { continue }
            let y = (-0.08 + age * piece.speed) * Double(size.height)
            if y > Double(size.height) + 20 { continue }
            let x = (piece.x + sin(age * piece.sway * 2) * 0.03) * Double(size.width)
            var ctx = context
            ctx.opacity = max(0, min(1, 3.0 - t))
            ctx.translateBy(x: CGFloat(x), y: CGFloat(y))
            ctx.rotate(by: .radians(age * piece.spin))
            let w = CGFloat(piece.width)
            ctx.fill(Path(CGRect(x: -w / 2, y: -w * 0.3, width: w, height: w * 0.6)),
                     with: .color(colours[piece.colour % colours.count]))
        }
    }
}

// MARK: - Big buttons

/// A button's label sized for a thumb: at least 56 pt tall once the button's
/// own padding is round it, in the app's tracked caps.
struct HometownsBigLabel: View {
    let title: String
    var icon: String? = nil
    var fill = false
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(SR.Text.title(16))
                    .accessibilityHidden(true)
            }
            Text(title.uppercased())
                .font(SR.Text.label(15))
                .tracking(1.1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: fill ? .infinity : nil, minHeight: height)
        .padding(.horizontal, 6)
    }
}

/// An icon-only button's label, a square thumb target. Give the button an
/// `accessibilityLabel`: the symbol is hidden from VoiceOver.
struct HometownsIconLabel: View {
    let icon: String
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 40

    var body: some View {
        Image(systemName: icon)
            .font(SR.Text.title(17))
            .frame(minWidth: side, minHeight: side)
            .accessibilityHidden(true)
    }
}

import SwiftUI

// The cards and the cloth they lie on, drawn in SwiftUI: no images, nothing
// in the asset catalogue. Sizes inside a card are fractions of its width,
// so a card reads the same on a 375-point phone and a big one. The play
// field's type is fixed to the card, not to the reader's text size: a card
// that grew with Dynamic Type would no longer fit its column.

/// Card colours. A card's face is paper-white in both modes (a touch dimmer
/// in dark, so a table of them does not glare); the suits are the classic
/// red and black, or four colours for telling suits apart at a glance.
enum SolitaireInk {
    static let face = Color(light: 0xFFFFFF, dark: 0xECEBF4)
    static let faceLow = Color(light: 0xF2F1F8, dark: 0xD9D7E6)
    static let edge = Color(hex: 0x15123A, alpha: 0.22)
    /// The hint's glow: a warm gold that shows on every cloth.
    static let hint = Color(hex: 0xFFD447)

    static func suit(_ suit: SolitaireSuit, fourColour: Bool) -> Color {
        switch suit {
        case .spades: return Color(hex: 0x15123A)
        case .hearts: return Color(hex: 0xC8102E)
        case .diamonds: return fourColour ? Color(hex: 0x1652B8) : Color(hex: 0xC8102E)
        case .clubs: return fourColour ? Color(hex: 0x16702F) : Color(hex: 0x15123A)
        }
    }

    static var faceFill: LinearGradient {
        LinearGradient(colors: [face, faceLow], startPoint: .top, endPoint: .bottom)
    }
}

extension SolitaireFelt {
    var base: Color {
        switch self {
        case .baize: return Color(hex: 0x0B4A31)
        case .midnight: return Color(hex: 0x14123A)
        case .plum: return Color(hex: 0x37143F)
        }
    }

    /// The light falling on the middle of the table.
    var glow: Color {
        switch self {
        case .baize: return Color(hex: 0x23925F)
        case .midnight: return Color(hex: 0x4B3FB8)
        case .plum: return Color(hex: 0x8E3C99)
        }
    }
}

/// The table: the cloth, lit from above, darker towards the edges.
struct SolitaireFeltView: View {
    let felt: SolitaireFelt

    var body: some View {
        ZStack {
            felt.base
            RadialGradient(colors: [felt.glow.opacity(0.85), felt.base.opacity(0)],
                           center: UnitPoint(x: 0.5, y: 0.32), startRadius: 8, endRadius: 560)
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.32)],
                           startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A card's face: the index in the top corner (rank then suit, all that
/// shows when it is fanned in a column), and a big pip, or a framed letter
/// for the court cards, in the middle.
struct SolitaireCardFace: View {
    let card: SolitaireCard
    let width: CGFloat
    let fourColour: Bool

    private var height: CGFloat { (width * SolitaireLayout.aspect).rounded() }
    private var radius: CGFloat { width * 0.12 }

    var body: some View {
        let ink = SolitaireInk.suit(card.suit, fourColour: fourColour)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack(alignment: .topLeading) {
            shape.fill(SolitaireInk.faceFill)
            shape.strokeBorder(fourColour ? ink.opacity(0.6) : SolitaireInk.edge, lineWidth: fourColour ? 1.5 : 0.8)
            corner(ink)
            middle(ink)
                .frame(width: width, height: height * 0.7)
                .offset(y: height * 0.27)
        }
        .frame(width: width, height: height)
    }

    private func corner(_ ink: Color) -> some View {
        HStack(alignment: .center, spacing: width * 0.02) {
            Text(card.rankLabel)
                .font(.system(size: width * (card.rank == 10 ? 0.27 : 0.31), weight: .heavy, design: .rounded))
                .tracking(card.rank == 10 ? -width * 0.03 : 0)
            Image(systemName: card.suit.symbolName)
                .font(.system(size: width * 0.21, weight: .bold))
        }
        .foregroundStyle(ink)
        .lineLimit(1)
        .fixedSize()
        .padding(.leading, width * 0.08)
        .padding(.top, width * 0.045)
    }

    @ViewBuilder
    private func middle(_ ink: Color) -> some View {
        if card.rank >= 11 {
            court(ink)
        } else {
            Image(systemName: card.suit.symbolName)
                .font(.system(size: width * (card.rank == 1 ? 0.62 : 0.46), weight: .regular))
                .foregroundStyle(ink)
        }
    }

    /// Jack, queen and king: a framed letter under a small emblem.
    private func court(_ ink: Color) -> some View {
        let frame = RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
        return ZStack {
            frame.fill(ink.opacity(0.09))
            frame.strokeBorder(ink.opacity(0.4), lineWidth: 1)
            VStack(spacing: 0) {
                Image(systemName: emblem)
                    .font(.system(size: width * 0.14, weight: .bold))
                Text(card.rankLabel)
                    .font(.system(size: width * 0.36, weight: .black, design: .serif))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: card.suit.symbolName)
                    .font(.system(size: width * 0.13, weight: .bold))
            }
            .foregroundStyle(ink)
        }
        .frame(width: width * 0.64, height: height * 0.52)
    }

    private var emblem: String {
        switch card.rank {
        case 13: return "crown.fill"
        case 12: return "sparkles"
        default: return "star.fill"
        }
    }
}

/// Diagonal lines both ways: the lattice on a card's back.
struct SolitaireLattice: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = max(rect.width / 4.5, 4)
        var x = -rect.height
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
            path.move(to: CGPoint(x: x + rect.height, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }
        return path
    }
}

/// A card's back, in the app's own colours: the games hue into the deep
/// accent, a lattice, an inner rule and the `sr` mark.
struct SolitaireCardBack: View {
    let width: CGFloat

    var body: some View {
        let height = (width * SolitaireLayout.aspect).rounded()
        let shape = RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
        let inner = shape.inset(by: width * 0.075)
        return ZStack {
            shape.fill(LinearGradient(colors: [SR.Hue.games.glow, SR.accentDeep],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            SolitaireLattice()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                .clipShape(inner)
            inner.strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("sr")
                    .font(.system(size: width * 0.27, weight: .heavy, design: .rounded))
                Circle()
                    .frame(width: width * 0.08, height: width * 0.08)
            }
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, width * 0.07)
            .padding(.vertical, width * 0.02)
            .background(Capsule().fill(Color.black.opacity(0.18)))
            shape.strokeBorder(Color.black.opacity(0.28), lineWidth: 0.6)
        }
        .frame(width: width, height: height)
    }
}

/// One card on the table: its face or its back, turning over in 3D when
/// that changes, with a shadow under it that lengthens when it is lifted.
///
/// The angle is the animated value (0 face up, 180 face down), so a card
/// that turns over mid-move flips smoothly with the move's own animation;
/// a card at rest is drawn flat, with no 3D transform at all.
struct SolitaireCardView: View, Animatable {
    var angle: Double
    let card: SolitaireCard
    let width: CGFloat
    let fourColour: Bool
    var lifted = false

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let height = (width * SolitaireLayout.aspect).rounded()
        let turning = angle > 0.5 && angle < 179.5
        let shape = RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
        return ZStack {
            // A shadow without a blur: cheap enough for fifty-two of them.
            shape
                .fill(Color.black.opacity(lifted ? 0.22 : 0.3))
                .frame(width: width, height: height)
                .scaleEffect(lifted ? 1.03 : 1)
                .offset(x: lifted ? 3 : 0, y: lifted ? 8 : 1.2)
            if angle < 90 {
                SolitaireCardFace(card: card, width: width, fourColour: fourColour)
            } else {
                SolitaireCardBack(width: width)
                    .scaleEffect(x: turning ? -1 : 1, y: 1)
            }
        }
        .frame(width: width, height: height)
        .rotation3DEffect(.degrees(turning ? angle : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}

/// A shake for a card that has nowhere to go: one unit of `phase` is three
/// quick wiggles, ending where it started.
struct SolitaireShake: GeometryEffect {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = sin(Double(phase) * .pi * 6) * 6
        return ProjectionTransform(CGAffineTransform(translationX: CGFloat(dx), y: 0))
    }
}

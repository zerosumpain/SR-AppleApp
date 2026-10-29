import SwiftUI

/// The board's colours. A game board keeps its own palette rather than the
/// app's tokens (grass is green in any theme), with a darker lawn at night so
/// it does not glare in dark mode.
struct SnakeBoardPaint {
    let grass: Color
    let grassAlt: Color
    let tuft: Color
    let hedge: Color
    let stoneTop: Color
    let stoneBottom: Color
    let stoneEdge: Color
    let rim: Color

    static func of(dark: Bool) -> SnakeBoardPaint {
        if dark {
            return SnakeBoardPaint(grass: Color(hex: 0x2F4F2A), grassAlt: Color(hex: 0x2A4826),
                                   tuft: Color(hex: 0x3D6535), hedge: Color(hex: 0x1B3117),
                                   stoneTop: Color(hex: 0x756A5C), stoneBottom: Color(hex: 0x4F473D),
                                   stoneEdge: Color(hex: 0x2E2924), rim: Color.white.opacity(0.10))
        }
        return SnakeBoardPaint(grass: Color(hex: 0xAAD46B), grassAlt: Color(hex: 0xA0CB60),
                               tuft: Color(hex: 0x86B44C), hedge: Color(hex: 0x5C8A34),
                               stoneTop: Color(hex: 0xBDAE99), stoneBottom: Color(hex: 0x918270),
                               stoneEdge: Color(hex: 0x675A4B), rim: Color.black.opacity(0.12))
    }
}

/// A colour for the snake: the body, its outline, and the stripe and shine.
struct SnakeSkinPaint {
    let main: Color
    let dark: Color
    let light: Color
    /// Drawn in a moving band of every colour instead of `main`.
    let rainbow: Bool

    static func of(_ skin: SnakeSkin) -> SnakeSkinPaint {
        switch skin {
        case .sky:
            return SnakeSkinPaint(main: Color(hex: 0x4C7DF0), dark: Color(hex: 0x2B50B0), light: Color(hex: 0xA6C2FF), rainbow: false)
        case .grape:
            return SnakeSkinPaint(main: Color(hex: 0x9A5CE4), dark: Color(hex: 0x6332A6), light: Color(hex: 0xD8BDFF), rainbow: false)
        case .sunset:
            return SnakeSkinPaint(main: Color(hex: 0xFF8B3D), dark: Color(hex: 0xC25414), light: Color(hex: 0xFFD6A8), rainbow: false)
        case .midnight:
            return SnakeSkinPaint(main: Color(hex: 0x313846), dark: Color(hex: 0x13161C), light: Color(hex: 0xF6CA4C), rainbow: false)
        case .rainbow:
            return SnakeSkinPaint(main: Color(hex: 0xFF5E7E), dark: Color(hex: 0x3A2A55), light: Color.white, rainbow: true)
        }
    }

    /// The colour `offset` along a rainbow body at time `now`.
    static func rainbowColour(_ offset: Double, now: Double) -> Color {
        let raw = offset * 0.055 - now * 0.22
        let hue = raw - floor(raw)
        return Color(hue: hue, saturation: 0.72, brightness: 0.96)
    }
}

/// Fixed colours the effects share.
enum SnakeInk {
    static let apple = Color(hex: 0xE8352C)
    static let appleLight = Color(hex: 0xFF7A68)
    static let appleDeep = Color(hex: 0x9E1B16)
    static let gold = Color(hex: 0xFFC83D)
    static let goldLight = Color(hex: 0xFFF2A8)
    static let goldDeep = Color(hex: 0xC98200)
    static let leaf = Color(hex: 0x4FA83A)
    static let stem = Color(hex: 0x6B4423)
    static let tongue = Color(hex: 0xE0245E)
}

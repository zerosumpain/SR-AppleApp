import SwiftUI

/// A colour as three numbers, so the sky can blend from one zone to the
/// next (iOS 17's `Color` cannot mix).
struct SkyHopperRGB: Equatable {
    let r: Double
    let g: Double
    let b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mixed(with other: SkyHopperRGB, _ t: Double) -> SkyHopperRGB {
        let t = min(1, max(0, t))
        return SkyHopperRGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    func scaled(_ k: Double) -> SkyHopperRGB { SkyHopperRGB(r: r * k, g: g * k, b: b * k) }

    var color: Color { Color(red: r, green: g, blue: b) }
}

/// The sky at a height: the gradient, how much starlight, how much sun.
/// The board keeps its own palette, as a window on the sky; at night (dark
/// mode) the same sky is a little deeper so it does not glare.
struct SkyHopperSkyPaint {
    let top: Color
    let bottom: Color
    /// 0 (none) to 1 (a sky full of stars).
    let starlight: Double
    /// 0 to 1: the sun low in the corner near the ground.
    let sun: Double

    private static let stops: [(metres: Double, top: SkyHopperRGB, bottom: SkyHopperRGB)] = [
        (0, SkyHopperRGB(0x5DB9F6), SkyHopperRGB(0xD3F1FF)),
        (150, SkyHopperRGB(0x4A9EEB), SkyHopperRGB(0xC3E6FF)),
        (400, SkyHopperRGB(0x6F6ED6), SkyHopperRGB(0xFFB98F)),
        (800, SkyHopperRGB(0x3C3F9F), SkyHopperRGB(0xC77FB9)),
        (1300, SkyHopperRGB(0x1F2668), SkyHopperRGB(0x4E52AA)),
        (2000, SkyHopperRGB(0x0C1034), SkyHopperRGB(0x262B62)),
    ]

    static func at(metres: Double, dark: Bool) -> SkyHopperSkyPaint {
        let stops = Self.stops
        var top = stops[0].top
        var bottom = stops[0].bottom
        for index in 1..<stops.count {
            let stop = stops[index]
            // Blend over the 120 m before each zone begins.
            let t = (metres - (stop.metres - 120)) / 120
            if t <= 0 { break }
            top = top.mixed(with: stop.top, t)
            bottom = bottom.mixed(with: stop.bottom, t)
        }
        let dim = dark ? 0.78 : 1
        let stars = min(1, max(0, (metres - 650) / 650))
        let sun = max(0, 1 - metres / 260)
        return SkyHopperSkyPaint(top: top.scaled(dim).color, bottom: bottom.scaled(dim).color,
                                 starlight: dark ? max(0.3, stars) : stars, sun: sun)
    }
}

/// Hop's colours: the body, its outline, and the belly and shine.
struct SkyHopperHopPaint {
    let main: Color
    let dark: Color
    let light: Color
    /// Drawn in shifting colours instead of `main`.
    let rainbow: Bool

    static func of(_ colour: SkyHopperColour) -> SkyHopperHopPaint {
        switch colour {
        case .sunny:
            return SkyHopperHopPaint(main: Color(hex: 0xFFC93C), dark: Color(hex: 0xC98A10), light: Color(hex: 0xFFF0B8), rainbow: false)
        case .mint:
            return SkyHopperHopPaint(main: Color(hex: 0x5ED6A4), dark: Color(hex: 0x2B9468), light: Color(hex: 0xC9F7E2), rainbow: false)
        case .berry:
            return SkyHopperHopPaint(main: Color(hex: 0xE25C9A), dark: Color(hex: 0xA02D66), light: Color(hex: 0xFFC6E0), rainbow: false)
        case .ocean:
            return SkyHopperHopPaint(main: Color(hex: 0x3E8BF0), dark: Color(hex: 0x1E55A8), light: Color(hex: 0xBFD8FF), rainbow: false)
        case .rainbow:
            return SkyHopperHopPaint(main: Color(hex: 0xFF6F91), dark: Color(hex: 0x6A3C8C), light: Color.white, rainbow: true)
        }
    }

    /// The rainbow body's colour at `now`.
    static func rainbowColour(now: Double) -> Color {
        let raw = now * 0.18
        return Color(hue: raw - floor(raw), saturation: 0.62, brightness: 0.98)
    }
}

/// Fixed colours for the clouds and the things in the sky.
enum SkyHopperInk {
    static let cloud = Color(hex: 0xFFFFFF)
    static let cloudShade = Color(hex: 0xD9E7F5)
    static let slide = Color(hex: 0xE6F5FF)
    static let slideShade = Color(hex: 0xADD6F2)
    static let streak = Color(hex: 0x8CC4EA)
    static let crumb = Color(hex: 0xFFEFD2)
    static let crumbShade = Color(hex: 0xE5C793)
    static let crack = Color(hex: 0xB0834A)
    static let blink = Color(hex: 0xF4F8FF)
    static let star = Color(hex: 0xFFD23F)
    static let starDeep = Color(hex: 0xE09A00)
    static let spring = Color(hex: 0x8A96A8)
    static let springTop = Color(hex: 0xFF5D5D)
    static let cap = Color(hex: 0x4F7CF7)
    static let capBand = Color(hex: 0xFFD23F)
    static let blade = Color(hex: 0xFF6B6B)
    static let bubble = Color(hex: 0x9BE7FF)
    static let magnet = Color(hex: 0xE8453C)
    static let magnetTip = Color(hex: 0xD7DEE8)
    static let hill = Color(hex: 0x8ED07A)
    static let hillFar = Color(hex: 0xB5E2A2)
    static let sun = Color(hex: 0xFFE58A)
    static let eye = Color(hex: 0x2A2340)
    static let cheek = Color(hex: 0xFF8FA3)
}

import SwiftUI
import UIKit

// The palette as the app's extensions see it.
//
// SHARED with the widget extension (`SRAppleLive`) and the share extension
// (`SRAppleShare`), see watch.yml: nothing here may reach for the app's own
// types. The app picks a palette (`SRPalette.swift`), resolves it, and leaves
// the few colours a widget or a Live Activity paints with on the Keychain
// shelf (`FamilyShelf`, account `.palette`); the extension reads them back
// here. A shelf with nothing on it — a build with no team, or an app that has
// not run since this shipped — reads as Prism.

/// A colour as the palette stores it: `0xRRGGBB`, sRGB.
///
/// The arithmetic the palette needs, PURE: WCAG luminance and contrast, a
/// mix, and a colour nudged until it reads.
enum SRRGB {
    static let white: UInt32 = 0xFFFFFF
    static let black: UInt32 = 0x000000

    /// WCAG 2.1 relative luminance.
    static func luminance(_ hex: UInt32) -> Double {
        func linear(_ channel: UInt32) -> Double {
            let value = Double(channel & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(hex >> 16) + 0.7152 * linear(hex >> 8) + 0.0722 * linear(hex)
    }

    /// WCAG contrast ratio, 1...21.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// `amount` of `a` over `b`, channel by channel.
    static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        let t = min(max(amount, 0), 1)
        var out: UInt32 = 0
        for shift: UInt32 in [16, 8, 0] {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            out |= UInt32((x * t + y * (1 - t)).rounded()) << shift
        }
        return out
    }

    /// `hex` pushed towards `toward` (black or white) in small steps until it
    /// reaches `ratio` against every one of `grounds` — the user's colour,
    /// kept as close to what they picked as legibility allows.
    static func legible(_ hex: UInt32, toward: UInt32, on grounds: [UInt32], ratio: Double = 4.5) -> UInt32 {
        var value = hex
        for step in 1...25 {
            if grounds.allSatisfy({ contrast(value, $0) >= ratio }) { return value }
            value = mix(toward, hex, Double(step) * 0.04)
        }
        return value
    }

    static func ui(_ hex: UInt32, alpha: Double = 1) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func color(_ hex: UInt32, alpha: Double = 1) -> Color {
        Color(uiColor: ui(hex, alpha: alpha))
    }

    /// A picked colour, back to a hex. Resolved for a light phone: a picker
    /// hands back a plain sRGB colour, so the trait changes nothing.
    static func hex(of color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}

/// A token's pair: its value on a light phone and on a dark one.
struct SRTone: Codable, Equatable, Hashable {
    var light: UInt32
    var dark: UInt32

    init(_ light: UInt32, _ dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    /// Follows the phone's appearance. A fresh `UIColor` per call, so a view
    /// built after the palette changed never holds the old one.
    func color(alpha: Double = 1) -> Color {
        Color(uiColor: ui(alpha: alpha))
    }

    func ui(alpha: Double = 1) -> UIColor {
        let light = SRRGB.ui(self.light, alpha: alpha), dark = SRRGB.ui(self.dark, alpha: alpha)
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
}

/// A feature's hue: the deeper stop, the brighter one, and the type on them.
struct SRHueSpec: Codable, Equatable, Hashable {
    var base: UInt32
    var glow: UInt32
    var onFill: UInt32

    /// The fill runs from `glow` to `base`; type is measured at its middle,
    /// which is where a tile's title sits. White while it holds 3:1 there —
    /// the vivid look — and the palette's dark ink on a fill too bright for
    /// it. (Prism shipped white on its green, orange and teal at 2.4–2.7:1.)
    init(base: UInt32, glow: UInt32, onFill: UInt32? = nil, dark ink: UInt32 = 0x15123A) {
        self.base = base
        self.glow = glow
        self.onFill = onFill ?? Self.typeColour(on: SRRGB.mix(base, glow, 0.5), ink: ink)
    }

    static func typeColour(on fill: UInt32, ink: UInt32) -> UInt32 {
        SRRGB.contrast(SRRGB.white, fill) >= 3 ? SRRGB.white : ink
    }

    /// One picked colour, made into a hue: the brighter stop is the same
    /// colour lifted towards white.
    static func from(_ picked: UInt32, ink: UInt32) -> SRHueSpec {
        SRHueSpec(base: picked, glow: SRRGB.mix(SRRGB.white, picked, 0.38), dark: ink)
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [SRRGB.color(glow), SRRGB.color(base)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// What a widget or a Live Activity paints with: the reading tokens and the
/// four hues their cards are filled with.
struct SRWidgetPalette: Codable, Equatable {
    var paper: SRTone
    var ink: SRTone
    var accent: SRTone
    var good: SRTone
    var error: SRTone
    var steps: SRHueSpec
    var tasks: SRHueSpec
    var family: SRHueSpec
    var trips: SRHueSpec

    /// Prism's own, for a shelf with nothing on it.
    static let prism = SRWidgetPalette(
        paper: SRTone(0xF4F3FB, 0x0B0A1C),
        ink: SRTone(0x15123A, 0xF4F3FB),
        accent: SRTone(0x5233F0, 0xA194FF),
        good: SRTone(0x0A8048, 0x4ADE80),
        error: SRTone(0xD7193F, 0xFF6B85),
        steps: SRHueSpec(base: 0xE85D00, glow: 0xFF9E2C, onFill: 0x15123A),
        tasks: SRHueSpec(base: 0xFFB800, glow: 0xFFE14D, onFill: 0x15123A),
        family: SRHueSpec(base: 0xE62E5C, glow: 0xFF7A59, onFill: 0xFFFFFF),
        trips: SRHueSpec(base: 0x1E63E9, glow: 0x2EC5FF, onFill: 0xFFFFFF)
    )
}

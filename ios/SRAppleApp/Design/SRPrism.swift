import SwiftUI

/// Prism's colour beyond the one accent: a vivid hue per feature and per
/// family member.
///
/// The Home dashboard is a wall of tiles and the family visualisations are a
/// handful of people drawn on one canvas. Both are read by colour before they
/// are read by label — "the coral tile is Family", "the blue thread is Sam" —
/// so the colours are fixed per thing, never picked per screen.
///
/// A tile's FILL is a two-stop gradient of its hue, and the type on it is
/// `onFill`: white on the deep hues, deep indigo on the two bright ones
/// (yellow and lime), where white would fail. Measured at the lighter stop,
/// where contrast is worst.
extension SR {
    struct Hue: Equatable {
        /// The deeper stop: text-safe under `onFill`, and the hue a line or a
        /// dot uses on the ground.
        let base: Color
        /// The brighter stop.
        let glow: Color
        /// Type on the fill.
        let onFill: Color

        var gradient: LinearGradient {
            LinearGradient(colors: [glow, base], startPoint: .topLeading, endPoint: .bottomTrailing)
        }

        /// The hue at 14%: a chip's or a track's ground.
        var wash: Color { base.opacity(0.14) }

        private static let white = Color.white
        private static let indigo = Color(hex: SR.Fixed.ink)

        static let family = Hue(base: Color(hex: 0xE62E5C), glow: Color(hex: 0xFF7A59), onFill: white)
        static let health = Hue(base: Color(hex: 0x0E9F5A), glow: Color(hex: 0x3DDC84), onFill: white)
        static let steps = Hue(base: Color(hex: 0xE85D00), glow: Color(hex: 0xFF9E2C), onFill: white)
        static let trips = Hue(base: Color(hex: 0x1E63E9), glow: Color(hex: 0x2EC5FF), onFill: white)
        static let tasks = Hue(base: Color(hex: 0xFFB800), glow: Color(hex: 0xFFE14D), onFill: indigo)
        static let backlog = Hue(base: Color(hex: 0xD6336C), glow: Color(hex: 0xFF8FB1), onFill: white)
        static let messages = Hue(base: Color(hex: 0x0B8A7A), glow: Color(hex: 0x2DD4BF), onFill: white)
        static let games = Hue(base: Color(hex: 0x7C3AED), glow: Color(hex: 0xC026D3), onFill: white)
        static let chat = Hue(base: Color(hex: 0x3B4BF5), glow: Color(hex: 0x6E8BFF), onFill: white)
        static let news = Hue(base: Color(hex: 0x0E7490), glow: Color(hex: 0x22C3DD), onFill: white)
        static let daydream = Hue(base: Color(hex: 0x9333EA), glow: Color(hex: 0xF472B6), onFill: white)
        static let flows = Hue(base: Color(hex: 0x4338CA), glow: Color(hex: 0x38BDF8), onFill: white)
        static let alerts = Hue(base: Color(hex: 0xDC2626), glow: Color(hex: 0xFB923C), onFill: white)
        static let wildmind = Hue(base: Color(hex: 0x15803D), glow: Color(hex: 0xA3E635), onFill: indigo)
        static let move = Hue(base: Color(hex: 0xE11D74), glow: Color(hex: 0xFF5FA2), onFill: white)
    }

    /// One colour per person, in a fixed order.
    ///
    /// Eight, chosen to stay apart from one another on both grounds, and none
    /// of them the accent — a person is never the thing the screen is asking
    /// you to press. A household larger than eight wraps; nobody's household
    /// is that large yet.
    enum PersonHue {
        static let all: [Color] = [
            Color(hex: 0xFF4D6D), // coral
            Color(hex: 0x2F80ED), // blue
            Color(hex: 0x12B76A), // green
            Color(hex: 0xF79009), // amber
            Color(hex: 0x9B51E0), // purple
            Color(hex: 0x06AED4), // cyan
            Color(hex: 0xEE46BC), // pink
            Color(hex: 0x84CC16), // lime
        ]

        /// A colour per subject, stable for as long as the household is: the
        /// subjects sorted, each taking the next colour. Sorting by subject
        /// rather than by the list's order means a person keeps their colour
        /// when somebody else starts or stops sharing.
        static func assign(_ subjects: [String]) -> [String: Color] {
            var out: [String: Color] = [:]
            for (index, subject) in Array(Set(subjects)).sorted().enumerated() {
                out[subject] = all[index % all.count]
            }
            return out
        }
    }
}

// MARK: - The Prism ground

/// The bright ground under a dashboard: the page colour with three soft
/// fields of hue drifting under the glass.
///
/// iOS 18 draws it as a `MeshGradient` — one draw, no blur, so scrolling over
/// it costs nothing — and earlier phones get the same fields as radial
/// gradients. Static: nothing here animates while the screen is idle (the app
/// has run hot before, and a moving background is the first thing to blame).
struct SRPrismGround: View {
    var hues: [SR.Hue] = [.family, .trips, .daydream]
    /// 1 for a dashboard; less for a screen you read.
    var scale: Double = 1
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let strength = (scheme == .dark ? 0.30 : 0.20) * scale
        ZStack {
            SR.paper
            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.45], [0.6, 0.4], [1, 0.55],
                        [0, 1], [0.45, 1], [1, 1],
                    ],
                    colors: [
                        hue(0).opacity(strength), .clear, hue(1).opacity(strength * 0.9),
                        .clear, hue(2).opacity(strength * 0.5), .clear,
                        hue(1).opacity(strength * 0.6), .clear, hue(0).opacity(strength * 0.7),
                    ]
                )
            } else {
                RadialGradient(colors: [hue(0).opacity(strength), .clear], center: .topLeading, startRadius: 0, endRadius: 420)
                RadialGradient(colors: [hue(1).opacity(strength), .clear], center: .topTrailing, startRadius: 0, endRadius: 380)
                RadialGradient(colors: [hue(2).opacity(strength * 0.6), .clear], center: .bottom, startRadius: 0, endRadius: 420)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func hue(_ index: Int) -> Color {
        hues.isEmpty ? SR.accent : hues[index % hues.count].glow
    }
}

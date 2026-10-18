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
/// `onFill`: white wherever white holds 3:1 at the gradient's middle, and the
/// palette's dark ink on the brighter fills (`SRHueSpec.typeColour`). Every hue
/// comes from the reader's palette (`SRPalette.swift`).
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

        // The reader's palette (`SRPalette.swift`): Prism's values unless
        // they picked another, or re-picked this one feature's colour.
        static var family: Hue { SRPaint.current.hue(.family) }
        static var health: Hue { SRPaint.current.hue(.health) }
        static var steps: Hue { SRPaint.current.hue(.steps) }
        static var trips: Hue { SRPaint.current.hue(.trips) }
        static var tasks: Hue { SRPaint.current.hue(.tasks) }
        static var backlog: Hue { SRPaint.current.hue(.backlog) }
        static var messages: Hue { SRPaint.current.hue(.messages) }
        static var games: Hue { SRPaint.current.hue(.games) }
        static var chat: Hue { SRPaint.current.hue(.chat) }
        static var news: Hue { SRPaint.current.hue(.news) }
        static var daydream: Hue { SRPaint.current.hue(.daydream) }
        static var flows: Hue { SRPaint.current.hue(.flows) }
        static var alerts: Hue { SRPaint.current.hue(.alerts) }
        static var wildmind: Hue { SRPaint.current.hue(.wildmind) }
        static var move: Hue { SRPaint.current.hue(.move) }
    }

    /// One colour per person, in a fixed order.
    ///
    /// Eight per palette, chosen to stay apart from one another on both
    /// grounds, and none of them the accent — a person is never the thing the
    /// screen is asking you to press. A household larger than eight wraps; nobody's household
    /// is that large yet.
    enum PersonHue {
        static var all: [Color] { SRPaint.current.people }

        /// A colour per subject, stable for as long as the household is: the
        /// subjects sorted, each taking the next colour. Sorting by subject
        /// rather than by the list's order means a person keeps their colour
        /// when somebody else starts or stops sharing.
        static func assign(_ subjects: [String]) -> [String: Color] {
            let colours = all
            var out: [String: Color] = [:]
            for (index, subject) in Array(Set(subjects)).sorted().enumerated() {
                out[subject] = colours[index % colours.count]
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
        let strength = (scheme == .dark ? 0.30 : 0.20) * scale * SRPaint.current.glow
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

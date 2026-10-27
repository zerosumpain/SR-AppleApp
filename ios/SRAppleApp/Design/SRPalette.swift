import SwiftUI
import UIKit
import WidgetKit

/// The reader's colours.
///
/// Prism (2026-10-18) gave the app one bright palette. John liked the layout
/// and not every colour in it, so the palette is now a CHOICE: fourteen whole
/// palettes (six at first, eight more on 2026-10-27), each tuned so every
/// reading token holds WCAG AA on its grounds in both modes, and on top of
/// whichever is chosen the reader may re-pick any feature's hue and the
/// accent. A re-picked accent is nudged darker (light mode) or lighter (dark
/// mode) until it reads; a re-picked hue picks its own type colour. So no
/// choice the reader makes can produce an unreadable screen — `PaletteTests`
/// holds every preset to the same floors.
///
/// How a change reaches the screen: `SR`'s tokens read `SRPaint.current`, and
/// the store bumps `epoch`, which `ContentView` uses as the tab view's
/// identity — a fresh set of screens in the new colours, with the router's
/// paths (and so wherever the reader was) kept. The Colours sheet sits OUTSIDE
/// that identity, so it stays put while the app redraws behind it.
extension SR {
    /// Which feature a hue belongs to.
    enum HueKey: String, CaseIterable, Codable, Identifiable {
        case family, health, steps, trips, tasks, backlog, messages, games, chat, news, daydream, flows, alerts, wildmind, move

        var id: String { rawValue }

        var title: String {
            switch self {
            case .family: return "Family"
            case .health: return "Health"
            case .steps: return "Steps"
            case .trips: return "Trips"
            case .tasks: return "Tasks"
            case .backlog: return "Backlog"
            case .messages: return "Messages"
            case .games: return "Games"
            case .chat: return "Ask jkai"
            case .news: return "News"
            case .daydream: return "Daydream"
            case .flows: return "Flows"
            case .alerts: return "Alerts"
            case .wildmind: return "Wildmind"
            case .move: return "Move ring"
            }
        }
    }
}

/// One whole palette: grounds, type, accents, a hue per feature, a colour per
/// person, and the app icon that goes with it.
struct SRPalette: Identifiable, Equatable {
    let id: String
    let name: String
    let blurb: String
    let paper: SRTone
    let surface: SRTone
    let ink: SRTone
    let inkSecondary: SRTone
    let accent: SRTone
    let accentDeep: SRTone
    let accentInk: SRTone
    let good: SRTone
    let warn: SRTone
    let error: SRTone
    let hues: [SR.HueKey: SRHueSpec]
    let people: [UInt32]
    /// The alternate icon's name in the asset catalogue; nil is the primary.
    let icon: String?
    /// The icon's ground, corner by corner (top-left, top-right, bottom-left,
    /// bottom-right) — the picker draws it rather than shipping a thumbnail.
    let iconGround: [UInt32]
    /// The mark and the bar under it on that icon.
    var iconInk: UInt32 = SRRGB.white
    var iconBar: UInt32 = SRRGB.white

    func hue(_ key: SR.HueKey) -> SRHueSpec {
        hues[key] ?? SRHueSpec(base: accent.light, glow: SRRGB.mix(SRRGB.white, accent.light, 0.38), dark: ink.light)
    }

    // MARK: - Resolving a choice

    /// The chosen preset with the reader's own colours laid over it. PURE.
    static func resolve(_ choice: SRPaletteChoice) -> SRPalette {
        let base = preset(choice.preset)
        var hues = base.hues
        for (raw, picked) in choice.hues[base.id] ?? [:] {
            guard let key = SR.HueKey(rawValue: raw) else { continue }
            hues[key] = SRHueSpec.from(picked, ink: base.ink.light)
        }
        var accent = base.accent, deep = base.accentDeep
        if let picked = choice.accent[base.id] {
            (accent, deep) = derivedAccent(picked, in: base)
        }
        return SRPalette(
            id: base.id, name: base.name, blurb: base.blurb,
            paper: base.paper, surface: base.surface, ink: base.ink, inkSecondary: base.inkSecondary,
            accent: accent, accentDeep: deep, accentInk: base.accentInk,
            good: base.good, warn: base.warn, error: base.error,
            hues: hues, people: base.people, icon: base.icon, iconGround: base.iconGround,
            iconInk: base.iconInk, iconBar: base.iconBar
        )
    }

    /// A picked accent made legible: darker on the light grounds, lighter on
    /// the dark ones and the band, and a deeper stop for a fill that carries
    /// paper type. PURE.
    static func derivedAccent(_ picked: UInt32, in palette: SRPalette) -> (accent: SRTone, deep: SRTone) {
        let light = SRRGB.legible(picked, toward: SRRGB.black, on: [palette.paper.light, palette.surface.light])
        let deepLight = SRRGB.legible(SRRGB.mix(SRRGB.black, light, 0.12), toward: SRRGB.black, on: [palette.paper.light, SRRGB.white])
        let dark = SRRGB.legible(picked, toward: SRRGB.white, on: [palette.paper.dark, palette.surface.dark, palette.ink.light])
        return (SRTone(light, dark), SRTone(deepLight, dark))
    }

    static func preset(_ id: String) -> SRPalette {
        presets.first { $0.id == id } ?? prism
    }

    /// What the Watch needs of this palette: always dark, so the dark page,
    /// the lifted partners, and a bright stop for each of Today's rings.
    var watch: WatchPalette {
        WatchPalette(
            ground: paper.dark, cream: paper.light, accent: accent.dark, good: good.dark, warn: warn.dark,
            bad: error.dark, move: hue(.move).glow, recovery: hue(.health).glow, readiness: accent.dark
        )
    }

    /// What a widget or Live Activity needs of this palette.
    var widget: SRWidgetPalette {
        SRWidgetPalette(
            paper: paper, ink: ink, accent: accent, good: good, error: error,
            steps: hue(.steps), tasks: hue(.tasks), family: hue(.family), trips: hue(.trips)
        )
    }
}

// MARK: - The presets

extension SRPalette {
    static let presets: [SRPalette] = [
        prism, sherbet, ocean, sunset, meadow, classic,
        candy, citrus, berry, lavender, arctic, forest, terracotta, graphite,
    ]

    private static func hues(_ ink: UInt32, _ list: [(SR.HueKey, UInt32, UInt32)]) -> [SR.HueKey: SRHueSpec] {
        var out: [SR.HueKey: SRHueSpec] = [:]
        for (key, base, glow) in list {
            out[key] = SRHueSpec(base: base, glow: glow, dark: ink)
        }
        return out
    }

    /// Electric violet on a cool near-white: the 2026-10-18 redesign.
    static let prism = SRPalette(
        id: "prism", name: "Prism", blurb: "Electric violet, every feature its own bright hue",
        paper: SRTone(0xF4F3FB, 0x0B0A1C), surface: SRTone(0xFFFFFF, 0x1A1838),
        ink: SRTone(0x15123A, 0xF4F3FB), inkSecondary: SRTone(0x45417A, 0xC8C4EE),
        accent: SRTone(0x5233F0, 0xA194FF), accentDeep: SRTone(0x4426D6, 0xA194FF),
        accentInk: SRTone(0x087078, 0x4FD8E0), good: SRTone(0x0A8048, 0x4ADE80),
        warn: SRTone(0x9A5B00, 0xFFC24B), error: SRTone(0xD7193F, 0xFF6B85),
        hues: hues(0x15123A, [
            (.family, 0xE62E5C, 0xFF7A59), (.health, 0x0E9F5A, 0x3DDC84), (.steps, 0xE85D00, 0xFF9E2C),
            (.trips, 0x1E63E9, 0x2EC5FF), (.tasks, 0xFFB800, 0xFFE14D), (.backlog, 0xD6336C, 0xFF8FB1),
            (.messages, 0x0B8A7A, 0x2DD4BF), (.games, 0x7C3AED, 0xC026D3), (.chat, 0x3B4BF5, 0x6E8BFF),
            (.news, 0x0E7490, 0x22C3DD), (.daydream, 0x9333EA, 0xF472B6), (.flows, 0x4338CA, 0x38BDF8),
            (.alerts, 0xDC2626, 0xFB923C), (.wildmind, 0x15803D, 0xA3E635), (.move, 0xE11D74, 0xFF5FA2),
        ]),
        people: [0xFF4D6D, 0x2F80ED, 0x12B76A, 0xF79009, 0x9B51E0, 0x06AED4, 0xEE46BC, 0x84CC16],
        icon: nil, iconGround: [0xFF7A59, 0xF472B6, 0x7C3AED, 0x3B4BF5]
    )

    /// Warm cream and soft fruit colours: bright without shouting.
    static let sherbet = SRPalette(
        id: "sherbet", name: "Sherbet", blurb: "Warm cream, soft fruit colours, a tangerine accent",
        paper: SRTone(0xFFF6EE, 0x1C1311), surface: SRTone(0xFFFFFF, 0x2A1D1A),
        ink: SRTone(0x2D1B14, 0xFFF6EE), inkSecondary: SRTone(0x6A4A3C, 0xE8CFC2),
        accent: SRTone(0xC2410C, 0xFF9A6B), accentDeep: SRTone(0xA8360A, 0xFF9A6B),
        accentInk: SRTone(0x0F766E, 0x5EEAD4), good: SRTone(0x15803D, 0x4ADE80),
        warn: SRTone(0x9A5B00, 0xFFC24B), error: SRTone(0xC81E3C, 0xFF7A8A),
        hues: hues(0x2D1B14, [
            (.family, 0xF2545B, 0xFF9A8B), (.health, 0x1A9E62, 0x6EE7A8), (.steps, 0xF26B0F, 0xFFB85C),
            (.trips, 0x3D6FF2, 0x7CC4FF), (.tasks, 0xFFC53D, 0xFFE58A), (.backlog, 0xE8457F, 0xFF9CC0),
            (.messages, 0x0F9E8E, 0x7FE3D3), (.games, 0x8B50F0, 0xD4A5FF), (.chat, 0x5160F5, 0x9AA8FF),
            (.news, 0x1693B3, 0x7FD8EB), (.daydream, 0xB04EE0, 0xF5A3D9), (.flows, 0x5B4FE0, 0x8FD3FF),
            (.alerts, 0xE53E3E, 0xFDA27A), (.wildmind, 0x3E9A45, 0xC5E86C), (.move, 0xF23F80, 0xFF9EC0),
        ]),
        people: [0xFF6B6B, 0x4D96FF, 0x2BC48A, 0xFFA62B, 0xA66CFF, 0x22C1E3, 0xFF6FB5, 0x9BD14A],
        icon: "AppIcon-Sherbet", iconGround: [0xFFB85C, 0xFF9A8B, 0xF2545B, 0xB04EE0]
    )

    /// Sea blues and teals, with a coral family so the people still stand out.
    static let ocean = SRPalette(
        id: "ocean", name: "Ocean", blurb: "Sea blues and teals, a coral family",
        paper: SRTone(0xEEF5FA, 0x07131F), surface: SRTone(0xFFFFFF, 0x102233),
        ink: SRTone(0x0B2540, 0xEEF5FA), inkSecondary: SRTone(0x3B5670, 0xB9CDE0),
        accent: SRTone(0x0B5FD6, 0x6CB2FF), accentDeep: SRTone(0x0A4FB3, 0x6CB2FF),
        accentInk: SRTone(0x0E7C72, 0x4FE0C8), good: SRTone(0x0A7A45, 0x4ADE80),
        warn: SRTone(0x935A00, 0xFFC24B), error: SRTone(0xC8243F, 0xFF7A8A),
        hues: hues(0x0B2540, [
            (.family, 0xF2594B, 0xFFA07A), (.health, 0x0B8F63, 0x4ADE9C), (.steps, 0x0B8EA0, 0x5EEAD4),
            (.trips, 0x2563EB, 0x60A5FA), (.tasks, 0xF4B400, 0xFFE066), (.backlog, 0x5B63E8, 0xB4B9FF),
            (.messages, 0x0779A0, 0x67E8F9), (.games, 0x6D28D9, 0xA78BFA), (.chat, 0x1D4ED8, 0x3B82F6),
            (.news, 0x0F766E, 0x2DD4BF), (.daydream, 0x5050C8, 0xC4B5FD), (.flows, 0x03649A, 0x38BDF8),
            (.alerts, 0xE11D48, 0xFB7185), (.wildmind, 0x15803D, 0x86EFAC), (.move, 0x0270B0, 0x7DD3FC),
        ]),
        people: [0xFF6B5B, 0x1E88E5, 0x00A884, 0xF2A900, 0x7E57C2, 0x00ACC1, 0xD81B60, 0x7CB342],
        icon: "AppIcon-Ocean", iconGround: [0x5EEAD4, 0x60A5FA, 0x0B8EA0, 0x1D4ED8]
    )

    /// Pinks, oranges and violets: the evening sky.
    static let sunset = SRPalette(
        id: "sunset", name: "Sunset", blurb: "Pinks, oranges and violets, a raspberry accent",
        paper: SRTone(0xFFF3EF, 0x1A0D14), surface: SRTone(0xFFFFFF, 0x2B1622),
        ink: SRTone(0x2A0E1F, 0xFFF3EF), inkSecondary: SRTone(0x6B3A55, 0xF0C8DA),
        accent: SRTone(0xC21858, 0xFF7AA8), accentDeep: SRTone(0xA3124A, 0xFF7AA8),
        accentInk: SRTone(0x6D28D9, 0xC4A5FF), good: SRTone(0x0F7A43, 0x4ADE80),
        warn: SRTone(0x9A5B00, 0xFFC24B), error: SRTone(0xC81E1E, 0xFF7A7A),
        hues: hues(0x2A0E1F, [
            (.family, 0xE8334F, 0xFF8A65), (.health, 0x1A8F5E, 0x7EE2A8), (.steps, 0xEA6A0C, 0xFDBA74),
            (.trips, 0xD12A78, 0xF9A8D4), (.tasks, 0xFBBF24, 0xFDE68A), (.backlog, 0xB8185A, 0xF472B6),
            (.messages, 0xDA5A0B, 0xFFA94D), (.games, 0x9333EA, 0xE879F9), (.chat, 0x7C3AED, 0xC084FC),
            (.news, 0xBE3F0C, 0xFB923C), (.daydream, 0xA21CAF, 0xF0ABFC), (.flows, 0x6D28D9, 0xF472B6),
            (.alerts, 0xDC2626, 0xF87171), (.wildmind, 0x5E9410, 0xBEF264), (.move, 0xE03A8A, 0xFDA4AF),
        ]),
        people: [0xF43F5E, 0x6366F1, 0x10B981, 0xF59E0B, 0xA855F7, 0x0EA5E9, 0xEC4899, 0x84CC16],
        icon: "AppIcon-Sunset", iconGround: [0xFDBA74, 0xFF8A65, 0xE03A8A, 0x7C3AED]
    )

    /// Leaf greens and earth: the calmest of the first six.
    static let meadow = SRPalette(
        id: "meadow", name: "Meadow", blurb: "Leaf greens and earth tones, calm and soft",
        paper: SRTone(0xF3F6EC, 0x0E140C), surface: SRTone(0xFFFFFF, 0x1A2416),
        ink: SRTone(0x1C2A16, 0xF3F6EC), inkSecondary: SRTone(0x4A5A3E, 0xCBD8BC),
        accent: SRTone(0x2F6B1F, 0x9BD67A), accentDeep: SRTone(0x285C1A, 0x9BD67A),
        accentInk: SRTone(0x8A4B0F, 0xF2B66B), good: SRTone(0x1E7A3C, 0x6EE7A0),
        warn: SRTone(0x8F5A00, 0xFFC24B), error: SRTone(0xB42318, 0xFF8A7A),
        hues: hues(0x1C2A16, [
            (.family, 0xD9603F, 0xF4A261), (.health, 0x23887C, 0x7FD1C1), (.steps, 0xD49A12, 0xF2CC5C),
            (.trips, 0x3E6F8E, 0x8EC5E8), (.tasks, 0xE9C46A, 0xF7E3A1), (.backlog, 0xA0646F, 0xE5B3BB),
            (.messages, 0x3A7D44, 0x8CC084), (.games, 0x6A4C93, 0xA98BD0), (.chat, 0x355070, 0x6D8FB8),
            (.news, 0x437080, 0x8FBFCC), (.daydream, 0x7A68B0, 0xC8B8F0), (.flows, 0x4A6E64, 0x9CC5B9),
            (.alerts, 0xC0392B, 0xF28B82), (.wildmind, 0x55822A, 0xB5D86B), (.move, 0xC43E52, 0xF28C9C),
        ]),
        people: [0xE76F51, 0x457B9D, 0x2A9D8F, 0xE9C46A, 0x8E7DBE, 0x4D9DE0, 0xD1495B, 0x8AB17D],
        icon: "AppIcon-Meadow", iconGround: [0xB5D86B, 0xF2CC5C, 0x23887C, 0x3E6F8E]
    )

    /// The website's own: cream paper, burnt orange, ink. The app before Prism,
    /// in Prism's layout.
    static let classic = SRPalette(
        id: "classic", name: "Classic", blurb: "The website's cream, ink and burnt orange",
        paper: SRTone(0xEDE4D4, 0x15100B), surface: SRTone(0xF7F1E6, 0x241B13),
        ink: SRTone(0x1A1008, 0xEDE4D4), inkSecondary: SRTone(0x4A3A2C, 0xCDBFAA),
        accent: SRTone(0xA34A08, 0xE8863A), accentDeep: SRTone(0x8F4106, 0xE8863A),
        accentInk: SRTone(0x0E5B66, 0x5FB3BF), good: SRTone(0x4A5A30, 0x9AAA6B),
        warn: SRTone(0x7F5200, 0xD9A53A), error: SRTone(0xA82C2C, 0xE89090),
        hues: hues(0x1A1008, [
            (.family, 0xB8520A, 0xE8863A), (.health, 0x55663A, 0x8A9A5B), (.steps, 0xA07A1E, 0xD9B44A),
            (.trips, 0x0E5B66, 0x3A8C96), (.tasks, 0xD9A520, 0xF2C94C), (.backlog, 0x8F3A4F, 0xC76B84),
            (.messages, 0x2F6F5E, 0x5A9C88), (.games, 0x6B4E8C, 0x9A7DB8), (.chat, 0x3D4F7A, 0x6A7FB0),
            (.news, 0x7A5230, 0xA87D55), (.daydream, 0x74498A, 0xB08AC2), (.flows, 0x4A5A7A, 0x7D8DAD),
            (.alerts, 0xA82C2C, 0xE08B8B), (.wildmind, 0x4F6B2A, 0x8FA85B), (.move, 0xA3412A, 0xD97A5E),
        ]),
        people: [0xC4570A, 0x0E5B66, 0x55663A, 0xB0892A, 0x6B4E8C, 0x3D7A8A, 0x9C3D54, 0x7A8B3A],
        icon: "AppIcon-Classic", iconGround: [0x1A1008, 0x1A1008, 0x1A1008, 0x1A1008],
        iconInk: 0xEDE4D4, iconBar: 0xE8863A
    )

    /// Sweet-shop colours, light and sugary: one for the children.
    static let candy = SRPalette(
        id: "candy", name: "Candy", blurb: "Bubblegum pink, sky blue, mint and lemon",
        paper: SRTone(0xFFF4F9, 0x170F1F), surface: SRTone(0xFFFFFF, 0x261A33),
        ink: SRTone(0x2A1235, 0xFFF4F9), inkSecondary: SRTone(0x6A3F72, 0xF0C9E8),
        accent: SRTone(0xC4148A, 0xFF8AD0), accentDeep: SRTone(0xA8117A, 0xFF8AD0),
        accentInk: SRTone(0x0A69AD, 0x7CCBFF), good: SRTone(0x0B7A52, 0x5EEAB0),
        warn: SRTone(0x945800, 0xFFC94D), error: SRTone(0xC4261E, 0xFF8577),
        hues: hues(0x2A1235, [
            (.family, 0xFF6FAE, 0xFFBEDC), (.health, 0x2CD3A0, 0xAAF5DC), (.steps, 0xA978FF, 0xDCC8FF),
            (.trips, 0x45B2FF, 0xB8E4FF), (.tasks, 0xFFD21F, 0xFFF4A0), (.backlog, 0xFF9466, 0xFFD3BC),
            (.messages, 0x1FC6D6, 0xA8F2F5), (.games, 0x7A3FE8, 0xB592FF), (.chat, 0x5D6BFF, 0xAEB6FF),
            (.news, 0xFF8A1F, 0xFFC27A), (.daydream, 0xE472E2, 0xFFC6F9), (.flows, 0x1E7FE0, 0x6CC0FF),
            (.alerts, 0xEE2F4A, 0xFF8A80), (.wildmind, 0x7CCF35, 0xD6F69C), (.move, 0xF0306E, 0xFF7C9E),
        ]),
        people: [0xFF5FA2, 0x3AA0F5, 0x1FC795, 0xFFB31F, 0xA066F0, 0x16C0D0, 0xFF7A45, 0x8BD12E],
        icon: "AppIcon-Candy", iconGround: [0xFF9CCB, 0xFFE76A, 0x8FD8FF, 0x7DF2C9],
        iconInk: 0x2A1235, iconBar: 0xF2559A
    )

    /// Lemon, lime, orange and grapefruit on a fresh white: zesty.
    static let citrus = SRPalette(
        id: "citrus", name: "Citrus", blurb: "Lemon, lime, orange and grapefruit on fresh white",
        paper: SRTone(0xFAFBF4, 0x101309), surface: SRTone(0xFFFFFF, 0x1C2113),
        ink: SRTone(0x1D2412, 0xFAFBF4), inkSecondary: SRTone(0x4A5532, 0xD6E0BC),
        accent: SRTone(0x5A7A00, 0xB5E655), accentDeep: SRTone(0x4C6800, 0xB5E655),
        accentInk: SRTone(0xC23F1C, 0xFF9C7A), good: SRTone(0x157A3A, 0x6EE79A),
        warn: SRTone(0x8F5A00, 0xFFC94D), error: SRTone(0xC52A2A, 0xFF8A80),
        hues: hues(0x1D2412, [
            (.family, 0xF5506A, 0xFFA494), (.health, 0x5BAA10, 0xBDEA5C), (.steps, 0xFF7A00, 0xFFB84D),
            (.trips, 0x0FA58A, 0x7DE8C8), (.tasks, 0xF5C400, 0xFFEE6B), (.backlog, 0x9C2048, 0xDD5A7A),
            (.messages, 0x1E9BE0, 0x8AD8FF), (.games, 0xB02A78, 0xF07AB8), (.chat, 0x3558D8, 0x8AA4FF),
            (.news, 0x2E7D32, 0x7CC86A), (.daydream, 0x8A5BE0, 0xC9B0FF), (.flows, 0x0B7894, 0x4CC6E0),
            (.alerts, 0xE0261E, 0xFF7058), (.wildmind, 0xB5C800, 0xEEF57A), (.move, 0xE83E8C, 0xFF9AC8),
        ]),
        people: [0xF5586E, 0x2D8FE0, 0x2EB060, 0xFF9500, 0x9A5BE0, 0x10B5A0, 0xE8C400, 0x86C21A],
        icon: "AppIcon-Citrus", iconGround: [0xFFC400, 0x7CB518, 0xFF7A00, 0xE63E62]
    )

    /// Plum, raspberry, blackcurrant and blueberry: rich and deep.
    static let berry = SRPalette(
        id: "berry", name: "Berry", blurb: "Rich plum, raspberry, blackcurrant and blueberry",
        paper: SRTone(0xF8F1F6, 0x140A16), surface: SRTone(0xFFFFFF, 0x241327),
        ink: SRTone(0x2A0F2E, 0xF8F1F6), inkSecondary: SRTone(0x67406A, 0xE6C6E6),
        accent: SRTone(0x8B2387, 0xEFA0E8), accentDeep: SRTone(0x761C73, 0xEFA0E8),
        accentInk: SRTone(0x3346B8, 0xA6B2FF), good: SRTone(0x0F7A47, 0x5FE39A),
        warn: SRTone(0x925600, 0xFFC24B), error: SRTone(0xC4182F, 0xFF7A8A),
        hues: hues(0x2A0F2E, [
            (.family, 0xD1246A, 0xFF7AA6), (.health, 0x1E7F4C, 0x5CC98A), (.steps, 0xE08A10, 0xFFC45C),
            (.trips, 0x2F55C8, 0x7A98FF), (.tasks, 0xD9BE1A, 0xFFEC7A), (.backlog, 0x7A1A52, 0xC2508E),
            (.messages, 0x15807A, 0x52C9BE), (.games, 0x4E1A7A, 0x8E50C8), (.chat, 0x2E2A8A, 0x6460D0),
            (.news, 0x7A5A7E, 0xBBA0BE), (.daydream, 0xB04AC0, 0xEAA0F0), (.flows, 0x2A86B0, 0x78D2F0),
            (.alerts, 0xD9480F, 0xFF9A5A), (.wildmind, 0x6E8A12, 0xC4D84A), (.move, 0xE8384A, 0xFF8A80),
        ]),
        people: [0xE0306A, 0x4058D8, 0x1E9E6A, 0xF0A020, 0x9B3FD0, 0x2A9AB0, 0xF06A3A, 0x7FA82A],
        icon: "AppIcon-Berry", iconGround: [0xE0306A, 0x8B2387, 0x3148C8, 0x3D1550]
    )

    /// Pastels with dark type on every tile: the gentlest of them.
    static let lavender = SRPalette(
        id: "lavender", name: "Lavender", blurb: "Soft lilac, periwinkle, mint and blush pastels",
        paper: SRTone(0xF7F2FA, 0x16121F), surface: SRTone(0xFFFFFF, 0x241E31),
        ink: SRTone(0x221A38, 0xF7F2FA), inkSecondary: SRTone(0x544A73, 0xD5CBEB),
        accent: SRTone(0x7A4AB0, 0xCDB0F5), accentDeep: SRTone(0x683D9C, 0xCDB0F5),
        accentInk: SRTone(0x0B7566, 0x7EE6CF), good: SRTone(0x1A7A4C, 0x7FE3AE),
        warn: SRTone(0x8F5800, 0xFFC970), error: SRTone(0xBF2A4A, 0xFF8FA3),
        hues: hues(0x221A38, [
            (.family, 0xF2899E, 0xFFCDD6), (.health, 0x4FC79A, 0xB8F0DA), (.steps, 0xF5A26B, 0xFFD8B8),
            (.trips, 0x6FA8F0, 0xC2DEFF), (.tasks, 0xF2CF5B, 0xFFEDA8), (.backlog, 0x9E6A9A, 0xD8B4D4),
            (.messages, 0x52BCC8, 0xB5ECF0), (.games, 0x9E80E6, 0xD8CAFF), (.chat, 0x5F6FD0, 0xA8B2F2),
            (.news, 0x8FAF94, 0xD3E5D5), (.daydream, 0xD58AE6, 0xF5D0FA), (.flows, 0x9893B5, 0xD8D5E8),
            (.alerts, 0xF07466, 0xFFBCAE), (.wildmind, 0xA6CF6A, 0xE0F2BC), (.move, 0xE0659C, 0xFFB3D3),
        ]),
        people: [0xF07A96, 0x6F8EEA, 0x4CC29A, 0xF2B24D, 0xB088EE, 0x5EBFD9, 0xD884C8, 0x9CC764],
        icon: "AppIcon-Lavender", iconGround: [0xEE8FAE, 0xA98BEB, 0x7F95F0, 0x5CC9A6]
    )

    /// Ice, slate and a pale aurora: cool and calm, with a rose family to stand out.
    static let arctic = SRPalette(
        id: "arctic", name: "Arctic", blurb: "Icy blues, slate and a pale aurora green",
        paper: SRTone(0xF2F5F7, 0x0B1016), surface: SRTone(0xFFFFFF, 0x161E27),
        ink: SRTone(0x0F1E2B, 0xF2F5F7), inkSecondary: SRTone(0x3D5366, 0xBACBD9),
        accent: SRTone(0x0B6A8C, 0x7FD4F0), accentDeep: SRTone(0x095A78, 0x7FD4F0),
        accentInk: SRTone(0x0B7A5E, 0x6EEBC0), good: SRTone(0x167A4A, 0x6EE7A0),
        warn: SRTone(0x8A5A00, 0xFFC857), error: SRTone(0xBE2D3C, 0xFF8A94),
        hues: hues(0x0F1E2B, [
            (.family, 0xC8637E, 0xEFB4C4), (.health, 0x2FAE84, 0xB0F2D6), (.steps, 0x55697E, 0xA6B6C6),
            (.trips, 0x3E86D0, 0xB2D8F7), (.tasks, 0x86C6DC, 0xDDF2F9), (.backlog, 0x7C76B5, 0xC0BCE6),
            (.messages, 0x15909F, 0x8CDCE6), (.games, 0x6650C0, 0xAA9CF0), (.chat, 0x2F5E96, 0x7FA8D6),
            (.news, 0x8A97A3, 0xD2D9DF), (.daydream, 0xA06AB8, 0xDDBDEA), (.flows, 0x1E3F6E, 0x4E7DB8),
            (.alerts, 0xC94545, 0xF09A8C), (.wildmind, 0x6C9A62, 0xBADBAA), (.move, 0xB0488C, 0xE39AC9),
        ]),
        people: [0xE0607F, 0x2F7FD0, 0x2EA585, 0xE0A93A, 0x7A6BC8, 0x1AA0B8, 0xE5824F, 0x8DBF6A],
        icon: "AppIcon-Arctic", iconGround: [0x7FDDBA, 0x8EC2F0, 0x3E86D0, 0x1E3F6E]
    )

    /// Pine, moss, bark and amber: darker and woodier than Meadow.
    static let forest = SRPalette(
        id: "forest", name: "Forest", blurb: "Deep pine, moss, bark and amber",
        paper: SRTone(0xE9ECE3, 0x0B120E), surface: SRTone(0xF6F7F1, 0x17211B),
        ink: SRTone(0x16201A, 0xE9ECE3), inkSecondary: SRTone(0x44503E, 0xC6D0BE),
        accent: SRTone(0x1F5E45, 0x7FCFA6), accentDeep: SRTone(0x1A503A, 0x7FCFA6),
        accentInk: SRTone(0x8C4F00, 0xF0B45A), good: SRTone(0x2B6E2E, 0x86D98A),
        warn: SRTone(0x845200, 0xF2B84B), error: SRTone(0xA8321F, 0xF2907A),
        hues: hues(0x16201A, [
            (.family, 0xC0432E, 0xE8866A), (.health, 0x4F7D2A, 0x95BF5A), (.steps, 0xC07A10, 0xE8B04A),
            (.trips, 0x2F6E8C, 0x6FB0CC), (.tasks, 0xC9A227, 0xE8CD6A), (.backlog, 0x7E4F6E, 0xB88AA6),
            (.messages, 0x1F6B5C, 0x5AA593), (.games, 0x55457E, 0x8C7DB5), (.chat, 0x5A7A8C, 0xA0BCC8),
            (.news, 0x6B4A2F, 0xA07B57), (.daydream, 0x9E5A9C, 0xD8A0D4), (.flows, 0x2E3F66, 0x6A7EAA),
            (.alerts, 0x9E1F2E, 0xD9505A), (.wildmind, 0x6E8F1E, 0xB7D05A), (.move, 0xB83A55, 0xE57F94),
        ]),
        people: [0xC0502E, 0x3A6F96, 0x4F8A3A, 0xD09A2A, 0x7A5A9E, 0x2E8A7A, 0xA8456A, 0x8A6A45],
        icon: "AppIcon-Forest", iconGround: [0x4F7D2A, 0xC07A10, 0x1F5E45, 0x4A3424],
        iconBar: 0xE8B04A
    )

    /// Sand, clay and terracotta with sage and dusty blue: earthy and warm.
    static let terracotta = SRPalette(
        id: "terracotta", name: "Terracotta", blurb: "Sun-baked sand and clay, sage and dusty blue",
        paper: SRTone(0xF7EFE6, 0x1A1210), surface: SRTone(0xFFFBF6, 0x2A1E19),
        ink: SRTone(0x2B1A12, 0xF7EFE6), inkSecondary: SRTone(0x67503F, 0xE2CDBD),
        accent: SRTone(0xA23B30, 0xF29A7A), accentDeep: SRTone(0x8C3128, 0xF29A7A),
        accentInk: SRTone(0x3A6585, 0x9CC3E0), good: SRTone(0x3E6E3A, 0xA3CF96),
        warn: SRTone(0x8A5600, 0xE8B65A), error: SRTone(0xB51D45, 0xFF8A9C),
        hues: hues(0x2B1A12, [
            (.family, 0xC2593A, 0xE89878), (.health, 0x6E8F6A, 0xAFC9A6), (.steps, 0xC98A2E, 0xE8BF72),
            (.trips, 0x5A7FA0, 0x9DBBD4), (.tasks, 0xD9B47A, 0xF2E0C2), (.backlog, 0xB66B6E, 0xE0A7A6),
            (.messages, 0x4C8A84, 0x93C7C0), (.games, 0x7A4F78, 0xB48CB0), (.chat, 0x45618C, 0x8296BF),
            (.news, 0x8C5A3C, 0xC4977A), (.daydream, 0x8C7AA8, 0xC9BCDB), (.flows, 0x3F6E7A, 0x83AAB5),
            (.alerts, 0xB03A2E, 0xE58A78), (.wildmind, 0x7A8A3A, 0xBDC77E), (.move, 0xC8506A, 0xEE9AA8),
        ]),
        people: [0xC8603F, 0x4F7FA6, 0x6E9A68, 0xD4A040, 0x8A6A9E, 0x3F8F88, 0xB85A6E, 0x8A9A45],
        icon: "AppIcon-Terracotta", iconGround: [0xE8BF72, 0xC2593A, 0x8FAF8A, 0x5A7FA0]
    )

    /// Greys and slate, so the one signal orange is what you notice.
    static let graphite = SRPalette(
        id: "graphite", name: "Graphite", blurb: "Greys and slate, one signal orange",
        paper: SRTone(0xF2F2F1, 0x0E0F11), surface: SRTone(0xFFFFFF, 0x1B1D21),
        ink: SRTone(0x17191C, 0xF2F2F1), inkSecondary: SRTone(0x4A4F57, 0xC6CAD0),
        accent: SRTone(0xC93000, 0xFF6B2C), accentDeep: SRTone(0xB02A00, 0xFF6B2C),
        accentInk: SRTone(0x46607A, 0xA8BCD0), good: SRTone(0x2E7048, 0x7FD6A0),
        warn: SRTone(0x845A00, 0xE8BC5A), error: SRTone(0xC0183C, 0xFF7A93),
        hues: hues(0x17191C, [
            (.family, 0x2F3237, 0x5A5F67), (.health, 0x5F7266, 0x9AAEA1), (.steps, 0x7A6F66, 0xB3A99F),
            (.trips, 0x4A6585, 0x8CA5C2), (.tasks, 0xA9AEB5, 0xDADDE1), (.backlog, 0x766A7E, 0xADA3B5),
            (.messages, 0x4F7478, 0x8FB0B3), (.games, 0x3B4252, 0x6B7488), (.chat, 0x657080, 0xA3ADBB),
            (.news, 0x8F8A80, 0xC9C5BD), (.daydream, 0x8A87A8, 0xC4C2DA), (.flows, 0x3D5560, 0x75909C),
            (.alerts, 0xD9480F, 0xFF8A4C), (.wildmind, 0x6B7254, 0xA8AE90), (.move, 0xF08A24, 0xFFC27A),
        ]),
        people: [0xE5531A, 0x4A6585, 0x5F8A6E, 0xB08D3E, 0x7D6A9E, 0x3E8A92, 0xA35D6A, 0x9AA0A8],
        icon: "AppIcon-Graphite", iconGround: [0x4A4F57, 0x3B4048, 0x2A2D33, 0x1C1E22],
        iconInk: 0xF2F2F1, iconBar: 0xFF5A1F
    )
}

// MARK: - The reader's choice

/// What the reader chose. Stored as JSON under one key; lenient on the way
/// back in, so a value from a later build never throws away the rest.
struct SRPaletteChoice: Codable, Equatable {
    var preset = SRPalette.prism.id
    /// Per preset: the hues the reader re-picked, by feature. Per preset so
    /// going back to a palette brings back what was done to it.
    var hues: [String: [String: UInt32]] = [:]
    /// Per preset: a re-picked accent.
    var accent: [String: UInt32] = [:]
    var glow: Glow = .vivid
    /// The app icon follows the palette.
    var iconFollows = true

    /// How strongly the page's ground is lit by the screen's hues.
    enum Glow: String, Codable, CaseIterable, Identifiable {
        case vivid, soft, off
        var id: String { rawValue }
        var scale: Double {
            switch self {
            case .vivid: return 1
            case .soft: return 0.5
            case .off: return 0
            }
        }
        var title: String {
            switch self {
            case .vivid: return "Vivid"
            case .soft: return "Soft"
            case .off: return "Off"
            }
        }
    }

    static let key = "palette"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = ((try? c.decodeIfPresent(String.self, forKey: .preset)) ?? nil) ?? SRPalette.prism.id
        hues = ((try? c.decodeIfPresent([String: [String: UInt32]].self, forKey: .hues)) ?? nil) ?? [:]
        accent = ((try? c.decodeIfPresent([String: UInt32].self, forKey: .accent)) ?? nil) ?? [:]
        glow = ((try? c.decodeIfPresent(Glow.self, forKey: .glow)) ?? nil) ?? .vivid
        iconFollows = ((try? c.decodeIfPresent(Bool.self, forKey: .iconFollows)) ?? nil) ?? true
    }

    static func decode(_ raw: String?) -> SRPaletteChoice {
        guard let data = raw?.data(using: .utf8), let choice = try? JSONDecoder().decode(SRPaletteChoice.self, from: data) else {
            return SRPaletteChoice()
        }
        return choice
    }

    var raw: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// What this phone chose. The screenshot harness always starts on Prism,
    /// or on `-SRPalette <id>` when a run asks for one.
    static var stored: SRPaletteChoice {
        #if DEBUG
        if SRDemo.isShowcase {
            var choice = SRPaletteChoice()
            let args = ProcessInfo.processInfo.arguments
            if let at = args.firstIndex(of: "-SRPalette"), at + 1 < args.count { choice.preset = args[at + 1] }
            return choice
        }
        #endif
        return decode(UserDefaults.standard.string(forKey: key))
    }

    /// The reader's own colour for a feature on the current preset, if any.
    func picked(_ key: SR.HueKey) -> UInt32? { hues[preset]?[key.rawValue] }

    mutating func pick(_ key: SR.HueKey, _ hex: UInt32?) {
        var mine = hues[preset] ?? [:]
        mine[key.rawValue] = hex
        hues[preset] = mine.isEmpty ? nil : mine
    }

    /// Whether anything on the current preset was re-picked.
    var customised: Bool { !(hues[preset] ?? [:]).isEmpty || accent[preset] != nil }

    mutating func resetCurrent() {
        hues[preset] = nil
        accent[preset] = nil
    }
}

// MARK: - Paint: the resolved palette, as colours

/// The resolved palette as the `Color`s every screen paints with. Built once
/// per change, so a token is a field read, and NEW colour objects per change,
/// so nothing built after a change can be holding the old one.
final class SRPaint {
    /// What `SR`'s tokens read. Set by `SRPaletteStore`; main thread only.
    static var current = SRPaint(SRPaletteChoice.stored)

    let palette: SRPalette
    let glow: Double

    let paper: Color
    let surface: Color
    let ink: Color
    let inkSecondary: Color
    let inkMuted: Color
    let inkGhost: Color
    let band: Color
    let cream: Color
    let accent: Color
    let accentDeep: Color
    let accentOnDark: Color
    let accentInk: Color
    let accentInkOnDark: Color
    let good: Color
    let goodOnDark: Color
    let warn: Color
    let error: Color
    let errorOnDark: Color
    let line: Color
    let divider: Color
    let lineOnDark: Color
    let creamOnDark: Color

    /// Glass over the ground: the surface, lifted a touch in dark mode so a
    /// panel reads as a sheet rather than a hole.
    let lifted: SRTone
    let hues: [SR.HueKey: SR.Hue]
    let people: [Color]

    convenience init(_ choice: SRPaletteChoice) {
        self.init(SRPalette.resolve(choice), glow: choice.glow.scale)
    }

    init(_ p: SRPalette, glow: Double = 1) {
        palette = p
        self.glow = glow
        paper = p.paper.color()
        surface = p.surface.color()
        ink = p.ink.color()
        inkSecondary = p.inkSecondary.color()
        inkMuted = SRTone(p.ink.light, p.ink.dark).color(alpha: 0.65)
        inkGhost = SRTone(p.ink.light, p.ink.dark).color(alpha: 0.45)
        band = SRRGB.color(p.ink.light)
        cream = SRRGB.color(p.paper.light)
        accent = p.accent.color()
        accentDeep = p.accentDeep.color()
        accentOnDark = SRRGB.color(p.accent.dark)
        accentInk = p.accentInk.color()
        accentInkOnDark = SRRGB.color(p.accentInk.dark)
        good = p.good.color()
        goodOnDark = SRRGB.color(p.good.dark)
        warn = p.warn.color()
        error = p.error.color()
        errorOnDark = SRRGB.color(p.error.dark)
        line = p.ink.color(alpha: 0.18)
        divider = p.ink.color(alpha: 0.08)
        lineOnDark = SRRGB.color(p.paper.light, alpha: 0.14)
        creamOnDark = SRRGB.color(p.paper.light, alpha: 0.72)
        lifted = SRTone(p.surface.light, SRRGB.mix(p.ink.dark, p.surface.dark, 0.05))
        var hues: [SR.HueKey: SR.Hue] = [:]
        for key in SR.HueKey.allCases { hues[key] = SR.Hue(p.hue(key)) }
        self.hues = hues
        people = p.people.map { SRRGB.color($0) }
    }

    func hue(_ key: SR.HueKey) -> SR.Hue {
        hues[key] ?? SR.Hue(palette.hue(key))
    }
}

// MARK: - The store

/// Holds the choice, persists it, and tells the app when to redraw.
@MainActor
final class SRPaletteStore: ObservableObject {
    static let shared = SRPaletteStore()

    @Published private(set) var choice: SRPaletteChoice
    /// Bumped a moment after the last change: the app's tab view takes it as
    /// part of its identity, so every screen is rebuilt in the new colours.
    /// Debounced, because a colour wheel changes the choice on every frame of
    /// a drag and a rebuild per frame would reload every tab's data.
    @Published private(set) var epoch = 0
    private var pending: Task<Void, Never>?

    private init() {
        choice = SRPaletteChoice.stored
    }

    var palette: SRPalette { SRPaint.current.palette }

    func update(_ change: (inout SRPaletteChoice) -> Void) {
        var next = choice
        change(&next)
        guard next != choice else { return }
        choice = next
        UserDefaults.standard.set(next.raw, forKey: SRPaletteChoice.key)
        SRPaint.current = SRPaint(next)
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            self.epoch += 1
            self.shareWithWidgets()
        }
    }

    /// Leave the widgets' colours on the shelf, and reload them if those
    /// changed. Also at launch, so a phone updated to this build gets its
    /// palette onto the Home Screen without visiting the sheet.
    func shareWithWidgets() {
        if FamilyShelf.save(SRPaint.current.palette.widget, .palette) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The icon the choice asks for: the palette's own, or the primary.
    var wantedIcon: String? {
        choice.iconFollows ? SRPaint.current.palette.icon : nil
    }

    /// Change the Home Screen icon to match. Only when the Colours sheet
    /// closes: iOS says so in an alert every time, and one alert per palette
    /// tapped through would be a nuisance. Never in the screenshot harness,
    /// where that alert would sit over every later shot.
    func syncIcon() {
        guard !SRDemo.isShowcase else { return }
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.applicationState == .active,
              app.alternateIconName != wantedIcon else { return }
        app.setAlternateIconName(wantedIcon) { _ in }
    }
}

extension SR.Hue {
    init(_ spec: SRHueSpec) {
        self.init(base: SRRGB.color(spec.base), glow: SRRGB.color(spec.glow), onFill: SRRGB.color(spec.onFill))
    }
}

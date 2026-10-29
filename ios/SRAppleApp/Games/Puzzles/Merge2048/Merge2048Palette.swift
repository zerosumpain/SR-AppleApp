import SwiftUI

/// 2048's colours. Each value owns a two-stop fill and the type that reads on
/// it, in a ramp that climbs from quiet lilac through the warm hues to green,
/// blue and the app's violet at 2048, then into deep indigo beyond. Every pair
/// has a dark-mode partner lifted for the midnight ground, so a light phone
/// and a dark one read the board alike.
struct Merge2048Swatch {
    /// The deeper stop, bottom right. Also the colour of a merge's sparks.
    let base: Color
    /// The brighter stop, top left.
    let glow: Color
    /// The number on the tile.
    let ink: Color
    /// 2048 and beyond: the tile is ringed so it reads as special.
    let crowned: Bool

    var fill: LinearGradient {
        LinearGradient(colors: [glow, base], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum Merge2048Palette {
    /// The board's tray.
    static let tray = Color(light: 0xCBC6E6, dark: 0x16142C)
    static let trayDeep = Color(light: 0xB7B1DA, dark: 0x0F0D22)
    /// An empty cell.
    static let slot = Color(light: 0xE4E0F5, dark: 0x25223F)

    private static let lightInk = Color(light: 0x2D2A5A, dark: 0xECEAFF)
    private static let white = Color(light: 0xFFFFFF, dark: 0xFFFFFF)
    private static let goldInk = Color(light: 0x3A2A00, dark: 0x2A1F00)
    private static let limeInk = Color(light: 0x1C3000, dark: 0x152400)
    private static let amberInk = Color(light: 0x3D1C00, dark: 0x2E1500)

    // (base light, base dark, glow light, glow dark), from 2 upward.
    private static let ramp: [(UInt32, UInt32, UInt32, UInt32)] = [
        (0xEFEBFF, 0x302D58, 0xFFFFFF, 0x3D3A6C), // 2
        (0xDCD5FF, 0x3A3474, 0xF1EDFF, 0x4A4390), // 4
        (0xFFA23F, 0xFF9530, 0xFFC872, 0xFFBA60), // 8
        (0xF26522, 0xF0601E, 0xFF9757, 0xFF8C4A), // 16
        (0xEE4450, 0xEC3D4A, 0xFF7B7B, 0xFF7070), // 32
        (0xDD2763, 0xDB255F, 0xFF5F8F, 0xFF5A8A), // 64
        (0xF5B700, 0xF2B200, 0xFFDC5C, 0xFFD54C), // 128
        (0x94C51C, 0x8CBF18, 0xC9EB55, 0xC0E64A), // 256
        (0x14A472, 0x149C6C, 0x48D69C, 0x42CF96), // 512
        (0x1A86D8, 0x1C84D6, 0x55BCFF, 0x50B6FF), // 1024
        (0x6E3CF5, 0x7A4BFF, 0xA987FF, 0xB394FF), // 2048
        (0x3F27B0, 0x5138D8, 0x6F55F0, 0x7E66FF), // 4096
        (0x231C5E, 0x2B2378, 0x4C3FA6, 0x5A4BC0), // 8192
    ]

    /// The swatch for a tile's value.
    static func swatch(_ value: Int) -> Merge2048Swatch {
        let step = Merge2048Ladder.step(value)
        let index = min(max(step - 1, 0), ramp.count - 1)
        let entry = ramp[index]
        let base = Color(light: entry.0, dark: entry.1)
        let glow = Color(light: entry.2, dark: entry.3)
        return Merge2048Swatch(base: base, glow: glow, ink: ink(step), crowned: step >= 11)
    }

    private static func ink(_ step: Int) -> Color {
        switch step {
        case ...2: return lightInk
        case 3: return amberInk
        case 7: return goldInk
        case 8: return limeInk
        default: return white
        }
    }

    /// The number's size on a tile `cell` points wide: shrinks for 3, 4 and
    /// 5 digits so 16384 still fits on a 3×3 board's tile and a 5×5's.
    static func fontSize(for value: Int, cell: CGFloat) -> CGFloat {
        let digits = String(value).count
        let share: CGFloat
        switch digits {
        case ...2: share = 0.46
        case 3: share = 0.38
        case 4: share = 0.30
        default: share = 0.24
        }
        return max(10, cell * share)
    }
}

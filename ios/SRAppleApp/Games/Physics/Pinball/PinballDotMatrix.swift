import Foundation

/// The dot-matrix strip's picture: 128 × 16 dots, each on or off, like the
/// orange display on the back box of a real machine.
struct PinballDotFrame: Equatable {
    static let columns = 128
    static let rows = 16

    private(set) var dots: [Bool] = Array(repeating: false, count: PinballDotFrame.columns * PinballDotFrame.rows)

    subscript(row: Int, column: Int) -> Bool {
        get {
            guard row >= 0, row < Self.rows, column >= 0, column < Self.columns else { return false }
            return dots[row * Self.columns + column]
        }
        set {
            guard row >= 0, row < Self.rows, column >= 0, column < Self.columns else { return }
            dots[row * Self.columns + column] = newValue
        }
    }

    var litCount: Int { dots.reduce(0) { $0 + ($1 ? 1 : 0) } }

    /// The big score across the middle, or a smaller one when it is too long.
    static func score(_ points: Int) -> PinballDotFrame {
        let text = PinballScoring.digits(points)
        var frame = PinballDotFrame()
        if PinballDotFont.width(text, scale: 2) <= columns {
            PinballDotFont.draw(text, into: &frame, row: 1, scale: 2)
        } else {
            PinballDotFont.draw(text, into: &frame, row: 4, scale: 1)
        }
        return frame
    }

    /// A message: one line big if it fits, otherwise two small lines.
    static func message(_ top: String, _ bottom: String) -> PinballDotFrame {
        var frame = PinballDotFrame()
        if bottom.isEmpty {
            if PinballDotFont.width(top, scale: 2) <= columns {
                PinballDotFont.draw(top, into: &frame, row: 1, scale: 2)
            } else {
                PinballDotFont.draw(top, into: &frame, row: 4, scale: 1)
            }
        } else {
            PinballDotFont.draw(top, into: &frame, row: 0, scale: 1)
            PinballDotFont.draw(bottom, into: &frame, row: 9, scale: 1)
        }
        return frame
    }
}

/// A 5 × 7 dot font: capitals, digits and the few marks the messages use.
/// Each glyph is seven rows of five bits, the left-hand dot in bit 4.
enum PinballDotFont {
    static let height = 7

    private static let glyphs: [Character: [UInt8]] = [
        "A": [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        "B": [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
        "C": [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
        "D": [0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E],
        "E": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
        "F": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
        "G": [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],
        "H": [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        "I": [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
        "J": [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C],
        "K": [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
        "L": [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
        "M": [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
        "N": [0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11],
        "O": [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        "P": [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
        "Q": [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
        "R": [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
        "S": [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],
        "T": [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
        "U": [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        "V": [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
        "W": [0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A],
        "X": [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
        "Y": [0x11, 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04],
        "Z": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
        "0": [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
        "1": [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
        "2": [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
        "3": [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],
        "4": [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
        "5": [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
        "6": [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
        "7": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
        "8": [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
        "9": [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
        ",": [0x00, 0x00, 0x00, 0x00, 0x0C, 0x04, 0x08],
        ".": [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C],
        "!": [0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04],
        "+": [0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00],
        "-": [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00],
        ":": [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00],
        "/": [0x01, 0x01, 0x02, 0x04, 0x08, 0x10, 0x10],
        "?": [0x0E, 0x11, 0x01, 0x02, 0x04, 0x00, 0x04],
        "'": [0x04, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00],
        "%": [0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03],
    ]

    /// Narrow marks take only the columns they use.
    private static let narrow: Set<Character> = [",", ".", "!", ":", "'"]

    /// A glyph's rows, its first used column (0…4) and how many columns it takes.
    static func glyph(_ ch: Character) -> (rows: [UInt8], first: Int, width: Int) {
        // `first`, not `Character(...)`: some letters upper-case to two ("ß" → "SS").
        let key = String(ch).uppercased().first ?? ch
        guard let rows = glyphs[key] else { return ([0, 0, 0, 0, 0, 0, 0], 0, 3) }
        guard narrow.contains(key) else { return (rows, 0, 5) }
        let used = rows.reduce(UInt8(0)) { $0 | $1 }
        var first = 0, last = 4
        while first < 4 && used & (UInt8(0x10) >> UInt8(first)) == 0 { first += 1 }
        while last > first && used & (UInt8(0x10) >> UInt8(last)) == 0 { last -= 1 }
        return (rows, first, last - first + 1)
    }

    /// Columns the text takes, with one dark column between glyphs.
    static func width(_ text: String, scale: Int) -> Int {
        var total = 0
        for ch in text { total += glyph(ch).width + 1 }
        return max(0, total - 1) * max(1, scale)
    }

    /// Draws `text` centred across the frame, its top at `row`; anything
    /// past the edges is cut off.
    static func draw(_ text: String, into frame: inout PinballDotFrame, row: Int, scale: Int) {
        let s = max(1, scale)
        var column = (PinballDotFrame.columns - width(text, scale: s)) / 2
        column = max(0, column)
        for ch in text {
            let g = glyph(ch)
            for (r, bits) in g.rows.enumerated() {
                for c in 0..<g.width {
                    let bit = UInt8(0x10) >> UInt8(g.first + c)
                    guard bits & bit != 0 else { continue }
                    for dy in 0..<s {
                        for dx in 0..<s {
                            frame[row + r * s + dy, column + c * s + dx] = true
                        }
                    }
                }
            }
            column += (g.width + 1) * s
            if column >= PinballDotFrame.columns { break }
        }
    }
}

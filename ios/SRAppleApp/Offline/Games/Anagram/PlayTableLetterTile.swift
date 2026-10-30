import SwiftUI

// The letter pieces of the nearby word games, drawn as things you could pick
// up: Anagram Blitz's tiles (ivory, with a darker lip underneath so they sit
// proud of the table), Boggle's dice (a rounded cube with a lighter top), the
// rack the word being built sits in, and Categories' letter die.
//
// Fixed colours: a tile is an object, ivory in a dark room too. The letters
// are bold enough on the ivory and on the violet "picked" face to pass large
// text contrast in both appearances.

/// What a letter piece is doing right now.
enum PlayTableTileState: Equatable {
    /// Sitting on the table, ready to be picked.
    case ready
    /// Already used in the word being built: pressed down and greyed.
    case used
    /// Part of the word being traced.
    case traced
    /// The newest letter of the trace: lit and raised.
    case tracedLast
    /// Lit after the round, to show a word on the board.
    case shown
}

enum PlayTableTilePaint {
    static let ivoryTop = Color(hex: 0xFFF8E6)
    static let ivoryBottom = Color(hex: 0xF1DFB6)
    static let ivoryLip = Color(hex: 0xC9AE7A)
    static let ivoryInk = Color(hex: 0x3A2A12)
    static let tracedTop = Color(hex: 0x7A4BF0)
    static let tracedBottom = Color(hex: 0x5228C4)
    static let tracedLip = Color(hex: 0x35168A)
    static let shownTop = Color(hex: 0x17A3A0)
    static let shownBottom = Color(hex: 0x0C7472)
    static let shownLip = Color(hex: 0x064A49)
    static let usedFace = Color(hex: 0xD9CFBC)
    static let usedInk = Color(hex: 0x9C8F78)
}

/// One letter tile (Anagram) or die (Boggle), `side` points square, plus a lip
/// underneath that the frame includes.
struct PlayTableLetterTile: View {
    let letter: String
    let side: CGFloat
    var state: PlayTableTileState = .ready
    /// A die (Boggle): rounder, with the top face lit like a cube's.
    var die: Bool = false
    /// The small figure in the corner, as on a word-game tile.
    var points: Int? = nil

    private var lip: CGFloat { max(2, side * 0.08) }
    private var pressed: Bool { state == .used }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * (die ? 0.24 : 0.16), style: .continuous)
        let colours = paint
        ZStack {
            shape
                .fill(colours.lip)
                .offset(y: pressed ? lip * 0.25 : lip)
            shape
                .fill(LinearGradient(colors: [colours.top, colours.bottom], startPoint: .top, endPoint: .bottom))
            if die {
                // The cube's top face: a softer square inside the edge.
                shape
                    .inset(by: side * 0.1)
                    .fill(Color.white.opacity(state == .ready ? 0.35 : 0.12))
            }
            shape
                .strokeBorder(Color.white.opacity(pressed ? 0.15 : 0.55), lineWidth: 1)
            Text(letter.isEmpty ? " " : letter)
                .font(.system(size: side * (letter.count > 1 ? 0.4 : 0.54), weight: .heavy, design: .rounded))
                .foregroundStyle(colours.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, side * 0.06)
            if let points, !pressed {
                Text("\(points)")
                    .font(.system(size: side * 0.2, weight: .bold, design: .rounded))
                    .foregroundStyle(colours.ink.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(side * 0.09)
            }
        }
        .frame(width: side, height: side)
        .offset(y: pressed ? lip * 0.75 : 0)
        .scaleEffect(state == .tracedLast ? 1.07 : 1)
        .padding(.bottom, lip)
        .shadow(color: Color.black.opacity(pressed ? 0.05 : 0.18), radius: pressed ? 1 : 3, x: 0, y: pressed ? 1 : 3)
    }

    private var paint: (top: Color, bottom: Color, lip: Color, ink: Color) {
        switch state {
        case .ready:
            return (PlayTableTilePaint.ivoryTop, PlayTableTilePaint.ivoryBottom, PlayTableTilePaint.ivoryLip, PlayTableTilePaint.ivoryInk)
        case .used:
            return (PlayTableTilePaint.usedFace, PlayTableTilePaint.usedFace, PlayTableTilePaint.ivoryLip, PlayTableTilePaint.usedInk)
        case .traced, .tracedLast:
            return (PlayTableTilePaint.tracedTop, PlayTableTilePaint.tracedBottom, PlayTableTilePaint.tracedLip, Color.white)
        case .shown:
            return (PlayTableTilePaint.shownTop, PlayTableTilePaint.shownBottom, PlayTableTilePaint.shownLip, Color.white)
        }
    }
}

/// The rack the word being built sits in: one slot per letter it can hold,
/// filled from the left with small tiles, so the length of the word and the
/// room left read at a glance.
struct PlayTableRack: View {
    /// The letters placed so far.
    let letters: [String]
    /// How many slots the rack has.
    let slots: Int
    /// The widest a slot may be.
    var maxSlot: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let count = max(slots, 1)
            let gap: CGFloat = 5
            let side = max(18, min(maxSlot, (geo.size.width - 20 - gap * CGFloat(count - 1)) / CGFloat(count)))
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { index in
                    slot(index, side: side)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: maxSlot + 16)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x8C5A33), Color(hex: 0x5E3A1E)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 3)
        )
        .srAnimation(.snappy(duration: 0.18), value: letters)
    }

    @ViewBuilder
    private func slot(_ index: Int, side: CGFloat) -> some View {
        if index < letters.count {
            PlayTableLetterTile(letter: letters[index], side: side)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else {
            RoundedRectangle(cornerRadius: side * 0.16, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: side * 0.16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .frame(width: side, height: side)
                .padding(.bottom, max(2, side * 0.08))
        }
    }
}

/// Categories' letter: a big die. When the letter arrives it rolls — a short
/// flick through other letters, then it lands with a tap you can feel. Under
/// Reduce Motion it simply shows the letter.
struct PlayTableLetterDie: View {
    let letter: String?
    var side: CGFloat = 72
    @State private var face: String = "?"
    @State private var rolling = false
    @State private var turn: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PlayTableLetterTile(letter: face, side: side, state: rolling ? .ready : (letter == nil ? .used : .traced), die: true)
            .rotationEffect(.degrees(turn))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(letter.map { "The letter \($0.uppercased())" } ?? "The letter is coming")
            .task(id: letter ?? "") { await roll() }
    }

    /// Flick through a few letters, slowing down, then land on the real one.
    @MainActor
    private func roll() async {
        guard let letter, !letter.isEmpty else {
            // A roll cut short by the letter going away must not leave the
            // die mid-tumble.
            face = "?"
            rolling = false
            turn = 0
            return
        }
        let target = letter.uppercased()
        if reduceMotion || face == target {
            face = target
            rolling = false
            turn = 0
            return
        }
        let faces = PlayTableMath.rollFaces(final: target, count: 9, seed: Int(target.unicodeScalars.first?.value ?? 0))
        rolling = true
        for (index, next) in faces.enumerated() {
            if Task.isCancelled { return }
            face = next
            turn = index == faces.count - 1 ? 0 : PlayTableMath.tilt(index, range: 14)
            if index < faces.count - 1 {
                let wait = 0.05 + 0.02 * Double(index)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        rolling = false
        SRHaptic.ok()
    }
}

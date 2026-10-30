import SwiftUI

/// The face on the restart button, drawn rather than an emoji so it can
/// worry while a finger is down, think while a fair field is laid, put on
/// sunglasses for a win and go cross-eyed for a loss.
struct MinesweeperFace: View {
    let mood: MinesweeperMood

    var body: some View {
        let mood = self.mood
        Canvas { context, size in
            MinesweeperFace.paint(mood, in: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    static func paint(_ mood: MinesweeperMood, in context: inout GraphicsContext, size: CGSize) {
        let d = min(size.width, size.height)
        let rect = CGRect(x: (size.width - d) / 2, y: (size.height - d) / 2, width: d, height: d)
        let face = Path(ellipseIn: rect.insetBy(dx: d * 0.05, dy: d * 0.05))
        let skin = Gradient(colors: [Color(hex: 0xFFEC80), Color(hex: 0xFFB300)])
        context.fill(face, with: .linearGradient(skin, startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                 endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        context.stroke(face, with: .color(Color(hex: 0xB06F00)), lineWidth: max(1, d * 0.05))
        let shine = CGRect(x: rect.minX + d * 0.24, y: rect.minY + d * 0.14, width: d * 0.24, height: d * 0.12)
        context.fill(Path(ellipseIn: shine), with: .color(Color.white.opacity(0.45)))

        let ink = Color(hex: 0x3B2A00)
        let eyeY = rect.minY + d * 0.42
        let left = rect.minX + d * 0.36, right = rect.minX + d * 0.64
        let mouthY = rect.minY + d * 0.66
        let line = max(1, d * 0.06)

        switch mood {
        case .happy:
            dot(at: CGPoint(x: left, y: eyeY), r: d * 0.05, ink, &context)
            dot(at: CGPoint(x: right, y: eyeY), r: d * 0.05, ink, &context)
            curve(from: rect.minX + d * 0.32, to: rect.minX + d * 0.68, y: mouthY, bend: d * 0.14, ink, line, &context)
        case .worried:
            dot(at: CGPoint(x: left, y: eyeY), r: d * 0.075, ink, &context)
            dot(at: CGPoint(x: right, y: eyeY), r: d * 0.075, ink, &context)
            let o = CGRect(x: rect.midX - d * 0.08, y: mouthY - d * 0.06, width: d * 0.16, height: d * 0.17)
            context.fill(Path(ellipseIn: o), with: .color(ink))
        case .thinking:
            dot(at: CGPoint(x: left + d * 0.03, y: eyeY - d * 0.04), r: d * 0.05, ink, &context)
            dot(at: CGPoint(x: right + d * 0.03, y: eyeY - d * 0.04), r: d * 0.05, ink, &context)
            var mouth = Path()
            mouth.move(to: CGPoint(x: rect.minX + d * 0.38, y: mouthY + d * 0.03))
            mouth.addLine(to: CGPoint(x: rect.minX + d * 0.64, y: mouthY - d * 0.01))
            context.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: line, lineCap: .round))
        case .cool:
            let glass = Color(hex: 0x14181C)
            var bar = Path()
            bar.move(to: CGPoint(x: rect.minX + d * 0.16, y: eyeY - d * 0.05))
            bar.addLine(to: CGPoint(x: rect.minX + d * 0.84, y: eyeY - d * 0.05))
            context.stroke(bar, with: .color(glass), style: StrokeStyle(lineWidth: line, lineCap: .round))
            for x in [left, right] {
                let lens = CGRect(x: x - d * 0.13, y: eyeY - d * 0.07, width: d * 0.26, height: d * 0.15)
                context.fill(Path(roundedRect: lens, cornerRadius: d * 0.06), with: .color(glass))
                let glint = CGRect(x: lens.minX + d * 0.04, y: lens.minY + d * 0.03, width: d * 0.07, height: d * 0.035)
                context.fill(Path(roundedRect: glint, cornerRadius: d * 0.017), with: .color(Color.white.opacity(0.6)))
            }
            curve(from: rect.minX + d * 0.3, to: rect.minX + d * 0.7, y: mouthY, bend: d * 0.17, ink, line, &context)
        case .dead:
            for x in [left, right] {
                var cross = Path()
                let k = d * 0.065
                cross.move(to: CGPoint(x: x - k, y: eyeY - k))
                cross.addLine(to: CGPoint(x: x + k, y: eyeY + k))
                cross.move(to: CGPoint(x: x + k, y: eyeY - k))
                cross.addLine(to: CGPoint(x: x - k, y: eyeY + k))
                context.stroke(cross, with: .color(ink), style: StrokeStyle(lineWidth: line, lineCap: .round))
            }
            curve(from: rect.minX + d * 0.34, to: rect.minX + d * 0.66, y: mouthY + d * 0.06, bend: -d * 0.12, ink, line, &context)
        }
    }

    private static func dot(at p: CGPoint, r: CGFloat, _ colour: Color, _ context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(colour))
    }

    /// A smile (positive bend) or a frown (negative).
    private static func curve(from x0: CGFloat, to x1: CGFloat, y: CGFloat, bend: CGFloat, _ colour: Color,
                              _ width: CGFloat, _ context: inout GraphicsContext) {
        var mouth = Path()
        mouth.move(to: CGPoint(x: x0, y: y))
        mouth.addQuadCurve(to: CGPoint(x: x1, y: y), control: CGPoint(x: (x0 + x1) / 2, y: y + bend))
        context.stroke(mouth, with: .color(colour), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

/// A figure at the top of the field: the mines left, or the clock.
struct MinesweeperReadout: View {
    let label: String
    let icon: String
    let value: String
    let spoken: String
    var trailing = false
    var tint: Color = SR.ink

    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(SR.Text.label())
                Text(label)
                    .font(SR.Text.label())
                    .tracking(1.2)
            }
            .foregroundStyle(SR.inkMuted)
            .lineLimit(1)
            Text(value)
                .font(SR.Text.figure(26))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 64)
        .srGlassCard(.paper, radius: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// The clock, ticking a few times a second only while a game runs.
struct MinesweeperClockReadout: View {
    @ObservedObject var game: MinesweeperGame

    var body: some View {
        if game.clockRunning && !game.paused {
            TimelineView(.periodic(from: Date(), by: 0.25)) { context in
                readout(game.elapsed(at: context.date))
            }
        } else {
            readout(game.stage == .won || game.stage == .lost ? game.finalTime : game.elapsed(at: Date()))
        }
    }

    private func readout(_ seconds: Double) -> some View {
        MinesweeperReadout(label: "TIME", icon: "stopwatch", value: MinesweeperFormat.clock(seconds),
                           spoken: "Time, \(MinesweeperFormat.spoken(seconds))", trailing: true)
            .accessibilityIdentifier("minesweeper-clock")
    }
}

/// Dig or Flag: what a plain tap does. Big halves, easy to hit with a thumb.
struct MinesweeperModeToggle: View {
    @Binding var flagMode: Bool

    var body: some View {
        HStack(spacing: 4) {
            segment(title: "Dig", icon: "hand.point.up.left.fill", on: !flagMode, fill: SR.accentDeep, ink: SR.paper) {
                flagMode = false
            }
            .accessibilityIdentifier("minesweeper-mode-dig")
            segment(title: "Flag", icon: "flag.fill", on: flagMode, fill: Color(hex: 0xD32F2F), ink: Color.white) {
                flagMode = true
            }
            .accessibilityIdentifier("minesweeper-mode-flag")
        }
        .padding(4)
        .srGlassCard(.paper, radius: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What a tap does")
    }

    private func segment(title: String, icon: String, on: Bool, fill: Color, ink: Color,
                         action: @escaping () -> Void) -> some View {
        Button {
            guard !on else { return }
            SRHaptic.select()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(SR.Text.title(17))
            .foregroundStyle(on ? ink : SR.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(on ? fill : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(title == "Dig" ? "Tap digs" : "Tap plants a flag")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A round glass button for the bar under the field.
struct MinesweeperRoundButton: View {
    let icon: String
    let label: String
    let id: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(SR.Text.title(20))
                .foregroundStyle(enabled ? SR.ink : SR.inkGhost)
                .frame(width: 64, height: 64)
                .srGlassCard(.paper, radius: 32)
                .contentShape(Circle())
        }
        .buttonStyle(SRPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Zoom in to a comfortable square, or out to the whole field. Only shown
/// when the field is too big to play at full view.
struct MinesweeperZoomButton: View {
    @ObservedObject var camera: MinesweeperCamera
    let focus: Int?

    var body: some View {
        let zoomedIn = camera.resting.isZoomedIn
        if camera.resting.canZoom {
            MinesweeperRoundButton(icon: zoomedIn ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass",
                                   label: zoomedIn ? "Show the whole field" : "Zoom in",
                                   id: "minesweeper-zoom") {
                camera.toggleZoom(around: focus)
            }
        }
    }
}

/// One line of how to play: an icon in a tinted circle and the words.
struct MinesweeperHowRow: View {
    let icon: String
    let text: String
    var tint: Color = SR.accent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(SR.Text.label(15))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(tint.opacity(0.14)))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A small figure with its label: the best time, games won, the streak.
struct MinesweeperStatChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            Text(value)
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(SR.ink.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

/// Keeps a card on screen whatever the text size: as it is when it fits,
/// scrolling when the reader's setting makes it taller than the room left.
struct MinesweeperCardHolder<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }
}

/// The start card's picture: a corner of a field, half dug, drawn by the
/// same painter as the real one.
struct MinesweeperIntroArt: View {
    @Environment(\.colorScheme) private var colorScheme

    static let board: MinesweeperBoard = {
        var b = MinesweeperBoard(width: 8, height: 3, mineAt: [5, 22])
        _ = b.reveal(8)
        b.toggleFlag(5)
        return b
    }()

    var body: some View {
        let palette = MinesweeperPalette.shared(dark: colorScheme == .dark)
        Canvas { context, size in
            let board = MinesweeperIntroArt.board
            let view = MinesweeperViewport(columns: board.width, rows: board.height,
                                           width: Double(size.width) - 12, height: Double(size.height) - 12).fitted()
            var shifted = view
            shifted.offsetX += 6
            shifted.offsetY += 6
            let scene = MinesweeperScene(board: board, fx: MinesweeperEffects(count: board.size), viewport: shifted,
                                         now: Date().timeIntervalSinceReferenceDate, press: nil, veiled: false, calm: true)
            MinesweeperPainter(palette: palette).draw(scene, in: &context, size: size)
        }
        .accessibilityHidden(true)
    }
}

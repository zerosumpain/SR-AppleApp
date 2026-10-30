import SwiftUI

/// The big on-screen arrows, for younger players (and always under
/// VoiceOver). Each arrow turns the moment a finger lands on it, not when it
/// lifts, so a quick double tap makes a U-turn.
struct SnakePad: View {
    let onTurn: (SnakeDirection) -> Void
    var size: CGFloat = 62

    var body: some View {
        VStack(spacing: 6) {
            SnakePadKey(direction: .up, size: size, onTurn: onTurn)
            HStack(spacing: 6) {
                SnakePadKey(direction: .left, size: size, onTurn: onTurn)
                Circle()
                    .fill(SR.ink.opacity(0.06))
                    .frame(width: size * 0.62, height: size * 0.62)
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
                SnakePadKey(direction: .right, size: size, onTurn: onTurn)
            }
            SnakePadKey(direction: .down, size: size, onTurn: onTurn)
        }
        .accessibilityElement(children: .contain)
    }
}

struct SnakePadKey: View {
    let direction: SnakeDirection
    let size: CGFloat
    let onTurn: (SnakeDirection) -> Void
    @State private var down = false
    /// True only while a finger is on the key. A gesture the system cancels
    /// (a second finger, a call coming in) never reaches `onEnded`, but this
    /// resets itself, so the key cannot be left stuck down and dead.
    @GestureState private var touching = false

    private var icon: String {
        switch direction {
        case .up: return "arrowtriangle.up.fill"
        case .down: return "arrowtriangle.down.fill"
        case .left: return "arrowtriangle.left.fill"
        case .right: return "arrowtriangle.right.fill"
        }
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(down ? Color.white : SR.ink)
            .frame(width: size, height: size)
            .background(keyFace)
            .srGlassCard(.paper, radius: 18)
            .scaleEffect(down ? 0.92 : 1)
            .animation(.snappy(duration: 0.12), value: down)
            .contentShape(Rectangle())
            .gesture(press)
            .onChange(of: touching) { _, now in
                if !now { down = false }
            }
            .accessibilityElement()
            .accessibilityLabel("Turn \(direction.word)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTurn(direction) }
            .accessibilityIdentifier("snake-\(direction.rawValue)")
    }

    private var keyFace: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(down ? SR.accent : Color.clear)
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { _ in
                guard !down else { return }
                down = true
                onTurn(direction)
            }
            .onEnded { _ in down = false }
    }
}

/// A figure along the top: score, best, length.
struct SnakeStatBox: View {
    let title: String
    let value: Int
    var strong = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(value)")
                .font(SR.Text.figure(strong ? 24 : 20))
                .foregroundStyle(strong ? SR.accent : SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: value)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .srGlassCard(.paper, radius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}

/// How fast it is going: six pips that light as it speeds up.
struct SnakeSpeedPips: View {
    let level: Double

    var body: some View {
        let lit = level >= 0.999 ? 6 : Int((level * 6).rounded(.down)) + 1
        HStack(spacing: 3) {
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(index < lit ? pipColour(index) : SR.ink.opacity(0.12))
                    .frame(width: 9, height: 6 + CGFloat(index) * 1.5)
            }
        }
        .frame(height: 14, alignment: .bottom)
        .animation(.easeOut(duration: 0.2), value: lit)
        .accessibilityElement()
        .accessibilityLabel(level >= 0.999 ? "Top speed" : "Speed \(lit) of 6")
    }

    private func pipColour(_ index: Int) -> Color {
        index >= 4 ? SR.error : index >= 2 ? SR.warn : SR.good
    }
}

/// One of the three modes on the card.
struct SnakeModeTile: View {
    let mode: SnakeMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18, weight: .bold))
                    .accessibilityHidden(true)
                Text(mode.title)
                    .font(SR.Text.title(15))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? Color.white : SR.ink)
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.vertical, 4)
            .background(tileFace)
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(mode.title)
        .accessibilityHint(mode.line)
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityIdentifier("snake-mode-\(mode.rawValue)")
    }

    private var tileFace: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(selected ? SR.accent : SR.ink.opacity(0.07))
    }
}

/// A maze on the card: its walls in miniature, its name, and its best or
/// what opens it.
struct SnakeMazeChip: View {
    let maze: SnakeMaze
    let open: Bool
    let selected: Bool
    let best: Int
    let dark: Bool
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            HStack(spacing: 8) {
                SnakeMazeThumb(maze: maze, dark: dark)
                    .frame(width: 30)
                    .opacity(open ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if !open {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                                .accessibilityHidden(true)
                        }
                        Text(maze.name)
                            .font(SR.Text.title(14))
                            .lineLimit(1)
                    }
                    .foregroundStyle(SR.ink)
                    Text(detail)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 168, alignment: .leading)
            .frame(minHeight: 60)
            .background(chipFace)
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(open ? "\(maze.name). \(detail)" : "\(maze.name), locked. \(detail)")
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("snake-maze-\(maze.id)")
    }

    private var detail: String {
        if !open {
            let previous = maze.previous?.name ?? "the last maze"
            return "Score \(maze.unlockScore) on \(previous)"
        }
        return best > 0 ? "Best \(best)" : "Not played yet"
    }

    private var chipFace: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(selected ? SR.accent.opacity(0.16) : SR.ink.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? SR.accent : Color.clear, lineWidth: 2)
            )
    }
}

/// A colour for the snake, or a lock until enough apples have been eaten.
struct SnakeSkinSwatch: View {
    let skin: SnakeSkin
    let open: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                    .opacity(open ? 1 : 0.35)
                if !open {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SR.ink)
                }
                Circle()
                    .stroke(selected ? SR.accent : Color.clear, lineWidth: 3)
                    .frame(width: 48, height: 48)
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(open ? skin.title : "\(skin.title), locked. Eat \(skin.unlockApples) apples in all to open it.")
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityIdentifier("snake-skin-\(skin.rawValue)")
    }

    private var fill: AnyShapeStyle {
        let paint = SnakeSkinPaint.of(skin)
        if paint.rainbow {
            let colours: [Color] = [0.0, 0.16, 0.33, 0.5, 0.66, 0.83].map { Color(hue: $0, saturation: 0.72, brightness: 0.96) }
            return AnyShapeStyle(AngularGradient(colors: colours, center: .center, startAngle: .degrees(0), endAngle: .degrees(360)))
        }
        return AnyShapeStyle(LinearGradient(colors: [paint.main, paint.dark], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

/// One line of how to play: an icon in a tinted circle and the words.
struct SnakeHowRow: View {
    let icon: String
    let text: String
    var tint: Color = SR.accent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.14)))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A small figure with its label, on the cards.
struct SnakeStatChip: View {
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

/// Keeps a card's middle on screen whatever the text size: as it is when it
/// fits, scrolling when the reader's setting makes it taller than the room.
struct SnakeCardHolder<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }
}

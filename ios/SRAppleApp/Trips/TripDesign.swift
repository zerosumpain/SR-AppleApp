import SwiftUI

// The trip screens' own furniture (Trips v8, 2026-10-21), from the designer's
// mockups (Prism): a button label in sentence case that wraps, the four chip
// kinds, and the few colours with one job each.
//
// - Violet (`SR.accent`, filled `accentFill`) is the one action on a screen,
//   a selection, "You decide" and a proposed route — nothing else.
// - Amber means ASSUMED and nothing else: a guess the planner is working on,
//   with Right / Change beside it. Never a warning.
// - Red is overdue or at risk; green is confirmed, or "pushes out nothing".
//
// Cards are glass at `SR.Glass.radius` (26); anything inside a card 16
// (`SR.Glass.innerRadius`); buttons and chips are capsules. Every size here
// goes through `SR.Text` (Dynamic Type, a 12 pt floor) — no fixed fonts.
//
// The shared `SRButtonLabel` and `SRGlassChip` upper-case their text and are
// used app-wide, so they are left alone; trip screens use these instead.
// P2's files reference `TripButtonLabel` and `TripChip` by these names.

enum TripPalette {
    /// The one action, a selection, "You decide", a proposed route.
    static var accent: Color { SR.accent }
    /// The filled main button.
    static let accentFill = Color(light: 0x4426D6, dark: 0xA194FF)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0B0A1C)
    static let accentWash = Color(light: 0x5233F0, dark: 0xA194FF, alpha: 0.12)
    static let accentLine = Color(light: 0x5233F0, dark: 0xA194FF, alpha: 0.42)

    /// Amber: assumed — and only that.
    static let assumed = Color(light: 0x9A5B00, dark: 0xFFC24B)
    static let assumedWash = Color(light: 0xFFB800, dark: 0xFFC24B, alpha: 0.2)
    static let assumedLine = Color(light: 0x9A5B00, dark: 0xFFC24B, alpha: 0.38)

    /// Red: overdue, at risk.
    static var overdue: Color { SR.error }
    static let overdueWash = Color(light: 0xD7193F, dark: 0xFF6B85, alpha: 0.1)
    /// Green: confirmed, nothing pushed out.
    static var confirmed: Color { SR.good }

    /// A trade-off chip's ground: 5% ink.
    static let chipFill = Color(light: 0x15123A, dark: 0xF4F3FB, alpha: 0.06)
    /// The hairline round an answer chip or a dashed "add".
    static let line = Color(light: 0x15123A, dark: 0xF4F3FB, alpha: 0.16)

    /// The parts of the day, as on the map. The evening's ink disappears on
    /// a dark ground, so dark mode lifts it.
    static func stage(_ stage: DayStage) -> Color {
        switch stage {
        case .morning: return Color(hex: 0x1E63E9)
        case .lunch: return Color(hex: 0xE62E5C)
        case .afternoon: return Color(hex: 0xE85D00)
        case .evening: return Color(light: 0x15123A, dark: 0x5A55A8)
        }
    }

    /// A day's colour on the trip's map.
    static func day(_ index: Int) -> Color { Color(hex: TripMapScene.dayColor(index)) }
}

// MARK: - Buttons

/// A button's label on a trip screen: sentence case, and it wraps rather
/// than truncating at large text sizes. The icon scales with the text.
/// `fill` stretches it to the width it is given.
struct TripButtonLabel: View {
    let title: String
    var icon: String?
    var fill: Bool

    init(_ title: String, icon: String? = nil, fill: Bool = false) {
        self.title = title
        self.icon = icon
        self.fill = fill
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(SR.Text.title(15))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(SR.Text.title(16))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: fill ? .infinity : nil)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

/// The one filled violet button a trip screen has: "Start planning", "Use
/// this plan", "Use this". Everything else is `.srButton(.regular)`.
struct TripPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(TripPalette.onAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .background(Capsule().fill(TripPalette.accentFill.opacity(enabled ? 1 : 0.45)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// The screen's one filled action.
    func tripPrimary() -> some View { buttonStyle(TripPrimaryButtonStyle()) }
}

// MARK: - Chips

/// The trip screens' chips, in the mockups' four kinds (and two tones):
///
/// - `brief(origin)`: a fact of the brief, 30 pt glass with its icon — amber
///   when the planner assumed it;
/// - `tradeoff`: what a proposal costs or gives, 28 pt on 5% ink;
///   `highlight` is the same in violet (less visited);
/// - `answer(isDefault:)`: a question's answer, 48 pt glass that wraps and
///   never truncates — "You decide" in violet;
/// - `nudge`: "Closer", "Cheaper"…, 36 pt on a violet wash;
/// - `warning`: at risk or overdue, in red.
///
/// A chip is a look, not a button: wrap it in `Button` (plain style) where it
/// acts, and give it a VoiceOver label there.
struct TripChip: View {
    enum Style: Equatable {
        case brief(FactSource)
        case tradeoff
        case answer(isDefault: Bool)
        case nudge
        case warning
        case highlight
    }

    let text: String
    var icon: String?
    var style: Style

    init(_ text: String, icon: String? = nil, style: Style) {
        self.text = text
        self.icon = icon
        self.style = style
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(iconFont)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }
            label
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 6)
        .frame(minHeight: minHeight)
        .background { ground }
        .overlay { rim }
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var label: some View {
        if case .brief(.assumed) = style {
            (Text(text) + Text(" · assumed").font(SR.Text.label(13)))
                .font(font)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(font)
                .multilineTextAlignment(isAnswer ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isAnswer: Bool {
        if case .answer = style { return true }
        return false
    }

    private var font: Font {
        switch style {
        case .answer: return SR.Text.title(16)
        case .nudge: return SR.Text.title(14)
        default: return SR.Text.title(13)
        }
    }

    private var iconFont: Font {
        switch style {
        case .answer: return SR.Text.title(15)
        default: return SR.Text.label(12)
        }
    }

    private var minHeight: CGFloat {
        switch style {
        case .brief: return 30
        case .tradeoff, .warning, .highlight: return 28
        case .answer: return 48
        case .nudge: return 36
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .answer: return 18
        case .nudge: return 14
        default: return 10
        }
    }

    private var textColor: Color {
        switch style {
        case .brief(let origin): return origin == .assumed ? TripPalette.assumed : SR.ink
        case .tradeoff: return SR.inkSecondary
        case .answer(let isDefault): return isDefault ? TripPalette.accent : SR.ink
        case .nudge, .highlight: return TripPalette.accent
        case .warning: return TripPalette.overdue
        }
    }

    private var iconColor: Color {
        switch style {
        case .brief(let origin): return origin == .assumed ? TripPalette.assumed : SR.inkSecondary
        default: return textColor
        }
    }

    @ViewBuilder
    private var ground: some View {
        switch style {
        case .brief(let origin) where origin == .assumed:
            Capsule().fill(TripPalette.assumedWash)
        case .brief:
            Color.clear.srGlass(.paper, in: Capsule())
        case .tradeoff:
            Capsule().fill(TripPalette.chipFill)
        case .answer(let isDefault):
            if isDefault { Capsule().fill(TripPalette.accentWash) } else { Color.clear.srGlass(.paper, in: Capsule()) }
        case .nudge, .highlight:
            Capsule().fill(TripPalette.accentWash)
        case .warning:
            Capsule().fill(TripPalette.overdueWash)
        }
    }

    @ViewBuilder
    private var rim: some View {
        switch style {
        case .brief(let origin) where origin == .assumed:
            Capsule().strokeBorder(TripPalette.assumedLine, lineWidth: 1)
        case .answer(let isDefault):
            Capsule().strokeBorder(isDefault ? TripPalette.accentLine : TripPalette.line, lineWidth: 1.5)
        default:
            EmptyView()
        }
    }
}

// MARK: - Layout

/// Chips that wrap onto as many lines as they need — never a row that runs
/// off the screen at a large text size.
struct TripFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, min(x - spacing, width))
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

/// A section's heading on a trip screen: a title, and a quiet note at the
/// trailing edge ("Each changes the plan", "2, in date order").
struct TripSectionHeading: View {
    let title: String
    var note: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(SR.Text.title(17))
                .foregroundStyle(SR.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let note {
                Text(note)
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkMuted)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The page dots under a pager: the current one a violet bar.
struct TripPageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? TripPalette.accent : SR.inkMuted.opacity(0.5))
                    .frame(width: i == current ? 20 : 7, height: 7)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(current + 1) of \(count)")
    }
}

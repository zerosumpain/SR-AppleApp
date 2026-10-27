import SwiftUI

/// A tile's chrome: the hue, the corner, the header, and the press.
///
/// Two looks. `.vivid` is the hue's own gradient with white (or, on the two
/// bright hues, indigo) type — the dashboard's colour. `.glass` is a lifted
/// white sheet for the one tile whose picture is itself colour-coded (the
/// family, where every person is a hue and a coral ground would swallow them).
struct HomeTileFrame<Content: View>: View {
    let kind: HomeTileKind
    var look: Look = .vivid
    /// A short figure top-right — "3", "NEW".
    var badge: String? = nil
    @ViewBuilder var content: Content

    enum Look: Equatable {
        case vivid, glass
        /// The daydream's still aurora, at a strength.
        case aurora(Double)
    }

    static var corner: CGFloat { 28 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(vivid ? kind.hue.onFill : SR.ink)
        .background { fill(shape) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(vivid ? 0.22 : 0.5), lineWidth: 1))
        .shadow(color: (vivid ? kind.hue.base : SR.ink).opacity(vivid ? 0.28 : 0.08), radius: 14, y: 6)
        // The whole tile is the target. On iOS 26 glass is not a hit-testable
        // background, so without this only the drawn type answered a tap.
        .contentShape(shape)
    }

    /// Coloured ground, light type: everything but the glass sheet.
    private var vivid: Bool { look != .glass }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(vivid ? kind.hue.base : .white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(vivid ? kind.hue.onFill.opacity(0.92) : kind.hue.base))
                .accessibilityHidden(true)
            // The tile's name wins over its badge: a square tile is narrow,
            // and "2 FAILING" once squeezed "Flows" down to an ellipsis.
            Text(kind.title)
                .font(SR.Text.title(15))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(2)
            Spacer(minLength: 4)
            if let badge {
                Text(badge)
                    .font(SR.Text.label(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(vivid ? kind.hue.onFill.opacity(0.22) : kind.hue.wash))
                    .foregroundStyle(vivid ? kind.hue.onFill : SR.ink)
                    .layoutPriority(1)
            }
        }
    }

    @ViewBuilder
    private func fill(_ shape: RoundedRectangle) -> some View {
        switch look {
        case .vivid:
            ZStack {
                kind.hue.gradient
                // A sheen top-left: the gradient alone reads as flat paint.
                RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 220)
            }
        case .glass:
            Color.clear.srGlass(.paper, in: shape)
        case .aurora(let strength):
            ZStack {
                kind.hue.gradient
                AuroraField(intensity: strength).opacity(0.85)
            }
        }
    }
}

/// The figure at the foot of a tile: big number, small words.
///
/// Everything here gives way rather than spilling: the figure shrinks to half
/// before it is cut, the unit keeps its size beside it, and the caption is
/// cut with an ellipsis at its line limit.
struct HomeFigure: View {
    let value: String
    var unit: String? = nil
    var caption: String? = nil
    var size: CGFloat = 30
    var captionLines = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(SR.Text.figure(size))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let unit {
                    Text(unit)
                        .font(SR.Text.label(13))
                        .lineLimit(1)
                        .fixedSize()
                        .opacity(0.85)
                }
            }
            if let caption {
                Text(caption)
                    .font(SR.Text.secondary(13))
                    .opacity(0.9)
                    .lineLimit(captionLines)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: captionLines > 1)
            }
        }
    }
}

/// A tile as a button: one tap goes where the feature is; a long press offers
/// taking it off Home, arranging Home, or changing its colours.
///
/// `keepsChildren`: a tap target that is NOT a `Button`, for a tile whose
/// picture has parts of its own — the Orbit's people, each a VoiceOver
/// element. A `Button` folds everything inside it into one element.
struct HomeTileButton<Content: View>: View {
    let kind: HomeTileKind
    let id: String
    let action: () -> Void
    var hide: (() -> Void)? = nil
    var customise: (() -> Void)? = nil
    var keepsChildren = false
    @ViewBuilder var label: Content
    @Environment(\.homeColours) private var colours

    var body: some View {
        Group {
            if keepsChildren {
                label
                    .contentShape(RoundedRectangle(cornerRadius: HomeTileFrame<EmptyView>.corner, style: .continuous))
                    .onTapGesture {
                        SRHaptic.tap()
                        action()
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { action() }
            } else {
                Button {
                    SRHaptic.tap()
                    action()
                } label: {
                    label
                }
                .buttonStyle(SRPressStyle())
                .accessibilityAddTraits(.isButton)
            }
        }
        .contextMenu {
            if let hide {
                Button { hide() } label: { Label("Hide from Home", systemImage: "eye.slash") }
            }
            if let customise {
                Button { customise() } label: { Label("Arrange Home…", systemImage: "square.grid.2x2") }
            }
            if let colours {
                Button { colours() } label: { Label("Colours…", systemImage: "paintpalette") }
            }
        }
        .accessibilityIdentifier(id)
    }
}

/// "Colours…" on a tile's long-press menu: Home sets it to open the palette
/// sheet. An environment value rather than a parameter, so the fifteen tiles
/// that already take `hide` and `customise` do not each grow a third.
private struct HomeColoursKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var homeColours: (() -> Void)? {
        get { self[HomeColoursKey.self] }
        set { self[HomeColoursKey.self] = newValue }
    }
}

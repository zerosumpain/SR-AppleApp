import SwiftUI
import UIKit

// MARK: - The pad

/// The buttons along the bottom: a strip per player (one for solo), drawn in
/// SwiftUI, with a multi-touch `UIView` on top that reads every finger.
struct TetherPalsPad: View {
    @ObservedObject var session: TetherPalsSession
    let rowHeight: CGFloat

    var body: some View {
        GeometryReader { geo in
            padStack(size: geo.size)
        }
        .frame(height: rowHeight * CGFloat(session.players.strips))
        .opacity(session.scripted ? 0.85 : 1)
    }

    private var live: Bool { session.stage == .ready || session.stage == .playing }

    private func padStack(size: CGSize) -> some View {
        let strips = session.players.strips
        let buttons = TetherPalsPadLayout.buttons(width: Double(size.width), height: Double(size.height),
                                                  strips: strips, solo: session.solo)
        return ZStack {
            TetherPalsPadArt(buttons: buttons, holds: session.holds, solo: session.solo,
                             active: session.active, team: session.team)
                .accessibilityHidden(true)
            TetherPalsTouchPad(session: session, strips: strips, solo: session.solo, live: live)
                .accessibilityIdentifier("tether-pals-pad")
        }
    }
}

/// The drawn keys, lit while held.
struct TetherPalsPadArt: View {
    let buttons: [TetherPalsPadButton]
    let holds: [TetherPalsHold]
    let solo: Bool
    let active: Int
    let team: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                key(button)
                    .frame(width: CGFloat(button.width), height: CGFloat(button.height))
                    .position(x: CGFloat(button.x + button.width / 2), y: CGFloat(button.y + button.height / 2))
            }
        }
    }

    private func key(_ button: TetherPalsPadButton) -> TetherPalsKeyView {
        let pal = solo ? active : button.player
        let hold = button.player < holds.count ? holds[button.player] : TetherPalsHold()
        let pressed: Bool
        switch button.key {
        case .left: pressed = hold.left
        case .right: pressed = hold.right
        case .jump: pressed = hold.jump
        case .swap: pressed = false
        }
        return TetherPalsKeyView(key: button.key, pal: pal, next: (active + 1) % max(1, team), pressed: pressed)
    }
}

/// One key of a strip, in its pal's colour.
struct TetherPalsKeyView: View {
    let key: TetherPalsKey
    let pal: Int
    let next: Int
    let pressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return label
            .foregroundStyle(TetherPalsPalette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(TetherPalsPalette.palDeep(tint).opacity(pressed ? 1 : 0.55), lineWidth: pressed ? 3 : 1.5))
            .scaleEffect(pressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }

    private var tint: Int { key == .swap ? next : pal }

    private var fill: Color {
        let colour = TetherPalsPalette.pal(tint)
        return pressed ? TetherPalsPalette.palDeep(tint).opacity(0.75) : colour.opacity(key == .swap ? 0.55 : 0.85)
    }

    @ViewBuilder
    private var label: some View {
        switch key {
        case .left:
            glyph("arrowtriangle.left.fill")
        case .right:
            glyph("arrowtriangle.right.fill")
        case .jump:
            HStack(spacing: 6) {
                glyph("arrow.up")
                Text("\(TetherPalsCast.name(pal)) jump".uppercased())
                    .font(SR.Text.label(13))
                    .tracking(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 6)
        case .swap:
            VStack(spacing: 2) {
                glyph("arrow.triangle.2.circlepath")
                Text("SWAP")
                    .font(SR.Text.label(11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 22, weight: .heavy))
    }
}

/// Every finger on the pad, tracked on its own so several thumbs work at
/// once. A finger keeps the strip it started on but can slide between ◀, ▶
/// and Jump. UIKit rather than a SwiftUI gesture, as Pinball's flippers: a
/// gesture sees one finger and answers a frame late.
struct TetherPalsTouchPad: UIViewRepresentable {
    let session: TetherPalsSession
    let strips: Int
    let solo: Bool
    /// False under a card: every finger is forgotten, so nothing stays held.
    let live: Bool

    func makeUIView(context: Context) -> TetherPalsTouchView {
        let view = TetherPalsTouchView()
        view.configure(session: session, strips: strips, solo: solo, live: live)
        return view
    }

    func updateUIView(_ view: TetherPalsTouchView, context: Context) {
        view.configure(session: session, strips: strips, solo: solo, live: live)
    }
}

final class TetherPalsTouchView: UIView {
    private weak var session: TetherPalsSession?
    private var strips = 1
    private var solo = true
    private var fingers: [ObjectIdentifier: (player: Int, key: TetherPalsKey)] = [:]
    /// The navigation stack's swipe-back, off while the pad is on screen: a
    /// thumb sliding on ◀ ▶ would otherwise pull the game away.
    private let hold = SwipeBackHold()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityTraits = [.allowsDirectInteraction]
        accessibilityLabel = "Buttons"
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
    }

    func configure(session: TetherPalsSession, strips: Int, solo: Bool, live: Bool) {
        let changed = self.strips != strips || self.solo != solo || self.session !== session
        self.session = session
        self.strips = strips
        self.solo = solo
        if changed {
            fingers = [:]
            installActions()
        }
        if !live { fingers = [:] }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        hold.update(for: self)
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        var pressed: [(player: Int, key: TetherPalsKey)] = []
        for touch in touches {
            let point = touch.location(in: self)
            guard let hit = TetherPalsPadLayout.hit(x: Double(point.x), y: Double(point.y), width: Double(bounds.width),
                                                    height: Double(bounds.height), strips: strips, solo: solo) else { continue }
            fingers[ObjectIdentifier(touch)] = hit
            pressed.append(hit)
        }
        report(pressed)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var changed = false
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let finger = fingers[id] else { continue }
            let x = min(max(0, touch.location(in: self).x), bounds.width)
            let key = TetherPalsPadLayout.key(atX: Double(x), width: Double(bounds.width), solo: solo)
            if key != finger.key {
                fingers[id] = (finger.player, key)
                changed = true
            }
        }
        if changed { report([]) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    private func finish(_ touches: Set<UITouch>) {
        for touch in touches { fingers[ObjectIdentifier(touch)] = nil }
        report([])
    }

    private func report(_ pressed: [(player: Int, key: TetherPalsKey)]) {
        session?.touches(Array(fingers.values), pressed: pressed)
    }

    // MARK: - VoiceOver

    private func installActions() {
        var actions: [UIAccessibilityCustomAction] = []
        if solo {
            actions = [
                UIAccessibilityCustomAction(name: "Step left", target: self, selector: #selector(activeLeft)),
                UIAccessibilityCustomAction(name: "Step right", target: self, selector: #selector(activeRight)),
                UIAccessibilityCustomAction(name: "Jump", target: self, selector: #selector(activeJump)),
                UIAccessibilityCustomAction(name: "Swap pal", target: self, selector: #selector(swapPal)),
            ]
        } else {
            let table: [(Selector, Selector, Selector)] = [
                (#selector(pipLeft), #selector(pipRight), #selector(pipJump)),
                (#selector(boLeft), #selector(boRight), #selector(boJump)),
                (#selector(kitLeft), #selector(kitRight), #selector(kitJump)),
            ]
            for pal in 0..<min(strips, table.count) {
                let name = TetherPalsCast.name(pal)
                actions.append(UIAccessibilityCustomAction(name: "\(name): step left", target: self, selector: table[pal].0))
                actions.append(UIAccessibilityCustomAction(name: "\(name): step right", target: self, selector: table[pal].1))
                actions.append(UIAccessibilityCustomAction(name: "\(name): jump", target: self, selector: table[pal].2))
            }
        }
        accessibilityCustomActions = actions
        accessibilityHint = solo
            ? "Swipe up or down for step left, step right, jump and swap pal."
            : "Swipe up or down to choose a pal's step or jump."
    }

    /// A step (or, with no direction, a jump) for a pal; -1 is whoever solo drives.
    private func act(_ pal: Int, direction: Int) -> Bool {
        guard let session else { return false }
        let index = pal < 0 ? session.active : pal
        if direction == 0 {
            session.jump(index)
        } else {
            session.step(index, direction: direction)
        }
        return true
    }

    @objc private func activeLeft() -> Bool { act(-1, direction: -1) }
    @objc private func activeRight() -> Bool { act(-1, direction: 1) }
    @objc private func activeJump() -> Bool { act(-1, direction: 0) }
    @objc private func pipLeft() -> Bool { act(0, direction: -1) }
    @objc private func pipRight() -> Bool { act(0, direction: 1) }
    @objc private func pipJump() -> Bool { act(0, direction: 0) }
    @objc private func boLeft() -> Bool { act(1, direction: -1) }
    @objc private func boRight() -> Bool { act(1, direction: 1) }
    @objc private func boJump() -> Bool { act(1, direction: 0) }
    @objc private func kitLeft() -> Bool { act(2, direction: -1) }
    @objc private func kitRight() -> Bool { act(2, direction: 1) }
    @objc private func kitJump() -> Bool { act(2, direction: 0) }

    @objc private func swapPal() -> Bool {
        session?.swap()
        return true
    }
}

// MARK: - HUD and card pieces

/// A figure in the HUD, in its own glass box.
struct TetherPalsStatBox: View {
    let title: String
    let value: String
    var strong = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(SR.Text.figure(strong ? 24 : 20))
                .foregroundStyle(strong ? SR.accent : SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .srGlassCard(.paper, radius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}

/// A symbol and one sentence, on the cards.
struct TetherPalsHowRow: View {
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
struct TetherPalsStatChip: View {
    let label: String
    let value: String
    var icon: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.95, green: 0.7, blue: 0.1))
                        .accessibilityHidden(true)
                }
                Text(value)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(SR.ink.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

/// Keeps a card's middle on screen whatever the text size: as it is when it
/// fits, scrolling when it is taller than the room.
struct TetherPalsCardHolder<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }
}

/// "Press any button to start", with the level's tip, over the board.
struct TetherPalsReadyHint: View {
    let tip: String
    let resuming: Bool
    @State private var lifted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            if !resuming {
                Text(tip)
                    .font(SR.Text.secondary(13))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)
                Text(resuming ? "Press any button to carry on" : "Press any button to start")
                    .font(SR.Text.title(14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.58)))
        .offset(y: lifted ? -3 : 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatCount(12, autoreverses: true)) { lifted = true }
        }
    }
}

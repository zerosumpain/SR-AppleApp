import SwiftUI
import UIKit

/// The flipper buttons: the whole play area, split down the middle. Every
/// finger is tracked on its own, so both flippers can be held at once, and a
/// touch keeps the side it started on even if it slides across.
///
/// UIKit rather than a SwiftUI gesture: a gesture reports a frame or more
/// late and sees one finger, and a flipper has to answer the instant it is
/// pressed. While a ball waits on the plunger, a finger on the right-hand
/// side pulls the plunger instead: drag down to draw it back, let go to fire.
struct PinballTouchPad: UIViewRepresentable {
    let engine: PinballEngine

    func makeUIView(context: Context) -> PinballTouchView {
        let view = PinballTouchView()
        view.engine = engine
        return view
    }

    func updateUIView(_ view: PinballTouchView, context: Context) {
        view.engine = engine
    }
}

final class PinballTouchView: UIView {
    private enum Role {
        case left, right, plunger
    }

    weak var engine: PinballEngine?
    private var roles: [ObjectIdentifier: Role] = [:]
    private var plungerStart: CGFloat = 0
    /// How far a finger drags for a full pull.
    private let fullPull: CGFloat = 130

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityTraits = [.allowsDirectInteraction]
        accessibilityLabel = "Pinball table"
        accessibilityHint = "Touch the left or right side to flip. Swipe up or down for more actions."
        installActions()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        installActions()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let engine else { return }
        for touch in touches {
            let point = touch.location(in: self)
            let rightSide = point.x >= bounds.midX
            let role: Role
            if rightSide && engine.plungerReady && !roles.values.contains(.plunger) {
                role = .plunger
                plungerStart = point.y
                engine.setPull(0)
            } else {
                role = rightSide ? .right : .left
            }
            roles[ObjectIdentifier(touch)] = role
        }
        refresh()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let engine else { return }
        for touch in touches where roles[ObjectIdentifier(touch)] == .plunger {
            let drag = touch.location(in: self).y - plungerStart
            engine.setPull(Double(max(0, drag) / fullPull))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    private func finish(_ touches: Set<UITouch>) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            if roles[key] == .plunger { engine?.releasePlunger() }
            roles[key] = nil
        }
        refresh()
    }

    private func refresh() {
        let held = Set(roles.values)
        engine?.setFlippers(left: held.contains(.left), right: held.contains(.right))
    }

    // MARK: - Swipe back

    /// The navigation stack's edge swipe, off while the table is on screen: a
    /// thumb sliding on the left flipper would otherwise pull the whole game
    /// away mid-ball. The back button still leaves; the swipe comes back the
    /// moment the table goes.
    private weak var popGesture: UIGestureRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            guard popGesture == nil, let gesture = Self.navigationController(above: self)?.interactivePopGestureRecognizer else { return }
            gesture.isEnabled = false
            popGesture = gesture
        } else {
            popGesture?.isEnabled = true
            popGesture = nil
        }
    }

    private static func navigationController(above view: UIView) -> UINavigationController? {
        var responder: UIResponder? = view.next
        while let current = responder {
            if let controller = current as? UIViewController, let navigation = controller.navigationController {
                return navigation
            }
            responder = current.next
        }
        return nil
    }

    // MARK: - VoiceOver

    private func installActions() {
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Left flipper", target: self, selector: #selector(flipLeft)),
            UIAccessibilityCustomAction(name: "Right flipper", target: self, selector: #selector(flipRight)),
            UIAccessibilityCustomAction(name: "Launch the ball", target: self, selector: #selector(launchBall)),
            UIAccessibilityCustomAction(name: "Nudge the table", target: self, selector: #selector(nudgeTable)),
        ]
    }

    @objc private func flipLeft() -> Bool {
        engine?.tapFlipper(.left)
        return true
    }

    @objc private func flipRight() -> Bool {
        engine?.tapFlipper(.right)
        return true
    }

    @objc private func launchBall() -> Bool {
        guard let engine, engine.plungerReady else { return false }
        engine.setPull(0.42)
        engine.releasePlunger()
        return true
    }

    @objc private func nudgeTable() -> Bool {
        engine?.nudge()
        return true
    }
}

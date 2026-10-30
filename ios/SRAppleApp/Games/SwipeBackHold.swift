import SwiftUI
import UIKit

/// Holds the navigation stack's swipe-back off while a game's play surface is
/// on screen. Since iOS 26 a rightward drag anywhere on a pushed screen, not
/// only from the left edge, is the stack's "back", so panning a board or
/// sliding a thumb pulled the whole game off the screen and closed it. The
/// back button still leaves; both swipes come back the moment the surface
/// goes. Only gestures this hold switched off are switched back on, so two
/// surfaces on screen at once don't fight.
@MainActor
final class SwipeBackHold {
    private var held: [UIGestureRecognizer] = []

    /// Call from the owning view's `didMoveToWindow`.
    func update(for view: UIView) {
        if view.window != nil {
            guard held.isEmpty, let navigation = Self.navigationController(above: view) else { return }
            var gestures = [navigation.interactivePopGestureRecognizer]
            if #available(iOS 26.0, *) { gestures.append(navigation.interactiveContentPopGestureRecognizer) }
            held = gestures.compactMap { $0 }.filter(\.isEnabled)
            held.forEach { $0.isEnabled = false }
        } else {
            release()
        }
    }

    private func release() {
        held.forEach { $0.isEnabled = true }
        held = []
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
}

extension View {
    /// Keeps swipe-back from leaving the screen while this view is showing.
    /// For play surfaces that own their drags (a board that pans, a map).
    func holdingSwipeBack() -> some View {
        background(SwipeBackHoldAnchor().allowsHitTesting(false))
    }
}

/// An invisible view whose only job is to know when it joins a window.
private struct SwipeBackHoldAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> AnchorView { AnchorView() }
    func updateUIView(_ uiView: AnchorView, context: Context) {}

    final class AnchorView: UIView {
        private let hold = SwipeBackHold()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            hold.update(for: self)
        }
    }
}

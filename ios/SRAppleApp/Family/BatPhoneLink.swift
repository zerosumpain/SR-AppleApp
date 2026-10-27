import SwiftUI
import UIKit

/// The way into the bat phone from outside the app: the Home Screen and Lock
/// Screen widget (`sr://batphone`), the Control Center control and a
/// Shortcut (`OpenBatPhoneIntent`). Each lands on `BatPhoneConfirmSheet` —
/// never a send — because a widget is brushed by accident far more often
/// than a button in the app is pressed by one.
///
/// A box rather than a call on the router: the intent runs with no view in
/// reach, and on a cold launch before `ContentView` exists. `ContentView`
/// watches `pending` (a `@Published` value is handed to a new subscriber at
/// once, so a request made before it appeared is still seen) and opens the
/// sheet.
@MainActor
final class BatPhoneLink: ObservableObject {
    static let shared = BatPhoneLink()

    @Published private(set) var pending = false
    /// The check is on screen now. Set by the sheet itself, not by whoever
    /// asked for it: asking is no proof it showed.
    private(set) var showing = false

    /// Whoever has msg family has the bat phone; the demo shows it to anyone.
    static var allowed: Bool { SRDemo.isOn || AccessStore.shared.familyBoards }

    /// Set even when already set: `$pending` re-sends every assignment, so a
    /// second tap retries a request the first could not show.
    func open() {
        guard Self.allowed else { return }
        pending = true
    }

    /// The request is spent — only once the sheet has appeared, or there is
    /// nothing to show. Spent on asking, a sheet that never came up (another
    /// modal in the way) left the widget dead until relaunch.
    func taken() {
        pending = false
    }

    func appeared() {
        showing = true
        taken()
    }

    func disappeared() {
        showing = false
    }
}

extension Router {
    /// The bat phone's check, over whatever was open. The root's one modal
    /// slot (`sheet`) cannot show while anything else is presented — Settings
    /// is in that slot, but a screen's own sheet or cover (a compose sheet, a
    /// game) is not, and SwiftUI then drops the request with only a log
    /// line. So whatever is up is closed first, and the slot is emptied
    /// before it is filled, so a value left there by a request that never
    /// showed is a change again.
    func openBatPhone() {
        let link = BatPhoneLink.shared
        guard BatPhoneLink.allowed else { link.taken(); return }
        // Already in front: nothing to do.
        guard !link.showing else { link.taken(); return }
        // Somebody else's alarm outranks the check; the request waits, and
        // the next tap after it is dismissed shows it.
        guard FamilyAlarmStore.shared.incoming == nil else { return }
        if let root = Self.rootController, root.presentedViewController != nil {
            // Closing it through UIKit resets the SwiftUI binding that showed
            // it, as a swipe down does.
            root.dismiss(animated: true) {
                Task { @MainActor [weak self] in self?.fillBatPhoneSlot() }
            }
        } else {
            fillBatPhoneSlot()
        }
    }

    /// Empty, then fill on the next turn of the run loop: setting the value
    /// the slot already holds would change nothing and show nothing.
    private func fillBatPhoneSlot() {
        sheet = nil
        DispatchQueue.main.async { [weak self] in self?.sheet = .batPhone }
    }

    private static var rootController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

/// What a bat phone widget, control or Shortcut opens: what it does, and the
/// one button that does it. The button keeps its own guard against a slip
/// (`BatPhoneButton`); this sheet is the guard against the widget.
struct BatPhoneConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: BatPhoneLook.symbol)
                    .font(SR.Text.display(28))
                    .foregroundStyle(Color.white)
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(SR.error))
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("Bat phone")
                        .font(SR.Text.display(24))
                        .foregroundStyle(SR.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Messages the family group that you need them. Nothing is sent until you use the button below.")
                        .font(SR.Text.secondary(15))
                        .foregroundStyle(SR.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                BatPhoneButton()
                Button("Not now") { dismiss() }
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.inkSecondary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("bat-phone-cancel")
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 28)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .background(SR.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("bat-phone-confirm")
        .onAppear { BatPhoneLink.shared.appeared() }
        .onDisappear { BatPhoneLink.shared.disappeared() }
    }
}

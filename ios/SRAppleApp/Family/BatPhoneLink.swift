import SwiftUI

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

    /// Whoever has msg family has the bat phone; the demo shows it to anyone.
    static var allowed: Bool { SRDemo.isOn || AccessStore.shared.familyBoards }

    func open() {
        guard Self.allowed else { return }
        pending = true
    }

    /// The sheet is on its way: the request is spent.
    func taken() {
        pending = false
    }
}

extension Router {
    /// The bat phone's check, over whatever was open — the one modal slot
    /// (`sheet`), so it replaces Settings or the inbox rather than silently
    /// failing behind them.
    func openBatPhone() {
        BatPhoneLink.shared.taken()
        guard BatPhoneLink.allowed else { return }
        sheet = .batPhone
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
    }
}

import SwiftUI
import UIKit

/// Light, dark, or whatever the phone is set to.
///
/// The palette in `Theme.swift` is a light/dark pair throughout, so the whole
/// app follows the window's interface style. This is the reader's override of
/// it, from Settings › Appearance.
///
/// Applied to the WINDOW (`overrideUserInterfaceStyle`), not as SwiftUI's
/// `.preferredColorScheme`: the window covers what UIKit presents on the app's
/// behalf too — an alert, an action sheet, the share sheet, the camera picker —
/// and going back to "System" actually lets go, which `.preferredColorScheme(nil)`
/// does not reliably do.
enum SRAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let key = "sr.appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Paint every window this app has with the choice.
    @MainActor func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}

private struct SRAppearanceRoot: ViewModifier {
    @AppStorage(SRAppearance.key) private var appearance: SRAppearance = .system

    func body(content: Content) -> some View {
        content
            .onAppear { appearance.apply() }
            .onChange(of: appearance) { _, next in next.apply() }
    }
}

extension View {
    /// The window root: keep every window on the reader's appearance choice.
    func srAppearanceRoot() -> some View { modifier(SRAppearanceRoot()) }
}

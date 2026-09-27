import SwiftUI
import UIKit

/// A tab bar item with its glyph drawn about a third larger than the system's.
///
/// Why: on iOS 26 the bar shrinks to one icon in a pill while you scroll, and
/// the system draws that icon small — too small to read at a glance. There is
/// no API for the pill's glyph size, and the app is never told when the bar is
/// collapsed (only a bottom ACCESSORY is), so the one lever is the image
/// itself: the bar draws a plain bitmap at its own size, where it re-sizes a
/// named symbol to its default. That makes the full bar's icons bigger too —
/// John's call (2026-09-27), at 35% rather than 50% so the full bar holds.
///
/// Rendered to a bitmap on purpose: `Image(uiImage:)` of a SYMBOL image is
/// still re-configured by the bar. Template, so selection still tints it.
enum SRTabIcon {
    /// The system's tab glyph is ~18 pt; this is 35% over it.
    static let pointSize: CGFloat = 24

    @MainActor private static var cache: [String: UIImage] = [:]

    @MainActor
    static func image(_ symbol: String) -> UIImage {
        if let hit = cache[symbol] { return hit }
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let glyph = UIImage(systemName: symbol, withConfiguration: config) else { return UIImage() }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let bitmap = UIGraphicsImageRenderer(size: glyph.size, format: format).image { _ in
            glyph.withTintColor(.black, renderingMode: .alwaysOriginal).draw(at: .zero)
        }
        let image = bitmap.withRenderingMode(.alwaysTemplate)
        cache[symbol] = image
        return image
    }

    /// `Label(title, systemImage:)` with the larger glyph. The title is the
    /// same text, so UI tests that find a tab by its name still do.
    @MainActor
    static func label(_ title: String, _ symbol: String) -> some View {
        Label { Text(title) } icon: { Image(uiImage: image(symbol)) }
    }
}

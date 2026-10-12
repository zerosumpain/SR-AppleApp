import SwiftUI

/// The shared tokens (`SRTokens.swift`) as SwiftUI colours, for every target.
///
/// `SRTokens.swift` is generated in SR-Infra (`design/tokens.json`, built by
/// `npm run tokens`) and copied here unedited; it is plain data so the Watch
/// and the extensions can compile it. This file is the one step from that data
/// to a `Color`. The mode-following pair lives in `Theme.swift`, because it
/// needs UIKit, which the Watch does not have.
extension Color {
    /// One side of a token, fixed: the same colour in light and dark.
    init(token rgba: SRRGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

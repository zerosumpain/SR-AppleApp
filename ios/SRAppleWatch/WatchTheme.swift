import SwiftUI

/// The ink register, on a wrist: cream type on ink, one accent. watchOS is
/// always dark, and the site's ink band is the part of its palette made for
/// that. Two faces only — Inter Display for figures, JetBrains Mono for labels.
enum WatchInk {
    // From the shared tokens (`Shared/SRTokens.swift`): the band's day values,
    // which is what the phone's ink band shows too.
    static let ground = Color(token: SRTokens.Colour.chromeBg.light)
    static let cream = Color(token: SRTokens.Colour.chromeInk.light)
    static let creamSoft = Color(token: SRTokens.Colour.onInk70.light)
    static let creamFaint = Color(token: SRTokens.Colour.onInk45.light)
    static let accent = Color(token: SRTokens.Colour.accentOnDark.light)
    static let good = Color(token: SRTokens.Colour.goodOnDark.light)
    static let warn = Color(token: SRTokens.Colour.warn.light)
    /// The app's error-on-ink, which has no site token.
    static let bad = Color(red: 0xE0 / 255, green: 0x8B / 255, blue: 0x8B / 255)

    /// Scaled with the wearer's text size, like every face in the phone app.
    static func figure(_ size: CGFloat) -> Font {
        .custom("InterDisplay-ExtraBold", size: size, relativeTo: .title3)
    }

    static func label(_ size: CGFloat = 12) -> Font {
        .custom("JetBrainsMono-Medium", size: size, relativeTo: .caption2)
    }

    static func mono(_ size: CGFloat = 13) -> Font {
        .custom("JetBrainsMono-Regular", size: size, relativeTo: .footnote)
    }

    static func severity(_ severity: String) -> Color {
        switch severity {
        case "alert", "high": return bad
        case "warn": return warn
        default: return creamFaint
        }
    }
}

/// A score as a ring with its number inside.
struct WatchRing: View {
    let fraction: Double?
    let value: String
    let tint: Color
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: lineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0, min(1, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(value)
                .font(WatchInk.figure(15))
                .foregroundStyle(fraction == nil ? WatchInk.creamFaint : WatchInk.cream)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(lineWidth + 2)
        }
    }
}

/// "12m", "3h", "2d" — a compact age for a wrist.
func watchAgo(_ iso: String, now: Date = Date()) -> String {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    return watchAgo(date, now: now)
}

func watchAgo(_ date: Date, now: Date = Date()) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    if seconds < 60 { return "now" }
    if seconds < 3600 { return "\(Int(seconds / 60))m" }
    if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
    return "\(Int(seconds / 86_400))d"
}

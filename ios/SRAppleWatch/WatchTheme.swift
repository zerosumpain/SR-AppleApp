import SwiftUI

/// The ink register, on a wrist: cream type on ink, one accent. watchOS is
/// always dark, and the site's ink band is the part of its palette made for
/// that. Two faces only — Inter Display for figures, JetBrains Mono for labels.
enum WatchInk {
    static let ground = Color(red: 0x1A / 255, green: 0x10 / 255, blue: 0x08 / 255)
    static let cream = Color(red: 0xED / 255, green: 0xE4 / 255, blue: 0xD4 / 255)
    static let creamSoft = cream.opacity(0.7)
    static let creamFaint = cream.opacity(0.45)
    static let accent = Color(red: 0xE8 / 255, green: 0x86 / 255, blue: 0x3A / 255)
    static let good = Color(red: 0x8A / 255, green: 0x9A / 255, blue: 0x5B / 255)
    static let warn = Color(red: 0xB0 / 255, green: 0x89 / 255, blue: 0x2A / 255)
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

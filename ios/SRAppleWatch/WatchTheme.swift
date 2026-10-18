import SwiftUI

/// The reader's palette, on a wrist: light type on the dark page, one accent,
/// a colour per ring. Chosen on the phone (Settings → Colours) and carried in
/// the snapshot (`WatchPalette`); Prism until a phone sends one. SF Pro
/// Rounded throughout, as on the phone since Prism.
enum WatchInk {
    /// Set by `WatchModel` as each snapshot lands, before it is published, so
    /// the redraw that follows paints in the new colours. Main thread only.
    static var palette: WatchPalette = WatchShelf.load()?.palette ?? .prism

    static var ground: Color { hex(palette.ground) }
    static var cream: Color { hex(palette.cream) }
    static var creamSoft: Color { cream.opacity(0.7) }
    static var creamFaint: Color { cream.opacity(0.55) }
    static var accent: Color { hex(palette.accent) }
    static var good: Color { hex(palette.good) }
    static var warn: Color { hex(palette.warn) }
    static var bad: Color { hex(palette.bad) }
    static var move: Color { hex(palette.move) }
    static var recovery: Color { hex(palette.recovery) }
    static var readiness: Color { hex(palette.readiness) }

    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// Scaled with the wearer's text size: the system's text styles, rounded.
    static func figure(_ size: CGFloat) -> Font {
        .system(size >= 17 ? .title3 : .headline, design: .rounded, weight: .heavy)
    }

    static func label(_ size: CGFloat = 12) -> Font {
        .system(size >= 12 ? .caption : .caption2, design: .rounded, weight: .bold)
    }

    static func mono(_ size: CGFloat = 13) -> Font {
        .system(size >= 13 ? .footnote : .caption2, design: .rounded, weight: .medium).monospacedDigit()
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

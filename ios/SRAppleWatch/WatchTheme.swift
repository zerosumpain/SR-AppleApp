import SwiftUI

/// The ink register, on a wrist: cream type on ink, the site's pens. watchOS is
/// always dark, and the notebook's ink cover is the part of its palette made
/// for that, so the Watch stays the cover while the phone's pages became ruled
/// paper (2026-10-11). Its pens are the cover's: orange `#E8863A` for kickers,
/// units and the Move ring, petrol `#7FB8C0` for the labels over a reading,
/// olive and ochre pencils for the other two rings. Three faces: Inter Display
/// for figures, JetBrains Mono for labels, DM Sans for a sentence someone wrote.
enum WatchInk {
    static let ground = Color(red: 0x1A / 255, green: 0x10 / 255, blue: 0x08 / 255)
    static let cream = Color(red: 0xED / 255, green: 0xE4 / 255, blue: 0xD4 / 255)
    static let creamSoft = cream.opacity(0.7)
    static let creamFaint = cream.opacity(0.45)
    /// The orange pen on the cover (`SR.accentOnDark`).
    static let accent = Color(red: 0xE8 / 255, green: 0x86 / 255, blue: 0x3A / 255)
    /// The petrol pen on the cover (`SR.accentInkOnDark`): what a reading is.
    static let petrol = Color(red: 0x7F / 255, green: 0xB8 / 255, blue: 0xC0 / 255)
    static let good = Color(red: 0x8A / 255, green: 0x9A / 255, blue: 0x5B / 255)
    /// The ochre pencil of the site's night theme, for the Readiness ring: a
    /// pencil colour, not the warning below, so a good score does not look
    /// like a problem.
    static let ochre = Color(red: 0xC9 / 255, green: 0xA4 / 255, blue: 0x45 / 255)
    static let warn = Color(red: 0xB0 / 255, green: 0x89 / 255, blue: 0x2A / 255)
    static let bad = Color(red: 0xE0 / 255, green: 0x8B / 255, blue: 0x8B / 255)

    /// The site's kicker tracking: 0.14em of a 12pt label.
    static let kickerTracking: CGFloat = 1.68

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

    /// The kicker's face: JetBrains Mono at its regular weight, as the site
    /// sets its margin labels.
    static func kicker(_ size: CGFloat = 12) -> Font {
        .custom("JetBrainsMono-Regular", size: size, relativeTo: .caption2)
    }

    /// DM Sans, the site's reading face, for an alert's or a workflow's title:
    /// a sentence, which reads badly in mono across a wrist's width.
    static func body(_ size: CGFloat = 15) -> Font {
        .custom("DMSans-Medium", size: size, relativeTo: .footnote)
    }

    static func severity(_ severity: String) -> Color {
        switch severity {
        case "alert", "high": return bad
        case "warn": return warn
        default: return creamFaint
        }
    }
}

/// A kicker in the notebook's recipe: mono caps, tracked 0.14em, in a pen.
/// Orange names the thing; petrol labels a reading.
struct WatchKicker: View {
    let text: String
    var tone: Color = WatchInk.accent
    var size: CGFloat = 12

    var body: some View {
        Text(text.uppercased())
            .font(WatchInk.kicker(size))
            .tracking(WatchInk.kickerTracking * size / 12)
            .foregroundStyle(tone)
            .lineLimit(1)
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

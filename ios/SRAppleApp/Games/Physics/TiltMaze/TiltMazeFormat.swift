import Foundation

/// Times as Tilt Maze shows and says them. Rounded once, to the tenth, before
/// they are split, so 59.97 seconds reads "1:00.0" and never "60.0".
enum TiltMazeFormat {
    /// "9.4", "1:02.5".
    static func time(_ seconds: Double) -> String {
        let tenths = wholeTenths(seconds)
        if tenths < 600 { return "\(tenths / 10).\(tenths % 10)" }
        let minutes = tenths / 600
        let rest = tenths % 600
        return String(format: "%d:%02d.%d", minutes, rest / 10, rest % 10)
    }

    /// "9.4 seconds", "1 minute 2 seconds".
    static func spoken(_ seconds: Double) -> String {
        let tenths = wholeTenths(seconds)
        if tenths < 600 { return "\(tenths / 10).\(tenths % 10) seconds" }
        let whole = Int((Double(tenths) / 10).rounded())
        let minutes = whole / 60
        let rest = whole % 60
        let minuteText = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        if rest == 0 { return minuteText }
        return minuteText + (rest == 1 ? " 1 second" : " \(rest) seconds")
    }

    /// The time in tenths of a second, never negative, never wild.
    private static func wholeTenths(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int((min(seconds, 359_999) * 10).rounded())
    }
}

import Foundation

/// The arithmetic behind the app's picture caches, kept free of UIKit so each
/// rule is a unit test on Linux (`scripts/home-check.sh`).
///
/// Why any of it: a picture's memory is its pixels, not its file. A 30 KB
/// JPEG tile decodes to the same 0.5 MB as any other 360-pixel square, and a
/// 12-megapixel photo decoded whole is 48 MB. So caches are bounded by decoded
/// bytes, every picture is decoded at the size it is drawn, and the disk cache
/// is trimmed by bytes too.
enum SRImageLogic {
    /// The most pixels any one decode is asked for: past this a decode is a
    /// memory spike, not a sharper picture on a phone screen.
    static let maxPixels = 4096

    /// Pixels on the longest edge for something drawn `points` wide on a
    /// screen of `scale` — rounded up, so a tile is never a pixel short.
    static func pixels(points: Double, scale: Double) -> Int {
        guard points.isFinite, scale.isFinite, points > 0, scale > 0 else { return 1 }
        return min(maxPixels, max(1, Int((points * scale).rounded(.up))))
    }

    /// What a decoded picture holds in memory: four bytes a pixel (RGBA).
    static func decodedCost(width: Int, height: Int) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let (product, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else { return Int.max }
        let (bytes, overflow4) = product.multipliedReportingOverflow(by: 4)
        return overflow4 ? Int.max : bytes
    }

    /// One file in a disk cache, for `trimPlan`.
    struct DiskEntry: Equatable {
        let name: String
        let bytes: Int
        let modified: Date
    }

    /// The files to delete so a cache over `budget` bytes comes down to
    /// `keep` of it (default 80%, so it is not trimmed again on the next
    /// write): the oldest first. Nothing while it is within the budget.
    static func trimPlan(_ entries: [DiskEntry], budget: Int, keep: Double = 0.8) -> [String] {
        let total = entries.reduce(0) { $0 + max(0, $1.bytes) }
        guard total > budget else { return [] }
        let target = Int(Double(budget) * min(1, max(0, keep)))
        var held = total
        var out: [String] = []
        let oldestFirst = entries.sorted { a, b in
            a.modified != b.modified ? a.modified < b.modified : a.name < b.name
        }
        for entry in oldestFirst where held > target {
            out.append(entry.name)
            held -= max(0, entry.bytes)
        }
        return out
    }

    /// A disk-cache name from parts that may hold anything (an id from the
    /// site): letters, digits, `-` and `.` are kept and everything else is
    /// percent-escaped, so two different keys never share a file and no key
    /// can climb out of the folder.
    static func fileName(_ parts: [String], ext: String) -> String {
        var plain = CharacterSet.alphanumerics
        plain.insert(charactersIn: "-.")
        let safe = parts.map { part -> String in
            let escaped = part.addingPercentEncoding(withAllowedCharacters: plain) ?? ""
            // A leading dot would hide the file; ".." would be the parent.
            return escaped.hasPrefix(".") ? "%2E" + escaped.dropFirst() : escaped
        }
        return safe.joined(separator: "_") + "." + ext
    }
}

/// Bookkeeping for "at most N at once, the rest wait their turn": which
/// ticket may run now, which waits, and who goes next when one finishes. The
/// waiting is `SRFetchGate`'s; this is only the counting, so it is testable.
struct SRFetchSlots: Equatable {
    let limit: Int
    private(set) var running = 0
    private(set) var waiting: [Int] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// True when `ticket` may start now; otherwise it joins the queue.
    mutating func request(_ ticket: Int) -> Bool {
        if running < limit {
            running += 1
            return true
        }
        waiting.append(ticket)
        return false
    }

    /// One running finished: the next waiting ticket takes its slot (and is
    /// returned, to be woken), or the slot is free.
    mutating func finish() -> Int? {
        if !waiting.isEmpty { return waiting.removeFirst() }
        running = max(0, running - 1)
        return nil
    }

    /// A waiting ticket gave up (its tile scrolled away). False when it was
    /// not waiting — already running, or never asked.
    mutating func withdraw(_ ticket: Int) -> Bool {
        guard let index = waiting.firstIndex(of: ticket) else { return false }
        waiting.remove(at: index)
        return true
    }
}

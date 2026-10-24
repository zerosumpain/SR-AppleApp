import Foundation

/// The only randomness a game's rules may use: SplitMix64, seeded by the host.
///
/// Seeded and `Codable` so a match is reproducible — a test that starts with
/// seed 7 deals the same hands every run, on Linux and on a phone — and so a
/// game may keep a generator inside its `State` if it ever needs one.
///
/// Use the helpers below rather than the standard library's
/// `Int.random(in:using:)` and `shuffle(using:)`. Those accept this generator
/// (it is a `RandomNumberGenerator`) but how they turn its numbers into a
/// result is the standard library's business and may change between Swift
/// releases; these are written out here, so a seed means the same deal forever.
struct OfflineRNG: RandomNumberGenerator, Codable, Equatable {
    private(set) var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A whole number in `0..<bound`. `bound` must be positive.
    mutating func int(below bound: Int) -> Int {
        precondition(bound > 0, "OfflineRNG.int(below:) needs a positive bound")
        // Lemire's rejection: unbiased, and the same answer on every platform.
        let range = UInt64(bound)
        let threshold = (0 &- range) % range
        while true {
            let r = next()
            let product = r.multipliedFullWidth(by: range)
            if product.low >= threshold { return Int(product.high) }
        }
    }

    /// A whole number in `range` (closed): `rng.int(in: 1...6)` is a die.
    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + int(below: range.upperBound - range.lowerBound + 1)
    }

    /// A fraction in `0..<1`, 53 bits of it.
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// A time or size in `range`: `rng.double(in: 2...6)` seconds.
    mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// True with probability `p`.
    mutating func chance(_ p: Double) -> Bool { unit() < p }

    /// One element, or nil from an empty collection.
    mutating func pick<T>(_ items: [T]) -> T? {
        items.isEmpty ? nil : items[int(below: items.count)]
    }

    /// A Fisher–Yates shuffle, in place.
    mutating func shuffle<T>(_ items: inout [T]) {
        guard items.count > 1 else { return }
        for i in stride(from: items.count - 1, to: 0, by: -1) {
            let j = int(below: i + 1)
            if i != j { items.swapAt(i, j) }
        }
    }

    /// A shuffled copy.
    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var copy = items
        shuffle(&copy)
        return copy
    }

    /// A fresh seed for a new match: the host calls this, never a rule.
    static func freshSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max) }
}

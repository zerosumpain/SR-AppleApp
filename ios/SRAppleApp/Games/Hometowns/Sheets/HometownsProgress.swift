import Foundation

// The shell's own small sums for Hometowns, kept apart from the wire so they
// can be tested on their own: how far the town is from its next tier, the
// Founding Fortnight's weeks, the milestones worth a celebration (remembered
// on this phone), and the look of each animal the shell draws.
//
// None of this is the game's rules: the server decides tiers, weeks and
// everything else. These only turn what the frame already says into a bar to
// fill, a dot to light or a face to draw.

// MARK: - Growth to the next tier

/// How far the town is from its next tier, for the growth bar under the top bar.
struct HometownsGrowth: Equatable {
    /// The tier the town is working towards, or nil at the top (Metropolis).
    let nextTier: Int?
    /// People still to come before the next tier (0 once there).
    let needed: Int
    /// 0…1 of the way from this tier's floor to the next tier's.
    let fraction: Double

    /// `floors` are the tiers' populations (content.ts TIER_DEFS, as the
    /// catalogue has them). A retune shows as a slightly stale bar, never as a
    /// wrong tier: the frame's own `tier` is what the town is.
    static func of(population: Int, tier: Int, floors: [Int] = HometownsCatalogue.tierPopulation) -> HometownsGrowth {
        guard !floors.isEmpty else { return HometownsGrowth(nextTier: nil, needed: 0, fraction: 1) }
        let t = min(max(0, tier), floors.count - 1)
        guard t + 1 < floors.count else { return HometownsGrowth(nextTier: nil, needed: 0, fraction: 1) }
        let low = floors[t]
        let high = floors[t + 1]
        let span = max(1, high - low)
        let share = Double(population - low) / Double(span)
        return HometownsGrowth(nextTier: t + 1, needed: max(0, high - population), fraction: max(0, min(1, share)))
    }
}

// MARK: - The Founding Fortnight

/// The fortnight's weeks as dots: twelve "Next week" presses in all.
enum HometownsSprintWeeks {
    static let total = 12

    /// (weeks played, weeks in all): a frame that says more than twelve are
    /// left widens the row rather than showing a negative count.
    static func of(left: Int) -> (done: Int, total: Int) {
        let l = max(0, left)
        let all = max(total, l)
        return (all - l, all)
    }
}

// MARK: - Milestones, remembered on this phone

/// The biggest the town has been and the highest tier it has reached, as this
/// phone last saw them. A tier or a round number of people passed since is a
/// moment worth a card; the first look at a town only records it, so opening
/// an old county on a new phone does not throw a party for every tier at once.
struct HometownsMilestones: Codable, Equatable {
    var highestTier: Int = 0
    var peakPopulation: Int = 0
    /// False until the first look has been recorded.
    var seen: Bool = false

    /// Round numbers of people worth saying out loud.
    static let populationMarks = [50, 100, 250, 500, 1000, 2000, 5000, 10000, 25000, 50000, 100000]

    enum Event: Equatable {
        /// The town became this tier.
        case tierUp(Int)
        /// The town passed this many people.
        case population(Int)
    }

    /// Record the town as it is now, and say what to celebrate, if anything.
    /// A tier beats a head-count when both happen in one frame.
    mutating func observe(tier: Int, population: Int) -> Event? {
        let tier = max(0, tier)
        let population = max(0, population)
        guard seen else {
            seen = true
            highestTier = tier
            peakPopulation = population
            return nil
        }
        var event: Event?
        if tier > highestTier {
            event = .tierUp(tier)
        } else if let mark = Self.populationMarks.last(where: { $0 > peakPopulation && $0 <= population }) {
            event = .population(mark)
        }
        highestTier = max(highestTier, tier)
        peakPopulation = max(peakPopulation, population)
        return event
    }
}

/// Milestones per county and seat, in UserDefaults under `hometowns-milestones-…`.
struct HometownsMilestoneStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(roomId: String, seat: String) -> String { "hometowns-milestones-\(roomId)-\(seat)" }

    func load(roomId: String, seat: String) -> HometownsMilestones {
        guard let data = defaults.data(forKey: Self.key(roomId: roomId, seat: seat)),
              let m = try? JSONDecoder().decode(HometownsMilestones.self, from: data) else { return HometownsMilestones() }
        return m
    }

    func save(_ m: HometownsMilestones, roomId: String, seat: String) {
        guard let data = try? JSONEncoder().encode(m) else { return }
        defaults.set(data, forKey: Self.key(roomId: roomId, seat: seat))
    }

    /// Load, observe and save in one go: the event to show, if any.
    func observe(roomId: String, seat: String, tier: Int, population: Int) -> HometownsMilestones.Event? {
        var m = load(roomId: roomId, seat: seat)
        let before = m
        let event = m.observe(tier: tier, population: population)
        if m != before { save(m, roomId: roomId, seat: seat) }
        return event
    }
}

// MARK: - The animals the shell draws

/// The look of an animal face (a mayor or an advisor), as plain numbers, so
/// every animal in the catalogue can be checked to have one. Colours are
/// 0xRRGGBB; the drawing itself is `HometownsCritterFace`.
struct HometownsCritter: Equatable {
    enum Ears: Equatable { case pointy, round, long, tufts, none }
    enum Snout: Equatable { case nose, beak, longBeak, wideBeak, tallBeak, smile }
    enum Patch: Equatable {
        /// A muzzle round the nose.
        case muzzle
        /// A big pale face on a darker head (puffin, owl).
        case mask
        /// A coloured breast under the face (robin).
        case bib
        case none
    }

    let head: UInt32
    let patch: Patch
    let patchColour: UInt32
    /// The nose or the beak.
    let snoutColour: UInt32
    let ears: Ears
    let snout: Snout
    /// Badger: two dark stripes through the eyes.
    var stripes: Bool = false
    /// Hedgehog: a ring of spines round the face.
    var spines: Bool = false
    /// Owl and frog: big round eyes.
    var bigEyes: Bool = false

    /// The animal for an advisor's key (Bramble the badger, Mo the hedgehog…).
    static func advisorAnimal(_ advisor: String) -> String {
        switch advisor {
        case "penny": return "magpie"
        case "mo": return "hedgehog"
        case "zia": return "otter"
        default: return "badger"
        }
    }

    /// Every animal the shell knows how to draw.
    static let known = ["fox", "owl", "rabbit", "squirrel", "duck", "mole", "deer", "robin", "frog", "puffin", "mouse", "heron",
                        "badger", "hedgehog", "magpie", "otter"]

    /// The face for an animal; anything unknown (a new avatar, Kingsport) is a badger.
    static func of(_ animal: String) -> HometownsCritter {
        switch animal {
        case "fox":
            return HometownsCritter(head: 0xE07B2E, patch: .muzzle, patchColour: 0xF7EEDF, snoutColour: 0x2A211C, ears: .pointy, snout: .nose)
        case "owl":
            return HometownsCritter(head: 0x8A6A4C, patch: .mask, patchColour: 0xE9D7B8, snoutColour: 0xE0A030, ears: .tufts, snout: .beak, bigEyes: true)
        case "rabbit":
            return HometownsCritter(head: 0xB7A08A, patch: .muzzle, patchColour: 0xF4ECE2, snoutColour: 0xE58C9C, ears: .long, snout: .nose)
        case "squirrel":
            return HometownsCritter(head: 0xC2532B, patch: .muzzle, patchColour: 0xF3E2C8, snoutColour: 0x2A211C, ears: .tufts, snout: .nose)
        case "duck":
            return HometownsCritter(head: 0x2E7D4F, patch: .none, patchColour: 0x2E7D4F, snoutColour: 0xF2C230, ears: .none, snout: .wideBeak)
        case "mole":
            return HometownsCritter(head: 0x3B3431, patch: .none, patchColour: 0x3B3431, snoutColour: 0xEE8FB5, ears: .none, snout: .nose)
        case "deer":
            return HometownsCritter(head: 0xB9834F, patch: .muzzle, patchColour: 0xF1E3CC, snoutColour: 0x2A211C, ears: .round, snout: .nose)
        case "robin":
            return HometownsCritter(head: 0x8B6B4A, patch: .bib, patchColour: 0xE0602E, snoutColour: 0x2A211C, ears: .none, snout: .beak)
        case "frog":
            return HometownsCritter(head: 0x5BA35B, patch: .none, patchColour: 0x5BA35B, snoutColour: 0x2A3A22, ears: .none, snout: .smile, bigEyes: true)
        case "puffin":
            return HometownsCritter(head: 0x24272C, patch: .mask, patchColour: 0xF4F0E6, snoutColour: 0xE8692C, ears: .none, snout: .tallBeak)
        case "mouse":
            return HometownsCritter(head: 0xC59A62, patch: .muzzle, patchColour: 0xF4E8D2, snoutColour: 0xE58C9C, ears: .round, snout: .nose)
        case "heron":
            return HometownsCritter(head: 0x9AA6B2, patch: .mask, patchColour: 0xF1F2F0, snoutColour: 0xE6B53A, ears: .none, snout: .longBeak)
        case "hedgehog":
            return HometownsCritter(head: 0x6B5240, patch: .mask, patchColour: 0xE8D3B4, snoutColour: 0x2A211C, ears: .none, snout: .nose, spines: true)
        case "magpie":
            return HometownsCritter(head: 0x22252B, patch: .muzzle, patchColour: 0xF4F0E6, snoutColour: 0x3A3F48, ears: .none, snout: .beak)
        case "otter":
            return HometownsCritter(head: 0x7A5537, patch: .muzzle, patchColour: 0xE6CFAE, snoutColour: 0x2A211C, ears: .round, snout: .nose)
        default:
            // Bramble the badger: a pale face, dark stripes, grey ears.
            return HometownsCritter(head: 0xEDEAE2, patch: .none, patchColour: 0xEDEAE2, snoutColour: 0x2A211C, ears: .round, snout: .nose, stripes: true)
        }
    }

    /// A head dark enough to need a pale outline against a dark badge.
    var darkHead: Bool { Self.luminance(head) < 0.3 }

    /// The eyes sit on the mask where there is one, else on the head; on a
    /// dark ground they are drawn pale so they can be seen.
    var paleEyes: Bool { Self.luminance(patch == .mask ? patchColour : head) < 0.3 }

    /// Relative luminance, 0…1 (sRGB, unlinearised: good enough to pick an eye colour).
    static func luminance(_ hex: UInt32) -> Double {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

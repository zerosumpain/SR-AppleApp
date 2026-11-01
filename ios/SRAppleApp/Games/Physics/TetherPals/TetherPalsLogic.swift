import Foundation

// Tether Pals: the rules. A side-on world of 1-tile squares (y grows
// downward), two or three pals that run, jump, stand on each other's heads
// and are sometimes tied together, stepped on a fixed beat of 1/120 s. No
// clocks and no randomness: time arrives as steps, so a test can play a
// whole level in an instant and the same inputs always give the same game.

/// The numbers that make the pals feel the way they do, in tiles and seconds.
enum TetherPalsRules {
    static let step = 1.0 / 120
    static let gravity = 45.0
    /// A jump from the ground rises 1.6 tiles: a 1-tile step is easy, a 2-tile wall is not.
    static let jumpSpeed = 12.0
    /// A jump off a pal's head rises 2.2 tiles: a springy one.
    static let boostSpeed = (2 * 45.0 * 2.2).squareRoot()
    static let runSpeed = 4.5
    /// A pal carrying someone walks at this share of its speed.
    static let carryShare = 0.6
    /// Sideways speed off a pal's head, for the long leaps.
    static let boostRun = 7.5
    static let airAccel = 40.0
    static let maxFall = 16.0
    /// A jump still works this long after running off an edge.
    static let coyote = 0.08
    /// A jump pressed this long before landing still happens.
    static let buffer = 0.12
    static let palSize = 0.8
    /// How far a rope lets two pals apart, centre to centre.
    static let rope = 4.0
    /// How long a popped pal is away before it is back at the start.
    static let popDelay = 0.7
    /// Everyone has to stand at the flag this long.
    static let homeHold = 0.3
    static let maxPals = 3
    static let columns = 16
    static let rows = 10
}

/// The two colours of buttons, doors and bridges.
enum TetherPalsChannel: Int, Equatable, CaseIterable {
    case gold = 0
    case blue = 1
}

enum TetherPalsTile: Equatable {
    case empty
    case ground
    case prickles
    case button(TetherPalsChannel)
    case door(TetherPalsChannel)
    case bridge(TetherPalsChannel)
}

struct TetherPalsCell: Equatable, Hashable {
    let col: Int
    let row: Int
}

/// What a pal is standing on.
enum TetherPalsSupport: Equatable {
    case none
    case ground
    case pal(Int)

    var standing: Bool { self != .none }
}

/// One pal's held buttons this step.
struct TetherPalsInput: Equatable {
    var left = false
    var right = false
    var jump = false

    static let none = TetherPalsInput()

    var direction: Int { (right ? 1 : 0) - (left ? 1 : 0) }
}

/// A door or a bridge: a tile that comes and goes with its buttons.
struct TetherPalsGate: Equatable {
    let cell: TetherPalsCell
    let channel: TetherPalsChannel
    /// A door is solid until pressed open; a bridge is there only while pressed.
    let isDoor: Bool
}

struct TetherPalsPal: Equatable {
    var x: Double
    var y: Double
    var vx = 0.0
    var vy = 0.0
    var support: TetherPalsSupport = .none
    /// Seconds since last standing on something.
    var air = 0.0
    var buffer = 0.0
    var jumpHeld = false
    /// In a springy jump off a pal's head.
    var boosting = false
    var facing = 1
    var active = true
    var popTimer = 0.0
    /// How far it moved in the last step, so a rider moves with it.
    var dx = 0.0
    var dy = 0.0
    let spawnX: Double
    let spawnY: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
        spawnX = x
        spawnY = y
    }

    var size: Double { TetherPalsRules.palSize }
    var centreX: Double { x + size / 2 }
    var centreY: Double { y + size / 2 }
    var bottom: Double { y + size }
}

/// What happened in one step, for the haptics, sparks and words.
struct TetherPalsEvents: Equatable {
    var jumped: [Int] = []
    var boosted: [Int] = []
    var landedOnPal: [Int] = []
    var landed: [Int] = []
    var popped: [Int] = []
    var respawned: [Int] = []
    var arrived: [Int] = []
    var buttonChanged = false
    var won = false

    var isEmpty: Bool {
        jumped.isEmpty && boosted.isEmpty && landedOnPal.isEmpty && landed.isEmpty && popped.isEmpty
            && respawned.isEmpty && arrived.isEmpty && !buttonChanged && !won
    }
}

/// A level being played: the pals, the gates, the clock.
struct TetherPalsWorld: Equatable {
    let level: TetherPalsLevel
    let team: Int
    private(set) var pals: [TetherPalsPal]
    /// Solid now, per gate.
    private(set) var gateSolid: [Bool]
    /// 0 (gone) to 1 (solid), eased, for drawing.
    private(set) var gateShown: [Double]
    /// Pressed now, per channel.
    private(set) var pressed: [Bool] = [false, false]
    /// Standing in the flag's zone, per pal.
    private(set) var home: [Bool]
    private(set) var homeTime = 0.0
    private(set) var time = 0.0
    private(set) var steps = 0
    private(set) var won = false
    /// Pals that touched prickles or fell (not counting a rope partner pulled along).
    private(set) var pops = 0

    init(level: TetherPalsLevel, team: Int) {
        self.level = level
        let team = min(TetherPalsRules.maxPals, max(2, team))
        self.team = team
        pals = (0..<team).map { index in
            let cell = level.spawn(index)
            return TetherPalsPal(x: Double(cell.col) + 0.1, y: Double(cell.row) + 1 - TetherPalsRules.palSize)
        }
        gateSolid = level.gates.map(\.isDoor)
        gateShown = level.gates.map { $0.isDoor ? 1 : 0 }
        home = Array(repeating: false, count: team)
    }

    var everyoneHome: Bool { home.allSatisfy { $0 } }
    var homeCount: Int { home.filter { $0 }.count }

    /// Whether a channel's buttons are held down now.
    func isPressed(_ channel: TetherPalsChannel) -> Bool {
        channel.rawValue < pressed.count && pressed[channel.rawValue]
    }

    // MARK: - The step

    /// One fixed step. `inputs[i]` is what pal `i` holds (missing means nothing).
    @discardableResult
    mutating func step(_ inputs: [TetherPalsInput]) -> TetherPalsEvents {
        var events = TetherPalsEvents()
        guard !won else { return events }
        updateGates(&events)
        let order = pals.indices.sorted { a, b in
            pals[a].bottom != pals[b].bottom ? pals[a].bottom > pals[b].bottom : a < b
        }
        var riders = Array(repeating: 0, count: team)
        for pal in pals {
            if case .pal(let under) = pal.support, under >= 0, under < team { riders[under] += 1 }
        }
        for index in order {
            let input = index < inputs.count ? inputs[index] : .none
            move(index, input: input, carrying: riders[index] > 0, events: &events)
        }
        hurt(&events)
        if level.tied { pullRopes() }
        respawn(&events)
        checkHome(&events)
        time += TetherPalsRules.step
        steps += 1
        return events
    }

    private mutating func move(_ index: Int, input: TetherPalsInput, carrying: Bool, events: inout TetherPalsEvents) {
        var pal = pals[index]
        pal.dx = 0
        pal.dy = 0
        guard pal.active else {
            pals[index] = pal
            return
        }
        let x0 = pal.x, y0 = pal.y
        let wasStanding = pal.support.standing
        // Carried by the pal underneath (moved earlier this step: lower pals go first).
        if case .pal(let under) = pal.support, under >= 0, under < team {
            let carrier = pals[under]
            if carrier.active && (carrier.dx != 0 || carrier.dy != 0) {
                moveX(&pal, by: carrier.dx)
                _ = moveYTiles(&pal, by: carrier.dy)
            }
        }
        let direction = input.direction
        if direction != 0 { pal.facing = direction }
        if input.jump && !pal.jumpHeld { pal.buffer = TetherPalsRules.buffer }
        pal.jumpHeld = input.jump
        if pal.support.standing {
            pal.boosting = false
            pal.vx = Double(direction) * TetherPalsRules.runSpeed * (carrying ? TetherPalsRules.carryShare : 1)
        } else {
            let top = pal.boosting ? TetherPalsRules.boostRun : TetherPalsRules.runSpeed
            let target = direction == 0 && pal.boosting ? pal.vx : Double(direction) * top
            let most = TetherPalsRules.airAccel * TetherPalsRules.step
            pal.vx += max(-most, min(most, target - pal.vx))
        }
        if pal.buffer > 0 && pal.air <= TetherPalsRules.coyote {
            if case .pal = pal.support {
                pal.vy = -TetherPalsRules.boostSpeed
                pal.boosting = true
                if direction != 0 { pal.vx = Double(direction) * TetherPalsRules.boostRun }
                events.boosted.append(index)
            } else {
                pal.vy = -TetherPalsRules.jumpSpeed
                events.jumped.append(index)
            }
            pal.buffer = 0
            pal.air = TetherPalsRules.coyote + 1
            pal.support = .none
        }
        pal.vy = min(pal.vy + TetherPalsRules.gravity * TetherPalsRules.step, TetherPalsRules.maxFall)
        if !moveX(&pal, by: pal.vx * TetherPalsRules.step) { pal.vx = 0 }
        let support = fall(&pal, index: index)
        pal.support = support
        if support.standing {
            pal.air = 0
            pal.boosting = false
            if !wasStanding {
                events.landed.append(index)
                if case .pal = support { events.landedOnPal.append(index) }
            }
        } else {
            pal.air += TetherPalsRules.step
        }
        pal.buffer = max(0, pal.buffer - TetherPalsRules.step)
        pal.dx = pal.x - x0
        pal.dy = pal.y - y0
        pals[index] = pal
    }

    /// The vertical move: tiles stop it, and a pal's head catches it from above.
    private func fall(_ pal: inout TetherPalsPal, index: Int) -> TetherPalsSupport {
        let size = TetherPalsRules.palSize
        let previousBottom = pal.bottom
        let dy = pal.vy * TetherPalsRules.step
        let hit = moveYTiles(&pal, by: dy)
        var support: TetherPalsSupport = .none
        if hit == 1 {
            support = .ground
            pal.vy = 0
        } else if hit == -1 {
            pal.vy = max(pal.vy, 0)
        }
        guard dy > 0 else { return support }
        let newBottom = pal.bottom
        var best: Int?
        for other in pals.indices where other != index {
            let head = pals[other]
            guard head.active else { continue }
            let overlap = min(pal.x + size, head.x + size) - max(pal.x, head.x)
            guard overlap > 0.1 else { continue }
            if previousBottom <= head.y + 1e-4 && newBottom >= head.y {
                if let current = best {
                    if head.y < pals[current].y { best = other }
                } else {
                    best = other
                }
            }
        }
        if let best, support == .none || pals[best].y <= pal.y + size {
            pal.y = pals[best].y - size
            pal.vy = 0
            support = .pal(best)
        }
        return support
    }

    // MARK: - Tiles

    /// Solid at a tile: the walls left and right and the sky's lid are, the
    /// pit below the bottom row is not.
    func isSolid(col: Int, row: Int) -> Bool {
        if col < 0 || col >= level.columns || row < 0 { return true }
        if row >= level.rows { return false }
        switch level.tile(col: col, row: row) {
        case .ground:
            return true
        case .door, .bridge:
            if let gate = level.gateIndex[TetherPalsCell(col: col, row: row)], gate < gateSolid.count {
                return gateSolid[gate]
            }
            return false
        case .empty, .prickles, .button:
            return false
        }
    }

    func boxHitsSolid(x: Double, y: Double) -> Bool {
        let size = TetherPalsRules.palSize
        let e = 1e-6
        guard x.isFinite, y.isFinite else { return true }
        let c0 = Int(floor(x + e)), c1 = Int(floor(x + size - e))
        let r0 = Int(floor(y + e)), r1 = Int(floor(y + size - e))
        guard c0 <= c1, r0 <= r1 else { return false }
        for row in r0...r1 {
            for col in c0...c1 where isSolid(col: col, row: row) { return true }
        }
        return false
    }

    /// Sideways: false when a tile stopped it (it is left touching the tile).
    @discardableResult
    private func moveX(_ pal: inout TetherPalsPal, by dx: Double) -> Bool {
        guard dx != 0, dx.isFinite else { return true }
        let size = TetherPalsRules.palSize
        let e = 1e-6
        let nx = pal.x + dx
        if !boxHitsSolid(x: nx, y: pal.y) {
            pal.x = nx
            return true
        }
        pal.x = dx > 0 ? floor(nx + size - e) - size : floor(nx + e) + 1
        return false
    }

    /// Up or down: 1 when the floor stopped it, -1 the ceiling, 0 free.
    private func moveYTiles(_ pal: inout TetherPalsPal, by dy: Double) -> Int {
        guard dy != 0, dy.isFinite else { return 0 }
        let size = TetherPalsRules.palSize
        let e = 1e-6
        let ny = pal.y + dy
        if !boxHitsSolid(x: pal.x, y: ny) {
            pal.y = ny
            return 0
        }
        if dy > 0 {
            pal.y = floor(ny + size - e) - size
            return 1
        }
        pal.y = floor(ny + e) + 1
        return -1
    }

    /// A long pull, a few short moves at a time, so it never jumps through a tile.
    private func shove(_ pal: inout TetherPalsPal, dx: Double, dy: Double) {
        let parts = max(1, Int(ceil(max(abs(dx), abs(dy)) / 0.3)))
        guard parts < 1000 else { return }
        for _ in 0..<parts {
            moveX(&pal, by: dx / Double(parts))
            _ = moveYTiles(&pal, by: dy / Double(parts))
        }
    }

    private func overlaps(_ pal: TetherPalsPal, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
        let size = TetherPalsRules.palSize
        return pal.x < x1 && pal.x + size > x0 && pal.y < y1 && pal.y + size > y0
    }

    // MARK: - Buttons and gates

    private mutating func updateGates(_ events: inout TetherPalsEvents) {
        var now = [false, false]
        for button in level.buttons {
            let c = Double(button.cell.col), r = Double(button.cell.row)
            if pals.contains(where: { $0.active && overlaps($0, c + 0.1, r + 0.75, c + 0.9, r + 1) }) {
                now[button.channel.rawValue] = true
            }
        }
        if now != pressed {
            events.buttonChanged = true
            pressed = now
        }
        for (index, gate) in level.gates.enumerated() {
            let on = pressed[gate.channel.rawValue]
            let want = gate.isDoor ? !on : on
            if want && !gateSolid[index] {
                let c = Double(gate.cell.col), r = Double(gate.cell.row)
                // Never shut on a pal standing in it.
                if pals.contains(where: { $0.active && overlaps($0, c + 0.02, r + 0.02, c + 0.98, r + 0.98) }) { continue }
            }
            gateSolid[index] = want
        }
        for index in gateShown.indices {
            let target = gateSolid[index] ? 1.0 : 0.0
            let most = 8 * TetherPalsRules.step
            gateShown[index] += max(-most, min(most, target - gateShown[index]))
        }
    }

    // MARK: - Prickles, pits and coming back

    private mutating func hurt(_ events: inout TetherPalsEvents) {
        var anyone = false
        for index in pals.indices where pals[index].active {
            let pal = pals[index]
            var hurt = pal.y > Double(level.rows)
            if !hurt {
                for cell in level.prickles {
                    let c = Double(cell.col), r = Double(cell.row)
                    if pal.x + 0.05 < c + 0.85 && pal.x + pal.size - 0.05 > c + 0.15
                        && pal.y + 0.05 < r + 1 && pal.y + pal.size - 0.05 > r + 0.45 {
                        hurt = true
                        break
                    }
                }
            }
            if hurt {
                pop(index, events: &events)
                pops += 1
                anyone = true
            }
        }
        // Tied pals go back together: the rope would yank the other across the screen.
        if anyone && level.tied {
            for index in pals.indices where pals[index].active { pop(index, events: &events) }
        }
    }

    private mutating func pop(_ index: Int, events: inout TetherPalsEvents) {
        pals[index].active = false
        pals[index].popTimer = TetherPalsRules.popDelay
        events.popped.append(index)
        for other in pals.indices where pals[other].support == .pal(index) {
            pals[other].support = .none
        }
    }

    private mutating func respawn(_ events: inout TetherPalsEvents) {
        for index in pals.indices where !pals[index].active {
            pals[index].popTimer -= TetherPalsRules.step
            guard pals[index].popTimer <= 0 else { continue }
            var pal = pals[index]
            pal.active = true
            pal.x = pal.spawnX
            pal.y = pal.spawnY
            pal.vx = 0
            pal.vy = 0
            pal.support = .none
            pal.boosting = false
            pal.air = 0
            pal.buffer = 0
            pals[index] = pal
            events.respawned.append(index)
        }
    }

    // MARK: - The rope

    /// Keep each tied pair within the rope: two on the ground share the pull
    /// (one drags the other), one on the ground holds firm against one in the
    /// air (who dangles, and is hauled up), two in the air share it.
    private mutating func pullRopes() {
        for _ in 0..<2 {
            for first in 0..<(team - 1) {
                let second = first + 1
                var a = pals[first], b = pals[second]
                guard a.active, b.active else { continue }
                let ex = b.centreX - a.centreX, ey = b.centreY - a.centreY
                let distance = (ex * ex + ey * ey).squareRoot()
                guard distance > TetherPalsRules.rope else { continue }
                let nx = ex / distance, ny = ey / distance
                let excess = distance - TetherPalsRules.rope
                let (shareA, shareB) = Self.shares(a.support.standing, b.support.standing)
                if shareA > 0 { shove(&a, dx: nx * excess * shareA, dy: ny * excess * shareA) }
                if shareB > 0 { shove(&b, dx: -nx * excess * shareB, dy: -ny * excess * shareB) }
                let apart = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
                if apart > 0 {
                    a.vx += nx * apart * shareA
                    a.vy += ny * apart * shareA
                    b.vx -= nx * apart * shareB
                    b.vy -= ny * apart * shareB
                }
                pals[first] = a
                pals[second] = b
            }
        }
    }

    /// Who gives way to a taut rope: (first's share, second's share).
    static func shares(_ firstStanding: Bool, _ secondStanding: Bool) -> (Double, Double) {
        if firstStanding == secondStanding { return (0.5, 0.5) }
        return firstStanding ? (0, 1) : (1, 0)
    }

    /// The distance between two tied pals, centre to centre.
    func ropeLength(_ first: Int, _ second: Int) -> Double {
        guard first >= 0, second >= 0, first < team, second < team else { return 0 }
        let ex = pals[second].centreX - pals[first].centreX
        let ey = pals[second].centreY - pals[first].centreY
        return (ex * ex + ey * ey).squareRoot()
    }

    // MARK: - The flag

    /// A pal's middle inside the flag's zone: the flag's tile, one either side, two up.
    func isInZone(_ pal: TetherPalsPal) -> Bool {
        let fc = Double(level.flag.col), fr = Double(level.flag.row)
        return pal.centreX >= fc - 1 && pal.centreX < fc + 2 && pal.centreY >= fr - 2 && pal.centreY < fr + 1
    }

    private mutating func checkHome(_ events: inout TetherPalsEvents) {
        for index in pals.indices {
            let now = pals[index].active && isInZone(pals[index])
            if now && !home[index] { events.arrived.append(index) }
            home[index] = now
        }
        if everyoneHome {
            homeTime += TetherPalsRules.step
            if homeTime >= TetherPalsRules.homeHold {
                won = true
                events.won = true
            }
        } else {
            homeTime = 0
        }
    }

    // MARK: - Words

    /// What a pal is up to, for VoiceOver: "Pip is on Bo's head, 4 steps left of the flag."
    func describe(_ index: Int) -> String {
        guard index >= 0, index < team else { return "" }
        let pal = pals[index]
        let name = TetherPalsCast.name(index)
        guard pal.active else { return "\(name) is popping back to the start." }
        if home[index] { return "\(name) is at the flag." }
        let place: String
        switch pal.support {
        case .pal(let under): place = "\(name) is on \(TetherPalsCast.name(under))'s head"
        case .ground: place = "\(name) is standing"
        case .none: place = "\(name) is in the air"
        }
        let steps = Int((Double(level.flag.col) + 0.5 - pal.centreX).rounded())
        let rise = Int((pal.bottom - Double(level.flag.row + 1)).rounded())
        var words = steps == 0 ? "\(place), under the flag" : "\(place), \(abs(steps)) \(abs(steps) == 1 ? "step" : "steps") \(steps > 0 ? "left" : "right") of the flag"
        if rise > 0 { words += ", \(rise) below it" }
        return words + "."
    }
}

/// The pals: names and the order of their colours.
enum TetherPalsCast {
    static let names = ["Pip", "Bo", "Kit"]

    static func name(_ index: Int) -> String {
        index >= 0 && index < names.count ? names[index] : "Pal \(index + 1)"
    }
}

import Foundation

// The eight Car Racer+ circuits. Each is written as control points in
// metres (racing order, the first on the main straight), its corners and
// sector splits by control-point index, and what lies beside the road.
// `CarProCircuits.all` builds them once.

enum CarProCircuits {
    static let brackenfield = CarProCircuit(
        id: "brackenfield", name: "Brackenfield Park",
        line: "A flowing club circuit through parkland. Fast sweepers reward a smooth line.",
        location: "Parkland club circuit", theme: .parkland, width: 12,
        control: [(0, 0), (200, 0), (375, 6), (462, 50), (488, 138), (438, 212), (350, 238), (288, 300),
                  (300, 400), (238, 462), (125, 450), (50, 375), (-50, 350), (-138, 288), (-150, 175),
                  (-100, 75)],
        corners: [(3, "Abbey Sweep"), (5, "Mill Lane"), (7, "The Spinney"), (9, "Hollow"), (11, "Church Kink"),
                  (13, "Long Field"), (15, "Home Bend")],
        sectors: (6, 11), start: 90, runoff: 10, gravel: true, gravelDepth: 20)

    static let thunderBowl = CarProCircuit(
        id: "thunder-bowl", name: "Thunder Bowl",
        line: "A banked speedway. Two huge bowls, a kink on the front stretch, and slipstreams everywhere.",
        location: "High-speed banked oval", theme: .speedway, width: 16,
        control: [(0, 0), (260, -10), (520, 0), (702, 39), (793, 169), (754, 312), (598, 377), (338, 390),
                  (78, 390), (-104, 351), (-195, 221), (-169, 78)],
        corners: [(1, "The Kink"), (4, "North Bowl"), (10, "South Bowl")],
        sectors: (4, 8), start: 110, runoff: 8, gravel: false, banking: 0.21)

    static let oldTown = CarProCircuit(
        id: "old-town", name: "Old Town Streets",
        line: "Right angles between the walls of a market town. Brake late, kiss the barriers, never touch them.",
        location: "Tight street circuit", theme: .streets, width: 10,
        control: [(0, 0), (69, 0), (138, 0), (172, 0), (190, -17), (190, -69), (207, -86), (299, -86),
                  (316, -69), (316, 46), (301, 63), (253, 63), (236, 80), (236, 161), (218, 178), (115, 178),
                  (98, 161), (98, 126), (80, 109), (0, 109), (-46, 109), (-63, 92), (-63, 17), (-46, 0)],
        corners: [(4, "Market Cross"), (6, "Chapel"), (8, "Guildhall"), (10, "Bridge"), (12, "Wool Street"),
                  (14, "Corn Exchange"), (16, "Bakers Row"), (18, "Castle Gate"), (21, "Town Hall"),
                  (23, "Fountain")],
        sectors: (7, 15), start: 60, runoff: 2.2, gravel: false)

    static let kestrelHill = CarProCircuit(
        id: "kestrel-hill", name: "Kestrel Hill",
        line: "A technical hillside circuit: an uphill esses section, a tight hairpin and a long drop home.",
        location: "Technical hillside circuit", theme: .hills, width: 11,
        control: [(0, 0), (182, 0), (325, 13), (390, 65), (377, 143), (312, 169), (260, 221), (299, 273),
                  (260, 325), (195, 312), (130, 364), (156, 442), (104, 494), (39, 455), (52, 390), (-13, 338),
                  (-104, 312), (-169, 234), (-156, 117), (-91, 39)],
        corners: [(3, "Summit"), (5, "Kestrel"), (6, "Esses I"), (7, "Esses II"), (8, "Esses III"), (10, "The Dip"),
                  (12, "Hairpin"), (14, "Chalk Pit"), (16, "Beacon"), (18, "Long Drop")],
        sectors: (6, 13), start: 80, runoff: 7, gravel: true, gravelDepth: 16)

    static let saltcliff = CarProCircuit(
        id: "saltcliff", name: "Saltcliff GP",
        line: "A coastal Grand Prix circuit: a kilometre-long straight broken by a chicane, then the cliffs.",
        location: "Coastal Grand Prix circuit", theme: .coast, width: 13,
        control: [(0, 0), (300, 0), (396, 0), (422, -16), (449, -16), (475, 0), (600, 0), (900, 0), (984, 12),
                  (1008, 60), (972, 108), (996, 156), (960, 216), (840, 240), (720, 216), (648, 264), (672, 348),
                  (600, 408), (456, 396), (360, 336), (264, 360), (216, 420), (120, 432), (24, 384), (-12, 300),
                  (-72, 240), (-144, 180), (-132, 72), (-72, 12)],
        corners: [(3, "Lighthouse Chicane"), (9, "Harbour Bend"), (10, "Cliff Esses"), (12, "Gull Corner"),
                  (15, "Smugglers"), (17, "Old Fort"), (19, "Dunes"), (21, "Rock Pool"), (24, "Sea Wall"),
                  (26, "Promenade")],
        sectors: (8, 18), start: 120, runoff: 12, gravel: true, gravelDepth: 24, wet: [(10, 12)])

    static let quarry = CarProCircuit(
        id: "quarry-rx", name: "Quarry Rallycross",
        line: "Half tarmac, half loose dirt round an old quarry. The grip changes under you mid-corner.",
        location: "Mixed-surface rallycross", theme: .quarry, width: 12,
        control: [(50, 0), (100, 0), (170, 20), (190, 80), (150, 120), (90, 110), (60, 150), (90, 200),
                  (50, 250), (-20, 240), (-60, 180), (-30, 120), (-70, 70), (-50, 15), (0, 0)],
        corners: [(2, "Crusher"), (4, "Spoil Heap"), (6, "The Joker"), (8, "Conveyor"), (10, "Pit Face"),
                  (12, "Blast Bend")],
        sectors: (4, 9), start: 10, runoff: 6, gravel: true, gravelDepth: 14, dirt: [(3, 7), (9, 12)])

    static let neonHarbour = CarProCircuit(
        id: "neon-harbour", name: "Neon Harbour",
        line: "A night race round the docks under floodlights. Containers, cranes and a quick quayside.",
        location: "Night circuit", theme: .harbourNight, width: 12,
        control: [(0, 0), (225, 0), (400, 0), (475, 38), (475, 125), (412, 162), (325, 150), (250, 188),
                  (262, 275), (200, 338), (75, 325), (0, 275), (-75, 312), (-162, 275), (-175, 162), (-112, 112),
                  (-112, 50), (-62, 6)],
        corners: [(3, "Neon Bend"), (5, "Quayside"), (7, "Container Yard"), (9, "The Crane"), (11, "Fish Market"),
                  (13, "Lighthouse"), (15, "Ferry Terminal"), (17, "Marina")],
        sectors: (6, 12), start: 90, runoff: 5, gravel: true, gravelDepth: 12)

    static let nordwald = CarProCircuit(
        id: "nordwald", name: "Nordwald Ring",
        line: "Nearly five kilometres through the forest. Narrow, endless, and the ultimate test.",
        location: "Endurance forest ring", theme: .forest, width: 11,
        control: [(0, 0), (375, 0), (750, 0), (1100, 0), (1195, 10), (1250, 55), (1275, 150), (1200, 225), (1225, 325),
                  (1325, 375), (1375, 500), (1300, 600), (1175, 588), (1100, 650), (1125, 750), (1050, 850),
                  (900, 825), (800, 875), (700, 950), (550, 925), (500, 825), (375, 800), (275, 875), (150, 862),
                  (75, 775), (125, 675), (75, 588), (-50, 575), (-150, 500), (-138, 375), (-225, 300),
                  (-238, 175), (-150, 112), (-112, 38)],
        corners: [(5, "Hatchery"), (7, "Fox Hollow"), (10, "Adler Wood"), (12, "Mill Brook"), (14, "Black Gorge"),
                  (17, "Kestrel Rise"), (19, "The Carousel"), (22, "High Ridge"), (24, "Little Well"),
                  (26, "Garden Jump"), (28, "Swallow Tail"), (30, "Gallows Kink"), (32, "Last Hairpin")],
        sectors: (12, 24), start: 150, runoff: 4.5, gravel: true, gravelDepth: 10, wet: [(14, 16)])

    /// Every circuit, in the order the picker shows them.
    static let circuits: [CarProCircuit] = [brackenfield, thunderBowl, oldTown, kestrelHill, saltcliff, quarry,
                                            neonHarbour, nordwald]

    /// The built circuits, once.
    static let all: [CarProTrack] = circuits.map { CarProTrack($0) }

    static var ids: [String] { circuits.map(\.id) }

    static func track(_ id: String) -> CarProTrack? { all.first { $0.id == id } }
}

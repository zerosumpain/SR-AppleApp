import Foundation

// Orbit's thirty levels, ten in each system, easiest first. Each was laid
// out by hand and then checked by flying every launch the pad allows (half a
// degree by one percent of power): the stars sit on a line that reaches the
// target, and `demo` is a launch that collects every one and arrives. The
// tests fly every demo, and search for a way through each level afresh.
//
// The difficulty climbs by system: the Inner System teaches one idea a level
// (a bend, a pad on the ground, a moon, the sun, a belt); the Gas Giants pull
// harder, with moons and stations on the move; Deep Space has black holes,
// rubble and wormholes, and its aiming line shows the least.

enum OrbitLevels {
    static let count = 30

    /// Every level, in order: `all[n - 1]` is level n.
    static let all: [OrbitLevel] = [
        level1(),
        level2(),
        level3(),
        level4(),
        level5(),
        level6(),
        level7(),
        level8(),
        level9(),
        level10(),
        level11(),
        level12(),
        level13(),
        level14(),
        level15(),
        level16(),
        level17(),
        level18(),
        level19(),
        level20(),
        level21(),
        level22(),
        level23(),
        level24(),
        level25(),
        level26(),
        level27(),
        level28(),
        level29(),
        level30(),
    ]

    /// Level `number`, clamped to the ones there are.
    static func level(_ number: Int) -> OrbitLevel {
        all[min(max(number, 1), count) - 1]
    }

    private static func level1() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Pip", .rocky, 430.0, 470.0, radius: 34.0, mass: 400000),
        ]
        return OrbitLevel(
            number: 1, name: "First Light",
            hint: "Pull back, aim at the station and launch.",
            pad: OrbitKit.launcher(300.0, 800.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(300.0, 140.0, radius: 30.0),
            stars: [OrbitVec(290.0, 581.0), OrbitVec(288.0, 389.0)],
            par: 2, preview: 3.2, timeLimit: 12.0,
            demo: OrbitKit.shot(-93.00, 0.78)
        )
    }

    private static func level2() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Ferro", .rocky, 300.0, 470.0, radius: 44.0, mass: 1000000),
        ]
        return OrbitLevel(
            number: 2, name: "Round the Rock",
            hint: "A planet is in the way. Its pull bends your path, so aim to one side.",
            pad: OrbitKit.launcher(300.0, 820.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(300.0, 120.0, radius: 28.0),
            stars: [OrbitVec(257.0, 592.0), OrbitVec(253.0, 376.0)],
            par: 2, preview: 3.1, timeLimit: 12.0,
            demo: OrbitKit.shot(-101.00, 0.99)
        )
    }

    private static func level3() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Terra", .ocean, 300.0, 860.0, radius: 56.0, mass: 350000),
            OrbitKit.planet("Dusk", .desert, 220.0, 430.0, radius: 36.0, mass: 850000),
        ]
        return OrbitLevel(
            number: 3, name: "Home Ground",
            hint: "Launching from a planet, you can only fly up and away from the ground.",
            pad: OrbitKit.pad(on: bodies, 0, at: -90.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(440.0, 130.0, radius: 28.0),
            stars: [OrbitVec(355.0, 605.0), OrbitVec(387.0, 477.0), OrbitVec(412.0, 348.0)],
            par: 2, preview: 3.0, timeLimit: 12.0,
            demo: OrbitKit.shot(-74.00, 0.88)
        )
    }

    private static func level4() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Cinder", .lava, 170.0, 470.0, radius: 40.0, mass: 1100000),
            OrbitKit.planet("Frost", .ice, 440.0, 410.0, radius: 40.0, mass: 1100000),
        ]
        return OrbitLevel(
            number: 4, name: "Between Two",
            hint: "Two pulls at once. Thread the gap between them.",
            pad: OrbitKit.launcher(300.0, 830.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(300.0, 110.0, radius: 28.0),
            stars: [OrbitVec(305.0, 630.0), OrbitVec(306.0, 487.0), OrbitVec(305.0, 341.0)],
            par: 2, preview: 2.9, timeLimit: 12.0,
            demo: OrbitKit.shot(-89.00, 0.98)
        )
    }

    private static func level5() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Terra", .ocean, 110.0, 830.0, radius: 48.0, mass: 350000),
            OrbitKit.planet("Gaia", .jungle, 330.0, 450.0, radius: 50.0, mass: 1400000),
            OrbitKit.moon("Luna", around: 330.0, 450.0, distance: 125.0, period: 7.0, phase: 90.0, radius: 16.0, mass: 100000, look: .moon),
        ]
        return OrbitLevel(
            number: 5, name: "Moonrise",
            hint: "Moons ride round their dotted rails. Mind where the moon will be, not where it is.",
            pad: OrbitKit.pad(on: bodies, 0, at: -60.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(480.0, 120.0, radius: 28.0),
            stars: [OrbitVec(282.0, 624.0), OrbitVec(378.0, 502.0), OrbitVec(434.0, 352.0)],
            par: 2, preview: 2.8, timeLimit: 13.0,
            demo: OrbitKit.shot(-47.50, 0.99)
        )
    }

    private static func level6() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.sun(300.0, 440.0, radius: 60.0, mass: 2200000),
        ]
        return OrbitLevel(
            number: 6, name: "Sunward",
            hint: "The sun pulls hard and burns anything that touches it.",
            pad: OrbitKit.launcher(110.0, 820.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(490.0, 110.0, radius: 28.0),
            stars: [OrbitVec(173.0, 562.0), OrbitVec(284.0, 327.0)],
            par: 2, preview: 2.8, timeLimit: 13.0,
            demo: OrbitKit.shot(-77.00, 0.99)
        )
    }

    private static func level7() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Vesta", .rocky, 300.0, 400.0, radius: 44.0, mass: 1800000),
        ]
        return OrbitLevel(
            number: 7, name: "Slingshot",
            hint: "A rock wall blocks the way. Fly up, swing right round the planet and come back down.",
            pad: OrbitKit.launcher(470.0, 820.0),
            bodies: bodies,
            belts: [
                OrbitKit.belt(1300.0, 760.0, inner: 1000.0, outer: 1030.0, from: 172.0, span: 16.1),
            ],
            target: OrbitKit.station(130.0, 790.0, radius: 34.0),
            stars: [OrbitVec(493.0, 678.0), OrbitVec(475.0, 528.0), OrbitVec(247.0, 354.0)],
            par: 2, preview: 2.7, timeLimit: 15.0,
            demo: OrbitKit.shot(-71.50, 0.03)
        )
    }

    private static func level8() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.sun(190.0, 320.0, radius: 50.0, mass: 2000000),
            OrbitKit.planet("Ember", .lava, 290.0, 640.0, radius: 40.0, mass: 700000),
            OrbitKit.moon("Spark", around: 290.0, 640.0, distance: 80.0, period: 5.0, phase: 0.0, radius: 11.0, mass: 40000, look: .moon),
        ]
        return OrbitLevel(
            number: 8, name: "Hot Corner",
            hint: "Use the sun's pull to turn the corner without touching it.",
            pad: OrbitKit.launcher(480.0, 840.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(90.0, 500.0, radius: 26.0),
            stars: [OrbitVec(359.0, 765.0), OrbitVec(276.0, 707.0), OrbitVec(200.0, 635.0)],
            par: 2, preview: 2.6, timeLimit: 14.0,
            demo: OrbitKit.shot(-148.50, 0.96)
        )
    }

    private static func level9() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Pebble", .desert, 430.0, 620.0, radius: 34.0, mass: 900000),
        ]
        return OrbitLevel(
            number: 9, name: "The Belt",
            hint: "Rocks wreck a probe. Find the gap in the belt.",
            pad: OrbitKit.launcher(480.0, 840.0),
            bodies: bodies,
            belts: [
                OrbitKit.belt(112.5, 1435.0, inner: 1000.0, outer: 1030.0, from: 263.5, span: 12.9),
                OrbitKit.belt(487.5, 1435.0, inner: 1000.0, outer: 1030.0, from: 263.5, span: 12.9),
            ],
            target: OrbitKit.station(160.0, 120.0, radius: 28.0),
            stars: [OrbitVec(352.0, 641.0), OrbitVec(292.0, 495.0), OrbitVec(241.0, 353.0)],
            par: 2, preview: 2.5, timeLimit: 13.0,
            demo: OrbitKit.shot(-125.50, 0.96)
        )
    }

    private static func level10() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.sun(300.0, 430.0, radius: 50.0, mass: 1800000),
            OrbitKit.planet("Terra", .ocean, 120.0, 820.0, radius: 44.0, mass: 350000),
            OrbitKit.planet("Rust", .desert, 470.0, 640.0, radius: 30.0, mass: 650000),
            OrbitKit.moon("Flint", around: 470.0, 640.0, distance: 70.0, period: -5.0, phase: 180.0, radius: 10.0, mass: 35000, look: .moon),
        ]
        return OrbitLevel(
            number: 10, name: "Inner Tour",
            hint: "Planets, a moon and the sun, all pulling at once.",
            pad: OrbitKit.pad(on: bodies, 1, at: -45.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(300.0, 90.0, radius: 26.0),
            stars: [OrbitVec(160.0, 579.0), OrbitVec(173.0, 436.0), OrbitVec(212.0, 297.0)],
            par: 2, preview: 2.4, timeLimit: 15.0,
            demo: OrbitKit.shot(-88.50, 0.98)
        )
    }

    private static func level11() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Jove", .amber, 300.0, 450.0, radius: 76.0, mass: 3200000, ringed: true),
            OrbitKit.moon("Pell", around: 300.0, 450.0, distance: 140.0, period: 8.0, phase: 0.0, radius: 15.0, mass: 80000, look: .moon),
        ]
        return OrbitLevel(
            number: 11, name: "Big Pull",
            hint: "Gas giants pull far harder than rocky planets. Let it swing you round.",
            pad: OrbitKit.launcher(480.0, 840.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(120.0, 120.0, radius: 28.0),
            stars: [OrbitVec(308.0, 692.0), OrbitVec(196.0, 557.0), OrbitVec(135.0, 383.0)],
            par: 2, preview: 2.3, timeLimit: 15.0,
            demo: OrbitKit.shot(-138.00, 0.78)
        )
    }

    private static func level12() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Sorrel", .rose, 300.0, 450.0, radius: 64.0, mass: 2600000),
            OrbitKit.moon("Bram", around: 300.0, 450.0, distance: 130.0, period: 6.0, phase: 30.0, radius: 15.0, mass: 80000, look: .moon),
            OrbitKit.moon("Wick", around: 300.0, 450.0, distance: 205.0, period: -9.0, phase: 200.0, radius: 18.0, mass: 120000, look: .moon),
        ]
        return OrbitLevel(
            number: 12, name: "Moon Dance",
            hint: "Two moons, going opposite ways. Find a moment when the way is clear.",
            pad: OrbitKit.launcher(300.0, 850.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(300.0, 80.0, radius: 26.0),
            stars: [OrbitVec(363.0, 641.0), OrbitVec(393.0, 482.0), OrbitVec(375.0, 315.0)],
            par: 2, preview: 2.2, timeLimit: 15.0,
            demo: OrbitKit.shot(-72.50, 0.99)
        )
    }

    private static func level13() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Tethys", .teal, 300.0, 420.0, radius: 66.0, mass: 2700000),
        ]
        return OrbitLevel(
            number: 13, name: "Catch the Station",
            hint: "The station orbits the giant. Aim for where it is going to be.",
            pad: OrbitKit.launcher(460.0, 850.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.orbitingStation(around: 300.0, 420.0, distance: 175.0, period: 11.0, phase: 150.0, radius: 26.0),
            stars: [OrbitVec(345.0, 697.0), OrbitVec(245.0, 549.0)],
            par: 2, preview: 2.1, timeLimit: 15.0,
            demo: OrbitKit.shot(-127.50, 0.88)
        )
    }

    private static func level14() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Castor", .amber, 190.0, 300.0, radius: 58.0, mass: 2400000),
            OrbitKit.planet("Pollux", .violet, 410.0, 600.0, radius: 58.0, mass: 2400000, ringed: true),
        ]
        return OrbitLevel(
            number: 14, name: "Twin Giants",
            hint: "Weave between two giants: one bends you, the other bends you back.",
            pad: OrbitKit.launcher(110.0, 840.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(500.0, 90.0, radius: 26.0),
            stars: [OrbitVec(209.0, 626.0), OrbitVec(293.0, 475.0), OrbitVec(382.0, 326.0)],
            par: 3, preview: 2.0, timeLimit: 15.0,
            demo: OrbitKit.shot(-66.00, 0.99)
        )
    }

    private static func level15() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Hale", .teal, 160.0, 520.0, radius: 54.0, mass: 2400000),
            OrbitKit.planet("Marl", .amber, 450.0, 300.0, radius: 50.0, mass: 2000000),
        ]
        return OrbitLevel(
            number: 15, name: "Ringside",
            hint: "A belt of rocks cuts the system in two. Go round it or through the gap.",
            pad: OrbitKit.launcher(470.0, 850.0),
            bodies: bodies,
            belts: [
                OrbitKit.belt(435.0, 1655.0, inner: 1000.0, outer: 1030.0, from: 260.5, span: 19.0),
            ],
            target: OrbitKit.station(120.0, 120.0, radius: 26.0),
            stars: [OrbitVec(213.0, 797.0), OrbitVec(39.0, 663.0), OrbitVec(34.0, 244.0)],
            par: 3, preview: 1.9, timeLimit: 15.0,
            demo: OrbitKit.shot(-180.00, 0.26)
        )
    }

    private static func level16() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Oberon", .violet, 300.0, 380.0, radius: 60.0, mass: 2600000, ringed: true),
            OrbitKit.moon("Puck", around: 300.0, 380.0, distance: 120.0, period: -6.0, phase: 90.0, radius: 14.0, mass: 70000, look: .moon),
        ]
        return OrbitLevel(
            number: 16, name: "Fast Station",
            hint: "This station laps quickly. Launch early and meet it on the way round.",
            pad: OrbitKit.launcher(300.0, 860.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.orbitingStation(around: 300.0, 380.0, distance: 200.0, period: 7.0, phase: 0.0, radius: 24.0),
            stars: [OrbitVec(327.0, 777.0), OrbitVec(344.0, 721.0), OrbitVec(362.0, 663.0)],
            par: 3, preview: 1.9, timeLimit: 15.0,
            demo: OrbitKit.shot(-72.00, 0.86)
        )
    }

    private static func level17() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Halcyon", .rose, 200.0, 360.0, radius: 56.0, mass: 2300000),
            OrbitKit.planet("Teal", .teal, 430.0, 560.0, radius: 48.0, mass: 1700000),
            OrbitKit.moon("Cob", around: 430.0, 560.0, distance: 95.0, period: 6.0, phase: 270.0, radius: 12.0, mass: 50000, look: .moon),
        ]
        return OrbitLevel(
            number: 17, name: "Wormhole",
            hint: "A wormhole works like a station: fly into its middle.",
            pad: OrbitKit.launcher(100.0, 860.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.wormhole(480.0, 150.0, radius: 28.0),
            stars: [OrbitVec(205.0, 668.0), OrbitVec(282.0, 529.0), OrbitVec(365.0, 383.0)],
            par: 3, preview: 1.8, timeLimit: 16.0,
            demo: OrbitKit.shot(-61.50, 0.98)
        )
    }

    private static func level18() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Ash", .amber, 180.0, 660.0, radius: 50.0, mass: 1900000),
            OrbitKit.planet("Briar", .violet, 420.0, 450.0, radius: 52.0, mass: 2000000, ringed: true),
            OrbitKit.planet("Cress", .teal, 180.0, 230.0, radius: 50.0, mass: 1900000),
        ]
        return OrbitLevel(
            number: 18, name: "Gauntlet",
            hint: "Three giants in a row. Bend left, right and left again.",
            pad: OrbitKit.launcher(470.0, 860.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(480.0, 80.0, radius: 24.0),
            stars: [OrbitVec(566.0, 661.0), OrbitVec(549.0, 707.0), OrbitVec(566.0, 256.0)],
            par: 3, preview: 1.7, timeLimit: 16.0,
            demo: OrbitKit.shot(-58.00, 0.53)
        )
    }

    private static func level19() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Mimas", .amber, 300.0, 470.0, radius: 56.0, mass: 2400000, ringed: true),
            OrbitKit.moon("Tick", around: 300.0, 470.0, distance: 110.0, period: 5.0, phase: 0.0, radius: 12.0, mass: 50000, look: .moon),
            OrbitKit.moon("Tock", around: 300.0, 470.0, distance: 165.0, period: -7.0, phase: 120.0, radius: 14.0, mass: 70000, look: .moon),
            OrbitKit.moon("Chime", around: 300.0, 470.0, distance: 225.0, period: 10.0, phase: 240.0, radius: 16.0, mass: 90000, look: .moon),
        ]
        return OrbitLevel(
            number: 19, name: "Clockwork",
            hint: "Three moons on three rails, each at its own pace.",
            pad: OrbitKit.launcher(300.0, 870.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(300.0, 70.0, radius: 24.0),
            stars: [OrbitVec(237.0, 651.0), OrbitVec(208.0, 483.0), OrbitVec(230.0, 312.0)],
            par: 3, preview: 1.6, timeLimit: 16.0,
            demo: OrbitKit.shot(-107.00, 0.99)
        )
    }

    private static func level20() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Regal", .rose, 200.0, 560.0, radius: 60.0, mass: 2600000, ringed: true),
            OrbitKit.moon("Page", around: 200.0, 560.0, distance: 115.0, period: 6.0, phase: 45.0, radius: 13.0, mass: 60000, look: .moon),
            OrbitKit.planet("Sable", .violet, 430.0, 280.0, radius: 52.0, mass: 2100000),
            OrbitKit.moon("Knave", around: 430.0, 280.0, distance: 100.0, period: -5.0, phase: 200.0, radius: 12.0, mass: 50000, look: .moon),
        ]
        return OrbitLevel(
            number: 20, name: "Crown",
            hint: "Two giants, two moons and a station that will not sit still.",
            pad: OrbitKit.launcher(480.0, 860.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.orbitingStation(around: 430.0, 280.0, distance: 175.0, period: 12.0, phase: 160.0, radius: 24.0),
            stars: [OrbitVec(566.0, 718.0), OrbitVec(544.0, 761.0), OrbitVec(520.0, 803.0)],
            par: 3, preview: 1.5, timeLimit: 17.0,
            demo: OrbitKit.shot(-52.50, 0.35)
        )
    }

    private static func level21() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.hole(300.0, 430.0, horizon: 14.0, mass: 3500000),
        ]
        return OrbitLevel(
            number: 21, name: "Event Horizon",
            hint: "A black hole is small but pulls like a giant. Get too close and it keeps you.",
            pad: OrbitKit.launcher(470.0, 830.0),
            bodies: bodies,
            belts: [
                OrbitKit.belt(1300.0, 730.0, inner: 1000.0, outer: 1030.0, from: 170.2, span: 19.6),
            ],
            target: OrbitKit.station(120.0, 800.0, radius: 26.0),
            stars: [OrbitVec(442.0, 652.0), OrbitVec(375.0, 468.0), OrbitVec(177.0, 573.0)],
            par: 3, preview: 1.4, timeLimit: 15.0,
            demo: OrbitKit.shot(-95.50, 0.22)
        )
    }

    private static func level22() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.hole(430.0, 300.0, horizon: 14.0, mass: 3200000),
            OrbitKit.planet("Umbra", .ice, 200.0, 540.0, radius: 40.0, mass: 1000000),
        ]
        return OrbitLevel(
            number: 22, name: "Dark Bend",
            hint: "Skim the black hole to turn a sharp corner.",
            pad: OrbitKit.launcher(90.0, 860.0),
            bodies: bodies,
            belts: [
                OrbitKit.belt(1375.0, 740.0, inner: 1000.0, outer: 1030.0, from: 170.8, span: 18.4),
            ],
            target: OrbitKit.station(515.0, 710.0, radius: 28.0),
            stars: [OrbitVec(456.0, 866.0), OrbitVec(477.0, 823.0), OrbitVec(495.0, 778.0)],
            par: 3, preview: 1.3, timeLimit: 15.0,
            demo: OrbitKit.shot(52.00, 0.09)
        )
    }

    private static func level23() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.moon("Helios", around: 300.0, 430.0, distance: 85.0, period: 7.0, phase: 0.0, radius: 30.0, mass: 1100000, look: .sun),
            OrbitKit.moon("Selene", around: 300.0, 430.0, distance: 85.0, period: 7.0, phase: 180.0, radius: 30.0, mass: 1100000, look: .sun),
        ]
        return OrbitLevel(
            number: 23, name: "Binary",
            hint: "Two suns circle each other. Slip past while the gap is open.",
            pad: OrbitKit.launcher(300.0, 860.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(300.0, 70.0, radius: 24.0),
            stars: [OrbitVec(365.0, 648.0), OrbitVec(397.0, 485.0), OrbitVec(382.0, 314.0)],
            par: 3, preview: 1.2, timeLimit: 15.0,
            demo: OrbitKit.shot(-72.50, 0.93)
        )
    }

    private static func level24() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Grit", .rocky, 300.0, 450.0, radius: 30.0, mass: 700000),
        ]
        return OrbitLevel(
            number: 24, name: "Rubble",
            hint: "Belt after belt. Weave through the gaps.",
            pad: OrbitKit.launcher(300.0, 860.0),
            bodies: bodies,
            belts: [
                OrbitKit.belt(145.0, 1675.0, inner: 1000.0, outer: 1030.0, from: 261.7, span: 16.7),
                OrbitKit.belt(525.0, 1465.0, inner: 1000.0, outer: 1030.0, from: 265.7, span: 8.6),
                OrbitKit.belt(75.0, 1465.0, inner: 1000.0, outer: 1030.0, from: 265.7, span: 8.6),
                OrbitKit.belt(455.0, 1255.0, inner: 1000.0, outer: 1030.0, from: 261.7, span: 16.7),
            ],
            target: OrbitKit.station(120.0, 90.0, radius: 24.0),
            stars: [OrbitVec(327.0, 632.0), OrbitVec(339.0, 491.0), OrbitVec(251.0, 300.0)],
            par: 3, preview: 1.1, timeLimit: 15.0,
            demo: OrbitKit.shot(-83.00, 0.62)
        )
    }

    private static func level25() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.hole(300.0, 470.0, horizon: 14.0, mass: 3600000),
        ]
        return OrbitLevel(
            number: 25, name: "Lensing",
            hint: "The wormhole is right behind the black hole. Bend round it.",
            pad: OrbitKit.launcher(300.0, 860.0),
            bodies: bodies,
            belts: [
                OrbitKit.belt(1105.0, 475.0, inner: 1000.0, outer: 1030.0, from: 167.0, span: 26.0),
                OrbitKit.belt(1525.0, 475.0, inner: 1000.0, outer: 1030.0, from: 167.0, span: 26.0),
            ],
            target: OrbitKit.wormhole(300.0, 90.0, radius: 26.0),
            stars: [OrbitVec(218.0, 658.0), OrbitVec(182.0, 492.0), OrbitVec(209.0, 321.0)],
            par: 3, preview: 1.0, timeLimit: 15.0,
            demo: OrbitKit.shot(-110.50, 0.98)
        )
    }

    private static func level26() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.sun(300.0, 430.0, radius: 44.0, mass: 2000000, name: "the pulsar"),
        ]
        return OrbitLevel(
            number: 26, name: "Pulsar",
            hint: "A ring of rocks round a burning star, with one way in and out.",
            pad: OrbitKit.launcher(120.0, 860.0),
            bodies: bodies,
            belts: [
                OrbitKit.belt(300.0, 430.0, inner: 130.0, outer: 155.0, from: 340.0, span: 280.0),
            ],
            target: OrbitKit.station(480.0, 80.0, radius: 24.0),
            stars: [OrbitVec(298.0, 696.0), OrbitVec(415.0, 550.0), OrbitVec(480.0, 361.0)],
            par: 3, preview: 1.0, timeLimit: 16.0,
            demo: OrbitKit.shot(-40.50, 0.44)
        )
    }

    private static func level27() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.planet("Wisp", .ice, 160.0, 620.0, radius: 22.0, mass: 400000),
            OrbitKit.planet("Mote", .rocky, 430.0, 450.0, radius: 20.0, mass: 350000),
            OrbitKit.planet("Gleam", .ocean, 200.0, 240.0, radius: 24.0, mass: 450000),
        ]
        return OrbitLevel(
            number: 27, name: "Long Drift",
            hint: "Weak pulls, a long way to go and not much battery.",
            pad: OrbitKit.launcher(560.0, 870.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(60.0, 60.0, radius: 24.0),
            stars: [OrbitVec(404.0, 647.0), OrbitVec(297.0, 492.0), OrbitVec(192.0, 336.0)],
            par: 3, preview: 0.9, timeLimit: 9.0,
            demo: OrbitKit.shot(-125.00, 0.99)
        )
    }

    private static func level28() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.hole(300.0, 460.0, horizon: 14.0, mass: 3400000),
            OrbitKit.moon("Shade", around: 300.0, 460.0, distance: 210.0, period: 9.0, phase: 90.0, radius: 16.0, mass: 90000, look: .moon),
        ]
        return OrbitLevel(
            number: 28, name: "Maelstrom",
            hint: "A black hole in a ring of rubble, with a moon on guard.",
            pad: OrbitKit.launcher(300.0, 870.0),
            bodies: bodies,
            belts: [
                OrbitKit.belt(300.0, 460.0, inner: 115.0, outer: 135.0, from: 300.0, span: 300.0),
            ],
            target: OrbitKit.station(300.0, 70.0, radius: 24.0),
            stars: [OrbitVec(402.0, 664.0), OrbitVec(445.0, 488.0), OrbitVec(416.0, 304.0)],
            par: 3, preview: 0.8, timeLimit: 16.0,
            demo: OrbitKit.shot(-60.50, 0.61)
        )
    }

    private static func level29() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.hole(200.0, 340.0, horizon: 13.0, mass: 2600000),
            OrbitKit.hole(410.0, 580.0, horizon: 13.0, mass: 2600000),
        ]
        return OrbitLevel(
            number: 29, name: "Needle",
            hint: "Two black holes. Thread the needle between them.",
            pad: OrbitKit.launcher(80.0, 860.0),
            bodies: bodies,
            belts: [],
            target: OrbitKit.station(530.0, 110.0, radius: 22.0),
            stars: [OrbitVec(195.0, 648.0), OrbitVec(288.0, 494.0), OrbitVec(391.0, 338.0)],
            par: 3, preview: 0.7, timeLimit: 15.0,
            demo: OrbitKit.shot(-62.00, 0.99)
        )
    }

    private static func level30() -> OrbitLevel {
        let bodies: [OrbitBody] = [
            OrbitKit.moon("Castle", around: 190.0, 540.0, distance: 70.0, period: 6.0, phase: 0.0, radius: 24.0, mass: 900000, look: .sun),
            OrbitKit.moon("Keep", around: 190.0, 540.0, distance: 70.0, period: 6.0, phase: 180.0, radius: 24.0, mass: 900000, look: .sun),
            OrbitKit.hole(440.0, 300.0, horizon: 13.0, mass: 2800000),
        ]
        return OrbitLevel(
            number: 30, name: "The Far Gate",
            hint: "Everything deep space has, between you and the last wormhole.",
            pad: OrbitKit.launcher(500.0, 870.0),
            bodies: bodies,
            belts: [
                OrbitKit.belt(450.0, 1175.0, inner: 1000.0, outer: 1030.0, from: 261.4, span: 17.3),
            ],
            target: OrbitKit.wormhole(530.0, 80.0, radius: 28.0),
            stars: [OrbitVec(566.0, 775.0), OrbitVec(540.0, 816.0)],
            par: 3, preview: 0.6, timeLimit: 17.0,
            demo: OrbitKit.shot(-51.50, 0.32)
        )
    }
}

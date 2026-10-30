import XCTest
@testable import SRAppleApp

/// Hometowns' shell sums: the growth bar, the fortnight's dots, the
/// milestones this phone celebrates, and an animal face for every mayor.
final class HometownsProgressTests: XCTestCase {

    // MARK: Growth

    func testGrowthFromHamletToVillage() {
        let g = HometownsGrowth.of(population: 150, tier: 0, floors: [0, 300, 2000, 15000, 80000])
        XCTAssertEqual(g.nextTier, 1)
        XCTAssertEqual(g.needed, 150)
        XCTAssertEqual(g.fraction, 0.5, accuracy: 0.0001)
    }

    func testGrowthIsClampedAndStopsAtTheTop() {
        let floors = [0, 300, 2000, 15000, 80000]
        // Past the next floor but not promoted yet: a full bar, nobody still needed.
        let full = HometownsGrowth.of(population: 450, tier: 0, floors: floors)
        XCTAssertEqual(full.fraction, 1)
        XCTAssertEqual(full.needed, 0)
        // Shrunk below its own floor: an empty bar, never a negative one.
        let empty = HometownsGrowth.of(population: 1500, tier: 2, floors: floors)
        XCTAssertEqual(empty.fraction, 0)
        XCTAssertEqual(empty.needed, 13500)
        let top = HometownsGrowth.of(population: 90000, tier: 4, floors: floors)
        XCTAssertNil(top.nextTier)
        XCTAssertEqual(top.fraction, 1)
        XCTAssertNil(HometownsGrowth.of(population: 10, tier: 9, floors: floors).nextTier)
        XCTAssertNil(HometownsGrowth.of(population: 10, tier: 0, floors: []).nextTier)
    }

    func testGrowthUsesTheCatalogueByDefault() {
        let g = HometownsGrowth.of(population: 0, tier: 0)
        XCTAssertEqual(g.nextTier, 1)
        XCTAssertEqual(g.needed, HometownsCatalogue.tierPopulation[1])
    }

    // MARK: The fortnight

    func testSprintWeeks() {
        XCTAssertEqual(HometownsSprintWeeks.of(left: 12).done, 0)
        XCTAssertEqual(HometownsSprintWeeks.of(left: 3).done, 9)
        XCTAssertEqual(HometownsSprintWeeks.of(left: 0).done, 12)
        XCTAssertEqual(HometownsSprintWeeks.of(left: -4).done, 12)
        let wide = HometownsSprintWeeks.of(left: 14)
        XCTAssertEqual(wide.done, 0)
        XCTAssertEqual(wide.total, 14)
    }

    // MARK: Milestones

    func testTheFirstLookOnlyRecords() {
        var m = HometownsMilestones()
        XCTAssertNil(m.observe(tier: 2, population: 4000))
        XCTAssertTrue(m.seen)
        XCTAssertEqual(m.highestTier, 2)
        XCTAssertEqual(m.peakPopulation, 4000)
    }

    func testATierUpBeatsAHeadCount() {
        var m = HometownsMilestones()
        _ = m.observe(tier: 0, population: 240)
        XCTAssertEqual(m.observe(tier: 1, population: 310), .tierUp(1))
        // The same tier again is nothing new.
        XCTAssertNil(m.observe(tier: 1, population: 320))
    }

    func testPopulationMarksFireOnceEach() {
        var m = HometownsMilestones()
        _ = m.observe(tier: 0, population: 40)
        XCTAssertEqual(m.observe(tier: 0, population: 60), .population(50))
        XCTAssertNil(m.observe(tier: 0, population: 70))
        // Falling back and climbing again does not repeat a mark already passed.
        XCTAssertNil(m.observe(tier: 0, population: 45))
        XCTAssertNil(m.observe(tier: 0, population: 65))
        // Passing two marks in one frame names the bigger.
        XCTAssertEqual(m.observe(tier: 0, population: 260), .population(250))
    }

    func testATierDropIsNotCelebratedAndTheBestIsKept() {
        var m = HometownsMilestones()
        _ = m.observe(tier: 2, population: 2500)
        XCTAssertNil(m.observe(tier: 1, population: 1800))
        XCTAssertEqual(m.highestTier, 2)
        XCTAssertEqual(m.peakPopulation, 2500)
        XCTAssertNil(m.observe(tier: 2, population: 2400))
    }

    func testTheStoreRemembersPerCountyAndSeat() throws {
        let suite = "hometowns-progress-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HometownsMilestoneStore(defaults: defaults)
        XCTAssertEqual(HometownsMilestoneStore.key(roomId: "g_1", seat: "s1"), "hometowns-milestones-g_1-s1")
        XCTAssertNil(store.observe(roomId: "g_1", seat: "s1", tier: 0, population: 90))
        XCTAssertEqual(store.observe(roomId: "g_1", seat: "s1", tier: 0, population: 120), .population(100))
        XCTAssertEqual(store.load(roomId: "g_1", seat: "s1").peakPopulation, 120)
        // Another county starts from nothing.
        XCTAssertNil(store.observe(roomId: "g_2", seat: "s1", tier: 0, population: 120))
        XCTAssertEqual(store.observe(roomId: "g_1", seat: "s1", tier: 1, population: 320), .tierUp(1))
    }

    func testAMangledRecordStartsAgain() throws {
        let suite = "hometowns-progress-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("nope".utf8), forKey: HometownsMilestoneStore.key(roomId: "g_1", seat: "s1"))
        let store = HometownsMilestoneStore(defaults: defaults)
        XCTAssertEqual(store.load(roomId: "g_1", seat: "s1"), HometownsMilestones())
    }

    // MARK: Animals

    func testEveryMayorAndAdvisorHasAFace() {
        for animal in HometownsCatalogue.avatars {
            XCTAssertTrue(HometownsCritter.known.contains(animal), animal)
        }
        let badger = HometownsCritter.of("badger")
        XCTAssertTrue(badger.stripes)
        XCTAssertEqual(HometownsCritter.of("kingsport"), badger)
        XCTAssertEqual(HometownsCritter.advisorAnimal("bramble"), "badger")
        XCTAssertEqual(HometownsCritter.advisorAnimal("mo"), "hedgehog")
        XCTAssertEqual(HometownsCritter.advisorAnimal("penny"), "magpie")
        XCTAssertEqual(HometownsCritter.advisorAnimal("zia"), "otter")
        // Each known animal other than the badger is drawn as itself, not as the fallback.
        for animal in HometownsCritter.known where animal != "badger" {
            XCTAssertNotEqual(HometownsCritter.of(animal), badger, animal)
        }
    }

    func testDarkHeadsGetPaleEyes() {
        XCTAssertTrue(HometownsCritter.of("mole").darkHead)
        XCTAssertTrue(HometownsCritter.of("puffin").darkHead)
        XCTAssertFalse(HometownsCritter.of("fox").darkHead)
        XCTAssertFalse(HometownsCritter.of("badger").darkHead)
        XCTAssertTrue(HometownsCritter.of("mole").paleEyes)
        XCTAssertTrue(HometownsCritter.of("magpie").paleEyes)
        // The puffin's eyes sit on its white mask.
        XCTAssertFalse(HometownsCritter.of("puffin").paleEyes)
        XCTAssertEqual(HometownsCritter.luminance(0xFFFFFF), 1, accuracy: 0.0001)
        XCTAssertEqual(HometownsCritter.luminance(0x000000), 0, accuracy: 0.0001)
    }
}

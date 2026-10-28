import XCTest
@testable import SRAppleApp

/// "Family now": the snapshot the app leaves on the shelf, its words, and the
/// glance widgets' links.
///
/// Foundation only: `scripts/home-check.sh` runs this file on Linux too.
final class FamilyNowWidgetTests: XCTestCase {

    /// Tuesday 27 October 2026, 10:00 in London (GMT).
    private let ten = Date(timeIntervalSince1970: 1_793_095_200)

    private func iso(_ minutesAgo: Double) -> String {
        ISO8601DateFormatter().string(from: ten.addingTimeInterval(-minutesAgo * 60))
    }

    private var household: [FamilyNow.Input] {
        [
            .init(name: "Sam Lee", initials: "Sa", status: "home", place: "Home", km: 0.02, battery: 92, lastSeenAt: iso(14), hue: 3),
            .init(name: "Robin", initials: "Ro", status: "out", movingMode: "walking", km: 1.234, battery: 18, lastSeenAt: iso(2), hue: 1),
            .init(name: "John Kelly", initials: "Jo", isSelf: true, status: "home", battery: 64, lastSeenAt: iso(1), hue: 0),
            .init(name: "Pat", initials: "Pa", status: "off", place: "Work", km: 4, battery: 50, lastSeenAt: iso(5), hue: 5),
            .init(name: "Kit", initials: "Ki", status: "out", place: "School", km: 2.44, battery: 71, lastSeenAt: iso(6), hue: 2),
            .init(name: "Alex", initials: "Al", status: "unknown", place: "The Park", lastSeenAt: iso(190), hue: 4),
        ]
    }

    // MARK: - Snapshot

    func testYouFirstThenMovingOutHomeUnseenOff() {
        let s = FamilyNow.snapshot(household, now: ten)
        XCTAssertEqual(s.people.map(\.initials), ["Jo", "Ro", "Ki", "Sa", "Al", "Pa"])
        XCTAssertEqual(s.savedAt, ten)
    }

    func testMovingWinsOverTheSitesStatus() {
        XCTAssertEqual(FamilyNow.state(status: "home", moving: true), .moving)
        XCTAssertEqual(FamilyNow.state(status: "out", moving: false), .out)
        XCTAssertEqual(FamilyNow.state(status: "unknown", moving: false), .unseen)
        XCTAssertEqual(FamilyNow.state(status: "something-new", moving: false), .unseen)
        XCTAssertEqual(FamilyNow.state(status: "off", moving: true), .off, "not sharing says nothing of moving")
    }

    func testTheShelfKeepsFirstNamesAndRoundedDistances() throws {
        let s = FamilyNow.snapshot(household, now: ten)
        let robin = try XCTUnwrap(s.people.first { $0.initials == "Ro" })
        XCTAssertEqual(robin.km, 1.2)
        XCTAssertEqual(robin.mode, "walking")
        XCTAssertEqual(robin.seenAt, ten.addingTimeInterval(-120))
        let sam = try XCTUnwrap(s.people.first { $0.initials == "Sa" })
        XCTAssertEqual(sam.name, "Sam", "first name only")
        XCTAssertNil(sam.mode, "not moving: no mode kept")
    }

    func testSomebodyNotSharingLeavesNothingOfWhereTheyAre() throws {
        let pat = try XCTUnwrap(FamilyNow.snapshot(household, now: ten).people.first { $0.initials == "Pa" })
        XCTAssertEqual(pat.state, .off)
        XCTAssertNil(pat.place)
        XCTAssertNil(pat.km)
        XCTAssertNil(pat.battery)
        XCTAssertNil(pat.seenAt)
        XCTAssertEqual(FamilyNow.line(pat), "Not sharing")
    }

    func testKeepCapsThePeople() {
        XCTAssertEqual(FamilyNow.snapshot(household, now: ten, keep: 3).people.count, 3)
    }

    func testSameContentIgnoresWhenItWasSaved() {
        let a = FamilyNow.snapshot(household, now: ten)
        var b = a
        b.savedAt = ten.addingTimeInterval(60)
        XCTAssertTrue(b.sameContent(as: a))
        b.people[0].battery = 10
        XCTAssertFalse(b.sameContent(as: a))
        XCTAssertFalse(a.sameContent(as: nil))
    }

    func testTheSnapshotRoundTripsThroughJSON() throws {
        let s = FamilyNow.snapshot(household, now: ten)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(FamilyNowSnapshot.self, from: data), s)
    }

    // MARK: - Words

    func testCountsNameOnlyWhatSomebodyIs() {
        let s = FamilyNow.snapshot(household, now: ten)
        XCTAssertEqual(FamilyNow.counts(s), "2 home · 1 out · 1 moving")
        XCTAssertEqual(FamilyNow.counts(FamilyNowSnapshot(people: [], savedAt: ten)), "Nobody yet")
        let unseen = FamilyNow.snapshot([.init(name: "Alex", initials: "Al", status: "unknown")], now: ten)
        XCTAssertEqual(FamilyNow.counts(unseen), "Nobody placed")
    }

    func testEachStateHasItsLine() throws {
        let s = FamilyNow.snapshot(household, now: ten)
        func line(_ initials: String) throws -> String {
            FamilyNow.line(try XCTUnwrap(s.people.first { $0.initials == initials }))
        }
        XCTAssertEqual(try line("Sa"), "Home")
        XCTAssertEqual(try line("Ro"), "Walking · 1.2 km from home")
        XCTAssertEqual(try line("Ki"), "School · 2.4 km")
        XCTAssertEqual(try line("Al"), "Last at The Park")
    }

    func testAnOutLineWithoutAPlaceSaysHowFar() {
        let person = FamilyNowPerson(initials: "Ro", name: "Robin", isSelf: false, state: .out, mode: nil,
                                     place: nil, km: 12.4, battery: nil, seenAt: nil, hue: 0)
        XCTAssertEqual(FamilyNow.line(person), "12 km from home")
        var nowhere = person
        nowhere.km = nil
        XCTAssertEqual(FamilyNow.line(nowhere), "Out")
    }

    func testDistances() {
        XCTAssertNil(FamilyNow.distance(nil))
        XCTAssertNil(FamilyNow.distance(0.05), "that close is home")
        XCTAssertEqual(FamilyNow.distance(0.34), "350 m")
        XCTAssertEqual(FamilyNow.distance(2.44), "2.4 km")
        XCTAssertEqual(FamilyNow.distance(12.6), "13 km")
    }

    func testFreshnessAndBattery() throws {
        let s = FamilyNow.snapshot(household, now: ten)
        let robin = try XCTUnwrap(s.people.first { $0.initials == "Ro" })
        XCTAssertEqual(FamilyNow.seen(robin, now: ten), "2m")
        XCTAssertFalse(FamilyNow.isStale(robin, now: ten))
        let alex = try XCTUnwrap(s.people.first { $0.initials == "Al" })
        XCTAssertTrue(FamilyNow.isStale(alex, now: ten), "three hours: faded")
        XCTAssertTrue(FamilyNow.isLow(18))
        XCTAssertTrue(FamilyNow.isLow(20))
        XCTAssertFalse(FamilyNow.isLow(21))
        XCTAssertFalse(FamilyNow.isLow(nil))
        XCTAssertEqual(FamilyNow.batterySymbol(18), "battery.25percent")
    }

    func testSpokenSaysTheBatteryIsLow() throws {
        let robin = try XCTUnwrap(FamilyNow.snapshot(household, now: ten).people.first { $0.initials == "Ro" })
        XCTAssertEqual(FamilyNow.spoken(robin, now: ten),
                       "Robin, Walking · 1.2 km from home, battery 18 percent, low, seen 2m ago")
        let me = try XCTUnwrap(FamilyNow.snapshot(household, now: ten).people.first)
        XCTAssertEqual(FamilyNow.who(me), "You")
    }

    // MARK: - Links

    func testGlanceLinks() {
        XCTAssertEqual(GlanceLink.from(url: GlanceLink.familyURL), .family)
        XCTAssertEqual(GlanceLink.from(url: GlanceLink.healthURL), .health)
        XCTAssertEqual(GlanceLink.from(url: GlanceLink.gamesURL), .games(room: nil, game: nil))
        XCTAssertEqual(GlanceLink.from(url: GlanceLink.gameURL(room: "r 1", game: "chess")), .games(room: "r 1", game: "chess"))
        XCTAssertEqual(GlanceLink.from(url: URL(string: "SR://Games/abc")!), .games(room: "abc", game: nil))
    }

    func testFamilyPagesAreNotTheTab() {
        XCTAssertNil(GlanceLink.from(url: URL(string: "sr://family/steps")!), "FamilyPage's link")
        XCTAssertNil(GlanceLink.from(url: URL(string: "sr://trips/abc")!))
        XCTAssertNil(GlanceLink.from(url: URL(string: "https://family")!))
    }
}

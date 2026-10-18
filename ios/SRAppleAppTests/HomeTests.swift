import XCTest
@testable import SRAppleApp

/// Home's rules: which tiles exist, the reader's order and switches, how the
/// rows pack — and the family pictures' geometry.
final class HomeTests: XCTestCase {

    // MARK: - Which tiles exist

    func testTheOwnerHasEveryTile() {
        XCTAssertEqual(HomeTileKind.available(access: .everything, sitePaired: true), HomeTileKind.defaultOrder)
    }

    func testFamilyComesFirst() {
        XCTAssertEqual(HomeTileKind.defaultOrder.first, .family)
    }

    func testAMemberWithFamilyAndGamesHasNoOwnerTiles() {
        let member = AppAccess(family: true, games: true)
        let tiles = HomeTileKind.available(access: member, sitePaired: true)
        XCTAssertTrue(tiles.contains(.family))
        XCTAssertTrue(tiles.contains(.steps), "family + site credential is the family boards")
        XCTAssertTrue(tiles.contains(.games))
        for owner in [HomeTileKind.news, .daydream, .flows, .wildmind, .chat] {
            XCTAssertFalse(tiles.contains(owner), "\(owner) leaked to a member")
        }
    }

    func testNoSiteCredentialMeansNoBoards() {
        let tiles = HomeTileKind.available(access: AppAccess(family: true), sitePaired: false)
        XCTAssertEqual(tiles, [.family, .health, .familyDay])
    }

    func testEveryoneHasHealth() {
        XCTAssertEqual(HomeTileKind.available(access: .nothing, sitePaired: false), [.health])
    }

    // MARK: - The reader's layout

    func testANewInstallShowsEverythingInTheDefaultOrder() {
        let available = HomeTileKind.available(access: .everything, sitePaired: true)
        XCTAssertEqual(HomeLayout().visible(available), available)
    }

    func testHiddenTilesStayListedButAreNotDrawn() {
        var layout = HomeLayout()
        layout.set(.news, shown: false)
        let available = HomeTileKind.available(access: .everything, sitePaired: true)
        XCTAssertFalse(layout.visible(available).contains(.news))
        XCTAssertTrue(layout.arranged(available).contains(.news))
        layout.set(.news, shown: true)
        XCTAssertTrue(layout.visible(available).contains(.news))
    }

    func testAMoveIsKeptAndSurvivesTheRoundTrip() {
        let available: [HomeTileKind] = [.family, .health, .steps]
        var layout = HomeLayout()
        layout.move(available, from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(layout.arranged(available), [.steps, .family, .health])
        XCTAssertEqual(HomeLayout.decode(layout.raw).arranged(available), [.steps, .family, .health])
    }

    func testATileGainedLaterLandsBesideItsNeighbourAndShown() {
        // Stored before the person had the boards.
        let layout = HomeLayout(order: [.health, .family])
        let now: [HomeTileKind] = [.family, .health, .steps]
        // Steps follows Health by default, so it lands straight after it.
        XCTAssertEqual(layout.visible(now), [.health, .steps, .family])
    }

    func testTilesThisPersonCannotSeeKeepTheirPlaceAfterAMove() {
        var layout = HomeLayout(order: [.family, .news, .health])
        layout.move([.family, .health], from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(layout.order, [.health, .family, .news])
    }

    func testUnknownTilesInStoredJSONAreDropped() {
        let layout = HomeLayout.decode(#"{"order":["family","teleport","health"],"hidden":["teleport","news"]}"#)
        XCTAssertEqual(layout.order, [.family, .health])
        XCTAssertEqual(layout.hidden, [.news])
    }

    func testGarbageIsTheDefaultLayout() {
        XCTAssertEqual(HomeLayout.decode("not json"), HomeLayout())
        XCTAssertEqual(HomeLayout.decode(""), HomeLayout())
    }

    // MARK: - Rows

    func testSquaresPairAndALoneSquareTakesTheRow() {
        let rows = HomeRows.pack([.family, .health, .steps, .trips, .tasks])
        XCTAssertEqual(rows, [.full(.family), .pair(.health, .steps), .full(.trips), .full(.tasks)])
    }

    func testASquareBeforeAWideTileIsNotLeftWithAHole() {
        XCTAssertEqual(HomeRows.pack([.health, .trips, .steps, .tasks]),
                       [.full(.health), .full(.trips), .pair(.steps, .tasks)])
    }

    func testAccessibilitySizesAreOneColumn() {
        XCTAssertEqual(HomeRows.pack([.health, .steps], folded: true), [.full(.health), .full(.steps)])
    }

    // MARK: - The header

    func testTheHeaderLineNamesOnePersonOut() throws {
        let view = try household()
        XCTAssertEqual(HomeHeader.line(view: view, tasksToDo: 2), "2 at home · Sam is out · 1 on the move · 2 tasks to do")
    }

    // MARK: - The Orbit

    func testDistanceAndBearing() {
        let london = GeoPoint(lat: 51.5074, lon: -0.1278)
        let cambridge = GeoPoint(lat: 52.2053, lon: 0.1218)
        XCTAssertEqual(FamilyOrbitMath.distanceKm(london, cambridge), 79.3, accuracy: 1)
        let bearing = FamilyOrbitMath.bearing(from: london, to: cambridge) * 180 / .pi
        XCTAssertEqual(bearing, 12, accuracy: 3, "Cambridge is a little east of north of London")
        XCTAssertEqual(FamilyOrbitMath.compass(bearing * .pi / 180), "north")
        XCTAssertEqual(FamilyOrbitMath.compass(.pi / 2), "east")
    }

    func testTheRadiusGrowsWithDistanceAndStaysInside() {
        let outer = 25.0
        let near = FamilyOrbitMath.radius(km: 0.5, maxKm: outer)
        let far = FamilyOrbitMath.radius(km: 20, maxKm: outer)
        XCTAssertGreaterThan(near, FamilyOrbitMath.inner)
        XCTAssertGreaterThan(far, near)
        XCTAssertLessThanOrEqual(FamilyOrbitMath.radius(km: 400, maxKm: outer), 1)
    }

    func testTheOuterRingIsARoundNumberPastTheFarthest() {
        XCTAssertEqual(FamilyOrbitMath.outerKm(farthest: 0), 5)
        XCTAssertEqual(FamilyOrbitMath.outerKm(farthest: 7), 10)
        XCTAssertEqual(FamilyOrbitMath.outerKm(farthest: 90), 250)
        XCTAssertEqual(FamilyOrbitMath.rings(outer: 25), [5, 10, 25])
    }

    func testNorthIsUpAndEastIsRight() {
        let placed = FamilyOrbitMath.place([
            .init(subject: "n", km: 10, bearing: 0, atHome: false),
            .init(subject: "e", km: 10, bearing: .pi / 2, atHome: false),
        ], outer: 25)
        let n = placed.first { $0.subject == "n" }!, e = placed.first { $0.subject == "e" }!
        XCTAssertLessThan(n.y, 0)
        XCTAssertEqual(n.x, 0, accuracy: 0.001)
        XCTAssertGreaterThan(e.x, 0)
        XCTAssertEqual(e.y, 0, accuracy: 0.001)
    }

    func testTwoPeopleInOnePlaceAreDrawnApart() {
        let placed = FamilyOrbitMath.place([
            .init(subject: "a", km: 3, bearing: 1, atHome: false),
            .init(subject: "b", km: 3, bearing: 1, atHome: false),
        ], outer: 10, separation: 0.2)
        let dx = placed[0].x - placed[1].x, dy = placed[0].y - placed[1].y
        XCTAssertGreaterThanOrEqual(sqrt(dx * dx + dy * dy), 0.19)
    }

    func testEveryoneAtHomeCirclesTheSun() {
        let placed = FamilyOrbitMath.place([
            .init(subject: "a", km: 0, bearing: 0, atHome: true),
            .init(subject: "b", km: 0, bearing: 0, atHome: true),
            .init(subject: "c", km: 0, bearing: 0, atHome: true),
        ], outer: 5)
        for spot in placed {
            XCTAssertEqual(sqrt(spot.x * spot.x + spot.y * spot.y), FamilyOrbitMath.inner * 0.72, accuracy: 0.001)
        }
        XCTAssertEqual(Set(placed.map { "\(Int(($0.x * 100).rounded())),\(Int(($0.y * 100).rounded()))" }).count, 3,
                       "three people at home are three planets, not one")
    }

    func testHomeIsTheWatchedPlaceFirstThenTheMedianOfThoseAtHome() throws {
        let view = try household()
        let watched = WatchedPlace(id: "h", label: "Home", lat: 1, lon: 2, radiusM: 150)
        XCTAssertEqual(FamilyOrbitMath.home(people: view.people, watch: [watched]), GeoPoint(lat: 1, lon: 2))
        let fromPeople = try XCTUnwrap(FamilyOrbitMath.home(people: view.people, watch: nil))
        XCTAssertEqual(fromPeople.lat, 54.776, accuracy: 0.001)
    }

    func testTheOrbitModelSaysWhereInWords() throws {
        let model = try XCTUnwrap(FamilyOrbitModel.make(view: household(), watch: nil))
        let sam = try XCTUnwrap(model.people.first { $0.subject == "sam" })
        XCTAssertFalse(sam.atHome)
        let words = model.spoken(sam)
        XCTAssertTrue(words.hasPrefix("Sam, "), words)
        XCTAssertTrue(words.contains("of home"), words)
        XCTAssertTrue(words.contains("walking"), words)
        XCTAssertFalse(words.contains("km/h"), "the Orbit never says how fast")
        XCTAssertEqual(model.missing, ["Pat"])
    }

    // MARK: - The Ribbons

    func testRibbonsBreakAtAGapAndKeepTheirDistances() {
        let home = GeoPoint(lat: 54.776, lon: -1.575)
        let start = 1_000_000.0
        let trail: [[Double]] = [
            [54.776, -1.575, start + 60], [54.786, -1.575, start + 120],
            // Twenty minutes of nothing: a new segment, never a line across it.
            [54.796, -1.575, start + 1320], [54.806, -1.575, start + 1380],
        ]
        let segments = FamilyRibbonMath.series(trail: trail, home: home, start: start)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0][0].km, 0, accuracy: 0.01)
        XCTAssertEqual(segments[1][1].km, 3.3, accuracy: 0.1)
        XCTAssertEqual(segments[1][1].t, 1380)
    }

    func testRibbonHeightIsSharedAndCapped() {
        XCTAssertEqual(FamilyRibbonMath.height(km: 0, maxKm: 10), 0)
        XCTAssertEqual(FamilyRibbonMath.height(km: 10, maxKm: 10), 1, accuracy: 0.0001)
        XCTAssertEqual(FamilyRibbonMath.height(km: 50, maxKm: 10), 1)
    }

    // MARK: - Colours

    func testPeopleKeepTheirColourWhenSomebodyElseLeaves() {
        let before = SR.PersonHue.assign(["alex", "kit", "sam"])
        let after = SR.PersonHue.assign(["alex", "sam", "zed"])
        XCTAssertEqual(before["alex"], after["alex"])
    }

    // MARK: - A small household

    private func household() throws -> HouseholdView {
        let json = """
        {"generatedAt":"2026-10-18T10:00:00Z","viewer":"owner","people":[
          {"subject":"you","name":"Alex Kelly","self":true,"status":"home","line":"Home · seen 1m ago","batteryPct":80,
           "lastSeenAt":"2026-10-18T09:59:00Z","position":{"lat":54.776,"lon":-1.575,"at":"2026-10-18T09:59:00Z"},"today":null},
          {"subject":"robin","name":"Robin","self":false,"status":"home","line":"Home · seen 2m ago","batteryPct":55,
           "lastSeenAt":"2026-10-18T09:58:00Z","position":{"lat":54.7762,"lon":-1.5751,"at":"2026-10-18T09:58:00Z"},"today":null},
          {"subject":"sam","name":"Sam","self":false,"status":"out","line":"At School · seen 3m ago","batteryPct":18,
           "lastSeenAt":"2026-10-18T09:57:00Z","position":{"lat":54.79,"lon":-1.55,"at":"2026-10-18T09:57:00Z"},
           "moving":{"mode":"walking","speedKmh":5,"since":"2026-10-18T09:50:00Z"},"today":null},
          {"subject":"pat","name":"Pat","self":false,"status":"off","line":"Not sharing","batteryPct":null,
           "lastSeenAt":null,"position":null,"today":null}
        ]}
        """
        return try JSONDecoder().decode(HouseholdView.self, from: Data(json.utf8))
    }
}

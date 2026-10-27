import XCTest
@testable import SRAppleApp

/// Home's rules: which tiles exist, the reader's order and switches, how the
/// rows pack — and the family pictures' geometry.
final class HomeTests: XCTestCase {

    // MARK: - Which tiles exist

    func testTheOwnerHasEveryTile() {
        XCTAssertEqual(HomeTileKind.available(access: .everything, sitePaired: true), HomeTileKind.defaultOrder)
    }

    func testTheBriefingLeadsAndTheFamilyFollows() {
        XCTAssertEqual(Array(HomeTileKind.defaultOrder.prefix(2)), [.briefing, .family])
    }

    func testTheShortcutsComeLast() {
        XCTAssertEqual(Array(HomeTileKind.defaultOrder.suffix(4)), [.captures, .travel, .chat, .wildmind])
        XCTAssertEqual(HomeTileKind.defaultOrder.filter { $0.size == .compact }, [.batPhone, .captures, .travel, .chat, .wildmind],
                       "the bat phone is the one shortcut kept at the top, under the family")
    }

    func testTheBatPhoneSitsUnderTheFamily() {
        XCTAssertEqual(Array(HomeTileKind.defaultOrder.prefix(4)), [.briefing, .family, .batPhone, .messages])
    }

    func testTilesThatCarryDataAreWide() {
        for kind in [HomeTileKind.briefing, .health, .steps, .news, .moves, .trips] {
            XCTAssertEqual(kind.size, .wide, "\(kind) needs a row of its own for its numbers")
        }
    }

    func testEveryTileIsInTheDefaultOrderOnce() {
        XCTAssertEqual(Set(HomeTileKind.defaultOrder), Set(HomeTileKind.allCases))
        XCTAssertEqual(HomeTileKind.defaultOrder.count, HomeTileKind.allCases.count)
    }

    func testAMemberWithFamilyAndGamesHasNoOwnerTiles() {
        let member = AppAccess(family: true, games: true)
        let tiles = HomeTileKind.available(access: member, sitePaired: true)
        XCTAssertTrue(tiles.contains(.family))
        XCTAssertTrue(tiles.contains(.steps), "family + site credential is the family boards")
        XCTAssertTrue(tiles.contains(.games))
        XCTAssertTrue(tiles.contains(.batPhone), "every family phone has the bat phone")
        for owner in [HomeTileKind.news, .daydream, .flows, .wildmind, .chat, .diary, .captures] {
            XCTAssertFalse(tiles.contains(owner), "\(owner) leaked to a member")
        }
    }

    func testNoSiteCredentialMeansNoBoards() {
        let tiles = HomeTileKind.available(access: AppAccess(family: true), sitePaired: false)
        XCTAssertEqual(tiles, [.briefing, .family, .health, .travel])
    }

    func testEveryoneHasHealth() {
        XCTAssertEqual(HomeTileKind.available(access: .nothing, sitePaired: false), [.briefing, .health, .travel],
                       "Health is at least this phone's own, and the Travel kit runs on the phone")
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

    func testSquaresPairAndALoneSquareStaysASquare() {
        let rows = HomeRows.pack([.family, .tasks, .backlog, .trips, .daydream])
        XCTAssertEqual(rows, [.full(.family), .pair(.tasks, .backlog), .full(.trips), .single(.daydream)])
    }

    func testASquarePairsAcrossAWideTile() {
        XCTAssertEqual(HomeRows.pack([.tasks, .trips, .daydream, .backlog]),
                       [.pair(.tasks, .daydream), .full(.trips), .single(.backlog)])
    }

    func testShortcutsPairWithShortcutsOrStackBesideASquare() {
        XCTAssertEqual(HomeRows.pack([.daydream, .chat, .wildmind, .tasks]),
                       [.pair(.daydream, .tasks), .pair(.chat, .wildmind)])
        XCTAssertEqual(HomeRows.pack([.tasks, .chat]), [.stack(.tasks, [.chat])],
                       "a shortcut beside a square is stacked in its height, never stretched to it")
    }

    func testTheReadersSizeIsWhatIsPacked() {
        XCTAssertEqual(HomeRows.pack([.health, .steps], sizes: [.health: .square, .steps: .square]), [.pair(.health, .steps)])
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

    // MARK: - The Orbit, turning with the phone

    func testARelativeBearingWrapsBothWays() {
        let degree = Double.pi / 180
        // Facing 350°, something at 10° is 20° to the right, not -340°.
        XCTAssertEqual(FamilyOrbitMath.relative(10 * degree, facing: 350 * degree), 20 * degree, accuracy: 1e-9)
        // Facing 10°, something at 350° is 340° round: just to the left.
        XCTAssertEqual(FamilyOrbitMath.relative(350 * degree, facing: 10 * degree), 340 * degree, accuracy: 1e-9)
        XCTAssertEqual(FamilyOrbitMath.relative(.pi, facing: .pi), 0, accuracy: 1e-9)
        // An unwrapped heading past a full turn still reads the same way.
        XCTAssertEqual(FamilyOrbitMath.relative(.pi / 2, facing: 2 * .pi + .pi / 2), 0, accuracy: 1e-9)
    }

    func testUnwrapTakesTheShortWayRound() {
        let degree = Double.pi / 180
        // 359° then 1°: two degrees on, not 358 back.
        XCTAssertEqual(FamilyOrbitMath.unwrap(1 * degree, after: 359 * degree), 361 * degree, accuracy: 1e-9)
        // And back again.
        XCTAssertEqual(FamilyOrbitMath.unwrap(359 * degree, after: 361 * degree), 359 * degree, accuracy: 1e-9)
        // Several turns in, a reading lands next to where the disc already is.
        XCTAssertEqual(FamilyOrbitMath.unwrap(5 * degree, after: 720 * degree + 3 * degree), 725 * degree, accuracy: 1e-9)
        XCTAssertEqual(FamilyOrbitMath.unwrap(90 * degree, after: 0), 90 * degree, accuracy: 1e-9)
    }

    func testRelativeDirectionInWords() {
        XCTAssertEqual(FamilyOrbitMath.relativeWords(0), "ahead")
        XCTAssertEqual(FamilyOrbitMath.relativeWords(.pi / 4), "ahead and to your right")
        XCTAssertEqual(FamilyOrbitMath.relativeWords(.pi / 2), "to your right")
        XCTAssertEqual(FamilyOrbitMath.relativeWords(.pi), "behind you")
        XCTAssertEqual(FamilyOrbitMath.relativeWords(3 * .pi / 2), "to your left")
        XCTAssertEqual(FamilyOrbitMath.relativeWords(2 * .pi - 0.01), "ahead", "just left of ahead is still ahead")
    }

    func testTheTurningOrbitIsCentredOnYou() throws {
        let view = try household()
        let model = try XCTUnwrap(FamilyOrbitModel.makeFacing(view: view, watch: nil))
        XCTAssertTrue(model.facing)
        XCTAssertFalse(model.centredOnHome)
        XCTAssertNil(model.people.first { $0.isSelf }, "you are the centre, not a planet")
        XCTAssertNil(model.home, "no home marker while you are at home")
        let you = GeoPoint(lat: 54.776, lon: -1.575)
        let sam = try XCTUnwrap(model.people.first { $0.subject == "sam" })
        XCTAssertEqual(sam.km, FamilyOrbitMath.distanceKm(you, GeoPoint(lat: 54.79, lon: -1.55)), accuracy: 1e-9)
        let robin = try XCTUnwrap(model.people.first { $0.subject == "robin" })
        XCTAssertTrue(robin.atHome, "at home with you")
        XCTAssertTrue(model.spoken(robin, heading: 0).hasPrefix("Robin, at home, battery 55%"), model.spoken(robin, heading: 0))
        // Sam is north-east of you: facing north-east, Sam is ahead; facing
        // south-west, behind you.
        let northEast = Double.pi / 4
        XCTAssertTrue(model.spoken(sam, heading: northEast).hasPrefix("Sam, \(FamilyOrbitMath.formatKm(sam.km)) ahead,"),
                      model.spoken(sam, heading: northEast))
        XCTAssertTrue(model.spoken(sam, heading: northEast + .pi).contains("behind you"))
        // No compass: the turning model still says where, by the compass.
        XCTAssertTrue(model.spoken(sam, heading: nil).contains("north-east of you"), model.spoken(sam, heading: nil))
        XCTAssertEqual(model.missing, ["Pat"])
    }

    func testTheTurningOrbitNeedsAFixForYou() throws {
        let view = try household(selfPosition: false)
        XCTAssertNil(FamilyOrbitModel.makeFacing(view: view, watch: nil), "no fix, no centre: the tab shows home instead")
        let device = GeoPoint(lat: 54.776, lon: -1.575)
        XCTAssertNotNil(FamilyOrbitModel.makeFacing(view: view, watch: nil, device: device), "the phone's own last fix will do")
    }

    func testAFixYouStoppedSharingIsNotACentre() throws {
        // Sharing off: the household still carries where you were when it
        // stopped, and a picture centred there would be centred on the past.
        let view = try household(selfStatus: "off")
        XCTAssertNil(FamilyOrbitModel.makeFacing(view: view, watch: nil))
        let device = GeoPoint(lat: 54.70, lon: -1.575)
        let model = try XCTUnwrap(FamilyOrbitModel.makeFacing(view: view, watch: nil, device: device))
        let sam = try XCTUnwrap(model.people.first { $0.subject == "sam" })
        XCTAssertEqual(sam.km, FamilyOrbitMath.distanceKm(device, GeoPoint(lat: 54.79, lon: -1.55)), accuracy: 1e-9)
    }

    func testTheNewerOfYourTwoFixesIsTheCentre() throws {
        let view = try household() // your household fix is from 09:59:00Z
        let device = GeoPoint(lat: 54.70, lon: -1.575)
        let sam = GeoPoint(lat: 54.79, lon: -1.55)
        let iso = ISO8601DateFormatter()
        func samKm(_ at: String?) throws -> Double {
            let model = try XCTUnwrap(FamilyOrbitModel.makeFacing(view: view, watch: nil, device: device,
                                                                  deviceAt: at.flatMap { iso.date(from: $0) }))
            return try XCTUnwrap(model.people.first { $0.subject == "sam" }).km
        }
        let yours = GeoPoint(lat: 54.776, lon: -1.575)
        XCTAssertEqual(try samKm("2026-10-18T10:05:00Z"), FamilyOrbitMath.distanceKm(device, sam), accuracy: 1e-9, "the phone's newer fix wins")
        XCTAssertEqual(try samKm("2026-10-18T09:00:00Z"), FamilyOrbitMath.distanceKm(yours, sam), accuracy: 1e-9, "an older one does not")
        XCTAssertEqual(try samKm(nil), FamilyOrbitMath.distanceKm(yours, sam), accuracy: 1e-9, "an undated one is a fallback only")
    }

    func testAwayFromHomeHomeIsAMarker() throws {
        // Home is ~8 km due south of where you are.
        let watched = WatchedPlace(id: "h", label: "Home", lat: 54.70, lon: -1.575, radiusM: 150)
        let model = try XCTUnwrap(FamilyOrbitModel.makeFacing(view: household(), watch: [watched]))
        XCTAssertFalse(model.youAreHome, "the site's 'home' does not outweigh a fix 8 km away")
        let home = try XCTUnwrap(model.home)
        XCTAssertEqual(home.km, 8.45, accuracy: 0.1)
        XCTAssertEqual(home.bearing, .pi, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(model.outer, home.km, "the rings hold home too")
        // Drawn below the centre, north up, and spaced apart with everyone else.
        let placed = FamilyOrbitMath.place(model.bodies, outer: model.outer)
        let spot = try XCTUnwrap(placed.first { $0.subject == FamilyOrbitModel.homeSubject })
        XCTAssertGreaterThan(spot.y, 0)
        XCTAssertEqual(spot.x, 0, accuracy: 0.05)
        // Facing south, home is ahead.
        XCTAssertEqual(model.spokenHome(heading: .pi), "Home, 8.5 km ahead")
        // Robin, beside you but away from home, is with you.
        let robin = try XCTUnwrap(model.people.first { $0.subject == "robin" })
        XCTAssertTrue(robin.atHome)
        XCTAssertTrue(model.spoken(robin, heading: 0).hasPrefix("Robin, with you"), model.spoken(robin, heading: 0))
    }

    func testHomeTileOrbitIsUnchangedByTurning() throws {
        let model = try XCTUnwrap(FamilyOrbitModel.make(view: household(), watch: nil))
        XCTAssertFalse(model.facing)
        XCTAssertNil(model.home)
        XCTAssertEqual(model.bodies.count, model.people.count)
        let sam = try XCTUnwrap(model.people.first { $0.subject == "sam" })
        XCTAssertEqual(model.spoken(sam, heading: 1), model.spoken(sam), "a heading never changes Home's words")
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

    private func household(selfPosition: Bool = true, selfStatus: String = "home") throws -> HouseholdView {
        let you = selfPosition ? #"{"lat":54.776,"lon":-1.575,"at":"2026-10-18T09:59:00Z"}"# : "null"
        let json = """
        {"generatedAt":"2026-10-18T10:00:00Z","viewer":"owner","people":[
          {"subject":"you","name":"Alex Kelly","self":true,"status":"\(selfStatus)","line":"Home · seen 1m ago","batteryPct":80,
           "lastSeenAt":"2026-10-18T09:59:00Z","position":\(you),"today":null},
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

    /// The bat phone: hidden or not, it is on Home. msg family can go now
    /// the bat phone has a tile of its own.
    func testTheBatPhoneCannotBeHidden() {
        var layout = HomeLayout(hidden: [.batPhone, .news])
        let available = HomeTileKind.available(access: .everything, sitePaired: true)
        XCTAssertTrue(layout.visible(available).contains(.batPhone))
        XCTAssertFalse(layout.visible(available).contains(.news))
        layout.set(.batPhone, shown: false)
        XCTAssertTrue(layout.shows(.batPhone))
        layout.set(.messages, shown: false)
        XCTAssertFalse(layout.shows(.messages))
    }

    // MARK: - Arrange

    func testASizeIsKeptAndTheDefaultForgotten() {
        var layout = HomeLayout()
        layout.set(.steps, size: .square)
        XCTAssertEqual(layout.size(of: .steps), .square)
        XCTAssertEqual(HomeLayout.decode(layout.raw).size(of: .steps), .square)
        layout.set(.steps, size: .wide)
        XCTAssertNil(layout.sizes[.steps], "the default is not stored")
        layout.set(.family, size: .square)
        XCTAssertEqual(layout.size(of: .family), .hero, "the Orbit has one size")
    }

    func testAnUnknownSizeInStoredJSONIsDropped() {
        let layout = HomeLayout.decode(#"{"order":[],"hidden":[],"sizes":{"steps":"square","news":"huge","teleport":"wide"}}"#)
        XCTAssertEqual(layout.sizes, [.steps: .square])
    }

    func testALayoutFromBeforeSizesStillReads() {
        let layout = HomeLayout.decode(#"{"order":["health","family"],"hidden":["news"]}"#)
        XCTAssertEqual(layout.order, [.health, .family])
        XCTAssertTrue(layout.sizes.isEmpty)
    }

    func testDroppedOnATileTakesItsPlace() {
        let available: [HomeTileKind] = [.family, .health, .steps, .tasks]
        var layout = HomeLayout()
        layout.move(.tasks, before: .health, available: available)
        XCTAssertEqual(layout.arranged(available), [.family, .tasks, .health, .steps])
        layout.move(.family, before: .steps, available: available)
        XCTAssertEqual(layout.arranged(available), [.tasks, .health, .steps, .family], "dragged down, it lands after")
    }

    func testNudgeStepsOverHiddenTiles() {
        let available: [HomeTileKind] = [.family, .health, .steps]
        var layout = HomeLayout(hidden: [.health])
        layout.nudge(.steps, by: -1, available: available)
        XCTAssertEqual(layout.visible(available), [.steps, .family])
        layout.nudge(.steps, by: -1, available: available)
        XCTAssertEqual(layout.visible(available), [.steps, .family], "already first")
    }

    func testAddableIsWhatIsOff() {
        let available: [HomeTileKind] = [.family, .health, .steps]
        XCTAssertEqual(HomeLayout(hidden: [.steps]).addable(available), [.steps])
    }

    func testEveryTileCanBeDrawnAtItsDefault() {
        for kind in HomeTileKind.allCases {
            XCTAssertTrue(kind.sizes.contains(kind.defaultSize), "\(kind)")
            XCTAssertEqual(kind.sizes, kind.sizes.sorted(), "\(kind)'s sizes go smallest first")
        }
    }

    func testWhatWaitsOpensOut() {
        for kind in [HomeTileKind.games, .flows, .diary, .trips, .moves] {
            XCTAssertTrue(kind.adaptive, "\(kind) should fold when empty")
            XCTAssertEqual(kind.defaultSize, .wide, "\(kind) starts wide, to fold when there is nothing")
        }
    }

    func testAdaptiveTilesCanFold() {
        for kind in HomeTileKind.allCases where kind.adaptive {
            XCTAssertTrue(kind.sizes.contains(.square), "\(kind) has no square to fold to")
        }
    }
}

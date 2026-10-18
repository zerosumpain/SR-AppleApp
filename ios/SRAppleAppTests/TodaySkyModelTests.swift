import XCTest
@testable import SRAppleApp

/// Today's sky: where along the horizon a time sits, how high the sun
/// stands, which layers the sky is made of, where it is worked out for, and
/// what is on the line under it.
///
/// Foundation only, like the model: the Linux harness runs these too.
final class TodaySkyModelTests: XCTestCase {

    /// Everything in UTC, so local minutes are the instant's own.
    private let utc = TimeZone(secondsFromGMT: 0)!
    /// 2026-10-17 00:00 UTC.
    private let midnight = Date(timeIntervalSince1970: 1_792_195_200)

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        midnight.addingTimeInterval(Double(hour * 60 + minute) * 60)
    }

    /// Sunrise 07:00, golden hour from 17:20, sunset 18:00.
    private let sun = TripSun.Day(sunriseMin: 420, sunsetMin: 1080, goldenMin: 1040)

    private func near(_ a: SkyLayers, _ b: SkyLayers, file: StaticString = #filePath, line: UInt = #line) {
        for (x, y) in [(a.petrol, b.petrol), (a.ink, b.ink), (a.deep, b.deep), (a.accent, b.accent), (a.warm, b.warm)] {
            XCTAssertEqual(x, y, accuracy: 0.000_001, file: file, line: line)
        }
    }

    // MARK: - Along the horizon

    func testFracRunsFromFiveInTheMorningToElevenAtNight() {
        XCTAssertEqual(TodayHeroModel.frac(at(5), zone: utc), 0, accuracy: 0.000_001)
        XCTAssertEqual(TodayHeroModel.frac(at(14), zone: utc), 0.5, accuracy: 0.000_001)
        // Past 23:00 the sun parks at the end of the line.
        XCTAssertEqual(TodayHeroModel.frac(at(23, 30), zone: utc), 1, accuracy: 0.000_001)
        XCTAssertEqual(TodayHeroModel.frac(at(3), zone: utc), 0, accuracy: 0.000_001)
    }

    func testAPointAlongTheHorizonNamesThatTimeToday() {
        let date = TodayHeroModel.date(forFrac: 0.5, on: at(9, 12), zone: utc)
        XCTAssertEqual(date.timeIntervalSince(midnight), 14 * 3600, accuracy: 0.5)
    }

    // MARK: - The sun's height

    func testTheSunIsDownBeforeSunriseAndHighestHalfwayThroughTheDay() {
        XCTAssertEqual(TodaySky.lift(minute: 400, sun: sun), 0, accuracy: 0.000_001)
        XCTAssertEqual(TodaySky.lift(minute: 750, sun: sun), 1, accuracy: 0.000_001)
        XCTAssertEqual(TodaySky.lift(minute: 1200, sun: sun), 0, accuracy: 0.000_001)
        XCTAssertEqual(TodaySky.lift(minute: 750, sun: nil), 0)
    }

    // MARK: - The layers

    func testEachKeyframeIsItsAnchorRowExactly() {
        // M, the evening's golden stretch, is 40 minutes.
        near(TodaySky.layers(minute: 380, sun: sun), .night)     // R − 40
        near(TodaySky.layers(minute: 420, sun: sun), .twilight)  // R
        near(TodaySky.layers(minute: 445, sun: sun), .golden)    // R + 25
        near(TodaySky.layers(minute: 490, sun: sun), .day)       // R + M + 30
        near(TodaySky.layers(minute: 1010, sun: sun), .day)      // G − 30
        near(TodaySky.layers(minute: 1065, sun: sun), .golden)   // S − 15
        near(TodaySky.layers(minute: 1090, sun: sun), .twilight) // S + 10
        near(TodaySky.layers(minute: 1125, sun: sun), .night)    // S + 45
    }

    func testBetweenKeyframesTheLayersRunInAStraightLine() {
        near(TodaySky.layers(minute: 400, sun: sun), SkyLayers.mix(.night, .twilight, 0.5))
        near(TodaySky.layers(minute: 120, sun: sun), .night)
        near(TodaySky.layers(minute: 1400, sun: sun), .night)
        near(TodaySky.layers(minute: 750, sun: sun), .day)
    }

    func testPolarDayOrNightIsTheDayRowThroughout() {
        let polar = TripSun.Day(sunriseMin: nil, sunsetMin: nil, goldenMin: nil)
        for minute in [0.0, 300, 720, 1100, 1439] {
            near(TodaySky.layers(minute: minute, sun: polar), .day)
        }
        near(TodaySky.layers(minute: 720, sun: nil), .day)
        XCTAssertEqual(TodaySky.lift(minute: 720, sun: polar), 0)
    }

    // MARK: - Where the sky is for

    func testARunningTripBeatsThePhonesOwnFix() {
        let rome = TripLatLng(lat: 41.9, lng: 12.5)
        let place = TodaySky.place(selfFix: (lat: 54.97, lon: -1.61), trip: rome, zone: utc, at: at(12))
        XCTAssertEqual(place.place, rome)
        XCTAssertTrue(place.isFix)
    }

    func testATripOnAnotherClockDoesNotTakeTheSkyYet() {
        // The morning of the flight: the phone is still on home time.
        let rome = TripLatLng(lat: 41.9, lng: 12.5)
        let place = TodaySky.place(selfFix: (lat: 54.97, lon: -1.61), trip: rome,
                                   tripZone: TimeZone(secondsFromGMT: 7200)!, zone: utc, at: at(7))
        XCTAssertEqual(place.place, TripLatLng(lat: 54.97, lng: -1.61))
        XCTAssertTrue(place.isFix)
    }

    func testAFixFarFromTheZonesMeridianKeepsOnlyItsLatitude() {
        // A fix from New York on a phone set to UTC: the longitude would put
        // sunset five hours late.
        let place = TodaySky.place(selfFix: (lat: 40.77, lon: -73.97), trip: nil, zone: utc, at: at(12))
        XCTAssertEqual(place.place.lat, 40.77, accuracy: 0.000_001)
        XCTAssertEqual(place.place.lng, 0, accuracy: 0.000_001)
        XCTAssertFalse(place.isFix)
    }

    func testAPlausibleFixIsUsedWhole() {
        let tokyo = TimeZone(secondsFromGMT: 9 * 3600)!
        let place = TodaySky.place(selfFix: (lat: 35.68, lon: 139.69), trip: nil, zone: tokyo, at: at(12))
        XCTAssertEqual(place.place, TripLatLng(lat: 35.68, lng: 139.69))
        XCTAssertTrue(place.isFix)
    }

    func testAcrossTheDateLineTheFixIsStillPlausible() {
        let auckland = TimeZone(secondsFromGMT: 12 * 3600)!
        let place = TodaySky.place(selfFix: (lat: -36.85, lon: -179.5), trip: nil, zone: auckland, at: at(12))
        XCTAssertTrue(place.isFix)
    }

    func testWithNoFixTheSkyIsLondonsLatitudeOnTheZonesMeridian() {
        let paris = TimeZone(secondsFromGMT: 3600)!
        let place = TodaySky.place(selfFix: nil, trip: nil, zone: paris, at: at(12))
        XCTAssertEqual(place.place, TripLatLng(lat: 51.5, lng: 15))
        XCTAssertFalse(place.isFix)
    }

    // MARK: - On the horizon

    private func person(_ subject: String, _ firstOut: String?, out: Bool = true, isSelf: Bool = false) -> TodayHeroInput.Person {
        TodayHeroInput.Person(subject: subject, name: subject.capitalized, initials: String(subject.prefix(2)).capitalized,
                              isSelf: isSelf, firstOut: firstOut, out: out)
    }

    private func input(
        now: Date,
        people: [TodayHeroInput.Person] = [],
        trip: TodayHeroInput.TripDay? = nil,
        isFix: Bool = false
    ) -> TodayHeroInput {
        TodayHeroInput(now: now, zone: utc, place: TripLatLng(lat: 51.5, lng: 0), placeIsFix: isFix,
                       people: people, trip: trip)
    }

    func testAFirstOutStillToComeIsNotOnTheLine() {
        let model = TodayHeroModel.make(input(now: at(10, 40), people: [person("sam", "07:48"), person("kit", "11:15")]))
        XCTAssertEqual(model.markers.map(\.id), ["person-sam"])
        XCTAssertEqual(model.markers.first?.spoken, "Sam went out at 07:48")
        XCTAssertEqual(model.markers.first?.short, "Sam out")
        XCTAssertEqual(model.markers.first?.target, .family)
    }

    func testYouAreSaidAsYou() {
        let model = TodayHeroModel.make(input(now: at(10, 40), people: [person("alex", "08:12", isSelf: true)]))
        XCTAssertEqual(model.markers.first?.spoken, "You went out at 08:12")
    }

    func testAtMostFourPeopleTheEarliestFirst() {
        let people = [("a", "09:30"), ("b", "07:10"), ("c", "08:00"), ("d", "06:45"), ("e", "10:05"), ("f", "08:30")]
            .map { person($0.0, $0.1) }
        let model = TodayHeroModel.make(input(now: at(11), people: people))
        XCTAssertEqual(model.markers.map(\.id), ["person-d", "person-b", "person-c", "person-f"])
    }

    func testWhoIsBackHomeIsDrawnAsBack() {
        let model = TodayHeroModel.make(input(now: at(11), people: [person("robin", "08:00", out: false)]))
        XCTAssertEqual(model.markers.first?.kind, .person(initials: "Ro", out: false, subject: "robin"))
    }

    private func stop(_ id: String, _ hour: Int, _ minute: Int = 0, done: Bool = false, here: Bool = false) -> TodayHeroInput.Stop {
        TodayHeroInput.Stop(id: id, title: id.capitalized, at: at(hour, minute), done: done, here: here)
    }

    func testStopsCarryDoneAndHereFromThePlan() {
        let trip = TodayHeroInput.TripDay(tripId: "rome", date: "2026-10-17", stops: [
            stop("pantheon", 10, done: true), stop("trevi", 12, 30, here: true), stop("steps", 14),
        ])
        let model = TodayHeroModel.make(input(now: at(12), trip: trip))
        XCTAssertEqual(model.markers.map(\.kind), [.stop(done: true, here: false), .stop(done: false, here: true), .stop(done: false, here: false)])
        XCTAssertEqual(model.markers[0].spoken, "Pantheon, done")
        XCTAssertEqual(model.markers[1].spoken, "Trevi at 12:30")
        XCTAssertEqual(model.markers[1].target, .tripDay(tripId: "rome", date: "2026-10-17"))
    }

    func testAtMostSixStopsTheNearestNowAndOnlyInsideTheWindow() {
        let hours = [4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 23]
        let trip = TodayHeroInput.TripDay(tripId: "rome", date: "2026-10-17",
                                          stops: hours.map { stop("s\($0)", $0, $0 == 23 ? 30 : 0) })
        let model = TodayHeroModel.make(input(now: at(12, 10), trip: trip))
        // 04:00 and 23:30 are off the line; of the rest, the six nearest 12:10.
        XCTAssertEqual(model.markers.map(\.id), ["stop-s10", "stop-s11", "stop-s12", "stop-s13", "stop-s14", "stop-s15"])
    }

    func testSunriseAndSunsetOnlyFromARealPlace() {
        let guessed = TodayHeroModel.make(input(now: at(12), isFix: false))
        XCTAssertFalse(guessed.markers.contains { $0.kind == .sunrise || $0.kind == .sunset })

        let fixed = TodayHeroModel.make(input(now: at(12), isFix: true))
        XCTAssertEqual(fixed.markers.filter { $0.kind == .sunrise || $0.kind == .sunset }.map(\.id), ["sunrise", "sunset"])
        XCTAssertTrue(fixed.markers.first { $0.id == "sunrise" }?.spoken.hasPrefix("Sunrise ") ?? false)
        XCTAssertNotNil(fixed.sun?.sunriseMin)
    }

    func testMarkerIdsHoldFromOneMinuteToTheNext() {
        let trip = TodayHeroInput.TripDay(tripId: "rome", date: "2026-10-17", stops: [stop("trevi", 12, 30)])
        let people = [person("sam", "07:48")]
        let a = TodayHeroModel.make(input(now: at(10, 40), people: people, trip: trip, isFix: true))
        let b = TodayHeroModel.make(input(now: at(10, 41), people: people, trip: trip, isFix: true))
        XCTAssertEqual(a.markers.map(\.id), b.markers.map(\.id))
        XCTAssertEqual(a.minuteKey, 640)
        XCTAssertEqual(b.minuteKey, 641)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - The days the clocks change

    private let london = TimeZone(identifier: "Europe/London")!

    /// An instant as hours and minutes UTC after a UTC midnight.
    private func utcAt(_ midnight: TimeInterval, _ hour: Int, _ minute: Int = 0) -> Date {
        Date(timeIntervalSince1970: midnight + Double(hour * 3600 + minute * 60))
    }

    func testTheDayTheClocksGoBackIsReadByTheWallClock() {
        // 2026-10-25: BST until 02:00, GMT after, so the day is 25 hours
        // long and 10:40 GMT is 700 minutes after local midnight.
        let day = 1_792_886_400.0
        let now = utcAt(day, 10, 40)
        let trip = TodayHeroInput.TripDay(tripId: "rome", date: "2026-10-25", stops: [
            TodayHeroInput.Stop(id: "trevi", title: "Trevi", at: utcAt(day, 12, 30), done: false, here: false),
        ])
        let model = TodayHeroModel.make(TodayHeroInput(
            now: now, zone: london, place: TripLatLng(lat: 51.5, lng: 0), placeIsFix: true,
            people: [person("sam", "08:12")], trip: trip
        ))
        XCTAssertEqual(model.minuteKey, 640)
        XCTAssertEqual(model.nowFrac, (640 - 300) / 1080, accuracy: 0.000_001)
        XCTAssertEqual(model.markers.first { $0.id == "person-sam" }?.at, utcAt(day, 8, 12))
        XCTAssertEqual(model.markers.first { $0.id == "person-sam" }?.spoken, "Sam went out at 08:12")
        XCTAssertEqual(model.markers.first { $0.id == "stop-trevi" }?.spoken, "Trevi at 12:30")
        XCTAssertEqual(TodayHeroModel.instant("2026-10-25", minutes: 750, zone: london), utcAt(day, 12, 30))
        // Sunrise on the line where the clock puts it, not an hour out.
        if let rise = model.sun?.sunriseMin, let marker = model.markers.first(where: { $0.id == "sunrise" }) {
            XCTAssertEqual(TodayHeroModel.frac(marker.at, zone: london), (rise - 300) / 1080, accuracy: 0.001)
        } else {
            XCTFail("no sunrise on the line")
        }
    }

    func testTheDayTheClocksGoForwardKeepsWhoWentOut() {
        // 2027-03-28: GMT until 01:00, BST after. At 08:30 BST somebody out
        // at 08:12 has been out for eighteen minutes, not "still to come".
        let day = 1_806_192_000.0
        let now = utcAt(day, 7, 30)
        let model = TodayHeroModel.make(TodayHeroInput(
            now: now, zone: london, place: TripLatLng(lat: 51.5, lng: 0), placeIsFix: false,
            people: [person("sam", "08:12")], trip: nil
        ))
        XCTAssertEqual(model.minuteKey, 510)
        XCTAssertEqual(model.markers.map(\.id), ["person-sam"])
        XCTAssertEqual(model.markers.first?.at, utcAt(day, 7, 12))
        XCTAssertEqual(TodayHeroModel.date(forFrac: 0.5, on: now, zone: london), utcAt(day, 13))
    }

    func testTheModelIsTheSameForTheSameMinute() {
        let a = TodayHeroModel.make(input(now: at(10, 40)))
        let b = TodayHeroModel.make(input(now: at(10, 40)))
        XCTAssertEqual(a, b)
    }
}

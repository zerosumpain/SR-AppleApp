import XCTest
@testable import SRAppleApp

/// Home's family board (`Home/HomeFamilyBoardModel.swift`): who is where, since
/// when, who is on the way, and the shape of the day. Linux-run.
final class HomeFamilyBoardTests: XCTestCase {
    private let home = (lat: 54.52, lon: -1.55)
    private let school = (lat: 54.53, lon: -1.52)
    private let clock: (Double) -> String = { t in
        let m = Int(t.truncatingRemainder(dividingBy: 86_400)) / 60
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
    /// 06:00 and 09:00 on day 0 (UTC clock in these tests).
    private let six = 6.0 * 3600, nine = 9.0 * 3600

    /// Home until 08:20, walks 08:20–08:40, at school since 08:41.
    private var schoolRun: [[Double]] {
        var t: [[Double]] = []
        for s in stride(from: six, through: 8 * 3600 + 20 * 60, by: 600) { t.append([home.lat, home.lon, s]) }
        for k in 1...4 {
            let f = Double(k) / 5
            t.append([home.lat + (school.lat - home.lat) * f, home.lon + (school.lon - home.lon) * f, 8 * 3600 + 20 * 60 + Double(k) * 240])
        }
        for s in stride(from: 8 * 3600 + 41 * 60, through: nine - 60, by: 300) { t.append([school.lat, school.lon, s]) }
        return t
    }

    private func person(_ subject: String, _ extra: (inout FamilyBoardInput.Person) -> Void = { _ in }) -> FamilyBoardInput.Person {
        var p = FamilyBoardInput.Person(subject: subject, name: subject.capitalized, isSelf: false, status: "out", place: "School")
        extra(&p)
        return p
    }

    func testSaysWhereAndSinceWhenFromTodaysTrail() throws {
        let rory = person("rory") { $0.lat = self.school.lat; $0.lon = self.school.lon; $0.trail = self.schoolRun; $0.lastSeen = self.nine - 60 }
        let input = FamilyBoardInput(people: [rory], home: home, dayStart: six, now: nine)
        let row = try XCTUnwrap(FamilyBoard.rows(input, clock: clock).first)
        XCTAssertEqual(row.headline, "At School")
        XCTAssertEqual(row.since, "since 08:41")
        XCTAssertEqual(row.spoken, "Rory, at School since 08:41.")
    }

    func testTheStripShowsHomeThenTheWalkThenAway() throws {
        let bands = FamilyBoard.bands(trail: schoolRun, home: home, from: six, to: nine, bins: 18)
        // 10-minute slices: 06:00–08:20 home (14), the walk, then school.
        XCTAssertEqual(Array(bands.prefix(14)), Array(repeating: .home, count: 14))
        XCTAssertTrue(bands[14...15].contains(.moving), "the walk to school: \(bands)")
        XCTAssertEqual(bands.last, .away)
        XCTAssertFalse(bands.contains(.none))
    }

    func testAGapInTheTrailIsNoFixNotMoreOfTheSame() {
        let trail: [[Double]] = [[home.lat, home.lon, six], [home.lat, home.lon, six + 600]]
        let bands = FamilyBoard.bands(trail: trail, home: home, from: six, to: nine, bins: 18)
        XCTAssertEqual(bands.first, .home)
        XCTAssertEqual(bands.last, FamilyBand.none)
    }

    func testAMoverLeadsWithTheirJourneyAndETA() throws {
        let you = person("john") { $0.isSelf = true; $0.status = "home"; $0.place = "Home" }
        let sam = person("sam") {
            $0.place = nil
            $0.movingMode = "walking"; $0.movingSince = self.nine - 12 * 60; $0.near = "Station Road"
            $0.journey = .init(to: "School", leftAt: self.nine - 12 * 60, arriveFrom: self.nine + 6 * 60, arriveTo: self.nine + 10 * 60)
        }
        let off = person("kit") { $0.status = "off" }
        let rows = FamilyBoard.rows(FamilyBoardInput(people: [off, you, sam], home: home, dayStart: six, now: nine), clock: clock)
        XCTAssertEqual(rows.map(\.subject), ["sam", "john", "kit"], "movers, then you, then not sharing")
        let mover = rows[0]
        XCTAssertEqual(mover.headline, "Walking near Station Road")
        XCTAssertEqual(mover.since, "for 12 min")
        XCTAssertEqual(mover.journey?.to, "School")
        XCTAssertEqual(mover.journey?.eta, "09:06–09:10")
        XCTAssertEqual(try XCTUnwrap(mover.journey?.progress), 0.6, accuracy: 0.01)
        XCTAssertEqual(rows[2].headline, "Not sharing")
        XCTAssertNil(rows[2].battery)
    }

    func testStaleAndLowBatteryAreFlaggedAndSaidHowLongAgo() throws {
        let kit = person("kit") { $0.status = "unknown"; $0.lastSeen = self.nine - 3 * 3600; $0.battery = 9 }
        let row = try XCTUnwrap(FamilyBoard.rows(FamilyBoardInput(people: [kit], dayStart: six, now: nine), clock: clock).first)
        XCTAssertEqual(row.headline, "Last at School")
        XCTAssertEqual(row.since, "seen 3h 00m ago")
        XCTAssertTrue(row.stale)
        XCTAssertTrue(row.lowBattery)
    }

    func testAllDayWhenEveryFixTodayIsHere() throws {
        let trail: [[Double]] = stride(from: six, through: nine, by: 900).map { [home.lat, home.lon, $0] }
        let arrived = try XCTUnwrap(FamilyBoard.arrivedAt(trail: trail, lat: home.lat, lon: home.lon))
        XCTAssertTrue(arrived.wholeTrail)
        XCTAssertNil(FamilyBoard.arrivedAt(trail: trail, lat: school.lat, lon: school.lon), "the trail is behind the pin")
    }
}

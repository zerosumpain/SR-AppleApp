import XCTest
@testable import SRAppleApp

/// Tilt Maze's clock as it is shown and read aloud.
final class TiltMazeFormatTests: XCTestCase {
    func testShortTimesShowTenths() {
        XCTAssertEqual(TiltMazeFormat.time(0), "0.0")
        XCTAssertEqual(TiltMazeFormat.time(9.44), "9.4")
        XCTAssertEqual(TiltMazeFormat.time(9.46), "9.5")
        XCTAssertEqual(TiltMazeFormat.time(-3), "0.0")
        XCTAssertEqual(TiltMazeFormat.time(.nan), "0.0")
    }

    func testAMinuteRollsOverCleanly() {
        XCTAssertEqual(TiltMazeFormat.time(59.94), "59.9")
        XCTAssertEqual(TiltMazeFormat.time(59.97), "1:00.0")
        XCTAssertEqual(TiltMazeFormat.time(62.5), "1:02.5")
        XCTAssertEqual(TiltMazeFormat.time(119.98), "2:00.0")
    }

    func testSpokenTimes() {
        XCTAssertEqual(TiltMazeFormat.spoken(9.4), "9.4 seconds")
        XCTAssertEqual(TiltMazeFormat.spoken(60), "1 minute")
        XCTAssertEqual(TiltMazeFormat.spoken(61.2), "1 minute 1 second")
        XCTAssertEqual(TiltMazeFormat.spoken(125), "2 minutes 5 seconds")
    }
}

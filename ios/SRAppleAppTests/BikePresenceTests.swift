import XCTest
@testable import SRAppleApp

/// The e-bike mark: what it looks for, what it remembers, and that a phone with
/// no bike uploads exactly what it did before.
@MainActor
final class BikePresenceTests: XCTestCase {

    private func defaults() -> UserDefaults {
        let name = "bike-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    func testStandardServicesAloneWhenNothingIsTyped() {
        XCTAssertEqual(BikePresence.services(extra: nil), ["180A", "180F"])
        XCTAssertEqual(BikePresence.services(extra: "   "), ["180A", "180F"])
    }

    func testATypedServiceIsAddedOnceAndUppercased() {
        XCTAssertEqual(BikePresence.services(extra: " fff0 "), ["180A", "180F", "FFF0"])
        XCTAssertEqual(BikePresence.services(extra: "180f"), ["180A", "180F"], "a standard service must not be listed twice")
        let long = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
        XCTAssertEqual(BikePresence.services(extra: long.lowercased()), ["180A", "180F", long])
    }

    func testGarbageIsRefusedRatherThanHandedToCoreBluetooth() {
        // CBUUID(string:) traps on these; the screen's text field can produce any of them.
        for text in ["", "18", "180G", "not-a-uuid", "6E400001-B5A3"] {
            XCTAssertNil(BikePresence.uuid(text), text)
        }
        XCTAssertEqual(BikePresence.services(extra: "zzzz"), ["180A", "180F"])
    }

    func testTheBikeIsRememberedAndForgotten() {
        let d = defaults()
        let id = UUID()
        let first = BikePresence(defaults: d)
        XCTAssertNil(first.bike)
        first.choose(.init(id: id, name: "Avinox"), extra: "FFF0")
        let reopened = BikePresence(defaults: d)
        XCTAssertEqual(reopened.bike, .init(id: id, name: "Avinox", services: ["180A", "180F", "FFF0"]))
        reopened.forget()
        XCTAssertNil(BikePresence(defaults: d).bike)
    }

    func testNoBikeMeansNoStatement() {
        // Never false: the field is absent unless it is a yes.
        XCTAssertNil(BikePresence(defaults: defaults()).connectedNow())
    }

    func testAFixWithoutTheBikeEncodesNoBikeKey() throws {
        let fix = LocationRecord(recorded: "2026-10-09T10:00:00Z", latitude: 54.5, longitude: -1.5, accuracy: 5, speed: 6, moving: true)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fix)) as? [String: Any]
        XCTAssertNil(json?["bike"], "an old server's exactKeys would refuse the whole batch")
        var onBike = fix
        onBike.bike = true
        let marked = try JSONSerialization.jsonObject(with: JSONEncoder().encode(onBike)) as? [String: Any]
        XCTAssertEqual(marked?["bike"] as? Bool, true)
    }

    func testAQueuedFixFromBeforeTheBikeStillDecodes() throws {
        let old = #"{"id":"a","recorded":"2026-10-09T10:00:00Z","latitude":54.5,"longitude":-1.5,"accuracy":5,"speed":1,"moving":true,"battery":80}"#
        let fix = try JSONDecoder().decode(LocationRecord.self, from: Data(old.utf8))
        XCTAssertNil(fix.bike)
    }
}

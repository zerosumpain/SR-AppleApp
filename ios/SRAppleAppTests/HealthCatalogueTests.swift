import XCTest
@testable import SRAppleApp

final class HealthCatalogueTests: XCTestCase {
    func testTheCatalogueIsBundledAndHasNineGroups() {
        XCTAssertEqual(Set(HealthCatalogue.file.groups.keys), Set(HealthCatalogue.groupOrder))
        XCTAssertEqual(HealthCatalogue.groupOrder.count, 9)
    }

    func testOldPerKindTogglesBecomeGroups() {
        XCTAssertEqual(HealthCatalogue.migrate(["steps", "heart_rate", "resting_heart_rate", "sleep", "workout"]),
                       ["activity", "heart", "sleep", "workouts"])
        XCTAssertEqual(HealthCatalogue.migrate(["heart", "vitals"]), ["heart", "vitals"], "already-migrated state is left alone")
        XCTAssertEqual(HealthCatalogue.migrate([]), [])
    }

    func testBoundsComeFromTheCatalogue() {
        let base = HealthRecord(id: "x", kind: "oxygen_saturation", start: "2026-09-23T01:00:00Z", end: "2026-09-23T01:00:00Z", value: 97, unit: "%", source: "Watch")
        XCTAssertTrue(HealthCatalogue.accepts(base))
        var fraction = base; fraction.value = 0.97
        XCTAssertFalse(HealthCatalogue.accepts(fraction), "a 0–1 fraction must never be sent as a percentage")
        var wrongUnit = base; wrongUnit.unit = "bpm"
        XCTAssertFalse(HealthCatalogue.accepts(wrongUnit))
        var unknown = base; unknown.kind = "blood_glucose"
        XCTAssertFalse(HealthCatalogue.accepts(unknown))
    }
}

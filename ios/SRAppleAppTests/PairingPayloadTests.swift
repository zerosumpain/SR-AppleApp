import XCTest
@testable import SRAppleApp

/// What the scanner and "Open SR" hand to pairing: the site's QR (JSON), or
/// an install link in either of its two spellings. SR-Main `pair-route.test`
/// is the other half of the contract.
@MainActor
final class PairingPayloadTests: XCTestCase {
    func testTheSitesQRStillParses() throws {
        let p = try PairingPayload.parse(#"{"type":"sr-pair","version":1,"server":"https://strangeramblings.com","code":"\#(String(repeating: "C", count: 43))"}"#)
        XCTAssertEqual(p.code, String(repeating: "C", count: 43))
        XCTAssertNil(p.join)
    }

    func testAnInstallLinkParsesAsAJoin() throws {
        let p = try PairingPayload.parse("https://strangeramblings.com/app/rory-Ab12Cd34Ef")
        XCTAssertEqual(p.join, "rory-Ab12Cd34Ef")
        XCTAssertNil(p.code)
        XCTAssertEqual(p.server, "https://strangeramblings.com")
    }

    func testTheOpenButtonsSchemeParsesAsTheSameJoin() throws {
        let p = try PairingPayload.parse("sr://pair?join=rory-Ab12Cd34Ef&server=https%3A%2F%2Fstrangeramblings.com")
        XCTAssertEqual(p.join, "rory-Ab12Cd34Ef")
        XCTAssertEqual(p.server, "https://strangeramblings.com")
    }

    func testAnythingElseIsRefused() {
        XCTAssertNil(PairingPayload.fromLink("https://strangeramblings.com/welcome"))
        XCTAssertNil(PairingPayload.fromLink("https://strangeramblings.com/app/not%20a%20code"))
        XCTAssertNil(PairingPayload.fromLink("http://strangeramblings.com/app/rory-Ab12Cd34Ef"), "only HTTPS")
        XCTAssertNil(PairingPayload.fromLink("sr://pair?join=rory-Ab12Cd34Ef"), "no server")
        XCTAssertThrowsError(try PairingPayload.parse("https://strangeramblings.com/app/rory-Ab12Cd34Ef/profile"))
    }
}

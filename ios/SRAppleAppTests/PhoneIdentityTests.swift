import XCTest
@testable import SRAppleApp

/// The two headers both servers parse (SR-Main `native-telemetry.test.ts`,
/// pilot `app.test.mjs`): the grammar is a contract, so the exact strings are
/// asserted here rather than only read back from a phone.
final class PhoneIdentityTests: XCTestCase {
    func testHeadersAreTheDocumentedGrammar() {
        let h = PhoneIdentity.headers(version: "0.1.136", build: "136", commit: "68136470", model: "iPhone15,2", os: "26.0.1", name: "")
        XCTAssertEqual(h["X-SR-App"], "0.1.136/136/68136470")
        XCTAssertEqual(h["X-SR-Device"], "iPhone15,2/26.0.1")
        XCTAssertEqual(h.count, 2)
    }

    func testAnXcodeBuildHasNoCommitAndSaysSo() {
        let h = PhoneIdentity.headers(version: "0.1.0", build: "1", commit: "", model: "arm64", os: "26.0", name: "")
        XCTAssertEqual(h["X-SR-App"], "0.1.0/1/")
    }

    func testTheNameIsPercentEncodedSoASlashCannotBreakAField() {
        let h = PhoneIdentity.headers(version: "1", build: "1", commit: "", model: "iPhone15,2", os: "26.0", name: " Rory's A/B iPhone ")
        XCTAssertEqual(h["X-SR-Device"], "iPhone15,2/26.0/Rory%27s%20A%2FB%20iPhone")
    }

    func testTheNameStaysASCIIAndBounded() {
        let h = PhoneIdentity.headers(version: "1", build: "1", commit: "", model: "iPhone15,2", os: "26.0", name: "Zoë " + String(repeating: "x", count: 80))
        let value = try XCTUnwrap(h["X-SR-Device"])
        XCTAssertTrue(value.allSatisfy { $0.isASCII }, value)
        XCTAssertTrue(value.hasPrefix("iPhone15,2/26.0/Zo%C3%AB%20x"), value)
        // 60 characters of name at most, before encoding.
        let encoded = value.split(separator: "/", maxSplits: 2)[2]
        XCTAssertEqual(encoded.removingPercentEncoding?.count, 60)
    }

    func testModelIdentifierIsAPlainToken() {
        let model = PhoneIdentity.modelIdentifier
        XCTAssertFalse(model.isEmpty)
        XCTAssertTrue(model.allSatisfy { $0.isLetter || $0.isNumber || $0 == "," || $0 == "_" || $0 == "." || $0 == "-" }, model)
    }

    func testApplySetsBothHeaders() {
        var req = URLRequest(url: URL(string: "https://example.test/api/native/me")!)
        PhoneIdentity.apply(to: &req)
        XCTAssertNotNil(req.value(forHTTPHeaderField: "X-SR-App"))
        XCTAssertNotNil(req.value(forHTTPHeaderField: "X-SR-Device"))
    }
}

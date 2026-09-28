import XCTest
@testable import SRAppleApp

/// Which screen a phone opens on: Welcome, the review screen, or the app.
/// The rule that matters most is the first test — nobody already using the
/// app may ever be sent back to Welcome.
final class RegistrationTests: XCTestCase {

    func testAPairedPhoneIsTheAppWhateverElseIsTrue() {
        // John's phone (site), a family member's from a QR (companion).
        XCTAssertEqual(EntryPolicy.entry(status: nil, sitePaired: true, companionPaired: false, skipped: false), .app)
        XCTAssertEqual(EntryPolicy.entry(status: nil, sitePaired: false, companionPaired: true, skipped: false), .app)
        XCTAssertEqual(EntryPolicy.entry(status: .active, sitePaired: true, companionPaired: true, skipped: false), .app)
    }

    func testANewPhoneOpensOnWelcome() {
        XCTAssertEqual(EntryPolicy.entry(status: nil, sitePaired: false, companionPaired: false, skipped: false), .welcome)
    }

    func testAWaitingRegistrantSeesOnlyTheReviewScreen() {
        XCTAssertEqual(EntryPolicy.entry(status: .pending, sitePaired: true, companionPaired: false, skipped: false), .reviewing(.pending))
        XCTAssertEqual(EntryPolicy.entry(status: .declined, sitePaired: true, companionPaired: false, skipped: false), .reviewing(.declined))
        // Even with a companion pairing from somewhere, pending holds.
        XCTAssertEqual(EntryPolicy.entry(status: .pending, sitePaired: true, companionPaired: true, skipped: true), .reviewing(.pending))
    }

    func testASignedOutRegistrantIsBackAtWelcome() {
        // Sign out drops the credential; a stale status alone opens nothing.
        XCTAssertEqual(EntryPolicy.entry(status: .pending, sitePaired: false, companionPaired: false, skipped: false), .welcome)
    }

    func testApprovalWithNoLanesStillOpensTheApp() {
        // Approved with nothing that keeps a site credential: the app signs it
        // out (AccessPolicy.signsOutSite), and the phone must not fall back to Welcome.
        XCTAssertEqual(EntryPolicy.entry(status: .active, sitePaired: false, companionPaired: false, skipped: false), .app)
    }

    func testAPairingCodeSetsWelcomeAside() {
        XCTAssertEqual(EntryPolicy.entry(status: nil, sitePaired: false, companionPaired: false, skipped: true), .app)
    }

    func testDemoModeIsAlwaysTheApp() {
        XCTAssertEqual(EntryPolicy.entry(status: nil, sitePaired: false, companionPaired: false, skipped: false, demo: true), .app)
    }
}

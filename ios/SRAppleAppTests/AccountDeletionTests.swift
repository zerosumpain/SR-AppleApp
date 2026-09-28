import XCTest
@testable import SRAppleApp

/// Settings → Delete account (App Store 5.1.1(v)): who is offered it, what
/// confirms it, and the phone it leaves behind.
final class AccountDeletionTests: XCTestCase {

    func testTheOwnerIsNeverOfferedIt() {
        // Whatever the phone holds, the owner is told where the account lives.
        for site in [true, false] {
            for companion in [true, false] {
                XCTAssertEqual(AccountDeletionPolicy.lane(isOwner: true, sitePaired: site, companionPaired: companion), .ownerManaged)
            }
        }
    }

    func testAMemberDeletesThroughTheSiteWhenItCan() {
        XCTAssertEqual(AccountDeletionPolicy.lane(isOwner: false, sitePaired: true, companionPaired: true), .site)
        XCTAssertEqual(AccountDeletionPolicy.lane(isOwner: false, sitePaired: true, companionPaired: false), .site)
    }

    func testACompanionOnlyPhoneDeletesThroughTheCompanionServer() {
        XCTAssertEqual(AccountDeletionPolicy.lane(isOwner: false, sitePaired: false, companionPaired: true), .companion)
    }

    func testAnUnpairedPhoneHasNothingToDelete() {
        XCTAssertEqual(AccountDeletionPolicy.lane(isOwner: false, sitePaired: false, companionPaired: false), .unpaired)
    }

    func testOnlyTheTypedWordConfirms() {
        XCTAssertTrue(AccountDeletionPolicy.confirmed("DELETE"))
        XCTAssertTrue(AccountDeletionPolicy.confirmed(" delete "))
        XCTAssertFalse(AccountDeletionPolicy.confirmed(""))
        XCTAssertFalse(AccountDeletionPolicy.confirmed("DELET"))
        XCTAssertFalse(AccountDeletionPolicy.confirmed("yes"))
        XCTAssertFalse(AccountDeletionPolicy.confirmed("DELETE ACCOUNT"))
    }

    func testTheScreenSaysWhatGoesAndWhatStays() {
        let deleted = AccountDeletionPolicy.deleted.joined(separator: " ")
        XCTAssertTrue(deleted.contains("health records and location history"))
        XCTAssertTrue(deleted.contains("chat threads"))
        XCTAssertTrue(deleted.contains("every other phone"))
        XCTAssertTrue(AccountDeletionPolicy.kept.joined(separator: " ").contains("Apple Health on this iPhone"))
    }

    @MainActor func testAfterDeletionThePhoneIsBackAtWelcome() {
        let store = RegistrationStore.shared
        // A phone that had set Welcome aside with a pairing code…
        store.skipToPairing()
        XCTAssertTrue(store.skipped)
        store.forgetAfterAccountDeletion()
        // …is a phone nobody has set up.
        XCTAssertNil(store.status)
        XCTAssertNil(store.email)
        XCTAssertFalse(store.skipped)
        XCTAssertEqual(EntryPolicy.entry(status: store.status, sitePaired: false, companionPaired: false, skipped: store.skipped), .welcome)
    }

    @MainActor func testNothingHappensForTheOwnerOrAnUnpairedPhone() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = try Outbox(url: directory.appendingPathComponent("state.json"))
        let companion = Companion(outbox: outbox)
        let site = SitePairingModel()
        let deletion = AccountDeletionStore()
        let ownerDeleted = await deletion.delete(lane: .ownerManaged, companion: companion, site: site)
        XCTAssertFalse(ownerDeleted)
        let noneDeleted = await deletion.delete(lane: .unpaired, companion: companion, site: site)
        XCTAssertFalse(noneDeleted)
        XCTAssertNil(deletion.error)
    }

    @MainActor func testForgettingTheCompanionLeavesNothingBehind() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = try Outbox(url: directory.appendingPathComponent("state.json"))
        try outbox.change { $0.sharing = true }
        let companion = Companion(outbox: outbox)
        companion.forgetAfterAccountDeletion()
        XCTAssertFalse(companion.paired)
        XCTAssertNil(companion.api.token)
        XCTAssertFalse(outbox.state.sharing, "a phone that re-pairs starts from ask-first")
        XCTAssertEqual(companion.queueCount, 0)
        XCTAssertTrue(companion.family.isEmpty)
    }
}

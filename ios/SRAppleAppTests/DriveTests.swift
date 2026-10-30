import XCTest
@testable import SRAppleApp

/// Drive on the phone. The privacy itself is the site's (SR-Main
/// `$lib/drive/app-lane`, with its own tests); these hold the app to what it
/// shows: who gets the door, what a listing decodes to, and the names and
/// sizes it sends.
final class DriveTests: XCTestCase {

    // MARK: - Who gets Drive

    func testTheOwnerAndADriveMemberGetDriveOverTheSite() {
        XCTAssertTrue(AccessPolicy.drive(AppAccess(owner: true), sitePaired: true))
        XCTAssertTrue(AccessPolicy.drive(AppAccess(family: true, drive: true), sitePaired: true))
    }

    func testNoDriveWithoutTheGrantOrTheSite() {
        XCTAssertFalse(AccessPolicy.drive(AppAccess(family: true, games: true), sitePaired: true))
        XCTAssertFalse(AccessPolicy.drive(AppAccess(drive: true), sitePaired: false))
        XCTAssertFalse(AccessPolicy.drive(.nothing, sitePaired: true))
    }

    func testADriveOnlyMemberAsksForASiteCredentialAndKeepsIt() {
        let driveOnly = AppAccess(drive: true)
        XCTAssertTrue(AccessPolicy.wantsSitePair(known: driveOnly, sitePaired: false))
        XCTAssertFalse(AccessPolicy.signsOutSite(known: driveOnly, sitePaired: true, siteRole: "member"))
    }

    func testTheDriveFlagDecodesAndIsFalseWhenMissing() throws {
        let on = try JSONDecoder().decode(AppAccess.self, from: Data(#"{"family":true,"drive":true}"#.utf8))
        XCTAssertEqual(on, AppAccess(family: true, drive: true))
        let off = try JSONDecoder().decode(AppAccess.self, from: Data(#"{"family":true,"drive":"yes"}"#.utf8))
        XCTAssertFalse(off.drive)
        XCTAssertTrue(AppAccess.everything.drive)
        let back = try JSONDecoder().decode(AppAccess.self, from: JSONEncoder().encode(AppAccess(drive: true)))
        XCTAssertTrue(back.drive)
    }

    // MARK: - The site's answer

    func testAListingDecodes() throws {
        let json = #"""
        {"space":"shared","folder":"Trip","folders":[{"name":"Day 1","path":"Trip/Day 1","items":3}],
         "files":[{"id":"f1","name":"rota.xlsx","path":"Trip/rota.xlsx","mimeType":"application/vnd.ms-excel",
                   "sizeBytes":2048,"createdAt":"2026-10-30T08:00:00.000Z","updatedAt":"2026-10-30T08:00:00.000Z",
                   "mine":false,"addedBy":"Rory","canDelete":false}],
         "usage":{"bytes":2048,"quotaBytes":2147483648},"maxUploadBytes":31457280}
        """#
        let listing = try JSONDecoder().decode(DriveListing.self, from: Data(json.utf8))
        XCTAssertEqual(listing.space, .shared)
        XCTAssertEqual(listing.folders.first?.path, "Trip/Day 1")
        XCTAssertEqual(listing.files.first?.addedBy, "Rory")
        XCTAssertFalse(listing.files[0].canDelete)
        XCTAssertEqual(listing.usage.quotaBytes, 2_147_483_648)
    }

    func testTheOwnersDriveHasNoLimit() throws {
        let json = #"{"space":"mine","folder":"","folders":[],"files":[],"usage":{"bytes":10,"quotaBytes":null},"maxUploadBytes":1}"#
        let listing = try JSONDecoder().decode(DriveListing.self, from: Data(json.utf8))
        XCTAssertNil(listing.usage.quotaBytes)
        XCTAssertTrue(DriveLogic.usage(listing.usage).hasSuffix("used"))
    }

    // MARK: - What the app sends

    func testListPathsEscapeTheFolderStrictly() {
        XCTAssertEqual(DriveLogic.listPath(DriveRef(space: .mine)), "api/native/drive?space=mine")
        XCTAssertEqual(DriveLogic.listPath(DriveRef(space: .shared, folder: "Run & ride/2026")),
                       "api/native/drive?space=shared&folder=Run%20%26%20ride/2026")
    }

    func testFolderNamesTheSiteWouldRefuseAreCaughtFirst() {
        XCTAssertEqual(DriveLogic.usableName("  Holiday  "), "Holiday")
        for bad in ["", "  ", ".", "..", ".keep", "a/b", "a\\b", String(repeating: "x", count: 121), "a\nb"] {
            XCTAssertNil(DriveLogic.usableName(bad), bad)
        }
    }

    func testPhotoNamesSortByTimeAndNeverClashInABatch() {
        let at = ISO8601DateFormatter().date(from: "2026-10-30T08:05:09Z")!
        let first = DriveLogic.photoName(at: at, index: 0)
        let second = DriveLogic.photoName(at: at, index: 1)
        XCTAssertTrue(first.hasPrefix("Photo 2026-10-30 "))
        XCTAssertTrue(first.hasSuffix(".jpg"))
        XCTAssertNotEqual(first, second)
    }

    func testFoldersAndTitles() {
        XCTAssertEqual(DriveLogic.child("", "Trip"), "Trip")
        XCTAssertEqual(DriveLogic.child("Holiday", "2026"), "Holiday/2026")
        XCTAssertEqual(DriveRef(space: .mine, folder: "Holiday/2026").title, "2026")
        XCTAssertEqual(DriveRef().title, "Drive")
    }

    func testTooLargeSaysSoBeforeUploading() {
        XCTAssertNil(DriveLogic.tooLarge(10, limit: 10))
        XCTAssertNotNil(DriveLogic.tooLarge(11, limit: 10))
    }

    func testIcons() {
        XCTAssertEqual(DriveLogic.icon(mime: "image/jpeg", name: "a.jpg"), "photo")
        XCTAssertEqual(DriveLogic.icon(mime: "application/octet-stream", name: "a.HEIC"), "photo")
        XCTAssertEqual(DriveLogic.icon(mime: "video/quicktime", name: "a.mov"), "film")
        XCTAssertEqual(DriveLogic.icon(mime: "application/pdf", name: "a.pdf"), "doc.richtext")
        XCTAssertEqual(DriveLogic.icon(mime: "text/plain", name: "a.txt"), "doc.text")
    }
}

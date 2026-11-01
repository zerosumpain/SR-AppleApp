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

    func testTheShareExtensionGetsTheCredentialForDriveAlone() {
        XCTAssertTrue(AccessPolicy.shelvesCredential(AppAccess(drive: true), sitePaired: true))
        XCTAssertTrue(AccessPolicy.shelvesCredential(AppAccess(family: true), sitePaired: true))
        XCTAssertFalse(AccessPolicy.shelvesCredential(AppAccess(games: true), sitePaired: true))
        XCTAssertFalse(AccessPolicy.shelvesCredential(AppAccess(drive: true), sitePaired: false))
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

/// Drive's pure rules: links, order, names, the upload queue's states and
/// what jkai's analysis decodes to. Foundation only, like the code they
/// test — they also run on Linux, outside Xcode, against `DriveLink.swift`,
/// `DriveModels.swift` and `DriveUploadJobs.swift` alone.
final class DriveLogicTests: XCTestCase {

    private func file(_ id: String, _ name: String, size: Int = 1, updated: String = "2026-10-30T08:00:00.000Z",
                      mime: String = "application/octet-stream", path: String? = nil) -> DriveFile {
        DriveFile(id: id, name: name, path: path ?? name, mimeType: mime, sizeBytes: size, createdAt: updated,
                  updatedAt: updated, mine: true, addedBy: nil, canDelete: true)
    }

    // MARK: - Links

    func testADriveLinkReadsEveryPart() {
        let url = URL(string: "sr://drive?space=shared&folder=Mail%2Fimportant%2F2026-11&file=abc-123")!
        XCTAssertEqual(DriveLink.from(url: url), DriveLink(space: .shared, folder: "Mail/important/2026-11", fileId: "abc-123"))
    }

    func testEveryPartIsOptional() {
        XCTAssertEqual(DriveLink.from(url: URL(string: "sr://drive")!), DriveLink())
        XCTAssertEqual(DriveLink.from(url: URL(string: "sr://drive?folder=Trip")!), DriveLink(space: .mine, folder: "Trip"))
        XCTAssertEqual(DriveLink.from(url: URL(string: "sr://drive?space=SHARED")!)?.space, .shared)
        XCTAssertEqual(DriveLink.from(url: URL(string: "sr://drive?space=nobody")!)?.space, .mine)
    }

    func testOtherLinksAreNotDrives() {
        XCTAssertNil(DriveLink.from(url: URL(string: "sr://captures/abc")!))
        XCTAssertNil(DriveLink.from(url: URL(string: "https://strangeramblings.com/jkai?c=1")!))
        XCTAssertNil(DriveLink.from(url: URL(string: "mailto:a@b.c")!))
    }

    func testALinkRoundTrips() {
        let links = [
            DriveLink(),
            DriveLink(space: .shared, folder: "Run & ride/2026 #1", fileId: nil),
            DriveLink(space: .mine, folder: "Mail/important/Café", fileId: "6f1c2a9e-0d1b-4b8e-9a77-1f0c3e2d4b5a"),
        ]
        for link in links { XCTAssertEqual(DriveLink.from(url: link.url), link, link.url.absoluteString) }
    }

    func testTheWebPageLinkReadsAsMyFiles() {
        XCTAssertEqual(DriveLink.from(link: "/drive?path=Mail%2Fimportant&file=f1"),
                       DriveLink(space: .mine, folder: "Mail/important", fileId: "f1"))
        XCTAssertEqual(DriveLink(space: .mine, folder: "Mail/important", fileId: "f1").webPath, "/drive?path=Mail%2Fimportant&file=f1")
        XCTAssertEqual(DriveLink().webPath, "/drive")
    }

    func testAPushOpensTheFolderItNames() {
        let info: [AnyHashable: Any] = ["category": "drive", "url": "sr://drive?space=mine&folder=Mail%2Fimportant%2Fhmrc.gov.uk%2F2026-11&file=f9"]
        XCTAssertEqual(DriveLink.from(userInfo: info), DriveLink(space: .mine, folder: "Mail/important/hmrc.gov.uk/2026-11", fileId: "f9"))
        XCTAssertNil(DriveLink.from(userInfo: ["url": "sr://chat/abc"]))
        XCTAssertNil(DriveLink.from(userInfo: [:]))
    }

    func testALinkCannotClimbOutOrAddressAnotherRoute() {
        XCTAssertEqual(DriveLink.from(url: URL(string: "sr://drive?folder=a%2F..%2Fb")!)?.folder, "")
        XCTAssertEqual(DriveLink.from(url: URL(string: "sr://drive?folder=%2Fa%2F%2Fb%2F")!)?.folder, "a/b")
        XCTAssertNil(DriveLink.from(url: URL(string: "sr://drive?file=..%2Fmeta")!)?.fileId)
        XCTAssertNil(DriveLink.from(url: URL(string: "sr://drive?file=a%20b")!)?.fileId)
    }

    // MARK: - Order and search

    func testSortsByEachKeyWithTheNameBreakingTies() {
        let a = file("1", "b.pdf", size: 10, updated: "2026-10-01T00:00:00.000Z", mime: "application/pdf")
        let b = file("2", "a.jpg", size: 30, updated: "2026-10-03T00:00:00.000Z", mime: "image/jpeg")
        let c = file("3", "c.txt", size: 30, updated: "2026-10-02T00:00:00.000Z", mime: "text/plain")
        XCTAssertEqual(DriveLogic.sorted([a, b, c], by: .name).map(\.id), ["2", "1", "3"])
        XCTAssertEqual(DriveLogic.sorted([a, b, c], by: .date).map(\.id), ["2", "3", "1"])
        XCTAssertEqual(DriveLogic.sorted([a, b, c], by: .size).map(\.id), ["2", "3", "1"])
        XCTAssertEqual(DriveLogic.sorted([a, b, c], by: .type).map(\.id), ["2", "1", "3"])
    }

    func testNamesSortAsPeopleCount() {
        let names = ["Photo 10.jpg", "Photo 2.jpg", "photo 1.jpg"].enumerated().map { file("\($0.offset)", $0.element) }
        XCTAssertEqual(DriveLogic.sorted(names, by: .name).map(\.name), ["photo 1.jpg", "Photo 2.jpg", "Photo 10.jpg"])
    }

    func testSearchMatchesEveryWordAnyCase() {
        XCTAssertTrue(DriveLogic.matches("HMRC tax return 2026.pdf", query: "tax hmrc"))
        XCTAssertFalse(DriveLogic.matches("HMRC tax return 2026.pdf", query: "tax invoice"))
        XCTAssertTrue(DriveLogic.matches("anything", query: "  "))
    }

    func testSearchPathsAreEscapedAndBounded() {
        XCTAssertEqual(DriveLogic.searchPath(space: .mine, query: " tax & vat "), "api/native/drive/search?space=mine&q=tax%20%26%20vat")
        XCTAssertNil(DriveLogic.searchPath(space: .mine, query: "   "))
        XCTAssertNil(DriveLogic.searchPath(space: .shared, query: String(repeating: "x", count: 201)))
    }

    func testFilePathsKeepTheIdOneComponent() {
        XCTAssertEqual(DriveLogic.filePath("abc-1", "meta"), "api/native/drive/files/abc-1/meta")
        XCTAssertEqual(DriveLogic.metaPath(DriveFileRef(space: .shared, id: "f1")), "api/native/drive/files/f1/meta?space=shared")
        XCTAssertFalse(DriveLogic.filePath("a/b?c").contains("a/b"))
    }

    func testAFileRefIsItsSpaceAndId() {
        let known = file("f1", "a.pdf")
        XCTAssertEqual(DriveFileRef(space: .mine, id: "f1", known: known, action: .analyse), DriveFileRef(space: .mine, id: "f1"))
        XCTAssertNotEqual(DriveFileRef(space: .mine, id: "f1"), DriveFileRef(space: .shared, id: "f1"))
    }

    func testMoveTargetsNeverIncludeWhereItIs() {
        let children = [DriveFolder(name: "x", path: "a/b/x", items: 1)]
        XCTAssertEqual(DriveLogic.moveTargets(from: "a/b", children: children), ["", "a", "a/b/x"])
        XCTAssertEqual(DriveLogic.moveTargets(from: "", children: []), [])
        XCTAssertEqual(DriveLogic.parent("a/b"), "a")
        XCTAssertEqual(DriveLogic.parent("a"), "")
    }

    // MARK: - Names and times

    func testAPhotoIsNamedFromWhenItWasTaken() {
        XCTAssertEqual(DriveLogic.photoName(takenAt: "2026-10-30T09:05:09+01:00", filename: "IMG_1234.HEIC", mimeType: "image/heic"),
                       "Photo 2026-10-30 09.05.09.heic")
        XCTAssertEqual(DriveLogic.photoName(takenAt: "2026-10-30T09:05:09Z", filename: nil, mimeType: "image/jpeg"),
                       "Photo 2026-10-30 09.05.09.jpg")
        XCTAssertEqual(DriveLogic.photoName(takenAt: "2026-10-30 09:05:09", filename: "", mimeType: "video/quicktime"),
                       "Photo 2026-10-30 09.05.09.mov")
    }

    func testANamedFileOrAFilmKeepsItsName() {
        XCTAssertNil(DriveLogic.photoName(takenAt: "2026-10-30T09:05:09Z", filename: "Beach.jpg", mimeType: "image/jpeg"))
        XCTAssertNil(DriveLogic.photoName(takenAt: "2026-10-30T09:05:09Z", filename: "IMG_0001.MOV", mimeType: "video/quicktime"))
        XCTAssertNil(DriveLogic.photoName(takenAt: nil, filename: "IMG_0001.HEIC", mimeType: "image/heic"))
        XCTAssertNil(DriveLogic.photoName(takenAt: "yesterday", filename: "IMG_0001.HEIC", mimeType: "image/heic"))
    }

    func testExifTimesBecomeTakenAt() {
        XCTAssertEqual(DriveLogic.takenAt(exif: "2026:10:30 09:05:09", offset: "+01:00"), "2026-10-30T09:05:09+01:00")
        let london = TimeZone(identifier: "Europe/London")!
        XCTAssertEqual(DriveLogic.takenAt(exif: "2026:07:01 18:00:00", offset: nil, timeZone: london), "2026-07-01T18:00:00+01:00")
        XCTAssertNil(DriveLogic.takenAt(exif: "not a date", offset: nil))
        XCTAssertNil(DriveLogic.takenAt(exif: nil, offset: "+01:00"))
    }

    func testTheLocalTimeCarriesItsOffset() {
        let moment = ISO8601DateFormatter().date(from: "2026-07-01T17:00:00Z")!
        XCTAssertEqual(DriveLogic.localISO(moment, timeZone: TimeZone(identifier: "Europe/London")!), "2026-07-01T18:00:00+01:00")
        XCTAssertEqual(DriveLogic.localISO(moment, timeZone: TimeZone(identifier: "UTC")!), "2026-07-01T17:00:00Z")
    }

    func testTheDetailLineIsSizeDateAndWho() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z")!
        let shared = DriveFile(id: "f", name: "rota.xlsx", path: "rota.xlsx", mimeType: "x", sizeBytes: 2048,
                               createdAt: "2026-10-30T08:00:00.000Z", updatedAt: "2026-10-30T08:00:00.000Z",
                               mine: false, addedBy: "Rory", canDelete: false)
        let detail = DriveLogic.detail(shared, now: now, calendar: calendar)
        XCTAssertTrue(detail.hasSuffix(" · 30 Oct · added by Rory"), detail)
        XCTAssertEqual(DriveLogic.day("2026-11-01T08:00:00Z", now: now, calendar: calendar), "Today")
        XCTAssertEqual(DriveLogic.day("2025-11-01T08:00:00Z", now: now, calendar: calendar), "1 Nov 2025")
    }

    // MARK: - The upload queue

    private func job(asset: String? = nil) -> DriveUploadJob {
        DriveUploadJob(id: "j1", space: .mine, folder: "Camera", filename: "IMG_0001.HEIC", mimeType: "image/heic",
                       sizeBytes: 100, sha256: String(repeating: "a", count: 64), takenAt: "2026-10-30T09:05:09+01:00",
                       staged: "j1.HEIC", assetId: asset, createdAt: Date(timeIntervalSince1970: 0))
    }

    private func reply(_ duplicate: Bool?) -> Data {
        let flag = duplicate.map { ",\"duplicate\":\($0)" } ?? ""
        return Data(#"{"file":{"id":"f1","name":"Photo.heic","path":"Camera/Photo.heic","mimeType":"image/heic","sizeBytes":100,"createdAt":"x","updatedAt":"x","mine":true,"addedBy":null,"canDelete":true}\#(flag)}"#.utf8)
    }

    func testANewFileIsStoredSafely() {
        let sending = job().started()
        XCTAssertEqual(sending.state, .sending)
        XCTAssertEqual(sending.attempts, 1)
        let done = sending.progressed(60).finished(status: 201, body: reply(false), transportError: nil)
        XCTAssertEqual(done.state, .stored(fileId: "f1", duplicate: false, safe: true))
        XCTAssertTrue(done.isSafelyStored)
        XCTAssertEqual(done.sentBytes, 100)
        XCTAssertEqual(done.displayName, "Photo 2026-10-30 09.05.09.heic")
    }

    func testAFileAlreadyThereIsAsSafe() {
        let done = job().started().finished(status: 200, body: reply(true), transportError: nil)
        XCTAssertEqual(done.state, .stored(fileId: "f1", duplicate: true, safe: true))
    }

    func testOnlyA201OrADuplicateProvesTheBytesAreHeld() {
        XCTAssertFalse(job().started().finished(status: 200, body: reply(false), transportError: nil).isSafelyStored)
        XCTAssertFalse(job().started().finished(status: 200, body: reply(nil), transportError: nil).isSafelyStored)
        XCTAssertFalse(job().started().finished(status: 201, body: Data("{}".utf8), transportError: nil).isSafelyStored)
    }

    func testNoSignalOrABusySiteIsTriedAgainThenWaits() {
        var j = job().started().finished(status: nil, body: nil, transportError: "offline")
        XCTAssertEqual(j.state, .failed("offline"))
        XCTAssertTrue(j.retriesItself)
        j = j.retried().started().finished(status: 503, body: nil, transportError: nil)
        XCTAssertTrue(j.retriesItself)
        j = j.retried().started().finished(status: 429, body: nil, transportError: nil)
        XCTAssertEqual(j.attempts, 3)
        XCTAssertFalse(j.retriesItself, "a third failure waits for Try again")
        XCTAssertFalse(j.isFinished)
    }

    func testARefusalIsFinalAndInTheSitesWords() {
        let body = Data(#"{"error":"This space is full — 2 GB each."}"#.utf8)
        let j = job().started().finished(status: 413, body: body, transportError: nil)
        XCTAssertEqual(j.state, .refused("This space is full — 2 GB each."))
        XCTAssertTrue(j.isFinished)
        XCTAssertFalse(j.retriesItself)
        XCTAssertEqual(job().started().finished(status: 400, body: nil, transportError: nil).state,
                       .refused("The site wouldn't take that (400)."))
    }

    func testTheLedgerHoldsOnlyWhatIsSafe() {
        let ledger = DriveMoveLedger()
        let safe = job(asset: "A1").started().finished(status: 201, body: reply(false), transportError: nil)
        let unproven = job(asset: "A2").started().finished(status: 200, body: reply(false), transportError: nil)
        let failed = job(asset: "A3").started().finished(status: 500, body: nil, transportError: nil)
        let next = ledger.recording(safe).recording(unproven).recording(failed).recording(safe)
        XCTAssertEqual(next.entries.map(\.assetId), ["A1"])
        XCTAssertEqual(next.removable.count, 1)
        XCTAssertTrue(next.removing(["A1"]).removable.isEmpty)
        XCTAssertTrue(next.removing(["A1"]).contains("A1"), "a removed photo is never offered again")
    }

    func testTheBannerCountsUp() {
        var a = job().started()
        a = a.progressed(50)
        var b = job()
        b = DriveUploadJob(id: "j2", space: .mine, folder: "", filename: "b.pdf", mimeType: "application/pdf", sizeBytes: 100,
                           sha256: "b", takenAt: nil, staged: "j2.pdf", assetId: nil, createdAt: Date())
        XCTAssertEqual(DriveUploadOutcome.banner([a, b]), "Adding 1 of 2 · 25%")
        let done = a.finished(status: 201, body: reply(false), transportError: nil)
        XCTAssertEqual(DriveUploadOutcome.banner([done, b]), "Adding 2 of 2…")
        XCTAssertNil(DriveUploadOutcome.banner([done]))
        XCTAssertNil(DriveUploadOutcome.trouble([done]))
    }

    func testAJobSurvivesBeingWrittenDown() throws {
        let stored = job(asset: "A1").started().finished(status: 201, body: reply(false), transportError: nil)
        let back = try JSONDecoder().decode([DriveUploadJob].self, from: JSONEncoder().encode([stored, job()]))
        XCTAssertEqual(back, [stored, job()])
    }

    // MARK: - What the site sends

    func testAnAnalysisDecodes() throws {
        let json = #"""
        {"fileId":"f1","contentHash":"abc","source":"mail-rule","model":"m","summary":"Quarterly VAT invoice.",
         "docType":"invoice","keyFacts":[{"label":"Supplier","value":"Acme"}],"dates":[{"label":"Due","date":"2026-11-30"}],
         "amounts":[{"label":"Total","value":120.5,"currency":"GBP"}],"actionNeeded":"Pay by 30 Nov","createdAt":"2026-11-01T10:00:00.000Z"}
        """#
        let analysis = try JSONDecoder().decode(FileAnalysis.self, from: Data(json.utf8))
        XCTAssertEqual(analysis.docTypeTitle, "Invoice")
        XCTAssertEqual(analysis.keyFacts, [FileAnalysis.Fact(label: "Supplier", value: "Acme")])
        XCTAssertEqual(analysis.dates.first?.date, "2026-11-30")
        XCTAssertEqual(analysis.amounts.first?.value, 120.5)
        XCTAssertEqual(analysis.actionNeeded, "Pay by 30 Nov")
        XCTAssertEqual(analysis.source, "mail-rule")
    }

    func testAnAnalysisFallbackDecodesWithItsListsEmpty() throws {
        let json = #"{"fileId":"f1","contentHash":null,"source":"drive","model":"m","summary":"Some text","docType":"novel","actionNeeded":"  ","createdAt":"x"}"#
        let analysis = try JSONDecoder().decode(FileAnalysis.self, from: Data(json.utf8))
        XCTAssertTrue(analysis.keyFacts.isEmpty && analysis.dates.isEmpty && analysis.amounts.isEmpty)
        XCTAssertNil(analysis.actionNeeded)
        XCTAssertEqual(analysis.docTypeTitle, "Document")
    }

    func testAFilesMetaDecodesForTheOwnerAndAMember() throws {
        let owner = #"""
        {"file":{"id":"f1","name":"inv.pdf","path":"Mail/important/inv.pdf","mimeType":"application/pdf","sizeBytes":3,
                 "createdAt":"x","updatedAt":"x","mine":true,"addedBy":null,"canDelete":true,"folder":"Mail/important","description":null},
         "analysis":{"fileId":"f1","contentHash":null,"source":"mail-rule","model":"m","summary":"s","docType":"invoice",
                     "keyFacts":[],"dates":[],"amounts":[],"actionNeeded":null,"createdAt":"x"},
         "intel":{"status":"done","outcome":"extracted","entityCount":3},
         "mail":{"from":"HMRC","subject":"Your return","receivedAt":"2026-11-01T09:00:00.000Z"}}
        """#
        let meta = try JSONDecoder().decode(DriveFileMeta.self, from: Data(owner.utf8))
        XCTAssertEqual(meta.folder, "Mail/important")
        XCTAssertEqual(meta.file.name, "inv.pdf")
        XCTAssertEqual(meta.intel?.entityCount, 3)
        XCTAssertEqual(meta.mail?.from, "HMRC")
        XCTAssertEqual(meta.analysis?.docType, "invoice")
        let member = #"{"file":{"id":"f2","name":"a.jpg","path":"a.jpg","mimeType":"image/jpeg","sizeBytes":1,"createdAt":"x","updatedAt":"x","mine":false,"addedBy":"Sam","canDelete":false,"folder":"","description":"Beach"},"analysis":null,"intel":null,"mail":null}"#
        let seen = try JSONDecoder().decode(DriveFileMeta.self, from: Data(member.utf8))
        XCTAssertNil(seen.analysis)
        XCTAssertNil(seen.intel)
        XCTAssertEqual(seen.description, "Beach")
    }

    func testSearchResultsDecodeWithAndWithoutContents() throws {
        let f = #"{"id":"f1","name":"a.pdf","path":"a.pdf","mimeType":"application/pdf","sizeBytes":1,"createdAt":"x","updatedAt":"x","mine":true,"addedBy":null,"canDelete":true}"#
        let owner = try JSONDecoder().decode(DriveSearchResults.self, from: Data(#"{"files":[\#(f)],"semantic":[{"file":\#(f),"score":0.7,"passage":"VAT due"}]}"#.utf8))
        XCTAssertEqual(owner.semantic?.first?.passage, "VAT due")
        let member = try JSONDecoder().decode(DriveSearchResults.self, from: Data(#"{"files":[\#(f)]}"#.utf8))
        XCTAssertNil(member.semantic)
    }

    func testAChangeLeavesOutWhatItDoesNotChange() throws {
        let rename = String(decoding: try JSONEncoder().encode(DriveFileChange(space: "mine", name: "b.pdf")), as: UTF8.self)
        XCTAssertFalse(rename.contains("folder"))
        let move = String(decoding: try JSONEncoder().encode(DriveFileChange(space: "mine", folder: "")), as: UTF8.self)
        XCTAssertTrue(move.contains("\"folder\":\"\""))
        XCTAssertFalse(move.contains("name"))
    }

    func testExtractionsSayWhatHappened() {
        XCTAssertTrue(DriveLogic.intelSentence(status: "done", outcome: "extracted", entityCount: 3).contains("3"))
        XCTAssertTrue(DriveLogic.intelSentence(status: "done", outcome: "skipped", entityCount: nil).contains("folder"))
        XCTAssertTrue(DriveLogic.intelSettled("done"))
        XCTAssertFalse(DriveLogic.intelSettled("pending"))
    }
}

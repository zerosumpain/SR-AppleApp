import XCTest
@testable import SRAppleApp

/// Photo search in Drive (`DrivePhotoSearchLogic.swift`). What these hold: the
/// query is what SR-Main's `native-photos` reads, nothing is sent until
/// something is asked, each chip removes exactly its filter, the answer is
/// read leniently but only native image paths are ever fetched, and paging
/// shows each picture once.
final class DrivePhotoSearchTests: XCTestCase {

    private let a1 = "11111111-1111-4111-8111-111111111111"
    private let a2 = "22222222-2222-4222-8222-222222222222"
    private let p1 = "33333333-3333-4333-8333-333333333333"

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - The query

    func testNothingAskedSendsNothing() {
        XCTAssertTrue(PhotoSearchCriteria().isEmpty)
        XCTAssertNil(PhotoSearchCriteria(text: "   ").path())
    }

    func testBuildsTheQueryTheSiteReads() {
        var c = PhotoSearchCriteria(text: "dog & cat", ocr: "total=£5", place: "Lisbon", from: date(2026, 6, 1), to: date(2026, 8, 31), kind: .photo)
        c.add(PhotoPersonPick(id: p1, name: "Sam"))
        c.add(PhotoPersonPick(id: a1, name: nil))
        XCTAssertEqual(
            c.path(page: 1, limit: 30, calendar: utc),
            "api/native/drive/photos/search?person=\(p1)&person=\(a1)&text=dog%20%26%20cat&ocr=total%3D%C2%A35&place=Lisbon&from=2026-06-01&to=2026-08-31&type=photo&limit=30"
        )
        XCTAssertEqual(PhotoSearchCriteria(kind: .video).path(page: 3, limit: 30, calendar: utc),
                       "api/native/drive/photos/search?type=video&limit=30&page=3")
    }

    func testPeopleAreUniqueAndAtMostTen() {
        var c = PhotoSearchCriteria()
        c.add(PhotoPersonPick(id: p1, name: "Sam"))
        c.add(PhotoPersonPick(id: p1, name: "Sam"))
        XCTAssertEqual(c.people.count, 1)
        for i in 0..<20 { c.add(PhotoPersonPick(id: "id\(i)", name: nil)) }
        XCTAssertEqual(c.people.count, PhotoSearchCriteria.maxPeople)
    }

    func testSaysWhenTheRangeIsBackwards() {
        XCTAssertNotNil(PhotoSearchCriteria(from: date(2026, 9, 1), to: date(2026, 8, 1)).rangeProblem)
        XCTAssertNil(PhotoSearchCriteria(from: date(2026, 8, 1), to: date(2026, 8, 1)).rangeProblem)
    }

    // MARK: - Chips

    func testChipsShowEachFilterAndRemoveOnlyThatOne() {
        var c = PhotoSearchCriteria(text: "beach", ocr: "", place: "Lisbon", from: date(2026, 6, 1), to: date(2026, 8, 31), kind: .video)
        c.add(PhotoPersonPick(id: p1, name: "Sam"))
        c.add(PhotoPersonPick(id: a1, name: nil))
        let chips = c.chips(calendar: utc)
        XCTAssertEqual(chips.map(\.label), ["“beach”", "Sam", "Unnamed person", "Lisbon", "1 Jun – 31 Aug 2026", "Videos"])

        let noSam = c.removing(.person(p1))
        XCTAssertEqual(noSam.people.map(\.id), [a1])
        XCTAssertEqual(noSam.text, "beach")
        let noDates = c.removing(.dates)
        XCTAssertNil(noDates.from)
        XCTAssertNil(noDates.to)
        XCTAssertEqual(noDates.place, "Lisbon")
        XCTAssertNil(c.removing(.kind).kind)
        XCTAssertEqual(c.removing(.text).text, "")
        XCTAssertEqual(c.removing(.place).place, "")
    }

    func testDateLabels() {
        XCTAssertEqual(PhotoSearchLogic.rangeLabel(from: date(2025, 12, 1), to: date(2026, 1, 2), calendar: utc), "1 Dec 2025 – 2 Jan 2026")
        XCTAssertEqual(PhotoSearchLogic.rangeLabel(from: date(2026, 7, 4), to: date(2026, 7, 4), calendar: utc), "4 Jul 2026")
        XCTAssertEqual(PhotoSearchLogic.rangeLabel(from: date(2026, 7, 4), to: nil, calendar: utc), "From 4 Jul 2026")
        XCTAssertEqual(PhotoSearchLogic.rangeLabel(from: nil, to: date(2026, 7, 4), calendar: utc), "Until 4 Jul 2026")
        XCTAssertNil(PhotoSearchLogic.rangeLabel(from: nil, to: nil, calendar: utc))
    }

    // MARK: - Decoding

    private func hitJSON(_ key: String, source: String = "photos", type: String = "photo", thumb: String? = nil,
                         driveFile: String = "null", file: String = "null") -> String {
        let id = key.split(separator: ":").last.map(String.init) ?? key
        let path = thumb ?? "api/native/drive/photos/thumb/\(id)"
        return """
        {"key":"\(key)","source":"\(source)","assetId":"\(id)","type":"\(type)","takenAt":"2026-07-04T10:00:00+01:00",
         "timeZone":"Europe/London","durationSec":\(type == "video" ? "12.6" : "null"),"width":4032,"height":3024,
         "place":"Lisbon, Portugal","people":[{"id":"\(p1)","name":"Sam"},{"id":"x","name":null}],
         "thumbPath":"\(path)","previewPath":"\(path)?size=preview","driveFile":\(driveFile),"file":\(file)}
        """
    }

    private let fileJSON = """
    {"id":"f-d1","name":"whiteboard.png","path":"Notes/whiteboard.png","mimeType":"image/png","sizeBytes":10,
     "createdAt":"2026-10-30T00:00:00.000Z","updatedAt":"2026-10-30T00:00:00.000Z","mine":true,"addedBy":null,"canDelete":true}
    """

    func testDecodesAPage() throws {
        let json = """
        {"connected":true,"total":2,"page":1,"hasMore":true,"results":[
          \(hitJSON("photos:\(a1)", driveFile: #"{"id":"f-a1","name":"IMG_1.jpg"}"#)),
          \(hitJSON("photos:\(a2)", type: "video")),
          \(hitJSON("drive:f-d1", source: "drive", thumb: "api/native/drive/files/f-d1", file: fileJSON))
        ]}
        """
        let page = try decode(PhotoSearchPage.self, json)
        XCTAssertTrue(page.connected)
        XCTAssertEqual(page.total, 2)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.results.count, 3)
        let (photo, video, drive) = (page.results[0], page.results[1], page.results[2])
        XCTAssertEqual(photo.driveFileId, "f-a1")
        XCTAssertEqual(photo.previewPath, "api/native/drive/photos/thumb/\(a1)?size=preview")
        XCTAssertEqual(photo.caption, "4 Jul 2026, 10:00 · Lisbon, Portugal · Sam")
        XCTAssertTrue(video.isVideo)
        XCTAssertEqual(video.durationSec, 13)
        XCTAssertNil(video.driveFileId)
        XCTAssertEqual(drive.source, .drive)
        XCTAssertEqual(drive.file?.path, "Notes/whiteboard.png")
        XCTAssertEqual(drive.driveFileId, "f-d1")
    }

    func testSkipsAHitWithAForeignImagePathNotThePage() throws {
        let json = """
        {"connected":true,"total":null,"page":1,"hasMore":false,"results":[
          \(hitJSON("photos:\(a1)", thumb: "https://evil.example/x.jpg")),
          \(hitJSON("photos:\(a2)", thumb: "api/native/drive/photos/thumb/../../me")),
          \(hitJSON("photos:\(a2)"))
        ]}
        """
        let page = try decode(PhotoSearchPage.self, json)
        XCTAssertNil(page.total)
        XCTAssertEqual(page.results.map(\.key), ["photos:\(a2)"])
    }

    func testDecodesNotConnected() throws {
        let page = try decode(PhotoSearchPage.self, #"{"connected":false,"reason":"Immich is not linked","total":null,"page":1,"hasMore":false,"results":[]}"#)
        XCTAssertFalse(page.connected)
        XCTAssertEqual(page.reason, "Immich is not linked")
        XCTAssertTrue(PhotoSearchLogic.notConnectedMessage(page.reason).contains("Immich is not linked"))
    }

    func testDecodesPeopleAndDropsForeignFaces() throws {
        let json = """
        {"connected":true,"people":[
          {"id":"\(p1)","name":"Sam","photos":40,"facePath":"api/native/drive/photos/face/\(p1)"},
          {"id":"\(a1)","name":null,"photos":null,"facePath":"api/native/drive/photos/face/\(a1)"},
          {"id":"\(a2)","name":"Bad","photos":1,"facePath":"/api/photos/face/\(a2)"}
        ]}
        """
        let page = try decode(PhotoPeoplePage.self, json)
        XCTAssertEqual(page.people.map(\.id), [p1, a1])
        XCTAssertEqual(page.people[1].pick.label, "Unnamed person")
    }

    func testNativePaths() {
        XCTAssertTrue(PhotoSearchLogic.isNativePath("api/native/drive/photos/thumb/\(a1)"))
        XCTAssertTrue(PhotoSearchLogic.isNativePath("api/native/drive/photos/thumb/\(a1)?size=preview"))
        XCTAssertTrue(PhotoSearchLogic.isNativePath("api/native/drive/photos/face/\(p1)"))
        XCTAssertTrue(PhotoSearchLogic.isNativePath("api/native/drive/files/f-d1"))
        XCTAssertFalse(PhotoSearchLogic.isNativePath("/api/photos/thumb/\(a1)"))
        XCTAssertFalse(PhotoSearchLogic.isNativePath("api/native/drive/photos/thumb/not-a-uuid"))
        XCTAssertFalse(PhotoSearchLogic.isNativePath("api/native/drive/files/a/b"))
        XCTAssertFalse(PhotoSearchLogic.isNativePath("api/native/drive/files/.."))
        XCTAssertFalse(PhotoSearchLogic.isNativePath("https://example.com/api/native/drive/files/x"))
    }

    // MARK: - Paging and dedupe

    private func hit(_ key: String, file: String? = nil) -> PhotoHit {
        PhotoHit(key: key, thumbPath: "api/native/drive/photos/thumb/\(a1)", driveFile: file.map { PhotoHit.FileLink(id: $0, name: "x") })
    }

    func testPagesAddEachPictureOnce() {
        var r = PhotoSearchResults()
        XCTAssertEqual(r.nextPage, 1)
        r.append(PhotoSearchPage(total: nil, page: 1, hasMore: true, results: [hit("photos:a"), hit("drive:f9", file: "f9")]))
        // The same Immich photo again, and an Immich photo that is the Drive file already shown.
        r.append(PhotoSearchPage(total: nil, page: 2, hasMore: false, results: [hit("photos:a"), hit("photos:b", file: "f9"), hit("photos:c")]))
        XCTAssertEqual(r.hits.map(\.key), ["photos:a", "drive:f9", "photos:c"])
        XCTAssertNil(r.nextPage)
    }

    func testIgnoresAPageAlreadyHeld() {
        var r = PhotoSearchResults()
        r.append(PhotoSearchPage(total: 5, page: 1, hasMore: true, results: [hit("photos:a")]))
        r.append(PhotoSearchPage(total: 5, page: 1, hasMore: true, results: [hit("photos:z")]))
        XCTAssertEqual(r.hits.map(\.key), ["photos:a"])
        XCTAssertEqual(r.total, 5)
        XCTAssertEqual(r.nextPage, 2)
    }

    func testNotConnectedStopsPagingAndSaysNothingMatched() {
        var r = PhotoSearchResults()
        XCTAssertFalse(r.loadedNothing)
        r.append(PhotoSearchPage(connected: false, reason: "not linked", page: 1, hasMore: true, results: []))
        XCTAssertFalse(r.connected)
        XCTAssertNil(r.nextPage)
        XCTAssertTrue(r.loadedNothing)
    }

    // MARK: - Words

    func testDurationsAndTimes() {
        XCTAssertEqual(PhotoSearchLogic.duration(13), "0:13")
        XCTAssertEqual(PhotoSearchLogic.duration(725), "12:05")
        XCTAssertEqual(PhotoSearchLogic.duration(3723), "1:02:03")
        // The wall clock it was taken at, whatever zone the phone is in.
        XCTAssertEqual(PhotoSearchLogic.when("2026-07-04T23:30:00-07:00"), "4 Jul 2026, 23:30")
        XCTAssertEqual(PhotoSearchLogic.when("2026-07-04"), "4 Jul 2026")
        XCTAssertNil(PhotoSearchLogic.when("yesterday"))
    }
}

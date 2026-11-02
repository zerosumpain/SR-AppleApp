import XCTest
@testable import SRAppleApp

/// Drive's pictures: which files get a preview, the request and cache names,
/// the fallback to an original on an older site, and the grid's rows.
///
/// Foundation only: `scripts/home-check.sh` runs this file on Linux too.
final class DriveImageLogicTests: XCTestCase {

    func testPreviewsAreAskedOnlyForWhatTheSiteRenders() {
        XCTAssertTrue(DrivePreviewLogic.canPreview(mime: "image/heic", name: "IMG_1.HEIC"))
        XCTAssertTrue(DrivePreviewLogic.canPreview(mime: "application/octet-stream", name: "beach.JPG"))
        XCTAssertTrue(DrivePreviewLogic.canPreview(mime: "image/webp", name: "x"))
        XCTAssertFalse(DrivePreviewLogic.canPreview(mime: "image/svg+xml", name: "logo.svg"), "SVG is a document")
        XCTAssertFalse(DrivePreviewLogic.canPreview(mime: "video/quicktime", name: "clip.mov"))
        XCTAssertFalse(DrivePreviewLogic.canPreview(mime: "application/pdf", name: "plan.pdf"))
    }

    func testTheVersionIsSizeAndModifiedTimeInPlainCharacters() {
        XCTAssertEqual(DrivePreviewLogic.version(sizeBytes: 1234, updatedAt: "2026-10-30T09:15:00.000Z"), "1234-20261030091500000")
        XCTAssertNotEqual(DrivePreviewLogic.version(sizeBytes: 1234, updatedAt: "2026-10-30T09:15:00.000Z"),
                          DrivePreviewLogic.version(sizeBytes: 1235, updatedAt: "2026-10-30T09:15:00.000Z"))
        let v = DrivePreviewLogic.version(sizeBytes: 9, updatedAt: String(repeating: "9", count: 200))
        XCTAssertLessThanOrEqual(v.count, 64, "SR-Main drops a longer key")
    }

    func testTheQueryNamesTheSizeAndVersion() {
        XCTAssertEqual(DrivePreviewLogic.query(size: .thumb, version: "12-2026"), "size=thumb&v=12-2026")
        XCTAssertEqual(DrivePreviewLogic.query(size: .view, version: nil), "size=view")
    }

    func testDiskNamesAreOnePerFileVersionAndSize() {
        let a = DrivePreviewLogic.diskName(id: "f1", version: "1-2", size: .thumb)
        XCTAssertEqual(a, "f1_1-2_thumb.jpg")
        XCTAssertNotEqual(a, DrivePreviewLogic.diskName(id: "f1", version: "1-2", size: .view))
        XCTAssertNotEqual(a, DrivePreviewLogic.diskName(id: "f1", version: "1-3", size: .thumb))
        XCTAssertTrue(a.hasPrefix(DrivePreviewLogic.diskPrefix(id: "f1")))
        XCTAssertFalse(DrivePreviewLogic.diskName(id: "f10", version: "1-2", size: .thumb).hasPrefix(DrivePreviewLogic.diskPrefix(id: "f1")),
                       "forgetting f1 must not take f10's")
    }

    func testMemoryKeysDifferByDrawnSize() {
        XCTAssertNotEqual(DrivePreviewLogic.memoryKey(id: "f", version: "v", size: .thumb, points: 32),
                          DrivePreviewLogic.memoryKey(id: "f", version: "v", size: .thumb, points: 140))
    }

    func testWhatEachAnswerMeans() {
        XCTAssertEqual(DrivePreviewLogic.answer(status: 200), .show)
        XCTAssertEqual(DrivePreviewLogic.answer(status: 404), .original, "an older site without the route")
        XCTAssertEqual(DrivePreviewLogic.answer(status: 415), .mark)
        XCTAssertEqual(DrivePreviewLogic.answer(status: 422), .mark)
        XCTAssertEqual(DrivePreviewLogic.answer(status: 410), .mark)
        XCTAssertEqual(DrivePreviewLogic.answer(status: 502), .later)
        XCTAssertEqual(DrivePreviewLogic.answer(status: nil), .later)
    }

    func testOnlyASmallOriginalIsFetchedForATile() {
        XCTAssertTrue(DrivePreviewLogic.mayFetchOriginal(sizeBytes: 2 * 1024 * 1024))
        XCTAssertFalse(DrivePreviewLogic.mayFetchOriginal(sizeBytes: 15 * 1024 * 1024))
        XCTAssertFalse(DrivePreviewLogic.mayFetchOriginal(sizeBytes: 0))
    }

    func testTheGridFitsColumnsAsTheAdaptiveGridDid() {
        XCTAssertEqual(DriveGridLayout.columns(width: 361), 3)
        XCTAssertEqual(DriveGridLayout.columns(width: 408), 4)
        XCTAssertEqual(DriveGridLayout.columns(width: 0), 3, "before the width is known")
        XCTAssertEqual(DriveGridLayout.columns(width: 50), 1)
        XCTAssertEqual(DriveGridLayout.tileSide(width: 361, columns: 3), 115)
        XCTAssertEqual(DriveGridLayout.tileSide(width: 1000, columns: 2), 140, "never past the maximum")
    }

    func testRowsCoverEveryItemOnce() {
        XCTAssertEqual(DriveGridLayout.rows(count: 7, columns: 3), [0..<3, 3..<6, 6..<7])
        XCTAssertEqual(DriveGridLayout.rows(count: 0, columns: 3), [])
        XCTAssertEqual(DriveGridLayout.rows(count: 2, columns: 0), [0..<1, 1..<2])
    }
}

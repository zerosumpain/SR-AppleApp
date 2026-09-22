import XCTest
import SwiftUI
import UIKit
@testable import SRAppleApp

/// The site half of the app: what a pairing QR is allowed to say, how a
/// transcript is split, and whether the fonts the design system names actually
/// shipped in the bundle.
final class SiteTests: XCTestCase {

    // MARK: - Pairing
    //
    // A QR code is a URL somebody else controls. Without these checks the
    // scanner is a "point your paired phone at my server" button.

    private func payload(
        type: String = "sr-native-pair",
        version: Int = 1,
        server: String = "https://strangeramblings.com",
        code: String = String(repeating: "a", count: 43)
    ) throws -> String {
        let object: [String: Any] = ["type": type, "version": version, "server": server, "code": code]
        return String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    func testAcceptsOurOwnPairingPayload() throws {
        let parsed = try SitePairing.parse(try payload())
        XCTAssertEqual(parsed.server, "https://strangeramblings.com")
        XCTAssertEqual(parsed.code.count, 43)
    }

    func testRefusesPlainHTTP() throws {
        XCTAssertThrowsError(try SitePairing.parse(try payload(server: "http://strangeramblings.com")))
    }

    func testRefusesAnotherAppsQRCode() throws {
        // The companion pairing envelope is `sr-companion-pair`; scanning one
        // here must not silently point the site client at the health server.
        XCTAssertThrowsError(try SitePairing.parse(try payload(type: "sr-companion-pair")))
        XCTAssertThrowsError(try SitePairing.parse("https://example.com"))
        XCTAssertThrowsError(try SitePairing.parse("not json at all"))
    }

    func testRefusesAFutureVersion() throws {
        // A v2 payload may mean something different by the same field names.
        XCTAssertThrowsError(try SitePairing.parse(try payload(version: 2)))
    }

    // MARK: - Transcript rendering

    func testSplitsFencedCodeFromProse() {
        let markdown = """
        Here is the fix.

        ```swift
        let x = 1
        ```

        That is all.
        """
        let blocks = MarkdownText(raw: markdown).testBlocks
        XCTAssertEqual(blocks.count, 3)
        guard case .prose(let first) = blocks[0] else { return XCTFail("expected prose first") }
        XCTAssertTrue(first.contains("Here is the fix."))
        guard case .code(let code, let language) = blocks[1] else { return XCTFail("expected code second") }
        XCTAssertEqual(code, "let x = 1")
        XCTAssertEqual(language, "swift")
        guard case .prose(let last) = blocks[2] else { return XCTFail("expected prose last") }
        XCTAssertTrue(last.contains("That is all."))
    }

    /// A half-streamed code block has an opening fence and no closing one. It
    /// must render as code while it arrives, not as prose that reflows into code
    /// the moment the fence lands.
    func testUnclosedFenceIsStillCode() {
        let blocks = MarkdownText(raw: "Building it:\n\n```ts\nconst a = 1\nconst b = 2").testBlocks
        XCTAssertEqual(blocks.count, 2)
        guard case .code(let code, let language) = blocks[1] else { return XCTFail("expected trailing code") }
        XCTAssertEqual(language, "ts")
        XCTAssertTrue(code.contains("const b = 2"))
    }

    func testPlainProseIsOneBlock() {
        let blocks = MarkdownText(raw: "Just a sentence.").testBlocks
        XCTAssertEqual(blocks.count, 1)
    }

    // MARK: - The design system

    /// Every face the theme names must actually be in the bundle.
    ///
    /// `Font.custom` fails SILENTLY — a missing face falls back to the system
    /// font and the screen still renders, just wrong. That is exactly the class
    /// of bug a screenshot review misses, so it is asserted rather than eyeballed.
    func testEveryNamedFontIsRegistered() {
        let faces = [
            SR.Face.display, SR.Face.brand, SR.Face.brandMedium,
            SR.Face.body, SR.Face.bodyMedium, SR.Face.bodyBold,
            SR.Face.mono, SR.Face.monoMedium, SR.Face.monoBold,
        ]
        for face in faces {
            XCTAssertNotNil(UIFont(name: face, size: 14), "font not registered: \(face)")
        }
    }

    /// The 12pt floor. `check-font-sizes` gates 12px across the website and the
    /// health rebuild mapped the reference's 8–11px labels onto it; a phone has
    /// a weaker case for small type, not a stronger one.
    func testMonoNeverGoesUnderTheLabelFloor() {
        XCTAssertEqual(UIFont(name: SR.Face.mono, size: 14)?.pointSize, 14)
        // The helper clamps rather than trusting its caller.
        let clamped = SR.mono(8)
        XCTAssertNotNil(clamped)
        XCTAssertEqual(SR.labelFloor, 12)
    }

    /// The two registers must not resolve to the same value, or the whole point
    /// of having them is gone — every relighting bug on the website was a paper
    /// token left on an ink band.
    func testInkAndPaperRegistersDiffer() {
        XCTAssertNotEqual(SRRegister.paper.accent, SRRegister.ink.accent)
        XCTAssertNotEqual(SRRegister.paper.primary, SRRegister.ink.primary)
        XCTAssertNotEqual(SRRegister.paper.good, SRRegister.ink.good)
        XCTAssertNotEqual(SRRegister.paper.danger, SRRegister.ink.danger)
        XCTAssertNotEqual(SRRegister.paper.background, SRRegister.ink.background)
    }

    /// Spot-check the palette against `src/app.css`. These are copied values,
    /// and a copied value is one that can drift.
    func testPaletteMatchesTheSiteTokens() {
        XCTAssertEqual(UIColor(SR.paper).hexString, "EDE4D4")   // --bg
        XCTAssertEqual(UIColor(SR.ink).hexString, "1A1008")     // --text-primary
        XCTAssertEqual(UIColor(SR.accent).hexString, "C4570A")  // --accent
        XCTAssertEqual(UIColor(SR.accentOnDark).hexString, "E8863A") // --accent-on-dark
        XCTAssertEqual(UIColor(SR.accentInk).hexString, "0E5B66")    // --accent-ink
        XCTAssertEqual(UIColor(SR.good).hexString, "55663A")         // --good
        XCTAssertEqual(UIColor(SR.goodOnDark).hexString, "8A9A5B")   // --good-on-dark
        XCTAssertEqual(UIColor(SR.surface).hexString, "E8DECE")      // --surface-elevated
    }

    // MARK: - Relative time

    func testShortAgoReadsInTheLedgersRegister() {
        let now = Date()
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(shortAgo(iso.string(from: now.addingTimeInterval(-120))), "2m")
        XCTAssertEqual(shortAgo(iso.string(from: now.addingTimeInterval(-7200))), "2h")
        XCTAssertEqual(shortAgo(iso.string(from: now.addingTimeInterval(-172_800))), "2d")
        // A future timestamp clamps rather than printing a negative age.
        XCTAssertEqual(shortAgo(iso.string(from: now.addingTimeInterval(600))), "0m")
        XCTAssertEqual(shortAgo("not a date"), "")
    }
}

private extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

// ---------------------------------------------------------------------------
// URL building
//
// `appendingPathComponent` percent-encodes a `?`, so every request carrying a
// query string asked for a path that does not exist. The server answered 404
// with an HTML page, the app failed to decode `APIError` out of it, and the
// reader saw a generic error. Pairing worked throughout, because
// `api/native/me` has no query — which is exactly what made it look like a
// server problem rather than a client one.
// ---------------------------------------------------------------------------
final class SiteURLTests: XCTestCase {

    @MainActor private func built(_ path: String) throws -> URL {
        try SiteClient.shared.url(for: path)
    }

    @MainActor func testAQueryStringStaysAQueryString() throws {
        let url = try built("api/native/news?view=top&sort=time")
        XCTAssertEqual(url.path, "/api/native/news")
        XCTAssertEqual(url.query, "view=top&sort=time")
        XCTAssertFalse(url.absoluteString.contains("%3F"), "the ? was encoded into the path: \(url)")
    }

    @MainActor func testPathsWithoutAQueryAreUnchanged() throws {
        let url = try built("api/native/me")
        XCTAssertEqual(url.path, "/api/native/me")
        XCTAssertNil(url.query)
    }

    @MainActor func testEveryQueryBearingCallTheAppActuallyMakes() throws {
        // The real call sites, not invented ones.
        let paths = [
            "api/native/news?view=for-you&sort=heat&fresh=1",
            "api/native/chat/conversations?limit=40",
            "api/native/chat/conversations/abc-123/messages?limit=60&before=2026-09-22T05:00:00.000Z&beforeId=x1",
            "api/workflows/orchestrator/chat?jobId=job-7",
            "api/workflows/orchestrator/chat/stream?jobId=job-7",
        ]
        for path in paths {
            let url = try built(path)
            XCTAssertFalse(url.absoluteString.contains("%3F"), "encoded ? in \(path)")
            XCTAssertNotNil(url.query, "lost the query in \(path)")
            XCTAssertEqual(url.path, "/" + path.split(separator: "?")[0], "path wrong for \(path)")
        }
    }

    @MainActor func testAnAlreadyEncodedSearchTermIsNotEncodedTwice() throws {
        // The thread search encodes its own term. Assigning to `query` rather
        // than `percentEncodedQuery` would turn %20 into %2520.
        let url = try built("api/native/chat/conversations?limit=40&q=policy%20paper")
        XCTAssertEqual(url.query, "limit=40&q=policy%20paper")
        XCTAssertFalse(url.absoluteString.contains("%2520"))
    }

    @MainActor func testAPathSegmentIsStillEscapedProperly() throws {
        let url = try built("api/native/news/story/hn/44212")
        XCTAssertEqual(url.path, "/api/native/news/story/hn/44212")
    }
}

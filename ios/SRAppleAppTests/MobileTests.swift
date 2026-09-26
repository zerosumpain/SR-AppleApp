import XCTest
import SwiftUI
import UIKit
@testable import SRAppleApp

/// The overhaul's own logic: everything a screenshot would not catch.
///
/// The screens themselves are verified by the UI tests' attachments, which is
/// the right instrument for a layout. These are the sentences and mappings —
/// the places where a wrong answer looks perfectly plausible.
final class AlertRoutingTests: XCTestCase {

    private func route(whatsapp: Bool, native: Bool, floor: Int = 0) -> AlertRoute {
        AlertRoute(
            id: "health",
            label: "Health",
            description: "…",
            whatsapp: whatsapp,
            native: native,
            minIntervalSeconds: floor,
            customised: false
        )
    }

    func testEveryCombinationOfChannelsHasItsOwnSentence() {
        XCTAssertEqual(route(whatsapp: true, native: true).destination, "WhatsApp and this iPhone")
        XCTAssertEqual(route(whatsapp: true, native: false).destination, "WhatsApp only")
        XCTAssertEqual(route(whatsapp: false, native: true).destination, "This iPhone only")
        // Both off is a real choice and must read as one, not as a blank.
        XCTAssertEqual(route(whatsapp: false, native: false).destination, "Off")
    }

    func testAFloorReadsAsAnEnglishSentenceOrNotAtAll() {
        XCTAssertNil(route(whatsapp: true, native: true, floor: 0).floorSentence)
        XCTAssertEqual(route(whatsapp: true, native: true, floor: 3600).floorSentence,
                       "At most once every 1 hour")
        // The brief's number, and the shipped default for health.
        XCTAssertEqual(route(whatsapp: true, native: true, floor: 3 * 3600).floorSentence,
                       "At most once every 3 hours")
        XCTAssertEqual(route(whatsapp: true, native: true, floor: 5400).floorSentence,
                       "At most once every 1h 30m")
        XCTAssertEqual(route(whatsapp: true, native: true, floor: 900).floorSentence,
                       "At most once every 15 minutes")
    }

    func testEachCategoryGetsItsOwnGlyph() {
        // A notification list where every row carries the same glyph is a list
        // with no glyph, so the mapping is asserted rather than eyeballed.
        var seen = Set<String>()
        for category in ["health", "chat", "build", "deploy", "uptime", "intel", "news"] {
            let alert = SiteAlert(
                id: "a", category: category, title: "t", body: "b", url: nil,
                severity: "info", createdAt: "2026-09-22T10:00:00.000Z", read: false
            )
            XCTAssertFalse(alert.icon.isEmpty)
            XCTAssertTrue(seen.insert(alert.icon).inserted, "\(category) reuses \(alert.icon)")
        }
        // Anything unrecognised still gets a glyph rather than nothing.
        let unknown = SiteAlert(
            id: "a", category: "something-new", title: "t", body: "b", url: nil,
            severity: "info", createdAt: "2026-09-22T10:00:00.000Z", read: false
        )
        XCTAssertEqual(unknown.icon, "bell.fill")
    }

    func testSeverityIsReadFromTheWireNotGuessed() {
        let alert = SiteAlert(
            id: "a", category: "uptime", title: "t", body: "b", url: nil,
            severity: "alert", createdAt: "2026-09-22T10:00:00.000Z", read: false
        )
        XCTAssertTrue(alert.isAlert)
        XCTAssertFalse(alert.isWarning)
    }
}

final class HealthFigureTests: XCTestCase {

    private func figure(_ key: String, _ display: String, _ unit: String) -> HealthFigure {
        HealthFigure(
            key: key, label: key, value: 0, unit: unit, display: display,
            delta: nil, deltaDisplay: nil, direction: nil, improving: nil,
            caption: "today", series: nil
        )
    }

    func testAUnitIsAttachedOnlyWhereTheRenderedValueLacksOne() {
        // Percent binds tight; hours are already in the string; everything else
        // takes a space. Getting this wrong reads as "52 ms ms" or as "8h 12m h".
        XCTAssertEqual(figure("recovery", "61", "%").displayWithUnit, "61%")
        XCTAssertEqual(figure("hrv", "52", "ms").displayWithUnit, "52 ms")
        XCTAssertEqual(figure("rhr", "58", "bpm").displayWithUnit, "58 bpm")
        XCTAssertEqual(figure("sleep", "7h 24m", "h").displayWithUnit, "7h 24m")
    }

    func testAFigureDecodesWithoutItsSeries() throws {
        // The Today card ships figures WITHOUT `series` to keep the payload
        // small. A non-optional array there would make that response
        // undecodable and the whole first screen would go blank.
        let json = """
        {"key":"hrv","label":"HRV","value":52,"unit":"ms","display":"52",
         "delta":-4,"deltaDisplay":"-4%","direction":"down","improving":false,
         "caption":"vs yesterday"}
        """.data(using: .utf8)!
        let figure = try JSONDecoder().decode(HealthFigure.self, from: json)
        XCTAssertNil(figure.series)
        XCTAssertEqual(figure.improving, false)
        XCTAssertEqual(figure.id, "hrv")
    }

    func testTheWholeSummaryDecodes() throws {
        let json = """
        {"generatedAt":"2026-09-22T06:00:00.000Z","isMock":false,"strap":"Body reporting in.",
         "readiness":{"score":72.4,"label":"Ready","recommendation":"Train."},
         "figures":[{"key":"recovery","label":"Recovery","value":61,"unit":"%","display":"61",
                     "delta":null,"deltaDisplay":null,"direction":null,"improving":null,
                     "caption":"today","series":[55,58,61]}],
         "week":{"activities":4,"distanceKm":31.2,"durationMinutes":214,"elevationM":410,
                 "avgRecovery":63,"avgSleep":71},
         "records":[{"label":"Longest Run","display":"21.1 km","date":"2026-05-04"}],
         "fingerprint":"abc123"}
        """.data(using: .utf8)!
        let summary = try JSONDecoder().decode(HealthSummary.self, from: json)
        XCTAssertEqual(summary.figures.first?.series?.count, 3)
        XCTAssertEqual(summary.week?.activities, 4)
        XCTAssertEqual(summary.records.first?.display, "21.1 km")
        XCTAssertEqual(summary.fingerprint, "abc123")
    }
}

final class ThreadNavigationTests: XCTestCase {

    func testAPlaceholderThreadCarriesNothingItDoesNotKnow() {
        // Spotlight and a notification both hand back an id and nothing else.
        // The placeholder must not invent a title — "New thread" is the
        // honest label until the fetch lands. Never "Untitled".
        let placeholder = Conversation.placeholder(id: "abc-123")
        XCTAssertEqual(placeholder.id, "abc-123")
        XCTAssertNil(placeholder.title)
        XCTAssertEqual(placeholder.displayTitle, "New thread")
        XCTAssertFalse(placeholder.pinned)
        XCTAssertNil(placeholder.oneLinePreview)
    }

    private func thread(_ id: String, title: String? = nil, preview: String? = nil, messages: Int = 2,
                        pinned: Bool = false, created: String? = nil, updated: String? = nil) -> Conversation {
        Conversation(id: id, title: title, source: "web", pinned: pinned, messageCount: messages, modelProvider: nil,
                     modelId: nil, preview: preview, createdAt: created, updatedAt: updated)
    }

    func testAThreadIsNeverUntitled() {
        XCTAssertEqual(thread("a", title: "Hourly rate on 135k").displayTitle, "Hourly rate on 135k")
        XCTAssertEqual(thread("b", title: "New thread", preview: "What is wrong with this fella").displayTitle,
                       "What is wrong with this fella")
        XCTAssertEqual(thread("c", preview: "A very long last line that goes on and on well past where a title should stop").displayTitle,
                       "A very long last line that goes on and on well…")
        XCTAssertEqual(thread("d", messages: 0).displayTitle, "New thread")
    }

    func testAnEmptyThreadIsListedOnlyWhileItIsNew() {
        let now = parseTimestamp("2026-09-26T12:00:00Z")!
        XCTAssertTrue(thread("a").isListable(now: now))
        XCTAssertTrue(thread("b", messages: 0, created: "2026-09-26T11:50:00Z").isListable(now: now))
        XCTAssertFalse(thread("c", messages: 0, created: "2026-09-26T09:00:00Z").isListable(now: now))
        XCTAssertTrue(thread("d", messages: 0, pinned: true).isListable(now: now))
    }

    func testThreadsAreGroupedByWhenTheyWereLastTouched() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let now = parseTimestamp("2026-09-26T12:00:00Z")!
        let threads = [
            thread("t1", updated: "2026-09-26T09:00:00Z"),
            thread("t2", updated: "2026-09-26T07:00:00Z"),
            thread("y", updated: "2026-09-25T20:00:00Z"),
            thread("w", updated: "2026-09-22T10:00:00Z"),
            thread("m", updated: "2026-09-10T10:00:00Z"),
            thread("aug", updated: "2026-08-10T10:00:00Z"),
            thread("old", updated: "2025-07-01T10:00:00Z"),
        ]
        let groups = ThreadSections.group(threads, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.title), ["Today", "Yesterday", "Previous 7 days", "Previous 30 days", "August", "July 2025"])
        XCTAssertEqual(groups.first?.threads.map(\.id), ["t1", "t2"])
    }

    @MainActor func testAQuestionForTheDeskIsEncodedIntoTheURL() throws {
        // A Shortcut's dictated sentence reaches /jkai as a query parameter, so
        // spaces, ampersands and question marks all have to survive it.
        let url = SiteClient.shared.askURL("what is my resting heart rate & why?")
        XCTAssertEqual(url.path, "/jkai")
        let query = try XCTUnwrap(url.query)
        XCTAssertTrue(query.hasPrefix("q="))
        XCTAssertFalse(query.contains(" "), "a raw space reached the query")
        // `.urlQueryAllowed` would have let the ampersand and the question mark
        // through, splitting one question into two parameters.
        XCTAssertTrue(query.contains("%26"), "a bare & reached the query: \(query)")
        XCTAssertTrue(query.contains("%3F"), "a bare ? reached the query: \(query)")
        XCTAssertFalse(url.absoluteString.contains("%3Fq="), "the ? was encoded into the path")
    }

    @MainActor func testSendingAQuestionIsOptInAtTheURLLevelToo() throws {
        XCTAssertFalse(try XCTUnwrap(SiteClient.shared.askURL("hello").query).contains("send=1"))
        XCTAssertTrue(try XCTUnwrap(SiteClient.shared.askURL("hello", send: true).query).contains("send=1"))
    }
}

final class DynamicTypeTests: XCTestCase {

    func testEveryMonoSizeStillHonoursTheTwelvePointFloor() {
        // The floor is gated sitewide on the web and the same rule applies here,
        // where the screen is smaller and the argument for small type is weaker
        // rather than stronger. `SR.Text` is the scaled ramp; it must not have
        // lost the clamp the unscaled one has.
        for size in [6, 8, 10, 11, 12] as [CGFloat] {
            XCTAssertEqual(SR.Text.mono(size), SR.Text.mono(max(size, 12)))
            XCTAssertEqual(SR.Text.label(size), SR.Text.label(max(size, 12)))
        }
    }

    func testThePhoneMetricsClearApplesTapTarget() {
        // 12 top and bottom around a 17pt title clears 44 without measuring —
        // but only while both numbers are what they are.
        XCTAssertGreaterThanOrEqual(SR.tapTarget, 44)
        XCTAssertGreaterThanOrEqual(SR.rowPadding * 2 + 17, SR.tapTarget - 3)
    }
}

/// What the palette may and may not be asked to carry.
///
/// Three tokens measure under the 4.5:1 floor against cream, and until this
/// test existed nothing said so — the values are copied from the site, they are
/// asserted by hex, and a contrast failure is invisible to every other check in
/// the suite including the screenshots.
///
/// This does not repaint anything. The palette is the site's and changing it is
/// a decision about the site. What it does is PIN the measurement, so that a
/// value which moves moves deliberately, and so that "this colour cannot carry
/// a sentence" is a fact in the repository rather than a thing somebody once
/// noticed.
final class ContrastTests: XCTestCase {

    private func components(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// WCAG 2.1 relative luminance, of a token composited over its ground.
    ///
    /// The compositing is not optional. `--text-muted` and `--text-ghost` are
    /// PERCENTAGES OF INK, not colours, so measuring them raw reports the
    /// contrast of solid ink and passes everything. And the ground must be a
    /// parameter rather than a constant: `creamOnDark` is cream at 70% and is
    /// only ever painted on the ink band — blending it over paper would measure
    /// a colour that never appears on screen.
    private func luminance(_ color: Color, over ground: Color) -> Double {
        let top = components(color)
        let base = components(ground)
        let blend = { (channel: Double, under: Double) in channel * top.a + under * (1 - top.a) }
        let linear = { (value: Double) -> Double in
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(blend(top.r, base.r))
             + 0.7152 * linear(blend(top.g, base.g))
             + 0.0722 * linear(blend(top.b, base.b))
    }

    private func contrast(_ tone: Color, on ground: Color) -> Double {
        let (x, y) = (luminance(tone, over: ground), luminance(ground, over: ground))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testEveryTokenTheAppSetsBodyCopyInClearsTheFloor() {
        // 4.5:1 is the AA floor for text under 18pt, which is everything here.
        for (name, token) in [("ink", SR.ink), ("inkSecondary", SR.inkSecondary), ("inkMuted", SR.inkMuted)] {
            let ratio = contrast(token, on: SR.paper)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) measures \(String(format: "%.2f", ratio)):1 on paper")
        }
    }

    func testTheThreeTonesThatCannotCarryASentenceAreKnownAndMeasured() {
        // If one of these rises above the floor, the constraint has been lifted
        // and this test should be deleted rather than updated. If one FALLS
        // further, something re-picked a token by eye.
        let measured: [(String, Color, ClosedRange<Double>)] = [
            ("accent", SR.accent, 3.2...3.9),
            ("warn", SR.warn, 2.3...2.9),
            ("inkGhost", SR.inkGhost, 2.6...3.2),
        ]
        for (name, token, expected) in measured {
            let ratio = contrast(token, on: SR.paper)
            XCTAssertTrue(
                expected.contains(ratio),
                "\(name) measures \(String(format: "%.2f", ratio)):1 on paper, outside the recorded \(expected)"
            )
            XCTAssertLessThan(ratio, 4.5, "\(name) now clears the floor — lift the rule rather than keeping it")
        }
    }

    func testTheInkRegisterHasItsOwnPartnerForEachOne() {
        // The whole reason `SRRegister` exists: a paper token is ink on ink.
        // Each on-dark partner must actually be readable on the band it is for.
        for (name, token) in [("accentOnDark", SR.accentOnDark),
                              ("goodOnDark", SR.goodOnDark),
                              ("errorOnDark", SR.errorOnDark),
                              ("creamOnDark", SR.creamOnDark)] {
            let ratio = contrast(token, on: SR.ink)
            XCTAssertGreaterThanOrEqual(ratio, 3.0, "\(name) measures \(String(format: "%.2f", ratio)):1 on ink")
        }
    }
}

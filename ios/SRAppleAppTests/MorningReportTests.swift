import XCTest
@testable import SRAppleApp

/// The morning report's wire shape (`GET /api/native/briefing`, contract §3)
/// and the rules the screen draws by.
///
/// Foundation only: `scripts/home-check.sh` runs this file on Linux too.
final class MorningReportTests: XCTestCase {

    private func decode(_ json: String) throws -> NativeBriefing {
        try JSONDecoder().decode(NativeBriefing.self, from: Data(json.utf8))
    }

    // MARK: - The contract's record

    func testTheContractRecordDecodes() throws {
        let report = try decode(Self.fixture)
        XCTAssertEqual(report.day, "2026-10-28")
        XCTAssertEqual(report.title, "Briefing — Wed 28 Oct")
        XCTAssertEqual(report.dateLabel, "Wednesday 28 October")
        XCTAssertTrue(report.verified)
        XCTAssertEqual(report.mode, .weekday)
        XCTAssertEqual(report.factors.count, 19)
        XCTAssertEqual(report.factors.map(\.n), Array(1...19))
        XCTAssertEqual(report.connections.count, 2)
        XCTAssertEqual(report.actionable, 1)
        XCTAssertEqual(report.gaps, [.init(section: "todos", reason: "timed out")])
        XCTAssertEqual(report.days.first, "2026-10-28")
        XCTAssertEqual(report.pageUrl, "https://strangeramblings.com/jkai/daydreams/briefing/2026-10-28")
    }

    func testFactsCarryTheirAssessmentLinksAndActions() throws {
        let weather = try XCTUnwrap(try decode(Self.fixture).factors.first { $0.key == "weather-here" })
        XCTAssertEqual(weather.icon, "cloud.sun.fill")
        XCTAssertEqual(weather.group, .place)
        XCTAssertEqual(weather.salience, 72)
        XCTAssertEqual(weather.facts.count, 2)
        XCTAssertEqual(weather.facts[0].assessment, "Umbrella by 16:00")
        XCTAssertNil(weather.facts[0].href)
        XCTAssertFalse(weather.facts[0].action)
        XCTAssertEqual(weather.facts[1].href, "/jkai/weather")
        XCTAssertTrue(weather.facts[1].action)
        XCTAssertTrue(weather.hasAction)
    }

    func testEveryStatusDecodes() throws {
        let byKey = Dictionary(uniqueKeysWithValues: try decode(Self.fixture).factors.map { ($0.key, $0.status) })
        XCTAssertEqual(byKey["sleep"], .ok)
        XCTAssertEqual(byKey["air"], .stale)
        XCTAssertEqual(byKey["trip"], .off)
        XCTAssertEqual(byKey["todos"], .failed)
        XCTAssertEqual(byKey["local"], .empty)
    }

    func testACardWithNoHeadlineSaysWhy() throws {
        let report = try decode(Self.fixture)
        let trip = try XCTUnwrap(report.factors.first { $0.key == "trip" })
        XCTAssertEqual(trip.line, "No trip in the next 14 days")
        XCTAssertTrue(trip.status.isQuiet)
        let sleep = try XCTUnwrap(report.factors.first { $0.key == "sleep" })
        XCTAssertEqual(sleep.line, "Sleep line")
        XCTAssertNil(sleep.status.badge)
    }

    // MARK: - Old records and new values

    func testARecordFromBeforeTheFactorsDecodesWithEmptyLists() throws {
        let report = try decode("""
        {"day":"2026-10-20","title":"Briefing — Tue 20 Oct","dateLabel":"Tuesday 20 October",
         "generatedAt":"2026-10-20T07:00:00Z","headline":"A quiet one","markdown":"Nothing much.",
         "verified":false,"mode":null,"gaps":[],"daydreamsText":"",
         "pageUrl":"https://strangeramblings.com/jkai/daydreams/briefing/2026-10-20","days":["2026-10-20"]}
        """)
        XCTAssertEqual(report.day, "2026-10-20")
        XCTAssertEqual(report.factors, [])
        XCTAssertEqual(report.connections, [])
        XCTAssertNil(report.mode)
        XCTAssertTrue(report.grouped.isEmpty)
        XCTAssertEqual(report.markdown, "Nothing much.")
    }

    func testABareRecordStillDecodes() throws {
        let report = try decode(#"{"day":"2026-10-21"}"#)
        XCTAssertEqual(report.day, "2026-10-21")
        XCTAssertEqual(report.markdown, "")
        XCTAssertFalse(report.verified)
        XCTAssertEqual(report.days, [])
        XCTAssertEqual(report.gaps, [])
    }

    func testUnknownStatusGroupAndModeDoNotFailTheDecode() throws {
        let report = try decode("""
        {"day":"2026-10-29","mode":"holiday","factors":[
          {"key":"tides","n":20,"label":"Tides","group":"Sea","icon":"water.waves","status":"partial",
           "headline":"High at 11:02","salience":12,"facts":[],"detail":""},
          {"key":"sleep","n":7,"label":"Sleep","group":"Body","icon":"bed.double.fill","status":"ok",
           "headline":"7h 10m","salience":30,"facts":[],"detail":""}
        ],"connections":[{"text":"Odd","factors":["tides"],"salience":5,"action":false,"extra":1}]}
        """)
        XCTAssertEqual(report.mode, .other("holiday"))
        XCTAssertNil(report.mode?.label)
        XCTAssertEqual(report.factors.count, 2)
        XCTAssertEqual(report.factors[0].status, .other("partial"))
        XCTAssertEqual(report.factors[0].status.badge, "Partial")
        XCTAssertEqual(report.factors[0].group, .other("Sea"))
        // Known groups first, in the contract's order; the unknown one after.
        XCTAssertEqual(report.grouped.map(\.group), [.body, .other("Sea")])
        XCTAssertEqual(report.connections.first?.text, "Odd")
    }

    func testOneMalformedCardCostsOnlyThatCard() throws {
        let report = try decode("""
        {"day":"2026-10-29","factors":[
          "not a card",
          {"key":"sleep","n":"7","label":"Sleep","group":"Body","status":"ok","salience":"30","facts":[{"label":"Asleep","value":7.5}]}
        ],"connections":{"oops":true},"gaps":null}
        """)
        XCTAssertEqual(report.factors.map(\.key), ["sleep"])
        XCTAssertEqual(report.factors[0].n, 7)
        XCTAssertEqual(report.factors[0].salience, 30)
        XCTAssertEqual(report.factors[0].facts.first?.value, "7.5")
        XCTAssertEqual(report.connections, [])
        XCTAssertEqual(report.gaps, [])
    }

    func testItRoundTripsForTheCache() throws {
        let report = try decode(Self.fixture)
        let again = try JSONDecoder().decode(NativeBriefing.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(again, report)
    }

    // MARK: - Grouping and labels

    func testFactorsGroupInTheContractsOrder() throws {
        let groups = try decode(Self.fixture).grouped
        XCTAssertEqual(groups.map(\.group.title), ["Place", "Body", "Day", "Home & family", "Intelligence", "Systems"])
        XCTAssertEqual(groups.map(\.factors.count), [6, 3, 3, 2, 4, 1])
        XCTAssertEqual(groups[0].factors.map(\.key), ["location", "weather-here", "weather-home", "air", "daylight", "trip"])
    }

    func testAConnectionNamesItsFactorsByLabel() throws {
        let report = try decode(Self.fixture)
        let first = try XCTUnwrap(report.connections.first)
        XCTAssertTrue(first.action)
        XCTAssertEqual(report.labels(for: first), ["Weather where you are", "Calendar", "Family"])
        XCTAssertEqual(report.labels(for: .init(text: "x", factors: ["mystery"])), ["mystery"])
    }

    // MARK: - Paths, days and links

    func testThePathAsksForADayOnlyWhenItIsOne() {
        XCTAssertEqual(NativeBriefing.path(), "api/native/briefing")
        XCTAssertEqual(NativeBriefing.path(day: "2026-10-27"), "api/native/briefing?day=2026-10-27")
        XCTAssertEqual(NativeBriefing.path(day: "27/10/2026"), "api/native/briefing")
        XCTAssertEqual(NativeBriefing.path(day: "2026-10-27&x=1"), "api/native/briefing")
    }

    func testTheDayPickerSaysTheDayShort() {
        XCTAssertEqual(NativeBriefing.shortLabel("2026-10-28"), "Wed 28 Oct")
        XCTAssertEqual(NativeBriefing.shortLabel("2026-11-01"), "Sun 1 Nov")
        XCTAssertEqual(NativeBriefing.shortLabel("soon"), "soon")
    }

    func testLinksResolveAgainstTheSite() {
        XCTAssertEqual(BriefingLinks.resolve("/jkai/weather")?.absoluteString, "https://strangeramblings.com/jkai/weather")
        XCTAssertEqual(BriefingLinks.resolve("https://www.bbc.co.uk/news/1")?.absoluteString, "https://www.bbc.co.uk/news/1")
        XCTAssertNil(BriefingLinks.resolve("javascript:alert(1)"))
        XCTAssertNil(BriefingLinks.resolve("//evil.example/x"))
        XCTAssertNil(BriefingLinks.resolve("jkai/weather"))
        XCTAssertNil(BriefingLinks.resolve(""))
        XCTAssertNil(BriefingLinks.resolve(nil))
    }

    // MARK: - Fixture

    /// A record as SR-Main sends it (contract §3), with all nineteen factors.
    static let fixture = #"""
{
 "day": "2026-10-28",
 "title": "Briefing — Wed 28 Oct",
 "dateLabel": "Wednesday 28 October",
 "generatedAt": "2026-10-28T07:00:12.000Z",
 "headline": "Rain at four, and the school run",
 "markdown": "**Good morning.** Rain arrives at 16:00.\n\n- Take the umbrella\n- [Weather](/jkai/weather)",
 "verified": true,
 "mode": "weekday",
 "factors": [
  {
   "key": "location",
   "n": 1,
   "label": "Where you are",
   "group": "Place",
   "icon": "location.fill",
   "status": "ok",
   "headline": "Where you are line",
   "salience": 50,
   "facts": [],
   "detail": "Where you are ledger"
  },
  {
   "key": "weather-here",
   "n": 2,
   "label": "Weather where you are",
   "group": "Place",
   "icon": "cloud.sun.fill",
   "status": "ok",
   "headline": "Weather where you are line",
   "salience": 72,
   "facts": [
    {
     "label": "Now",
     "value": "14°C, light rain",
     "assessment": "Umbrella by 16:00"
    },
    {
     "label": "Forecast",
     "value": "Clears at 18:00",
     "href": "/jkai/weather",
     "action": true
    }
   ],
   "detail": "Weather where you are ledger"
  },
  {
   "key": "weather-home",
   "n": 3,
   "label": "Weather at home",
   "group": "Place",
   "icon": "house.fill",
   "status": "ok",
   "headline": "Weather at home line",
   "salience": 50,
   "facts": [],
   "detail": "Weather at home ledger"
  },
  {
   "key": "air",
   "n": 4,
   "label": "Air quality",
   "group": "Place",
   "icon": "aqi.medium",
   "status": "stale",
   "headline": "Air quality line",
   "salience": 50,
   "facts": [],
   "detail": "Last reading 9 hours ago"
  },
  {
   "key": "daylight",
   "n": 5,
   "label": "Daylight",
   "group": "Place",
   "icon": "sunrise.fill",
   "status": "ok",
   "headline": "Daylight line",
   "salience": 50,
   "facts": [],
   "detail": "Daylight ledger"
  },
  {
   "key": "trip",
   "n": 6,
   "label": "Trip",
   "group": "Place",
   "icon": "suitcase.rolling.fill",
   "status": "off",
   "headline": "",
   "salience": 50,
   "facts": [],
   "detail": "No trip in the next 14 days"
  },
  {
   "key": "sleep",
   "n": 7,
   "label": "Sleep",
   "group": "Body",
   "icon": "bed.double.fill",
   "status": "ok",
   "headline": "Sleep line",
   "salience": 50,
   "facts": [],
   "detail": "Sleep ledger"
  },
  {
   "key": "readiness",
   "n": 8,
   "label": "Readiness",
   "group": "Body",
   "icon": "gauge.with.dots.needle.67percent",
   "status": "ok",
   "headline": "Readiness line",
   "salience": 50,
   "facts": [],
   "detail": "Readiness ledger"
  },
  {
   "key": "activity",
   "n": 9,
   "label": "Activity",
   "group": "Body",
   "icon": "figure.walk",
   "status": "ok",
   "headline": "Activity line",
   "salience": 50,
   "facts": [],
   "detail": "Activity ledger"
  },
  {
   "key": "calendar",
   "n": 10,
   "label": "Calendar",
   "group": "Day",
   "icon": "calendar",
   "status": "ok",
   "headline": "Calendar line",
   "salience": 50,
   "facts": [],
   "detail": "Calendar ledger"
  },
  {
   "key": "email",
   "n": 11,
   "label": "Email",
   "group": "Day",
   "icon": "envelope.fill",
   "status": "ok",
   "headline": "Email line",
   "salience": 50,
   "facts": [],
   "detail": "Email ledger"
  },
  {
   "key": "todos",
   "n": 12,
   "label": "To-dos",
   "group": "Day",
   "icon": "checklist",
   "status": "failed",
   "headline": "",
   "salience": 50,
   "facts": [],
   "detail": "Todo source timed out"
  },
  {
   "key": "family",
   "n": 13,
   "label": "Family",
   "group": "Home & family",
   "icon": "person.3.fill",
   "status": "ok",
   "headline": "Family line",
   "salience": 50,
   "facts": [],
   "detail": "Family ledger"
  },
  {
   "key": "house",
   "n": 14,
   "label": "House",
   "group": "Home & family",
   "icon": "house.lodge.fill",
   "status": "ok",
   "headline": "House line",
   "salience": 50,
   "facts": [],
   "detail": "House ledger"
  },
  {
   "key": "news",
   "n": 15,
   "label": "News",
   "group": "Intelligence",
   "icon": "newspaper.fill",
   "status": "ok",
   "headline": "News line",
   "salience": 50,
   "facts": [
    {
     "label": "Top story",
     "value": "Budget leaks",
     "href": "https://www.bbc.co.uk/news/1",
     "assessment": null
    }
   ],
   "detail": "News ledger"
  },
  {
   "key": "policy",
   "n": 16,
   "label": "Policy",
   "group": "Intelligence",
   "icon": "building.columns.fill",
   "status": "ok",
   "headline": "Policy line",
   "salience": 50,
   "facts": [],
   "detail": "Policy ledger"
  },
  {
   "key": "local",
   "n": 17,
   "label": "Local",
   "group": "Intelligence",
   "icon": "mappin.and.ellipse",
   "status": "empty",
   "headline": "",
   "salience": 50,
   "facts": [],
   "detail": "Nothing local overnight"
  },
  {
   "key": "intel",
   "n": 18,
   "label": "Intel",
   "group": "Intelligence",
   "icon": "brain.head.profile",
   "status": "ok",
   "headline": "Intel line",
   "salience": 50,
   "facts": [],
   "detail": "Intel ledger"
  },
  {
   "key": "systems",
   "n": 19,
   "label": "Systems",
   "group": "Systems",
   "icon": "server.rack",
   "status": "ok",
   "headline": "Systems line",
   "salience": 50,
   "facts": [],
   "detail": "Systems ledger"
  }
 ],
 "connections": [
  {
   "text": "Rain at 16:00 lands on the school run",
   "factors": [
    "weather-here",
    "calendar",
    "family"
   ],
   "salience": 81,
   "action": true
  },
  {
   "text": "Short sleep and a long diary",
   "factors": [
    "sleep",
    "calendar"
   ],
   "salience": 40
  }
 ],
 "gaps": [
  {
   "section": "todos",
   "reason": "timed out"
  }
 ],
 "daydreamsText": "Two notes to decide.",
 "pageUrl": "https://strangeramblings.com/jkai/daydreams/briefing/2026-10-28",
 "days": [
  "2026-10-28",
  "2026-10-27",
  "2026-10-26"
 ]
}
"""#
}

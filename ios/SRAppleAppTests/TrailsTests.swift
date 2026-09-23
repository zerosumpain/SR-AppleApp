import XCTest
import SwiftUI
import UIKit
@testable import SRAppleApp

/// Samples of the four `/api/native/health/*` answers, in the contract's shape.
///
/// Written out by hand from the contract rather than captured, so each one
/// exercises the awkward parts on purpose: a colon in an id, nulls where the
/// contract says nullable, a part-kilometre last split, a best effort.
///
/// SYNTHETIC. This repository is public: no real route, id or segment name goes
/// in here. The route is a made-up loop somewhere the owner does not run.
enum TrailSamples {
    static let activities = """
    {
      "activities": [
        {
          "id": "apple:6F1C2A9E-1B2C-4D5E-8F90-ABCDEF012345",
          "name": "Morning park loop",
          "activityType": "run",
          "startDate": "2026-09-22T06:12:00.000Z",
          "startDateLocal": "2026-09-22 07:12:00 +0100",
          "distanceM": 7423.4,
          "durationS": 2533,
          "movingS": 2470,
          "elevationGainM": 58.2,
          "avgHeartrate": 148.6,
          "paceSPerKm": 332.7,
          "energyKcal": 512,
          "hasTrack": true,
          "segmentCount": 3,
          "highlight": { "label": "2nd best", "detail": "heron.slate.ridge, 4:12" }
        },
        {
          "id": "strava:1234567",
          "name": "Evening ride",
          "activityType": "ride",
          "startDate": "2026-09-20T17:30:00.000Z",
          "startDateLocal": "2026-09-20T18:30:00",
          "distanceM": 32180,
          "durationS": 4210,
          "movingS": null,
          "elevationGainM": 310,
          "avgHeartrate": null,
          "paceSPerKm": 130.9,
          "energyKcal": null,
          "hasTrack": false,
          "segmentCount": 0,
          "highlight": null
        }
      ],
      "nextBefore": "2026-09-20T17:30:00.000Z"
    }
    """

    static let activity = """
    {
      "activity": {
        "id": "apple:6F1C2A9E-1B2C-4D5E-8F90-ABCDEF012345",
        "name": "Morning park loop",
        "activityType": "run",
        "startDate": "2026-09-22T06:12:00.000Z",
        "startDateLocal": "2026-09-22 07:12:00 +0100",
        "distanceM": 7423.4, "durationS": 2533, "movingS": 2470,
        "elevationGainM": 58.2, "avgHeartrate": 148.6, "paceSPerKm": 332.7,
        "energyKcal": 512, "hasTrack": true, "segmentCount": 2,
        "highlight": { "label": "2nd best", "detail": "heron.slate.ridge, 4:12" },
        "maxHeartrate": 171, "avgCadence": 168, "elevationLossM": 55.1,
        "temperatureC": 12.5, "timezone": "America/New_York", "source": "apple",
        "route": [[40.7680, -73.9810], [40.7712, -73.9790], [40.7745, -73.9760], [40.7790, -73.9700], [40.7830, -73.9650], [40.7812, -73.9610], [40.7760, -73.9640]],
        "bounds": { "n": 40.7830, "s": 40.7680, "e": -73.9610, "w": -73.9810 },
        "elevation": [
          { "d": 0, "e": 12 }, { "d": 1000, "e": 18 }, { "d": 2000, "e": 31 }, { "d": 3000, "e": 44 },
          { "d": 4000, "e": 38 }, { "d": 5000, "e": 25 }, { "d": 6000, "e": 16 }, { "d": 7423, "e": 13 }
        ],
        "heartRate": [
          { "t": 0, "v": 102 }, { "t": 300, "v": 138 }, { "t": 600, "v": 146 }, { "t": 900, "v": 151 },
          { "t": 1200, "v": 158 }, { "t": 1500, "v": 162 }, { "t": 1800, "v": 149 }, { "t": 2100, "v": 155 },
          { "t": 2400, "v": 171 }
        ],
        "splits": [
          { "index": 1, "distanceM": 1000, "durationS": 338, "paceSPerKm": 338, "elevationGainM": 6 },
          { "index": 2, "distanceM": 1000, "durationS": 331, "paceSPerKm": 331, "elevationGainM": 13 },
          { "index": 3, "distanceM": 1000, "durationS": 344, "paceSPerKm": 344, "elevationGainM": 14 },
          { "index": 4, "distanceM": 1000, "durationS": 319, "paceSPerKm": 319, "elevationGainM": 2 },
          { "index": 5, "distanceM": 1000, "durationS": 326, "paceSPerKm": 326, "elevationGainM": 0 },
          { "index": 6, "distanceM": 1000, "durationS": 335, "paceSPerKm": 335, "elevationGainM": 1 },
          { "index": 7, "distanceM": 1000, "durationS": 329, "paceSPerKm": 329, "elevationGainM": 0 },
          { "index": 8, "distanceM": 423, "durationS": 148, "paceSPerKm": 349.9, "elevationGainM": null }
        ]
      },
      "physio": {
        "trimp": 96.4, "efficiencyFactor": 1.37, "decouplingPct": 4.2, "hrr60": 31,
        "zones": [
          { "zone": 0, "seconds": 90 }, { "zone": 1, "seconds": 310 }, { "zone": 2, "seconds": 880 },
          { "zone": 3, "seconds": 820 }, { "zone": 4, "seconds": 330 }, { "zone": 5, "seconds": 40 }
        ]
      },
      "highlights": [
        { "label": "2nd best", "detail": "heron.slate.ridge, 4:12 — 6 seconds off your best" },
        { "label": "Fastest km this month", "detail": "Kilometre 4 in 5:19" }
      ],
      "segments": [
        { "segmentId": 41, "name": "heron.slate.ridge", "descriptor": "0.9 km at 4.1%", "distanceM": 910,
          "durationS": 252, "paceSPerKm": 276.9, "avgHeartrate": 161, "rankByTime": 2, "rankedByTimeOf": 7, "effortCount": 7 },
        { "segmentId": 57, "name": "wren.amber.causeway", "descriptor": "0.4 km, flat", "distanceM": 402,
          "durationS": 101, "paceSPerKm": 251.2, "avgHeartrate": 158, "rankByTime": 1, "rankedByTimeOf": 4, "effortCount": 4 }
      ]
    }
    """

    static let segments = """
    {
      "segments": [
        {
          "id": 41, "name": "heron.slate.ridge", "descriptor": "0.9 km at 4.1%", "activityType": "run",
          "distanceM": 910, "elevationGainM": 37.4, "gradientPct": 4.1, "terrain": "climb",
          "effortCount": 7, "lastEffortAt": "2026-09-22T06:30:00.000Z",
          "bestDurationS": 246, "bestPaceSPerKm": 270.3,
          "form": { "direction": "improving", "deltaPct": -3.2, "daysSincePb": 41, "spark": [270, 266, 259, 262, 255, 252] }
        },
        {
          "id": 57, "name": "wren.amber.causeway", "descriptor": "0.4 km, flat", "activityType": "run",
          "distanceM": 402, "elevationGainM": 0.5, "gradientPct": 0.1, "terrain": "flat",
          "effortCount": 4, "lastEffortAt": null, "bestDurationS": null, "bestPaceSPerKm": null,
          "form": null
        }
      ]
    }
    """

    static let segment = """
    {
      "segment": {
        "id": 41, "name": "heron.slate.ridge", "descriptor": "0.9 km at 4.1%", "activityType": "run",
        "distanceM": 910, "elevationGainM": 37.4, "gradientPct": 4.1, "terrain": "climb",
        "effortCount": 3, "lastEffortAt": "2026-09-22T06:30:00.000Z",
        "bestDurationS": 246, "bestPaceSPerKm": 270.3,
        "form": { "direction": "improving", "deltaPct": -3.2, "daysSincePb": 41, "spark": [270, 266, 252] },
        "route": [[40.7712, -73.9790], [40.7745, -73.9760], [40.7790, -73.9700]],
        "elevationLossM": 1.2,
        "conditions": { "meanC": 11.4, "quickestC": 9.0, "slowestC": 17.5 }
      },
      "efforts": [
        { "id": 903, "activityId": "apple:6F1C2A9E-1B2C-4D5E-8F90-ABCDEF012345", "activityName": "Morning park loop",
          "activityType": "run", "startedAt": "2026-09-22T06:30:00.000Z", "durationS": 252, "paceSPerKm": 276.9,
          "avgHeartrate": 161, "efficiencyFactor": 1.41, "isBest": false },
        { "id": 811, "activityId": "strava:998877", "activityName": "Tempo Tuesday",
          "activityType": "run", "startedAt": "2026-08-12T17:05:00.000Z", "durationS": 246, "paceSPerKm": 270.3,
          "avgHeartrate": 166, "efficiencyFactor": null, "isBest": true },
        { "id": 702, "activityId": "strava:887766", "activityName": "Long run",
          "activityType": "run", "startedAt": "2026-06-30T08:10:00.000Z", "durationS": 270, "paceSPerKm": 296.7,
          "avgHeartrate": 152, "efficiencyFactor": 1.33, "isBest": false }
      ]
    }
    """

    static func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

/// Decoding each endpoint's contract, including the tolerance: a missing
/// optional array must cost its section, never the whole screen.
final class TrailDecodingTests: XCTestCase {

    func testTheActivitiesPageDecodes() throws {
        let page: ActivitiesPage = try TrailSamples.decode(TrailSamples.activities)
        XCTAssertEqual(page.activities.count, 2)
        XCTAssertEqual(page.nextBefore, "2026-09-20T17:30:00.000Z")

        let run = page.activities[0]
        XCTAssertEqual(run.id, "apple:6F1C2A9E-1B2C-4D5E-8F90-ABCDEF012345")
        XCTAssertEqual(run.segmentCount, 3)
        XCTAssertEqual(run.highlight?.label, "2nd best")
        XCTAssertEqual(run.timeS, 2470, "moving time wins over elapsed when the source measured it")

        let ride = page.activities[1]
        XCTAssertNil(ride.movingS)
        XCTAssertNil(ride.avgHeartrate)
        XCTAssertNil(ride.highlight)
        XCTAssertEqual(ride.timeS, 4210)
    }

    func testTheActivityDetailDecodesEverySection() throws {
        let detail: ActivityDetailResponse = try TrailSamples.decode(TrailSamples.activity)
        XCTAssertEqual(detail.activity.row.name, "Morning park loop")
        XCTAssertEqual(detail.activity.route.count, 7)
        XCTAssertEqual(detail.activity.route.first?.latitude ?? 0, 40.7680, accuracy: 0.0001)
        XCTAssertEqual(detail.activity.elevation.count, 8)
        XCTAssertEqual(detail.activity.heartRate.count, 9)
        XCTAssertEqual(detail.activity.splits.count, 8)
        XCTAssertNil(detail.activity.splits.last?.elevationGainM)
        XCTAssertEqual(detail.physio?.zones.count, 6)
        XCTAssertEqual(detail.highlights.count, 2)
        XCTAssertEqual(detail.segments.map(\.segmentId), [41, 57])
        XCTAssertEqual(detail.segments[0].rankLine, "2nd of 7")
        XCTAssertEqual(detail.segments[1].rankLine, "PB")
    }

    func testAnActivityWithNoTrackAndNoEnrichmentsStillDecodes() throws {
        // The bare minimum a server could send: no route, no series, no physio,
        // no arrays at all. Every section is simply absent.
        let json = """
        { "activity": { "id": "apple:X", "name": "Treadmill", "activityType": "workout",
                        "startDate": "2026-09-21T10:00:00.000Z", "durationS": 1800 },
          "physio": null }
        """
        let detail: ActivityDetailResponse = try TrailSamples.decode(json)
        XCTAssertTrue(detail.activity.route.isEmpty)
        XCTAssertTrue(detail.activity.elevation.isEmpty)
        XCTAssertTrue(detail.activity.splits.isEmpty)
        XCTAssertNil(detail.physio)
        XCTAssertTrue(detail.highlights.isEmpty)
        XCTAssertTrue(detail.segments.isEmpty)
        XCTAssertFalse(detail.activity.row.hasTrack)
    }

    func testAMalformedRoutePointIsDroppedNotDrawnToNullIsland() {
        let coordinates = ActivityDetail.coordinates([[40.77, -73.97], [], [999, 0], [40.78, -73.96]])
        XCTAssertEqual(coordinates.count, 2)
    }

    func testTheSegmentsListDecodes() throws {
        let page: SegmentsPage = try TrailSamples.decode(TrailSamples.segments)
        XCTAssertEqual(page.segments.count, 2)
        XCTAssertEqual(page.segments[0].form?.direction, "improving")
        XCTAssertEqual(page.segments[0].form?.spark.count, 6)
        XCTAssertTrue(page.segments[0].form?.improving ?? false)
        XCTAssertNil(page.segments[1].form)
        XCTAssertNil(page.segments[1].bestDurationS)
        XCTAssertNil(page.segments[1].lastEffortAt)
    }

    func testTheSegmentDetailDecodes() throws {
        let detail: SegmentDetailResponse = try TrailSamples.decode(TrailSamples.segment)
        XCTAssertEqual(detail.segment.row.id, 41)
        XCTAssertEqual(detail.segment.route.count, 3)
        XCTAssertEqual(detail.segment.conditions?.meanC ?? 0, 11.4, accuracy: 0.01)
        XCTAssertEqual(detail.efforts.count, 3)
        XCTAssertEqual(detail.efforts.filter(\.isBest).map(\.id), [811])
        XCTAssertNil(detail.efforts[1].efficiencyFactor)
    }

    func testAnEmptyAnswerIsAnEmptyListNotAFailure() throws {
        let activities: ActivitiesPage = try TrailSamples.decode("{}")
        XCTAssertTrue(activities.activities.isEmpty)
        XCTAssertNil(activities.nextBefore)
        let segments: SegmentsPage = try TrailSamples.decode(#"{ "segments": null }"#)
        XCTAssertTrue(segments.segments.isEmpty)
    }
}

/// The words the numbers become. A wrong answer here looks perfectly plausible
/// on a screen, which is why these are asserted rather than eyeballed.
final class TrailFormatTests: XCTestCase {

    func testDistancesCarryOneOrTwoPlaces() {
        XCTAssertEqual(TrailFormat.km(7423.4), "7.42")
        XCTAssertEqual(TrailFormat.km(42195), "42.2")
        XCTAssertEqual(TrailFormat.km(161_000), "161")
        XCTAssertEqual(TrailFormat.km(fromKm: 23.46), "23.5")
    }

    func testDurationsDropAnHourThatIsNotThere() {
        XCTAssertEqual(TrailFormat.duration(2470), "41:10")
        XCTAssertEqual(TrailFormat.duration(3723), "1:02:03")
        XCTAssertEqual(TrailFormat.duration(59.6), "1:00")
        XCTAssertEqual(TrailFormat.duration(0), "0:00")
        XCTAssertEqual(TrailFormat.minutes(80), "1h 20m")
        XCTAssertEqual(TrailFormat.minutes(45), "45m")
    }

    func testPaceRoundsBeforeItSplits() {
        XCTAssertEqual(TrailFormat.pace(332.7), "5:33")
        // 5:59.6 must read 6:00, never 5:60.
        XCTAssertEqual(TrailFormat.pace(359.6), "6:00")
        XCTAssertEqual(TrailFormat.pace(0), "—")
        XCTAssertEqual(TrailFormat.speed(paceSPerKm: 130.9), "27.5")
    }

    func testRanksReadAsEnglish() {
        XCTAssertEqual(TrailFormat.rank(1, of: 7), "PB")
        XCTAssertEqual(TrailFormat.rank(2, of: 7), "2nd of 7")
        XCTAssertEqual(TrailFormat.rank(3, of: 12), "3rd of 12")
        XCTAssertEqual(TrailFormat.rank(11, of: 20), "11th of 20")
        XCTAssertEqual(TrailFormat.rank(22, of: 30), "22nd of 30")
        // One effort is not a leaderboard.
        XCTAssertNil(TrailFormat.rank(1, of: 1))
        XCTAssertNil(TrailFormat.rank(nil, of: 7))
    }

    func testASignedPercentUsesATrueMinus() {
        XCTAssertEqual(TrailFormat.signedPercent(-3.24), "−3.2%")
        XCTAssertEqual(TrailFormat.signedPercent(1), "+1.0%")
        XCTAssertEqual(TrailFormat.signedPercent(-0.01), "0.0%")
    }

    func testTheLocalDateIsReadNotRezoned() {
        // An evening run recorded at 23:40 local must stay on its own day
        // whatever zone the phone is in now.
        XCTAssertEqual(TrailFormat.date(local: "2026-09-22 23:40:00 +0100", iso: "2026-09-22T22:40:00.000Z"), "22 Sep 2026, 23:40")
        XCTAssertEqual(TrailFormat.date(local: "2026-01-03T07:05:00", iso: ""), "3 Jan 2026, 07:05")
    }

    func testBothSpellingsOfASportAreRead() {
        XCTAssertEqual(Sport.label("run"), "Run")
        XCTAssertEqual(Sport.label("Running"), "Run")
        XCTAssertEqual(Sport.label("trail_run"), "Trail run")
        XCTAssertEqual(Sport.label("ride"), "Ride")
        XCTAssertEqual(Sport.label("Cycling"), "Ride")
        XCTAssertEqual(Sport.label("workout"), "Workout")
        XCTAssertEqual(Sport.label("yoga_flow"), "Yoga Flow")
        XCTAssertTrue(Sport.isPace("walk"))
        XCTAssertFalse(Sport.isPace("ride"))
        XCTAssertEqual(Sport.icon("hike"), "figure.hiking")
        XCTAssertEqual(Sport.icon("something_new"), "figure.mixed.cardio")
    }

    func testTheSummaryLineChoosesPaceOrSpeedBySport() throws {
        let page: ActivitiesPage = try TrailSamples.decode(TrailSamples.activities)
        XCTAssertEqual(page.activities[0].summaryLine, "7.42 km · 41:10 · 5:33 /km · ↑58 m")
        XCTAssertEqual(page.activities[1].summaryLine, "32.2 km · 1:10:10 · 27.5 km/h · ↑310 m")
    }

    func testTheHeroLightsOneFigure() throws {
        let detail: ActivityDetailResponse = try TrailSamples.decode(TrailSamples.activity)
        let figures = ActivityHero.figures(detail.activity.row)
        XCTAssertEqual(figures.map(\.label), ["Distance", "Moving", "Pace", "Climb", "Avg HR", "Energy"])
        XCTAssertEqual(figures.filter(\.lit).count, 1)
        XCTAssertEqual(ActivityHero.sourceLabel("apple", id: "x"), "Apple Health")
        XCTAssertEqual(ActivityHero.sourceLabel(nil, id: "strava:1"), "Strava")
    }
}

/// An activity id carries a colon, and it must arrive at the server escaped
/// exactly once.
final class TrailPathTests: XCTestCase {

    func testAnActivityIdIsEscapedIntoThePath() {
        XCTAssertEqual(
            TrailPath.activity("apple:6F1C-2A9E"),
            "api/native/health/activities/apple%3A6F1C-2A9E"
        )
        XCTAssertEqual(TrailPath.segment(id: 41), "api/native/health/segments/41")
        XCTAssertEqual(
            TrailPath.activities(limit: 30, before: "2026-09-20T17:30:00.000Z"),
            "api/native/health/activities?limit=30&before=2026-09-20T17%3A30%3A00.000Z"
        )
    }

    @MainActor func testTheEscapedPathIsNotEscapedAgain() throws {
        let url = try SiteClient.shared.url(for: TrailPath.activity("apple:ABC"))
        XCTAssertTrue(url.absoluteString.hasSuffix("/api/native/health/activities/apple%3AABC"), url.absoluteString)
        XCTAssertFalse(url.absoluteString.contains("%253A"), "the % was escaped a second time: \(url)")
    }

    @MainActor func testAPlainPathStillBuildsAsBefore() throws {
        let url = try SiteClient.shared.url(for: "api/native/health/segments?limit=100")
        XCTAssertEqual(url.path, "/api/native/health/segments")
        XCTAssertEqual(url.query, "limit=100")
    }

    func testAStatusIsKeptOnTheError() {
        XCTAssertEqual(TrailLoad.from(SiteError.status(503, "Health is down")), .unavailable("Health is down"))
        XCTAssertEqual(TrailLoad.from(SiteError.status(404, "Not found")), .missing("Not found"))
        XCTAssertEqual(TrailLoad.from(SiteError.message("odd")), .failed("odd"))
    }
}

/// The new screens, photographed.
///
/// The UI tests run unpaired, so none of these screens can be reached there —
/// and a screenshot is the only instrument that catches a paper token left on
/// an ink band (or a large title that paints nothing). So the bodies are drawn
/// here from the samples above, in a real window, and attached. Not a mock
/// server: the screens' stores are never touched, only the views that render
/// what a store would hand them.
final class TrailSnapshotTests: XCTestCase {

    @MainActor private func snapshot<V: View>(_ view: V, name: String, height: CGFloat = 1800) {
        let host = UIHostingController(rootView:
            NavigationStack { view }
                .environmentObject(Router())
                .preferredColorScheme(.light)
        )
        let frame = CGRect(x: 0, y: 0, width: 393, height: height)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene {
            window = UIWindow(windowScene: scene)
            window.frame = frame
        } else {
            window = UIWindow(frame: frame)
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        // Long enough for layout, fonts and the charts; map tiles may or may
        // not arrive, and the frame is what is being checked.
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))

        // `drawHierarchy`, not `layer.render`: the second crashed CoreGraphics
        // on the segment screen's map layer, and the first draws the whole
        // (taller than the screen) window anyway.
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        window.isHidden = true
        window.rootViewController = nil
    }

    @MainActor func testTheActivityDetail() throws {
        let detail: ActivityDetailResponse = try TrailSamples.decode(TrailSamples.activity)
        snapshot(
            ActivityDetailBody(detail: detail)
                .navigationTitle(detail.activity.row.name)
                .navigationBarTitleDisplayMode(.inline),
            name: "Activity — ink hero, map, charts, splits",
            height: 2600
        )
    }

    @MainActor func testTheSegmentDetail() throws {
        let detail: SegmentDetailResponse = try TrailSamples.decode(TrailSamples.segment)
        snapshot(
            SegmentDetailBody(detail: detail)
                .navigationTitle(detail.segment.row.name)
                .navigationBarTitleDisplayMode(.inline),
            name: "Segment — ink hero, efforts",
            height: 1700
        )
    }

    @MainActor func testTheActivityAndSegmentLists() throws {
        let activities: ActivitiesPage = try TrailSamples.decode(TrailSamples.activities)
        let segments: SegmentsPage = try TrailSamples.decode(TrailSamples.segments)
        snapshot(
            List {
                Section {
                    ForEach(activities.activities) { row in
                        NavigationLink(value: ActivityRef(id: row.id, name: row.name)) { ActivityListRow(row: row) }
                            .srPlainRow()
                    }
                } header: {
                    SRSectionLabel(text: "Recent activities").srPlainRow().padding(.vertical, 6)
                }
                Section {
                    ForEach(segments.segments) { row in
                        NavigationLink(value: SegmentRef(id: row.id, name: row.name)) { SegmentListRow(row: row) }
                            .srPlainRow()
                    }
                } header: {
                    SRSectionLabel(text: "Segments").srPlainRow().padding(.vertical, 6)
                }
            }
            .listStyle(.plain)
            .srPaper()
            .navigationTitle("Activities")
            .navigationBarTitleDisplayMode(.inline),
            name: "Activities and segments — list rows",
            height: 900
        )
    }

    @MainActor func testTheHealthHero() throws {
        let summary: HealthSummary = try TrailSamples.decode(Self.summary)
        let activities: ActivitiesPage = try TrailSamples.decode(TrailSamples.activities)
        snapshot(
            List {
                HealthHero(summary: summary).srInkRow()
                Section {
                    ForEach(activities.activities) { row in
                        NavigationLink(value: ActivityRef(id: row.id, name: row.name)) { ActivityListRow(row: row) }
                            .srPlainRow()
                    }
                } header: {
                    SRSectionLabel(text: "Recent activities").srPlainRow().padding(.vertical, 6)
                }
            }
            .listStyle(.plain)
            .srPaper()
            .navigationTitle("Health")
            .navigationBarTitleDisplayMode(.inline),
            name: "Health — the ink hero band",
            height: 1300
        )
    }

    static let summary = """
    {
      "generatedAt": "2026-09-23T06:00:00.000Z",
      "isMock": false,
      "strap": "Recovered and ready.",
      "readiness": { "score": 78, "label": "Primed", "recommendation": "A quality session is on the cards — sleep and HRV both back above baseline." },
      "figures": [
        { "key": "rhr", "label": "Resting HR", "value": 52, "unit": "bpm", "display": "52", "delta": -2, "deltaDisplay": "−2 vs 7d", "direction": "down", "improving": true, "caption": "7-day mean", "series": [55, 54, 54, 53, 53, 52, 52] },
        { "key": "hrv", "label": "HRV", "value": 61, "unit": "ms", "display": "61", "delta": -4, "deltaDisplay": "−4 vs 7d", "direction": "down", "improving": false, "caption": "7-day mean", "series": [66, 64, 65, 63, 62, 61, 61] },
        { "key": "sleep", "label": "Sleep", "value": 7.4, "unit": "h", "display": "7h 24m", "delta": null, "deltaDisplay": null, "direction": null, "improving": null, "caption": "last night", "series": [6.9, 7.1, 7.8, 6.5, 7.2, 7.0, 7.4] },
        { "key": "steps", "label": "Steps", "value": 9120, "unit": "", "display": "9,120", "delta": 800, "deltaDisplay": "+800 vs 7d", "direction": "up", "improving": true, "caption": "yesterday", "series": [7200, 8100, 10400, 6600, 9900, 8300, 9120] }
      ],
      "week": null,
      "records": [],
      "fingerprint": "sample"
    }
    """
}

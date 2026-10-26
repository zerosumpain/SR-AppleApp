import XCTest
@testable import SRAppleApp

/// The Captures demo fixtures decode against the real models, so the
/// showcase photographs filled screens rather than "didn't load".
final class CaptureDemoTests: XCTestCase {
    private let clock = SRDemoFixtures.DemoClock(now: Date())

    private func reply(_ method: String, _ path: String, body: Data? = nil) throws -> Data {
        let url = try XCTUnwrap(URL(string: "https://strangeramblings.com/\(path)"))
        let answer = SRDemoFixtures.reply(method: method, url: url, body: body)
        XCTAssertEqual(answer.status, 200, path)
        return answer.body
    }

    func testListDecodes() throws {
        let page = try JSONDecoder().decode(CapturePage.self, from: reply("GET", "api/native/captures?limit=30"))
        XCTAssertEqual(page.items.count, 4)
        XCTAssertEqual(page.items.first?.id, "cap_demo_call", "newest first")
    }

    func testEveryDetailDecodes() throws {
        for id in ["cap_demo_park", "cap_demo_idea", "cap_demo_call", "cap_demo_robin"] {
            let capture = try JSONDecoder().decode(Capture.self, from: reply("GET", "api/native/captures/\(id)"))
            XCTAssertEqual(capture.id, id)
        }
        let park = try JSONDecoder().decode(Capture.self, from: reply("GET", "api/native/captures/cap_demo_park"))
        XCTAssertEqual(park.actions.count, 3)
        XCTAssertEqual(park.openActions, 2)
        XCTAssertEqual(park.speaker("S2")?.guess?.name, "Sam")
        XCTAssertEqual(park.actions.first?.params["attendees"], "Sam, Alex")
    }

    func testConfirmingASpeakerShowsTheName() throws {
        let body = try JSONEncoder().encode(CapturePatch(speakers: [.init(label: "S2", confirmed: CaptureSpeakerName(name: "Sam"))]))
        let capture = try JSONDecoder().decode(Capture.self, from: reply("PATCH", "api/native/captures/cap_demo_park", body: body))
        XCTAssertEqual(capture.speaker("S2")?.displayName, "Sam")
    }

    func testSearchEntityAndDecisionDecode() throws {
        let result = try JSONDecoder().decode(CaptureSearchResult.self, from: reply("GET", "api/native/captures/search?q=sam&limit=30"))
        XCTAssertFalse(result.captures.isEmpty)
        XCTAssertFalse(result.entities.isEmpty)
        let entity = try JSONDecoder().decode(CaptureEntityPage.self, from: reply("GET", "api/native/captures/entities/ent_demo_sam"))
        XCTAssertEqual(entity.entity.name, "Sam")
        let decision = try JSONEncoder().encode(CaptureDecision.dismiss)
        let action = try JSONDecoder().decode(CaptureAction.self, from: reply("POST", "api/native/captures/cap_demo_park/actions/act_park_2", body: decision))
        XCTAssertEqual(action.stateValue, .dismissed)
        let made = try JSONDecoder().decode(CaptureCreated.self, from: reply("POST", "api/native/captures", body: Data("{}".utf8)))
        XCTAssertEqual(made.id, "cap_demo_new")
        _ = try reply("PUT", "api/native/captures/cap_demo_new/audio", body: Data([0, 1, 2]))
    }
}

import XCTest
@testable import SRAppleApp

/// Captures: the offline queue's Codable, the wire shapes of the captures
/// CONTRACT, putting words on speakers, finding the owner's voice, and the
/// screenshot deny list.
///
/// Foundation only, so the same file also runs on Linux in
/// `scripts/captures-check.sh`, where there is no Mac to build the app on.
/// The JSON is shaped like SR-Main `$lib/captures/types.ts` (the CONTRACT's
/// `CaptureView`, `CaptureSummary`, `CaptureActionView`), with synthetic
/// names and Central Park for a place.
final class CapturesTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - The offline queue

    private func sample() -> PendingCapture {
        PendingCapture(
            id: "local-1",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_000_125),
            audioFile: "local-1.m4a",
            screenshotFile: "local-1.jpg",
            transcript: "Hello Sam. Hi.",
            turns: [CaptureTurn(speaker: "S1", start: 0, end: 1.2, text: "Hello Sam."),
                    CaptureTurn(speaker: "S2", start: 1.5, end: 2, text: "Hi.")],
            speakerCount: 2,
            ownerSpeaker: "S1",
            ocrText: "Chat with Sam",
            appHint: "WhatsApp",
            place: CapturePlace(lat: 40.7812, lon: -73.9665),
            source: "button"
        )
    }

    func testQueueRoundTrips() throws {
        let file = CaptureQueueFile(items: [sample()])
        let data = try XCTUnwrap(file.encoded())
        let back = CaptureQueueFile.decode(data)
        XCTAssertEqual(back, file)
        XCTAssertEqual(back.items.first?.turns.count, 2)
        XCTAssertEqual(back.items.first?.place?.lat, 40.7812)
    }

    func testQueueRowWithOnlyAnIdDecodesWithDefaults() throws {
        // An older build's row, or a newer field missing: never keyNotFound.
        let row = try decode(PendingCapture.self, #"{"id":"old"}"#)
        XCTAssertEqual(row.id, "old")
        XCTAssertEqual(row.transcript, "")
        XCTAssertEqual(row.turns, [])
        XCTAssertFalse(row.processed)
        XCTAssertEqual(row.processAttempts, 0)
        XCTAssertNil(row.serverId)
        XCTAssertFalse(row.screenDenied)
        XCTAssertEqual(row.source, "app")
        XCTAssertEqual(row.endedAt, row.startedAt)
        XCTAssertEqual(row.stage, .process)
    }

    func testQueueFileKeepsGoodRowsAroundABadOne() throws {
        let goodRow = try XCTUnwrap(String(data: JSONEncoder().encode(sample()), encoding: .utf8))
        let json = #"{"version":1,"items":[{"transcript":"no id"},"#
            + goodRow + #",{"id":"later","futureField":{"x":1},"speakerCount":"two"}]}"#
        let file = CaptureQueueFile.decode(Data(json.utf8))
        XCTAssertEqual(file.items.map(\.id), ["local-1", "later"])
        // A mistyped field takes its default rather than costing the row.
        XCTAssertEqual(file.items[1].speakerCount, 0)
    }

    func testQueueFileThatIsNotJSONIsAnEmptyQueue() {
        XCTAssertEqual(CaptureQueueFile.decode(Data("garbage".utf8)).items, [])
        XCTAssertEqual(CaptureQueueFile.decode(Data(#"{"items":"nope"}"#.utf8)).items, [])
    }

    func testStagesRunInOrder() {
        var row = sample()
        XCTAssertEqual(row.stage, .process)
        row.processed = true
        XCTAssertEqual(row.stage, .create)
        row.serverId = "cap_abc"
        XCTAssertEqual(row.stage, .audio)
        row.audioSent = true
        XCTAssertEqual(row.stage, .screen)
        row.screenSent = true
        XCTAssertEqual(row.stage, .done)
    }

    func testProcessingGivesUpAndSendsAsItIs() {
        var row = sample()
        row.processAttempts = PendingCapture.maxProcessAttempts
        XCTAssertEqual(row.stage, .create)
    }

    func testDeniedScreenshotIsNeverSent() {
        var row = sample()
        row.processed = true
        row.serverId = "cap_abc"
        row.audioSent = true
        row.screenDenied = true
        XCTAssertFalse(row.sendsScreenshot)
        XCTAssertEqual(row.stage, .done)
        let body = row.createRequest()
        XCTAssertFalse(body.screenshot)
        XCTAssertEqual(body.screen?.denied, true)
        XCTAssertEqual(body.screen?.ocrText, "", "a denied screen's words stay on the phone")
        XCTAssertEqual(body.screen?.appHint, "WhatsApp")
    }

    func testCreateRequestMatchesTheContract() throws {
        let body = sample().createRequest()
        let data = try JSONEncoder().encode(body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), [
            "startedAt", "endedAt", "transcript", "turns", "speakerCount", "ownerSpeaker",
            "screen", "place", "audio", "screenshot", "source",
        ])
        XCTAssertEqual(object["speakerCount"] as? Int, 2)
        XCTAssertEqual(object["ownerSpeaker"] as? String, "S1")
        XCTAssertEqual(object["audio"] as? Bool, true)
        XCTAssertEqual(object["screenshot"] as? Bool, true)
        XCTAssertEqual(object["source"] as? String, "button")
        let turns = try XCTUnwrap(object["turns"] as? [[String: Any]])
        XCTAssertEqual(Set(turns[0].keys), ["speaker", "start", "end", "text"])
        XCTAssertNotNil(CaptureClock.parse(try XCTUnwrap(object["startedAt"] as? String)))
        let screen = try XCTUnwrap(object["screen"] as? [String: Any])
        XCTAssertEqual(screen["ocrText"] as? String, "Chat with Sam")
    }

    func testUnknownSourceGoesUpAsApp() {
        var row = sample()
        row.source = "watch"
        XCTAssertEqual(row.createRequest().source, "app")
    }

    func testRetriesBackOff() {
        var row = sample()
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        XCTAssertTrue(row.isDue(now: now))
        row.attempts = 1
        row.lastTriedAt = now.addingTimeInterval(-10)
        XCTAssertFalse(row.isDue(now: now))
        row.lastTriedAt = now.addingTimeInterval(-31)
        XCTAssertTrue(row.isDue(now: now))
        row.attempts = 30
        row.lastTriedAt = now.addingTimeInterval(-3599)
        XCTAssertFalse(row.isDue(now: now))
        row.lastTriedAt = now.addingTimeInterval(-3600)
        XCTAssertTrue(row.isDue(now: now), "never more than an hour")
    }

    // MARK: - The wire

    private let captureExample = """
    {"id":"cap_k3x9","spaceId":"owner","startedAt":"2026-10-26T09:14:03.120Z","endedAt":"2026-10-26T09:18:10Z",
     "durationS":247,"transcript":"Thanks Sam, send me the plan by Friday. Will do.","transcriptSource":"phone",
     "turns":[{"speaker":"S1","start":0,"end":3.4,"text":"Thanks Sam, send me the plan by Friday."},
              {"speaker":"S2","start":3.9,"end":4.6,"text":"Will do."}],
     "speakers":[{"label":"S1","guess":null,"confirmed":null,"isOwner":true},
                 {"label":"S2","guess":{"name":"Sam","entityId":"ent_sam","confidence":0.82,"evidence":["named twice","calendar"]},"confirmed":null,"isOwner":false}],
     "screen":{"app":{"name":"Calendar","confidence":0.7},"summary":"A week view","ocrText":"Mon Tue","corrected":null},
     "place":{"lat":40.7812,"lon":-73.9665},
     "title":"Plan by Friday","summary":"Sam will send the plan.",
     "flow":[{"topic":"The plan","from_s":0,"to_s":4.6,"speakers":["S1","S2"]}],
     "entities":[{"name":"Sam","type":"person","mention":"Thanks Sam"},{"name":"Friday","type":"event","mention":"by Friday"}],
     "status":"ready","error":null,"analysisCostUsd":"0.0041","createdAt":"2026-10-26T09:18:12Z","updatedAt":"2026-10-26T09:18:40Z",
     "audioUrl":"/api/native/captures/cap_k3x9/audio","screenUrl":null,
     "actions":[
       {"id":"act_1","captureId":"cap_k3x9","kind":"calendar","title":"Plan review","detail":null,"who":null,"dueAt":null,
        "params":{"title":"Plan review","start":"2026-10-31T10:00:00Z","attendees":["Sam","Alex"]},"state":"proposed",
        "refKind":null,"refId":null,"error":null,"createdAt":"2026-10-26T09:18:40Z","decidedAt":null},
       {"id":"act_2","captureId":"cap_k3x9","kind":"todo_other","title":"Sam sends the plan","detail":"By Friday","who":"S2",
        "dueAt":"2026-10-31T17:00:00Z","params":{"draft":"Hi Sam"},"state":"done","refKind":"draft","refId":"d1",
        "error":null,"createdAt":"2026-10-26T09:18:40Z","decidedAt":"2026-10-26T09:20:00Z"},
       {"id":"act_3","captureId":"cap_k3x9","kind":"teleport","title":"Unknown kind","params":{"n":3,"ok":true},"state":"proposed"}
     ]}
    """

    func testFullCaptureDecodes() throws {
        let capture = try decode(Capture.self, captureExample)
        XCTAssertEqual(capture.id, "cap_k3x9")
        XCTAssertEqual(capture.statusValue, .ready)
        XCTAssertEqual(capture.durationS, 247)
        XCTAssertNotNil(capture.started)
        XCTAssertEqual(capture.turns.count, 2)
        XCTAssertEqual(capture.speakers.count, 2)
        XCTAssertEqual(capture.speaker("S1")?.displayName, "You")
        XCTAssertEqual(capture.speaker("S2")?.displayName, "Sam?")
        XCTAssertEqual(capture.speaker("S2")?.guess?.confidence, 0.82)
        XCTAssertEqual(capture.speaker("S2")?.guess?.evidence, ["named twice", "calendar"])
        XCTAssertEqual(capture.screen?.appName, "Calendar")
        XCTAssertEqual(capture.screen?.denied, false)
        XCTAssertEqual(capture.place?.lon, -73.9665)
        XCTAssertEqual(capture.flow.first?.fromS, 0)
        XCTAssertEqual(capture.flow.first?.toS, 4.6)
        XCTAssertEqual(capture.flow.first?.speakers, ["S1", "S2"])
        XCTAssertEqual(capture.entities.map(\.type), ["person", "event"])
        XCTAssertEqual(capture.analysisCostUsd ?? 0, 0.0041, accuracy: 1e-9, "numeric arrives as a string")
        XCTAssertEqual(capture.actions.count, 3)
        XCTAssertEqual(capture.openActions, 2)

        let calendar = capture.actions[0]
        XCTAssertEqual(calendar.kindValue, .calendar)
        XCTAssertEqual(calendar.stateValue, .proposed)
        XCTAssertEqual(calendar.params["attendees"], "Sam, Alex")
        XCTAssertEqual(calendar.params["start"], "2026-10-31T10:00:00Z")

        let other = capture.actions[1]
        XCTAssertEqual(other.kindValue, .todoOther)
        XCTAssertEqual(other.stateValue, .done)
        XCTAssertEqual(other.who, "S2")

        let unknown = capture.actions[2]
        XCTAssertNil(unknown.kindValue, "shown, but not approvable")
        XCTAssertEqual(unknown.params["n"], "3")
        XCTAssertEqual(unknown.params["ok"], "true")
    }

    func testSparseCaptureDecodes() throws {
        // Just received: no analysis yet, nulls everywhere.
        let capture = try decode(Capture.self, """
        {"id":"cap_new","startedAt":"2026-10-26T09:14:03Z","endedAt":null,"durationS":null,"transcript":"Remember the milk",
         "turns":[],"speakers":null,"screen":null,"place":null,"title":null,"summary":null,"flow":null,"entities":null,
         "status":"analysing","actions":[]}
        """)
        XCTAssertEqual(capture.statusValue, .analysing)
        XCTAssertEqual(capture.speakers, [])
        XCTAssertEqual(capture.flow, [])
        XCTAssertEqual(capture.shownTurns.count, 1, "the transcript as one speaker's")
        XCTAssertEqual(capture.shownTurns.first?.text, "Remember the milk")
    }

    func testListPageDecodes() throws {
        let page = try decode(CapturePage.self, """
        {"items":[
          {"id":"cap_1","title":"Plan by Friday","startedAt":"2026-10-26T09:14:03Z","durationS":247,"status":"ready",
           "app":"Calendar","speakers":["You","Sam"],"actionsOpen":2,"snippet":"Thanks Sam"},
          {"id":"cap_2","title":"","startedAt":"2026-10-26T08:00:00Z","durationS":null,"status":"weird","speakers":[],"actionsOpen":0,"snippet":""},
          {"title":"no id"}
        ],"next":"2026-10-26T08:00:00Z"}
        """)
        XCTAssertEqual(page.items.map(\.id), ["cap_1", "cap_2"], "a row without an id is dropped alone")
        XCTAssertEqual(page.items[0].app, "Calendar")
        XCTAssertEqual(page.items[0].actionsOpen, 2)
        XCTAssertEqual(page.items[1].statusValue, .received, "an unknown status reads as received")
        XCTAssertEqual(page.next, "2026-10-26T08:00:00Z")
    }

    func testSearchAndEntityPagesDecode() throws {
        let result = try decode(CaptureSearchResult.self, """
        {"captures":[{"id":"cap_1","title":"Plan","startedAt":"2026-10-26T09:14:03Z","durationS":30,"status":"ready",
                      "speakers":["You"],"actionsOpen":0,"snippet":"…the plan…","score":0.91}],
         "entities":[{"id":"ent_sam","name":"Sam","type":"person","captureCount":4}]}
        """)
        XCTAssertEqual(result.captures.first?.score, 0.91)
        XCTAssertEqual(result.entities.first?.captureCount, 4)

        let page = try decode(CaptureEntityPage.self, """
        {"entity":{"id":"ent_sam","name":"Sam","type":"person","summary":"A colleague."},
         "captures":[{"id":"cap_1","title":"Plan","startedAt":"2026-10-26T09:14:03Z","durationS":30,"status":"ready","speakers":[],"actionsOpen":0,"snippet":""}],
         "neighbours":[{"id":"ent_park","name":"Central Park","type":"place","relation":"walks in"}]}
        """)
        XCTAssertEqual(page.entity.name, "Sam")
        XCTAssertEqual(page.entity.summary, "A colleague.")
        XCTAssertEqual(page.captures.count, 1)
        XCTAssertEqual(page.neighbours.first?.relation, "walks in")
    }

    func testCreatedDecodes() throws {
        let made = try decode(CaptureCreated.self, #"{"id":"cap_9","uploadAudio":"/api/native/captures/cap_9/audio"}"#)
        XCTAssertEqual(made.id, "cap_9")
        XCTAssertNil(made.uploadScreen)
    }

    func testDecisionAndPatchEncode() throws {
        let approve = CaptureDecision.approve(params: CaptureParamValue.from(["title": "Review", "attendees": "Sam, Alex"]))
        let approveJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(approve)) as? [String: Any])
        XCTAssertEqual(approveJSON["decision"] as? String, "approve")
        let params = try XCTUnwrap(approveJSON["params"] as? [String: Any])
        XCTAssertEqual(params["attendees"] as? [String], ["Sam", "Alex"])
        XCTAssertEqual(params["title"] as? String, "Review")

        let dismissJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(CaptureDecision.dismiss)) as? [String: Any])
        XCTAssertEqual(dismissJSON["decision"] as? String, "dismiss")

        let patch = CapturePatch(speakers: [.init(label: "S2", confirmed: CaptureSpeakerName(name: "Sam", entityId: "ent_sam"))])
        let patchJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any])
        let speakers = try XCTUnwrap(patchJSON["speakers"] as? [[String: Any]])
        XCTAssertEqual(speakers.first?["label"] as? String, "S2")
        XCTAssertEqual((speakers.first?["confirmed"] as? [String: Any])?["entityId"] as? String, "ent_sam")
        XCTAssertNil(patchJSON["title"], "an unset field is left out, not sent as null")
    }

    func testPathsEscapeValues() {
        XCTAssertEqual(CapturePaths.audio("cap_1"), "api/native/captures/cap_1/audio")
        XCTAssertEqual(CapturePaths.action("cap_1", "act 2"), "api/native/captures/cap_1/actions/act%202")
        let path = CapturePaths.search(CaptureSearchFilters(q: "plan & budget", person: "Sam", app: nil, limit: 20))
        XCTAssertEqual(path, "api/native/captures/search?q=plan%20%26%20budget&person=Sam&limit=20")
        XCTAssertTrue(CapturePaths.list(before: "2026-10-26T08:00:00Z").contains("before=2026-10-26T08%3A00%3A00Z"))
    }

    // MARK: - Words onto speakers

    func testNoDiarizationIsOneSpeaker() {
        let result = CaptureTurns.build(
            words: [.init(text: "Buy", start: 0, end: 0.3), .init(text: "milk.", start: 0.4, end: 0.8)],
            segments: []
        )
        XCTAssertEqual(result.speakerCount, 1)
        XCTAssertEqual(result.turns, [CaptureTurn(speaker: "S1", start: 0, end: 0.8, text: "Buy milk.")])
    }

    func testVoicesAreLabelledInOrderOfFirstSpeech() {
        let segments = [
            CaptureVoiceSegment(speaker: "7", start: 0, end: 2, embedding: [1, 0]),
            CaptureVoiceSegment(speaker: "3", start: 2, end: 4, embedding: [0, 1]),
            CaptureVoiceSegment(speaker: "7", start: 4, end: 6, embedding: [1, 0]),
        ]
        let words: [CaptureTimedText] = [
            .init(text: "Hello", start: 0.2, end: 0.6), .init(text: "there", start: 0.7, end: 1.0),
            .init(text: "Hi", start: 2.3, end: 2.6), .init(text: ",", start: 2.6, end: 2.6),
            .init(text: "Sam", start: 4.2, end: 4.5),
        ]
        let result = CaptureTurns.build(words: words, segments: segments)
        XCTAssertEqual(result.speakerCount, 2)
        XCTAssertEqual(result.turns.map(\.speaker), ["S1", "S2", "S1"])
        XCTAssertEqual(result.turns.map(\.text), ["Hello there", "Hi,", "Sam"])
        XCTAssertEqual(result.centroids["S1"], [1, 0])
        XCTAssertEqual(result.centroids["S2"], [0, 1])
    }

    func testAWordBetweenSegmentsGoesToTheNearestVoice() {
        let segments = [
            CaptureVoiceSegment(speaker: "a", start: 0, end: 1),
            CaptureVoiceSegment(speaker: "b", start: 5, end: 6),
        ]
        XCTAssertEqual(CaptureTurns.voice(for: .init(text: "x", start: 1.2, end: 1.4), in: segments), "a")
        XCTAssertEqual(CaptureTurns.voice(for: .init(text: "y", start: 4.5, end: 4.7), in: segments), "b")
    }

    func testALongPauseStartsANewTurn() {
        let turns = CaptureTurns.join([
            ("S1", .init(text: "One", start: 0, end: 0.5)),
            ("S1", .init(text: "two", start: 10, end: 10.5)),
        ])
        XCTAssertEqual(turns.count, 2)
    }

    // MARK: - The owner's voice

    func testTheNearestVoiceAboveThresholdIsTheOwner() {
        let enrolled: [Float] = [0.9, 0.1, 0.0]
        let centroids: [String: [Float]] = ["S1": [0.1, 0.9, 0.2], "S2": [0.85, 0.15, 0.05]]
        XCTAssertEqual(CaptureOwnerMatch.ownerLabel(enrolled: enrolled, centroids: centroids), "S2")
    }

    func testNobodyIsTheOwnerWhenNoVoiceIsCloseEnough() {
        let enrolled: [Float] = [1, 0, 0]
        XCTAssertNil(CaptureOwnerMatch.ownerLabel(enrolled: enrolled, centroids: ["S1": [0, 1, 0], "S2": [0, 0, 1]]))
    }

    func testTwoVoicesEquallyLikeTheOwnerNamesNeither() {
        let enrolled: [Float] = [1, 1, 0]
        XCTAssertNil(CaptureOwnerMatch.ownerLabel(enrolled: enrolled, centroids: ["S1": [1, 0.98, 0], "S2": [0.98, 1, 0]]))
    }

    func testNoEnrolmentOrMismatchedVectorsNameNobody() {
        XCTAssertNil(CaptureOwnerMatch.ownerLabel(enrolled: [], centroids: ["S1": [1, 0]]))
        XCTAssertNil(CaptureOwnerMatch.ownerLabel(enrolled: [1, 0, 0], centroids: ["S1": [1, 0]]))
        XCTAssertNil(CaptureOwnerMatch.cosine([0, 0], [1, 0]))
    }

    func testASingleVoiceMatchesWithoutARunnerUp() {
        XCTAssertEqual(CaptureOwnerMatch.ownerLabel(enrolled: [1, 0], centroids: ["S1": [0.9, 0.2]]), "S1")
    }

    func testEnrolmentTakesAreAveraged() {
        XCTAssertEqual(CaptureOwnerMatch.average([[1, 0], [0, 1]]), [0.5, 0.5])
        XCTAssertEqual(CaptureOwnerMatch.average([]), [])
        XCTAssertEqual(CaptureOwnerMatch.average([[2, 2], [9]]), [2, 2], "a take of the wrong size is ignored")
    }

    // MARK: - The screenshot deny list

    func testABankOnTheDefaultListIsDenied() {
        let verdict = ScreenshotPolicy.evaluate(ocrText: "Monzo\nBalance £1,204.33\nPots")
        XCTAssertTrue(verdict.denied)
        XCTAssertEqual(verdict.appHint, "Monzo")
        XCTAssertEqual(verdict.reason, "Monzo is on your deny list")
    }

    func testMatchingIsOnWholeWordsAndIgnoresCase() {
        XCTAssertFalse(ScreenshotPolicy.evaluate(ocrText: "otherwise fine", denyList: ["Wise"], sensitive: false).denied)
        XCTAssertTrue(ScreenshotPolicy.evaluate(ocrText: "Sent with WISE today", denyList: ["Wise"], sensitive: false).denied)
        XCTAssertTrue(ScreenshotPolicy.evaluate(ocrText: "Open 1Password.", denyList: ["1Password"], sensitive: false).denied)
        XCTAssertTrue(ScreenshotPolicy.evaluate(ocrText: "first direct app", denyList: ["First Direct"], sensitive: false).denied)
    }

    func testTheOwnersOwnListReplacesTheDefault() {
        XCTAssertFalse(ScreenshotPolicy.evaluate(ocrText: "Monzo", denyList: [], sensitive: false).denied)
        XCTAssertTrue(ScreenshotPolicy.evaluate(ocrText: "Acme Bank login", denyList: ["Acme Bank", "  "], sensitive: false).denied)
    }

    func testSecretShapedWordsAreDenied() {
        let verdict = ScreenshotPolicy.evaluate(ocrText: "WhatsApp\nYour verification code is 123456", denyList: [])
        XCTAssertTrue(verdict.denied)
        XCTAssertEqual(verdict.appHint, "WhatsApp")
        XCTAssertFalse(ScreenshotPolicy.evaluate(ocrText: "Your verification code", denyList: [], sensitive: false).denied)
    }

    func testCardNumbersAreDeniedOnlyWhenTheyPassLuhn() {
        XCTAssertTrue(ScreenshotPolicy.hasCardNumber("Card 4242 4242 4242 4242 exp 12/30"))
        XCTAssertTrue(ScreenshotPolicy.hasCardNumber("4000-0566-5566-5556"))
        XCTAssertFalse(ScreenshotPolicy.hasCardNumber("Order 4242 4242 4242 4241"))
        XCTAssertFalse(ScreenshotPolicy.hasCardNumber("Call 0123 456 7890"))
    }

    func testAnOrdinaryScreenGoesUpWithAHint() {
        let verdict = ScreenshotPolicy.evaluate(ocrText: "Safari\nstrangeramblings.com\nThe news desk")
        XCTAssertFalse(verdict.denied)
        XCTAssertNil(verdict.reason)
        XCTAssertEqual(verdict.appHint, "Safari")
    }
}

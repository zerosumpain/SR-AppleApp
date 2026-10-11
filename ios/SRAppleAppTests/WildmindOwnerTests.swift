import XCTest
@testable import SRAppleApp

/// Talk, Chronicle, Inventions and whispers: the owner lane's decoders, the
/// whisper rules, and the demo lane the showcase photographs.
///
/// The JSON examples are Wildmind's own (its owner-lane contract, W5, as
/// built: real answers from its test server over a synthetic valley), with
/// SR-Main's `"state":"live"` added as the phone receives them. Everything
/// these tests touch is Foundation only, so the same file also runs on Linux
/// in a SwiftPM harness, where there is no Mac to build the app on.
final class WildmindOwnerTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Talk

    private let talkExample = """
    {"state":"live","v":1,"valley":{"seed":51,"generation":3,"day":1,"clock":"Day 1, 17:00"},"entries":[
    {"id":7,"minute":2460,"when":"Day 1, 17:00","who":"main","name":"JKai","kind":"thought","to":null,"toName":null,
     "text":"A raft of reeds would carry us across. I will gather more.","detail":"Goal: Build a reed raft \u{00B7} Mood: eager"},
    {"id":6,"minute":2460,"when":"Day 1, 17:00","who":"main","name":"JKai","kind":"whisper","to":null,"toName":null,
     "text":"And mind the current.","detail":null},
    {"id":5,"minute":2460,"when":"Day 1, 17:00","who":"main","name":"JKai","kind":"whisper","to":null,"toName":null,
     "text":"The reeds could make a raft.","detail":null},
    {"id":3,"minute":2460,"when":"Day 1, 17:00","who":"companion","name":"Wren","kind":"diary","to":null,"toName":null,
     "text":"Wren's diary, day 0: Found reeds that float well. JKai talks to the river.","detail":null},
    {"id":2,"minute":2460,"when":"Day 1, 17:00","who":"companion","name":"Wren","kind":"speech","to":"main","toName":"JKai",
     "text":"Only mist. Come and look at these reeds.","detail":null},
    {"id":1,"minute":2460,"when":"Day 1, 17:00","who":"main","name":"JKai","kind":"speech","to":"companion","toName":"Wren",
     "text":"Is that smoke over the ridge?","detail":null}
    ],"oldestId":1,"latestId":7,"more":false}
    """

    func testTalkExampleDecodes() throws {
        let page = try decode(WildmindTalkPage.self, talkExample)
        XCTAssertFalse(page.offline)
        XCTAssertEqual(page.valley?.seed, 51)
        XCTAssertEqual(page.valley?.generation, 3)
        XCTAssertEqual(page.valley?.clock, "Day 1, 17:00")
        XCTAssertEqual(page.entries.map(\.id), [7, 6, 5, 3, 2, 1])
        XCTAssertEqual(page.oldestId, 1)
        XCTAssertEqual(page.latestId, 7)
        XCTAssertFalse(page.more)

        let thought = page.entries[0]
        XCTAssertEqual(thought.kind, .thought)
        XCTAssertEqual(thought.goal, "Build a reed raft")
        XCTAssertEqual(thought.mood, "eager")
        XCTAssertNil(thought.to)

        let speech = page.entries[5]
        XCTAssertEqual(speech.kind, .speech)
        XCTAssertEqual(speech.to, "companion")
        XCTAssertEqual(speech.toName, "Wren")
        XCTAssertEqual(WildmindTalkWords.speechByline(speech), "JKai \u{2192} Wren \u{00B7} 17:00")

        let diary = page.entries[3]
        XCTAssertEqual(WildmindTalkWords.diaryBody(diary.text), "Found reeds that float well. JKai talks to the river.")
        XCTAssertEqual(WildmindTalkWords.diaryDay(diary.text), 0)
        XCTAssertEqual(WildmindTalkWords.day(diary), 1)
    }

    /// Wildmind's own body, with no SR-Main `state`, reads as live.
    func testTalkWithoutStateIsLive() throws {
        let raw = talkExample.replacingOccurrences(of: #""state":"live","#, with: "")
        let page = try decode(WildmindTalkPage.self, raw)
        XCTAssertFalse(page.offline)
        XCTAssertEqual(page.entries.count, 6)
    }

    func testOfflineDecodesAsOffline() throws {
        let offline = #"{"state":"offline"}"#
        XCTAssertTrue(try decode(WildmindTalkPage.self, offline).offline)
        XCTAssertTrue(try decode(WildmindChronicle.self, offline).offline)
        XCTAssertTrue(try decode(WildmindInventions.self, offline).offline)
        XCTAssertTrue(try decode(WildmindWhispers.self, offline).offline)
        XCTAssertTrue(try decode(WildmindTalkPage.self, offline).entries.isEmpty)
    }

    /// A row with no id or text is dropped; a kind this build has not met is
    /// `unknown`; a null valley is no valley.
    func testTalkToleratesBadRows() throws {
        let raw = """
        {"state":"live","valley":null,"entries":[{"id":9,"kind":"sneeze","text":"Atchoo."},{"kind":"speech","text":"no id"},
        {"id":8,"kind":"speech"},"junk",{"id":"7","kind":"thought","text":"id as a string"},{"id":6,"kind":"diary","text":"Plain.","minute":null}],
        "oldestId":null,"latestId":9,"more":"yes"}
        """
        let page = try decode(WildmindTalkPage.self, raw)
        XCTAssertNil(page.valley)
        XCTAssertEqual(page.entries.map(\.id), [9, 6])
        XCTAssertEqual(page.entries[0].kind, .unknown)
        XCTAssertNil(page.oldestId)
        XCTAssertFalse(page.more)
        XCTAssertEqual(WildmindTalkWords.diaryBody("Plain."), "Plain.")
    }

    func testTalkPathsAndMerge() {
        var filter = WildmindTalkFilter()
        XCTAssertEqual(filter.path(), "api/native/wildmind/talk?limit=60")
        filter.kinds = .whispers
        filter.who = .main
        XCTAssertEqual(filter.path(before: 40, limit: 500), "api/native/wildmind/talk?limit=200&before=40&who=main&kinds=whisper")
        filter = WildmindTalkFilter(kinds: .said, who: .companion)
        XCTAssertEqual(filter.path(since: 12), "api/native/wildmind/talk?limit=60&since=12&who=companion&kinds=speech")
        XCTAssertEqual(WildmindTalkFilter(kinds: .diaries).path(before: 0), "api/native/wildmind/talk?limit=60&kinds=diary")

        let a = WildmindTalkEntry(id: 3, kind: .speech, text: "a")
        let b = WildmindTalkEntry(id: 1, kind: .thought, text: "b")
        let b2 = WildmindTalkEntry(id: 1, kind: .thought, text: "b, again")
        let c = WildmindTalkEntry(id: 7, kind: .whisper, text: "c")
        let merged = WildmindTalkMerge.merge([b, a], [c, b2])
        XCTAssertEqual(merged.map(\.id), [1, 3, 7])
        XCTAssertEqual(merged[0].text, "b, again")
    }

    func testDetailParts() {
        XCTAssertEqual(WildmindTalkEntry.part("Goal", of: "Goal: Find water \u{00B7} Mood: thirsty"), "Find water")
        XCTAssertEqual(WildmindTalkEntry.part("Mood", of: "Goal: Find water \u{00B7} Mood: thirsty"), "thirsty")
        XCTAssertNil(WildmindTalkEntry.part("Mood", of: "Goal: Find water"))
        XCTAssertNil(WildmindTalkEntry.part("Goal", of: nil))
        XCTAssertEqual(WildmindTalkWords.day(of: "Day 24, 17:00"), 24)
        XCTAssertEqual(WildmindTalkWords.time(of: "Day 24, 17:00"), "17:00")
        XCTAssertNil(WildmindTalkWords.day(of: "dawn"))
    }

    // MARK: - Chronicle

    private let chronicleExample = """
    {"state":"live","v":1,"valley":{"seed":51,"generation":3,"day":1,"clock":"Day 1, 17:00"},
    "who":{"id":"companion","name":"Wren","alive":true,"causeOfDeath":null,"persona":"Wren (she/her), 34. Patient, practical and dry-humoured."},
    "now":{"lastThought":"","mood":"uneasy","goal":"Get my bearings",
      "ambitions":[{"text":"Build a boat that holds two","status":"active"}],
      "values":[{"text":"Test before trusting","strength":40,"since":"Day 1, 17:00","kept":1,"broken":0,
                 "rules":[{"effect":"prefer","verb":"experiment","target":"any"}]}],
      "attitudes":[{"subject":"the river","feeling":30,"reason":"It brings reeds down every morning.","since":"Day 1, 17:00"}],
      "people":[{"name":"JKai","set":true,"trust":45,"affection":50,"note":"Talks to rivers, but works hard.","partner":false}]},
    "timeline":[
      {"minute":2460,"day":1,"when":"Day 1, 17:00","kind":"start","icon":"\u{1F331}","text":"Wren's mind woke for the first time."},
      {"minute":1860,"day":1,"when":"Day 1, 07:00","kind":"explore","icon":"\u{1F9ED}","text":"Wren found Long Meadow."},
      {"minute":1860,"day":1,"when":"Day 1, 07:00","kind":"explore","icon":"\u{1F9ED}","text":"Wren found Tuber Hollow."}],
    "diary":[{"day":0,"text":"Found reeds that float well. JKai talks to the river."}]}
    """

    func testChronicleExampleDecodes() throws {
        let chronicle = try decode(WildmindChronicle.self, chronicleExample)
        XCTAssertFalse(chronicle.offline)
        XCTAssertEqual(chronicle.who?.id, "companion")
        XCTAssertEqual(chronicle.who?.name, "Wren")
        XCTAssertEqual(chronicle.who?.alive, true)
        XCTAssertNil(chronicle.who?.causeOfDeath)
        let now = try XCTUnwrap(chronicle.now)
        XCTAssertNil(now.lastThought, "an empty last thought is no thought")
        XCTAssertEqual(now.mood, "uneasy")
        XCTAssertEqual(now.goal, "Get my bearings")
        XCTAssertEqual(now.ambitions.first?.text, "Build a boat that holds two")
        XCTAssertEqual(now.ambitions.first?.isActive, true)
        XCTAssertEqual(now.values.first?.kept, 1)
        XCTAssertEqual(now.attitudes.first?.feeling, 30)
        XCTAssertEqual(now.people.first?.name, "JKai")
        XCTAssertEqual(now.people.first?.partner, false)
        XCTAssertEqual(chronicle.timeline.count, 3)
        XCTAssertEqual(chronicle.timeline[0].kind, "start")
        XCTAssertEqual(chronicle.timeline[1].day, 1)
        XCTAssertEqual(chronicle.kinds, ["explore", "start"])
        XCTAssertEqual(chronicle.diary.first?.day, 0)
    }

    /// SR-Main sends `now: null` when Wildmind's was malformed.
    func testChronicleWithoutNow() throws {
        let raw = #"{"state":"live","valley":{"seed":1},"who":{"id":"main","name":"JKai","alive":false,"causeOfDeath":"cold"},"now":null,"timeline":[{"kind":"x"}],"diary":[]}"#
        let chronicle = try decode(WildmindChronicle.self, raw)
        XCTAssertNil(chronicle.now)
        XCTAssertEqual(chronicle.who?.alive, false)
        XCTAssertEqual(chronicle.who?.causeOfDeath, "cold")
        XCTAssertTrue(chronicle.timeline.isEmpty, "an event with no text is dropped")
    }

    // MARK: - Inventions

    private let inventionsExample = """
    {"state":"live","v":1,"valley":{"seed":51,"generation":3,"day":1,"clock":"Day 1, 17:00"},
    "inventions":[
      {"id":"bark_cord","name":"Bark cord","kind":"material","description":"","inventor":"JKai","day":0,"placed":false,
       "summary":"made at a workstation","notes":[],"rationale":""},
      {"id":"reed_raft","name":"Reed raft","kind":"vehicle","description":"Bundles of reeds lashed into a raft.","inventor":"Wren",
       "day":0,"placed":false,"summary":"made at a workstation","notes":["Speed clamped to what reeds allow."],
       "rationale":"Reeds float; lashed together they carry a person."}],
    "refused":[{"when":"Day 1, 17:00","text":"JKai's idea \u{201C}Stone boat\u{201D} doesn't work out: stone does not float."}]}
    """

    func testInventionsExampleDecodes() throws {
        let reply = try decode(WildmindInventions.self, inventionsExample)
        XCTAssertEqual(reply.inventions.map(\.id), ["bark_cord", "reed_raft"])
        let cord = reply.inventions[0]
        XCTAssertNil(cord.description, "an empty description is none")
        XCTAssertNil(cord.rationale)
        XCTAssertEqual(cord.day, 0)
        XCTAssertEqual(cord.inventor, "JKai")
        let raft = reply.inventions[1]
        XCTAssertEqual(raft.kind, "vehicle")
        XCTAssertEqual(raft.notes, ["Speed clamped to what reeds allow."])
        XCTAssertEqual(raft.rationale, "Reeds float; lashed together they carry a person.")
        XCTAssertFalse(raft.placed)
        XCTAssertEqual(reply.refused.count, 1)
        XCTAssertEqual(reply.refused[0].when, "Day 1, 17:00")
    }

    // MARK: - Whispers

    private let whispersExample = """
    {"state":"live","v":1,"pending":["And mind the current."],"reserveLeftUsd":0.25,"modelAvailable":true,"whispers":[
      {"logId":6,"when":"Day 1, 17:00","text":"And mind the current.","status":"pending","answer":null},
      {"logId":5,"when":"Day 1, 17:00","text":"The reeds could make a raft.","status":"heard",
       "answer":{"logId":7,"when":"Day 1, 17:00","thought":"A raft of reeds would carry us across. I will gather more.",
                 "goal":"Build a reed raft","mood":"eager"}}]}
    """

    func testWhispersExampleDecodes() throws {
        let reply = try decode(WildmindWhispers.self, whispersExample)
        XCTAssertEqual(reply.pending, ["And mind the current."])
        XCTAssertEqual(reply.reserveLeftUsd, 0.25)
        XCTAssertTrue(reply.modelAvailable)
        XCTAssertEqual(reply.whispers.map(\.logId), [6, 5])
        XCTAssertEqual(reply.whispers[0].status, .pending)
        XCTAssertNil(reply.whispers[0].answer)
        let heard = try XCTUnwrap(reply.whisper(5))
        XCTAssertEqual(heard.status, .heard)
        XCTAssertEqual(heard.answer?.logId, 7)
        XCTAssertEqual(heard.answer?.goal, "Build a reed raft")
        XCTAssertEqual(WildmindWhisperWords.status(heard), "JKai heard you")
        XCTAssertEqual(WildmindWhisperWords.status(reply.whispers[0]), "Waiting for JKai to hear it")
        XCTAssertEqual(WildmindWhisperWords.status(nil), "Sent")
    }

    func testWhisperAcceptedDecodes() throws {
        let raw = #"{"v":1,"ok":true,"logId":5,"when":"Day 1, 17:00","pending":["The reeds could make a raft."],"dropped":null,"asleep":false,"modelAvailable":true}"#
        let reply = try decode(WildmindWhisperAccepted.self, raw)
        XCTAssertEqual(reply.logId, 5)
        XCTAssertEqual(reply.pending.count, 1)
        XCTAssertNil(reply.dropped)
        XCTAssertFalse(reply.asleep)
        XCTAssertThrowsError(try decode(WildmindWhisperAccepted.self, #"{"ok":false,"logId":5}"#))
        XCTAssertThrowsError(try decode(WildmindWhisperAccepted.self, #"{"error":"slow-down"}"#))
    }

    func testUnknownStatusAndReadiness() throws {
        let raw = #"{"pending":["a","b"],"modelAvailable":false,"whispers":[{"logId":1,"text":"x","status":"echoed"}]}"#
        let reply = try decode(WildmindWhispers.self, raw)
        XCTAssertEqual(reply.whispers.first?.status, .unknown)
        XCTAssertNotNil(WildmindWhisperWords.readiness(reply, asleep: false))
        XCTAssertEqual(WildmindWhisperWords.readiness(reply, asleep: true), "JKai\u{2019}s asleep, so it\u{2019}ll be heard on waking.")
        XCTAssertNil(WildmindWhisperWords.readiness(WildmindWhispers(), asleep: false))
    }

    // MARK: - The whisper rules

    func testWhisperTextRules() {
        XCTAssertEqual(WildmindWhisperText.clean("  look\n\n  at the reeds \t now "), "look at the reeds now")
        XCTAssertEqual(WildmindWhisperText.clean("bell\u{07}less"), "bellless")
        XCTAssertEqual(WildmindWhisperText.problem("   \n "), .empty)
        XCTAssertNil(WildmindWhisperText.problem(String(repeating: "a", count: 240)))
        XCTAssertEqual(WildmindWhisperText.problem(String(repeating: "a", count: 241)), .tooLong(over: 1))
        // Counted in code points, as Wildmind counts: a flag is two.
        XCTAssertEqual(WildmindWhisperText.count("\u{1F1EC}\u{1F1E7}"), 2)
        XCTAssertNil(WildmindWhisperText.problem(String(repeating: "\u{1F33F}", count: 240)))
    }

    func testFailuresMapFromTheSitesStrings() {
        XCTAssertEqual(WildmindWhisperFailure.from(status: 429, error: "slow-down", retryAfter: 17), .slowDown(retryAfter: 17))
        XCTAssertEqual(WildmindWhisperFailure.from(status: 400, error: "empty", retryAfter: nil), .empty)
        XCTAssertEqual(WildmindWhisperFailure.from(status: 400, error: "too-long", retryAfter: nil), .tooLong)
        XCTAssertEqual(WildmindWhisperFailure.from(status: 400, error: "idempotency-key", retryAfter: nil), .badRequest)
        XCTAssertEqual(WildmindWhisperFailure.from(status: 403, error: "only-jkai", retryAfter: nil), .onlyJkai)
        XCTAssertEqual(WildmindWhisperFailure.from(status: 403, error: "View as is look-only", retryAfter: nil), .refused)
        XCTAssertEqual(WildmindWhisperFailure.from(status: 409, error: "dead", retryAfter: nil), .dead)
        XCTAssertEqual(WildmindWhisperFailure.from(status: 409, error: "halted", retryAfter: nil), .halted)
        XCTAssertEqual(WildmindWhisperFailure.from(status: 409, error: "between-lives", retryAfter: nil), .betweenLives)
        XCTAssertEqual(WildmindWhisperFailure.from(status: 422, error: "key-reused", retryAfter: nil), .keyReused)
        XCTAssertEqual(WildmindWhisperFailure.from(status: 503, error: "offline", retryAfter: nil), .offline)
        XCTAssertEqual(WildmindWhisperFailure.from(status: 404, error: nil, retryAfter: nil), .notOnSite)
        XCTAssertEqual(WildmindWhisperFailure.slowDown(retryAfter: 12).message, "One whisper at a time \u{2014} try again in 12 s.")
        XCTAssertTrue(WildmindWhisperFailure.dead.blocksSending)
        XCTAssertFalse(WildmindWhisperFailure.slowDown(retryAfter: 3).blocksSending)
        // No message is ever empty, and none repeats the site's raw string.
        let all: [WildmindWhisperFailure] = [.slowDown(retryAfter: nil), .empty, .tooLong, .onlyJkai, .dead, .halted, .betweenLives,
                                             .keyReused, .badRequest, .offline, .network, .refused, .expired, .notOnSite, .other("x")]
        for failure in all {
            XCTAssertFalse(failure.message.isEmpty)
            XCTAssertFalse(failure.message.contains("between-lives") || failure.message.contains("slow-down"))
        }
    }

    /// The same words after a failure go with the same key; other words, or
    /// words after a success, get a new one; a 422 retires the key.
    func testWhisperFlowKeysAndRetries() {
        var keys = ["k1", "k2", "k3", "k4"].makeIterator()
        let next = { keys.next()! }
        var flow = WildmindWhisperFlow()
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertNil(flow.begin("   ", now: t0, newKey: next), "nothing to send")
        let first = flow.begin("Try the reeds", now: t0, newKey: next)
        XCTAssertEqual(first?.key, "k1")
        XCTAssertTrue(flow.isSending)
        XCTAssertNil(flow.begin("Try the reeds", now: t0, newKey: next), "one at a time")

        flow.failed(.network, now: t0)
        XCTAssertEqual(flow.failure, .network)
        let retry = flow.begin("Try the reeds ", now: t0, newKey: next)
        XCTAssertEqual(retry?.key, "k1", "a retry of the same words reuses the key")

        flow.failed(.offline, now: t0)
        let changed = flow.begin("Try the reeds by the lake", now: t0, newKey: next)
        XCTAssertEqual(changed?.key, "k2", "other words, a new key")

        flow.failed(.keyReused, now: t0)
        let after422 = flow.begin("Try the reeds by the lake", now: t0, newKey: next)
        XCTAssertEqual(after422?.key, "k3", "a key the site refused is not reused")

        flow.accepted(WildmindWhisperAccepted(logId: 42), now: t0)
        XCTAssertEqual(flow.phase, .sent(logId: 42))
        XCTAssertEqual(flow.sentIds, [42])
        let again = flow.begin("Try the reeds by the lake", now: t0, newKey: next)
        XCTAssertEqual(again?.key, "k4", "an accepted whisper retires its key")
    }

    func testWhisperFlowPollsFastForAMinute() {
        var flow = WildmindWhisperFlow()
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertEqual(flow.pollInterval(now: t0, normal: 15), 15)
        _ = flow.begin("Hello", now: t0, newKey: { "a" })
        XCTAssertEqual(flow.pollInterval(now: t0, normal: 15), 3)
        flow.accepted(WildmindWhisperAccepted(logId: 1), now: t0)
        XCTAssertEqual(flow.pollInterval(now: t0.addingTimeInterval(10), normal: 15), 3)
        XCTAssertTrue(flow.isWatching(now: t0.addingTimeInterval(59)))
        XCTAssertEqual(flow.pollInterval(now: t0.addingTimeInterval(61), normal: 15), 15)
        XCTAssertFalse(flow.isWatching(now: t0.addingTimeInterval(61)))
    }

    func testSlowDownCoolsTheComposer() {
        var flow = WildmindWhisperFlow()
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        _ = flow.begin("Hello", now: t0, newKey: { "a" })
        flow.failed(.slowDown(retryAfter: 20), now: t0)
        XCTAssertFalse(flow.canSend("Hello", blocked: false, now: t0.addingTimeInterval(5)))
        XCTAssertEqual(flow.coolingSeconds(now: t0.addingTimeInterval(5)), 15)
        XCTAssertTrue(flow.canSend("Hello", blocked: false, now: t0.addingTimeInterval(21)))
        XCTAssertFalse(flow.canSend("Hello", blocked: true, now: t0.addingTimeInterval(21)))
        XCTAssertNil(flow.coolingSeconds(now: t0.addingTimeInterval(21)))
        let retry = flow.begin("Hello", now: t0.addingTimeInterval(21), newKey: { "b" })
        XCTAssertEqual(retry?.key, "a", "a 429 was not remembered, so the key is still good")
    }

    // MARK: - The demo lane

    private func demo(_ method: String, _ route: String, _ query: [String: String] = [:], body: String? = nil, now: Date) -> String? {
        WildmindDemoLane.shared.route(method: method, route: route, query: query, body: body.map { Data($0.utf8) }, now: now)
    }

    func testDemoRoutesDecode() throws {
        WildmindDemoLane.shared.reset()
        let now = Date()
        let talk = try decode(WildmindTalkPage.self, try XCTUnwrap(demo("GET", "talk", ["limit": "60"], now: now)))
        XCTAssertFalse(talk.entries.isEmpty)
        XCTAssertEqual(talk.entries.map(\.id), talk.entries.map(\.id).sorted(by: >), "newest first")
        XCTAssertEqual(talk.valley?.day, 5)
        XCTAssertTrue(Set(talk.entries.map(\.kind)).isSuperset(of: [.speech, .thought, .whisper, .diary]))

        for id in ["main", "companion"] {
            let chronicle = try decode(WildmindChronicle.self, try XCTUnwrap(demo("GET", "chronicle", ["id": id], now: now)))
            XCTAssertEqual(chronicle.who?.id, id)
            XCTAssertNotNil(chronicle.now?.goal)
            XCTAssertFalse(chronicle.timeline.isEmpty)
            XCTAssertFalse(chronicle.diary.isEmpty)
        }
        XCTAssertNil(demo("GET", "chronicle", ["id": "stranger"], now: now))

        let inventions = try decode(WildmindInventions.self, try XCTUnwrap(demo("GET", "inventions", now: now)))
        XCTAssertEqual(inventions.inventions.map(\.name), ["Reed basket", "Fire drill"])
        XCTAssertEqual(inventions.refused.count, 3)

        let whispers = try decode(WildmindWhispers.self, try XCTUnwrap(demo("GET", "whispers", now: now)))
        XCTAssertEqual(whispers.whispers.first?.status, .heard)
        XCTAssertNil(demo("GET", "nope", now: now))
        XCTAssertNil(demo("DELETE", "talk", now: now))
    }

    func testDemoTalkPages() throws {
        WildmindDemoLane.shared.reset()
        let now = Date()
        let newest = try decode(WildmindTalkPage.self, try XCTUnwrap(demo("GET", "talk", ["limit": "5"], now: now)))
        XCTAssertEqual(newest.entries.count, 5)
        XCTAssertTrue(newest.more)
        let oldest = try XCTUnwrap(newest.oldestId)
        let older = try decode(WildmindTalkPage.self, try XCTUnwrap(demo("GET", "talk", ["limit": "5", "before": "\(oldest)"], now: now)))
        XCTAssertTrue(older.entries.allSatisfy { $0.id < oldest })
        let since = try decode(WildmindTalkPage.self, try XCTUnwrap(demo("GET", "talk", ["since": "\(oldest)"], now: now)))
        XCTAssertEqual(since.entries.count, 4)
        XCTAssertFalse(since.more)
        let diaries = try decode(WildmindTalkPage.self, try XCTUnwrap(demo("GET", "talk", ["kinds": "diary", "who": "companion"], now: now)))
        XCTAssertTrue(diaries.entries.allSatisfy { $0.kind == .diary && $0.who == "companion" })
        XCTAssertEqual(diaries.entries.count, 1)
    }

    /// A whisper sent in the demo waits, then is heard, and the thought that
    /// heard it turns up in Talk.
    func testDemoWhisperIsHeard() throws {
        WildmindDemoLane.shared.reset()
        let t0 = Date()
        XCTAssertNil(demo("POST", "whisper", body: #"{"text":"   "}"#, now: t0))
        let sent = try decode(WildmindWhisperAccepted.self,
                              try XCTUnwrap(demo("POST", "whisper", body: #"{"text":"Try the reeds\nby the lake"}"#, now: t0)))
        XCTAssertEqual(sent.pending, ["Try the reeds by the lake"])

        let soon = try decode(WildmindWhispers.self, try XCTUnwrap(demo("GET", "whispers", now: t0.addingTimeInterval(1))))
        XCTAssertEqual(soon.whisper(sent.logId)?.status, .pending)
        XCTAssertEqual(soon.pending, ["Try the reeds by the lake"])

        let later = t0.addingTimeInterval(WildmindDemoLane.hearingDelay + 0.5)
        let heard = try decode(WildmindWhispers.self, try XCTUnwrap(demo("GET", "whispers", now: later)))
        let whisper = try XCTUnwrap(heard.whisper(sent.logId))
        XCTAssertEqual(whisper.status, .heard)
        let answerId = try XCTUnwrap(whisper.answer?.logId)
        XCTAssertTrue(heard.pending.isEmpty)

        let talk = try decode(WildmindTalkPage.self, try XCTUnwrap(demo("GET", "talk", ["since": "116"], now: later)))
        XCTAssertEqual(talk.entries.map(\.id), [answerId, sent.logId])
        XCTAssertEqual(talk.entries.last?.kind, .whisper)
        XCTAssertEqual(talk.entries.first?.kind, .thought)
        WildmindDemoLane.shared.reset()
    }
}

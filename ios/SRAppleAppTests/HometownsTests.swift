import XCTest
@testable import SRAppleApp

/// Hometowns: the shared wire fixtures decode, deltas merge onto the frame
/// they were cut against (and refuse any other), the copy grammar formats
/// numbers as the engine does, and the Build trays, the tutorial and the move
/// bodies come out of the wire the way the shell expects.
///
/// `Fixtures/Hometowns/hometowns-*.json` are SR-Main's own frames, written by
/// `npx tsx scripts/hometowns/wire-fixtures.ts <dir>` (bot- and hand-built
/// only, never a production room) and copied here with the `hometowns-`
/// prefix so they cannot collide with another suite's resources. When the
/// wire changes, regenerate and copy rather than edit.
///
/// Every assertion is about SHAPE, merge and formatting, never a balance
/// number: the engine's parameters are tuned on a separate branch, and a test
/// that pinned "283 people" would fail on every retune.
final class HometownsTests: XCTestCase {

    static let fixtures = ["lobby", "founding", "hamlet", "town", "metropolis", "metropolis-delta", "visiting", "deputy"]
    static let whole = ["lobby", "founding", "hamlet", "town", "metropolis", "visiting", "deputy"]
    static let founded = ["hamlet", "town", "metropolis", "visiting", "deputy"]

    private func load(_ name: String) throws -> Data {
        // In the app's test bundle (xcodegen copies the JSON as resources);
        // beside this file when run from a plain checkout.
        if let url = Bundle(for: HometownsTests.self).url(forResource: "hometowns-\(name)", withExtension: "json") {
            return try Data(contentsOf: url)
        }
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return try Data(contentsOf: here.appendingPathComponent("Fixtures/Hometowns/hometowns-\(name).json"))
    }

    private func dict(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: try load(name)) as? [String: Any], name)
    }

    private func wire(_ name: String) throws -> HometownsWire {
        try JSONDecoder().decode(HometownsWire.self, from: try load(name))
    }

    /// The bundled copy file: the app's, or the one beside the sources.
    private func copy() throws -> HometownsCopy {
        if HometownsCopy.shared.has("tier.0") { return HometownsCopy.shared }
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("../SRAppleApp/Games/Hometowns/hometowns-copy-en-GB.json")
        return HometownsCopy(json: try Data(contentsOf: url))
    }

    // MARK: - Decoding

    func testEveryFixtureDecodes() throws {
        for name in Self.fixtures {
            let w = try wire(name)
            XCTAssertFalse(w.id.isEmpty, name)
            XCTAssertGreaterThan(w.rev, 0, name)
            XCTAssertFalse(w.client.engineHash.isEmpty, name)
            XCTAssertTrue(w.client.page.hasPrefix("/projects/hometowns/"), name)
            XCTAssertTrue(w.client.page.hasSuffix("/mobile.html"), name)
            // The folder is the page's own hash (engine and page code), never the engine hash itself.
            let pageHash = try XCTUnwrap(w.client.pageHash, name)
            XCTAssertEqual(w.client.page, "/projects/hometowns/\(pageHash)/mobile.html", name)
            XCTAssertNotEqual(pageHash, w.client.engineHash, "the page is named by its page hash: \(name)")
            XCTAssertNotNil(w.me, "the fixture host has a seat: \(name)")
        }
    }

    func testThePageIsTheWiresPathAndItsFolderIsThePageHash() throws {
        let hashes = try Set(Self.fixtures.map { try XCTUnwrap(wire($0).client.pageHash, $0) })
        XCTAssertEqual(hashes.count, 1, "one server, one page")
        let page = HometownsClient(engineHash: "aaaabbbbccccdddd", page: "/projects/hometowns/0123456789abcdef/mobile.html")
        XCTAssertEqual(page.pageHash, "0123456789abcdef")
        for bad in ["", "/projects/hometowns/aaaabbbbccccdddd", "/projects/hometowns//mobile.html", "/projects/other/0123/mobile.html",
                    "/projects/hometowns/01/23/mobile.html", "https://elsewhere.test/projects/hometowns/0123/mobile.html", "/projects/hometowns/ab%2F/mobile.html"] {
            XCTAssertNil(HometownsClient(page: bad).pageHash, bad)
        }
    }

    func testWholeFramesAreWholeAndTheDeltaIsNot() throws {
        for name in Self.whole {
            XCTAssertNil(try wire(name).base, name)
        }
        XCTAssertNotNil(try wire("metropolis-delta").base)
    }

    func testAFoundedTownHasItsRecordAndALobbyHasNone() throws {
        for name in Self.founded {
            let w = try wire(name)
            let town = try XCTUnwrap(w.town, name)
            XCTAssertFalse(town.name.isEmpty, name)
            XCTAssertGreaterThan(town.population, 0, name)
            XCTAssertEqual(town.people.count, 13, "the 13 person stocks: \(name)")
            XCTAssertEqual(town.happy.count, 10, "happiness by the 10 cohorts: \(name)")
            XCTAssertEqual(town.funding.count, HometownsCatalogue.fundingKeys.count, name)
            XCTAssertEqual(town.taxes.homes.count, 3, name)
            XCTAssertFalse(town.orders.isEmpty, "a town starts with Bramble's orders: \(name)")
            XCTAssertNotNil(w.myCard, "my own public card is listed: \(name)")
            XCTAssertFalse(w.me?.townHash.isEmpty ?? true, "the canary rides every founded frame: \(name)")
        }
        for name in ["lobby", "founding"] {
            let w = try wire(name)
            XCTAssertNil(w.town, name)
            XCTAssertEqual(w.me?.townHash, "", name)
        }
        XCTAssertEqual(try wire("lobby").phase, "lobby")
        XCTAssertEqual(try wire("founding").phase, "running")
        XCTAssertFalse(try wire("founding").freeSites.isEmpty, "a running county with no towns has sites to found on")
    }

    /// The lenient decoders must not have dropped real rows.
    func testNoRowIsLostInTheLenientDecode() throws {
        for name in Self.whole {
            let raw = try dict(name)
            let w = try wire(name)
            XCTAssertEqual(w.towns.count, (raw["towns"] as? [Any])?.count ?? 0, name)
            XCTAssertEqual(w.players.count, (raw["players"] as? [Any])?.count ?? 0, name)
            let county = raw["county"] as? [String: Any]
            XCTAssertEqual(w.county?.sites.count, (county?["sites"] as? [Any])?.count, name)
            let me = raw["me"] as? [String: Any]
            let derived = me?["derived"] as? [String: Any]
            XCTAssertEqual(w.me?.derived.wants.count ?? 0, (derived?["wants"] as? [Any])?.count ?? 0, name)
            XCTAssertEqual(w.me?.derived.advisors.count ?? 0, (derived?["advisors"] as? [Any])?.count ?? 0, name)
            XCTAssertEqual(w.me?.derived.needs.count ?? 0, (derived?["needs"] as? [Any])?.count ?? 0, name)
            XCTAssertEqual(w.me?.derived.townTalk.count ?? 0, (derived?["townTalk"] as? [Any])?.count ?? 0, name)
            XCTAssertEqual(w.me?.welcomeBack.count ?? 0, (me?["welcomeBack"] as? [Any])?.count ?? 0, name)
            let town = me?["town"] as? [String: Any]
            XCTAssertEqual(w.town?.orders.count ?? 0, (town?["orders"] as? [Any])?.count ?? 0, name)
            XCTAssertEqual(w.town?.deputyUndo.count ?? 0, (town?["deputyUndo"] as? [Any])?.count ?? 0, name)
        }
    }

    func testTheVisitNamesTheTownBeingVisited() throws {
        let w = try wire("visiting")
        let seat = try XCTUnwrap(w.visitingSeat)
        XCTAssertNotEqual(seat, w.me?.seat, "a visit is to someone else's town")
        XCTAssertTrue(w.towns.contains { $0.seat == seat })
        XCTAssertNil(try wire("hamlet").visitingSeat)
    }

    #if !HOMETOWNS_LOGIC_ONLY
    /// The shared room views (the lobby, "this game has ended") read the same JSON.
    func testTheFrameworkRoomDecodesFromEveryWholeFrame() throws {
        for name in Self.whole {
            let room = try JSONDecoder().decode(GameRoom.self, from: try load(name))
            XCTAssertEqual(room.game, "hometowns", name)
            XCTAssertEqual(room.kind, .hometowns, name)
            XCTAssertFalse(room.players.isEmpty, name)
        }
        XCTAssertEqual(try JSONDecoder().decode(GameRoom.self, from: try load("lobby")).phase, .lobby)
    }

    func testTheDemoCountiesDecodeAsTheShellReadsThem() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let town = try XCTUnwrap(SRDemoFixtures.hometownsRoom(id: SRDemoFixtures.demoHometownsRoom, clock: clock))
        let w = try JSONDecoder().decode(HometownsWire.self, from: Data(town.utf8))
        XCTAssertEqual(w.town?.name, "Sunnyvale")
        XCTAssertFalse(w.me?.derived.advisors.isEmpty ?? true)
        XCTAssertEqual(try JSONDecoder().decode(GameRoom.self, from: Data(town.utf8)).kind, .hometowns)
        let found = try XCTUnwrap(SRDemoFixtures.hometownsRoom(id: SRDemoFixtures.demoHometownsFoundRoom, clock: clock))
        let f = try JSONDecoder().decode(HometownsWire.self, from: Data(found.utf8))
        XCTAssertNil(f.town, "the founding room has no town for Alex yet")
        XCTAssertFalse(f.freeSites.isEmpty)
        // Routed like every other demo room, and listed in "Your games".
        XCTAssertEqual(SRDemoFixtures.demoRoom(id: SRDemoFixtures.demoHometownsRoom, meJoined: true, clock: clock), town)
        let lobby = try JSONDecoder().decode(GamesLobby.self, from: Data(SRDemoFixtures.gamesLobby(clock).utf8))
        XCTAssertEqual(lobby.rooms.filter { $0.game == "hometowns" }.map(\.id),
                       [SRDemoFixtures.demoHometownsRoom, SRDemoFixtures.demoHometownsFoundRoom])
    }

    func testACountysRowSaysHowTheTownIsDoing() {
        let room = GameRoomSummary(id: "g_1", game: "hometowns", phase: .unknown, hostName: "Alex", durable: true, pace: .async,
                                   myTurn: true, waitingFor: ["Alex"], dueAt: 1_790_000_000_000)
        XCTAssertEqual(YourGames.status(room, atServer: 1_789_000_000_000), "Your county · something waiting",
                       "a county has no deadline to count down")
        var told = room
        told.summary = "Sunnyvale · Town · 2,340 people"
        told.myTurn = false
        XCTAssertEqual(YourGames.status(told, atServer: nil), "Sunnyvale · Town · 2,340 people")
        XCTAssertEqual(YourGames.paceLine(told), "A year a day · hosted by Alex")
        let other = GameRoomSummary(id: "g_2", game: "homestead", phase: .playing, hostName: "Sam", durable: true, pace: .async)
        XCTAssertEqual(YourGames.paceLine(other), "Over days · hosted by Sam")
    }

    func testTheLobbyRowReadsTheSummaryLeniently() throws {
        let json = #"{"id":"g_1","game":"hometowns","phase":"running","hostName":"Alex","summary":"  "}"#
        XCTAssertNil(try JSONDecoder().decode(GameRoomSummary.self, from: Data(json.utf8)).summary, "blank reads as none")
    }

    func testTheCreateBodyCarriesTheCountyAndNoPace() throws {
        var body = CreateGameBody(game: GameKind.hometowns.rawValue, difficulty: "easy", invite: [])
        body.county = HometownsCountySetup(name: "Kingsport County", rivalry: "spirited", regionalHour: 17, mishaps: "off")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        let county = try XCTUnwrap(json["county"] as? [String: Any])
        XCTAssertEqual(county["rivalry"] as? String, "spirited")
        XCTAssertEqual(county["regionalHour"] as? Int, 17)
        XCTAssertEqual(county["mishaps"] as? String, "off")
        XCTAssertNil(json["pace"], "a county is always over days: the server sets the pace")
        // Every other game's body is unchanged: no county key.
        let plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(CreateGameBody(difficulty: "easy", invite: []))) as? [String: Any])
        XCTAssertNil(plain["county"])
    }

    func testAnOlderAppStillShowsAnUnknownGame() {
        XCTAssertEqual(GameNames.title("hometowns"), "Hometowns")
        XCTAssertEqual(GameNames.title("some-new-game"), "Some New Game")
        XCTAssertNil(GameKind(rawValue: "some-new-game"))
    }
    #endif

    // MARK: - Merging

    func testTheDeltaMergesOntoTheFrameItWasCutAgainst() throws {
        let held = try dict("metropolis")
        let delta = try dict("metropolis-delta")
        XCTAssertEqual(HometownsFrames.base(delta), HometownsFrames.rev(held))
        let merged = try HometownsFrames.merge(held, delta)
        XCTAssertTrue(merged["base"] is NSNull)
        XCTAssertNil(merged["townsPatch"])
        let w = try XCTUnwrap(HometownsFrames.decode(merged))
        XCTAssertEqual(w.rev, HometownsFrames.rev(delta))
        XCTAssertNil(w.base)
        // The fixture's move: a budget that set Town Tax to 9% (a scripted input, not a balance number).
        XCTAssertEqual(w.town?.taxes.town, 900)
        // What the delta left out came from the held frame.
        let before = try wire("metropolis")
        XCTAssertEqual(w.towns.count, before.towns.count)
        XCTAssertEqual(w.county, before.county)
        XCTAssertEqual(w.town?.name, before.town?.name)
        XCTAssertEqual(w.me?.affordances, before.me?.affordances)
    }

    func testAFrameCutAgainstAnotherRevIsAGap() throws {
        let delta = try dict("metropolis-delta")
        var other = try dict("metropolis")
        other["rev"] = (HometownsFrames.base(delta) ?? 0) + 1
        XCTAssertThrowsError(try HometownsFrames.merge(other, delta)) { error in
            XCTAssertEqual((error as? HometownsFrames.Gap)?.base, HometownsFrames.base(delta))
        }
        XCTAssertThrowsError(try HometownsFrames.merge(nil, delta))
    }

    func testAWholeFrameNeedsNothingHeld() throws {
        let merged = try HometownsFrames.merge(nil, try dict("hamlet"))
        let w = try XCTUnwrap(HometownsFrames.decode(merged))
        XCTAssertEqual(w, try wire("hamlet"))
    }

    func testTheRoomIsReadOutOfEitherEnvelope() throws {
        let frame = try load("hamlet")
        let room = String(decoding: frame, as: UTF8.self)
        let snapshot = Data("{\"room\": \(room)}".utf8)
        let stream = Data("{\"type\": \"room\", \"room\": \(room)}".utf8)
        XCTAssertEqual(HometownsFrames.room(in: snapshot).flatMap(HometownsFrames.rev), HometownsFrames.rev(try dict("hamlet")))
        XCTAssertEqual(HometownsFrames.room(in: stream).flatMap(HometownsFrames.rev), HometownsFrames.rev(try dict("hamlet")))
        XCTAssertNil(HometownsFrames.room(in: Data("{\"type\": \"gone\"}".utf8)))
    }

    // MARK: - Copy

    /// SR-Main's `wire-fixtures.ts` writes the FNV-1a 64 of its copy file
    /// beside the frames: the bundled copy must be byte for byte the site's.
    func testTheBundledCopyIsTheSitesCopy() throws {
        let want = try XCTUnwrap(try dict("copy-hash")["fnv64"] as? String)
        let bundled: Data
        if let url = Bundle.main.url(forResource: "hometowns-copy-en-GB", withExtension: "json") {
            bundled = try Data(contentsOf: url)
        } else {
            let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            bundled = try Data(contentsOf: here.appendingPathComponent("../SRAppleApp/Games/Hometowns/hometowns-copy-en-GB.json"))
        }
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in bundled { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        let got = String(h, radix: 16)
        XCTAssertEqual(String(repeating: "0", count: 16 - got.count) + got, want,
                       "copy SR-Main's engine/copy/en-GB.json over hometowns-copy-en-GB.json, then the fixtures")
    }

    func testNumbersAreFormattedByArithmetic() {
        let N = HometownsNumber.self
        XCTAssertEqual(N.pounds(12345), "£12,345")
        XCTAssertEqual(N.pounds(-300), "−£300")
        XCTAssertEqual(N.pounds(1_400_000), "£1,400,000")
        XCTAssertEqual(N.pounds(1_000_005), "£1,000,005")
        XCTAssertEqual(N.pounds(0), "£0")
        XCTAssertEqual(N.group(1_234_567), "1,234,567")
        XCTAssertEqual(N.group(-1234), "−1,234")
        XCTAssertEqual(N.signed(12), "+12")
        XCTAssertEqual(N.signed(-3), "−3")
        XCTAssertEqual(N.signed(0), "0")
        XCTAssertEqual(N.oneDecimal(2.5), "2.5")
        XCTAssertEqual(N.oneDecimal(3), "3")
        XCTAssertEqual(N.oneDecimal(-0.5), "−0.5")
        // JavaScript rounding: halves go up.
        XCTAssertEqual(N.round(2.5), 3)
        XCTAssertEqual(N.round(-2.5), -2)
        XCTAssertEqual(N.time(ticks: 1, .kid), "a week")
        XCTAssertEqual(N.time(ticks: 8, .kid), "2 months")
        XCTAssertEqual(N.time(ticks: 96, .kid), "2 years")
        XCTAssertEqual(N.time(ticks: 72, .adult), "1.5 years")
        XCTAssertEqual(N.realTime(ms: 20_000), "a moment")
        XCTAssertEqual(N.realTime(ms: 25 * 60_000), "about 25 minutes")
        XCTAssertEqual(N.realTime(ms: 2 * 3_600_000), "about 2 hours")
        XCTAssertEqual(N.realTime(ms: 3 * 86_400_000), "about 3 days")
    }

    func testTheTemplateGrammar() {
        let copy = HometownsCopy(strings: [
            "t": HometownsCopyEntry(kid: "{n:count:home:homes} for {cost:money}, {d:signedMoney}, {s:stars}, {p:pct}, {b:bp}",
                                    adult: "{x:ref:tier} · {who} · {q:signed}"),
            "tier.2": HometownsCopyEntry(kid: "Town", adult: "Town"),
            "less": HometownsCopyEntry(kid: "good", adult: "good", kidLess: "busy"),
        ])
        let data: HometownsData = ["n": .number(1), "cost": .number(1500), "d": .number(-300), "s": .number(72),
                                   "p": .number(0.38), "b": .number(250)]
        XCTAssertEqual(copy.say("t", .kid, data), "1 home for £1,500, −£300, ★3.5, 38%, 2.5%")
        XCTAssertEqual(copy.say("t", .adult, ["x": .number(2), "who": .text("Families"), "q": .number(4)]), "Town · Families · +4")
        // A kid never sees a raw string or an unknown reference.
        XCTAssertEqual(copy.fill("{who} and {x:ref:tier}", .kid, ["who": .text("Typed"), "x": .number(9)]), "something and something")
        XCTAssertEqual(copy.fill("{missing}", .kid), "some")
        XCTAssertEqual(copy.fill("{missing}", .adult), "?")
        XCTAssertEqual(copy.say("less", .kid, sign: -1), "busy")
        XCTAssertEqual(copy.say("less", .adult, sign: -1), "good")
        XCTAssertEqual(copy.say("unknown.key", .kid), "unknown.key")
        XCTAssertEqual(copy.line("advisor.mo.newRule", .kid), "New rule", "a screen never shows a raw key")
        XCTAssertEqual(copy.line("less", .adult, sign: -1), "good")
        XCTAssertEqual(copy.say("less.kid", .adult), "good", "a `.kid` key names its own level")
        // Not a slot: left as written.
        XCTAssertEqual(copy.fill("{not a slot} {}", .adult), "{not a slot} {}")
    }

    func testEverythingAFixtureAsksToSayHasWords() throws {
        let copy = try copy()
        XCTAssertTrue(copy.has("tier.0"), "the copy file is bundled")
        for name in Self.founded {
            let w = try wire(name)
            let me = try XCTUnwrap(w.me)
            for card in me.derived.advisors {
                XCTAssertTrue(copy.has("advisor.\(card.key)"), "advisor.\(card.key) in \(name)")
                XCTAssertTrue(copy.has("advisorName.\(card.advisor)"), card.advisor)
                if let action = card.action { XCTAssertTrue(copy.has("action.\(action)"), "action.\(action)") }
            }
            for want in me.derived.wants { XCTAssertTrue(copy.has("want.\(want.key)"), "want.\(want.key) in \(name)") }
            for talk in me.derived.townTalk { XCTAssertTrue(copy.has("talk.\(talk.key)"), "talk.\(talk.key)") }
            for row in me.derived.needs {
                for item in row.items { XCTAssertTrue(copy.has("need.\(item.key)"), "need.\(item.key)") }
            }
            for order in try XCTUnwrap(w.town).orders { XCTAssertTrue(copy.has("order.\(order.kind)"), order.kind) }
            for card in me.welcomeBack + (w.county?.bulletin ?? []) {
                for level in [HometownsCopyLevel.kid, .adult] {
                    let line = copy.say(card.key, level, card.data)
                    XCTAssertNotEqual(line, card.key, "\(card.key) has copy")
                    XCTAssertFalse(line.contains("{"), "\(card.key) fills every slot: \(line)")
                }
            }
        }
    }

    // MARK: - The shell

    func testTheDate() {
        XCTAssertEqual(HometownsText.date(tick: 0), "Year 1 · January")
        XCTAssertEqual(HometownsText.date(tick: 47), "Year 1 · December")
        XCTAssertEqual(HometownsText.date(tick: 116), "Year 3 · June")
    }

    func testMoneyForAChildIsShort() {
        XCTAssertEqual(HometownsText.money(171_171, .kid), "£171k")
        XCTAssertEqual(HometownsText.money(1_400_000, .kid), "£1.4m")
        XCTAssertEqual(HometownsText.money(950, .kid), "£950")
        XCTAssertEqual(HometownsText.money(171_171, .adult), "£171,171")
        XCTAssertEqual(HometownsText.rate(850), "8.5%")
    }

    func testMoodStaysInRange() throws {
        for name in Self.founded {
            let town = try XCTUnwrap(try wire(name).town)
            let mood = HometownsText.mood(town)
            XCTAssertTrue((0...100).contains(mood), "\(name): \(mood)")
            XCTAssertEqual(HometownsText.faceHappiness(town).count, 5)
        }
    }

    func testTheBuildTraysComeFromTheAffordances() throws {
        let copy = try copy()
        for name in Self.founded {
            let w = try wire(name)
            let me = try XCTUnwrap(w.me)
            let items = HometownsCatalogue.items(me.affordances, town: w.town, copy: copy, level: me.level)
            XCTAssertEqual(Set(items.map(\.id)).count, items.count, "every item once: \(name)")
            XCTAssertTrue(items.allSatisfy { HometownsCatalogue.trays.contains($0.tray) }, name)
            for id in me.affordances.unlocked {
                let item = try XCTUnwrap(items.first { $0.id == id }, "\(id) is offered in \(name)")
                XCTAssertNil(item.locked, "\(id) is unlocked in \(name)")
            }
            for item in items where item.locked == nil && item.tool.kind == "place" {
                XCTAssertNotNil(item.cost, "\(item.id) says what it costs")
            }
            for item in items where item.locked != nil {
                XCTAssertFalse(item.locked!.isEmpty)
                XCTAssertFalse(me.affordances.unlocked.contains(item.id))
            }
            // Painting is always there.
            XCTAssertTrue(items.contains { $0.id == "zone:homes" })
        }
    }

    func testAHamletHasTwoLensesAndAVillageAll() {
        XCTAssertEqual(HometownsCatalogue.lenses(forTier: 0), ["happy", "landValue"])
        XCTAssertEqual(HometownsCatalogue.lenses(forTier: 1).count, 14)
    }

    func testBramblesThreeSteps() {
        var t = HometownsTutorial()
        XCTAssertEqual(t.step, 0)
        t.note([["op": "road", "kind": "lane", "path": [32, 52, 32, 44]]])
        XCTAssertEqual(t.step, 1)
        t.note([["op": "zone", "zone": "homes", "rect": [30, 44, 2, 4]]])
        XCTAssertEqual(t.homes, 8)
        XCTAssertEqual(t.step, 1)
        t.note([["op": "zone", "zone": "homes", "rect": [34, 44, 2, 2]], ["op": "zone", "zone": "farms", "rect": [28, 40, 2, 1]]])
        XCTAssertEqual(t.step, 2)
        t.note([["op": "place", "id": "well", "x": 33, "y": 46, "rot": 0]])
        XCTAssertEqual(t.step, 3)
    }

    // MARK: - Bramble's undo (decision 11)

    /// A Deputy entry as the private town carries it (`UndoEntry`), for the planId rules.
    private func entry(_ planId: String, day: Int = 3, cost: Double = 0, lots: Int = 1) throws -> HometownsUndo {
        let tiles = (0..<lots).flatMap { [100 + $0, 0, 0, 0, 1, 0] }
        let json: [String: Any] = ["planId": planId, "day": day, "atTick": 120, "cost": cost, "tiles": tiles,
                                   "added": [], "removed": [], "construction": [], "terrainEdits": []]
        return try JSONDecoder().decode(HometownsUndo.self, from: try JSONSerialization.data(withJSONObject: json))
    }

    /// `deputy.json`: the hamlet whose mayor was away while Bramble's away
    /// zoning and growth help ran, so today's Deputy list has a build and zoning.
    func testBramblesBuildsAndZoningOfTodayComeFromTheFrame() throws {
        let copy = try copy()
        let w = try wire("deputy")
        let town = try XCTUnwrap(w.town)
        let today = w.deputyToday
        XCTAssertFalse(today.isEmpty, "Bramble did something today in the fixture")
        XCTAssertEqual(today, town.deputyUndo, "every entry on the list is of today")
        let day = try XCTUnwrap(w.me?.predict?.dayIndex)
        let me = try XCTUnwrap(w.me)
        let canUndo = Set(me.affordances.canUndo)
        for plan in today {
            XCTAssertEqual(plan.day, day, plan.planId)
            XCTAssertTrue(plan.planId.hasPrefix("deputy.\(day)."), plan.planId)
            XCTAssertFalse(canUndo.contains(plan.planId), "Bramble's entries never take a place in the mayor's list: \(plan.planId)")
            XCTAssertFalse(town.undo.contains(plan), plan.planId)
            XCTAssertGreaterThan(plan.lots, 0, "a Deputy entry changed at least one lot: \(plan.planId)")
            for level in [HometownsCopyLevel.kid, .adult] {
                let title = plan.deputyTitle(copy, level)
                XCTAssertFalse(title.isEmpty, plan.planId)
                XCTAssertFalse(title.contains("{"), "\(plan.planId) fills every slot: \(title)")
                XCTAssertFalse(title.contains("deputy."), "a row never shows a raw planId: \(title)")
                if let refund = plan.refundLine(copy, level) { XCTAssertFalse(refund.contains("{"), refund) }
            }
            if plan.deputyKind == .zoned || plan.deputyKind == .rezoned {
                XCTAssertEqual(plan.cost, 0, "zoning is free to undo: \(plan.planId)")
                XCTAssertNil(plan.refundLine(copy, .kid))
                XCTAssertEqual(plan.doneKey, "undo.doneFree")
            } else {
                let what = plan.planId.split(separator: ".").dropFirst(2).filter { $0 != "help" }.first.map(String.init)
                if let what, what != "road" { XCTAssertTrue(copy.has("buildingName.\(what)"), "\(what) has a name") }
            }
        }
        XCTAssertTrue(today.contains { $0.deputyKind == .zoned }, "the away order's zoning is listed")
        let build = try XCTUnwrap(today.first { $0.deputyKind == .built && $0.cost > 0 }, "a Deputy build is listed")
        XCTAssertEqual(build.doneKey, "undo.done")
        XCTAssertNotNil(build.refundLine(copy, .adult))
        // Every other fixture's mayor was at home: no Deputy rows to show.
        for name in ["hamlet", "town", "metropolis", "visiting"] {
            XCTAssertTrue(try wire(name).deputyToday.isEmpty, name)
        }
    }

    func testOnlyTodaysDeputyEntriesAreOffered() throws {
        var raw = try dict("deputy")
        var me = try XCTUnwrap(raw["me"] as? [String: Any])
        var town = try XCTUnwrap(me["town"] as? [String: Any])
        let predict = try XCTUnwrap(me["predict"] as? [String: Any])
        let day = try XCTUnwrap(predict["dayIndex"] as? Int)
        var list = try XCTUnwrap(town["deputyUndo"] as? [[String: Any]])
        XCTAssertGreaterThan(list.count, 1)
        list[0]["day"] = day - 1
        town["deputyUndo"] = list
        me["town"] = town
        raw["me"] = me
        let w = try JSONDecoder().decode(HometownsWire.self, from: try JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(w.deputyToday.count, list.count - 1, "an entry of a closed day cannot be undone (404)")
        XCTAssertFalse(w.deputyToday.contains { $0.day != day })
        // An older frame without `predict`: the server already dropped closed days' entries, so all are shown.
        me.removeValue(forKey: "predict")
        raw["me"] = me
        let older = try JSONDecoder().decode(HometownsWire.self, from: try JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(older.deputyToday.count, list.count)
    }

    func testDeputyPlanIdsSayWhatBrambleDid() throws {
        let copy = try copy()
        XCTAssertEqual(try entry("deputy.3.zone").deputyKind, .zoned)
        XCTAssertEqual(try entry("deputy.3.market").deputyKind, .zoned)
        XCTAssertEqual(try entry("deputy.3.help.zone.industry").deputyKind, .zoned)
        XCTAssertEqual(try entry("deputy.3.help.rezone.farms").deputyKind, .rezoned)
        for built in ["deputy.3.well", "deputy.3.help.surgery", "deputy.3.road", "deputy.3.road.2", "deputy.3.zoneless",
                      "deputy.3.help.zone", "deputy.x.zone", "p123"] {
            XCTAssertEqual(try entry(built).deputyKind, .built, built)
        }
        XCTAssertEqual(try entry("deputy.3.zone", lots: 2).lots, 2)
        XCTAssertEqual(try entry("deputy.3.zone", lots: 2).deputyTitle(copy, .kid), "Bramble painted 2 plots. Undo it for free.")
        XCTAssertEqual(try entry("deputy.3.market", lots: 1).deputyTitle(copy, .adult), "Zoned 1 tile (free to undo).")
        XCTAssertEqual(try entry("deputy.3.help.rezone.shops", lots: 1).deputyTitle(copy, .adult),
                       "Rezoned 1 empty Homes lot for work (free to undo).")
        XCTAssertEqual(try entry("deputy.3.road.2", cost: 9000, lots: 6).deputyTitle(copy, .kid), "Lane")
        XCTAssertEqual(try entry("deputy.3.help.well", cost: 1500).deputyTitle(copy, .adult), "Well")
        XCTAssertEqual(try entry("deputy.3.road", cost: 9000).refundLine(copy, .adult), "Full refund: £9,000.")
        XCTAssertNil(try entry("deputy.3.zone").refundLine(copy, .adult))
        XCTAssertTrue(copy.has("undo.doneFree"), "a free undo has its own words: no coins come back")
        XCTAssertFalse(copy.say("undo.doneFree", .kid).contains("coins"))
    }

    func testTheDeputyUndoIsTheOrdinaryUndoMove() throws {
        let move = HometownsMove.undo(planId: "deputy.3.help.zone.industry")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(move.body(since: 7))) as? [String: Any])
        XCTAssertEqual(body["action"] as? String, "undo")
        XCTAssertEqual(body["planId"] as? String, "deputy.3.help.zone.industry")
        XCTAssertFalse((body["moveId"] as? String ?? "").isEmpty, "a moveId, as the mayor's undo sends")
        let again = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(HometownsMove.undo(planId: "deputy.3.help.zone.industry").body(since: 7))) as? [String: Any])
        XCTAssertNotEqual(again["moveId"] as? String, body["moveId"] as? String, "each tap is its own move")
    }

    func testMoveBodies() throws {
        let build = HometownsMove.build(planId: "p123", ops: [["op": "zone", "zone": "homes", "rect": [1, 2, 3, 4]]])
        XCTAssertEqual(build.clientId, "p123")
        XCTAssertTrue(build.isPending)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(build.body(since: 41))) as? [String: Any])
        XCTAssertEqual(body["action"] as? String, "build")
        XCTAssertEqual(body["planId"] as? String, "p123")
        XCTAssertEqual(body["since"] as? Int, 41)
        XCTAssertEqual((body["plan"] as? [Any])?.count, 1)

        let budget = HometownsMove.budget(taxes: ["town": 850], funding: ["safety": 2])
        XCTAssertNotNil(budget.clientId)
        let b = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(budget.body(since: nil))) as? [String: Any])
        XCTAssertNil(b["since"])
        XCTAssertEqual((b["taxes"] as? [String: Any])?["town"] as? Int, 850)

        XCTAssertFalse(HometownsMove.hello().isPending)
        XCTAssertFalse(HometownsMove.seen(tick: 4).isPending)
        XCTAssertNotEqual(HometownsMove.newId("b"), HometownsMove.newId("b"))
        XCTAssertTrue(HometownsMove.newId("b").allSatisfy { $0.isLetter || $0.isNumber })
        let order = HometownsOrder(kind: "awayZoning", on: true, args: [12, 60, 3])
        XCTAssertEqual(order.json["args"] as? [Int], [12, 60, 3], "whole thresholds travel as integers")
    }

    func testTheRetrySentenceIsRecognised() {
        XCTAssertTrue(HometownsRetry.matches("Kingsport is just finishing the day. Trying again…"))
        XCTAssertFalse(HometownsRetry.matches("You have no town yet: found one first."))
    }

    func testTheForecastCardReadsThePagesNumbers() {
        let card = HometownsForecast([
            "seeds": 5, "cost": 12000, "upkeep": 40, "monthly": [-200, -50, 100], "people": [10, 30, 60],
            "happy": [[0, 1, 2], [0, 0, 0], [-1, 0, 3], [0, 0, 0], [0, 0, 0]], "months": 8,
            "readyTicks": 2, "readyMs": 3_600_000, "exactForMs": 1_800_000, "refused": NSNull(),
        ])
        XCTAssertEqual(card?.seeds, 5)
        XCTAssertEqual(card?.happy.count, 5)
        XCTAssertEqual(card.map { HometownsForecast.ends($0.monthly).0 }, -200)
        XCTAssertEqual(card.map { HometownsForecast.ends($0.people).1 }, 60)
        XCTAssertEqual(card?.isEstimate, true)
        XCTAssertNil(card?.refused)
        XCTAssertNil(HometownsForecast(nil))
    }

    func testTheCountySetupBoundsTheHour() {
        XCTAssertEqual(HometownsCountySetup.hours.first, 8)
        XCTAssertEqual(HometownsCountySetup.hours.last, 19)
        XCTAssertEqual(HometownsCountySetup.hourLabel(8), "08:00")
        XCTAssertTrue(HometownsCountySetup().line.contains("18:00"))
    }
}

import XCTest
@testable import SRAppleApp

/// The offline games' foundation: the seeded generator, the shared deck, the
/// wire, the host's room and the clock — every part that decides something,
/// without a phone, a radio or a main actor.
final class OfflineCoreTests: XCTestCase {

    // MARK: - The generator

    func testTheSameSeedGivesTheSameNumbers() {
        var a = OfflineRNG(seed: 42)
        var b = OfflineRNG(seed: 42)
        XCTAssertEqual((0..<20).map { _ in a.next() }, (0..<20).map { _ in b.next() })
        var c = OfflineRNG(seed: 43)
        var d = OfflineRNG(seed: 42)
        XCTAssertNotEqual(c.next(), d.next())
    }

    func testSplitMixMatchesItsReferenceValues() {
        // SplitMix64 from seed 0: the published first outputs.
        var rng = OfflineRNG(seed: 0)
        XCTAssertEqual(rng.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(rng.next(), 0x6E78_9E6A_A1B9_65F4)
    }

    func testRangesStayInsideTheirBounds() {
        var rng = OfflineRNG(seed: 9)
        var seen = Set<Int>()
        for _ in 0..<2_000 {
            let die = rng.int(in: 1...6)
            XCTAssertTrue((1...6).contains(die))
            seen.insert(die)
            let wait = rng.double(in: 2...6)
            XCTAssertTrue(wait >= 2 && wait <= 6)
            XCTAssertTrue((0..<3).contains(rng.int(below: 3)))
        }
        XCTAssertEqual(seen, Set(1...6), "every face of the die turns up")
    }

    func testTheGeneratorSurvivesJSONMidStream() throws {
        var rng = OfflineRNG(seed: 5)
        _ = rng.next()
        let copy = try OfflineCoding.decode(OfflineRNG.self, from: OfflineCoding.encode(rng))
        var a = rng, b = copy
        XCTAssertEqual(a.next(), b.next())
    }

    func testAShuffleIsAPermutationAndReproducible() {
        var a = OfflineRNG(seed: 11)
        var b = OfflineRNG(seed: 11)
        let items = Array(0..<30)
        let first = a.shuffled(items)
        XCTAssertEqual(first, b.shuffled(items))
        XCTAssertEqual(first.sorted(), items)
        XCTAssertNotEqual(first, items)
    }

    // MARK: - Cards

    func testADeckHasFiftyTwoDifferentCards() {
        let deck = OfflineCard.deck()
        XCTAssertEqual(deck.count, 52)
        XCTAssertEqual(Set(deck.map(\.id)).count, 52)
        XCTAssertEqual(deck.filter { $0.suit == .hearts }.count, 13)
        XCTAssertEqual(deck.first, OfflineCard(1, .clubs))
    }

    func testACardWritesItselfDown() {
        let ace = OfflineCard(1, .spades)
        XCTAssertEqual(ace.rankText, "A")
        XCTAssertEqual(ace.id, "AS")
        XCTAssertEqual(ace.highRank, 14)
        XCTAssertEqual(ace.name, "ace of spades")
        XCTAssertTrue(ace.text.hasPrefix("A"))
        let ten = OfflineCard(10, .hearts)
        XCTAssertEqual(ten.id, "10H")
        XCTAssertTrue(ten.isRed)
        XCTAssertEqual(OfflineCard(12, .diamonds).rankText, "Q")
        XCTAssertTrue(OfflineCard(13, .clubs).isFace)
    }

    func testAShuffledDeckIsSeededAndDealsRoundTheTable() {
        var a = OfflineRNG(seed: 3)
        var b = OfflineRNG(seed: 3)
        var deck = OfflineCard.shuffledDeck(&a)
        XCTAssertEqual(deck, OfflineCard.shuffledDeck(&b))
        XCTAssertEqual(Set(deck), Set(OfflineCard.deck()))
        let top = Array(deck.suffix(2).reversed())
        let hands = OfflineCard.deal(5, to: 3, from: &deck)
        XCTAssertEqual(hands.map(\.count), [5, 5, 5])
        XCTAssertEqual(deck.count, 37)
        XCTAssertEqual(hands[0].first, top[0], "the first card off the top goes to the first seat")
        XCTAssertEqual(hands[1].first, top[1])
        var twoDecks = OfflineCard.shuffledDeck(&a, decks: 2)
        XCTAssertEqual(twoDecks.count, 104)
        let all = OfflineCard.deal(30, to: 4, from: &twoDecks)
        XCTAssertEqual(all.map(\.count).reduce(0, +), 104, "dealing stops when the deck runs out")
    }

    func testACardTravelsAsJSON() throws {
        let card = OfflineCard(11, .diamonds)
        XCTAssertEqual(try OfflineCoding.decode(OfflineCard.self, from: OfflineCoding.encode(card)), card)
    }

    func testAHandSortsBySuitThenRank() {
        let hand = [OfflineCard(1, .hearts), OfflineCard(2, .clubs), OfflineCard(13, .clubs), OfflineCard(5, .hearts)]
        XCTAssertEqual(OfflineCard.sortedForHand(hand).map(\.id), ["2C", "KC", "5H", "AH"])
        XCTAssertEqual(OfflineCard.sortedForHand(hand, acesHigh: false).map(\.id), ["2C", "KC", "AH", "5H"])
    }

    // MARK: - Standings

    func testTiesShareARank() {
        let players = ["a", "b", "c", "d"].map { OfflinePlayer(id: $0, name: $0.uppercased()) }
        let scores = ["a": 3, "b": 5, "c": 3, "d": 1]
        let table = OfflineStanding.ranked(players, score: { scores[$0.id] ?? 0 })
        XCTAssertEqual(table.map(\.playerId), ["b", "a", "c", "d"])
        XCTAssertEqual(table.map(\.rank), [1, 2, 2, 4])
        let golf = OfflineStanding.ranked(players, score: { scores[$0.id] ?? 0 }, lowerIsBetter: true)
        XCTAssertEqual(golf.map(\.playerId), ["d", "a", "c", "b"])
    }

    func testThePlayerRangeReadsNaturally() {
        XCTAssertEqual(OfflineSecretRules.info.playersLabel, "2–3 players")
        XCTAssertTrue(OfflineSecretRules.info.allows(3))
        XCTAssertFalse(OfflineSecretRules.info.allows(4))
    }

    // MARK: - The wire

    func testEveryMessageSurvivesTheWire() throws {
        let lobby = OfflineLobby(
            hostId: "h", roomName: "Sam's room",
            players: [OfflineLobbyPlayer(id: "h", name: "Sam", present: true, inMatch: true)],
            gameId: "quick-draw", phase: .finished, match: 2,
            standings: [OfflineStanding(playerId: "h", name: "Sam", rank: 1, score: 5, detail: "best 200 ms")]
        )
        let messages: [OfflineMessage] = [
            .hello(playerId: "g", name: "Ali", version: 1),
            .welcome(playerId: "g", hostId: "h", roomName: "Sam's room"),
            .refused(reason: "Full"),
            .lobby(lobby),
            .view(OfflineViewPacket(gameId: "quick-draw", match: 2, data: Data("{\"a\":1}".utf8), over: false)),
            .action(seq: 4, match: 2, data: Data("{}".utf8)),
            .refusal(seq: 4, reason: "Not your turn."),
            .ping(id: 1, sentAt: 12.5),
            .pong(id: 1, sentAt: 12.5, hostNow: 99.25),
            .bye(reason: "Host left"),
        ]
        for message in messages {
            let data = try OfflineEnvelope(message).encoded()
            let back = try OfflineEnvelope.decode(data)
            XCTAssertEqual(back.message, message)
            XCTAssertEqual(back.v, OfflineEnvelope.version)
        }
    }

    func testEqualViewsEncodeToEqualBytes() throws {
        let a: [String: Int] = ["zed": 1, "alpha": 2, "mid": 3, "beta": 4, "omega": 5]
        let b = Dictionary(uniqueKeysWithValues: a.map { ($0.key, $0.value) }.reversed())
        XCTAssertEqual(try OfflineCoding.encode(a), try OfflineCoding.encode(b))
    }

    // MARK: - The room

    private let host = OfflinePlayer(id: "h", name: "Host")
    private func guest(_ n: Int) -> OfflinePlayer { OfflinePlayer(id: "g\(n)", name: "Guest \(n)") }

    private func room() -> OfflineRoom {
        OfflineRoom(host: host, roomName: "Host's room",
                    games: [OfflineGameEntry(OfflineSecretRules.self), OfflineGameEntry(QuickDrawRules.self)])
    }

    private func views(_ out: [OfflineOutgoing]) -> [String: OfflineViewPacket] {
        var found: [String: OfflineViewPacket] = [:]
        for item in out { if case .view(let packet) = item.message { found[item.to] = packet } }
        return found
    }

    private func lobbies(_ out: [OfflineOutgoing]) -> [String: OfflineLobby] {
        var found: [String: OfflineLobby] = [:]
        for item in out { if case .lobby(let lobby) = item.message { found[item.to] = lobby } }
        return found
    }

    private func secret(_ packet: OfflineViewPacket?) throws -> OfflineSecretRules.PlayerView {
        try OfflineCoding.decode(OfflineSecretRules.PlayerView.self, from: XCTUnwrap(packet).data)
    }

    private func action(_ a: OfflineSecretRules.Action) throws -> Data { try OfflineCoding.encode(a) }

    func testFivePlayersFitAndASixthIsRefused() throws {
        var room = room()
        for n in 1...4 { try room.join(guest(n), version: OfflineEnvelope.version) }
        XCTAssertEqual(room.players.count, 5)
        XCTAssertThrowsError(try room.join(guest(5), version: OfflineEnvelope.version)) { error in
            XCTAssertTrue((error as? OfflineRefusal)?.reason.contains("full") == true)
        }
        // A player already in the room is a rejoin, never "full".
        XCTAssertNoThrow(try room.join(guest(4), version: OfflineEnvelope.version))
        XCTAssertEqual(room.players.count, 5)
    }

    func testAnotherVersionIsRefusedWithASentence() {
        var room = room()
        XCTAssertThrowsError(try room.join(guest(1), version: OfflineEnvelope.version + 1)) { error in
            XCTAssertTrue((error as? OfflineRefusal)?.reason.contains("version") == true)
        }
        XCTAssertEqual(room.players.count, 1)
    }

    func testNamesAreTidied() throws {
        var room = room()
        try room.join(OfflinePlayer(id: "g", name: "   "), version: OfflineEnvelope.version)
        try room.join(OfflinePlayer(id: "x", name: "  A name far longer than twenty letters "), version: OfflineEnvelope.version)
        XCTAssertEqual(room.players[1].name, "Player")
        XCTAssertEqual(room.players[2].name.count, 20)
    }

    func testEveryoneGetsTheLobbyOnceUntilItChanges() throws {
        var room = room()
        try room.join(guest(1), version: OfflineEnvelope.version)
        let first = lobbies(room.outbox())
        XCTAssertEqual(Set(first.keys), ["h", "g1"])
        XCTAssertEqual(first["g1"]?.players.map(\.id), ["h", "g1"])
        XCTAssertTrue(room.outbox().isEmpty, "nothing changed, nothing sent")
        try room.choose("secret")
        XCTAssertEqual(lobbies(room.outbox())["g1"]?.gameId, "secret")
    }

    func testStartWaitsForAGameAndTheRightNumberOfPlayers() throws {
        var room = room()
        XCTAssertEqual(room.startProblem, "Pick a game.")
        try room.choose("secret")
        XCTAssertEqual(room.startProblem, "Secret needs 1 more player.")
        XCTAssertThrowsError(try room.start(seed: 1, now: 0))
        try room.join(guest(1), version: OfflineEnvelope.version)
        XCTAssertNil(room.startProblem)
        try room.join(guest(2), version: OfflineEnvelope.version)
        try room.join(guest(3), version: OfflineEnvelope.version)
        XCTAssertEqual(room.startProblem, "Secret is for at most 3 players.")
        room.drop("g3", now: 0)
        XCTAssertNil(room.startProblem)
        XCTAssertThrowsError(try room.choose("no-such-game"))
        try room.start(seed: 1, now: 0)
        XCTAssertEqual(room.phase, .playing)
        XCTAssertEqual(room.matchNumber, 1)
        XCTAssertThrowsError(try room.choose("quick-draw"), "no changing game mid-match")
    }

    func testEachPlayerIsSentOnlyTheirOwnSecret() throws {
        var room = room()
        try room.join(guest(1), version: OfflineEnvelope.version)
        try room.choose("secret")
        try room.start(seed: 99, now: 0)
        let sent = views(room.outbox())
        XCTAssertEqual(Set(sent.keys), ["h", "g1"])
        let hostView = try secret(sent["h"])
        let guestView = try secret(sent["g1"])
        XCTAssertEqual(hostView.me, "h")
        XCTAssertNotNil(hostView.mine)
        XCTAssertNotNil(guestView.mine)
        // Each packet was made FOR its addressee: the guest's carries the
        // guest's own number and nobody else's.
        XCTAssertEqual(guestView.me, "g1")
        XCTAssertEqual(sent["g1"]?.gameId, "secret")
        XCTAssertEqual(sent["g1"]?.match, 1)
        XCTAssertEqual(sent["g1"]?.over, false)
        XCTAssertTrue(room.outbox().isEmpty, "an unchanged view is not resent")
    }

    func testAnIllegalActionIsRefusedAndChangesNothing() throws {
        var room = room()
        try room.join(guest(1), version: OfflineEnvelope.version)
        try room.choose("secret")
        try room.start(seed: 1, now: 0)
        _ = room.outbox()
        XCTAssertThrowsError(try room.act(action(.add(-1)), by: "g1", match: 1, now: 1)) { error in
            XCTAssertEqual((error as? OfflineRefusal)?.reason, "Only positive numbers.")
        }
        XCTAssertTrue(room.outbox().isEmpty)
        // Half-applied then refused: the copy is thrown away.
        XCTAssertThrowsError(try room.act(action(.addThenRefuse(5)), by: "g1", match: 1, now: 1))
        XCTAssertTrue(room.outbox().isEmpty)
        XCTAssertThrowsError(try room.act(Data("nonsense".utf8), by: "g1", match: 1, now: 1))
        XCTAssertThrowsError(try room.act(action(.add(1)), by: "g1", match: 0, now: 1), "an earlier match's move")
        XCTAssertThrowsError(try room.act(action(.add(1)), by: "stranger", match: 1, now: 1))

        try room.act(action(.add(2)), by: "g1", match: 1, now: 1)
        let sent = views(room.outbox())
        XCTAssertEqual(try secret(sent["g1"]).total, 2)
        XCTAssertEqual(try secret(sent["h"]).total, 2, "the shared total reaches everyone")
    }

    func testAMatchEndsWithStandingsAndPlaysAgain() throws {
        var room = room()
        try room.join(guest(1), version: OfflineEnvelope.version)
        try room.choose("secret")
        try room.start(seed: 1, now: 0)
        try room.act(action(.add(3)), by: "g1", match: 1, now: 1)
        try room.act(action(.finish), by: "h", match: 1, now: 2)
        XCTAssertEqual(room.phase, .finished)
        let out = room.outbox()
        XCTAssertEqual(lobbies(out)["g1"]?.phase, .finished)
        XCTAssertEqual(lobbies(out)["g1"]?.standings?.first?.playerId, "g1")
        XCTAssertEqual(views(out)["g1"]?.over, true)
        XCTAssertThrowsError(try room.act(action(.add(1)), by: "g1", match: 1, now: 3))

        room.backToLobby()
        XCTAssertEqual(room.phase, .lobby)
        XCTAssertTrue(room.players.allSatisfy { !$0.inMatch })
        try room.start(seed: 2, now: 10)
        XCTAssertEqual(room.matchNumber, 2)
        XCTAssertEqual(views(room.outbox()).count, 2)
    }

    func testTicksDriveTheMatch() throws {
        var room = room()
        try room.join(guest(1), version: OfflineEnvelope.version)
        try room.choose("secret")
        try room.start(seed: 1, now: 0)
        _ = room.outbox()
        room.tick(now: 5)
        XCTAssertEqual(room.phase, .playing)
        room.tick(now: 61)
        XCTAssertEqual(room.phase, .finished, "the test game times out at sixty seconds")
    }

    func testANewcomerMidMatchWatchesAsASpectator() throws {
        var room = room()
        try room.join(guest(1), version: OfflineEnvelope.version)
        try room.choose("secret")
        try room.start(seed: 1, now: 0)
        _ = room.outbox()
        try room.join(guest(2), version: OfflineEnvelope.version)
        let out = room.outbox()
        XCTAssertEqual(lobbies(out).count, 3, "everyone hears about the newcomer")
        let watching = try secret(views(out)["g2"])
        XCTAssertNil(watching.me)
        XCTAssertNil(watching.mine)
        XCTAssertThrowsError(try room.act(action(.add(1)), by: "g2", match: 1, now: 1))
    }

    func testADroppedGuestLeavesTheLobby() throws {
        var room = room()
        try room.join(guest(1), version: OfflineEnvelope.version)
        room.drop("g1", now: 0)
        XCTAssertEqual(room.players.map(\.id), ["h"])
        room.drop("h", now: 0)
        XCTAssertEqual(room.players.map(\.id), ["h"], "the host cannot be dropped from its own room")
    }

    func testADropMidMatchKeepsTheSeatAndCanRejoin() throws {
        var room = room()
        try room.join(guest(1), version: OfflineEnvelope.version)
        try room.join(guest(2), version: OfflineEnvelope.version)
        try room.choose("secret")
        try room.start(seed: 1, now: 0)
        _ = room.outbox()
        room.drop("g2", now: 1)
        XCTAssertEqual(room.phase, .playing)
        XCTAssertEqual(room.players.first { $0.id == "g2" }?.present, false)
        let out = room.outbox()
        XCTAssertNil(views(out)["g2"], "nothing is sent to a phone that has gone")
        XCTAssertEqual(lobbies(out)["g1"]?.players.first { $0.id == "g2" }?.present, false)

        try room.join(guest(2), version: OfflineEnvelope.version)
        let back = room.outbox()
        XCTAssertNotNil(lobbies(back)["g2"])
        XCTAssertEqual(try secret(views(back)["g2"]).me, "g2", "back in their own seat, with their own secret")
    }

    func testAMatchBelowItsMinimumEnds() throws {
        var room = room()
        try room.join(guest(1), version: OfflineEnvelope.version)
        try room.choose("secret")
        try room.start(seed: 1, now: 0)
        room.drop("g1", now: 1)
        XCTAssertEqual(room.phase, .finished)
        XCTAssertEqual(room.standings?.count, 2)
        room.backToLobby()
        XCTAssertEqual(room.players.map(\.id), ["h"], "the absent leave with the match")
    }

    func testTheHostCanEndAMatchEarly() throws {
        var room = room()
        try room.join(guest(1), version: OfflineEnvelope.version)
        try room.choose("secret")
        try room.start(seed: 1, now: 0)
        room.endMatch()
        XCTAssertEqual(room.phase, .finished)
        XCTAssertNotNil(room.standings)
    }

    // MARK: - The clock

    func testTheQuickestRoundTripSetsTheOffset() {
        var clock = OfflineClockEstimator()
        XCTAssertNil(clock.offset)
        // Host is 100 s ahead. A slow, lopsided trip, then a quick one.
        clock.record(sentAt: 10.0, receivedAt: 10.4, hostNow: 110.35)
        XCTAssertEqual(clock.offset ?? 0, 100.15, accuracy: 0.0001)
        clock.record(sentAt: 20.0, receivedAt: 20.02, hostNow: 120.01)
        XCTAssertEqual(clock.offset ?? 0, 100.0, accuracy: 0.0001)
        XCTAssertEqual(clock.roundTrip ?? 0, 0.02, accuracy: 0.0001)
        // A later slow trip does not drag it.
        clock.record(sentAt: 30.0, receivedAt: 30.5, hostNow: 130.45)
        XCTAssertEqual(clock.offset ?? 0, 100.0, accuracy: 0.0001)
        clock.record(sentAt: 40.0, receivedAt: 39.0, hostNow: 1)
        XCTAssertEqual(clock.samples.count, 3, "a backwards trip is ignored")
    }

    func testOldSamplesAgeOut() {
        var clock = OfflineClockEstimator()
        clock.record(sentAt: 0, receivedAt: 0.001, hostNow: 50)
        for n in 1...OfflineClockEstimator.window {
            clock.record(sentAt: Double(n), receivedAt: Double(n) + 0.1, hostNow: Double(n) + 10.05)
        }
        XCTAssertEqual(clock.samples.count, OfflineClockEstimator.window)
        XCTAssertEqual(clock.offset ?? 0, 10.0, accuracy: 0.0001, "the quick sample from long ago has gone")
        XCTAssertFalse(clock.settling)
    }

    func testTheHostClockConvertsBothWays() {
        let clock = OfflineHostClock(offset: 100)
        XCTAssertEqual(clock.host(fromLocal: 5), 105)
        XCTAssertEqual(clock.local(fromHost: 105), 5)
        XCTAssertEqual(OfflineHostClock.host.offset, 0)
        XCTAssertEqual(clock.secondsLeft(until: clock.now() - 10), 0)
    }

    func testAReactionIsMeasuredFromTheFrameThatShowedIt() {
        XCTAssertEqual(OfflineReaction.ms(shownAt: 10.0, touchedAt: 10.2345), 235)
        XCTAssertNil(OfflineReaction.ms(shownAt: nil, touchedAt: 10))
        XCTAssertNil(OfflineReaction.ms(shownAt: 10.5, touchedAt: 10.4))
        XCTAssertFalse(OfflineReaction.counts(80))
        XCTAssertTrue(OfflineReaction.counts(100))
    }

    // MARK: - The Wi-Fi stream

    func testFramesSplitBackIntoMessagesWhateverTheChunks() throws {
        let one = try OfflineEnvelope(.ping(id: 1, sentAt: 2)).encoded()
        let two = try OfflineEnvelope(.bye(reason: "done")).encoded()
        let stream = OfflineFraming.frame(one) + OfflineFraming.frame(two)
        XCTAssertEqual(OfflineFraming.length(of: stream.prefix(4)), one.count)
        // Delivered a byte at a time, as TCP is entitled to.
        var buffer = Data()
        var got: [Data] = []
        for byte in stream {
            buffer.append(byte)
            got += try XCTUnwrap(OfflineFraming.drain(&buffer))
        }
        XCTAssertEqual(got, [one, two])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testAGarbledLengthIsCaught() {
        var buffer = Data([0xFF, 0xFF, 0xFF, 0xFF, 0x01])
        XCTAssertNil(OfflineFraming.drain(&buffer))
        XCTAssertNil(OfflineFraming.length(of: Data([0, 0, 0, 0])))
        XCTAssertNil(OfflineFraming.length(of: Data([0, 1])))
    }

    func testATypedAddressIsRead() {
        XCTAssertEqual(OfflineAddress.parse(" 172.20.10.1 ")?.host, "172.20.10.1")
        XCTAssertEqual(OfflineAddress.parse("172.20.10.1")?.port, OfflineAddress.preferredPort)
        XCTAssertEqual(OfflineAddress.parse("192.168.1.20:5000")?.port, 5000)
        XCTAssertEqual(OfflineAddress.parse("sams-phone.local")?.host, "sams-phone.local")
        XCTAssertNil(OfflineAddress.parse(""))
        XCTAssertNil(OfflineAddress.parse("172.20.10"))
        XCTAssertNil(OfflineAddress.parse("300.1.1.1"))
        XCTAssertNil(OfflineAddress.parse("172.20.10.1:0"))
        XCTAssertNil(OfflineAddress.parse("172.20.10.1:99999"))
        XCTAssertNil(OfflineAddress.parse("my phone"))
    }

    func testTheHotspotAddressIsOfferedFirst() {
        let interfaces: [(name: String, address: String)] = [
            ("lo0", "127.0.0.1"), ("pdp_ip0", "10.12.0.4"), ("en0", "192.168.1.20"),
            ("bridge100", "172.20.10.1"), ("utun3", "100.64.0.2"), ("en2", "169.254.3.3"),
        ]
        XCTAssertEqual(OfflineAddress.joinable(interfaces), ["172.20.10.1", "192.168.1.20"])
        XCTAssertEqual(OfflineAddress.display("172.20.10.1", port: OfflineAddress.preferredPort), "172.20.10.1")
        XCTAssertEqual(OfflineAddress.display("172.20.10.1", port: 5000), "172.20.10.1:5000")
    }

    func testNamesAreCutInBytesAtACharacterBoundary() {
        XCTAssertEqual(OfflineName.clipped("Sam's game", toUTF8: 63), "Sam's game")
        // Twenty CJK characters and "'s game" are 67 bytes: too long for Bonjour.
        let wide = String(repeating: "漢", count: 20) + "'s game"
        let cut = OfflineName.clipped(wide, toUTF8: 63)
        XCTAssertLessThanOrEqual(cut.utf8.count, 63)
        XCTAssertTrue(wide.hasPrefix(cut))
        XCTAssertEqual(cut, String(repeating: "漢", count: 20) + "'s ")
        // A family emoji is one character of 25 bytes: never split.
        let family = String(repeating: "👨‍👩‍👧‍👦", count: 3)
        XCTAssertEqual(OfflineName.clipped(family, toUTF8: 60), String(repeating: "👨‍👩‍👧‍👦", count: 2))
    }

    func testAPeerNameIsNeverEmptyOrTooLong() {
        XCTAssertEqual(OfflineName.peer("  Ann  "), "Ann")
        XCTAssertEqual(OfflineName.peer(""), "Player")
        // One letter carrying sixty combining marks is a single character of
        // over 63 bytes: MCPeerID would raise on what is left, so "Player".
        let stacked = "Z" + String(repeating: "\u{0301}\u{0327}\u{0336}", count: 20) + "oe"
        XCTAssertEqual(OfflineName.peer(stacked), "Player")
        XCTAssertLessThanOrEqual(OfflineName.peer(String(repeating: "👨‍👩‍👧‍👦", count: 20)).utf8.count, 63)
    }

    // MARK: - The audit

    func testTheAuditPassesAGoodGameAndCatchesABadOne() {
        XCTAssertEqual(OfflineRulesAudit.problems(OfflineSecretRules.self), [])
        let problems = OfflineRulesAudit.problems(OfflineBrokenRules.self)
        XCTAssertTrue(problems.contains { $0.contains("kebab-case") }, "\(problems)")
        XCTAssertTrue(problems.contains { $0.contains("maxPlayers") }, "\(problems)")
    }
}

// MARK: - A tiny game for the room's tests

/// Each player is dealt a secret number nobody else may see; anyone may add to
/// a shared total; `finish` ends it, the highest secret plus total winning.
/// Times out sixty seconds after it starts.
private enum OfflineSecretRules: OfflineGameRules {
    static let info = OfflineGameInfo(id: "secret", title: "Secret", blurb: "A test.", category: .skill,
                                      minPlayers: 2, maxPlayers: 3, symbol: "lock", howToPlay: ["Test."])

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        var secrets: [String: Int]
        var total = 0
        var endsAt: Double
        var over = false
    }

    enum Action: Codable, Equatable {
        case add(Int)
        case addThenRefuse(Int)
        case finish
    }

    struct PlayerView: Codable, Equatable {
        let me: String?
        let mine: Int?
        let total: Int
    }

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var secrets: [String: Int] = [:]
        for player in players { secrets[player.id] = rng.int(in: 1...100) }
        return State(players: players, secrets: secrets, endsAt: now + 60)
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        switch action {
        case .add(let n):
            guard n > 0 else { throw OfflineRefusal("Only positive numbers.") }
            state.total += n
        case .addThenRefuse(let n):
            state.total += n
            throw OfflineRefusal("Changed my mind.")
        case .finish:
            state.over = true
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        if now >= state.endsAt { state.over = true }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        PlayerView(me: playerId, mine: playerId.flatMap { state.secrets[$0] }, total: state.total)
    }

    static func isOver(_ state: State) -> Bool { state.over }

    static func standings(_ state: State) -> [OfflineStanding] {
        // The guest wins the test match: rank by seat, last seat first.
        let order = Dictionary(uniqueKeysWithValues: state.players.enumerated().map { ($0.element.id, $0.offset) })
        return OfflineStanding.ranked(state.players, score: { order[$0.id] ?? 0 })
    }
}

/// Wrong on purpose, for the audit.
private enum OfflineBrokenRules: OfflineGameRules {
    static let info = OfflineGameInfo(id: "Broken Game", title: "Broken", blurb: "x", category: .card,
                                      minPlayers: 2, maxPlayers: 9, symbol: "xmark", howToPlay: ["x"])
    struct State: Codable, Equatable { var n = 0 }
    enum Action: Codable, Equatable { case nothing }
    struct PlayerView: Codable, Equatable { var n: Int }
    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State { State() }
    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {}
    static func view(of state: State, for playerId: String?) -> PlayerView { PlayerView(n: state.n) }
    static func isOver(_ state: State) -> Bool { false }
    static func standings(_ state: State) -> [OfflineStanding] { [] }
}

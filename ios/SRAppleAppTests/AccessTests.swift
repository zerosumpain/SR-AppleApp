import XCTest
@testable import SRAppleApp

/// What a person may use, as the site decided it, and every rule the app
/// applies to that answer. The rules are pure functions so each is a test
/// here rather than something only a phone in somebody's hand can show.
final class AccessTests: XCTestCase {

    private func view(_ access: String?) throws -> HouseholdView? {
        let tail = access.map { #","access":\#($0)"# } ?? ""
        let json = #"{"view":{"generatedAt":"2026-09-26T09:00:00Z","viewer":"none","people":[]\#(tail)},"updated":"2026-09-26T09:00:00Z"}"#
        return try JSONDecoder().decode(HouseholdViewResponse.self, from: Data(json.utf8)).view
    }

    // MARK: - Decoding

    func testAViewWithoutAccessIsUnknownNotNothing() throws {
        // An older site sends no `access`. That must read as "not answered",
        // never as an answer of "nothing" — the owner's phone depends on it.
        let v = try XCTUnwrap(try view(nil))
        XCTAssertNil(v.access)
        XCTAssertFalse(v.showsHousehold)
    }

    func testTheGamesFlagDecodes() throws {
        let v = try XCTUnwrap(try view(#"{"owner":false,"chat":false,"news":false,"family":true,"games":true,"sitePair":null}"#))
        XCTAssertEqual(v.access?.flags, AppAccess(family: true, games: true))
    }

    func testAMissingGamesFlagIsFalse() throws {
        // A site older than family games has not granted them.
        let v = try XCTUnwrap(try view(#"{"owner":false,"chat":true,"family":true}"#))
        XCTAssertEqual(v.access?.flags.games, false)
        let odd = try XCTUnwrap(try view(#"{"family":true,"games":"yes"}"#))
        XCTAssertEqual(odd.access?.flags, AppAccess(family: true))
    }

    func testTheGamesFlagRoundTripsThroughPersistedState() throws {
        var state = PersistedState()
        state.access = AppAccess(family: true, games: true, source: "view")
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(back.access?.games, true)
    }

    func testAMemberViewDecodesItsFlags() throws {
        let v = try XCTUnwrap(try view(#"{"owner":false,"chat":true,"news":false,"research":false,"notes":false,"intel":false,"family":true,"sitePair":null}"#))
        let access = try XCTUnwrap(v.access)
        XCTAssertEqual(access.flags, AppAccess(chat: true, family: true))
        XCTAssertNil(access.sitePair)
    }

    func testASitePairCodeDecodesAndBecomesAPairing() throws {
        let v = try XCTUnwrap(try view(#"{"owner":false,"chat":true,"news":true,"research":false,"notes":false,"intel":false,"family":false,"sitePair":{"server":"https://strangeramblings.com","code":"abc123","expiresAt":"2026-09-26T09:10:00Z"}}"#))
        let offer = try XCTUnwrap(v.access?.sitePair)
        XCTAssertEqual(offer.code, "abc123")
        XCTAssertEqual(offer.pairing.type, "sr-native-pair")
        XCTAssertEqual(offer.pairing.server, "https://strangeramblings.com")
        XCTAssertFalse(offer.expired(now: isoDate("2026-09-26T09:05:00Z")!))
        XCTAssertTrue(offer.expired(now: isoDate("2026-09-26T09:11:00Z")!))
    }

    func testMissingOrOddFlagsAreFalseNotAThrow() throws {
        // A flag the site has not heard of has not been granted, and one odd
        // value must not cost the whole household view.
        let v = try XCTUnwrap(try view(#"{"chat":"yes","family":true}"#))
        XCTAssertEqual(v.access?.flags, AppAccess(family: true))
    }

    func testPersistedStateDecodesWithoutAccess() throws {
        // The upload queue. An upgrade must not discard it for want of the
        // new field.
        let old = #"{"batches":[],"anchors":{},"healthEnabled":["steps"],"sharing":true}"#
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(old.utf8))
        XCTAssertNil(state.access)
        XCTAssertTrue(state.sharing)
    }

    func testPersistedStateSurvivesAnUnreadableAccess() throws {
        let odd = #"{"sharing":true,"access":"owner"}"#
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(odd.utf8))
        XCTAssertNil(state.access, "a cache it cannot read costs the cache")
        XCTAssertTrue(state.sharing, "and never the queue")
    }

    func testAccessRoundTripsThroughPersistedState() throws {
        var state = PersistedState()
        state.access = AppAccess(news: true, family: true, source: "view")
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(back.access, state.access)
    }

    // MARK: - Resolution

    func testUnknownWithASiteCredentialIsTheOwner() {
        // Every existing owner install holds a site credential and has never
        // been told anything: John's phone must not change.
        XCTAssertEqual(AccessPolicy.resolve(known: nil, sitePaired: true), .everything)
    }

    func testUnknownWithoutASiteCredentialFailsClosed() {
        XCTAssertEqual(AccessPolicy.resolve(known: nil, sitePaired: false), .nothing)
    }

    func testAnOwnerGetsEverythingWhateverElseIsSet() {
        XCTAssertEqual(AccessPolicy.resolve(known: AppAccess(owner: true), sitePaired: false), .everything)
    }

    func testAMemberGetsExactlyTheirFlags() {
        let member = AppAccess(chat: true, family: true, source: "view")
        XCTAssertEqual(AccessPolicy.resolve(known: member, sitePaired: true), AppAccess(chat: true, family: true))
    }

    // MARK: - Tabs

    func testTheOwnerHasEverySevenTabsInOrder() {
        XCTAssertEqual(AccessPolicy.tabs(for: .everything), [.today, .chat, .health, .family, .games, .news, .flows])
    }

    func testGamesSitsRightAfterFamilyForAMember() {
        // Four tabs: on the bar, no More.
        XCTAssertEqual(AccessPolicy.tabs(for: AppAccess(family: true, games: true)), [.today, .health, .family, .games])
        XCTAssertEqual(AccessPolicy.tabs(for: AppAccess(games: true)), [.today, .health, .games])
    }

    func testGamesNeedsTheGamesFlag() {
        XCTAssertFalse(AccessPolicy.allows(.games, AppAccess(chat: true, news: true, family: true)))
        XCTAssertTrue(AccessPolicy.allows(.games, AppAccess(games: true)))
        XCTAssertTrue(AccessPolicy.allows(.games, AppAccess(owner: true)))
    }

    func testNobodyKnownHasTodayAndHealthOnly() {
        XCTAssertEqual(AccessPolicy.tabs(for: .nothing), [.today, .health])
    }

    func testAFamilyOnlyMemberHasNoChatNewsOrFlows() {
        XCTAssertEqual(AccessPolicy.tabs(for: AppAccess(family: true)), [.today, .health, .family])
    }

    func testFlowsAreTheOwnersEvenWithEveryOtherFlag() {
        let all = AppAccess(chat: true, news: true, research: true, notes: true, intel: true, family: true)
        XCTAssertFalse(AccessPolicy.tabs(for: all).contains(.flows))
        XCTAssertEqual(AccessPolicy.tabs(for: all).count, 5, "five tabs fit the bar: no More")
    }

    // MARK: - Automatic site pairing

    func testAMemberWithChatOrNewsAndNoCredentialWantsOne() {
        XCTAssertTrue(AccessPolicy.wantsSitePair(known: AppAccess(chat: true), sitePaired: false))
        XCTAssertTrue(AccessPolicy.wantsSitePair(known: AppAccess(news: true), sitePaired: false))
    }

    func testAGamesOnlyMemberWantsASiteCredentialToo() {
        // The rooms live on the site; without a credential the tab could only
        // ever say "Connecting".
        XCTAssertTrue(AccessPolicy.wantsSitePair(known: AppAccess(family: true, games: true), sitePaired: false))
        XCTAssertFalse(AccessPolicy.signsOutSite(known: AppAccess(games: true), sitePaired: true, siteRole: "member"),
                       "games alone keeps the credential")
    }

    func testNobodyElseAutoPairs() {
        XCTAssertFalse(AccessPolicy.wantsSitePair(known: nil, sitePaired: false), "unknown")
        XCTAssertFalse(AccessPolicy.wantsSitePair(known: AppAccess(owner: true, chat: true), sitePaired: false), "the owner keeps the QR")
        XCTAssertFalse(AccessPolicy.wantsSitePair(known: AppAccess(family: true), sitePaired: false), "nothing to pair for")
        XCTAssertFalse(AccessPolicy.wantsSitePair(known: AppAccess(chat: true), sitePaired: true), "already paired")
    }

    func testAMemberWhoLostBothLanesIsSignedOut() {
        XCTAssertTrue(AccessPolicy.signsOutSite(known: AppAccess(family: true), sitePaired: true, siteRole: "member"))
        XCTAssertTrue(AccessPolicy.signsOutSite(known: AppAccess(family: true), sitePaired: true, siteRole: nil))
    }

    func testTheOwnerIsNeverSignedOut() {
        XCTAssertFalse(AccessPolicy.signsOutSite(known: nil, sitePaired: true, siteRole: nil), "unknown is the owner")
        XCTAssertFalse(AccessPolicy.signsOutSite(known: AppAccess(owner: true), sitePaired: true, siteRole: nil))
        XCTAssertFalse(AccessPolicy.signsOutSite(known: AppAccess(), sitePaired: true, siteRole: "owner"),
                       "a stale view must not sign out a credential the site calls the owner's")
        XCTAssertFalse(AccessPolicy.signsOutSite(known: AppAccess(news: true), sitePaired: true, siteRole: "member"))
    }

    func testThePairRequestIsThrottledToFiveMinutes() {
        let now = Date()
        XCTAssertTrue(AccessPolicy.pairRequestDue(last: nil, now: now))
        XCTAssertFalse(AccessPolicy.pairRequestDue(last: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(AccessPolicy.pairRequestDue(last: now.addingTimeInterval(-301), now: now))
    }

    // MARK: - Quick actions and news verbs

    func testAskJkaiIsOnlyAQuickActionWithChat() {
        XCTAssertEqual(AccessPolicy.quickActions(for: .everything), [.ask, .health, .sync])
        XCTAssertEqual(AccessPolicy.quickActions(for: AppAccess(family: true)), [.health, .sync])
    }

    func testNewsVerbsFollowTheSitesCan() throws {
        let can = try JSONDecoder().decode(NewsCan.self, from: Data(#"{"graph":false,"research":true,"note":false,"ask":true}"#.utf8))
        XCTAssertEqual(AccessPolicy.newsActions(can: can, access: AppAccess(news: true)), [.favourite, .research])
    }

    func testNewsVerbsWithoutCanFallBackToTheFlags() {
        XCTAssertEqual(AccessPolicy.newsActions(can: nil, access: .everything), [.favourite, .graph, .note, .research])
        XCTAssertEqual(AccessPolicy.newsActions(can: nil, access: AppAccess(news: true)), [.favourite])
        XCTAssertEqual(AccessPolicy.newsActions(can: nil, access: AppAccess(news: true, research: true)), [.favourite, .research])
    }

    func testAMemberCannotAttachAudio() {
        XCTAssertFalse(ChatUpload.allowed(mime: "audio/mp4", owner: false))
        XCTAssertTrue(ChatUpload.allowed(mime: "application/pdf", owner: false))
        XCTAssertTrue(ChatUpload.allowed(mime: "image/jpeg", owner: false))
        XCTAssertTrue(ChatUpload.allowed(mime: "audio/mp4", owner: true))
    }

    // MARK: - The store

    @MainActor func testTheStoreAdoptsAViewAndPersistsIt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("access-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let outbox = try Outbox(url: url)
        let store = AccessStore(outbox: outbox, sitePaired: false)
        #if DEBUG
        try XCTSkipIf(SRDemo.isOn, "demo mode pins access")
        #endif
        XCTAssertEqual(store.current, .nothing)

        store.adopt(view: ViewAccess(flags: AppAccess(chat: true, family: true),
                                     sitePair: SitePairOffer(server: "https://strangeramblings.com", code: "c1", expiresAt: nil)))
        XCTAssertEqual(store.current, AppAccess(chat: true, family: true))
        XCTAssertEqual(outbox.state.access?.source, "view")
        XCTAssertEqual(store.takeOffer()?.code, "c1")
        XCTAssertNil(store.takeOffer(), "a code is spent once")

        // The same code again is not offered twice.
        store.adopt(view: ViewAccess(flags: AppAccess(chat: true, family: true),
                                     sitePair: SitePairOffer(server: "https://strangeramblings.com", code: "c1", expiresAt: nil)))
        XCTAssertNil(store.offer)

        // /api/native/me does not overrule the view.
        store.adopt(siteRole: "owner", flags: .nothing)
        XCTAssertEqual(store.current, AppAccess(chat: true, family: true))

        // A relaunch reads it back before any network.
        let again = AccessStore(outbox: try Outbox(url: url), sitePaired: false)
        XCTAssertEqual(again.current, AppAccess(chat: true, family: true))
    }

    @MainActor func testTheSitesAnswerFillsInWhereNoViewHasAnswered() throws {
        #if DEBUG
        try XCTSkipIf(SRDemo.isOn, "demo mode pins access")
        #endif
        let store = AccessStore(outbox: nil, sitePaired: true)
        XCTAssertEqual(store.current, .everything, "unknown and site-paired is the owner")
        store.adopt(siteRole: "member", flags: AppAccess(news: true))
        XCTAssertEqual(store.current, AppAccess(news: true))
        store.adopt(siteRole: "owner", flags: .nothing)
        XCTAssertEqual(store.current, .everything)
    }
}

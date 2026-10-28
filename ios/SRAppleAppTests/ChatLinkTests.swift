import XCTest
@testable import SRAppleApp

/// Links into one jkai thread, and an answer read aloud.
final class ChatLinkTests: XCTestCase {

    // MARK: - sr://chat/<id>

    func testTheAppLinkOpensTheThread() {
        XCTAssertEqual(ChatLink.from(url: URL(string: "sr://chat/c_123")!), ChatLink(conversationId: "c_123"))
        XCTAssertEqual(ChatLink.from(url: URL(string: "SR://Chat/abc-DEF")!), ChatLink(conversationId: "abc-DEF"))
        XCTAssertEqual(ChatLink.from(url: URL(string: "sr://chat")!), ChatLink(conversationId: nil), "the Chat page")
        XCTAssertEqual(ChatLink.from(url: URL(string: "sr://chat/")!), ChatLink(conversationId: nil))
        XCTAssertNil(ChatLink.from(url: URL(string: "sr://trips/abc")!))
        XCTAssertNil(ChatLink.from(url: URL(string: "https://strangeramblings.com/chat/abc")!))
    }

    func testAnIdThatIsNotAnIdOpensTheChatPage() {
        XCTAssertEqual(ChatLink.from(url: URL(string: "sr://chat/a%20b")!), ChatLink(conversationId: nil))
        XCTAssertEqual(ChatLink.from(url: URL(string: "sr://chat/" + String(repeating: "x", count: 200))!), ChatLink(conversationId: nil))
    }

    func testAppURLRoundTrips() {
        let url = ChatLink.appURL("c_123")
        XCTAssertEqual(url?.absoluteString, "sr://chat/c_123")
        XCTAssertEqual(url.flatMap(ChatLink.from(url:)), ChatLink(conversationId: "c_123"))
    }

    // MARK: - A tapped push

    func testAPushNamesItsThread() {
        XCTAssertEqual(ChatLink.conversationId(userInfo: ["category": "chat", "conversationId": "c1", "url": "/jkai?c=c2"]), "c1",
                       "the id first; the link is the fallback")
        // `privatePush`: a phone that hides details keeps only category and url.
        XCTAssertEqual(ChatLink.conversationId(userInfo: ["category": "chat", "url": "/jkai?c=c2"]), "c2")
        XCTAssertEqual(ChatLink.conversationId(userInfo: ["url": "https://strangeramblings.com/jkai?c=c3&x=1"]), "c3")
        XCTAssertEqual(ChatLink.conversationId(userInfo: ["url": "sr://chat/c4"]), "c4")
        XCTAssertNil(ChatLink.conversationId(userInfo: ["category": "chat", "url": "/jkai"]), "a push about chat with no thread")
        XCTAssertNil(ChatLink.conversationId(userInfo: ["url": "/jkai/daydreams?c=x"]), "a c= on another page is not a thread")
        XCTAssertNil(ChatLink.conversationId(userInfo: ["conversationId": "", "url": "javascript:alert(1)"]))
        XCTAssertNil(ChatLink.conversationId(userInfo: [:]))
    }

    // MARK: - Handoff and the web

    func testTheWebPathOpensTheThreadOnTheDesk() {
        XCTAssertEqual(ChatLink.webPath("c_123"), "jkai?c=c_123")
        XCTAssertEqual(ChatLink.webPath("a&b=c"), "jkai?c=a%26b%3Dc", "escaped as a value")
        XCTAssertEqual(ChatLink.conversationId(link: "/" + ChatLink.webPath("c_123")), "c_123")
    }

    // MARK: - Read aloud

    func testMarkdownIsReadAsWords() {
        let spoken = SpokenText.plain("""
        ## Your week
        **Recovery** is *up* — see [the chart](https://strangeramblings.com/health).
        - Sleep: `7h 40m`
        - [x] Run done
        > Quoted ~~not~~ line
        ---
        | Day | Load |
        | --- | ---: |
        | Mon | 12 |
        """)
        XCTAssertEqual(spoken, """
        Your week
        Recovery is up — see the chart.
        Sleep: 7h 40m
        Run done
        Quoted not line
        Day, Load
        Mon, 12
        """)
    }

    func testCodeIsNamedNotRead() {
        let spoken = SpokenText.plain("Try this:\n```swift\nlet x = 1\nprint(x)\n```\nThen run it.")
        XCTAssertEqual(spoken, "Try this:\nThere is a code block here.\nThen run it.")
    }

    func testABareLinkAndALoneAsteriskSurvive() {
        XCTAssertEqual(SpokenText.plain("Open https://example.com/a/very/long/path now"), "Open a link now")
        XCTAssertEqual(SpokenText.plain("2 * 3 is 6"), "2 * 3 is 6")
        XCTAssertEqual(SpokenText.plain("snake_case_name stays"), "snake_case_name stays")
    }
}

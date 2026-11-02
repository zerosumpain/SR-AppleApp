import SwiftUI
import UIKit
import WebKit

// The screens for an sr. tv party (`TVParty.swift`): the wait for the TV, the
// party's web page for a game this build cannot play, and what somebody
// without games in the app is told.

/// Navigation value: the wait at one TV, pushed on the Games stack.
struct TVPartyRef: Hashable {
    let code: String
}

/// Navigation value: the party's own web page, for a game the app has no
/// screen for. `seat` signs the page in as this member when the site sent one.
struct TVPartyWebRef: Hashable {
    let code: String
    var partyId: String? = nil
    var seat: String? = nil
    /// The game's name for the bar, when known.
    var title: String? = nil
}

/// "Joining the living room TV…": who is in, the TV's notice, and the wait
/// for it to start a game — which then opens by itself.
struct TVPartyScreen: View {
    let ref: TVPartyRef
    @StateObject private var store: TVPartyStore
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss

    init(ref: TVPartyRef) {
        self.ref = ref
        _store = StateObject(wrappedValue: TVPartyStore(code: ref.code))
    }

    var body: some View {
        Group {
            switch store.state {
            case .joining:
                joining
            case .failed(let sentence, let web):
                failed(sentence, web: web)
            case .waiting(let party):
                waiting(party)
            }
        }
        .navigationTitle("sr. tv")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        // Re-runs each time the wait is on screen again — back from a game,
        // the party is read at once and the next game opens by itself.
        .task { await store.run { step in open(step) } }
    }

    private func open(_ step: TVPartyStep) {
        guard let party = store.party, let room = party.roomId else { return }
        switch step {
        case .wait:
            return
        case .openRoom(let id, let game):
            store.opened = id
            SRHaptic.ok()
            router.push(GameRoomRef(id: id, game: game), on: .games)
        case .openWeb:
            store.opened = room
            SRHaptic.ok()
            router.push(webRef(party), on: .games)
        }
    }

    private func webRef(_ party: TVPartyView) -> TVPartyWebRef {
        TVPartyWebRef(code: party.code, partyId: store.partyId, seat: store.seat, title: party.gameTitle)
    }

    // MARK: States

    private var joining: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(SR.accent)
            Text("Joining the TV…")
                .font(SR.Text.display(19))
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.center)
            Text(ref.code)
                .font(SR.Text.mono(15))
                .foregroundStyle(SR.inkMuted)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srPaper()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tv-party-joining")
    }

    private func failed(_ sentence: String, web: Bool) -> some View {
        VStack(spacing: 12) {
            SREmpty(
                title: "Couldn\u{2019}t join the TV",
                icon: "tv",
                message: sentence,
                actionLabel: "Close",
                action: { dismiss() }
            )
            if web, TVPartyLink.code(ref.code) != nil {
                Button {
                    router.push(TVPartyWebRef(code: ref.code), on: .games)
                } label: {
                    SRButtonLabel(title: "Join on the web page")
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("tv-party-web")
            }
        }
        .frame(maxHeight: .infinity)
        .srPaper()
        .accessibilityIdentifier("tv-party-failed")
    }

    private func waiting(_ party: TVPartyView) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "sr. tv · \(party.code)",
                             title: party.tvName,
                             strap: strap(party))

                if let notice = party.notice {
                    SRCard(accented: true) {
                        Text(notice)
                            .font(SR.Text.bodyMedium(16))
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("tv-party-notice")
                }

                status(party)

                members(party)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("tv-party")
        .srAnimation(.snappy, value: party.members.map(\.id))
    }

    private func strap(_ party: TVPartyView) -> String {
        if party.roomId == nil {
            return "You\u{2019}re in. Waiting for the TV to start\u{2026}"
        }
        return "You\u{2019}re in. \(party.gameTitle ?? "A game") is on."
    }

    @ViewBuilder
    private func status(_ party: TVPartyView) -> some View {
        if let room = party.roomId, room == store.opened {
            // Back from a game still running: one tap back into it.
            Button {
                SRHaptic.tap()
                if TVPartyStep.playsNatively(party.game ?? "") {
                    router.push(GameRoomRef(id: room, game: party.game), on: .games)
                } else {
                    router.push(webRef(party), on: .games)
                }
            } label: {
                SRButtonLabel(title: "Back to \(party.gameTitle ?? "the game")", icon: "play.fill", fill: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("tv-party-back-to-game")
        } else if party.roomId == nil {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(SR.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Waiting for the TV to start\u{2026}")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    if let next = party.gameTitle {
                        Text("Next up: \(next)")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tv-party-waiting")
        }
    }

    private func members(_ party: TVPartyView) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Who\u{2019}s in", trailing: "\(party.members.count)")
            SRCard {
                VStack(alignment: .leading, spacing: 10) {
                    if party.members.isEmpty {
                        Text("Nobody yet.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                    }
                    ForEach(party.members) { member in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(member.online ? SR.good : SR.inkMuted.opacity(0.4))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text(member.name)
                                .font(SR.Text.bodyMedium(16))
                                .foregroundStyle(SR.ink)
                            Spacer(minLength: 8)
                            if member.kind == "guest" {
                                Text("Guest")
                                    .font(SR.Text.mono())
                                    .foregroundStyle(SR.inkMuted)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(member.name)\(member.kind == "guest" ? ", guest" : "")\(member.online ? "" : ", away")")
                    }
                }
            }
        }
        .accessibilityIdentifier("tv-party-members")
    }
}

// MARK: - Without games in the app

/// Somebody whose access has no games: say so, and offer the party's page,
/// where anyone can join by name.
struct TVPartyNoAccessView: View {
    let code: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            SREmpty(
                title: "Games aren\u{2019}t on for you yet",
                icon: "tv",
                message: "Joining the TV as yourself needs games in the app \u{2014} ask whoever runs your family\u{2019}s access. You can still join on the web page by typing your name."
            )
            if TVPartyLink.code(code) != nil {
                Button {
                    SRHaptic.tap()
                    openWeb = true
                } label: {
                    SRButtonLabel(title: "Join on the web page")
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("tv-party-web")
            }
        }
        .frame(maxHeight: .infinity)
        .srPaper()
        .navigationTitle("sr. tv")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .navigationDestination(isPresented: $openWeb) {
            TVPartyWebScreen(ref: TVPartyWebRef(code: code))
        }
        .accessibilityIdentifier("tv-party-no-access")
    }

    @State private var openWeb = false
}

// MARK: - The party's web page

/// The party's page on the site (`/games/join/<CODE>`) in a web view, for a
/// game this build has no screen for.
///
/// It is signed in as this member only when the site sent the party's seat
/// with the join (`TVPartyJoinAnswer.seat`): the app puts it in the web view's
/// cookie store as `sr_seat_<partyId>`, the cookie the page itself sets. The
/// app's other web sign-in (`sr_app_session`, Wildmind's) is for extracted
/// applications only and the main site never reads it, so without a seat the
/// page asks for a name and the member plays as a guest.
struct TVPartyWebScreen: View {
    let ref: TVPartyWebRef
    @State private var url: URL?
    @State private var failed: String?

    var body: some View {
        ZStack {
            if let url {
                TVPartyWebView(url: url, failed: $failed)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(SR.accent)
            }
            if let failed {
                SREmpty(
                    title: "The page didn\u{2019}t open",
                    icon: "wifi.exclamationmark",
                    message: failed,
                    actionLabel: "Try again",
                    action: { reload() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srPaper()
        .navigationTitle(ref.title ?? "sr. tv")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("tv-party-web-page")
        .task { await prepare() }
    }

    private func reload() {
        failed = nil
        let current = url
        url = nil
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            url = current
            if url == nil { await prepare() }
        }
    }

    private func prepare() async {
        guard url == nil, TVPartyLink.code(ref.code) != nil else { return }
        let page = SiteClient.shared.webURL(TVPartyLink.webPath(code: ref.code))
        if let seat = ref.seat, let partyId = ref.partyId, let host = page.host,
           let cookie = TVPartyWebSeat.cookie(seat: seat, partyId: partyId, host: host, secure: page.scheme == "https") {
            await WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
        }
        url = page
    }
}

/// The party page's seat cookie, as the page itself sets it (SR-Main
/// `setSeatCookie`). PURE apart from building the cookie.
enum TVPartyWebSeat {
    static func name(partyId: String) -> String { "sr_seat_\(partyId)" }

    static func cookie(seat: String, partyId: String, host: String, secure: Bool, now: Date = Date()) -> HTTPCookie? {
        // Ids are `pt_` and hex; anything else never becomes a cookie name.
        guard partyId.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), !seat.isEmpty, !seat.contains(";") else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name(partyId: partyId),
            .value: seat,
            .domain: host,
            .path: "/",
            .expires: now.addingTimeInterval(12 * 60 * 60),
            HTTPCookiePropertyKey("HttpOnly"): "TRUE",
            .sameSitePolicy: HTTPCookieStringPolicy.sameSiteLax.rawValue,
        ]
        if secure { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}

/// A plain web view onto the site. Only the site's own pages load in it; the
/// page's `sr://games/join/…` hand-off to the app is refused (the app is
/// already here), so the page falls through to its own join form.
struct TVPartyWebView: UIViewRepresentable {
    let url: URL
    @Binding var failed: String?

    func makeCoordinator() -> Coordinator { Coordinator(page: url, failed: $failed) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.applicationNameForUserAgent = "SRAppleApp-TV/1"
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.allowsBackForwardNavigationGestures = false
        web.navigationDelegate = context.coordinator
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let page: URL
        let failed: Binding<String?>

        init(page: URL, failed: Binding<String?>) {
            self.page = page
            self.failed = failed
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            if TVPartyWebPolicy.allows(url, page: page) { return .allow }
            // Anything else the page links to opens in the browser; the app's
            // own scheme (the page trying to hand over) is simply refused.
            if action.navigationType == .linkActivated, url.scheme == "https" {
                _ = await UIApplication.shared.open(url)
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            failed.wrappedValue = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            failed.wrappedValue = error.localizedDescription
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.load(URLRequest(url: page))
        }
    }
}

/// What may load in the party web view. PURE.
enum TVPartyWebPolicy {
    /// The site's own pages (same scheme, host and port as the party page),
    /// plus `about:` frames. Never `sr://`.
    static func allows(_ url: URL, page: URL) -> Bool {
        if url.scheme == "about" { return true }
        guard url.scheme == page.scheme, url.scheme == "https" || url.scheme == "http" else { return false }
        return url.host == page.host && url.port == page.port
    }
}

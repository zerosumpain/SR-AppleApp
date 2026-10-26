import SwiftUI
import UIKit
import WebKit

// The valley in 3D: Wildmind's own page (strangeramblings.com/wildmind), the
// three.js world the desktop shows, in a web view, with the app's glass bars
// drawn over it (`WildmindWorldScreen`). The engine stays the web one, like
// Marbler's: everything the desktop gains, the phone gains the same day.
//
// Signing in. The phone has a device credential, not a browser session, and
// a web view's requests cannot carry a bearer header. So the app asks SR-Main
// for a cookie (`POST api/native/wildmind/web-session`, owner only) and puts
// it in the web view's store before loading the page. Wildmind sends it to
// the site's session authority like any cookie; the site answers for it only
// to Wildmind and only while this phone stays paired.
//
// The bridge. Every page in the web view gets `window.__srApp` before its
// scripts run, which turns on the page's app layout (Wildmind's
// `client/app.ts`): no top bar, the world full-screen, the panel as a sheet.
// The page posts `ready`, `state` (clock, speed, people, what is open) and
// `news` to the `wildmind` message handler; the app steers through
// `window.wildmind.*` — pause, speed, view, panel, follow, watch, sound,
// insets — the same things the page's own controls do.

/// What the page last said about itself, for the bars.
struct WildmindWorldState: Equatable {
    struct Person: Equatable, Identifiable {
        let id: String
        let name: String
        let main: Bool
        let alive: Bool
        let activity: String
        let label: String
        let health: Int
        let thinking: Bool
        let alarm: Int
    }

    var day = 0
    var season = ""
    var dayOfSeason = 0
    var clock = "--:--"
    var daylight = 1.0
    var weather = "clear"
    var temperature = 0
    var speed = 1.0
    var paused = false
    var holding: [String] = []
    var modelAvailable: Bool?
    var modelStatus = ""
    var people: [Person] = []
    var map = false
    var watching = false
    var sound = false
    var panel: String?
    var selected = ""
    var following = true

    init() {}

    init?(_ d: [String: Any]) {
        guard d["t"] as? String == "state" else { return nil }
        day = d["day"] as? Int ?? 0
        season = d["season"] as? String ?? ""
        dayOfSeason = d["dayOfSeason"] as? Int ?? 0
        clock = d["clock"] as? String ?? "--:--"
        daylight = (d["daylight"] as? NSNumber)?.doubleValue ?? 1
        weather = d["weather"] as? String ?? "clear"
        temperature = d["temperature"] as? Int ?? 0
        speed = (d["speed"] as? NSNumber)?.doubleValue ?? 1
        paused = d["paused"] as? Bool ?? false
        holding = d["holding"] as? [String] ?? []
        if let model = d["model"] as? [String: Any] {
            modelAvailable = model["available"] as? Bool
            modelStatus = model["status"] as? String ?? ""
        }
        people = (d["people"] as? [[String: Any]] ?? []).compactMap { p in
            guard let id = p["id"] as? String, let name = p["name"] as? String else { return nil }
            return Person(
                id: id, name: name, main: p["main"] as? Bool ?? false, alive: p["alive"] as? Bool ?? true,
                activity: p["activity"] as? String ?? "", label: p["label"] as? String ?? "",
                health: p["health"] as? Int ?? 0, thinking: p["thinking"] as? Bool ?? false, alarm: p["alarm"] as? Int ?? 0
            )
        }
        map = d["map"] as? Bool ?? false
        watching = d["watching"] as? Bool ?? false
        sound = d["sound"] as? Bool ?? false
        panel = d["panel"] as? String
        selected = d["selected"] as? String ?? ""
        following = d["following"] as? Bool ?? true
    }

    /// "Day 337 · summer 8/10".
    var dayLine: String { day > 0 ? "Day \(day) \u{00B7} \(season) \(dayOfSeason)/10" : "The valley" }

    /// "☀ 12°C": the sky as the page words it.
    var skyLine: String {
        let sky: String
        switch weather {
        case "rain": sky = "Rain"
        case "storm": sky = "Storm"
        case "snow": sky = "Snow"
        case "fog": sky = "Fog"
        case "cloudy": sky = "Cloudy"
        default: sky = daylight < 0.2 ? "Clear night" : "Clear"
        }
        return "\(sky) \(temperature)\u{00B0}C"
    }

    var skyIcon: String {
        switch weather {
        case "rain": return "cloud.rain"
        case "storm": return "cloud.bolt.rain"
        case "snow": return "snowflake"
        case "fog": return "cloud.fog"
        case "cloudy": return "cloud"
        default: return daylight < 0.2 ? "moon.stars" : "sun.max"
        }
    }

    /// Any alarm standing on a living person: the Econ panel's red button.
    var alarm: Int { people.filter(\.alive).map(\.alarm).max() ?? 0 }
}

/// The speeds the page offers, as its own menu lists them.
enum WildmindSpeed {
    static let all: [Double] = [0.25, 0.5, 1, 2, 4, 8, 16, 32, 64]

    static func label(_ x: Double) -> String {
        switch x {
        case 0.25: return "\u{00BC}\u{00D7}"
        case 0.5: return "\u{00BD}\u{00D7}"
        default: return "\(Int(x))\u{00D7}"
        }
    }
}

/// The panel tabs the page's sheet has (Wildmind `index.html`).
enum WildmindPanel: String, CaseIterable, Identifiable {
    case mind, economy, together, inventions, chronicle, world

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mind: return "Mind"
        case .economy: return "Econ"
        case .together: return "Together"
        case .inventions: return "Inventions"
        case .chronicle: return "Chronicle"
        case .world: return "World"
        }
    }

    var icon: String {
        switch self {
        case .mind: return "brain.head.profile"
        case .economy: return "hourglass"
        case .together: return "person.2"
        case .inventions: return "lightbulb"
        case .chronicle: return "book"
        case .world: return "globe.europe.africa"
        }
    }
}

/// Wildmind's other pages, each opened in its own web view on the stack.
enum WildmindPlace: String, CaseIterable, Hashable, Identifiable {
    case economy, stats, lineage, story, engine, calls, how, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .economy: return "Economy"
        case .stats: return "Stats"
        case .lineage: return "Lineage"
        case .story: return "Story"
        case .engine: return "Engine"
        case .calls: return "Calls"
        case .how: return "How it works"
        case .settings: return "Settings"
        }
    }

    var hint: String {
        switch self {
        case .economy: return "Hours, supply and demand"
        case .stats: return "How lives are spent"
        case .lineage: return "Lives and what the next inherits"
        case .story: return "What each knew, and when"
        case .engine: return "The engine as a live flow"
        case .calls: return "What the minds were asked"
        case .how: return "Decisions, instincts, the model"
        case .settings: return "Key, models, budget, people"
        }
    }

    var icon: String {
        switch self {
        case .economy: return "chart.line.uptrend.xyaxis"
        case .stats: return "chart.bar"
        case .lineage: return "tree"
        case .story: return "text.book.closed"
        case .engine: return "gearshape.2"
        case .calls: return "text.bubble"
        case .how: return "questionmark.circle"
        case .settings: return "slider.horizontal.3"
        }
    }
}

/// The cookie that signs the web view in, minted by the site for this phone.
enum WildmindWebSession {
    private struct Answer: Decodable {
        struct Cookie: Decodable {
            let name: String
            let value: String
            let domain: String
            let path: String
            let expiresAt: String
        }
        let url: String
        let cookie: Cookie
    }

    /// The page's address, after the cookie is in the shared web store.
    /// A fresh cookie each time: minting one is a signature, not a row.
    @MainActor
    static func prepare() async throws -> URL {
        let answer: Answer = try await SiteClient.shared.send("api/native/wildmind/web-session", method: "POST", body: Data("{}".utf8))
        guard let url = URL(string: answer.url), url.scheme == "https" else {
            throw SiteError.message("The site gave the valley an address this app will not open.")
        }
        let expires = ISO8601DateFormatter.wildmind.date(from: answer.cookie.expiresAt) ?? Date().addingTimeInterval(3600)
        let properties: [HTTPCookiePropertyKey: Any] = [
            .name: answer.cookie.name,
            .value: answer.cookie.value,
            .domain: answer.cookie.domain,
            .path: answer.cookie.path,
            .expires: expires,
            .secure: "TRUE",
            HTTPCookiePropertyKey("HttpOnly"): "TRUE",
            .sameSitePolicy: HTTPCookieStringPolicy.sameSiteLax.rawValue,
        ]
        guard let cookie = HTTPCookie(properties: properties) else {
            throw SiteError.message("The valley\u{2019}s sign-in could not be kept on this phone.")
        }
        await WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
        return url
    }

    /// Whether a URL is one of Wildmind's own pages, which the web views may show.
    static func isWildmind(_ url: URL?, page: URL) -> Bool {
        guard let url, url.scheme == "https", url.host == page.host else { return false }
        return url.path == "/wildmind" || url.path.hasPrefix("/wildmind/")
    }
}

private extension ISO8601DateFormatter {
    static let wildmind: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// The world screen's model: the page's state, and the way to steer it.
@MainActor
final class WildmindWorldModel: ObservableObject {
    enum Phase: Equatable {
        case signingIn
        case loading
        case ready
        case failed(String)
    }

    @Published var phase: Phase = .signingIn
    @Published var state = WildmindWorldState()
    /// The newest moment worth telling, shown briefly under the top bar.
    @Published var news: String?
    weak var webView: WKWebView?
    private(set) var pageURL: URL?
    private var newsClear: Task<Void, Never>?

    /// Mint the cookie and load the valley (again).
    func start() async {
        phase = .signingIn
        do {
            let url = try await WildmindWebSession.prepare()
            pageURL = url
            phase = .loading
            webView?.load(URLRequest(url: url))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func receive(_ body: Any) {
        guard let d = body as? [String: Any], let t = d["t"] as? String else { return }
        switch t {
        case "ready":
            phase = .ready
        case "state":
            if let next = WildmindWorldState(d), next != state { state = next }
            if phase != .ready { phase = .ready }
        case "news":
            let kind = d["kind"] as? String ?? ""
            switch kind {
            case "danger", "death": SRHaptic.bad()
            case "invention", "birth": SRHaptic.ok()
            default: SRHaptic.tap()
            }
            show(d["text"] as? String)
        default:
            break
        }
    }

    private func show(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        news = text
        newsClear?.cancel()
        newsClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.news = nil
        }
    }

    // MARK: - Steering

    func setPaused(_ on: Bool) { call("pause(\(on))"); state.paused = on }
    func setSpeed(_ x: Double) { call("speed(\(x))"); state.speed = x; state.paused = false }
    func setMap(_ on: Bool) { call("view('\(on ? "map" : "3d")')"); state.map = on }
    func openPanel(_ panel: WildmindPanel?) {
        call("panel(\(panel.map { "'\($0.rawValue)'" } ?? "null"))")
        state.panel = panel?.rawValue
    }
    func follow(_ id: String) {
        let letGo = state.following && state.selected == id
        call("follow(\(Self.js(id)), \(!letGo))")
    }
    func setWatching(_ on: Bool) { call("watch(\(on))") }
    func setSound(_ on: Bool) { call("sound(\(on))") }
    func techTree() { call("techTree()") }
    func insets(top: CGFloat, bottom: CGFloat) { call("insets(\(Int(top)), \(Int(bottom)))") }
    func refresh() { call("refresh()") }

    /// Low detail draws without the ink pass; the page reads it once, so reload.
    func setQuality(_ high: Bool) {
        call("quality('\(high ? "high" : "low")')")
        webView?.reload()
    }

    private func call(_ js: String) {
        // `wildmind` is absent until the page has run its scripts: then the
        // call does nothing, and the next state message corrects the bars.
        webView?.evaluateJavaScript("window.wildmind && window.wildmind.\(js)", completionHandler: nil)
    }

    /// A string as a JavaScript literal.
    private static func js(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }
}

/// The script every page in a Wildmind web view gets before its own.
private let wildmindAppFlag = WKUserScript(
    source: "window.__srApp = { v: 1 };",
    injectionTime: .atDocumentStart,
    forMainFrameOnly: true
)

/// The web view the valley runs in. Only Wildmind's pages may load in it.
struct WildmindWorldWebView: UIViewRepresentable {
    let model: WildmindWorldModel
    /// Asked to open one of Wildmind's other pages, from a link in the valley.
    let open: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(model: model, open: open) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.addUserScript(wildmindAppFlag)
        // A weak trampoline: the content controller retains its handlers, and
        // the coordinator must not keep the web view alive through it.
        config.userContentController.add(WeakHandler(context.coordinator), name: "wildmind")
        config.allowsInlineMediaPlayback = true
        config.applicationNameForUserAgent = "SRAppleApp-Wildmind/1"
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        // The valley's sky before the first frame (the page's #stage colour).
        web.backgroundColor = UIColor(red: 0x8f / 255, green: 0xa3 / 255, blue: 0xad / 255, alpha: 1)
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsBackForwardNavigationGestures = false
        web.navigationDelegate = context.coordinator
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        model.webView = web
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "wildmind")
        web.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let model: WildmindWorldModel
        let open: (URL) -> Void

        init(model: WildmindWorldModel, open: @escaping (URL) -> Void) {
            self.model = model
            self.open = open
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            model.receive(message.body)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let page = model.pageURL else { return .cancel }
            let url = action.request.url
            // The valley itself (a reload, or the first load).
            if let url, WildmindWebSession.isWildmind(url, page: page), url.path == page.path || url.path + "/" == page.path {
                return .allow
            }
            // Another of Wildmind's pages: on its own screen, so the world keeps running.
            if action.navigationType == .linkActivated, let url, WildmindWebSession.isWildmind(url, page: page) {
                open(url)
                return .cancel
            }
            // Sent to the site's sign-in: the cookie was not taken.
            if url?.path == "/login" {
                model.phase = .failed("The site didn\u{2019}t let the valley in. Try again; if it keeps happening, pair this iPhone again.")
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            if let http = response.response as? HTTPURLResponse, response.isForMainFrame, http.statusCode >= 400 {
                model.phase = .failed(http.statusCode == 403
                    ? "The valley is watched from the owner\u{2019}s phone."
                    : "The valley didn\u{2019}t answer (\(http.statusCode)).")
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            model.phase = .failed(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            model.phase = .failed(error.localizedDescription)
        }

        /// The GPU process can be killed under memory pressure: load again.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Task { await model.start() }
        }
    }

    final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?

        init(_ target: WKScriptMessageHandler) { self.target = target }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(controller, didReceive: message)
        }
    }
}

/// One of Wildmind's other pages (Economy, Stats, Lineage…), in a plain web
/// view under the app's navigation bar. Links between those pages stay in it.
struct WildmindWebPageView: UIViewRepresentable {
    let url: URL
    @Binding var failed: String?

    func makeCoordinator() -> Coordinator { Coordinator(page: url, failed: $failed) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.addUserScript(wildmindAppFlag)
        config.applicationNameForUserAgent = "SRAppleApp-Wildmind/1"
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = context.coordinator
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let page: URL
        let failed: Binding<String?>

        init(page: URL, failed: Binding<String?>) {
            self.page = page
            self.failed = failed
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if WildmindWebSession.isWildmind(action.request.url, page: page) { return .allow }
            // Anything else the page links to opens in the browser.
            if action.navigationType == .linkActivated, let url = action.request.url, url.scheme == "https" {
                _ = await UIApplication.shared.open(url)
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            failed.wrappedValue = error.localizedDescription
        }
    }
}

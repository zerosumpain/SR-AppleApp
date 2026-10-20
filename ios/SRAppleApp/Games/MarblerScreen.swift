import SwiftUI
import UIKit
import WebKit

// Marbler, the marble-race game (`~/marbler`, public at
// strangeramblings.com/projects/marbler/). The engine stays the web one:
// this screen loads its phone page, `mobile.html`, in a web view, and the
// physics and drawing run here on the phone. Courses come from the page's
// course pack, generated ahead of time, so the phone never runs the
// generator.
//
// The page posts race events to the `marbler` message handler (see
// `src/mobile/bridge.ts`); the app answers with haptics and steers through
// `window.marbler.*`. Each pack course carries the race Node recorded, and
// the page checks this phone ran the very same race: that and the frame
// rate are what the spike measures, so the ⋯ menu shows them beside the
// phone's thermal state.

/// Navigation value for Marbler, pushed on the Games stack.
struct MarblerRef: Hashable {}

/// What the page has told us, plus the phone's own side of the spike.
@MainActor
final class MarblerModel: ObservableObject {
    @Published var course = ""
    @Published var fps: Int?
    @Published var minFps: Int?
    @Published var simMs: Double?
    @Published var checks: String?
    @Published var bench: String?
    @Published var error: String?
    @Published var thermal = ProcessInfo.processInfo.thermalState
    /// Set by the web view once it exists, for calls into the page.
    weak var webView: WKWebView?

    /// The phone page. A debug build may point it elsewhere (HTTPS only) with
    /// `-marblerURL https://…` as a launch argument.
    static var pageURL: URL {
        #if DEBUG
        if let text = UserDefaults.standard.string(forKey: "marblerURL"), let url = URL(string: text), url.scheme == "https" {
            return url
        }
        #endif
        return URL(string: "https://strangeramblings.com/projects/marbler/mobile.html")!
    }

    func call(_ script: String) {
        webView?.evaluateJavaScript("window.marbler && window.marbler.\(script)")
    }

    func receive(_ body: Any) {
        guard let m = body as? [String: Any], let type = m["type"] as? String else { return }
        switch type {
        case "course":
            course = m["name"] as? String ?? ""
            checks = nil
            bench = nil
        case "finish":
            if (m["place"] as? Int) == 1 { SRHaptic.tap() }
        case "won":
            SRHaptic.ok()
        case "check":
            let matched = m["matched"] as? Int ?? 0
            if let at = m["divergedAt"] as? Int {
                checks = "Parted from Node's race at \(at / 60) s"
                SRHaptic.bad()
            } else {
                checks = "\(matched) checks match Node"
            }
        case "bench":
            let ok = m["ok"] as? Bool ?? false
            let perSecond = m["stepsPerSecond"] as? Int ?? 0
            bench = "\(ok ? "Same race" : "Different race") · \(perSecond / 60)× real time"
            ok ? SRHaptic.ok() : SRHaptic.bad()
        case "stats":
            fps = m["fps"] as? Int
            minFps = m["minFps"] as? Int
            simMs = m["simMs"] as? Double
        case "error":
            error = m["message"] as? String
        default:
            break
        }
    }

    var thermalText: String {
        switch thermal {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

struct MarblerScreen: View {
    @StateObject private var model = MarblerModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MarblerWebView(model: model)
            .ignoresSafeArea(edges: .bottom)
            .background(Color(red: 0x14 / 255, green: 0x10 / 255, blue: 0x0c / 255))
            .overlay {
                if let error = model.error {
                    VStack(spacing: 12) {
                        Text("Marbler couldn't start")
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                        Text(error)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .multilineTextAlignment(.center)
                        Button("Try again") {
                            model.error = nil
                            model.webView?.load(URLRequest(url: MarblerModel.pageURL))
                        }
                        .accessibilityIdentifier("marbler-retry")
                    }
                    .padding(SR.gutter)
                    .background(SR.surface)
                }
            }
            .navigationTitle("Marbler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Spike") {
                            Text(model.fps.map { "\($0) fps · lowest \(model.minFps ?? $0)" } ?? "fps: waiting")
                            Text(model.simMs.map { String(format: "Physics %.2f ms a frame", $0) } ?? "Physics: waiting")
                            Text("Thermal state: \(model.thermalText)")
                            Text(model.checks ?? "Checks: waiting")
                            Text(model.bench ?? "Headless check: not run")
                        }
                        Button("Run the whole race headless") { model.call("bench()") }
                        Button("Next course") { model.call("next()") }
                        Button("Race again") { model.call("again()") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("marbler-menu")
                }
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .onChange(of: scenePhase) { _, phase in
                model.call(phase == .active ? "resume()" : "pause()")
            }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                model.thermal = ProcessInfo.processInfo.thermalState
            }
            .accessibilityIdentifier("marbler-screen")
    }
}

/// The web view the race runs in. Only the Marbler page may load in it.
struct MarblerWebView: UIViewRepresentable {
    let model: MarblerModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // A weak trampoline: the content controller retains its handlers, and
        // the coordinator must not keep the web view alive through it.
        config.userContentController.add(WeakHandler(context.coordinator), name: "marbler")
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0x14 / 255, green: 0x10 / 255, blue: 0x0c / 255, alpha: 1)
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = context.coordinator
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        model.webView = web
        web.load(URLRequest(url: MarblerModel.pageURL))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "marbler")
        web.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let model: MarblerModel

        init(model: MarblerModel) { self.model = model }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            model.receive(message.body)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            // The page's own address (it rewrites ?course= in place), nothing else.
            let page = MarblerModel.pageURL
            let ok = action.request.url.map { $0.host == page.host && $0.path == page.path } ?? false
            return ok ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            model.error = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.error = error.localizedDescription
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // iOS killed the page (usually memory): start it again rather than leave a blank screen.
            webView.load(URLRequest(url: MarblerModel.pageURL))
        }
    }

    /// Holds the real handler weakly, so the content controller can't keep it alive.
    @MainActor
    final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?

        init(_ target: WKScriptMessageHandler) { self.target = target }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(controller, didReceive: message)
        }
    }
}

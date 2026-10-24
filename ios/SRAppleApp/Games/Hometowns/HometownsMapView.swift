import SwiftUI
import UIKit
import WebKit

// The town map: the site's versioned map page (`/projects/hometowns/<engineHash>/
// mobile.html?app=1`) in a web view, the `MarblerScreen.swift` pattern. The
// page draws the town with Pixi, owns every gesture on the map (plan, ghosts,
// lenses, the time-lapse) and runs the engine in a worker for its forecasts
// and its exact local ticks. It posts typed messages to the `hometowns`
// handler, which `HometownsStore.receive` reads; the store calls back into
// `window.hometowns.*`.
//
// Only the Hometowns page may load here, and only over HTTPS. The page does
// no authenticated network, so nothing it could navigate to would carry a
// credential, but a link off the map would still be a door out of the app.
//
// In a demo the map is a drawn stand-in: the demo answers the site's API from
// fixtures, and the page itself would be a request to the internet.

struct HometownsMapView: View {
    @ObservedObject var store: HometownsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if SRDemo.isOn {
                HometownsMapStandIn(town: store.town)
            } else if let url = store.pageURL {
                HometownsWebView(store: store, url: url)
                    .overlay {
                        if !store.pageReady && store.pageError == nil {
                            ProgressView().tint(SR.accent)
                        }
                    }
            } else {
                ProgressView().tint(SR.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay {
            if let error = store.pageError {
                VStack(spacing: 12) {
                    Text("The map couldn't load")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text(error)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        store.pageError = nil
                        store.pageLoading()
                        if let url = store.pageURL { store.webView?.load(URLRequest(url: url)) }
                    } label: {
                        SRButtonLabel(title: "Try again", icon: "arrow.clockwise")
                    }
                    .srButton(.prominent)
                    .accessibilityIdentifier("hometowns-map-retry")
                }
                .padding(SR.gutter)
                .srGlassCard(.paper)
                .padding(SR.gutter)
            }
        }
        #if DEBUG
        .overlay(alignment: .topLeading) { HometownsDebugHUD(store: store) }
        #endif
        // The page boots with the wording, theme and motion of the moment;
        // a parent switching a seat, dark mode or Reduce Motion later reaches
        // it here (the page's `settings` takes each of them).
        .onAppear { store.pageSettings(dark: colorScheme == .dark, reduceMotion: reduceMotion) }
        .onChange(of: colorScheme) { _, scheme in store.pageSettings(dark: scheme == .dark, reduceMotion: reduceMotion) }
        .onChange(of: reduceMotion) { _, on in store.pageSettings(dark: colorScheme == .dark, reduceMotion: on) }
        .onChange(of: store.level) { _, _ in store.pageSettings(dark: colorScheme == .dark, reduceMotion: reduceMotion) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map of \(store.town?.name ?? "your town")")
        .accessibilityIdentifier("hometowns-map")
    }
}

/// The web view the page runs in.
struct HometownsWebView: UIViewRepresentable {
    let store: HometownsStore
    let url: URL

    /// The page's ground colour, so the first frame is not a white flash.
    static let ground = UIColor(red: 0xE8 / 255, green: 0xE4 / 255, blue: 0xD4 / 255, alpha: 1)

    func makeCoordinator() -> Coordinator { Coordinator(store: store, url: url) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // A weak trampoline: the content controller retains its handlers, and
        // the coordinator must not keep the web view alive through it.
        config.userContentController.add(WeakHandler(context.coordinator), name: "hometowns")
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = Self.ground
        // The page pans and zooms the map itself (one finger pans, two pinch).
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsLinkPreview = false
        web.navigationDelegate = context.coordinator
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        store.webView = web
        store.pageLoading()
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        // A new engine hash on the wire names a new page (§10.10). The page
        // asks for it itself (`needReload`, debounced A39); this catches a
        // page that never loaded far enough to ask.
        if context.coordinator.url != url, !store.pageReady {
            context.coordinator.url = url
            store.pageLoading()
            web.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "hometowns")
        web.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let store: HometownsStore
        var url: URL

        init(store: HometownsStore, url: URL) {
            self.store = store
            self.url = url
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            // Only the map page itself may speak for the county (a `commit`
            // posts real moves): its main frame, over HTTPS, on the page's host.
            let origin = message.frameInfo.securityOrigin
            guard message.frameInfo.isMainFrame, origin.protocol == "https", origin.host == url.host else { return }
            store.receive(message.body)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            // The Hometowns pages on this county's host, over HTTPS, and nothing else.
            guard let target = action.request.url else { return .cancel }
            let ok = target.scheme == "https" && target.host == url.host
                && (target.path.hasPrefix("/projects/hometowns/") || target.path == url.path)
            return ok ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        /// A navigation that failed, unless it is one this coordinator stopped
        /// itself: a cancelled load, and the "Frame load interrupted" (WebKit
        /// error 102) that cancelling a response causes, which would otherwise
        /// replace the sentence that response already set.
        private func fail(_ error: Error) {
            let e = error as NSError
            if (error as? URLError)?.code == .cancelled { return }
            if e.domain == "WebKitErrorDomain" && e.code == 102 { return }
            if store.pageError != nil { return }
            store.pageError = error.localizedDescription
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            // A page version not deployed yet answers 404: say so rather than draw the site's error page.
            // Only the page itself: a sub-frame's status is not the map's.
            if response.isForMainFrame, let http = response.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                store.pageError = "This county's map (\(store.wire?.client.engineHash ?? "?")) is not on the site yet."
                return .cancel
            }
            return .allow
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // iOS killed the page (usually memory): start it again rather than leave a blank map.
            store.pageLoading()
            webView.load(URLRequest(url: url))
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

/// A demo's map: a few drawn blocks on the ground, so a screenshot has a town
/// in it without a request to the internet.
struct HometownsMapStandIn: View {
    let town: HometownsTown?

    var body: some View {
        Canvas { context, size in
            let ground = Color(red: 0xE8 / 255, green: 0xE4 / 255, blue: 0xD4 / 255)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))
            let tile = max(10, min(size.width, size.height) / 18)
            let centre = CGPoint(x: size.width / 2, y: size.height * 0.48)
            func diamond(_ x: Int, _ y: Int) -> Path {
                let cx = centre.x + CGFloat(x - y) * tile
                let cy = centre.y + CGFloat(x + y) * tile / 2
                var p = Path()
                p.move(to: CGPoint(x: cx, y: cy - tile / 2))
                p.addLine(to: CGPoint(x: cx + tile, y: cy))
                p.addLine(to: CGPoint(x: cx, y: cy + tile / 2))
                p.addLine(to: CGPoint(x: cx - tile, y: cy))
                p.closeSubpath()
                return p
            }
            // The County Road coming in, a lane, and the first homes and farms.
            for y in -6...6 { context.fill(diamond(0, y), with: .color(Color(white: 0.62))) }
            for x in 1...5 { context.fill(diamond(x, 0), with: .color(Color(white: 0.72))) }
            let homes = Color(red: 0.86, green: 0.55, blue: 0.42)
            let farms = Color(red: 0.62, green: 0.74, blue: 0.40)
            for x in 1...4 { for y in [-2, -1, 1, 2] { context.fill(diamond(x, y), with: .color(homes)) } }
            for x in 1...2 { context.fill(diamond(x, 4), with: .color(farms)) }
            context.fill(diamond(-2, -1), with: .color(Color(red: 0.40, green: 0.62, blue: 0.80)))
        }
        .accessibilityLabel("A drawing of \(town?.name ?? "a town")")
        .accessibilityIdentifier("hometowns-map-standin")
    }
}

#if DEBUG
/// The spike's numbers (§9.15): the page's frame rate, its sim time, the
/// phone's thermal state and the canary. Debug builds only.
struct HometownsDebugHUD: View {
    @ObservedObject var store: HometownsStore

    var body: some View {
        if store.fps != nil || store.canaryLine != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let fps = store.fps {
                    Text("\(fps) fps · lowest \(store.minFps ?? fps) · \(String(format: "%.1f", store.simMs ?? 0)) ms sim")
                }
                Text("Thermal: \(HometownsStore.thermalName(store.thermal))")
                if let canary = store.canaryLine { Text(canary) }
            }
            .font(SR.Text.mono())
            .foregroundStyle(SR.cream)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.55)))
            .padding(8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
#endif

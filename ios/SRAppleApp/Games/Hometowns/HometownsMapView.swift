import SwiftUI
import UIKit
import WebKit

// The town map: the site's versioned map page (the wire's `client.page`,
// `/projects/hometowns/<pageHash>/mobile.html?app=1`) in a web view, the `MarblerScreen.swift` pattern. The
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

    // Split into pieces: as one expression, the body's modifier chain was
    // more than the type checker would finish in a Release archive.
    var body: some View {
        map
            .overlay { errorCard }
            #if DEBUG
            .overlay(alignment: .topLeading) { HometownsDebugHUD(store: store) }
            #endif
            // The page boots with the wording, theme and motion of the moment;
            // a parent switching a seat, dark mode or Reduce Motion later reaches
            // it here (the page's `settings` takes each of them).
            .onAppear { sendSettings() }
            .onChange(of: colorScheme) { _, _ in sendSettings() }
            .onChange(of: reduceMotion) { _, _ in sendSettings() }
            .onChange(of: store.level) { _, _ in sendSettings() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(mapLabel))
            .accessibilityIdentifier("hometowns-map")
    }

    private var mapLabel: String { "Map of \(store.town?.name ?? "your town")" }

    private func sendSettings() {
        store.pageSettings(dark: colorScheme == .dark, reduceMotion: reduceMotion)
    }

    @ViewBuilder private var map: some View {
        Group {
            if SRDemo.isOn {
                HometownsMapStandIn(town: store.town)
            } else if let url = store.pageURL {
                HometownsWebView(store: store, url: url)
                    .overlay {
                        if !store.pageReady && store.pageError == nil {
                            loading
                        }
                    }
            } else {
                loading
            }
        }
    }

    /// While the page boots: the drawn town, faded, under "Drawing your town…",
    /// so the first second is a town and not a blank square.
    private var loading: some View {
        ZStack {
            HometownsMapStandIn(town: store.town)
                .opacity(0.5)
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                ProgressView().tint(SR.accent)
                Text(store.level == .kid ? "Drawing your town…" : "Drawing the map…")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .srGlass(.paper, in: Capsule())
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .accessibilityIdentifier("hometowns-map-loading")
    }

    @ViewBuilder private var errorCard: some View {
        if let error = store.pageError {
            VStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(SR.Text.title(26))
                    .foregroundStyle(SR.accent)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(SR.accent.opacity(0.14)))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(SR.Text.title(18))
                            .foregroundStyle(SR.warn)
                    }
                    .accessibilityHidden(true)
                Text("The map couldn't load")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(error)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    SRHaptic.tap()
                    store.pageError = nil
                    store.pageLoading()
                    if let url = store.pageURL { store.webView?.load(URLRequest(url: url)) }
                } label: {
                    HometownsBigLabel(title: "Try again", icon: "arrow.clockwise", fill: true)
                }
                .srButton(.prominent)
                .accessibilityIdentifier("hometowns-map-retry")
            }
            .padding(SR.gutter)
            .frame(maxWidth: 380)
            .srGlassCard(.paper)
            .padding(SR.gutter)
        }
    }
}

/// The page's web view, holding the navigation stack's swipe-back off while
/// the map is on screen: the map owns every drag (one finger pans or paints a
/// zone), so a rightward drag mustn't count as "back". See `SwipeBackHold`.
final class HometownsWKWebView: WKWebView {
    private let hold = SwipeBackHold()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        hold.update(for: self)
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
        let web = HometownsWKWebView(frame: .zero, configuration: config)
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
        // A new page on the wire (a new engine, or a page-only change, §10.10). The page
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
                store.pageError = "This county's map (\(store.wire?.client.pageHash ?? "?")) is not on the site yet."
                return .cancel
            }
            return .allow
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // iOS killed the page (usually memory): start it again rather than leave a blank map,
            // on the wire's page (a needReload may have moved it since this view was made).
            store.pageLoading()
            webView.load(URLRequest(url: store.pageURL ?? url))
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

/// A demo's map, and the backdrop while the real page boots: a hamlet drawn
/// in isometric blocks — the County Road, a lane, homes with pitched roofs,
/// farms in rows, a pond and trees — so a screenshot has a town in it without
/// a request to the internet. Static: drawn once per size, nothing animates.
struct HometownsMapStandIn: View {
    let town: HometownsTown?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        Canvas { context, size in
            HometownsMapStandIn.draw(in: context, size: size, dark: dark)
        }
        .accessibilityLabel("A drawing of \(town?.name ?? "a town")")
        .accessibilityIdentifier("hometowns-map-standin")
    }

    /// One tile of the grid: its centre on screen.
    private struct Grid {
        let centre: CGPoint
        let tile: CGFloat

        func point(_ x: Int, _ y: Int) -> CGPoint {
            CGPoint(x: centre.x + CGFloat(x - y) * tile, y: centre.y + CGFloat(x + y) * tile / 2)
        }

        func diamond(_ x: Int, _ y: Int, lift: CGFloat = 0, inset: CGFloat = 0) -> Path {
            let c = point(x, y)
            let w = tile * (1 - inset)
            let h = tile / 2 * (1 - inset)
            var p = Path()
            p.move(to: CGPoint(x: c.x, y: c.y - h - lift))
            p.addLine(to: CGPoint(x: c.x + w, y: c.y - lift))
            p.addLine(to: CGPoint(x: c.x, y: c.y + h - lift))
            p.addLine(to: CGPoint(x: c.x - w, y: c.y - lift))
            p.closeSubpath()
            return p
        }
    }

    private static func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        p.addLine(to: c)
        p.addLine(to: d)
        p.closeSubpath()
        return p
    }

    static func draw(in context: GraphicsContext, size: CGSize, dark: Bool) {
        let ground = dark ? Color(hex: 0x2C3127) : Color(hex: 0xE8E4D4)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))
        let tile: CGFloat = max(10, min(size.width, size.height) / 18)
        let grid = Grid(centre: CGPoint(x: size.width / 2, y: size.height * 0.46), tile: tile)

        // A soft meadow under the hamlet.
        let meadow = CGRect(x: grid.centre.x - tile * 9, y: grid.centre.y - tile * 3.2, width: tile * 18, height: tile * 9.5)
        context.fill(Path(ellipseIn: meadow), with: .color(dark ? Color(hex: 0x34402C) : Color(hex: 0xD5DDB4)))

        // The County Road, a lane off it, and their centre lines.
        let road = dark ? Color(hex: 0x5A5D60) : Color(hex: 0x9C9A94)
        let lane = dark ? Color(hex: 0x6A6C6E) : Color(hex: 0xB5B2A9)
        for y in -7...7 { context.fill(grid.diamond(0, y), with: .color(road)) }
        for x in 1...6 { context.fill(grid.diamond(x, 0), with: .color(lane)) }
        var line = Path()
        line.move(to: grid.point(0, -7))
        line.addLine(to: grid.point(0, 7))
        context.stroke(line, with: .color(Color.white.opacity(dark ? 0.35 : 0.7)),
                       style: StrokeStyle(lineWidth: max(1, tile * 0.08), dash: [tile * 0.3, tile * 0.3]))

        // A pond, back left.
        context.fill(grid.diamond(-3, -1), with: .color(Color(hex: 0x4F93C9)))
        context.fill(grid.diamond(-2, -2), with: .color(Color(hex: 0x4F93C9)))
        context.fill(grid.diamond(-3, -2), with: .color(Color(hex: 0x5BA0D4)))
        context.fill(grid.diamond(-3, -2, inset: 0.6), with: .color(Color.white.opacity(0.45)))

        // Farms in rows, front right.
        for x in 1...3 {
            for y in 4...5 {
                context.fill(grid.diamond(x, y), with: .color(Color(hex: 0x9CBF5A)))
                let c = grid.point(x, y)
                for k in -1...1 {
                    var row = Path()
                    let off = CGFloat(k) * tile * 0.3
                    row.move(to: CGPoint(x: c.x - tile * 0.5 + off, y: c.y - tile * 0.25 + off / 2))
                    row.addLine(to: CGPoint(x: c.x + tile * 0.5 + off, y: c.y + tile * 0.25 + off / 2))
                    context.stroke(row, with: .color(Color(hex: 0x6E9440)), lineWidth: max(1, tile * 0.07))
                }
            }
        }

        // Homes, back to front so the nearer ones overlap the farther.
        var homes: [(Int, Int)] = []
        for x in 1...5 { for y in [-2, -1, 1, 2] { homes.append((x, y)) } }
        var trees: [(Int, Int)] = [(-2, 2), (-3, 3), (-1, 4), (5, -4), (6, 3), (-4, -4), (3, -4), (7, 1)]
        trees.sort { $0.0 + $0.1 < $1.0 + $1.1 }
        homes.sort { $0.0 + $0.1 < $1.0 + $1.1 }
        let walls = [Color(hex: 0xE9DCC6), Color(hex: 0xF1E6D2), Color(hex: 0xE3D3BB)]
        let roofs = [Color(hex: 0xC0563C), Color(hex: 0xA94A33), Color(hex: 0x8E5A3C), Color(hex: 0x3E6E8E)]
        var t = 0
        var h = 0
        for depth in -8...10 {
            while t < trees.count && trees[t].0 + trees[t].1 == depth {
                tree(context, grid, trees[t].0, trees[t].1)
                t += 1
            }
            while h < homes.count && homes[h].0 + homes[h].1 == depth {
                let (x, y) = homes[h]
                let pick = abs(x * 7 + y * 3)
                house(context, grid, x, y, wall: walls[pick % walls.count], roof: roofs[pick % roofs.count])
                h += 1
            }
        }

        // The signpost where the lane meets the County Road.
        let sign = grid.point(0, 0)
        context.fill(Path(CGRect(x: sign.x - tile * 0.05, y: sign.y - tile * 1.1, width: tile * 0.1, height: tile * 1.1)),
                     with: .color(Color(hex: 0x6B4E33)))
        context.fill(Path(roundedRect: CGRect(x: sign.x - tile * 0.05, y: sign.y - tile * 1.15, width: tile * 0.8, height: tile * 0.32),
                          cornerRadius: tile * 0.06), with: .color(Color(hex: 0xF2C230)))
    }

    /// A house on tile (x, y): two lit walls and a pitched roof.
    private static func house(_ context: GraphicsContext, _ grid: Grid, _ x: Int, _ y: Int, wall: Color, roof: Color) {
        let tile = grid.tile
        let c = grid.point(x, y)
        let w = tile * 0.78
        let d = tile * 0.39
        let lift = tile * 0.55
        let left = CGPoint(x: c.x - w, y: c.y)
        let front = CGPoint(x: c.x, y: c.y + d)
        let right = CGPoint(x: c.x + w, y: c.y)
        let back = CGPoint(x: c.x, y: c.y - d)
        func up(_ p: CGPoint, _ by: CGFloat) -> CGPoint { CGPoint(x: p.x, y: p.y - by) }
        // Walls: the left face in shade, the right face lit.
        context.fill(quad(left, front, up(front, lift), up(left, lift)), with: .color(wall))
        context.fill(quad(left, front, up(front, lift), up(left, lift)), with: .color(Color.black.opacity(0.16)))
        context.fill(quad(front, right, up(right, lift), up(front, lift)), with: .color(wall))
        // A door on the lit face.
        let door = CGPoint(x: (front.x + right.x) / 2, y: (front.y + right.y) / 2)
        let doorW: CGFloat = tile * 0.08
        let doorA = CGPoint(x: door.x - doorW, y: door.y + tile * 0.04)
        let doorB = CGPoint(x: door.x + doorW, y: door.y - tile * 0.04)
        let doorC = CGPoint(x: door.x + doorW, y: door.y - tile * 0.3)
        let doorD = CGPoint(x: door.x - doorW, y: door.y - tile * 0.22)
        context.fill(quad(doorA, doorB, doorC, doorD), with: .color(Color(hex: 0x6B4E33)))
        // The roof: a ridge over the middle, parallel to the left face, raised
        // above the walls. The back slope first, then the gable over the lit
        // wall, then the near slope in shade over both.
        let roofHeight = tile * 0.42
        let ridgeBack = up(CGPoint(x: (left.x + back.x) / 2, y: (left.y + back.y) / 2), lift + roofHeight)
        let ridgeFront = up(CGPoint(x: (front.x + right.x) / 2, y: (front.y + right.y) / 2), lift + roofHeight)
        context.fill(quad(up(back, lift), up(right, lift), ridgeFront, ridgeBack), with: .color(roof))
        var gable = Path()
        gable.move(to: up(front, lift))
        gable.addLine(to: up(right, lift))
        gable.addLine(to: ridgeFront)
        gable.closeSubpath()
        context.fill(gable, with: .color(wall))
        context.fill(quad(up(left, lift), up(front, lift), ridgeFront, ridgeBack), with: .color(roof))
        context.fill(quad(up(left, lift), up(front, lift), ridgeFront, ridgeBack), with: .color(Color.black.opacity(0.2)))
        var ridge = Path()
        ridge.move(to: ridgeBack)
        ridge.addLine(to: ridgeFront)
        context.stroke(ridge, with: .color(Color.white.opacity(0.3)), lineWidth: max(1, tile * 0.05))
    }

    /// A round tree on tile (x, y), with its shadow.
    private static func tree(_ context: GraphicsContext, _ grid: Grid, _ x: Int, _ y: Int) {
        let tile = grid.tile
        let c = grid.point(x, y)
        context.fill(Path(ellipseIn: CGRect(x: c.x - tile * 0.55, y: c.y - tile * 0.18, width: tile * 1.1, height: tile * 0.4)),
                     with: .color(Color.black.opacity(0.12)))
        context.fill(Path(CGRect(x: c.x - tile * 0.07, y: c.y - tile * 0.55, width: tile * 0.14, height: tile * 0.55)),
                     with: .color(Color(hex: 0x6B4E33)))
        let crown = CGRect(x: c.x - tile * 0.5, y: c.y - tile * 1.45, width: tile, height: tile)
        context.fill(Path(ellipseIn: crown), with: .color(Color(hex: 0x4E8A4C)))
        context.fill(Path(ellipseIn: crown.insetBy(dx: tile * 0.2, dy: tile * 0.2).offsetBy(dx: -tile * 0.1, dy: -tile * 0.1)),
                     with: .color(Color(hex: 0x67A562)))
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

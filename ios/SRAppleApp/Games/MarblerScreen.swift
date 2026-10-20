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
// `window.marbler.*`. Bridge 2 (`?app=2`): the app lists the courses and
// holds the race controls, so the page hides its own. Picking a marble,
// starting and the results stay on the page, where the race is.
//
// Each pack course carries the race Node recorded; the ⋯ menu can replay it
// and shows whether this phone ran the very same race, beside the frame
// rate and the phone's thermal state.

/// Navigation value for Marbler, pushed on the Games stack.
struct MarblerRef: Hashable {}

/// A course in the page's pack, as the course list shows it.
struct MarblerCourse: Identifiable, Equatable {
    let id: String
    let name: String
    let layout: String
    let marbles: Int
    let seconds: Int
    let odds: Double
    let today: Bool

    init?(_ d: [String: Any]) {
        guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
        self.id = id
        self.name = name
        layout = d["layout"] as? String ?? ""
        marbles = d["marbles"] as? Int ?? 0
        seconds = d["seconds"] as? Int ?? 0
        odds = (d["odds"] as? NSNumber)?.doubleValue ?? 0
        today = d["today"] as? Bool ?? false
    }

    /// "Switchback · 11 marbles · about 3 min".
    var detail: String {
        "\(layout) · \(marbles) marbles · about \(max(1, Int((Double(seconds) / 60).rounded()))) min"
    }
}

/// What the page has told us, plus the phone's own side of the spike.
@MainActor
final class MarblerModel: ObservableObject {
    @Published var courses: [MarblerCourse] = []
    @Published var courseId = ""
    @Published var course = ""
    /// ready (picking a marble), racing, done (results showing).
    @Published var phase = "ready"
    @Published var favourite: String?
    @Published var speed = 1
    @Published var glow = true
    @Published var fps: Int?
    @Published var minFps: Int?
    @Published var simMs: Double?
    @Published var recorded = false
    @Published var checks: String?
    @Published var bench: String?
    @Published var error: String?
    @Published var thermal = ProcessInfo.processInfo.thermalState
    /// Set by the web view once it exists, for calls into the page.
    weak var webView: WKWebView?
    /// A family race (Marble Race): the `room(…)` call for the page, worked out
    /// afresh each time the page says it is ready — so a page that reloads
    /// rejoins the race where the room's clock has got to.
    var roomScript: (() -> String?)?
    /// A family race ended on this phone: its finish order, by marble index.
    var onRoomFinished: (([Int]) -> Void)?
    private var pageReady = false

    /// The bridge version this app speaks: 2, the app draws the course list
    /// and controls; 3, it can start a family race with `room(…)`.
    static let bridgeVersion = 3

    /// The phone page. A debug build may point it elsewhere (HTTPS only) with
    /// `-marblerURL https://…` as a launch argument.
    static var pageURL: URL {
        var page = URL(string: "https://strangeramblings.com/projects/marbler/mobile.html")!
        #if DEBUG
        if let text = UserDefaults.standard.string(forKey: "marblerURL"), let url = URL(string: text), url.scheme == "https" {
            page = url
        }
        #endif
        var parts = URLComponents(url: page, resolvingAgainstBaseURL: false)
        parts?.queryItems = (parts?.queryItems ?? []) + [URLQueryItem(name: "app", value: String(bridgeVersion))]
        return parts?.url ?? page
    }

    func call(_ script: String) {
        webView?.evaluateJavaScript("window.marbler && window.marbler.\(script)")
    }

    /// Send the family race now if the page is up; otherwise it goes when the page says ready.
    func sendRoom() {
        guard pageReady, let script = roomScript?() else { return }
        call(script)
    }

    /// Pack ids are letters and digits; anything else never reaches the page.
    func load(_ course: MarblerCourse) {
        guard course.id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return }
        call("load('\(course.id)')")
    }

    func setSpeed(_ value: Int) {
        speed = value
        call("setSpeed(\(value))")
    }

    func setGlow(_ on: Bool) {
        glow = on
        call("setFx(\(on))")
    }

    func receive(_ body: Any) {
        guard let m = body as? [String: Any], let type = m["type"] as? String else { return }
        switch type {
        case "ready":
            pageReady = true
            sendRoom()
        case "courses":
            courses = (m["list"] as? [[String: Any]] ?? []).compactMap(MarblerCourse.init)
        case "course":
            courseId = m["id"] as? String ?? ""
            course = m["name"] as? String ?? ""
            checks = nil
        case "phase":
            phase = m["phase"] as? String ?? "ready"
            recorded = m["recorded"] as? Bool ?? false
            if phase == "ready" { checks = nil }
        case "favourite":
            favourite = m["colour"] as? String
        case "finish":
            // Your marble home is the moment; somebody else's win is a tap.
            let place = m["place"] as? Int ?? 0
            if m["yours"] as? Bool == true { place <= 3 ? SRHaptic.ok() : SRHaptic.select() } else if place == 1 { SRHaptic.tap() }
        case "burned":
            SRHaptic.select()
        case "won":
            SRHaptic.ok()
            if m["room"] as? Bool == true, let order = m["marbles"] as? [Int] { onRoomFinished?(order) }
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

    func pageNotReady() { pageReady = false }

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
    @State private var choosing = false

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
            .navigationTitle(model.course.isEmpty ? "Marbler" : model.course)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        SRHaptic.tap()
                        choosing = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .disabled(model.courses.isEmpty)
                    .accessibilityLabel("Courses")
                    .accessibilityIdentifier("marbler-courses")
                }
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
            .sheet(isPresented: $choosing) {
                MarblerCourseList(courses: model.courses, current: model.courseId) { course in
                    choosing = false
                    model.load(course)
                }
                .presentationDetents([.medium, .large])
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

    private var menu: some View {
        Menu {
            Button {
                model.call("again()")
            } label: {
                Label("New race on this course", systemImage: "arrow.clockwise")
            }
            Button {
                model.call("next()")
            } label: {
                Label("Next course", systemImage: "forward")
            }
            Picker("Speed", selection: Binding(get: { model.speed }, set: { model.setSpeed($0) })) {
                Text("1×").tag(1)
                Text("2×").tag(2)
                Text("4×").tag(4)
            }
            Toggle("Glow", isOn: Binding(get: { model.glow }, set: { model.setGlow($0) }))
            Button {
                model.call("setFollow(false)")
            } label: {
                Label("Show the whole course", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            Section("Spike") {
                Text(model.fps.map { "\($0) fps · lowest \(model.minFps ?? $0)" } ?? "fps: waiting")
                Text(model.simMs.map { String(format: "Physics %.2f ms a frame", $0) } ?? "Physics: waiting")
                Text("Thermal state: \(model.thermalText)")
                Text(model.recorded ? (model.checks ?? "Checks: waiting") : "Checks: only on the recorded race")
                Text(model.bench ?? "Headless check: not run")
                Button("Replay the recorded race") { model.call("again(true)") }
                Button("Run the recorded race headless") { model.call("bench()") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityIdentifier("marbler-menu")
    }
}

/// The course pack, today's course first.
struct MarblerCourseList: View {
    let courses: [MarblerCourse]
    let current: String
    let choose: (MarblerCourse) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let today = courses.first(where: \.today) {
                    Section("Today") { row(today) }
                }
                Section("Every course") {
                    ForEach(courses) { row($0) }
                }
            }
            .navigationTitle("Courses")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("marbler-course-list")
    }

    private func row(_ course: MarblerCourse) -> some View {
        Button {
            SRHaptic.select()
            choose(course)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.name)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text(course.detail)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 8)
                if course.id == current {
                    Image(systemName: "checkmark")
                        .foregroundStyle(SR.accent)
                        .accessibilityLabel("Playing now")
                }
            }
            .frame(minHeight: SR.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("marbler-course-\(course.id)")
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
            model.pageNotReady()
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

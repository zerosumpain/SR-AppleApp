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
    /// The page has loaded and spoken: the loading cover comes off.
    @Published var loaded = false
    /// Marbler on its own keeps this phone's book of races; a family race
    /// (Marble Race) keeps the room's instead, so leaves this off.
    var keepsSoloRecord = false
    /// The book, while `keepsSoloRecord`.
    @Published private(set) var soloBook = MarbleRaceRecordBook()
    /// Where my marble came in the race just run, for the native toast.
    @Published var finishNote: MarblerFinishNote?
    /// My marble's finish is counted once a race.
    private var countedThisRace = false
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
        let items = (parts?.queryItems ?? []) + [URLQueryItem(name: "app", value: String(bridgeVersion))]
        parts?.queryItems = items
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

    /// Start keeping Marbler's own book (the solo screen calls this once).
    func keepSoloRecord() {
        guard !keepsSoloRecord else { return }
        keepsSoloRecord = true
        soloBook = MarbleRaceRecordStore(key: MarbleRaceRecordStore.soloKey).load()
    }

    func receive(_ body: Any) {
        guard let m = body as? [String: Any], let type = m["type"] as? String else { return }
        // Any word from the page means it is up.
        if !loaded { loaded = true }
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
            if phase == "racing" {
                countedThisRace = false
                finishNote = nil
            }
        case "favourite":
            favourite = m["colour"] as? String
        case "finish":
            // Your marble home is the moment; somebody else's win is a tap.
            let place = m["place"] as? Int ?? 0
            if m["yours"] as? Bool == true { place <= 3 ? SRHaptic.ok() : SRHaptic.select() } else if place == 1 { SRHaptic.tap() }
            if m["yours"] as? Bool == true, place >= 1 { noteMyFinish(place) }
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

    func pageNotReady() {
        pageReady = false
        loaded = false
    }

    /// The page is being loaded afresh (Try again).
    func reload() {
        error = nil
        pageNotReady()
        webView?.load(URLRequest(url: MarblerModel.pageURL))
    }

    /// My marble is home: say where, and on its own keep the best.
    private func noteMyFinish(_ place: Int) {
        guard !countedThisRace else { return }
        countedThisRace = true
        var newBest = false
        if keepsSoloRecord {
            let store = MarbleRaceRecordStore(key: MarbleRaceRecordStore.soloKey)
            var book = store.load()
            newBest = book.record(key: nil, place: place).newBest && book.races > 1
            store.save(book)
            soloBook = book
        }
        finishNote = MarblerFinishNote(place: place, newBest: newBest, best: keepsSoloRecord ? soloBook.bestPlace : nil)
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

/// Where my marble came, for the toast over the race.
struct MarblerFinishNote: Equatable {
    let place: Int
    /// A new best on this phone (never on the very first race).
    let newBest: Bool
    /// The best so far, when Marbler keeps a book.
    let best: Int?

    var text: String {
        let came = "Your marble came \(MarbleRaceOrdinal.text(place))"
        if newBest { return "\(came) — a new best!" }
        if let best, best < place { return "\(came) · best \(MarbleRaceOrdinal.text(best))" }
        return "\(came)."
    }
}

/// Marbler's dark ground, behind the page and under its controls.
enum MarblerPaint {
    static let ground = Color(red: 0x14 / 255, green: 0x10 / 255, blue: 0x0c / 255)
    static let groundUI = UIColor(red: 0x14 / 255, green: 0x10 / 255, blue: 0x0c / 255, alpha: 1)
    static let cream = Color(hex: 0xF4EBDD)
}

/// Marbler on this phone: the page's race, the app's controls under it —
/// pause, a new race, speed and the next course, each a big button — and the
/// course list and the spike's numbers in the bar. While the page loads a
/// cover says so; if it cannot load, a card says why with Try again. When my
/// marble is home a toast says where it came and whether that is a best.
struct MarblerScreen: View {
    @StateObject private var model = MarblerModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var choosing = false
    /// Paused from the app's own button: a trip to the background and back
    /// leaves it paused.
    @State private var paused = false

    var body: some View {
        VStack(spacing: 0) {
            race
            MarblerControlBar(model: model, paused: paused, togglePause: togglePause)
        }
        .background(MarblerPaint.ground.ignoresSafeArea())
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
            MarblerCourseList(courses: model.courses, current: model.courseId, book: model.soloBook) { course in
                choosing = false
                endPause()
                model.load(course)
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            model.keepSoloRecord()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            model.call(phase == .active && !paused ? "resume()" : "pause()")
        }
        .onChange(of: model.phase) { _, phase in
            // A race that ends, or a new one, is never left paused.
            if phase != "racing" { endPause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            model.thermal = ProcessInfo.processInfo.thermalState
        }
        .accessibilityIdentifier("marbler-screen")
    }

    /// The page, with whatever it needs on top: loading, a failure, the pause, the finish.
    private var race: some View {
        MarblerWebView(model: model)
            .overlay {
                if let error = model.error {
                    MarblerErrorCard(message: error, retry: { model.reload() })
                } else if !model.loaded {
                    MarblerLoadingCover(text: "Rolling out the course…")
                } else if paused {
                    MarblerPausedCover(resume: togglePause)
                }
            }
            .overlay(alignment: .top) {
                MarblerFinishToast(note: model.finishNote, dismiss: { model.finishNote = nil })
            }
            .animation(.easeOut(duration: 0.2), value: paused)
            .animation(.easeOut(duration: 0.25), value: model.loaded)
    }

    private func togglePause() {
        SRHaptic.tap()
        paused.toggle()
        model.call(paused ? "pause()" : "resume()")
        UIAccessibility.post(notification: .announcement, argument: paused ? "Paused" : "Racing")
    }

    /// Out of a pause without a toggle: a new race, the next course or a
    /// finish. The page is told too, so it never waits paused under a bar
    /// that says it is running.
    private func endPause() {
        guard paused else { return }
        paused = false
        model.call("resume()")
    }

    private var menu: some View {
        Menu {
            Button {
                endPause()
                model.call("again()")
            } label: {
                Label("New race on this course", systemImage: "arrow.clockwise")
            }
            Button {
                endPause()
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

/// The race's controls, under the page: four big buttons on the dark ground.
/// Pause works only while a race is running (picking and the results are the
/// page's own); speed steps 1×, 2×, 4× and round again.
struct MarblerControlBar: View {
    @ObservedObject var model: MarblerModel
    let paused: Bool
    let togglePause: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            control(icon: paused ? "play.fill" : "pause.fill", title: paused ? "Resume" : "Pause",
                    spoken: paused ? "Resume the race" : "Pause the race", id: "marbler-pause",
                    enabled: model.loaded && model.phase == "racing") {
                togglePause()
            }
            control(icon: "arrow.clockwise", title: "New race", spoken: "New race on this course",
                    id: "marbler-again", enabled: model.loaded) {
                SRHaptic.tap()
                model.call("again()")
            }
            control(icon: "gauge.with.dots.needle.67percent", title: "\(model.speed)×",
                    spoken: "Speed, \(model.speed) times. Tap for faster.", id: "marbler-speed", enabled: model.loaded) {
                SRHaptic.select()
                model.setSpeed(Self.nextSpeed(after: model.speed))
            }
            control(icon: "forward.fill", title: "Next", spoken: "Next course", id: "marbler-next", enabled: model.loaded) {
                SRHaptic.tap()
                model.call("next()")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(MarblerPaint.ground.ignoresSafeArea(edges: .bottom))
    }

    static func nextSpeed(after speed: Int) -> Int {
        switch speed {
        case 1: return 2
        case 2: return 4
        default: return 1
        }
    }

    private func control(icon: String, title: String, spoken: String, id: String, enabled: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                Text(title.uppercased())
                    .font(SR.Text.label())
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(MarblerPaint.cream)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(SRPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(id)
    }
}

/// Over the page while it loads: three marbles and a line.
struct MarblerLoadingCover: View {
    let text: String

    var body: some View {
        ZStack {
            MarblerPaint.ground
            VStack(spacing: 18) {
                HStack(spacing: -8) {
                    ForEach(0..<4, id: \.self) { m in
                        MarbleRaceMarbleArt(index: m, size: 40)
                    }
                }
                ProgressView()
                    .tint(MarblerPaint.cream)
                Text(text)
                    .font(SR.Text.secondary())
                    .foregroundStyle(MarblerPaint.cream.opacity(0.8))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityIdentifier("marbler-loading")
    }
}

/// The page would not load: why, and Try again.
struct MarblerErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ZStack {
            MarblerPaint.ground
            VStack(spacing: 14) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(SR.accent)
                    .accessibilityHidden(true)
                Text("Marbler couldn't start")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(message)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The race comes from strangeramblings.com, so it needs a connection.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    SRHaptic.tap()
                    retry()
                } label: {
                    SRButtonLabel(title: "Try again", icon: "arrow.clockwise", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("marbler-retry")
            }
            .padding(SR.cardPadding + 4)
            .srGlassCard(.paper)
            .padding(.horizontal, SR.gutter)
        }
    }
}

/// Paused from the app's button: the race waits under a dim, with Resume.
struct MarblerPausedCover: View {
    let resume: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 14) {
                Text("PAUSED")
                    .font(SR.Text.label(13))
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(MarblerPaint.cream.opacity(0.8))
                Button(action: resume) {
                    SRButtonLabel(title: "Resume", icon: "play.fill", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .frame(maxWidth: 260)
                .accessibilityIdentifier("marbler-resume")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// "Your marble came 2nd — a new best!", dropped over the top of the race
/// when my marble is home, gone by itself after a few seconds or on a tap.
struct MarblerFinishToast: View {
    let note: MarblerFinishNote?
    let dismiss: () -> Void

    var body: some View {
        // A stack, not a Group: the toast's arrival needs a container to animate in.
        VStack(spacing: 0) {
            if let note {
                Button(action: dismiss) {
                    HStack(spacing: 10) {
                        Image(systemName: note.place == 1 ? "trophy.fill" : note.newBest ? "star.fill" : "flag.checkered")
                            .foregroundStyle(note.place <= 3 ? Color(hex: 0xFFD54F) : MarblerPaint.cream)
                            .accessibilityHidden(true)
                        Text(note.text)
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(MarblerPaint.cream)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .padding(.horizontal, SR.gutter)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("marbler-finish")
                .task(id: note) {
                    UIAccessibility.post(notification: .announcement, argument: note.text)
                    try? await Task.sleep(nanoseconds: 4_500_000_000)
                    if !Task.isCancelled { dismiss() }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: note)
    }
}

/// The course pack, today's course first.
struct MarblerCourseList: View {
    let courses: [MarblerCourse]
    let current: String
    /// This phone's races, for the line at the top; none shows nothing.
    var book = MarbleRaceRecordBook()
    let choose: (MarblerCourse) -> Void

    var body: some View {
        NavigationStack {
            List {
                if book.races > 0 {
                    Section("On this phone") {
                        Label(book.line, systemImage: "trophy")
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.ink)
                            .accessibilityIdentifier("marbler-record")
                    }
                }
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
        web.backgroundColor = MarblerPaint.groundUI
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // An older page may never say "ready"; loaded is loaded.
            model.loaded = true
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

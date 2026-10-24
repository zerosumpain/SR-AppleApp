import AVFoundation
import Foundation
import QuartzCore
import UIKit
import WebKit

/// One Hometowns county, live.
///
/// The connection is the game's own rather than `GameRoomLink`, because a
/// county's frames are DELTAS (§10.7): after the first, each stream frame
/// carries only what changed since the one before, and the map page must be
/// handed the very bytes the server sent so its own merge rebuilds exactly
/// the server's town (the canary, §10.4). So this store:
///   - keeps the last few WHOLE frames by `rev`, as JSON dictionaries, and
///     merges every frame — stream, snapshot or an action's answer — onto
///     the one it was cut against (`HometownsFrames.merge`). The merged frame
///     is decoded for the sheets. A frame cut against a rev it does not hold
///     is not guessed at: the snapshot is read whole instead.
///   - feeds the PAGE only the stream, in order, raw: its first frame is
///     whole and every later one is cut against the one before, which is
///     exactly the chain the page merges. When the page says it could not
///     merge (`needResync`), the stream is reopened, and a new stream always
///     starts whole. An action's answer is never forwarded: it is cut against
///     what this store held, which need not be what the page holds.
///   - posts every move on the native lane with the rev it holds as `since`,
///     and keeps each mutating move PENDING until a frame lists its id among
///     this seat's moves (A28), even after the server answered it: an answer
///     comes from the server's memory, which a restart or a lost write race
///     can still lose. The server reads a county back from its row with a
///     rev beyond anything it sent before, so the first frame after that is
///     always WHOLE; a whole frame from the stream or the snapshot that does
///     not list a pending move posted a few seconds before it gets that move
///     posted again, in the order they were made, and the server answers a
///     repeat from its log, so nothing lands twice. A pending move that a
///     later move overtook (the later one is listed, it is not) is dropped
///     rather than replayed over the newer choice.
///   - retries a move after a second when the Regional Day is still being
///     finished (A19: "Kingsport is just finishing the day. Trying again…").
///
/// The page does no authenticated network (§9.1): this is the only thing that
/// talks to the site, and the page only ever hears from it through
/// `window.hometowns.*`.
@MainActor
final class HometownsStore: ObservableObject, GameRoomStoring {
    let roomId: String

    /// The whole frame, decoded for the sheets.
    @Published private(set) var wire: HometownsWire?
    /// The same frame as the framework's room, for the shared lobby.
    @Published private(set) var room: GameRoom?
    @Published private(set) var ended = false
    @Published private(set) var busy = false
    @Published var message: String?
    /// Why the last move was refused, shown over the map for a moment.
    @Published private(set) var refusal: String?
    /// Something that went right ("Undone! Your coins are back."), for a moment.
    @Published private(set) var notice: String?
    @Published var sheet: HometownsSheet?
    /// The plan the page is holding, and its forecast once the worker has one (§9.8).
    @Published private(set) var plan: HometownsPlan?
    /// The card the page worked out for a long-pressed tile (§9.5).
    @Published var inspect: HometownsInspect?
    @Published private(set) var lens = "none"
    /// The flat top-down planning view is on (§9.3).
    @Published private(set) var topDown = false
    @Published private(set) var tool = HometownsTool.none
    /// Bramble's three founding steps, counted from this phone's plans.
    @Published private(set) var tutorial = HometownsTutorial()
    /// A plan has gone to the server and not come back.
    @Published private(set) var committing = false
    /// The page has loaded and booted.
    @Published private(set) var pageReady = false
    /// The page could not be loaded: a sentence, and a retry.
    @Published var pageError: String?
    // The page's telemetry (§9.15), for the debug HUD.
    @Published private(set) var fps: Int?
    @Published private(set) var minFps: Int?
    @Published private(set) var simMs: Double?
    @Published private(set) var canaryLine: String?
    @Published var thermal = ProcessInfo.processInfo.thermalState
    /// A founding week has just been asked for: the button rests for its ten seconds.
    @Published private(set) var sprintWaitUntil: Double = 0

    /// The web view, once it exists, for calls into the page.
    weak var webView: WKWebView?

    private var clock = GameClock()
    /// The most recent whole frames, oldest first: what a delta can be merged onto.
    private var ring: [(rev: Int, frame: [String: Any])] = []
    private static let ringSize = 6
    /// The highest rev a stream frame or a snapshot has shown.
    private var maxRev: Int?
    /// A mutating move this phone posted and no frame has listed yet.
    private struct Sent {
        let move: HometownsMove
        /// When it was posted, on this phone's clock (ms).
        var at: Double
    }
    /// Mutating moves not yet seen in a frame's `me.moves`, oldest first.
    private var pending: [Sent] = []
    /// When the newest move a frame has listed was posted: anything posted
    /// before it and still unlisted was overtaken, and is never replayed.
    private var landedAt: Double = 0
    /// A pending move is posted again only once it is this old (an answer may still be on its way).
    private static let repostAfterMs: Double = 5_000
    /// A pending move older than this is let go: the server would answer it from a log that has moved on.
    private static let pendingKeepMs: Double = 10 * 60_000
    private var retries: [String: Int] = [:]
    private var streamTask: Task<Void, Never>?
    private var noteTask: Task<Void, Never>?
    private var hasRoom = false
    private var joinTried = false
    private var helloSent = false
    private var onScreen = false
    private var pushObserver: NSObjectProtocol?
    /// The last whole stream frame, raw, and the stream frames since, raw: what the page boots from.
    private var pageWhole: Data?
    private var pageChain: [Data] = []
    /// A stream is delivering: the page is fed from it, not from snapshots.
    private var streamLive = false
    /// Which `listen` is the current one, so a cancelled stream winding down
    /// cannot mark its successor as not delivering.
    private var streamGeneration = 0
    /// The page has been booted with a whole frame since it last loaded.
    private var pageBooted = false
    private static let chainLimit = 40
    private var lastStatsAt: Double = 0
    /// Dark mode and Reduce Motion as the map view's environment last said (nil before it has).
    private var viewDark: Bool?
    private var viewReduceMotion: Bool?
    private let speech = AVSpeechSynthesizer()
    private let client = SiteClient.shared

    init(roomId: String) {
        self.roomId = roomId
        tutorial = Self.storedTutorial(roomId)
    }

    // MARK: - Reading the county

    var level: HometownsCopyLevel { wire?.level ?? .adult }
    var copy: HometownsCopy { HometownsCopy.shared }
    var town: HometownsTown? { wire?.town }
    var isParent: Bool { wire?.me?.isParent ?? false }

    /// The words for `key` at this seat's level; never the raw key (`HometownsCopy.line`).
    func say(_ key: String, _ data: HometownsData = [:], sign: Double = 1) -> String {
        copy.line(key, level, data, sign: sign)
    }

    /// The server's clock, now, as well as this phone can tell.
    func serverNow() -> Double? { clock.server(Self.nowMs()) }

    static func nowMs() -> Double { CACurrentMediaTime() * 1000 }

    /// The rev of the newest whole frame held.
    var heldRev: Int? { ring.last?.rev }

    /// The map page for this county: the page the wire names (§10.10), a
    /// versioned folder on the site for the server's exact engine and page
    /// code, with `?app=1`. It is never built from the engine hash: a
    /// page-only change keeps the engine and moves the page. A debug build may
    /// point it elsewhere (HTTPS only) with `-hometownsURL https://…`.
    var pageURL: URL? {
        var page: URL?
        if let named = wire?.client, named.pageHash != nil {
            page = client.webURL(String(named.page.dropFirst()))
        }
        #if DEBUG
        if let text = UserDefaults.standard.string(forKey: "hometownsURL"), let url = URL(string: text), url.scheme == "https" {
            page = url
        }
        #endif
        guard let page else { return nil }
        var parts = URLComponents(url: page, resolvingAgainstBaseURL: false)
        parts?.queryItems = (parts?.queryItems ?? []).filter { $0.name != "app" } + [URLQueryItem(name: "app", value: "1")]
        return parts?.url ?? page
    }

    /// What `needReload` loads: the wire's page, unless the web view already
    /// shows it (a request that crossed a newer frame, or a debug
    /// `-hometownsURL` pinning the page, which would otherwise reload it once
    /// a minute). The page asks at most once a minute and never for a page it
    /// has left (A39); which page is the wire's call, not the message's.
    var reloadURL: URL? {
        guard let url = pageURL, webView?.url != url else { return nil }
        return url
    }

    // MARK: - Connection

    /// Open (or reopen) the county. Idempotent.
    func open() {
        guard streamTask == nil, !ended else { return }
        showing(true)
        streamTask = Task { [weak self] in
            var backoff: UInt64 = 1
            while !Task.isCancelled {
                guard let self, !self.ended else { return }
                await self.refresh()
                if self.ended || Task.isCancelled { return }
                let delivered = await self.listen()
                if Task.isCancelled || self.ended { return }
                backoff = delivered ? 1 : min(backoff * 2, 10)
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
            }
        }
    }

    func close() {
        streamTask?.cancel()
        streamTask = nil
        showing(false)
        helloSent = false
        // Leaving the town screen counts as having seen it: the next open
        // replays only what grows after now (§9.9).
        if let t = town, t.tick > t.lastSeenTick, !t.inFortnight { send(.seen(tick: t.tick), quiet: true) }
    }

    /// The page asked for a whole frame: a new stream always starts with one.
    func restartStream() {
        guard !ended else { return }
        streamTask?.cancel()
        streamTask = nil
        open()
    }

    private func showing(_ on: Bool) {
        guard onScreen != on else { return }
        onScreen = on
        if on {
            GameRoomsOnScreen.opened(roomId)
            GameRoomsOnScreen.clearDelivered(roomId)
            let id = roomId
            pushObserver = NotificationCenter.default.addObserver(
                forName: GameTurnPush.arrived, object: nil, queue: .main
            ) { [weak self] note in
                guard (note.object as? String) == id else { return }
                Task { @MainActor in await self?.refresh() }
            }
        } else {
            GameRoomsOnScreen.closed(roomId)
            if let pushObserver { NotificationCenter.default.removeObserver(pushObserver) }
            pushObserver = nil
        }
    }

    /// The snapshot, whole: `GET api/native/games/<id>`.
    func refresh() async {
        let sent = Self.nowMs()
        // What the stream had shown when this was asked for: a snapshot below
        // that is the server's own regression, one between it and what the
        // stream shows since is merely late.
        let askedAt = maxRev
        do {
            let data = try await client.bytes("api/native/games/\(roomId)")
            guard let frame = HometownsFrames.room(in: data) else {
                note("The server sent something this version of the app cannot read.")
                return
            }
            if let now = frame["serverNow"] as? NSNumber {
                clock.record(serverNow: now.doubleValue, sentAt: sent, receivedAt: Self.nowMs())
            }
            absorb(frame, raw: data, source: .snapshot, askedAt: askedAt)
        } catch SiteError.status(let code, _) where code == 404 {
            end()
        } catch SiteError.status(let code, _) where code == 403 {
            message = "You are not in this county."
            end()
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            note(hasRoom ? "Reconnecting…" : error.localizedDescription)
        }
    }

    /// Read the stream until it ends. True when at least one frame arrived.
    private func listen() async -> Bool {
        var delivered = false
        do {
            let stream = try client.stream(path: "api/native/games/\(roomId)/stream")
            var first = true
            streamGeneration += 1
            let generation = streamGeneration
            defer { if streamGeneration == generation { streamLive = false } }
            for try await frame in stream {
                if Task.isCancelled { break }
                let received = Self.nowMs()
                guard frame.json["type"] as? String == "room", let room = frame.json["room"] as? [String: Any] else {
                    if frame.json["type"] as? String == "gone" { end() }
                    continue
                }
                if let now = room["serverNow"] as? NSNumber { clock.record(serverNow: now.doubleValue, receivedAt: received) }
                delivered = true
                // A new stream's first frame is whole; one that is not cannot start the page's chain.
                absorb(room, raw: frame.data, source: first ? .streamStart : .stream)
                first = false
                if message == "Reconnecting…" { message = nil }
            }
        } catch {
            // Dropped or refused: the loop reads the snapshot next, which is
            // what tells a gone county (404) from a flaky connection.
        }
        return delivered
    }

    private func end() {
        guard !ended else { return }
        ended = true
        streamTask?.cancel()
        streamTask = nil
        showing(false)
    }

    private func note(_ text: String) {
        message = text
    }

    // MARK: - Frames

    enum Source { case streamStart, stream, snapshot, answer }

    /// One frame from anywhere: merged onto what it was cut against, decoded,
    /// and (from the stream) handed to the page. `askedAt` is a snapshot's
    /// `maxRev` when it was requested.
    private func absorb(_ frame: [String: Any], raw: Data?, source: Source, askedAt: Int? = nil) {
        guard !ended, let rev = HometownsFrames.rev(frame) else { return }
        // An action's answer older than what is held is late, not news.
        if source == .answer, let held = heldRev, rev < held { return }
        // So is a snapshot the stream has overtaken since it was asked for
        // (a push, a gap or a 404 refresh crossing a stream frame).
        if source == .snapshot, let newest = maxRev, rev < newest, askedAt.map({ rev >= $0 }) ?? true { return }
        let base = HometownsFrames.base(frame)
        let held = base.flatMap { b in ring.last(where: { $0.rev == b })?.frame }
        let merged: [String: Any]
        do {
            merged = try HometownsFrames.merge(held, frame)
        } catch {
            // Cut against a frame this phone no longer holds: read it whole.
            if source != .answer { Task { await self.refresh() } }
            return
        }
        let regressed = source != .answer && maxRev.map { rev < $0 } == true
        if source != .answer { maxRev = rev }
        // Frames from before a lost write race belong to another timeline.
        if regressed { ring.removeAll() }
        ring.removeAll { $0.rev == rev }
        ring.append((rev: rev, frame: merged))
        if ring.count > Self.ringSize { ring.removeFirst(ring.count - Self.ringSize) }

        guard JSONSerialization.isValidJSONObject(merged), let data = try? JSONSerialization.data(withJSONObject: merged) else { return }
        let next = try? JSONDecoder().decode(HometownsWire.self, from: data)
        let nextRoom = try? JSONDecoder().decode(GameRoom.self, from: data)
        let previous = wire
        // A stream frame can trail an action's answer by a rev: the sheets
        // never step back to it (the page has its own chain and takes it).
        let newer = regressed || (wire.map { rev >= $0.rev } ?? true)
        if newer, let next, next != wire { wire = next }
        if newer, let nextRoom { room = nextRoom }
        hasRoom = true

        if let next {
            settlePending(next, whole: base == nil && source != .answer)
            react(previous, next)
            if next.phase == "closed" {
                end()
                return
            }
            if next.phase == "lobby", nextRoom?.me?.status == "invited", !joinTried {
                joinTried = true
                Task { _ = await self.act("join") }
            }
            if next.phase == "running", next.me != nil, !helloSent {
                helloSent = true
                send(.hello(), quiet: true)
            }
        }
        feedPage(raw: raw, whole: base == nil, source: source)
    }

    /// Pending moves: the ones a frame lists have landed. A whole frame that
    /// does not list one posted a while before it means the server lost it
    /// (a restart, a lost write race): it goes again (A28), unless a move
    /// made after it has landed, which it must not be replayed over.
    private func settlePending(_ w: HometownsWire, whole: Bool) {
        let listed = Set((w.me?.moves ?? []).map(\.id))
        let now = Self.nowMs()
        for sent in pending where sent.move.clientId.map({ listed.contains($0) }) == true { landedAt = max(landedAt, sent.at) }
        pending.removeAll { sent in
            guard let id = sent.move.clientId else { return true }
            return listed.contains(id) || now - sent.at > Self.pendingKeepMs
        }
        guard whole else { return }
        pending.removeAll { $0.at < landedAt }
        let again = pending.filter { now - $0.at >= Self.repostAfterMs }
        guard !again.isEmpty else { return }
        for sent in again { touch(sent.move, at: now) }
        Task { for sent in again { await self.post(sent.move, fresh: false) } }
    }

    /// A pending move being posted again counts from now (so it is not posted again by the next frame).
    private func touch(_ move: HometownsMove, at now: Double) {
        guard let id = move.clientId, let k = pending.firstIndex(where: { $0.move.clientId == id }) else { return }
        pending[k].at = now
    }

    /// Haptics and sheets for what a new frame says happened.
    private func react(_ before: HometownsWire?, _ after: HometownsWire) {
        guard let was = before?.town, let now = after.town else {
            // The first frame of a founded town after time away: welcome back (§9.9).
            if before == nil, !(after.me?.welcomeBack.isEmpty ?? true), sheet == nil { sheet = .welcomeBack }
            return
        }
        if now.tier > was.tier { SRHaptic.ok() }
        if now.gridBase != nil, was.gridBase == nil { SRHaptic.ok() }
        if now.sprintLeft < was.sprintLeft { SRHaptic.tap() }
    }

    // MARK: - The page (§10.9)

    /// Stream frames go to the page in order; a snapshot only stands in while
    /// no stream is delivering (the demo, or a phone whose stream will not open).
    private func feedPage(raw: Data?, whole: Bool, source: Source) {
        guard let raw else { return }
        switch source {
        case .streamStart:
            guard whole else { return }
            streamLive = true
            pageWhole = raw
            pageChain = []
        case .stream:
            guard pageWhole != nil else { return }
            pageChain.append(raw)
            if pageChain.count > Self.chainLimit {
                // A long-lived page has merged every one of these; boot from a fresh whole next time.
                restartStream()
                return
            }
        case .snapshot:
            guard whole, !streamLive else { return }
            pageWhole = raw
            pageChain = []
        case .answer:
            return
        }
        guard pageReady else { return }
        // A page that loaded before the first whole frame boots now, chain and all.
        guard pageBooted else {
            boot()
            return
        }
        callPage("if (window.hometowns) window.hometowns.apply(JSON.parse(s).room)", ["s": String(decoding: raw, as: UTF8.self)])
    }

    /// A call into the page with string arguments, which reach it exactly as
    /// sent: the page parses the server's JSON itself.
    func callPage(_ body: String, _ arguments: [String: String] = [:]) {
        webView?.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page, completionHandler: nil)
    }

    /// The page loaded: boot it with the newest whole frame and the chain since.
    private func boot() {
        guard let whole = pageWhole, let w = wire else { return }
        let args: [String: Any] = [
            "bridge": 1,
            "engineHash": w.client.engineHash,
            "copyLevel": w.level.rawValue,
            "theme": (viewDark ?? (UITraitCollection.current.userInterfaceStyle == .dark)) ? "dark" : "light",
            "reduceMotion": viewReduceMotion ?? UIAccessibility.isReduceMotionEnabled,
            "locale": "en-GB",
            "thermal": Self.thermalName(thermal),
            "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled,
        ]
        guard let argsData = try? JSONSerialization.data(withJSONObject: args) else { return }
        pageBooted = true
        callPage("if (window.hometowns) window.hometowns.boot(Object.assign(JSON.parse(a), {wire: JSON.parse(s).room}))",
                 ["a": String(decoding: argsData, as: UTF8.self), "s": String(decoding: whole, as: UTF8.self)])
        for frame in pageChain {
            callPage("if (window.hometowns) window.hometowns.apply(JSON.parse(s).room)", ["s": String(decoding: frame, as: UTF8.self)])
        }
        if tool != .none { setTool(tool) }
        if lens != "none" { setLens(lens) }
        if topDown { setTopDown(true) }
    }

    func pageLoading() {
        pageReady = false
        pageBooted = false
        plan = nil
    }

    /// The thermal state as the page names it.
    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "nominal"
        }
    }

    /// The phone got hotter or cooler, or Low Power Mode changed: the page drops decoration (§9.15).
    func thermalChanged() {
        thermal = ProcessInfo.processInfo.thermalState
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        callPage("if (window.hometowns) window.hometowns.settings({thermal: t, lowPower: p === 'true'})",
                 ["t": Self.thermalName(thermal), "p": lowPower ? "true" : "false"])
    }

    /// The wording, theme and motion the page draws with, whenever any of them
    /// changes after boot (a parent switching this seat, dark mode, Reduce Motion).
    func pageSettings(dark: Bool, reduceMotion: Bool) {
        // Kept for the next boot too: the view's environment is resolved, `UITraitCollection.current` may not be.
        viewDark = dark
        viewReduceMotion = reduceMotion
        let settings: [String: Any] = ["copyLevel": level.rawValue, "theme": dark ? "dark" : "light", "reduceMotion": reduceMotion]
        guard pageBooted, let data = try? JSONSerialization.data(withJSONObject: settings) else { return }
        callPage("if (window.hometowns) window.hometowns.settings(JSON.parse(s))", ["s": String(decoding: data, as: UTF8.self)])
    }

    func setPaused(_ on: Bool) {
        callPage("if (window.hometowns) window.hometowns.paused(\(on ? "true" : "false"))")
    }

    /// One message from the page's `hometowns` handler.
    func receive(_ body: Any) {
        guard let m = body as? [String: Any], let type = m["type"] as? String else { return }
        switch type {
        case "ready":
            pageReady = true
            pageError = nil
            boot()
        case "plan":
            let ops = m["ops"] as? [Any] ?? []
            if ops.isEmpty {
                plan = nil
            } else {
                plan = HometownsPlan(planId: m["planId"] as? String ?? "", ops: ops.count,
                                     cost: (m["cost"] as? NSNumber)?.doubleValue ?? 0,
                                     forecast: HometownsForecast(m["forecast"] as? [String: Any]))
            }
        case "commit":
            guard let planId = m["planId"] as? String, let ops = m["ops"] as? [Any] else { return }
            commit(planId: planId, ops: ops)
        case "inspect":
            if let card = HometownsInspect(m) {
                inspect = card
                SRHaptic.select()
            }
        case "lensChanged":
            lens = m["id"] as? String ?? "none"
        case "speak":
            if let text = m["text"] as? String { speak(text) }
        case "haptic":
            switch m["kind"] as? String {
            case "ok": SRHaptic.ok()
            case "bad": SRHaptic.bad()
            default: SRHaptic.tap()
            }
        case "needResync":
            restartStream()
        case "needReload":
            if let url = reloadURL {
                pageLoading()
                webView?.load(URLRequest(url: url))
            }
        case "stats":
            fps = (m["fps"] as? NSNumber)?.intValue
            minFps = (m["minFps"] as? NSNumber)?.intValue
            simMs = (m["simMs"] as? NSNumber)?.doubleValue
            relayStats(m)
        case "error":
            if let text = m["msg"] as? String { showRefusal(text) }
        default:
            break
        }
    }

    /// The canary and the page's numbers go to the server's log (§10.15): a
    /// mismatch at once, otherwise at most once a minute.
    private func relayStats(_ m: [String: Any]) {
        let canary = m["canary"] as? [String: Any]
        if let canary {
            let ok = canary["ok"] as? Bool ?? true
            let tick = (canary["tick"] as? NSNumber)?.intValue ?? 0
            canaryLine = ok ? "Canary: tick \(tick) matches the server" : "Canary: tick \(tick) differs — resyncing"
        }
        let mismatch = (canary?["ok"] as? Bool) == false
        let now = Self.nowMs()
        guard mismatch || (canary != nil && now - lastStatsAt > 60_000) else { return }
        lastStatsAt = now
        send(.stats(m), quiet: true)
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: String(text.prefix(2000)))
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        speech.stopSpeaking(at: .immediate)
        speech.speak(utterance)
    }

    /// Read a line aloud (§9.14: every advisor line, card and story).
    func readAloud(_ text: String) { speak(text) }

    // MARK: - Tools, lenses, plans

    func setTool(_ next: HometownsTool) {
        tool = next
        guard let data = try? JSONSerialization.data(withJSONObject: next.json) else { return }
        callPage("if (window.hometowns) window.hometowns.tool(JSON.parse(t))", ["t": String(decoding: data, as: UTF8.self)])
    }

    func setTopDown(_ on: Bool) {
        topDown = on
        callPage("if (window.hometowns) window.hometowns.settings({topDown: v === 'true'})", ["v": on ? "true" : "false"])
    }

    func setLens(_ id: String) {
        lens = id
        guard id == "none" || HometownsCatalogue.lenses.contains(id) else { return }
        callPage("if (window.hometowns) window.hometowns.lens(l)", ["l": id])
    }

    /// The forecast card's buttons: Build it!, take back the last ghost, clear the plan.
    func planEdit(_ action: String) {
        guard ["commit", "undo", "clear"].contains(action) else { return }
        if action == "commit" { SRHaptic.tap() }
        callPage("if (window.hometowns) window.hometowns.planEdit({action: a})", ["a": action])
    }

    /// An advisor's or a want's deep link (§9.7): a lens, a sheet, a tool, or a ghost plan.
    func follow(_ action: String) {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        switch parts[0] {
        case "lens":
            let lens = ["homes": "desirability", "jobs": "jobs", "traffic": "traffic", "pollution": "pollution"][parts[1]] ?? parts[1]
            setLens(HometownsCatalogue.lenses(forTier: town?.tier ?? 0).contains(lens) ? lens : "landValue")
        case "zone":
            setTool(HometownsTool(kind: "zone", variant: parts[1]))
        case "build":
            sheet = .build
        case "sheet":
            switch parts[1] {
            case "budget", "helper", "borrowing": sheet = .townHall
            case "wants", "talk", "growth", "recover": sheet = .people
            default: sheet = .townHall
            }
        default:
            break
        }
    }

    /// "What would make it grow?" (§9.5): the page drops the ghost plan.
    func dropGhost(_ ops: [Any]) {
        guard JSONSerialization.isValidJSONObject(["plan": ops]),
              let data = try? JSONSerialization.data(withJSONObject: ["plan": ops]) else { return }
        callPage("if (window.hometowns) window.hometowns.ghost(JSON.parse(g))", ["g": String(decoding: data, as: UTF8.self)])
    }

    func focus(tile: Int) {
        guard tile >= 0, tile < 64 * 64 else { return }
        callPage("if (window.hometowns) window.hometowns.focus({x: \(tile % 64), y: \(tile / 64)})")
    }

    /// The page committed a plan (Build it!): post it as one atomic move.
    private func commit(planId: String, ops: [Any]) {
        committing = true
        var counted = tutorial
        counted.note(ops)
        send(.build(planId: planId, ops: ops)) { [weak self] outcome in
            guard let self else { return }
            self.committing = false
            switch outcome {
            case .ok:
                self.tutorial = counted
                Self.storeTutorial(counted, self.roomId)
                self.commitResult(planId: planId, ok: true, error: nil)
                self.setTool(.none)
                SRHaptic.ok()
            case .refused(let sentence):
                self.commitResult(planId: planId, ok: false, error: sentence)
            case .failed(let text):
                // Not kept: the page puts the plan back as ghosts under the
                // same planId, so building it again is the retry, and the
                // server answers it from its log if the first one did land.
                self.drop(id: planId)
                self.commitResult(planId: planId, ok: false, error: text)
            case .gone:
                break
            }
        }
    }

    private func commitResult(planId: String, ok: Bool, error: String?) {
        var payload: [String: Any] = ["planId": planId, "ok": ok]
        if let error { payload["error"] = error }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        callPage("if (window.hometowns) window.hometowns.commitResult(JSON.parse(r))", ["r": String(decoding: data, as: UTF8.self)])
    }

    // MARK: - Moves

    enum Outcome: Equatable {
        case ok
        case refused(String)
        case failed(String)
        case gone
    }

    /// Post a move. `quiet` moves (hello, seen, stats) say nothing when they
    /// fail. A mutating move whose post fails on the way (no connection) stays
    /// pending, and the whole frame a reconnect starts with posts it again.
    func send(_ move: HometownsMove, quiet: Bool = false, then: ((Outcome) -> Void)? = nil) {
        if move.isPending { pending.append(Sent(move: move, at: Self.nowMs())) }
        Task {
            let outcome = await self.post(move, fresh: true)
            if !quiet, case .refused(let sentence) = outcome { self.showRefusal(sentence) }
            if !quiet, case .failed(let text) = outcome { self.message = text }
            then?(outcome)
        }
    }

    /// One POST, with the retry a Regional Day in progress asks for.
    @discardableResult
    private func post(_ move: HometownsMove, fresh: Bool) async -> Outcome {
        guard let body = move.body(since: heldRev) else { return .refused("That move could not be sent.") }
        let sent = Self.nowMs()
        do {
            let data = try await client.post("api/native/games/\(roomId)", body: body)
            if let frame = HometownsFrames.room(in: data) {
                if let now = frame["serverNow"] as? NSNumber {
                    clock.record(serverNow: now.doubleValue, sentAt: sent, receivedAt: Self.nowMs())
                }
                absorb(frame, raw: nil, source: .answer)
            }
            if let id = move.clientId { retries[id] = nil }
            return .ok
        } catch SiteError.status(let code, let sentence) where code == 404 {
            // A move can be refused with a 404 of its own ("That town isn't in
            // this county."): only the snapshot says whether the county is gone.
            drop(move)
            await refresh()
            return ended ? .gone : .refused(sentence)
        } catch SiteError.status(let code, let sentence) where code == 409 && HometownsRetry.matches(sentence) {
            // A19: the day completes within a few chunks; try again in a second.
            let id = move.clientId ?? move.action
            let n = (retries[id] ?? 0) + 1
            retries[id] = n
            guard n <= 6 else {
                drop(move)
                return .refused(sentence)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return await post(move, fresh: false)
        } catch SiteError.status(let code, let sentence) where (400..<500).contains(code) {
            drop(move)
            return .refused(sentence)
        } catch SiteError.invalid(let sentence, _) {
            drop(move)
            return .refused(sentence)
        } catch SiteError.expired {
            return .failed("This iPhone needs pairing again.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func drop(_ move: HometownsMove) {
        if let id = move.clientId { drop(id: id) }
    }

    private func drop(id: String) {
        pending.removeAll { $0.move.clientId == id }
        retries[id] = nil
    }

    private func showNotice(_ sentence: String) {
        notice = sentence
        SRHaptic.ok()
        UIAccessibility.post(notification: .announcement, argument: sentence)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self?.notice == sentence { self?.notice = nil }
        }
    }

    private func showRefusal(_ sentence: String) {
        refusal = sentence
        SRHaptic.bad()
        UIAccessibility.post(notification: .announcement, argument: sentence)
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.refusal = nil
        }
    }

    /// join | leave | start: the lobby's buttons. A plain action, answered whole.
    @discardableResult
    func act(_ action: String) async -> Bool {
        busy = true
        defer { busy = false }
        switch await post(HometownsMove(action: action), fresh: true) {
        case .ok:
            return true
        case .refused(let text), .failed(let text):
            message = text
            return false
        case .gone:
            return false
        }
    }

    // MARK: - The town's moves

    /// "Next week ▶" (§2.3): one founding week, at least ten seconds after the
    /// last. Ten seconds is the shipped `sprintMinGapMs`; the wire does not
    /// carry it, so a retuned gap the server still refuses ("Watch your town
    /// grow…") only makes the button rest a little longer, with no refusal shown.
    func nextWeek() {
        guard let now = serverNow(), now >= sprintWaitUntil else { return }
        sprintWaitUntil = now + 10_000
        send(.sprint(), quiet: true) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .refused(let sentence) where sentence.hasPrefix(Self.sprintTooSoon):
                self.sprintWaitUntil = max(self.sprintWaitUntil, (self.serverNow() ?? now) + 5_000)
            case .refused(let sentence):
                self.showRefusal(sentence)
            case .failed(let text):
                self.message = text
            case .ok, .gone:
                break
            }
        }
    }

    /// The engine's refusal of a founding week asked for too soon.
    private static let sprintTooSoon = "Watch your town grow"

    /// "Play it all": the rest of the fortnight, a week every fifteen seconds (adults).
    func playItAll() { send(.sprint(auto: true)) }

    /// Seconds before "Next week ▶" can be pressed again.
    func sprintWait() -> Int {
        guard let now = serverNow() else { return 0 }
        let town = self.town
        let lastAt = max(sprintWaitUntil - 10_000, town?.sprintAt ?? 0)
        let left = (lastAt + 10_000 - now) / 1000
        return lastAt > 0 && left > 0 ? Int(left.rounded(.up)) : 0
    }

    func undo(_ planId: String) {
        send(.undo(planId: planId)) { [weak self] outcome in
            if outcome == .ok { self?.showNotice(self?.say("undo.done") ?? "Undone.") }
        }
    }

    func budget(taxes: [String: Any]?, funding: [String: Int]?) {
        send(.budget(taxes: taxes, funding: funding)) { outcome in
            if outcome == .ok { SRHaptic.ok() }
        }
    }

    func setOrders(_ orders: [HometownsOrder]) { send(.orders(orders)) }

    func found(site: Int, nameParts: (String, String)?, name: String?, avatar: String, flag: Int) async -> String? {
        await withCheckedContinuation { continuation in
            send(.found(site: site, nameParts: nameParts, name: name, avatar: avatar, flag: flag), quiet: true) { outcome in
                switch outcome {
                case .ok, .gone: continuation.resume(returning: nil)
                case .refused(let text), .failed(let text): continuation.resume(returning: text)
                }
            }
        }
    }

    func pause(_ on: Bool) { send(.pause(on)) }

    func settings(county: [String: Any]? = nil, seat: [String: Any]? = nil) {
        send(.settings(county: county, seat: seat)) { outcome in
            if outcome == .ok { SRHaptic.ok() }
        }
    }

    /// Welcome back is read: the next open replays only what is new.
    func seenWelcome() {
        if let t = town { send(.seen(tick: t.tick), quiet: true) }
    }

    // MARK: - The tutorial, kept per county on this phone

    private static func tutorialKey(_ roomId: String) -> String { "hometowns-tutorial-\(roomId)" }

    private static func storedTutorial(_ roomId: String) -> HometownsTutorial {
        guard let data = UserDefaults.standard.data(forKey: tutorialKey(roomId)),
              let t = try? JSONDecoder().decode(HometownsTutorial.self, from: data) else { return HometownsTutorial() }
        return t
    }

    private static func storeTutorial(_ t: HometownsTutorial, _ roomId: String) {
        if let data = try? JSONEncoder().encode(t) { UserDefaults.standard.set(data, forKey: tutorialKey(roomId)) }
    }
}

/// The sheets over the town.
enum HometownsSheet: String, Identifiable {
    case build, lenses, townHall, people, county, welcomeBack, parent

    var id: String { rawValue }
}

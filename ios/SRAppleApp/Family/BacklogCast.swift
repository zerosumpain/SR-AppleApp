import AVKit
import GoogleCast
import SwiftUI

// "Play on TV" for the family backlog: one item, or everything on the shelf.
//
// A TV plays a plain video file and nothing else — not a TikTok page, not a
// web page. So the site fetches the clip (yt-dlp) and answers with a link the
// TV can open for six hours without a login
// (`POST api/native/family/backlog/<id>/cast`). The phone then hands that link
// to a Chromecast (the Google Cast SDK, Default Media Receiver) or plays it
// itself with AirPlay on. What the site cannot fetch comes back as a fallback:
// open it on the phone and mirror the screen — or, for YouTube, open it in the
// YouTube app, which casts by itself.

/// What the site says about one item.
struct BacklogCastWire: Decodable, Equatable {
    let state: String
    let mediaUrl: String?
    let title: String?
    let posterUrl: String?
    let durationSeconds: Double?
    let retryAfterSeconds: Double?
    let fallback: String?
    let reason: String?
    let url: String?
}

enum BacklogCastState: Equatable {
    case preparing
    case ready(BacklogCastWire)
    /// Play it from the phone. `youtube` when the YouTube app can cast it.
    case onPhone(reason: String, youtube: Bool)
    case failed(String)

    var isReady: Bool { if case .ready = self { return true } else { return false } }
}

enum BacklogCastSetup {
    /// At launch, before any screen asks: the Cast SDK wants its context
    /// early. Discovery (and with it the Local Network prompt) waits for the
    /// first tap on the Cast button, so nobody is asked who never casts.
    static func install() {
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.startDiscoveryAfterFirstTapOnCastButton = true
        GCKCastContext.setSharedInstanceWith(options)
    }
}

@MainActor
final class BacklogCastSession: ObservableObject {
    /// In the order they will play.
    let items: [FamilyBacklogItem]
    @Published private(set) var states: [String: BacklogCastState] = [:]
    @Published private(set) var castConnected = false
    @Published private(set) var castDevice: String?
    @Published var message: String?
    /// The queue on the Chromecast, once started: ids already sent to it.
    private var sent: Set<String> = []
    private var playing = false
    private var observer: NSObjectProtocol?

    init(items: [FamilyBacklogItem]) {
        self.items = items
        for item in items { states[item.id] = .preparing }
        refreshCastState()
        observer = NotificationCenter.default.addObserver(
            forName: kGCKCastStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.castStateChanged() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var ready: [(FamilyBacklogItem, BacklogCastWire)] {
        items.compactMap { item in
            if case .ready(let wire) = states[item.id] { return (item, wire) }
            return nil
        }
    }

    var waiting: Int { items.filter { states[$0.id] == .preparing }.count }
    var onPhone: Int { items.count - ready.count - waiting }

    /// Ask the site about every item, two at a time (the site fetches two at
    /// a time anyway), in list order so the first to play is the first ready.
    func prepare() async {
        await withTaskGroup(of: Void.self) { group in
            for (index, item) in items.enumerated() {
                if index >= 2 { _ = await group.next() }
                group.addTask { await self.prepare(item) }
            }
        }
    }

    private func prepare(_ item: FamilyBacklogItem) async {
        if SRDemo.isOn {
            states[item.id] = .onPhone(reason: "Not in the demo.", youtube: false)
            return
        }
        // About five minutes of asking: a long YouTube video takes a while.
        for _ in 0..<100 {
            do {
                let wire: BacklogCastWire = try await SiteClient.shared.send(
                    "api/native/family/backlog/\(item.id)/cast", method: "POST"
                )
                switch wire.state {
                case "ready":
                    states[item.id] = .ready(wire)
                    appendIfPlaying()
                    return
                case "fallback":
                    states[item.id] = .onPhone(
                        reason: wire.reason ?? "This one plays on the phone.",
                        youtube: wire.fallback == "youtube_app"
                    )
                    return
                default:
                    let wait = min(max(wire.retryAfterSeconds ?? 3, 1), 10)
                    try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
            } catch is CancellationError {
                return
            } catch {
                if (error as? URLError)?.code == .cancelled { return }
                states[item.id] = .failed(FamilyBacklogStore.sentence(for: error))
                return
            }
        }
        states[item.id] = .onPhone(reason: "It took too long to fetch.", youtube: item.provider == "youtube")
    }

    // MARK: Chromecast

    private func refreshCastState() {
        let context = GCKCastContext.sharedInstance()
        castConnected = context.castState == .connected
        castDevice = context.sessionManager.currentCastSession?.device.friendlyName
    }

    private func castStateChanged() {
        let was = castConnected
        refreshCastState()
        if !castConnected { playing = false; sent = [] }
        // Picked a TV after things were ready: start at once.
        if castConnected, !was, !ready.isEmpty { playOnCast() }
    }

    /// Start the queue on the connected Chromecast with whatever is ready;
    /// the rest join the end as they arrive.
    func playOnCast() {
        guard let client = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient else {
            message = "Choose a TV first."
            return
        }
        let batch = ready.filter { !sent.contains($0.0.id) }
        guard !batch.isEmpty else { return }
        let queue = GCKMediaQueueDataBuilder(queueType: .generic)
        queue.items = batch.compactMap { Self.queueItem($0.1) }
        queue.startIndex = 0
        let request = GCKMediaLoadRequestDataBuilder()
        request.queueData = queue.build()
        client.loadMedia(with: request.build())
        batch.forEach { sent.insert($0.0.id) }
        playing = true
        SRHaptic.ok()
    }

    private func appendIfPlaying() {
        guard playing,
              let client = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient
        else { return }
        // Only in list order: an item that is ready waits for the ones before
        // it, so the TV plays the list as it reads.
        for item in items {
            guard case .ready(let wire)? = states[item.id] else {
                if states[item.id] == .preparing { return }
                continue
            }
            guard !sent.contains(item.id), let queued = Self.queueItem(wire) else { continue }
            client.queueInsert(queued, beforeItemWithID: kGCKMediaQueueInvalidItemID)
            sent.insert(item.id)
        }
    }

    private static func queueItem(_ wire: BacklogCastWire) -> GCKMediaQueueItem? {
        guard let raw = wire.mediaUrl, let url = URL(string: raw) else { return nil }
        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(wire.title ?? "From the backlog", forKey: kGCKMetadataKeyTitle)
        if let poster = wire.posterUrl.flatMap(URL.init(string:)) {
            metadata.addImage(GCKImage(url: poster, width: 480, height: 360))
        }
        let media = GCKMediaInformationBuilder(contentURL: url)
        media.streamType = .buffered
        media.contentType = "video/mp4"
        media.metadata = metadata
        if let d = wire.durationSeconds { media.streamDuration = d }
        let item = GCKMediaQueueItemBuilder()
        item.mediaInformation = media.build()
        item.autoplay = true
        item.preloadTime = 10
        return item.build()
    }

    // MARK: AirPlay

    /// The ready videos as one queue for AVPlayer — AirPlay sends the video
    /// itself to the TV, not the phone's screen.
    func airPlayQueue() -> AVQueuePlayer? {
        let urls = ready.compactMap { $0.1.mediaUrl.flatMap(URL.init(string:)) }
        guard !urls.isEmpty else { return nil }
        let player = AVQueuePlayer(items: urls.map { AVPlayerItem(url: $0) })
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        return player
    }
}

/// The Cast button, as UIKit draws it: grey with no TV about, filled when connected.
struct CastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
        button.tintColor = UIColor(SR.accentInk)
        return button
    }

    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}

/// The AirPlay picker. Choosing a TV here sends the next video played to it.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = UIColor(SR.accentInk)
        picker.activeTintColor = UIColor(SR.accent)
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// AVKit's player, full screen, with its own AirPlay button.
struct BacklogAirPlayer: UIViewControllerRepresentable {
    let player: AVQueuePlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
    }
}

/// "Play on TV": pick the TV, watch the list get ready, play.
struct BacklogCastSheet: View {
    @StateObject private var session: BacklogCastSession
    @State private var airPlayer: AVQueuePlayer?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    init(items: [FamilyBacklogItem]) {
        _session = StateObject(wrappedValue: BacklogCastSession(items: items))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        CastButton().frame(width: 32, height: 32).accessibilityLabel("Chromecast")
                        AirPlayButton().frame(width: 32, height: 32).accessibilityLabel("AirPlay")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.castDevice.map { "On \($0)" } ?? "Choose the TV")
                                .font(SR.Text.title())
                                .foregroundStyle(SR.ink)
                            Text(session.castConnected
                                 ? "Ready videos play there, in list order."
                                 : "Chromecast on the left, AirPlay on the right.")
                                .font(SR.Text.secondary(13))
                                .foregroundStyle(SR.inkMuted)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text(summary)
                        .font(SR.Text.secondary(13))
                }

                Section {
                    ForEach(session.items) { item in row(item) }
                } header: {
                    SRSectionLabel(text: session.items.count == 1 ? "Playing" : "Up next", trailing: "\(session.items.count)")
                }

                if !mirrorItems.isEmpty {
                    Section {
                        Text("These play on the phone. To see one on the TV, open Control Centre, tap Screen Mirroring and choose the TV, then open it here.")
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkSecondary)
                    } header: {
                        SRSectionLabel(text: "Mirror from the phone")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .srPaper()
            .navigationTitle("Play on TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .overlay(alignment: .bottom) {
                if let message = session.message { SRBanner(text: message, tone: SR.error) }
            }
        }
        .tint(SR.accent)
        .task { await session.prepare() }
        .fullScreenCover(item: Binding(
            get: { airPlayer.map(PlayerBox.init) },
            set: { airPlayer = $0?.player }
        )) { box in
            BacklogAirPlayer(player: box.player).ignoresSafeArea()
        }
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("backlog-cast-sheet")
    }

    private var mirrorItems: [FamilyBacklogItem] {
        session.items.filter {
            if case .onPhone(_, let youtube)? = session.states[$0.id] { return !youtube }
            return false
        }
    }

    private var summary: String {
        let ready = session.ready.count
        var parts: [String] = []
        if ready > 0 { parts.append(ready == 1 ? "1 ready" : "\(ready) ready") }
        if session.waiting > 0 { parts.append("\(session.waiting) being fetched") }
        if session.onPhone > 0 { parts.append("\(session.onPhone) on the phone only") }
        return parts.isEmpty ? "Getting ready…" : parts.joined(separator: " · ")
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if session.castConnected {
                Button {
                    session.playOnCast()
                } label: {
                    Label("Play on the TV", systemImage: "tv").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.ready.isEmpty)
                .accessibilityIdentifier("backlog-cast-play")
            }
            Button {
                SRHaptic.tap()
                airPlayer = session.airPlayQueue()
            } label: {
                Label(session.castConnected ? "Play with AirPlay instead" : "Play (AirPlay)", systemImage: "airplayvideo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(session.ready.isEmpty)
            .accessibilityIdentifier("backlog-cast-airplay")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func row(_ item: FamilyBacklogItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: FamilyBacklogRules.symbol(item))
                .foregroundStyle(SR.accentInk)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(FamilyBacklogText.title(item))
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                if let line = line(item) {
                    Text(line)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing(item)
        }
        .accessibilityElement(children: .combine)
    }

    private func line(_ item: FamilyBacklogItem) -> String? {
        switch session.states[item.id] {
        case .preparing?: return "Fetching for the TV…"
        case .ready?: return nil
        case .onPhone(let reason, let youtube)?:
            return youtube ? "\(reason) Open it in YouTube and tap the cast icon there." : reason
        case .failed(let text)?: return text
        case nil: return nil
        }
    }

    @ViewBuilder
    private func trailing(_ item: FamilyBacklogItem) -> some View {
        switch session.states[item.id] {
        case .preparing?:
            ProgressView().tint(SR.accent)
        case .ready?:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(SR.good).accessibilityLabel("Ready")
        default:
            if let link = item.url.flatMap(URL.init(string:)) {
                Button("Open") { SRHaptic.tap(); openURL(link) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

/// `fullScreenCover(item:)` wants Identifiable; a player is not.
private struct PlayerBox: Identifiable {
    let player: AVQueuePlayer
    var id: ObjectIdentifier { ObjectIdentifier(player) }
}

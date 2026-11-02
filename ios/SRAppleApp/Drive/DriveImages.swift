import SwiftUI
import UIKit

extension DriveLogic {
    /// `api/native/drive/files/<id>/preview?size=thumb|view[&v=…]`: the
    /// site's JPEG of a picture, for tiles and the viewer. `version`
    /// (`DrivePreviewLogic.version`) changes with the bytes, so the site may
    /// mark the answer immutable. Here rather than beside `filePath` because
    /// the Share extension compiles DriveModels without the preview types.
    static func previewPath(_ id: String, _ size: DrivePreviewSize, version: String? = nil) -> String {
        filePath(id, "preview") + "?" + DrivePreviewLogic.query(size: size, version: version)
    }
}

/// One picture of one Drive file, at one drawn size.
struct DriveImageRequest: Sendable {
    let file: DriveFile
    let version: String
    let size: DrivePreviewSize
    /// The longest edge it is drawn at, in points.
    let points: CGFloat

    init(_ file: DriveFile, size: DrivePreviewSize, points: CGFloat) {
        self.file = file
        version = DrivePreviewLogic.version(sizeBytes: file.sizeBytes, updatedAt: file.updatedAt)
        self.size = size
        self.points = points
    }

    var id: String { file.id }
    var memoryKey: String { DrivePreviewLogic.memoryKey(id: id, version: version, size: size, points: Double(points)) }
    var diskName: String { DrivePreviewLogic.diskName(id: id, version: version, size: size) }
    /// The file at this version, whatever the size: what "the site will not render it" is remembered by.
    var fileKey: String { "\(id)|\(version)" }
    var memory: SRImageMemory { size == .view ? .driveViews : .drive }
}

/// What came of asking for a picture.
enum DriveImageOutcome {
    case image(UIImage)
    /// The site has no preview of this (an older site, or not a picture it
    /// renders): the viewer opens the original instead.
    case noPreview
    /// Not now (offline, cancelled, a timeout).
    case failed
}

/// Drive's pictures: the site's JPEG previews, never the originals.
///
/// A tile used to pull the whole original (up to 15 MB) to draw a 120-pixel
/// square, copy it into the downloads cache, and decode it whole. Now:
///
///   1. memory — decoded at the drawn size, bounded by bytes (`SRImageMemory`);
///   2. disk — the site's preview JPEG (~30 KB a tile), under Caches/drive;
///   3. the site — `…/files/<id>/preview?size=…&v=…`, at most four at once,
///      one request per picture however many tiles ask, and dropped when the
///      last tile asking scrolls away.
///
/// An older site answers the preview 404: a tile then fetches the original
/// only if it is small (`DrivePreviewLogic.fallbackMaxBytes`), keeps a
/// tile-sized JPEG of it, and drops the original.
actor DriveImageLoader {
    static let shared = DriveImageLoader()

    private struct Job {
        let task: Task<DriveImageOutcome, Never>
        var waiters: Set<UUID>
    }

    private var jobs: [String: Job] = [:]
    /// Files at a version the site will not render (415, 410, 422): not asked again this session.
    private var refused: Set<String> = []
    /// The site answered a preview 404 and then served the original: it has
    /// no preview route yet, so tiles go straight to the old way this session.
    private var legacySite = false
    private var writes = 0
    private let gate = SRFetchGate(limit: 4)

    /// Previews take at most this much of Caches; the oldest go first.
    static let diskBudget = 150 * 1024 * 1024

    static var folder: URL { DriveCache.previewsFolder }

    /// Already decoded, for a tile's first frame. Any thread.
    static func cached(_ request: DriveImageRequest) -> UIImage? {
        request.memory.image(for: request.memoryKey)
    }

    func image(_ request: DriveImageRequest, scale: CGFloat) async -> UIImage? {
        if case .image(let image) = await load(request, scale: scale) { return image }
        return nil
    }

    func load(_ request: DriveImageRequest, scale: CGFloat) async -> DriveImageOutcome {
        if let hit = Self.cached(request) { return .image(hit) }
        if refused.contains(request.fileKey) { return .noPreview }
        let key = request.memoryKey
        let me = UUID()
        let task: Task<DriveImageOutcome, Never>
        if var job = jobs[key] {
            job.waiters.insert(me)
            jobs[key] = job
            task = job.task
        } else {
            task = Task { await self.produce(request, scale: scale) }
            jobs[key] = Job(task: task, waiters: [me])
        }
        let outcome = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { await self.leave(key, me, cancelled: true) }
        }
        leave(key, me, cancelled: false)
        return outcome
    }

    /// One asker gone. When the last one goes before the picture arrived,
    /// the fetch is cancelled too (and leaves the gate's queue).
    private func leave(_ key: String, _ waiter: UUID, cancelled: Bool) {
        guard var job = jobs[key], job.waiters.remove(waiter) != nil else { return }
        if job.waiters.isEmpty {
            jobs[key] = nil
            if cancelled { job.task.cancel() }
        } else {
            jobs[key] = job
        }
    }

    private func refuse(_ request: DriveImageRequest) { refused.insert(request.fileKey) }
    private func markLegacy() { legacySite = true }
    private func isLegacy() -> Bool { legacySite }

    private func wrote() {
        writes += 1
        // The first write of a session, and every 40th after it.
        if writes % 40 == 1 {
            Task.detached(priority: .utility) { Self.trimDisk() }
        }
    }

    // MARK: - The work, off the actor (nonisolated async runs on the shared pool)

    private nonisolated func produce(_ request: DriveImageRequest, scale: CGFloat) async -> DriveImageOutcome {
        let pixels = SRImageLogic.pixels(points: Double(request.points), scale: Double(scale))
        let file = Self.folder.appendingPathComponent(request.diskName)

        // 2. Disk: decoded straight from the file, never read whole.
        if FileManager.default.fileExists(atPath: file.path),
           let image = SRDownsample.image(url: file, maxPixels: pixels) {
            request.memory.put(image, for: request.memoryKey)
            return .image(image)
        }
        guard !Task.isCancelled else { return .failed }

        // An original already on the phone (opened before): no network at all.
        if let local = DriveCache.url(for: request.file),
           let image = SRDownsample.image(url: local, maxPixels: pixels) {
            request.memory.put(image, for: request.memoryKey)
            return .image(image)
        }

        do {
            try await gate.enter()
        } catch {
            return .failed
        }
        let outcome = await fetch(request, file: file, pixels: pixels)
        await gate.leave()
        return outcome
    }

    private nonisolated func fetch(_ request: DriveImageRequest, file: URL, pixels: Int) async -> DriveImageOutcome {
        if await isLegacy() {
            // The viewer opens an older site's original in Quick Look instead.
            guard request.size == .thumb else { return .noPreview }
            return await fallback(request, pixels: pixels)
        }
        let path = DriveLogic.previewPath(request.id, request.size, version: request.version)
        var status: Int?
        var data: Data?
        do {
            data = try await SiteClient.shared.bytes(path)
            status = 200
        } catch {
            status = (error as? SiteError)?.status
        }
        guard !Task.isCancelled else { return .failed }
        switch DrivePreviewLogic.answer(status: status) {
        case .show:
            guard let data, let image = SRDownsample.image(data: data, maxPixels: pixels) else { return .failed }
            Self.save(data, to: file)
            await wrote()
            request.memory.put(image, for: request.memoryKey)
            return .image(image)
        case .original:
            // The viewer opens the original itself, with Quick Look.
            guard request.size == .thumb else { return .noPreview }
            return await fallback(request, pixels: pixels)
        case .mark:
            await refuse(request)
            return .noPreview
        case .later:
            return .failed
        }
    }

    /// An older site: the original, if it is small, made into a tile-sized
    /// JPEG for the disk cache. The original itself is not kept.
    private nonisolated func fallback(_ request: DriveImageRequest, pixels: Int) async -> DriveImageOutcome {
        guard DrivePreviewLogic.mayFetchOriginal(sizeBytes: request.file.sizeBytes) else { return .noPreview }
        guard let data = try? await SiteClient.shared.bytes(DriveLogic.filePath(request.id)), !Task.isCancelled else { return .failed }
        await markLegacy()
        // Kept at the size the site's own tile would be, so a list mark made
        // first never leaves the grid a 96-pixel picture.
        guard let tile = SRDownsample.image(data: data, maxPixels: DrivePreviewSize.thumb.edge) else {
            await refuse(request)
            return .noPreview
        }
        if let jpeg = tile.jpegData(compressionQuality: 0.75) {
            Self.save(jpeg, to: Self.folder.appendingPathComponent(request.diskName))
            await wrote()
        }
        let image = pixels < DrivePreviewSize.thumb.edge ? (SRDownsample.image(data: data, maxPixels: pixels) ?? tile) : tile
        request.memory.put(image, for: request.memoryKey)
        return .image(image)
    }

    private static func save(_ data: Data, to file: URL) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
        } catch {
            // A cache: the next ask fetches it again.
        }
    }

    /// Down to 80% of the budget, oldest first.
    static func trimDisk() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let names = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        let entries = names.compactMap { url -> SRImageLogic.DiskEntry? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return SRImageLogic.DiskEntry(name: url.lastPathComponent, bytes: values.fileSize ?? 0,
                                          modified: values.contentModificationDate ?? .distantPast)
        }
        for name in SRImageLogic.trimPlan(entries, budget: diskBudget) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Every preview of a file (deleted, renamed or moved), off the main thread.
    static func forget(id: String) {
        let prefix = DrivePreviewLogic.diskPrefix(id: id)
        DispatchQueue.global(qos: .utility).async {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
            for name in names where name.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }
}

/// A Drive file's picture, loaded by the tile itself: each tile watches only
/// its own image, so one landing redraws one tile — not the whole screen and
/// its sort. The load starts when the tile appears and is cancelled when it
/// scrolls away.
struct DriveThumb<Placeholder: View>: View {
    let request: DriveImageRequest
    @ViewBuilder let placeholder: () -> Placeholder
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    init(file: DriveFile, points: CGFloat, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        let request = DriveImageRequest(file, size: .thumb, points: points)
        self.request = request
        self.placeholder = placeholder
        // Decoded already (scrolled back to): drawn on the first frame.
        _image = State(initialValue: DriveImageLoader.cached(request))
    }

    var body: some View {
        // Clear takes exactly the space offered; the picture fills it and is clipped.
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    placeholder()
                }
            }
            .clipped()
            .task(id: request.memoryKey) {
                if let hit = DriveImageLoader.cached(request) {
                    image = hit
                    return
                }
                let loaded = await DriveImageLoader.shared.image(request, scale: scale)
                if !Task.isCancelled, let loaded { image = loaded }
            }
    }
}

/// A photo full screen: the site's screen-sized preview at once (~300 KB),
/// then the original only when it is zoomed past what that can show. The
/// original is kept in the downloads cache like any opened file, so Share
/// and a second look cost nothing. A file the site has no preview of opens
/// in Quick Look instead (`unavailable`).
struct DrivePhotoViewer: View {
    let file: DriveFile
    /// The original on this phone (fetched once per version).
    let original: () async -> URL?
    let unavailable: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?
    @State private var failed = false
    @State private var sharp = false
    @State private var fetchingOriginal = false
    @State private var sharing: DriveLocalFile?

    /// Past this zoom a 2048-pixel picture is visibly soft on a phone.
    private static let originalZoom: CGFloat = 1.6

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    DriveZoomView(image: image) { zoom in
                        if zoom > Self.originalZoom { loadOriginal() }
                    }
                    .ignoresSafeArea()
                    .accessibilityLabel(file.name)
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "photo").font(.largeTitle)
                        Text("This photo didn't open.").font(SR.Text.secondary(14))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                } else {
                    ProgressView().tint(.white)
                }
                if fetchingOriginal {
                    VStack {
                        Spacer()
                        ProgressView().tint(.white).padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("drive-viewer-done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { if let url = await original() { sharing = DriveLocalFile(url: url) } }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                    .accessibilityIdentifier("drive-viewer-share")
                }
            }
        }
        .accessibilityIdentifier("drive-viewer")
        .sheet(item: $sharing) { DriveActivitySheet(url: $0.url) }
        .task(id: file.id) {
            // Screen-sized: the long edge the site renders, decoded no larger.
            let request = DriveImageRequest(file, size: .view, points: CGFloat(DrivePreviewSize.view.edge) / max(1, scale))
            switch await DriveImageLoader.shared.load(request, scale: scale) {
            case .image(let picture): image = picture
            case .noPreview: unavailable()
            case .failed: if !Task.isCancelled { failed = true }
            }
        }
    }

    /// The original, decoded at no more than `SRImageLogic.maxPixels`: a
    /// 48-megapixel photo would otherwise be 190 MB in memory.
    @MainActor
    private func loadOriginal() {
        guard !sharp, !fetchingOriginal else { return }
        fetchingOriginal = true
        Task {
            defer { fetchingOriginal = false }
            guard let url = await original() else { return }
            let decoded = await Task.detached(priority: .userInitiated) {
                SRDownsample.image(url: url, maxPixels: SRImageLogic.maxPixels)
            }.value
            if let decoded {
                image = decoded
                sharp = true
            }
        }
    }
}

/// Pinch and double-tap zoom: a UIScrollView, which SwiftUI's own gestures
/// cannot match for momentum and bounce. `zoomed` hears each new scale.
struct DriveZoomView: UIViewRepresentable {
    let image: UIImage
    let zoomed: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(zoomed: zoomed) }

    func makeUIView(context: Context) -> DriveZoomScrollView {
        let scroll = DriveZoomScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 8
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear
        let picture = UIImageView(image: image)
        picture.contentMode = .scaleAspectFit
        picture.isAccessibilityElement = false
        scroll.addSubview(picture)
        scroll.picture = picture
        context.coordinator.picture = picture
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: DriveZoomScrollView, context: Context) {
        context.coordinator.zoomed = zoomed
        // The sharper original replaces the preview in place: same aspect, same frame, the zoom kept.
        if scroll.picture?.image !== image { scroll.picture?.image = image }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var zoomed: (CGFloat) -> Void
        weak var picture: UIImageView?

        init(zoomed: @escaping (CGFloat) -> Void) {
            self.zoomed = zoomed
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            zoomed(scale)
        }

        @objc func doubleTapped(_ tap: UITapGestureRecognizer) {
            guard let scroll = tap.view as? UIScrollView, let picture else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = tap.location(in: picture)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }
    }
}

/// Keeps the picture the size of the screen while it is not zoomed (a
/// rotation, the first layout); zoomed, the scroll view's transform rules.
final class DriveZoomScrollView: UIScrollView {
    weak var picture: UIImageView?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let picture, zoomScale == 1, picture.frame.size != bounds.size else { return }
        picture.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
    }
}

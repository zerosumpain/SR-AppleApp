import ImageIO
import Photos
import SwiftUI
import UIKit

/// Pictures decoded at the size they are drawn, off the main thread.
///
/// `UIImage(data:)` keeps the whole file and decodes every pixel the first
/// time it is drawn — on the main thread, mid-scroll — so a 12-megapixel
/// photo in a 32-point square costs 48 MB and a dropped frame. ImageIO's
/// thumbnail call decodes straight to the size asked for, applies the EXIF
/// orientation, and (`ShouldCacheImmediately`) does the decode now, on
/// whichever thread asks, so drawing it later is free.
enum SRDownsample {
    /// From bytes in memory. Nil for anything ImageIO cannot read.
    static func image(data: Data, maxPixels: Int) -> UIImage? {
        // Not cached by the source: the thumbnail below is what is kept.
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return image(source, maxPixels)
    }

    /// From a file, read only as far as ImageIO needs — never whole into memory.
    static func image(url: URL, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return image(source, maxPixels)
    }

    private static func image(_ source: CGImageSource, _ maxPixels: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, min(maxPixels, SRImageLogic.maxPixels)),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// What a decoded picture costs a cache, in bytes.
    static func cost(_ image: UIImage) -> Int {
        if let cg = image.cgImage { return cg.bytesPerRow * cg.height }
        return SRImageLogic.decodedCost(width: Int(image.size.width * image.scale), height: Int(image.size.height * image.scale))
    }
}

/// A memory cache of decoded pictures, bounded by their decoded bytes — an
/// `NSCache` with no limits keeps everything until the system is already
/// short of memory. NSCache is thread-safe, so any thread may ask.
final class SRImageMemory: @unchecked Sendable {
    /// Drive's tiles and list marks: ~120 tiles of 360 px.
    static let drive = SRImageMemory(bytes: 48 * 1024 * 1024, count: 600)
    /// The viewer's screen-sized pictures: a few, not a gallery.
    static let driveViews = SRImageMemory(bytes: 48 * 1024 * 1024, count: 4)
    /// Remote link pictures (the family backlog) and chat photos.
    static let remote = SRImageMemory(bytes: 32 * 1024 * 1024, count: 200)

    private let cache = NSCache<NSString, UIImage>()

    init(bytes: Int, count: Int) {
        cache.totalCostLimit = bytes
        cache.countLimit = count
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func put(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString, cost: SRDownsample.cost(image))
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// At most N fetches at once; the rest wait their turn, and one whose task
/// is cancelled (its tile scrolled away) leaves the queue without running.
/// The counting is `SRFetchSlots`, tested on its own.
actor SRFetchGate {
    private var slots: SRFetchSlots
    private var parked: [Int: CheckedContinuation<Void, Error>] = [:]
    private var nextTicket = 0

    init(limit: Int) {
        slots = SRFetchSlots(limit: limit)
    }

    /// Wait for a slot. Throws `CancellationError` if the caller is cancelled
    /// while waiting; every return must be matched by one `leave()`.
    func enter() async throws {
        try Task.checkCancellation()
        let ticket = nextTicket
        nextTicket += 1
        if slots.request(ticket) { return }
        try await withTaskCancellationHandler {
            // Stored before this suspends, and the actor runs nothing else in
            // between, so the cancel below always finds it.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                parked[ticket] = continuation
            }
        } onCancel: {
            Task { await self.withdraw(ticket) }
        }
    }

    func leave() {
        if let next = slots.finish() { parked.removeValue(forKey: next)?.resume() }
    }

    private func withdraw(_ ticket: Int) {
        guard slots.withdraw(ticket) else { return }
        parked.removeValue(forKey: ticket)?.resume(throwing: CancellationError())
    }
}

/// A picture from the web (a saved link's own image), fetched through the
/// system's HTTP cache, decoded at its drawn size and kept in memory — the
/// cheap stand-in for `AsyncImage`, which decodes at full size every time a
/// view appears and keeps nothing. A failure is not remembered, so a link
/// whose picture has expired (TikTok signs them for days) shows the
/// placeholder and is asked again next time.
enum SRRemoteImages {
    private static let gate = SRFetchGate(limit: 4)

    static func memoryKey(_ url: URL, points: CGFloat) -> String {
        "\(url.absoluteString)|\(Int(points.rounded(.up)))"
    }

    static func cached(_ url: URL, points: CGFloat) -> UIImage? {
        SRImageMemory.remote.image(for: memoryKey(url, points: points))
    }

    static func load(_ url: URL, points: CGFloat, scale: CGFloat) async -> UIImage? {
        let key = memoryKey(url, points: points)
        if let hit = SRImageMemory.remote.image(for: key) { return hit }
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        do {
            try await gate.enter()
        } catch {
            return nil
        }
        let data: Data
        do {
            defer { Task { await gate.leave() } }
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let (body, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
                  body.count < 20_000_000 else { return nil }
            data = body
        } catch {
            return nil
        }
        let pixels = SRImageLogic.pixels(points: Double(points), scale: Double(scale))
        guard let image = await Task.detached(priority: .userInitiated, operation: {
            SRDownsample.image(data: data, maxPixels: pixels)
        }).value else { return nil }
        SRImageMemory.remote.put(image, for: key)
        return image
    }
}

/// `AsyncImage`, downsampled and remembered: `points` is the longest edge it
/// is drawn at. Shows `placeholder` until the picture arrives, and for good
/// if it never does.
struct SRRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL
    let points: CGFloat
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    init(url: URL, points: CGFloat, @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.points = points
        self.content = content
        self.placeholder = placeholder
        // Already decoded: drawn on the first frame, no flash of the placeholder.
        _image = State(initialValue: SRRemoteImages.cached(url, points: points))
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: SRRemoteImages.memoryKey(url, points: points)) {
            if let hit = SRRemoteImages.cached(url, points: points) {
                image = hit
                return
            }
            image = nil
            let loaded = await SRRemoteImages.load(url, points: points, scale: scale)
            if !Task.isCancelled { image = loaded }
        }
    }
}

/// Library photos for small squares, through one shared caching manager
/// rather than a request each through `PHImageManager.default()`; the
/// request is cancelled when the square goes (the stream's termination).
enum SRLibraryImages {
    static let manager = PHCachingImageManager()

    /// The system answers twice in opportunistic mode: a quick blurry one, then the real one.
    static func images(_ asset: PHAsset, pixels: CGSize, options: PHImageRequestOptions) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            let id = manager.requestImage(for: asset, targetSize: pixels, contentMode: .aspectFill, options: options) { picture, info in
                if let picture { continuation.yield(picture) }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded || info?[PHImageErrorKey] != nil || (info?[PHImageCancelledKey] as? Bool) == true {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in manager.cancelImageRequest(id) }
        }
    }

    /// The options a thumbnail square wants: fast, iCloud allowed, two answers.
    static func thumbnailOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        return options
    }
}

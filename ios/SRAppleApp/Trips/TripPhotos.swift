import SwiftUI
import CryptoKit

/// Places' photographs (v7), kept on the phone like the rest of the trip:
/// fetched once from Wikimedia's upload host when a bundle arrives, read
/// from disk after that, so a stop's picture is there in airplane mode too.
/// Caches, not Documents: the system may clear them, and they come back.
@MainActor
final class TripPhotos: ObservableObject {
    static let shared = TripPhotos()

    /// Bumped when a photo lands, so a view waiting on one redraws.
    @Published private(set) var landed = 0
    /// Decoded photos, bounded by their decoded bytes: a long trip names
    /// dozens of places, and a dictionary kept every one for the session.
    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 80
        return cache
    }()
    private var fetching: Set<String> = []
    /// The longest edge a place's photo is decoded at: a full-width card at
    /// 220 points is ~1,200 pixels on a 3x phone, and the rows' squares use
    /// the same picture.
    nonisolated static let maxPixels = 1200

    private let folder: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("trip-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    /// Only Wikimedia's own image hosts (thumbnails moved to `thumb.` in
    /// 2026): the server checks the same.
    nonisolated static func allowed(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https",
              let host = url.host, ["upload.wikimedia.org", "thumb.wikimedia.org"].contains(host) else { return nil }
        return url
    }

    private func file(_ url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(String(digest.prefix(40)) + ".img")
    }

    /// The photo, if it is decoded already. Memory only: this is asked from
    /// `body`, where reading and decoding a file would stall the frame —
    /// `load` brings one in from disk or the web.
    func image(_ photo: PlaceImage) -> UIImage? {
        guard let url = Self.allowed(photo.url) else { return nil }
        return memory.object(forKey: url.absoluteString as NSString)
    }

    /// Bring one in (a card on screen asking): from disk if it is on the
    /// phone, from the web if not — read, downsampled and decoded off the
    /// main thread either way.
    func load(_ photo: PlaceImage) {
        guard let url = Self.allowed(photo.url), image(photo) == nil, !fetching.contains(url.absoluteString) else { return }
        fetching.insert(url.absoluteString)
        let saved = file(url)
        Task {
            defer { fetching.remove(url.absoluteString) }
            let fromDisk = await Task.detached(priority: .userInitiated) {
                SRDownsample.image(url: saved, maxPixels: Self.maxPixels)
            }.value
            if let fromDisk {
                keep(fromDisk, for: url)
                return
            }
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("StrangeRamblingsApp/1.0 (+https://strangeramblings.com)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count < 4_000_000 else { return }
            let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let image = SRDownsample.image(data: data, maxPixels: Self.maxPixels) else { return nil }
                try? data.write(to: saved, options: .atomic)
                return image
            }.value
            if let decoded { keep(decoded, for: url) }
        }
    }

    private func keep(_ image: UIImage, for url: URL) {
        memory.setObject(image, forKey: url.absoluteString as NSString, cost: SRDownsample.cost(image))
        landed += 1
    }

    /// Every photo a bundle names, so the trip's pictures go offline with it —
    /// on Wi-Fi, as the map packs are; on mobile data a card fetches its own.
    func prefetch(_ bundle: TripBundle) {
        guard !SRDemo.isOn, TripNetwork.shared.online, TripNetwork.shared.unmetered else { return }
        // Only what is not on the phone yet: one already saved is decoded
        // when a card asks, not now.
        for photo in (bundle.images ?? [:]).values {
            guard let url = Self.allowed(photo.url), !FileManager.default.fileExists(atPath: file(url).path) else { continue }
            load(photo)
        }
    }
}

/// A place's photograph, with its credit — the condition of showing it.
/// Nothing at all when there is no photo; a quiet frame while one loads.
struct TripPhotoView: View {
    let photo: PlaceImage
    var height: CGFloat = 200
    var showsCredit = true
    @ObservedObject private var photos = TripPhotos.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Rectangle().fill(SR.inkMuted.opacity(0.12))
                if let image = photos.image(photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(SR.inkMuted)
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 2, style: .continuous))
            .accessibilityHidden(true)
            if showsCredit, let link = URL(string: photo.sourceUrl) {
                Link(destination: link) {
                    Text(photo.creditLine)
                        .font(SR.Text.mono(10))
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityLabel("Photo credit: \(photo.creditLine)")
            }
        }
        .onAppear { photos.load(photo) }
        .animation(.easeOut(duration: 0.25), value: photos.landed)
    }
}

/// A small square of a place's photograph, for rows and the map's peek.
struct TripPhotoThumb: View {
    let photo: PlaceImage
    var size: CGFloat = 56
    @ObservedObject private var photos = TripPhotos.shared

    var body: some View {
        ZStack {
            Rectangle().fill(SR.inkMuted.opacity(0.12))
            if let image = photos.image(photo) {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
        .onAppear { photos.load(photo) }
    }
}

extension TripBundle {
    /// A stop's photograph: its wish's, or (a chosen meal) its place's.
    func photo(for stop: PlannedStop) -> PlaceImage? {
        guard let images else { return nil }
        if let wishId = stop.wishId, let photo = images[wishId] { return photo }
        return nil
    }
}

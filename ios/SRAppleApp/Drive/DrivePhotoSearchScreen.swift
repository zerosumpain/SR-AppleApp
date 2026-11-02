import ImageIO
import QuickLook
import SwiftUI
import UIKit

/// Search the owner's photos from Drive: what is in them (smart search), the
/// words in them, who, where, when, photo or video — and see only the
/// pictures that match.
///
/// The site does the searching (SR-Main `GET api/native/drive/photos/search`,
/// relaying SR-Drive's Immich and Drive's own file index); this screen holds
/// the criteria, draws the matches and pages on as the grid is scrolled. The
/// owner's alone: Drive's photo lane answers nobody else, so `DriveScreen`
/// offers the way in only to the owner, as himself.
struct DrivePhotoSearchScreen: View {
    @StateObject private var model = DrivePhotoSearchModel()
    @State private var pickingPeople = false
    @State private var showingFilters = true
    @State private var preview: URL?
    @State private var fullScreen: PhotoHit?

    var body: some View {
        ScrollView {
            // Lazy, so the "more" spinner at the grid's end appears (and asks
            // for the next page) only when it is scrolled to.
            LazyVStack(alignment: .leading, spacing: 14) {
                if showingFilters { DrivePhotoFilters(model: model, pickingPeople: $pickingPeople) }
                DrivePhotoChips(model: model)
                DrivePhotoResults(model: model, open: open)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .srPaper()
        .accessibilityIdentifier("drive-photo-search")
        .navigationTitle("Search photos")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.criteria.text, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "What's in it? A dog on a beach…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { showingFilters.toggle() }
                } label: {
                    Image(systemName: showingFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(showingFilters ? "Hide filters" : "Show filters")
            }
        }
        // Typing settles before a search goes: a new criteria value cancels
        // the task still sleeping for the last one.
        .task(id: model.criteria) {
            try? await Task.sleep(nanoseconds: PhotoSearchLogic.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await model.reload()
        }
        .sheet(isPresented: $pickingPeople) { DrivePhotoPeoplePicker(model: model) }
        .fullScreenCover(item: $fullScreen) { DrivePhotoPreview(hit: $0) }
        .quickLookPreview($preview)
        .overlay(alignment: .bottom) {
            if let message = model.message {
                SRBanner(text: message, tone: SR.error).onTapGesture { model.message = nil }
            }
        }
    }

    /// Its Drive file in Drive's own viewer when it has one; otherwise the
    /// photo library's large preview.
    private func open(_ hit: PhotoHit) {
        SRHaptic.tap()
        guard hit.driveFileId != nil else {
            fullScreen = hit
            return
        }
        Task {
            if let url = await model.localCopy(of: hit) {
                preview = url
            } else if hit.assetId != nil {
                // The Drive file went (moved, deleted): the picture still opens.
                fullScreen = hit
            }
        }
    }
}

// MARK: - The model

@MainActor
final class DrivePhotoSearchModel: ObservableObject {
    @Published var criteria = PhotoSearchCriteria()
    @Published private(set) var results = PhotoSearchResults()
    @Published private(set) var loading = false
    @Published private(set) var opening: String?
    @Published var message: String?
    @Published private(set) var people: [PhotoPerson]?
    @Published private(set) var peopleReason: String?

    /// Bumped for every new search, so a slow answer to an old one is dropped.
    private var generation = 0

    /// A fresh search for what is asked now: from page one.
    func reload() async {
        generation += 1
        results = PhotoSearchResults()
        message = nil
        guard !criteria.isEmpty else { return }
        if let problem = criteria.rangeProblem {
            message = problem
            return
        }
        await fetch(page: 1, generation: generation)
    }

    /// The next page, when the grid's end comes into view.
    func loadMore() async {
        guard !loading, let next = results.nextPage, next > 1 else { return }
        await fetch(page: next, generation: generation)
    }

    private func fetch(page: Int, generation asked: Int) async {
        guard let path = criteria.path(page: page) else { return }
        loading = true
        defer { if asked == generation { loading = false } }
        do {
            let answer: PhotoSearchPage = try await SiteClient.shared.send(path, timeout: 40)
            guard asked == generation else { return }
            results.append(answer)
        } catch is CancellationError {
            return
        } catch {
            guard asked == generation, !Task.isCancelled else { return }
            if (error as? URLError)?.code == .cancelled { return }
            message = error.localizedDescription
        }
    }

    /// The faces, once per screen, for the picker.
    func loadPeople() async {
        guard people == nil else { return }
        do {
            let page: PhotoPeoplePage = try await SiteClient.shared.send("api/native/drive/photos/people?filter=all&limit=200", timeout: 30)
            people = page.people.sorted { a, b in
                // Named first, the most photographed first among them.
                if (a.name == nil) != (b.name == nil) { return a.name != nil }
                return (a.photos ?? 0) > (b.photos ?? 0)
            }
            peopleReason = page.connected ? nil : PhotoSearchLogic.notConnectedMessage(page.reason)
        } catch {
            peopleReason = error.localizedDescription
        }
    }

    /// The hit's Drive file on this phone, fetched once per version, for
    /// Quick Look — the same cache and path the Drive screens use. An Immich
    /// photo names only its file's id, so the file is read first.
    func localCopy(of hit: PhotoHit) async -> URL? {
        guard let id = hit.driveFileId else { return nil }
        opening = hit.key
        defer { opening = nil }
        do {
            let file: DriveFile
            if let known = hit.file {
                file = known.driveFile
            } else {
                file = try await DriveAPI.meta(DriveFileRef(space: .mine, id: id)).file
            }
            if let cached = DriveCache.url(for: file) { return cached }
            let data = try await SiteClient.shared.bytes(DriveLogic.filePath(file.id))
            return try DriveCache.store(data, for: file)
        } catch {
            if hit.assetId == nil { message = error.localizedDescription }
            return nil
        }
    }
}

extension PhotoHitFile {
    /// The same file as the Drive screens know it.
    var driveFile: DriveFile {
        DriveFile(id: id, name: name, path: path, mimeType: mimeType, sizeBytes: sizeBytes, createdAt: createdAt,
                  updatedAt: updatedAt, mine: mine, addedBy: addedBy, canDelete: canDelete)
    }
}

// MARK: - Criteria

/// Words in the image, place, people, dates and photo/video. The "what's in
/// it" words are the screen's search field.
private struct DrivePhotoFilters: View {
    @ObservedObject var model: DrivePhotoSearchModel
    @Binding var pickingPeople: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(icon: "text.viewfinder", prompt: "Words in the image", text: $model.criteria.ocr)
            field(icon: "mappin.and.ellipse", prompt: "Place — city, region or country", text: $model.criteria.place)
            Button {
                SRHaptic.tap()
                pickingPeople = true
            } label: {
                HStack {
                    Image(systemName: "person.2.crop.square.stack").foregroundStyle(SR.accentInk).frame(width: 22)
                    Text(model.criteria.people.isEmpty ? "People" : "People · \(model.criteria.people.count)")
                        .font(SR.Text.body(15))
                        .foregroundStyle(model.criteria.people.isEmpty ? SR.inkMuted : SR.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(SR.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("photo-search-people")
            Divider().overlay(SR.line)
            DrivePhotoDates(criteria: $model.criteria)
            Picker("Kind", selection: $model.criteria.kind) {
                Text("Both").tag(PhotoKind?.none)
                ForEach(PhotoKind.allCases) { Text($0.title).tag(PhotoKind?.some($0)) }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .srGlassCard()
    }

    private func field(icon: String, prompt: String, text: Binding<String>) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(SR.accentInk).frame(width: 22)
            TextField(prompt, text: text)
                .font(SR.Text.body(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(SR.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
    }
}

/// From and to, each switched on by itself: an open end is "since" or "until".
private struct DrivePhotoDates: View {
    @Binding var criteria: PhotoSearchCriteria

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("From", date: $criteria.from, fallback: { Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date() })
            row("To", date: $criteria.to, fallback: { Date() })
        }
    }

    private func row(_ title: String, date: Binding<Date?>, fallback: @escaping () -> Date) -> some View {
        HStack {
            Image(systemName: "calendar").foregroundStyle(SR.accentInk).frame(width: 22)
            Toggle(isOn: Binding(get: { date.wrappedValue != nil }, set: { date.wrappedValue = $0 ? fallback() : nil })) {
                Text(title).font(SR.Text.body(15)).foregroundStyle(date.wrappedValue == nil ? SR.inkMuted : SR.ink)
            }
            .tint(SR.accent)
            .fixedSize()
            Spacer()
            if let value = date.wrappedValue {
                DatePicker(title, selection: Binding(get: { value }, set: { date.wrappedValue = $0 }), in: ...Date(),
                           displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }
}

/// What is being asked, as chips: tap the cross to drop one filter.
private struct DrivePhotoChips: View {
    @ObservedObject var model: DrivePhotoSearchModel

    var body: some View {
        let chips = model.criteria.chips()
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        Button {
                            SRHaptic.select()
                            model.criteria = model.criteria.removing(chip.kind)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: chip.icon).font(.system(size: 12, weight: .semibold))
                                Text(chip.label).font(SR.Text.secondary(13)).lineLimit(1)
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(SR.accentInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(SR.accentInk.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(chip.label)")
                    }
                    if chips.count > 1 {
                        Button("Clear all") {
                            SRHaptic.select()
                            model.criteria = PhotoSearchCriteria()
                        }
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Results

private struct DrivePhotoResults: View {
    @ObservedObject var model: DrivePhotoSearchModel
    let open: (PhotoHit) -> Void

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 4)]

    var body: some View {
        let results = model.results
        // A Group, not a stack: each part is its own child of the screen's
        // LazyVStack, so the end-of-grid spinner is not "on screen" from the start.
        Group {
            if model.criteria.isEmpty {
                SREmpty(title: "Search your photos", icon: "photo.on.rectangle.angled",
                        message: "Say what's in the picture, the words in it, who is in it, where or when. Only the photos that match are shown.")
            } else if !results.connected && results.hits.isEmpty && results.page > 0 {
                SREmpty(title: "Photos aren't connected", icon: "exclamationmark.triangle",
                        message: PhotoSearchLogic.notConnectedMessage(results.reason))
            } else if results.loadedNothing && !model.loading {
                SREmpty(title: "No photos match", icon: "magnifyingglass", message: PhotoSearchLogic.emptyMessage(model.criteria))
            } else {
                summary(results)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(results.hits) { hit in
                        DrivePhotoTile(hit: hit, opening: model.opening == hit.key) { open(hit) }
                    }
                }
                if results.nextPage != nil && results.page > 0 {
                    // The grid's end: in view, the next page is asked for.
                    ProgressView()
                        .tint(SR.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .task(id: results.page) { await model.loadMore() }
                } else if model.loading {
                    ProgressView().tint(SR.accent).frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
        }
    }

    @ViewBuilder
    private func summary(_ results: PhotoSearchResults) -> some View {
        if !results.connected {
            Text(PhotoSearchLogic.notConnectedMessage(results.reason))
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        } else if let total = results.total, !results.hits.isEmpty {
            SRSectionLabel(text: total == 1 ? "1 match" : "\(total) matches")
        } else if !results.hits.isEmpty {
            SRSectionLabel(text: "Best matches first")
        }
    }
}

private struct DrivePhotoTile: View {
    let hit: PhotoHit
    let opening: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { DrivePhotoThumb(path: hit.thumbPath, pixels: 320, icon: hit.isVideo ? "film" : "photo") }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if hit.isVideo {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                            if let seconds = hit.durationSec { Text(PhotoSearchLogic.duration(seconds)).font(SR.Text.mono(12)) }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(5)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if hit.source == .drive {
                        // Found by Drive's own reading of the image, not the photo library.
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(5)
                    }
                }
                .overlay { if opening { ProgressView().tint(.white) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var label: String {
        let what = hit.isVideo ? "Video" : "Photo"
        let caption = hit.caption
        return caption.isEmpty ? what : "\(what), \(caption)"
    }
}

/// The photo library's large preview, for a photo with no Drive file.
private struct DrivePhotoPreview: View {
    let hit: PhotoHit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            DrivePhotoThumb(path: hit.previewPath, pixels: 2048, icon: hit.isVideo ? "film" : "photo", fill: false)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                .padding(16)
                Spacer()
                VStack(spacing: 4) {
                    if !hit.caption.isEmpty {
                        Text(hit.caption).font(SR.Text.secondary(14)).foregroundStyle(.white)
                    }
                    if hit.isVideo {
                        Text("A still from the video. Videos without a Drive file play on the site.")
                            .font(SR.Text.secondary(12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .multilineTextAlignment(.center)
                .padding(16)
            }
        }
        .statusBarHidden()
    }
}

// MARK: - People

private struct DrivePhotoPeoplePicker: View {
    @ObservedObject var model: DrivePhotoSearchModel
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 12)]

    private var shown: [PhotoPerson] {
        let all = model.people ?? []
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { ($0.name ?? "").lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let reason = model.peopleReason, (model.people ?? []).isEmpty {
                    SREmpty(title: "No faces to pick", icon: "person.crop.circle.badge.questionmark", message: reason)
                } else if model.people == nil {
                    ProgressView().tint(SR.accent).frame(maxWidth: .infinity).padding(.vertical, 60)
                } else if shown.isEmpty {
                    SREmpty(title: "Nobody by that name", icon: "person.crop.circle",
                            message: "Faces are named on the site, in Drive's People tab.")
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(shown) { person in face(person) }
                    }
                    .padding(16)
                }
            }
            .srPaper()
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter, prompt: "Find a name")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await model.loadPeople() }
        }
    }

    private func face(_ person: PhotoPerson) -> some View {
        let chosen = model.criteria.people.contains { $0.id == person.id }
        return Button {
            SRHaptic.select()
            if chosen {
                model.criteria = model.criteria.removing(.person(person.id))
            } else {
                model.criteria.add(person.pick)
            }
        } label: {
            VStack(spacing: 6) {
                DrivePhotoThumb(path: person.facePath, pixels: 200, icon: "person.fill")
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(chosen ? SR.accent : Color.clear, lineWidth: 3))
                    .overlay(alignment: .bottomTrailing) {
                        if chosen {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(SR.accent)
                                .background(Circle().fill(SR.paper))
                        }
                    }
                Text(person.name ?? "Unnamed")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(person.name == nil ? SR.inkMuted : SR.ink)
                    .lineLimit(1)
                if let photos = person.photos {
                    Text("\(photos)").font(SR.Text.mono(12)).foregroundStyle(SR.inkMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!chosen && model.criteria.people.count >= PhotoSearchCriteria.maxPeople)
        .accessibilityLabel(chosen ? "\(person.name ?? "Unnamed person"), chosen" : (person.name ?? "Unnamed person"))
    }
}

// MARK: - Thumbnails

/// One image from the site's native photo lane, downsampled off the main
/// actor. Its task is the view's: scrolled away, the fetch is cancelled.
private struct DrivePhotoThumb: View {
    let path: String
    let pixels: Int
    let icon: String
    var fill = true
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                if fill {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else {
                SR.accentInk.opacity(0.08)
                Image(systemName: failed ? "exclamationmark.triangle" : icon)
                    .foregroundStyle(SR.accentInk.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: path) {
            image = DrivePhotoThumbs.shared.cached(path, pixels: pixels)
            guard image == nil else { return }
            let loaded = await DrivePhotoThumbs.shared.load(path, pixels: pixels)
            guard !Task.isCancelled else { return }
            image = loaded
            failed = loaded == nil
        }
    }
}

/// The search's own thumbnail loader: a bounded memory cache, at most four
/// fetches at once, ImageIO downsampling on a background thread. Kept to this
/// screen on purpose — Drive's shared loader is being reworked elsewhere, and
/// the two are to be made one later.
@MainActor
final class DrivePhotoThumbs {
    static let shared = DrivePhotoThumbs()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        c.totalCostLimit = 80 * 1024 * 1024
        return c
    }()
    private let gate = DrivePhotoGate(4)
    /// A Drive file that is not in the photo library comes whole; past this it is not drawn.
    private let largestFile = 15 * 1024 * 1024

    private func key(_ path: String, _ pixels: Int) -> NSString { "\(pixels)|\(path)" as NSString }

    func cached(_ path: String, pixels: Int) -> UIImage? { cache.object(forKey: key(path, pixels)) }

    func load(_ path: String, pixels: Int) async -> UIImage? {
        if let hit = cached(path, pixels: pixels) { return hit }
        guard PhotoSearchLogic.isNativePath(path) else { return nil }
        await gate.acquire()
        defer { Task { await gate.release() } }
        guard !Task.isCancelled else { return nil }
        guard let data = try? await SiteClient.shared.bytes(path), data.count <= largestFile, !Task.isCancelled else { return nil }
        let image = await Task.detached(priority: .utility) { Self.downsample(data, maxPixels: pixels) }.value
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            cache.setObject(image, forKey: key(path, pixels), cost: cost)
        }
        return image
    }

    /// Decoded straight to the size drawn, never the full picture in memory.
    nonisolated static func downsample(_ data: Data, maxPixels: Int) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumb = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumb) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// At most `limit` at once; the rest wait their turn in order.
actor DrivePhotoGate {
    private var available: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ limit: Int) { available = limit }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            available += 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}

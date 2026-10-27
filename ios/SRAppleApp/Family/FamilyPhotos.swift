import PhotosUI
import SwiftUI
import UIKit

/// Family photos: a person's own picture in place of their initials, wherever
/// their circle is drawn — msg family, the map, the Orbit, Coming up and the
/// step board (John, 2026-10-27: "the ability of family to replace their
/// icon with a photo of them").
///
/// The site keeps one small square JPEG per person (`/api/native/family/
/// photo[s]`), known by the person's family id and, where the site can say,
/// their household subject — the map and the Orbit know people by subject,
/// msg family and the steps board by id. This phone keeps each picture on
/// disk under its version, so a circle draws at once on launch and a picture
/// is fetched again only when its owner changes it.
@MainActor
final class FamilyPhotos: ObservableObject {
    static let shared = FamilyPhotos()

    struct Entry: Codable, Equatable {
        let id: String
        var subject: String?
        let version: String
    }

    /// By family id.
    @Published private(set) var images: [String: UIImage] = [:]
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var busy = false
    @Published var message: String?
    /// This phone's own person's id, once the site has said it (an upload's
    /// answer); kept so "Your photo" knows which circle is its own.
    @Published private(set) var mine: String? = UserDefaults.standard.string(forKey: FamilyPhotos.mineKey)
    private var lastLoad: Date?

    private static let mineKey = "family-photo-mine"
    /// The largest side sent: a circle is never drawn bigger than ~80 pt.
    nonisolated static let side: CGFloat = 512
    /// Under the site's 300 kB.
    nonisolated static let maxBytes = 280_000

    private init() {
        let saved = Self.readIndex()
        entries = saved
        images = Dictionary(uniqueKeysWithValues: saved.compactMap { e in Self.cached(e).map { (e.id, $0) } })
    }

    /// A person's picture, by id or by subject; nil draws their initials.
    func image(id: String?, subject: String?) -> UIImage? {
        if let id, let image = images[id] { return image }
        guard let subject, let entry = entries.first(where: { $0.subject == subject }) else { return nil }
        return images[entry.id]
    }

    /// This phone's own person's picture. Whose id that is: the site's
    /// answer to an upload from here, else the steps board's "me", else
    /// msg family's own lines.
    var myImage: UIImage? {
        let id = mine
            ?? FamilyStepsStore.shared.board?.people.first(where: \.me)?.id
            ?? FamilyMessagesStore.shared.thread.first(where: \.mine)?.fromId
        return id.flatMap { images[$0] }
    }

    /// The family's pictures. At most every five minutes unless `force`.
    func load(force: Bool = false) async {
        guard SiteClient.shared.isPaired, AccessStore.shared.familyBoards, !SRDemo.isOn else { return }
        if !force, let lastLoad, Date().timeIntervalSince(lastLoad) < 300 { return }
        lastLoad = Date()
        struct Reply: Decodable { let photos: [Entry] }
        guard let reply: Reply = try? await SiteClient.shared.send("api/native/family/photos") else { return }
        var next: [String: UIImage] = [:]
        for entry in reply.photos {
            if let image = images[entry.id], entries.first(where: { $0.id == entry.id })?.version == entry.version {
                next[entry.id] = image
            } else if let image = Self.cached(entry) {
                next[entry.id] = image
            } else if let data = try? await SiteClient.shared.bytes("api/native/family/photos/\(entry.id)?v=\(entry.version)"),
                      let image = UIImage(data: data) {
                Self.store(data, for: entry)
                next[entry.id] = image
            }
        }
        entries = reply.photos
        images = next
        Self.writeIndex(reply.photos)
        Self.prune(keeping: reply.photos)
    }

    /// Make `picked` this person's picture: squared, shrunk, sent.
    @discardableResult
    func upload(_ picked: UIImage) async -> Bool {
        guard !busy else { return false }
        guard let jpeg = Self.squareJPEG(picked) else {
            message = "That picture could not be read."
            return false
        }
        busy = true
        message = nil
        defer { busy = false }
        struct Reply: Decodable { let id: String; let version: String }
        do {
            let body = try JSONEncoder().encode(["jpeg": jpeg.base64EncodedString()])
            let reply: Reply = try await SiteClient.shared.send("api/native/family/photo", method: "PUT", body: body, asSelf: true)
            let entry = Entry(id: reply.id, subject: entries.first { $0.id == reply.id }?.subject, version: reply.version)
            Self.store(jpeg, for: entry)
            entries = entries.filter { $0.id != reply.id } + [entry]
            images[reply.id] = UIImage(data: jpeg)
            Self.writeIndex(entries)
            mine = reply.id
            UserDefaults.standard.set(reply.id, forKey: Self.mineKey)
            SRHaptic.ok()
            return true
        } catch {
            message = "Your photo was not saved: \(error.localizedDescription)"
            SRHaptic.bad()
            return false
        }
    }

    /// Back to initials.
    func remove() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        struct Reply: Decodable { let ok: Bool? }
        do {
            let _: Reply = try await SiteClient.shared.send("api/native/family/photo", method: "DELETE", asSelf: true)
            if let id = mine ?? FamilyStepsStore.shared.board?.people.first(where: \.me)?.id {
                images[id] = nil
                entries.removeAll { $0.id == id }
                Self.writeIndex(entries)
                Self.prune(keeping: entries)
            }
        } catch {
            message = "Your photo was not removed: \(error.localizedDescription)"
        }
    }

    // MARK: The picture

    /// The middle square, at most `side` across, as a JPEG under `maxBytes`.
    nonisolated static func squareJPEG(_ image: UIImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let crop = min(size.width, size.height)
        let side = min(Self.side, crop)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scale = side / crop
        let squared = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: -(size.width - crop) / 2 * scale, y: -(size.height - crop) / 2 * scale,
                                  width: size.width * scale, height: size.height * scale))
        }
        for quality in [0.8, 0.65, 0.5, 0.35] {
            if let data = squared.jpegData(compressionQuality: quality), data.count <= maxBytes { return data }
        }
        return nil
    }

    // MARK: The disk

    private static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("family-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func file(_ entry: Entry) -> URL {
        folder.appendingPathComponent("\(entry.id)-\(entry.version).jpg")
    }

    private static func cached(_ entry: Entry) -> UIImage? {
        UIImage(contentsOfFile: file(entry).path)
    }

    private static func store(_ data: Data, for entry: Entry) {
        try? data.write(to: file(entry), options: .atomic)
    }

    private static func prune(keeping entries: [Entry]) {
        let keep = Set(entries.map { file($0).lastPathComponent } + ["index.json"])
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where !keep.contains(name) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static func readIndex() -> [Entry] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("index.json")),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    private static func writeIndex(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: folder.appendingPathComponent("index.json"), options: .atomic)
    }
}

/// A picture cut to a circle, the size of the initials it stands in for.
struct FamilyPhotoCircle: View {
    let image: UIImage
    let size: CGFloat

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

/// Settings → Your photo: choose one, take one, or go back to initials.
struct FamilyPhotoScreen: View {
    @ObservedObject private var photos = FamilyPhotos.shared
    @State private var pick: PhotosPickerItem?
    @State private var camera = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    Group {
                        if let image = photos.myImage {
                            FamilyPhotoCircle(image: image, size: 132)
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 120))
                                .foregroundStyle(SR.inkGhost)
                        }
                    }
                    .overlay {
                        if photos.busy { ProgressView().tint(SR.accent) }
                    }
                    .accessibilityIdentifier("family-photo-preview")
                    Text("Your family sees this in place of your initials — on the map, in msg family and on the step board.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .srGlassRow()
            }
            Section {
                PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
                    SRRow(title: "Choose a photo", subtitle: "From your library", icon: "photo.on.rectangle")
                }
                .srGlassRow()
                .accessibilityIdentifier("family-photo-choose")
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        camera = true
                    } label: {
                        SRRow(title: "Take a photo", subtitle: "With the front camera", icon: "camera")
                    }
                    .buttonStyle(.plain)
                    .srGlassRow()
                    .accessibilityIdentifier("family-photo-camera")
                }
                if photos.myImage != nil {
                    Button(role: .destructive) {
                        Task { await photos.remove() }
                    } label: {
                        SRRow(title: "Use my initials", subtitle: "Removes your photo for everyone", icon: "textformat")
                    }
                    .buttonStyle(.plain)
                    .srGlassRow()
                    .accessibilityIdentifier("family-photo-remove")
                }
            } footer: {
                if let message = photos.message {
                    Text(message).foregroundStyle(SR.error)
                }
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.quiet)
        .navigationTitle("Your photo")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(photos.busy)
        .task { await photos.load() }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await photos.upload(image)
                } else {
                    photos.message = "That picture could not be read."
                }
                pick = nil
            }
        }
        .fullScreenCover(isPresented: $camera) {
            FamilyCamera { image in
                camera = false
                if let image { Task { await photos.upload(image) } }
            }
            .ignoresSafeArea()
        }
    }
}

/// The system camera, front-facing, for a picture of yourself.
struct FamilyCamera: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done((info[.editedImage] ?? info[.originalImage]) as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}

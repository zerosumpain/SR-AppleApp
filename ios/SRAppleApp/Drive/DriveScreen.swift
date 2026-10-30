import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Drive: this person's own files and the family's shared folder.
///
/// The top of Drive has a My files | Shared switch; a folder is pushed as its
/// own screen, so Back goes up a level. + adds photos, a photo taken now,
/// files from the Files app, or a new folder. Tapping a file opens it in Quick
/// Look (which also shares and saves it). Delete is offered only where the
/// site said this person may: everything in My files, and in Shared only what
/// they added themselves.
struct DriveScreen: View {
    let ref: DriveRef
    @StateObject private var model: DriveFolderModel
    @ObservedObject private var access = AccessStore.shared
    @ObservedObject private var thumbs = DriveThumbnails.shared
    @EnvironmentObject private var router: Router
    @State private var space: DriveSpace
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var choosingPhotos = false
    @State private var choosingFiles = false
    @State private var takingPhoto = false
    @State private var naming = false
    @State private var newFolder = ""
    @State private var preview: URL?
    @State private var confirmFile: DriveFile?
    @State private var confirmFolder: DriveFolder?

    init(ref: DriveRef) {
        self.ref = ref
        _model = StateObject(wrappedValue: DriveFolderModel(ref: ref))
        _space = State(initialValue: ref.space)
    }

    /// The top of Drive, where the switch between the two spaces lives.
    private var isTop: Bool { ref.folder.isEmpty }
    /// "View as" is look-only: the site refuses writes, so none are offered.
    private var canWrite: Bool { access.viewingAs == nil }

    var body: some View {
        List {
            if isTop { spaceSwitch }
            content
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .srPaper()
        .accessibilityIdentifier("drive-screen")
        .navigationTitle(isTop ? "Drive" : ref.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .srRefreshable { await model.load() }
        .task { await model.load() }
        .onChange(of: space) { _, next in
            // The other space is a sibling at the top, not a push: the same
            // screen shows it, so Back still leaves Drive in one tap.
            guard next != model.ref.space else { return }
            SRHaptic.select()
            Task { await model.show(DriveRef(space: next)) }
        }
        .overlay(alignment: .bottom) { banner }
        .modifier(DrivePickers(model: model, photoItems: $photoItems, choosingPhotos: $choosingPhotos,
                               choosingFiles: $choosingFiles, takingPhoto: $takingPhoto))
        .quickLookPreview($preview)
        .alert("New folder", isPresented: $naming) {
            TextField("Name", text: $newFolder)
            Button("Make") {
                let name = newFolder
                newFolder = ""
                Task { await model.makeFolder(name) }
            }
            Button("Cancel", role: .cancel) { newFolder = "" }
        }
        .confirmationDialog("Delete this file?", isPresented: fileConfirming, titleVisibility: .visible, presenting: confirmFile) { file in
            Button("Delete \(file.name)", role: .destructive) { Task { await model.delete(file) } }
        } message: { _ in
            Text(model.ref.space == .shared ? "It goes for everyone in the family." : "It can't be brought back.")
        }
        .confirmationDialog("Delete this folder?", isPresented: folderConfirming, titleVisibility: .visible, presenting: confirmFolder) { folder in
            Button("Delete \(folder.name) and everything in it", role: .destructive) { Task { await model.delete(folder) } }
        }
    }

    private var fileConfirming: Binding<Bool> {
        Binding(get: { confirmFile != nil }, set: { if !$0 { confirmFile = nil } })
    }

    private var folderConfirming: Binding<Bool> {
        Binding(get: { confirmFolder != nil }, set: { if !$0 { confirmFolder = nil } })
    }

    // MARK: - Pieces

    private var spaceSwitch: some View {
        Section {
            Picker("Space", selection: $space) {
                ForEach(DriveSpace.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("drive-space")
            HStack(spacing: 6) {
                Image(systemName: space.icon).accessibilityHidden(true)
                Text(space.promise)
            }
            .font(SR.Text.secondary(13))
            .foregroundStyle(SR.inkMuted)
            .padding(.horizontal, 4)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    @ViewBuilder
    private var content: some View {
        if let listing = model.listing {
            listingSections(listing)
        } else if model.loaded {
            Section {
                SREmpty(title: "Drive didn't open", icon: "externaldrive.badge.exclamationmark",
                        message: model.message ?? "Pull down to try again.")
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                ProgressView().tint(SR.accent).frame(maxWidth: .infinity).padding(.vertical, 40)
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func listingSections(_ listing: DriveListing) -> some View {
        if listing.folders.isEmpty && listing.files.isEmpty {
            Section {
                SREmpty(title: isTop ? "Nothing here yet" : "This folder is empty", icon: "tray",
                        message: canWrite ? "Add photos or files with +." : nil)
            }
            .listRowBackground(Color.clear)
        }
        if !listing.folders.isEmpty {
            Section {
                ForEach(listing.folders) { folder in folderRow(folder) }
            } header: {
                SRSectionLabel(text: "Folders", trailing: "\(listing.folders.count)")
            }
        }
        if !listing.files.isEmpty {
            Section {
                ForEach(listing.files) { file in fileRow(file) }
            } header: {
                SRSectionLabel(text: "Files", trailing: "\(listing.files.count)")
            } footer: {
                if isTop { usageFooter(listing.usage) }
            }
        } else if isTop {
            Section { EmptyView() } footer: { usageFooter(listing.usage) }
        }
    }

    private func usageFooter(_ usage: DriveUsage) -> some View {
        Text(DriveLogic.usage(usage))
            .font(SR.Text.mono())
            .foregroundStyle(SR.inkMuted)
            .accessibilityIdentifier("drive-usage")
    }

    private func folderRow(_ folder: DriveFolder) -> some View {
        Button {
            SRHaptic.tap()
            router.pushFromHub(DriveRef(space: model.ref.space, folder: folder.path))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(SR.accent)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name).font(SR.Text.bodyMedium()).foregroundStyle(SR.ink)
                    Text(folder.items == 1 ? "1 file" : "\(folder.items) files")
                        .font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").foregroundStyle(SR.inkGhost).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .srGlassRow()
        .accessibilityIdentifier("drive-folder-\(folder.name)")
        .swipeActions(edge: .trailing) {
            if canWrite {
                Button(role: .destructive) { confirmFolder = folder } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func fileRow(_ file: DriveFile) -> some View {
        Button {
            SRHaptic.tap()
            Task { if let url = await model.localCopy(of: file) { preview = url } }
        } label: {
            DriveFileRow(file: file, thumbnail: thumbs.image(for: file), opening: model.opening == file.id)
        }
        .buttonStyle(.plain)
        .srGlassRow()
        .accessibilityIdentifier("drive-file-\(file.name)")
        .task(id: file.id) { await thumbs.load(file) }
        .swipeActions(edge: .trailing) {
            if canWrite && file.canDelete {
                Button(role: .destructive) { confirmFile = file } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .contextMenu {
            if canWrite && file.canDelete {
                Button(role: .destructive) { confirmFile = file } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) { SRBarMark() }
        ToolbarItem(placement: .topBarTrailing) {
            if canWrite {
                Menu {
                    Button { choosingPhotos = true } label: { Label("Photos & Videos", systemImage: "photo.on.rectangle") }
                    if CameraPicker.isAvailable {
                        Button { takingPhoto = true } label: { Label("Take Photo", systemImage: "camera") }
                    }
                    Button { choosingFiles = true } label: { Label("Choose Files", systemImage: "doc") }
                    Button { naming = true } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(model.progress != nil || model.listing == nil)
                .accessibilityLabel("Add to Drive")
                .accessibilityIdentifier("drive-add")
            }
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let progress = model.progress {
            SRBanner(text: progress, tone: SR.accentDeep)
        } else if let message = model.message, model.listing != nil {
            SRBanner(text: message, tone: SR.error)
                .onTapGesture { model.message = nil }
        }
    }
}

/// One file: a thumbnail for a photo, otherwise its type's mark; its name,
/// size and — in the shared folder — who added it.
struct DriveFileRow: View {
    let file: DriveFile
    let thumbnail: UIImage?
    let opening: Bool

    var body: some View {
        HStack(spacing: 12) {
            mark
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(SR.Text.bodyMedium())
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                Text(detail)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if opening { ProgressView().tint(SR.accent) }
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        [DriveLogic.size(file.sizeBytes), file.addedBy.map { "added by \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var mark: some View {
        if let thumbnail {
            Image(uiImage: thumbnail).resizable().scaledToFill()
        } else {
            Image(systemName: DriveLogic.icon(mime: file.mimeType, name: file.name))
                .foregroundStyle(SR.accentInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SR.accentInk.opacity(0.1))
        }
    }
}

/// The three pickers +'s menu opens. Split out so neither the screen's body
/// nor this is one expression big enough to stall the type checker.
private struct DrivePickers: ViewModifier {
    @ObservedObject var model: DriveFolderModel
    @Binding var photoItems: [PhotosPickerItem]
    @Binding var choosingPhotos: Bool
    @Binding var choosingFiles: Bool
    @Binding var takingPhoto: Bool

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $choosingPhotos, selection: $photoItems, maxSelectionCount: 20,
                          matching: .any(of: [.images, .videos]))
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                Task { await add(items) }
            }
            .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task { await model.addFiles(urls) }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { image in Task { await model.addPhotos([image]) } }
                    .ignoresSafeArea()
            }
    }

    /// Photos are re-encoded; a video goes as it is, if it fits.
    @MainActor private func add(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            if isVideo {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let ext = item.supportedContentTypes.contains { $0.conforms(to: .mpeg4Movie) } ? "mp4" : "mov"
                    await model.addVideo(data, ext: ext)
                } else {
                    model.message = "A video could not be read."
                }
            } else if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            } else {
                model.message = "A photo could not be read."
            }
        }
        if !images.isEmpty { await model.addPhotos(images) }
    }
}

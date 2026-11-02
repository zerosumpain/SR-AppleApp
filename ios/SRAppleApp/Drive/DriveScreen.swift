import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Drive: this person's own files and the family's shared folder.
///
/// The top of Drive has a My files | Shared switch; a folder is pushed as its
/// own screen, so Back goes up a level. + adds photos and videos (sent in the
/// background, originals and all), a photo taken now, files from the Files
/// app, a new folder, or moves photos off the phone. Tapping a photo opens it
/// full screen from the site's preview (`DrivePhotoViewer`), anything else in
/// Quick Look; pressing and holding one offers Share, Save to Files, Save
/// to Photos, Rename, Move, Info and Delete — and, for the owner in his own
/// files, jkai's Analyse, Extract entities and Ask. Delete is offered only
/// where the site said this person may: everything in My files, and in
/// Shared only what they added themselves.
///
/// Search finds names in this folder at once, then across the whole space
/// from the site — and, for the owner, what his files say.
struct DriveScreen: View {
    let ref: DriveRef
    @StateObject private var model: DriveFolderModel
    @ObservedObject private var access = AccessStore.shared
    @ObservedObject private var uploads = DriveUploadQueue.shared
    @EnvironmentObject private var router: Router
    @AppStorage("drive.sort") private var sortRaw = DriveSort.name.rawValue
    @AppStorage("drive.grid") private var grid = false
    @AppStorage(DrivePhotoImport.keepOriginalsKey) private var keepOriginals = true
    @State private var space: DriveSpace
    @State private var query = ""
    @State private var remote: DriveSearchResults?
    @State private var searching = false
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var choosingPhotos = false
    @State private var choosingFiles = false
    @State private var takingPhoto = false
    @State private var movingFromPhone = false
    @State private var syncingPhotos = false
    @State private var naming = false
    @State private var newFolder = ""
    @State private var renaming: DriveFile?
    @State private var newName = ""
    @State private var moving: [DriveFile] = []
    @State private var preview: URL?
    @State private var sharing: DriveLocalFile?
    @State private var exportFile: URL?
    @State private var exporting = false
    @State private var confirmFiles: [DriveFile] = []
    @State private var confirmFolder: DriveFolder?
    @State private var searchingPhotos = false
    /// The photo open full screen (`DrivePhotoViewer`).
    @State private var viewing: DriveFile?
    /// The grid's row width, measured by its rows, for how many tiles fit.
    @State private var gridWidth: CGFloat = 0

    init(ref: DriveRef) {
        self.ref = ref
        _model = StateObject(wrappedValue: DriveFolderModel(ref: ref))
        _space = State(initialValue: ref.space)
    }

    /// The top of Drive, where the switch between the two spaces lives.
    private var isTop: Bool { ref.folder.isEmpty }
    /// "View as" is look-only: the site refuses writes, so none are offered.
    private var canWrite: Bool { access.viewingAs == nil }
    /// jkai on files: the owner, as himself, in his own files.
    private var jkai: Bool { access.current.owner && access.viewingAs == nil && model.ref.space == .mine }
    /// Photo search: the owner's photo library, so the owner as himself only.
    private var photoSearch: Bool { access.current.owner && access.viewingAs == nil }
    private var sort: DriveSort { DriveSort(rawValue: sortRaw) ?? .name }
    private var selecting: Bool { editMode.isEditing }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List(selection: $selection) {
            if isTop && trimmedQuery.isEmpty && !selecting { spaceSwitch }
            if trimmedQuery.isEmpty {
                content
            } else {
                searchSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .srPaper()
        .environment(\.editMode, $editMode)
        .accessibilityIdentifier("drive-screen")
        .navigationTitle(isTop ? "Drive" : ref.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: model.ref.space == .mine ? "Search My files" : "Search Shared")
        .toolbar { toolbar }
        .srRefreshable { await model.load() }
        .task { await model.load() }
        .task(id: "\(model.ref.space.rawValue)|\(trimmedQuery)") { await searchSite() }
        .onChange(of: space) { _, next in
            // The other space is a sibling at the top, not a push: the same
            // screen shows it, so Back still leaves Drive in one tap.
            guard next != model.ref.space else { return }
            SRHaptic.select()
            selection = []
            Task { await model.show(DriveRef(space: next)) }
        }
        .onChange(of: uploads.landed) { _, landing in
            if landing.ref == model.ref { Task { await model.load() } }
        }
        .dropDestination(for: URL.self) { urls, _ in
            drop(urls, into: model.ref.folder)
        }
        .overlay(alignment: .bottom) { banner }
        .modifier(DrivePickers(model: model, photoItems: $photoItems, choosingPhotos: $choosingPhotos,
                               choosingFiles: $choosingFiles, takingPhoto: $takingPhoto, keepOriginals: keepOriginals))
        .modifier(DriveDialogs(model: model, naming: $naming, newFolder: $newFolder, renaming: $renaming,
                               newName: $newName, confirmFiles: $confirmFiles, confirmFolder: $confirmFolder,
                               afterDelete: { selection = [] }))
        .quickLookPreview($preview)
        .sheet(item: $sharing) { DriveActivitySheet(url: $0.url) }
        .sheet(isPresented: movingSheet) { movePicker }
        .sheet(isPresented: $movingFromPhone) {
            DriveMoveSheet(folder: model, keepOriginals: keepOriginals)
        }
        .sheet(isPresented: $syncingPhotos) { DriveSyncSheet() }
        .navigationDestination(isPresented: $searchingPhotos) { DrivePhotoSearchScreen() }
        .modifier(DriveViewerCover(viewing: $viewing, original: { await model.localCopy(of: $0) }, quickLook: quickLook))
        .fileMover(isPresented: $exporting, file: exportFile) { result in
            if case .failure(let error) = result { model.message = error.localizedDescription }
            exportFile = nil
        }
    }

    /// Move…: a folder of this space, walked one level at a time.
    private var movePicker: some View {
        let files = moving
        return DriveFolderPicker(
            space: model.ref.space,
            title: files.count == 1 ? "Move \(files[0].name)" : "Move \(files.count) files",
            confirm: "Move here",
            start: model.ref.folder,
            load: { space, folder in await DriveAPI.listing(space: space, folder: folder) },
            chosen: { target in
                selection = []
                editMode = .inactive
                Task { await model.move(files, to: target) }
            }
        )
    }

    private var movingSheet: Binding<Bool> {
        Binding(get: { !moving.isEmpty }, set: { if !$0 { moving = [] } })
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
                        message: canWrite ? "Add photos or files with +, or drop them here." : nil)
            }
            .listRowBackground(Color.clear)
        }
        if !listing.folders.isEmpty {
            Section {
                ForEach(DriveLogic.sorted(listing.folders)) { folder in folderRow(folder) }
            } header: {
                SRSectionLabel(text: "Folders", trailing: "\(listing.folders.count)")
            }
        }
        if !listing.files.isEmpty {
            let files = DriveLogic.sorted(listing.files, by: sort)
            Section {
                if grid && !selecting {
                    gridRows(files)
                } else {
                    ForEach(files) { file in fileRow(file) }
                }
            } header: {
                SRSectionLabel(text: "Files", trailing: "\(listing.files.count)")
            } footer: {
                if isTop { usageFooter(listing.usage) }
            }
        } else if isTop {
            Section { EmptyView() } footer: { usageFooter(listing.usage) }
        }
    }

    /// The grid as List rows of tiles, not one row holding every tile: a row
    /// is made (and its tiles' pictures asked for) only as it scrolls into
    /// view, and its loads are cancelled when it scrolls away.
    @ViewBuilder
    private func gridRows(_ files: [DriveFile]) -> some View {
        let columns = DriveGridLayout.columns(width: Double(gridWidth))
        let side = CGFloat(DriveGridLayout.tileSide(width: Double(gridWidth), columns: columns))
        ForEach(DriveGridLayout.rows(count: files.count, columns: columns), id: \.lowerBound) { range in
            DriveGridRow(files: Array(files[range]), columns: columns, side: side, opening: model.opening,
                         width: $gridWidth) { file in
                open(file)
            } menu: { file in
                fileMenu(file)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
            .listRowSeparator(.hidden)
        }
    }

    /// Names here at once; then the site's answer for the whole space.
    @ViewBuilder
    private var searchSections: some View {
        let listing = model.listing
        let folders = (listing?.folders ?? []).filter { DriveLogic.matches($0.name, query: trimmedQuery) }
        let files = DriveLogic.sorted((listing?.files ?? []).filter { DriveLogic.matches($0.name, query: trimmedQuery) }, by: sort)
        if !folders.isEmpty || !files.isEmpty {
            Section {
                ForEach(DriveLogic.sorted(folders)) { folder in folderRow(folder) }
                ForEach(files) { file in fileRow(file) }
            } header: {
                SRSectionLabel(text: isTop ? "Here" : "In \(ref.title)")
            }
        }
        let shown = Set(files.map(\.id))
        let elsewhere = (remote?.files ?? []).filter { !shown.contains($0.id) }
        if !elsewhere.isEmpty {
            Section {
                ForEach(elsewhere) { file in fileRow(file, showPath: true) }
            } header: {
                SRSectionLabel(text: "In \(model.ref.space.title)", trailing: "\(elsewhere.count)")
            }
        }
        if let passages = remote?.semantic, !passages.isEmpty {
            Section {
                ForEach(passages) { hit in
                    Button {
                        open(hit.file)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(hit.file.name).font(SR.Text.bodyMedium(15)).foregroundStyle(SR.ink).lineLimit(1)
                            Text(hit.passage).font(SR.Text.secondary(13)).foregroundStyle(SR.inkSecondary).lineLimit(3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .srGlassRow()
                    .contextMenu { fileMenu(hit.file) }
                }
            } header: {
                SRSectionLabel(text: "What your files say")
            }
        }
        if searching {
            Section {
                ProgressView().tint(SR.accent).frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        } else if folders.isEmpty && files.isEmpty && elsewhere.isEmpty && (remote?.semantic ?? []).isEmpty {
            Section {
                SREmpty(title: "Nothing called that", icon: "magnifyingglass",
                        message: trimmedQuery.count < 2 ? "Type a little more." : nil)
            }
            .listRowBackground(Color.clear)
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
            HStack(spacing: 10) {
                if let mark = DriveLogic.incomingMark(folder.path) {
                    // Incoming photos and movies: a solid tile with its own mark,
                    // so the two the phone fills stand out from the rest.
                    Image(systemName: mark)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SR.paper)
                        .frame(width: 32, height: 32)
                        .background(SR.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(SR.accent)
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.name).font(SR.Text.bodyMedium(15)).fontWeight(DriveLogic.incomingMark(folder.path) == nil ? nil : .semibold).foregroundStyle(SR.ink).lineLimit(1)
                    Text(folder.items == 1 ? "1 file" : "\(folder.items) files")
                        .font(SR.Text.secondary(12)).foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").foregroundStyle(SR.inkGhost).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .srGlassRow()
        .selectionDisabled()
        .accessibilityIdentifier("drive-folder-\(folder.name)")
        .dropDestination(for: URL.self) { urls, _ in
            drop(urls, into: folder.path)
        }
        .swipeActions(edge: .trailing) {
            if canWrite {
                Button(role: .destructive) { confirmFolder = folder } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .contextMenu {
            Button {
                router.pushFromHub(DriveRef(space: model.ref.space, folder: folder.path))
            } label: { Label("Open", systemImage: "folder") }
            if canWrite {
                Button(role: .destructive) { confirmFolder = folder } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func fileRow(_ file: DriveFile, showPath: Bool = false) -> some View {
        Button {
            open(file)
        } label: {
            DriveFileRow(file: file, opening: model.opening == file.id, showPath: showPath)
        }
        .buttonStyle(.plain)
        .srGlassRow()
        .tag(file.id)
        .accessibilityIdentifier("drive-file-\(file.name)")
        .draggable(DriveLink(space: model.ref.space, folder: DriveLogic.parent(file.path), fileId: file.id).url)
        .swipeActions(edge: .trailing) {
            if canWrite && file.canDelete {
                Button(role: .destructive) { confirmFiles = [file] } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .swipeActions(edge: .leading) {
            Button { info(file) } label: { Label("Info", systemImage: "info.circle") }
                .tint(SR.accentDeep)
        }
        .contextMenu { fileMenu(file) }
    }

    /// Everything a file offers, everywhere it is drawn.
    @ViewBuilder
    private func fileMenu(_ file: DriveFile) -> some View {
        Section {
            Button { open(file) } label: { Label("Open", systemImage: "eye") }
            Button { withCopy(file) { sharing = DriveLocalFile(url: $0) } } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button { withCopy(file) { saveToFiles($0) } } label: { Label("Save to Files", systemImage: "folder") }
            if DriveLogic.savesToPhotos(file) {
                Button { withCopy(file) { saveToPhotos($0, file: file) } } label: {
                    Label("Save to Photos", systemImage: "photo.on.rectangle")
                }
            }
        }
        if canWrite && file.canDelete {
            Section {
                Button {
                    newName = file.name
                    renaming = file
                } label: { Label("Rename", systemImage: "pencil") }
                Button { moving = [file] } label: { Label("Move…", systemImage: "folder.badge.plus") }
            }
        }
        Section {
            Button { info(file) } label: { Label("Info", systemImage: "info.circle") }
        }
        if jkai {
            Section("jkai") {
                Button { info(file, action: .analyse) } label: { Label("Analyse", systemImage: "sparkles") }
                Button { info(file, action: .extract) } label: { Label("Extract entities", systemImage: "point.3.connected.trianglepath.dotted") }
                Button { router.ask(DriveLogic.askPrompt(for: file)) } label: { Label("Ask jkai", systemImage: "bubble.left.and.text.bubble.right") }
            }
        }
        if canWrite && file.canDelete {
            Section {
                Button(role: .destructive) { confirmFiles = [file] } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) { SRBarMark() }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if selecting {
                Button("Done") {
                    editMode = .inactive
                    selection = []
                }
                .accessibilityIdentifier("drive-select-done")
            } else {
                if photoSearch {
                    Button { searchingPhotos = true } label: { Image(systemName: "sparkle.magnifyingglass") }
                        .accessibilityLabel("Search photos")
                        .accessibilityIdentifier("drive-photo-search-open")
                }
                viewMenu
                if canWrite { addMenu }
            }
        }
        if selecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { moving = writableSelection } label: { Label("Move", systemImage: "folder") }
                    .disabled(writableSelection.isEmpty)
                Spacer()
                Text(selection.isEmpty ? "Choose files" : "\(selection.count) chosen")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                Spacer()
                Button(role: .destructive) { confirmFiles = writableSelection } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(writableSelection.isEmpty)
            }
        }
    }

    /// The chosen files this person may move or delete.
    private var writableSelection: [DriveFile] {
        (model.listing?.files ?? []).filter { selection.contains($0.id) && $0.canDelete }
    }

    private var viewMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortRaw) {
                ForEach(DriveSort.allCases) { Label($0.title, systemImage: $0.icon).tag($0.rawValue) }
            }
            Picker("View", selection: $grid) {
                Label("List", systemImage: "list.bullet").tag(false)
                Label("Grid", systemImage: "square.grid.3x3").tag(true)
            }
            if canWrite, !(model.listing?.files.isEmpty ?? true) {
                Button {
                    grid = false
                    editMode = .active
                } label: { Label("Select files", systemImage: "checkmark.circle") }
            }
            if canWrite {
                Toggle(isOn: $keepOriginals) { Label("Keep photo originals (HEIC)", systemImage: "photo.badge.checkmark") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Sort and view")
        .accessibilityIdentifier("drive-view")
    }

    private var addMenu: some View {
        Menu {
            Button { choosingPhotos = true } label: { Label("Photos & Videos", systemImage: "photo.on.rectangle") }
            if CameraPicker.isAvailable {
                Button { takingPhoto = true } label: { Label("Take Photo", systemImage: "camera") }
            }
            Button { choosingFiles = true } label: { Label("Choose Files", systemImage: "doc") }
            Button { naming = true } label: { Label("New Folder", systemImage: "folder.badge.plus") }
            Divider()
            Button { syncingPhotos = true } label: { Label("Photo Sync…", systemImage: "arrow.triangle.2.circlepath") }
            Button { movingFromPhone = true } label: { Label("Move Photos off This Phone…", systemImage: "arrow.up.bin") }
        } label: {
            Image(systemName: "plus")
        }
        .disabled(model.preparing != nil || model.listing == nil)
        .accessibilityLabel("Add to Drive")
        .accessibilityIdentifier("drive-add")
    }

    @ViewBuilder
    private var banner: some View {
        VStack(spacing: 6) {
            if let preparing = model.preparing {
                SRBanner(text: preparing, tone: SR.accentDeep)
            } else if let sending = DriveUploadOutcome.banner(uploads.jobs) {
                SRBanner(text: sending, tone: SR.accentDeep)
                    .accessibilityIdentifier("drive-uploading")
            }
            if let trouble = DriveUploadOutcome.trouble(uploads.jobs) {
                SRBanner(text: trouble + " Tap to try again.", tone: SR.error)
                    .onTapGesture {
                        uploads.retryFailed()
                        uploads.dismissFinished()
                    }
            }
            if let note = model.note {
                SRBanner(text: note, tone: SR.accentDeep)
                    .onTapGesture { model.note = nil }
                    .task(id: note) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if model.note == note { model.note = nil }
                    }
            } else if let message = model.message, model.listing != nil {
                SRBanner(text: message, tone: SR.error)
                    .onTapGesture { model.message = nil }
            }
        }
        .padding(.bottom, selecting ? 4 : 0)
    }

    // MARK: - Doing

    /// A photo the site can render opens in the viewer, from its preview; anything else in Quick Look.
    private func open(_ file: DriveFile) {
        guard !selecting else { return }
        SRHaptic.tap()
        if DrivePreviewLogic.canPreview(mime: file.mimeType, name: file.name) {
            viewing = file
        } else {
            quickLook(file)
        }
    }

    /// The original, fetched once per version, in Quick Look.
    private func quickLook(_ file: DriveFile) {
        Task { if let url = await model.localCopy(of: file) { preview = url } }
    }

    private func info(_ file: DriveFile, action: DriveFileAction? = nil) {
        SRHaptic.tap()
        router.pushFromHub(DriveFileRef(space: model.ref.space, id: file.id, known: file, action: action))
    }

    /// The file on this phone first (fetched once per version), then `then`.
    private func withCopy(_ file: DriveFile, _ then: @escaping (URL) -> Void) {
        Task { if let url = await model.localCopy(of: file) { then(url) } }
    }

    /// A copy for the Files app to take: the cached one stays for Quick Look.
    private func saveToFiles(_ url: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("drive-export/\(UUID().uuidString)", isDirectory: true)
        let copy = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: copy)
            exportFile = copy
            exporting = true
        } catch {
            model.message = "That file couldn't be copied."
        }
    }

    private func saveToPhotos(_ url: URL, file: DriveFile) {
        Task {
            do {
                try await DrivePhotoImport.saveToPhotos(url, isVideo: DriveLogic.icon(mime: file.mimeType, name: file.name) == "film")
                SRHaptic.ok()
                model.note = "Saved to Photos."
            } catch {
                model.message = error.localizedDescription
            }
        }
    }

    /// Something dropped: a Drive file (dragged from a row) moves; a file from
    /// another app is added.
    private func drop(_ urls: [URL], into folder: String) -> Bool {
        guard canWrite else { return false }
        let moves = urls.compactMap { DriveLink.from(url: $0) }.filter { $0.fileId != nil && $0.space == model.ref.space }
        let files = urls.filter(\.isFileURL)
        guard !moves.isEmpty || !files.isEmpty else { return false }
        Task {
            for link in moves where link.folder != folder {
                if let id = link.fileId { await model.moveFile(id: id, to: folder) }
            }
            if !files.isEmpty { await model.addFiles(files, into: folder) }
        }
        return true
    }

    private func searchSite() async {
        let q = trimmedQuery
        guard q.count >= 2 else {
            remote = nil
            searching = false
            return
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        let answer = try? await DriveAPI.search(q, space: model.ref.space)
        guard !Task.isCancelled else { return }
        remote = answer
    }
}

/// A file on this phone, for the share sheet.
struct DriveLocalFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// The system share sheet — AirDrop, Messages, Save to Files, Print — for a
/// file already fetched.
struct DriveActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// One file: a thumbnail for a photo, otherwise its type's mark; its name,
/// and one line of size, date and — in the shared folder — who added it.
struct DriveFileRow: View {
    let file: DriveFile
    let opening: Bool
    var showPath = false

    var body: some View {
        HStack(spacing: 10) {
            DriveFileMark(file: file, points: 32)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(showPath && file.path.contains("/") ? "\(DriveLogic.parent(file.path)) · \(DriveLogic.detail(file))" : DriveLogic.detail(file))
                    .font(SR.Text.secondary(12))
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if opening { ProgressView().tint(SR.accent) }
        }
        .contentShape(Rectangle())
    }
}

/// A photo's thumbnail (loaded by itself, at `points`), or the mark of the file's type.
struct DriveFileMark: View {
    let file: DriveFile
    var points: CGFloat = 32

    var body: some View {
        if DrivePreviewLogic.canPreview(mime: file.mimeType, name: file.name) {
            DriveThumb(file: file, points: points) { mark }
        } else {
            mark
        }
    }

    private var mark: some View {
        Image(systemName: DriveLogic.icon(mime: file.mimeType, name: file.name))
            .foregroundStyle(SR.accentInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SR.accentInk.opacity(0.1))
    }
}

/// One row of the grid: up to `columns` tiles, a short last row padded so
/// its tiles keep their size and place. Every row reports the width it was
/// given, which is how the screen knows how many tiles fit (rows live in
/// List cells, so a preference would not reach it).
struct DriveGridRow<MenuItems: View>: View {
    let files: [DriveFile]
    let columns: Int
    let side: CGFloat
    let opening: String?
    @Binding var width: CGFloat
    let open: (DriveFile) -> Void
    @ViewBuilder let menu: (DriveFile) -> MenuItems

    var body: some View {
        HStack(alignment: .top, spacing: CGFloat(DriveGridLayout.spacing)) {
            ForEach(files) { file in
                DriveGridTile(file: file, side: side, opening: opening == file.id, open: open, menu: menu)
            }
            ForEach(files.count..<max(files.count, columns), id: \.self) { _ in
                Color.clear.frame(width: side, height: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { report(geometry.size.width) }
                    .onChange(of: geometry.size.width) { _, next in report(next) }
            }
        }
    }

    private func report(_ next: CGFloat) {
        if abs(next - width) > 0.5 { width = next }
    }
}

/// Files as tiles: photos large enough to tell apart, the name beneath.
struct DriveGridTile<MenuItems: View>: View {
    let file: DriveFile
    let side: CGFloat
    let opening: Bool
    let open: (DriveFile) -> Void
    @ViewBuilder let menu: (DriveFile) -> MenuItems

    var body: some View {
        Button {
            open(file)
        } label: {
            VStack(spacing: 4) {
                DriveFileMark(file: file, points: side)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        if opening { ProgressView().tint(SR.accent) }
                    }
                Text(file.name)
                    .font(SR.Text.secondary(12))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: side)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(file.name)
        .contextMenu { menu(file) }
    }
}

/// The photo viewer, full screen. A file the site has no preview of (an
/// older site) goes to Quick Look once the cover has gone, so the two never
/// fight over the screen.
private struct DriveViewerCover: ViewModifier {
    @Binding var viewing: DriveFile?
    let original: (DriveFile) async -> URL?
    let quickLook: (DriveFile) -> Void
    @State private var instead: DriveFile?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $viewing, onDismiss: {
                if let file = instead {
                    instead = nil
                    quickLook(file)
                }
            }) { file in
                DrivePhotoViewer(file: file, original: { await original(file) }, unavailable: {
                    instead = file
                    viewing = nil
                })
            }
    }
}

/// New folder, Rename and the two Delete questions. Split out so neither the
/// screen's body nor this is one expression big enough to stall the type checker.
private struct DriveDialogs: ViewModifier {
    @ObservedObject var model: DriveFolderModel
    @Binding var naming: Bool
    @Binding var newFolder: String
    @Binding var renaming: DriveFile?
    @Binding var newName: String
    @Binding var confirmFiles: [DriveFile]
    @Binding var confirmFolder: DriveFolder?
    let afterDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("New folder", isPresented: $naming) {
                TextField("Name", text: $newFolder)
                Button("Make") {
                    let name = newFolder
                    newFolder = ""
                    Task { await model.makeFolder(name) }
                }
                Button("Cancel", role: .cancel) { newFolder = "" }
            }
            .alert("Rename", isPresented: renamingShown, presenting: renaming) { file in
                TextField("Name", text: $newName)
                Button("Rename") {
                    let name = newName
                    renaming = nil
                    Task { await model.rename(file, to: name) }
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog(confirmFiles.count == 1 ? "Delete this file?" : "Delete \(confirmFiles.count) files?",
                                isPresented: filesShown, titleVisibility: .visible, presenting: confirmFiles) { files in
                Button(files.count == 1 ? "Delete \(files[0].name)" : "Delete \(files.count) files", role: .destructive) {
                    confirmFiles = []
                    afterDelete()
                    Task { await model.delete(files) }
                }
            } message: { files in
                Text(model.ref.space == .shared
                     ? (files.count == 1 ? "It goes for everyone in the family." : "They go for everyone in the family.")
                     : (files.count == 1 ? "It can't be brought back." : "They can't be brought back."))
            }
            .confirmationDialog("Delete this folder?", isPresented: folderShown, titleVisibility: .visible, presenting: confirmFolder) { folder in
                Button("Delete \(folder.name) and everything in it", role: .destructive) { Task { await model.delete(folder) } }
            }
    }

    private var renamingShown: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var filesShown: Binding<Bool> {
        Binding(get: { !confirmFiles.isEmpty }, set: { if !$0 { confirmFiles = [] } })
    }

    private var folderShown: Binding<Bool> {
        Binding(get: { confirmFolder != nil }, set: { if !$0 { confirmFolder = nil } })
    }
}

/// The pickers +'s menu opens. Split out for the type checker, as above.
private struct DrivePickers: ViewModifier {
    @ObservedObject var model: DriveFolderModel
    @Binding var photoItems: [PhotosPickerItem]
    @Binding var choosingPhotos: Bool
    @Binding var choosingFiles: Bool
    @Binding var takingPhoto: Bool
    let keepOriginals: Bool

    func body(content: Content) -> some View {
        content
            // `.current`: the original as it is on the phone (a HEIC stays a
            // HEIC), and `.shared()` so each item names its library photo.
            .photosPicker(isPresented: $choosingPhotos, selection: $photoItems,
                          maxSelectionCount: DrivePhotoImport.pickLimit, selectionBehavior: .ordered,
                          matching: .any(of: [.images, .videos]), preferredItemEncoding: .current,
                          photoLibrary: .shared())
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                Task { await model.addPicked(items, keepOriginals: keepOriginals) }
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
}

/// "Move photos off this phone": choose the days or an album, copy them to
/// this folder, and once Drive holds every one, remove them from the phone.
struct DriveMoveSheet: View {
    @ObservedObject var folder: DriveFolderModel
    let keepOriginals: Bool
    @StateObject private var move = DriveMoveFromPhone()
    @ObservedObject private var uploads = DriveUploadQueue.shared
    @ObservedObject private var sync = DrivePhotoSync.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Copies photos and videos to \(folder.ref.folder.isEmpty ? folder.ref.space.title : folder.ref.title). Once Drive has every one, you can remove them from this phone to free up space. Nothing is removed until you say so.")
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(SR.inkSecondary)
                }
                if move.allowed {
                    Section("Which photos") {
                        Picker("From", selection: $move.album) {
                            Text("All photos").tag(String?.none)
                            ForEach(move.albums) { Text($0.title).tag(Optional($0.id)) }
                        }
                        DatePicker("Taken from", selection: $move.from, displayedComponents: .date)
                        DatePicker("Up to", selection: $move.to, displayedComponents: .date)
                        Text(move.candidates == 1 ? "1 photo or video not yet in Drive" : "\(move.candidates) photos and videos not yet in Drive")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    }
                    Section {
                        Button {
                            Task { await move.copy(into: folder, keepOriginals: keepOriginals) }
                        } label: {
                            Label(move.copying ?? "Copy to Drive", systemImage: "arrow.up.circle")
                        }
                        .disabled(move.candidates == 0 || move.copying != nil)
                        if let sending = DriveUploadOutcome.banner(uploads.jobs) {
                            Text(sending).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                        }
                    }
                    Section {
                        Button(role: .destructive) {
                            confirming = true
                        } label: {
                            Label(move.removable.count == 1 ? "Remove 1 from this phone" : "Remove \(move.removable.count) from this phone",
                                  systemImage: "trash")
                        }
                        // With photo sync on something is nearly always going, so
                        // what Drive has already confirmed may go meanwhile.
                        .disabled(move.removable.isEmpty || move.copying != nil || (move.stillSending && !sync.settings.on))
                    } footer: {
                        Text(move.stillSending && !sync.settings.on ? "Waiting for every copy to reach Drive first." : "Only photos Drive has confirmed it holds. Your phone asks before anything goes, and they stay in Recently Deleted for 30 days.")
                    }
                } else {
                    Section {
                        Button {
                            Task { await move.ask() }
                        } label: {
                            Label("Allow full access to Photos", systemImage: "photo.on.rectangle")
                        }
                    } footer: {
                        Text(move.access == .limited || move.access == .denied
                             ? "Removing photos needs full access. Change it in Settings → SR → Photos."
                             : "SR needs to see your library to copy photos from it and, when you ask, remove them.")
                    }
                }
                if let message = move.message {
                    Section { Text(message).foregroundStyle(SR.inkSecondary) }
                }
            }
            .navigationTitle("Move off this phone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Remove from this phone?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Remove \(move.removable.count)", role: .destructive) { Task { await move.removeFromPhone() } }
            } message: {
                Text("They're safely in Drive. Your phone will ask once more.")
            }
            .task { move.load() }
        }
    }
}

/// "Open in SR" with Drive: the reader chooses where the file goes — into
/// Drive, or to jkai in a chat. Cancel drops it, and the copy iOS put in Inbox.
struct DriveIncomingChoice: ViewModifier {
    @Binding var files: [URL]
    let chat: Bool
    let save: ([URL]) -> Void
    let ask: ([URL]) -> Void

    func body(content: Content) -> some View {
        content
            // `presenting`: each button is handed the files as they were
            // when asked, however the dialog's own dismissal is ordered.
            .confirmationDialog(files.count == 1 ? "Where should this go?" : "Where should these go?",
                                isPresented: shown, titleVisibility: .visible, presenting: files) { chosen in
                Button("Save to Drive") {
                    files = []
                    save(chosen)
                }
                if chat {
                    Button("Ask jkai") {
                        files = []
                        ask(chosen)
                    }
                }
                Button("Cancel", role: .cancel) {
                    for url in chosen where url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
                    files = []
                }
            } message: { _ in
                Text(chat ? "Drive keeps it in My files. jkai reads it in a chat." : "Drive keeps it in My files.")
            }
    }

    private var shown: Binding<Bool> {
        Binding(get: { !files.isEmpty }, set: { if !$0 { files = [] } })
    }
}

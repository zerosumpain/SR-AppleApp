import SwiftUI
import UIKit
import UniformTypeIdentifiers

// "Share → SR": a link, a video or a line of text from any app, onto the
// family backlog. The sheet shows what came in, takes an optional note and
// who it is for, and posts it with the site credential the app leaves on the
// shared Keychain shelf (FamilyBacklogShared.swift). The site cleans the
// link and names it; this sheet does no fetching of its own beyond the
// family's names for the picker.
//
// v8: or onto a trip coming up — "Add to a trip" — as one turn of its
// planning conversation (TripShareShared.swift, ShareTrips.swift), which the
// planner turns into a suggestion or a question on the trip.
//
// Or — photos, videos and files — into Drive ("Save to Drive"): My files or
// the family's Shared folder, and a folder in it, for whoever the app has
// shelved as having Drive (DriveShared.swift). Each file is read to disk and
// streamed up from there, never held in memory — a big one a piece at a
// time (DriveChunks.swift), each piece copied out a megabyte at a time.
//
// An extension is killed for memory or slowness long before an app is, so
// it stays thin: no page reads, one request per thing sent.

final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.finish = { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        model.cancel = { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        }
        let host = UIHostingController(rootView: ShareSheet(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { @MainActor in
            await model.read(items)
            if model.files.isEmpty {
                await model.loadPeople()
                await model.loadTrips()
            } else {
                await model.loadDriveLimit()
            }
        }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable {
        case reading, ready, sending
        case finished(String)
        case failed(String)
    }

    @Published var phase: Phase = .reading
    @Published var url: URL?
    @Published var text: String?
    @Published var note = ""
    @Published var forId: String?
    @Published var people: [FamilyTaskPerson] = []
    @Published var me: FamilyTaskMe?
    /// v8: trips still to come, and where this share goes.
    @Published var trips: [TripShareTarget] = []
    @Published var destination: Destination = .backlog

    enum Destination: Hashable {
        case backlog
        case trip(String)
        /// Drive: a space and a folder in it ("" for its top).
        case drive(DriveSpace, String)
    }

    /// A photo, video or file shared in, copied to the extension's own
    /// temporary folder (the system's copy goes when its callback returns).
    struct SharedFile: Equatable {
        let url: URL
        let name: String
        let bytes: Int
        let type: String
    }

    /// Photos, videos and files: these go to Drive, nothing else takes them.
    @Published var files: [SharedFile] = []
    /// The most the site takes per file, once a listing has said.
    @Published var maxUploadBytes = DriveLogic.defaultMaxUpload
    /// The most a file may be sent a piece at a time; nil when the site
    /// takes no big uploads.
    @Published var maxLargeUploadBytes: Int?
    @Published var sent = 0
    /// A big file on its way: the bytes the site holds, of its size.
    @Published var bigProgress: (held: Int, of: Int)?

    var driveAllowed: Bool { DriveShelf.allowed }

    var driveSpace: DriveSpace {
        if case .drive(let space, _) = destination { return space }
        return .mine
    }

    var driveFolder: String {
        if case .drive(_, let folder) = destination { return folder }
        return ""
    }

    /// The trip picked, if one is.
    var trip: TripShareTarget? {
        guard case .trip(let id) = destination else { return nil }
        return trips.first { $0.id == id }
    }

    var finish: () -> Void = {}
    var cancel: () -> Void = {}

    var signedIn: Bool { FamilyShelf.read(.credential) != nil }

    /// Photos, videos and files first (for Drive); else a link (YouTube,
    /// Safari), then text (a TikTok caption, a note).
    func read(_ items: [NSExtensionItem]) async {
        for item in items {
            for provider in item.attachments ?? [] {
                if let kind = Self.fileKind(provider), let file = await Self.copy(provider, kind) {
                    files.append(file)
                    continue
                }
                if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let found = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                   found.scheme == "https" || found.scheme == "http" {
                    url = found
                }
                if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let found = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    let trimmed = found.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { text = trimmed }
                }
            }
            // Some apps put the page's title here rather than in an attachment.
            if text == nil, let words = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines),
               !words.isEmpty {
                text = words
            }
        }
        if !files.isEmpty {
            guard driveAllowed else {
                phase = .failed("Photos and files go to Drive, and Drive isn't on for you in SR. Ask John to turn it on.")
                return
            }
            destination = .drive(.mine, "")
            phase = .ready
            return
        }
        if url == nil, let text, let link = FamilyBacklogText.firstLink(in: text) { url = link }
        // Text that is only the link adds nothing.
        if let text, let url, text == url.absoluteString { self.text = nil }
        phase = url == nil && text == nil ? .failed("There's nothing here SR can add — share a link or some text.") : .ready
    }

    /// The type a provider's file is read as: a photo, a film, or any other
    /// file. A link or a line of text is not a file, even though both
    /// conform to `public.data`.
    ///
    /// A document from Files arrives as its own type beside `public.file-url`
    /// — which is a URL — so a file URL marks it a file, text types and all.
    private static func fileKind(_ provider: NSItemProvider) -> UTType? {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) { return .image }
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) { return .movie }
        let types = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
        let fromFiles = types.contains { $0.conforms(to: .fileURL) }
        for type in types where !type.conforms(to: .url) && type.conforms(to: .data) {
            if fromFiles || !type.conforms(to: .text) { return type }
        }
        return nil
    }

    /// The provider's file, copied before the system takes its own away.
    private static func copy(_ provider: NSItemProvider, _ kind: UTType) async -> SharedFile? {
        let suggested = provider.suggestedName
        return await withCheckedContinuation { (done: CheckedContinuation<SharedFile?, Never>) in
            _ = provider.loadFileRepresentation(forTypeIdentifier: kind.identifier) { file, _ in
                guard let file else { done.resume(returning: nil); return }
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("share-drive", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                var name = file.lastPathComponent
                if let suggested, !suggested.isEmpty, !file.pathExtension.isEmpty,
                   (suggested as NSString).pathExtension.isEmpty {
                    name = "\(suggested).\(file.pathExtension)"
                }
                let target = folder.appendingPathComponent(DriveLogic.usableName(name) ?? file.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: file, to: target)
                    let bytes = (try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.intValue ?? 0
                    done.resume(returning: SharedFile(url: target, name: target.lastPathComponent, bytes: bytes,
                                                      type: DriveShelf.mimeType(for: target)))
                } catch {
                    done.resume(returning: nil)
                }
            }
        }
    }

    /// The top of the chosen space, for the site's per-file limit.
    func loadDriveLimit() async {
        guard !files.isEmpty, driveAllowed, let listing = await DriveFolderFetch.list(space: driveSpace, folder: "") else { return }
        maxUploadBytes = listing.maxUploadBytes
        maxLargeUploadBytes = listing.maxLargeUploadBytes
    }

    func loadPeople() async {
        guard signedIn, let board = await FamilyBacklogPost.board() else { return }
        people = board.people
        me = board.me
    }

    /// The trips this share could go to. None (no credential, no trips, no
    /// signal) leaves the sheet exactly as it was: the backlog alone.
    func loadTrips() async {
        guard signedIn, let all = await TripSharePost.trips() else { return }
        trips = TripShare.targets(all, now: Date())
    }

    var headline: String {
        if !files.isEmpty {
            let photos = files.filter { $0.type.hasPrefix("image/") }.count
            let films = files.filter { $0.type.hasPrefix("video/") }.count
            if files.count == 1 { return files[0].name }
            if photos == files.count { return "\(photos) photos" }
            if films == files.count { return "\(films) videos" }
            return "\(files.count) files"
        }
        if let url { return FamilyBacklogText.host(url.absoluteString) ?? url.absoluteString }
        return "An idea"
    }

    /// One line under the headline for files: their size together.
    var filesDetail: String? {
        guard !files.isEmpty else { return nil }
        if phase == .sending, let big = bigProgress {
            return "\(DriveLogic.size(big.held)) of \(DriveLogic.size(big.of)) sent"
        }
        return DriveLogic.size(files.reduce(0) { $0 + $1.bytes })
    }

    func send() async {
        guard phase == .ready else { return }
        guard signedIn else {
            phase = .failed("Open SR on this phone first. Sharing works once the Family pages are there for you.")
            return
        }
        if !files.isEmpty {
            await sendToDrive()
            return
        }
        if let trip {
            await send(to: trip)
            return
        }
        phase = .sending
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let share = FamilyBacklogShare(
            url: url?.absoluteString,
            text: text,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            forId: forId
        )
        switch await FamilyBacklogPost.send(share) {
        case .added(_, let duplicate):
            phase = .finished(duplicate ? "Already on the backlog." : "Added to the backlog.")
            done(after: 0.9)
        case .unreachable:
            FamilyBacklogQueue.add(share)
            phase = .finished("No signal — it'll go when SR next opens.")
            done(after: 1.6)
        case .notSignedIn:
            phase = .failed("SR isn't signed in for the family on this phone. Open SR to sort it out.")
        case .refused(let reason):
            phase = .failed(reason)
        }
    }

    /// One turn to the trip's planner, left to run. Never queued: the
    /// planner has to answer it, so offline says so instead.
    private func send(to trip: TripShareTarget) async {
        guard let text = TripShare.turn(url: url, text: text, note: note) else {
            phase = .failed("There's nothing here to tell the planner — share a link or some text.")
            return
        }
        phase = .sending
        switch await TripSharePost.send(text, to: trip.id) {
        case .sent:
            phase = .finished("Sent to the planner for \(trip.title). It comes back on the trip as a suggestion or a question.")
            done(after: 1.6)
        case .unreachable:
            phase = .failed("Couldn't reach the planner, so nothing was sent. Try again with a signal.")
        case .notSignedIn:
            phase = .failed("SR isn't signed in for the family on this phone. Open SR to sort it out.")
        case .refused(let reason):
            phase = .failed(reason)
        }
    }

    /// Each file up in turn, while the sheet is open. Never queued: without
    /// an App Group there is nowhere to keep a file for later.
    private func sendToDrive() async {
        let space = driveSpace
        let folder = driveFolder
        for file in files {
            if case .refused(let refusal) = DriveChunks.route(size: file.bytes, single: maxUploadBytes, large: maxLargeUploadBytes) {
                phase = .failed("\(file.name): \(refusal) Nothing was sent.")
                return
            }
        }
        phase = .sending
        sent = 0
        var duplicates = 0
        for file in files {
            let outcome: DriveSharePost.Outcome
            if DriveChunks.route(size: file.bytes, single: maxUploadBytes, large: maxLargeUploadBytes) == .chunked {
                bigProgress = (0, file.bytes)
                outcome = await DriveChunkedPost.upload(fileURL: file.url, size: file.bytes, space: space, folder: folder,
                                                        filename: file.name, type: file.type) { [weak self] held in
                    self?.bigProgress = (held, file.bytes)
                }
                bigProgress = nil
            } else {
                outcome = await DriveSharePost.upload(fileURL: file.url, space: space, folder: folder, filename: file.name, type: file.type)
            }
            switch outcome {
            case .stored(_, let duplicate):
                sent += 1
                if duplicate { duplicates += 1 }
                try? FileManager.default.removeItem(at: file.url)
            case .notSignedIn:
                phase = .failed("SR isn't signed in for Drive on this phone. Open SR to sort it out.")
                return
            case .refused(let reason):
                phase = .failed(sent == 0 ? "\(file.name): \(reason)" : "\(sent) saved. \(file.name): \(reason)")
                return
            case .unreachable:
                phase = .failed(sent == 0 ? "Couldn't send. Try again on Wi-Fi." : "\(sent) saved, the rest couldn't send. Try again on Wi-Fi.")
                return
            }
        }
        let place = folder.isEmpty ? space.title : (DriveLogic.lastSegment(folder) ?? space.title)
        let words: String
        if files.count == 1 {
            words = duplicates == 1 ? "Already in \(place)." : "Saved to \(place)."
        } else {
            words = duplicates == files.count ? "All already in \(place)." : "Saved \(files.count) to \(place)."
        }
        phase = .finished(words)
        done(after: 1.2)
    }

    private func done(after seconds: Double) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            finish()
        }
    }
}

struct ShareSheet: View {
    @ObservedObject var model: ShareModel
    @State private var choosingFolder = false

    private var title: String {
        if !model.files.isEmpty { return "Save to Drive" }
        return model.trip == nil ? "Family backlog" : "Add to a trip"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.headline)
                            .font(.headline)
                            .foregroundStyle(FamilyWidgetInk.ink)
                        if let detail = model.filesDetail {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(FamilyWidgetInk.muted)
                        }
                        if let text = model.text {
                            Text(text)
                                .font(.subheadline)
                                .foregroundStyle(FamilyWidgetInk.muted)
                                .lineLimit(4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if case .failed(let reason) = model.phase {
                    Section {
                        Text(reason).foregroundStyle(.red)
                    }
                } else if case .finished(let words) = model.phase {
                    Section {
                        Label(words, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(FamilyWidgetInk.ink)
                    }
                } else if !model.files.isEmpty {
                    driveSections
                } else {
                    // v8: a trip coming up is somewhere else this can go.
                    if !model.trips.isEmpty {
                        Section {
                            Picker("Add to", selection: $model.destination) {
                                Text("Family backlog").tag(ShareModel.Destination.backlog)
                                ForEach(model.trips) { trip in
                                    Text(TripShare.label(trip)).tag(ShareModel.Destination.trip(trip.id))
                                }
                            }
                        } header: {
                            Text("Add to a trip")
                        }
                    }
                    Section {
                        TextField(model.trip == nil ? "Note (optional)" : "Anything to tell the planner (optional)",
                                  text: $model.note, axis: .vertical)
                            .lineLimit(1...4)
                        if model.trip == nil {
                            Picker("For", selection: $model.forId) {
                                Text("Everyone").tag(String?.none)
                                ForEach(model.people) { person in
                                    Text(person.id == model.me?.id ? "\(person.name) (you)" : person.name).tag(Optional(person.id))
                                }
                            }
                        }
                    } footer: {
                        if let trip = model.trip {
                            Text("The planner reads it and comes back on \(trip.title) with a suggestion or a question.")
                        } else {
                            Text("Everyone in the family sees the backlog.")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FamilyWidgetInk.paper)
            .tint(FamilyWidgetInk.accent)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancel() }
                        .disabled(model.phase == .sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch model.phase {
                    case .sending:
                        ProgressView()
                    case .failed, .finished:
                        Button("Close") { model.finish() }
                    default:
                        Button(model.files.isEmpty ? "Add" : "Save") { Task { await model.send() } }
                            .disabled(model.phase != .ready)
                    }
                }
            }
            .sheet(isPresented: $choosingFolder) {
                DriveFolderPicker(
                    space: model.driveSpace,
                    title: "Choose a folder",
                    confirm: "Save here",
                    start: model.driveFolder,
                    load: { space, folder in await DriveFolderFetch.list(space: space, folder: folder) },
                    chosen: { folder in model.destination = .drive(model.driveSpace, folder) }
                )
            }
        }
        .tint(Color(red: 0xC4 / 255, green: 0x57 / 255, blue: 0x0A / 255))
    }

    /// Where in Drive: My files or Shared, and a folder.
    @ViewBuilder
    private var driveSections: some View {
        Section {
            Picker("Save in", selection: Binding(
                get: { model.driveSpace },
                set: { model.destination = .drive($0, "") }
            )) {
                ForEach(DriveSpace.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Button {
                choosingFolder = true
            } label: {
                LabeledContent("Folder") {
                    Text(model.driveFolder.isEmpty ? "Top of \(model.driveSpace.title)" : model.driveFolder)
                        .foregroundStyle(FamilyWidgetInk.muted)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(FamilyWidgetInk.ink)
        } footer: {
            if case .sending = model.phase, model.files.count > 1 {
                Text("Saving \(min(model.sent + 1, model.files.count)) of \(model.files.count)… Keep this open until it's done.")
            } else {
                Text(model.driveSpace.promise)
            }
        }
    }
}

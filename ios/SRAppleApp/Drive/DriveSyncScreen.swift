import Photos
import SwiftUI

/// "Photo sync": keep this phone's photos in Drive, and see how the two
/// compare — what is in Drive, what is on its way, what is still to go.
struct DriveSyncSheet: View {
    @ObservedObject private var sync = DrivePhotoSync.shared
    @ObservedObject private var uploads = DriveUploadQueue.shared
    @StateObject private var move = DriveMoveFromPhone()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemove = false
    @State private var showingSkipped = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $sync.settings.on) {
                        Label("Keep photos in Drive", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("drive-sync-toggle")
                } footer: {
                    Text("New photos and videos go to My files › Incoming photos and Incoming movies by themselves, in the background. Anything Drive already has is never sent twice. Nothing is removed from this phone unless you ask.")
                }

                if !DrivePhotoSync.canRead(sync.access) {
                    Section {
                        Button {
                            Task { await sync.askForAccess() }
                        } label: {
                            Label("Allow access to Photos", systemImage: "photo.on.rectangle")
                        }
                    } footer: {
                        Text(sync.access == .denied || sync.access == .restricted
                             ? "Photos access is off for SR. Turn it on in Settings → SR → Photos."
                             : "SR needs to see your library to compare it with Drive.")
                    }
                } else {
                    compare
                    options
                    freeUp
                }
            }
            .navigationTitle("Photo sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Remove from this phone?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove \(move.removable.count)", role: .destructive) { Task { await move.removeFromPhone() } }
            } message: {
                Text("Drive has confirmed it holds every one. Your phone will ask once more, and they stay in Recently Deleted for 30 days.")
            }
            .sheet(isPresented: $showingSkipped) { skippedList }
            .task {
                move.load()
                sync.kick()
            }
        }
    }

    // MARK: - The comparison

    private var compare: some View {
        Section {
            Text(DriveSync.status(pause: sync.pause, counts: sync.counts, working: sync.working))
                .font(SR.Text.bodyMedium())
                .foregroundStyle(SR.ink)
                .accessibilityIdentifier("drive-sync-status")
            row("On this phone", sync.counts.library, icon: "iphone")
            row("In Drive", sync.counts.inDrive, icon: "checkmark.icloud")
            row("Sending now", sync.counts.sending, icon: "arrow.up.circle")
            row("Not yet in Drive", sync.counts.notYet, icon: "icloud.slash")
            if sync.counts.skipped > 0 {
                Button {
                    showingSkipped = true
                } label: {
                    row("Drive wouldn't take", sync.counts.skipped, icon: "exclamationmark.triangle")
                }
            }
            if let trouble = DriveUploadOutcome.trouble(uploads.jobs) {
                Text(trouble).font(SR.Text.secondary()).foregroundStyle(SR.inkSecondary)
            }
            if sync.unchecked > 0 {
                Text("Drive is still fingerprinting \(sync.unchecked) older photos and videos. Big videos wait until it has, so none is sent twice.")
                    .font(SR.Text.secondary()).foregroundStyle(SR.inkMuted)
            }
            if !sync.waiting.isEmpty {
                NavigationLink {
                    DriveSyncWaiting(ids: sync.waiting, total: sync.counts.notYet)
                } label: {
                    Label("See what's not in Drive yet", systemImage: "square.grid.3x3")
                }
            }
            Button {
                sync.kick()
            } label: {
                Label("Check now", systemImage: "arrow.clockwise")
            }
            .disabled(!sync.settings.on || sync.working != nil)
        } header: {
            Text("This phone and Drive")
        } footer: {
            if let checked = sync.lastChecked {
                Text("Checked \(checked.formatted(.relative(presentation: .named))). \"In Drive\" counts only photos Drive has confirmed it holds.")
            }
        }
    }

    private func row(_ title: String, _ count: Int, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(SR.ink)
            Spacer()
            Text(count.formatted()).font(SR.Text.mono(14)).foregroundStyle(SR.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Options

    private var options: some View {
        Section("What to sync") {
            Toggle("Include videos", isOn: $sync.settings.videos)
            Toggle("Only on Wi-Fi", isOn: $sync.settings.wifiOnly)
            Picker("Photos taken", selection: sinceAll) {
                Text("Any time").tag(true)
                Text("Since a date").tag(false)
            }
            if let since = sync.settings.since {
                DatePicker("Since", selection: Binding(get: { since }, set: { sync.settings.since = $0 }),
                           in: ...Date(), displayedComponents: .date)
            }
            if sync.access == .limited {
                Text("SR can see only the photos you chose for it. To sync everything, allow full access in Settings → SR → Photos.")
                    .font(SR.Text.secondary()).foregroundStyle(SR.inkMuted)
            }
        }
    }

    private var sinceAll: Binding<Bool> {
        Binding(
            get: { sync.settings.since == nil },
            set: { all in
                sync.settings.since = all ? nil : Calendar.current.date(byAdding: .month, value: -1, to: Date())
            }
        )
    }

    // MARK: - Free up space

    private var freeUp: some View {
        Section {
            Button(role: .destructive) {
                confirmingRemove = true
            } label: {
                Label(move.removable.count == 1 ? "Remove 1 from this phone" : "Remove \(move.removable.count) from this phone",
                      systemImage: "trash")
            }
            .disabled(move.removable.isEmpty || !move.allowed)
        } header: {
            Text("Free up space")
        } footer: {
            Text(move.allowed
                 ? "Only photos Drive has confirmed it holds. Photos still on their way stay until they're in."
                 : "Removing photos needs full access to Photos.")
        }
    }

    // MARK: - Refused

    private var skippedList: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(sync.skipped.keys).sorted(), id: \.self) { id in
                        HStack(spacing: 12) {
                            DriveAssetThumb(id: id, side: 44)
                            Text(sync.skipped[id] ?? "").font(SR.Text.secondary()).foregroundStyle(SR.inkSecondary)
                        }
                    }
                } footer: {
                    Text("These stay on the phone. Try again sends them once more.")
                }
            }
            .navigationTitle("Drive wouldn't take")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { showingSkipped = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Try again") {
                        sync.retrySkipped()
                        showingSkipped = false
                    }
                }
            }
        }
    }
}

/// The newest photos not in Drive yet, as a grid.
struct DriveSyncWaiting: View {
    let ids: [String]
    let total: Int

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 2)], spacing: 2) {
                ForEach(ids, id: \.self) { DriveAssetThumb(id: $0, side: 88) }
            }
            if total > ids.count {
                Text("And \((total - ids.count).formatted()) more.")
                    .font(SR.Text.secondary()).foregroundStyle(SR.inkMuted)
                    .padding()
            }
        }
        .navigationTitle(total == 1 ? "1 not in Drive yet" : "\(total.formatted()) not in Drive yet")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One library photo, small, from the phone's own thumbnails.
struct DriveAssetThumb: View {
    let id: String
    let side: CGFloat
    @State private var image: UIImage?
    @State private var isVideo = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(SR.inkGhost)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
            if isVideo {
                Image(systemName: "video.fill")
                    .font(SR.Text.label())
                    .foregroundStyle(.white)
                    .padding(4)
                    .shadow(radius: 2)
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .accessibilityHidden(true)
        .task(id: id) { await load() }
    }

    private func load() async {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }
        isVideo = asset.mediaType == .video
        let scale = UITraitCollection.current.displayScale
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        let target = CGSize(width: side * scale, height: side * scale)
        for await picture in Self.images(asset, target, options) {
            image = picture
        }
    }

    /// The system answers twice in opportunistic mode: a quick blurry one, then the real one.
    private static func images(_ asset: PHAsset, _ size: CGSize, _ options: PHImageRequestOptions) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            let id = PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { picture, info in
                if let picture { continuation.yield(picture) }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded || info?[PHImageErrorKey] != nil || (info?[PHImageCancelledKey] as? Bool) == true {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in PHImageManager.default().cancelImageRequest(id) }
        }
    }
}

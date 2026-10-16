import SwiftUI
import Photos

/// "How it went" (v7, proposal D): each day that has been, its stops with
/// when you were there, and the photos this phone took at each — matched by
/// time and place (`TripStoryMatch`), read from the library on the phone and
/// never uploaded. "Loved it" / "Skip next time" are kept on the phone; an
/// editor may send them to the planner as a message.
struct TripStoryRef: Hashable { let tripId: String }

struct TripStoryScreen: View {
    let tripId: String
    @ObservedObject private var store = TripStore.shared
    @State private var access: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var photos: [String: [String: [PHAsset]]] = [:]
    @State private var verdicts: [String: String] = [:]
    @State private var sent = false
    @State private var sending = false

    private var verdictKey: String { "trip-story-verdicts:\(tripId)" }

    var body: some View {
        Group {
            if let bundle = store.bundles[tripId] {
                content(bundle)
            } else {
                SREmpty(title: "This trip is not on the phone", icon: "icloud.and.arrow.down")
            }
        }
        .srPaper()
        .navigationTitle("How it went")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .accessibilityIdentifier("trip-story")
    }

    private func pastDays(_ bundle: TripBundle) -> [PlannedDay] {
        let today = TripClock(bundle.trip.timeZone).localDate(Date())
        return (bundle.plan?.plan.days ?? []).filter { $0.date < today }.map { store.day(tripId, $0.date) ?? $0 }
    }

    private func content(_ bundle: TripBundle) -> some View {
        let clock = TripClock(bundle.trip.timeZone)
        let marks = store.marks(tripId)
        return List {
            if access == .notDetermined {
                VStack(alignment: .leading, spacing: 8) {
                    Text("See your photos beside each stop")
                        .font(SR.Text.title(16)).foregroundStyle(SR.ink)
                    Text("Photos taken on the trip are matched to the stops by when and where. They stay on this phone.")
                        .font(SR.Text.secondary(13)).foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                            Task { @MainActor in access = status; load() }
                        }
                    } label: { SRButtonLabel(title: "Show my photos", icon: "photo.on.rectangle", fill: true) }
                        .srButton(.prominent)
                }
                .padding(.vertical, 8)
                .srPlainRow()
            }
            ForEach(pastDays(bundle)) { day in
                Section {
                    ForEach(day.stops.filter { $0.kind == .wish || $0.kind == .meal }) { stop in
                        storyRow(stop, day: day, mark: marks[stop.id], bundle: bundle)
                            .srPlainRow()
                    }
                } header: {
                    TripHeading(text: TripFormat.day(day.date, zone: clock.zone))
                }
            }
            if bundle.can.canEdit, !verdicts.isEmpty {
                Button {
                    send(bundle)
                } label: {
                    if sending { ProgressView() } else {
                        SRButtonLabel(title: sent ? "Sent to the planner" : "Tell the planner what we loved", icon: "bubble.left", fill: !sent)
                    }
                }
                .srButton(.prominent)
                .disabled(sent || sending)
                .srPlainRow()
                .padding(.vertical, 12)
                .accessibilityIdentifier("trip-story-send")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func storyRow(_ stop: PlannedStop, day: PlannedDay, mark: TripStopMark?, bundle: TripBundle) -> some View {
        let shots = photos[day.date]?[stop.id] ?? []
        let verdict = verdicts[stop.id]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.title)
                        .font(SR.Text.title(16))
                        .foregroundStyle(mark?.skipped == true ? SR.inkMuted : SR.ink)
                        .strikethrough(mark?.skipped == true)
                    Text(when(stop, mark: mark))
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkMuted)
                }
                Spacer()
                if mark?.skipped != true {
                    Menu {
                        Button { judge(stop.id, "loved") } label: { Label("Loved it", systemImage: "heart") }
                        Button { judge(stop.id, "skip") } label: { Label("Skip next time", systemImage: "hand.thumbsdown") }
                        if verdict != nil { Button(role: .destructive) { judge(stop.id, nil) } label: { Label("Clear", systemImage: "xmark") } }
                    } label: {
                        Image(systemName: verdict == "loved" ? "heart.fill" : verdict == "skip" ? "hand.thumbsdown.fill" : "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(verdict == "loved" ? SR.accent : SR.inkMuted)
                    }
                    .accessibilityLabel(verdict == "loved" ? "Loved it" : verdict == "skip" ? "Skip next time" : "How was it?")
                }
            }
            if !shots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shots, id: \.localIdentifier) { asset in
                            TripAssetThumb(asset: asset)
                        }
                    }
                }
                .accessibilityLabel("\(shots.count) photo\(shots.count == 1 ? "" : "s") from here")
            }
        }
        .padding(.vertical, 6)
    }

    /// "Here 10:12–11:40", or the plan's times when nothing was marked.
    private func when(_ stop: PlannedStop, mark: TripStopMark?) -> String {
        if mark?.skipped == true { return "Skipped" }
        if let arrived = mark?.arrivedAt {
            let a = arrived.formatted(date: .omitted, time: .shortened)
            let l = mark?.leftAt.map { "–" + $0.formatted(date: .omitted, time: .shortened) } ?? ""
            return "Here \(a)\(l)"
        }
        return "Planned \(TripWords.span(stop))"
    }

    private func judge(_ stopId: String, _ verdict: String?) {
        SRHaptic.select()
        verdicts[stopId] = verdict
        sent = false
        UserDefaults.standard.set(verdicts, forKey: verdictKey)
    }

    private func send(_ bundle: TripBundle) {
        let titles = Dictionary(pastDays(bundle).flatMap(\.stops).map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let loved = verdicts.filter { $0.value == "loved" }.compactMap { titles[$0.key] }
        let skip = verdicts.filter { $0.value == "skip" }.compactMap { titles[$0.key] }
        var parts: [String] = []
        if !loved.isEmpty { parts.append("we loved " + loved.joined(separator: ", ")) }
        if !skip.isEmpty { parts.append("next time we'd skip " + skip.joined(separator: ", ")) }
        guard !parts.isEmpty else { return }
        sending = true
        // A memory for future trips, not an edit: the planner is told not to
        // change this one.
        let text = "Looking back on \(bundle.trip.title) (no changes to this trip, please): " + parts.joined(separator: "; ") + ". Please remember that for future trips."
        Task {
            let ok = (try? await TripsAPI.converse(text, trip: tripId)) != nil
            sending = false
            sent = ok
            if !ok { SRHaptic.bad() }
        }
    }

    /// The library's photos for each past day, matched to its stops.
    private func load() {
        verdicts = (UserDefaults.standard.dictionary(forKey: verdictKey) as? [String: String]) ?? [:]
        access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard access == .authorized || access == .limited, let bundle = store.bundles[tripId] else { return }
        let clock = TripClock(bundle.trip.timeZone)
        var out: [String: [String: [PHAsset]]] = [:]
        for day in pastDays(bundle) {
            guard let start = clock.date(day.date, minutes: 0), let end = clock.date(day.date, minutes: 1440) else { continue }
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@",
                                            PHAssetMediaType.image.rawValue, start as NSDate, end as NSDate)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let fetched = PHAsset.fetchAssets(with: options)
            var assets: [String: PHAsset] = [:]
            var shots: [TripStoryMatch.Photo] = []
            fetched.enumerateObjects { asset, _, _ in
                guard let taken = asset.creationDate else { return }
                assets[asset.localIdentifier] = asset
                let at = asset.location.map { TripLatLng(lat: $0.coordinate.latitude, lng: $0.coordinate.longitude) }
                shots.append(TripStoryMatch.Photo(id: asset.localIdentifier, minute: clock.minutes(taken), at: at))
            }
            let matched = TripStoryMatch.assign(shots, to: day)
            out[day.date] = matched.mapValues { ids in ids.compactMap { assets[$0] } }
        }
        photos = out
    }
}

/// One photo from the library, as a square.
struct TripAssetThumb: View {
    let asset: PHAsset
    var size: CGFloat = 84
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(SR.inkMuted.opacity(0.12))
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: asset.localIdentifier) {
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            let scale = UIScreen.main.scale
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: size * scale, height: size * scale),
                contentMode: .aspectFill, options: options
            ) { result, _ in
                Task { @MainActor in if let result { image = result } }
            }
        }
        .accessibilityHidden(true)
    }
}

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
// An extension is killed for memory or slowness long before an app is, so
// it stays thin: no images, no page reads, one request to send.

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
            await model.loadPeople()
            await model.loadTrips()
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
    }

    /// The trip picked, if one is.
    var trip: TripShareTarget? {
        guard case .trip(let id) = destination else { return nil }
        return trips.first { $0.id == id }
    }

    var finish: () -> Void = {}
    var cancel: () -> Void = {}

    var signedIn: Bool { FamilyShelf.read(.credential) != nil }

    /// A link first (YouTube, Safari), then text (a TikTok caption, a note).
    func read(_ items: [NSExtensionItem]) async {
        for item in items {
            for provider in item.attachments ?? [] {
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
        if url == nil, let text, let link = FamilyBacklogText.firstLink(in: text) { url = link }
        // Text that is only the link adds nothing.
        if let text, let url, text == url.absoluteString { self.text = nil }
        phase = url == nil && text == nil ? .failed("There's nothing here SR can add — share a link or some text.") : .ready
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
        if let url { return FamilyBacklogText.host(url.absoluteString) ?? url.absoluteString }
        return "An idea"
    }

    func send() async {
        guard phase == .ready else { return }
        guard signedIn else {
            phase = .failed("Open SR on this phone first. Sharing works once the Family pages are there for you.")
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

    private func done(after seconds: Double) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            finish()
        }
    }
}

struct ShareSheet: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.headline)
                            .font(.headline)
                            .foregroundStyle(FamilyWidgetInk.ink)
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
            .navigationTitle(model.trip == nil ? "Family backlog" : "Add to a trip")
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
                        Button("Add") { Task { await model.send() } }
                            .disabled(model.phase != .ready)
                    }
                }
            }
        }
        .tint(Color(red: 0xC4 / 255, green: 0x57 / 255, blue: 0x0A / 255))
    }
}

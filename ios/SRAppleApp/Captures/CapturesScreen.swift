import SwiftUI

/// Navigation values for Captures, registered on every tab's stack
/// (`ContentView.hosted`), because the hub is opened on whichever tab shows.
struct CapturesRef: Hashable {}
struct CaptureRef: Hashable { let id: String }
struct CaptureEntityRef: Hashable {
    let id: String
    let name: String
}
struct CaptureSettingsRef: Hashable {}

/// Captures: record, what is waiting to go up, and everything recorded —
/// searchable, with chips for a person, an app and a stretch of time.
///
/// The owner's alone, from the ⊞ hub (and `sr://captures`).
struct CapturesScreen: View {
    @ObservedObject private var store = CaptureStore.shared
    @ObservedObject private var recorder = CaptureRecorder.shared
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase

    @State private var query = ""
    @State private var person: String?
    @State private var app: String?
    @State private var window: Window?
    @State private var results: CaptureSearchResult?
    @State private var searching = false
    @State private var searchError: String?

    enum Window: String, CaseIterable, Identifiable {
        case today = "Today", week = "This week", month = "This month"
        var id: String { rawValue }

        func from(now: Date = Date()) -> Date {
            let calendar = Calendar.current
            switch self {
            case .today: return calendar.startOfDay(for: now)
            case .week: return calendar.date(byAdding: .day, value: -7, to: now) ?? now
            case .month: return calendar.date(byAdding: .month, value: -1, to: now) ?? now
            }
        }
    }

    private var filters: CaptureSearchFilters {
        CaptureSearchFilters(
            q: query,
            person: person,
            app: app,
            from: window.map { CaptureClock.iso($0.from()) }
        )
    }

    var body: some View {
        List {
            Section {
                recordCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            // The time chip is always there; people and apps once recorded.
            Section {
                chips
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            if !store.queue.isEmpty {
                Section {
                    ForEach(store.queue) { item in
                        PendingCaptureRow(item: item)
                            .srGlassRow()
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.discard(item.id)
                                } label: { Label("Discard", systemImage: "trash") }
                            }
                    }
                } header: {
                    SRSectionLabel(text: "On this phone", trailing: store.draining ? "Sending" : nil)
                } footer: {
                    Button {
                        SRHaptic.tap()
                        Task { await store.drain(force: true) }
                    } label: {
                        Text("Send now").font(SR.Text.secondary())
                    }
                    .disabled(store.draining)
                }
            }

            if filters.isEmpty {
                listSections
            } else {
                searchSections
            }
        }
        .listStyle(.insetGrouped)
        .srPaper()
        .navigationTitle("Captures")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search what was said")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .onChange(of: query) { _, value in
            if value.isEmpty { Task { await runSearch() } }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    SRHaptic.tap()
                    router.pushFromHub(CaptureSettingsRef())
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Capture settings")
                .accessibilityIdentifier("captures-settings")
            }
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await store.drain()
            await store.load()
        }
        .srRefreshable {
            await store.drain(force: true)
            await store.load()
            if !filters.isEmpty { await runSearch() }
        }
        .accessibilityIdentifier("captures-screen")
    }

    // MARK: - Recording

    private var recordCard: some View {
        SRCard(accented: recorder.recording) {
            VStack(alignment: .leading, spacing: 12) {
                if recorder.recording, let started = recorder.startedAt {
                    HStack(spacing: 10) {
                        Circle().fill(SR.error).frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(timerInterval: started...started.addingTimeInterval(CaptureRecorder.maximumLength), countsDown: false)
                            .font(SR.Text.figure())
                            .foregroundStyle(SR.ink)
                            .monospacedDigit()
                        Spacer()
                        if recorder.withScreenshot {
                            SRGlassChip(text: "Screenshot", icon: "camera.viewfinder")
                        }
                    }
                    Text("Recording. Stop here, on the Lock Screen, or with the button you started it from.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button {
                            SRHaptic.ok()
                            Task { await recorder.stop() }
                        } label: {
                            SRButtonLabel(title: "Stop and send", icon: "stop.fill", fill: true)
                        }
                        .srButton(.prominent)
                        .accessibilityIdentifier("captures-stop")
                        Button {
                            SRHaptic.tap()
                            Task { await recorder.discard() }
                        } label: {
                            SRButtonLabel(title: "Discard")
                        }
                        .srButton(.regular)
                    }
                } else {
                    Text("Record a conversation or a thought. It is transcribed on this phone, voices are told apart, and the site picks out follow-ups for you to approve.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        SRHaptic.tap()
                        Task { await recorder.toggle(source: "app") }
                    } label: {
                        SRButtonLabel(title: "Record", icon: "mic.fill", fill: true)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .accessibilityIdentifier("captures-record")
                    if let problem = recorder.problem {
                        Text(problem)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Filters

    /// People and apps to filter by, from what has been recorded.
    private var chipsPeople: [String] {
        var seen = Set<String>()
        return store.items.flatMap(\.speakers)
            .filter { $0 != "You" && !$0.hasPrefix("Speaker") && !$0.hasSuffix("?") }
            .filter { seen.insert($0).inserted }
            .prefix(8).map { $0 }
    }

    private var chipsApps: [String] {
        var seen = Set<String>()
        return store.items.compactMap(\.app).filter { seen.insert($0).inserted }.prefix(6).map { $0 }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("Any time") { window = nil; Task { await runSearch() } }
                    ForEach(Window.allCases) { option in
                        Button(option.rawValue) { window = option; Task { await runSearch() } }
                    }
                } label: {
                    chipLabel(window?.rawValue ?? "Any time", icon: "calendar", on: window != nil)
                }
                ForEach(chipsPeople, id: \.self) { name in
                    Button {
                        SRHaptic.select()
                        person = person == name ? nil : name
                        Task { await runSearch() }
                    } label: {
                        chipLabel(name, icon: "person", on: person == name)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(chipsApps, id: \.self) { name in
                    Button {
                        SRHaptic.select()
                        app = app == name ? nil : name
                        Task { await runSearch() }
                    } label: {
                        chipLabel(name, icon: "app", on: app == name)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("captures-chips")
    }

    private func chipLabel(_ text: String, icon: String, on: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: on ? "checkmark" : icon).font(.system(size: 11, weight: .bold))
            Text(text).font(SR.Text.secondary(13))
        }
        .foregroundStyle(on ? SR.paper : SR.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(on ? SR.accent : Color.clear))
        .srGlass(.paper, in: Capsule())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - The list

    @ViewBuilder
    private var listSections: some View {
        if store.items.isEmpty {
            Section {
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                } else {
                    SREmpty(
                        title: store.error == nil ? "Nothing captured yet" : "Captures didn't load",
                        icon: store.error == nil ? "waveform" : "wifi.exclamationmark",
                        message: store.error ?? "Press Record, or set up the Action Button or a Control Center control in Capture settings."
                    )
                    .listRowBackground(Color.clear)
                }
            }
        } else {
            Section {
                ForEach(store.items) { item in
                    NavigationLink(value: CaptureRef(id: item.id)) {
                        CaptureSummaryRow(item: item)
                    }
                    .srGlassRow()
                    .onAppear {
                        if item.id == store.items.last?.id { Task { await store.loadMore() } }
                    }
                }
            } header: {
                SRSectionLabel(text: "Recorded", trailing: store.items.isEmpty ? nil : "\(store.items.count)")
            }
        }
    }

    // MARK: - Search

    @ViewBuilder
    private var searchSections: some View {
        if searching {
            Section { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
        } else if let searchError {
            Section {
                SREmpty(title: "Search didn't work", icon: "magnifyingglass", message: searchError)
                    .listRowBackground(Color.clear)
            }
        } else if let results {
            if !results.entities.isEmpty {
                Section {
                    ForEach(results.entities) { entity in
                        NavigationLink(value: CaptureEntityRef(id: entity.id, name: entity.name)) {
                            SRRow(
                                title: entity.name,
                                subtitle: entity.captureCount == 1 ? "In 1 capture" : "In \(entity.captureCount) captures",
                                icon: CaptureEntityKind.symbol(entity.type)
                            )
                        }
                        .srGlassRow()
                    }
                } header: {
                    SRSectionLabel(text: "People, places and things")
                }
            }
            Section {
                if results.captures.isEmpty {
                    Text("No capture matches.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .srGlassRow()
                } else {
                    ForEach(results.captures) { item in
                        NavigationLink(value: CaptureRef(id: item.id)) {
                            CaptureSummaryRow(item: item)
                        }
                        .srGlassRow()
                    }
                }
            } header: {
                SRSectionLabel(text: "Captures")
            }
        }
    }

    private func runSearch() async {
        guard !filters.isEmpty else {
            results = nil
            searchError = nil
            return
        }
        searching = true
        defer { searching = false }
        do {
            results = try await store.search(filters)
            searchError = nil
        } catch {
            searchError = error.localizedDescription
        }
    }
}

/// One capture in the list: title, when and how long, who, the app, and
/// how many follow-ups wait.
struct CaptureSummaryRow: View {
    let item: CaptureSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title.isEmpty ? "Untitled capture" : item.title)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                Spacer(minLength: 6)
                if item.actionsOpen > 0 {
                    SRGlassChip(text: item.actionsOpen == 1 ? "1 to decide" : "\(item.actionsOpen) to decide", tone: SR.accent)
                }
            }
            Text(meta)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            if !item.snippet.isEmpty {
                Text(item.snippet)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        var parts: [String] = []
        if let date = item.started {
            parts.append(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
        }
        if let duration = item.durationS { parts.append(CaptureClock.duration(duration)) }
        if item.statusValue != .ready { parts.append(item.statusValue.label) }
        if let app = item.app { parts.append(app) }
        if !item.speakers.isEmpty { parts.append(item.speakers.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

/// A capture still on the phone.
struct PendingCaptureRow: View {
    let item: PendingCapture

    var body: some View {
        SRRow(
            title: item.startedAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()) + " · " + CaptureClock.duration(item.duration),
            subtitle: [item.statusLine, item.screenDeniedReason.map { "Screenshot kept off: \($0)" }]
                .compactMap { $0 }.joined(separator: "\n"),
            icon: item.stage == .process ? "waveform.badge.magnifyingglass" : "icloud.and.arrow.up"
        )
    }
}

import SwiftUI

// v8 (2026-10-21): starting a trip (plan §5.2, mockups 1–3). A short guided
// start replaces the free-text box: where, when, who (the family as chips,
// plus guests), pace, and what the owner's notes already hold, confirmed
// with a tap. Then the research runs where you can see it — named stages,
// ticked as they finish, a Cancel that really cancels — and the trip opens
// on its shapes. "Type instead" keeps the sentence path for anyone who
// prefers to say it.

struct TripStartFlow: View {
    /// The trip made, and whether it was typed (open the conversation) or
    /// guided (open on its shapes).
    let onCreated: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var jobs = TripJobs.shared
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var network = TripNetwork.shared
    @State private var draft = TripStartFlow.freshDraft()
    @State private var roster: [TripStart.Traveller] = []
    @State private var guests: [TripStart.Traveller] = []
    @State private var chosen: Set<String> = []
    @State private var addingGuest = false
    @State private var guestName = ""
    @State private var guestAge = ""
    @State private var notes: [NoteFact] = []
    /// Notes once offered keep the tick the person gave them.
    @State private var offered: Set<String> = []
    @State private var problems: [String] = []
    @State private var typing = false
    @State private var rosterLoaded = false

    private var zone: TimeZone { .current }
    private var researching: Bool {
        jobs.isRunning(TripJobs.startKey) || jobs.startJob[TripJobs.startKey] != nil
            || (!typing && jobs.isRunning(TripJobs.createKey))
    }

    var body: some View {
        NavigationStack {
            Group {
                if researching {
                    TripResearchProgress(summary: summaryLine, destination: draft.destination) {
                        jobs.cancel(TripJobs.startKey)
                        jobs.cancel(TripJobs.createKey)
                    }
                } else {
                    form
                }
            }
            .srGround(.warm)
            .navigationTitle(researching ? TripCityGuideCard.city(draft.destination.isEmpty ? "New trip" : draft.destination) : "New trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(researching ? "Leave — the research carries on" : "Close")
                }
                if !researching {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Type instead") { typing = true }
                            .accessibilityIdentifier("trips.start.typed")
                    }
                }
            }
            .navigationDestination(isPresented: $typing) {
                TripStartTextView { id in finish(id, typed: true) }
            }
        }
        .task {
            loadRoster()
            // Finished while this sheet was closed: open it now.
            if let id = jobs.created[TripJobs.startKey] { finish(id, typed: false) }
        }
        .onChange(of: jobs.created[TripJobs.startKey]) { _, id in
            if let id { finish(id, typed: false) }
        }
        .onChange(of: jobs.created[TripJobs.createKey]) { _, id in
            // An older server took the start as a sentence.
            if let id, !typing { finish(id, typed: true) }
        }
        .accessibilityIdentifier("trips.start")
    }

    // MARK: The form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Plan a trip")
                    .font(SR.Text.hero(30))
                    .foregroundStyle(SR.ink)
                    .accessibilityAddTraits(.isHeader)
                whereAndWhen
                who
                pace
                if !notes.isEmpty { fromNotes }
                VStack(alignment: .leading, spacing: 8) {
                    TripSectionHeading(title: "Anything else?", note: "Optional")
                    TextField("We love food markets; Sam is 9…", text: $draft.text, axis: .vertical)
                        .font(SR.Text.body(16))
                        .lineLimit(1...4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .srGlass(.paper, in: RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
                }
                ForEach(problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(TripPalette.overdue)
                }
                if case .failed(let why) = jobs.states[TripJobs.startKey] {
                    Label("Not started: \(why)", systemImage: "exclamationmark.triangle")
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(TripPalette.overdue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { typing = true } label: {
                    Text("Or just tell the planner in a sentence")
                        .font(SR.Text.title(15))
                        .foregroundStyle(TripPalette.accent)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                if !(network.online || SRDemo.isOn) {
                    Label("Starting a trip needs a connection.", systemImage: "wifi.slash")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                }
                Button { start() } label: { TripButtonLabel("Start planning", fill: true) }
                    .tripPrimary()
                    .disabled(!(network.online || SRDemo.isOn))
                    .accessibilityIdentifier("trips.start.go")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .task(id: notesKey) { await loadNotes() }
    }

    private var whereAndWhen: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                row(icon: "mappin.and.ellipse", label: "Where") {
                    TextField("A city, a town, a region", text: $draft.destination)
                        .font(SR.Text.title(17))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .accessibilityIdentifier("trips.start.where")
                }
                Divider().overlay(SR.divider).padding(.leading, 60)
                row(icon: "calendar", label: "When") {
                    HStack(alignment: .firstTextBaseline) {
                        Text(TripFormat.range(TripStartDraft.localDate(draft.startDate, zone: zone), TripStartDraft.localDate(draft.endDate, zone: zone), zone: zone))
                            .font(SR.Text.title(17))
                            .foregroundStyle(SR.ink)
                        Spacer(minLength: 6)
                        Text(dayCount).font(SR.Text.mono(12)).foregroundStyle(SR.inkMuted)
                    }
                }
                VStack(spacing: 4) {
                    DatePicker("First day", selection: $draft.startDate, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                    DatePicker("Last day", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                }
                .font(SR.Text.body(15))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .onChange(of: draft.startDate) { _, new in
                    if draft.endDate < new { draft.endDate = new }
                }
            }
            .srGlassCard(.paper)
            let past = pastPlaces
            if !past.isEmpty && draft.destination.isEmpty {
                TripFlow(spacing: 6, lineSpacing: 6) {
                    ForEach(past, id: \.self) { place in
                        Button { draft.destination = place } label: { TripChip(place, icon: "clock.arrow.circlepath", style: .tradeoff) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Again: \(place)")
                    }
                }
            }
        }
    }

    private func row<Value: View>(icon: String, label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(SR.Text.title(16))
                .foregroundStyle(TripPalette.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(TripPalette.accentWash))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(SR.Text.label(12)).foregroundStyle(SR.inkMuted)
                value()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 56)
    }

    private var who: some View {
        VStack(alignment: .leading, spacing: 8) {
            TripSectionHeading(title: "Who's going", note: roster.isEmpty ? nil : "From the family")
            TripFlow(spacing: 8, lineSpacing: 8) {
                ForEach(roster + guests, id: \.self) { person in
                    personChip(person)
                }
                Button { addingGuest.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(SR.Text.label(13))
                        Text(roster.isEmpty && guests.isEmpty ? "Add someone" : "Guest").font(SR.Text.title(15))
                    }
                    .foregroundStyle(SR.inkSecondary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .overlay(Capsule().strokeBorder(TripPalette.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a guest")
            }
            if addingGuest {
                HStack(spacing: 8) {
                    TextField("Name", text: $guestName)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .srGlass(.paper, in: Capsule())
                    TextField("Age", text: $guestAge)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 70)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .srGlass(.paper, in: Capsule())
                    Button { addGuest() } label: { TripButtonLabel("Add") }
                        .srButton(.regular)
                        .disabled(guestName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func personChip(_ person: TripStart.Traveller) -> some View {
        let on = chosen.contains(key(person))
        return Button {
            SRHaptic.select()
            if on { chosen.remove(key(person)) } else { chosen.insert(key(person)) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: on ? "checkmark" : "plus")
                    .font(SR.Text.label(11))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(on ? TripPalette.accentFill : SR.inkMuted))
                    .accessibilityHidden(true)
                Text(person.age.map { "\(person.name) \(Int($0))" } ?? person.name)
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
            }
            .padding(.leading, 9)
            .padding(.trailing, 14)
            .frame(minHeight: 36)
            .background(Capsule().fill(on ? TripPalette.accentWash : Color.clear))
            .overlay(Capsule().strokeBorder(on ? TripPalette.accentLine : TripPalette.line, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.name)
        .accessibilityValue(on ? "Going" : "Not going")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var pace: some View {
        VStack(alignment: .leading, spacing: 8) {
            TripSectionHeading(title: "Pace", note: Self.paceNote(draft.pace))
            Picker("Pace", selection: $draft.pace) {
                Text("Relaxed").tag("relaxed")
                Text("Normal").tag("normal")
                Text("Packed").tag("packed")
            }
            .pickerStyle(.segmented)
        }
    }

    static func paceNote(_ pace: String) -> String {
        switch pace {
        case "relaxed": return "About 3 stops a day"
        case "packed": return "About 7 stops a day"
        default: return "About 5 stops a day"
        }
    }

    private var fromNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            TripSectionHeading(title: "From your notes", note: "Ticked ones go in")
            VStack(spacing: 0) {
                ForEach(Array(notes.enumerated()), id: \.element.id) { i, note in
                    let on = draft.confirmNotes.contains(note.id)
                    Button {
                        SRHaptic.select()
                        if on { draft.confirmNotes.remove(note.id) } else { draft.confirmNotes.insert(note.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: Self.noteSymbol(note.kind))
                                .font(SR.Text.title(15))
                                .foregroundStyle(TripPalette.accent)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(TripPalette.accentWash))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.label).font(SR.Text.title(15)).foregroundStyle(SR.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let detail = note.detail {
                                    Text(detail + (on ? " · confirmed" : "")).font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 6)
                            if on {
                                Image(systemName: "checkmark")
                                    .font(SR.Text.label(13))
                                    .foregroundStyle(SR.paper)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(TripPalette.confirmed))
                            } else {
                                Text("Confirm")
                                    .font(SR.Text.title(14))
                                    .foregroundStyle(TripPalette.accent)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 34)
                                    .background(Capsule().fill(TripPalette.accentWash))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(on ? "Confirmed" : "Not included")
                    .accessibilityHint(on ? "Leaves it out" : "Includes it")
                    if i < notes.count - 1 { Divider().overlay(SR.divider).padding(.leading, 60) }
                }
            }
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("trips.start.notes")
    }

    static func noteSymbol(_ kind: String) -> String {
        switch kind {
        case "stay": return "bed.double"
        case "transport": return "airplane"
        case "booking": return "ticket"
        case "traveller": return "person"
        default: return "note.text"
        }
    }

    // MARK: Words

    private var dayCount: String {
        let a = TripStartDraft.localDate(draft.startDate, zone: zone), b = TripStartDraft.localDate(draft.endDate, zone: zone)
        let n = (TripClock(zone.identifier).days(from: a, to: b) ?? 0) + 1
        return n == 1 ? "1 day" : "\(n) days"
    }

    /// "26–30 Oct · 4 people · Normal pace".
    private var summaryLine: String {
        let a = TripStartDraft.localDate(draft.startDate, zone: zone), b = TripStartDraft.localDate(draft.endDate, zone: zone)
        let n = draft.travellers.count
        return [TripFormat.range(a, b, zone: zone), n == 0 ? nil : (n == 1 ? "1 person" : "\(n) people"), draft.pace.capitalized + " pace"]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// Places of earlier trips, for one tap.
    private var pastPlaces: [String] {
        var seen = Set<String>()
        return store.summaries.map(\.destination).filter { seen.insert($0).inserted }.prefix(4).map { $0 }
    }

    // MARK: Doing

    private func key(_ t: TripStart.Traveller) -> String { t.personId ?? "guest:\(t.name)" }

    private func loadRoster() {
        guard !rosterLoaded else { return }
        rosterLoaded = true
        let people = SRDemo.isOn
            ? (SRDemoFixtures.householdView(now: Date()).view?.people ?? [])
            : (FamilyViewCache.load()?.view.people ?? [])
        roster = people.map { TripStart.Traveller(name: $0.name, age: nil, personId: $0.subject) }
        chosen = Set(roster.map(key))
    }

    private func addGuest() {
        let name = guestName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let guest = TripStart.Traveller(name: name, age: Double(guestAge.trimmingCharacters(in: .whitespaces)), personId: nil)
        guests.append(guest)
        chosen.insert(key(guest))
        guestName = ""
        guestAge = ""
        addingGuest = false
    }

    /// Notes are looked up once there is a place and dates — owner only;
    /// anyone else gets none.
    private var notesKey: String {
        "\(draft.destination.trimmingCharacters(in: .whitespaces).lowercased())|\(TripStartDraft.localDate(draft.startDate, zone: zone))|\(TripStartDraft.localDate(draft.endDate, zone: zone))"
    }

    private func loadNotes() async {
        let place = draft.destination.trimmingCharacters(in: .whitespaces)
        guard place.count >= 2 else { notes = []; return }
        // Typing: wait for a pause.
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled else { return }
        let found = await TripsAPI.notes(destination: place, startDate: TripStartDraft.localDate(draft.startDate, zone: zone),
                                         endDate: TripStartDraft.localDate(draft.endDate, zone: zone))
        guard !Task.isCancelled else { return }
        // Ticked by default, the first time each is offered.
        for note in found where !offered.contains(note.id) {
            offered.insert(note.id)
            draft.confirmNotes.insert(note.id)
        }
        notes = found
    }

    private func start() {
        draft.travellers = (roster + guests).filter { chosen.contains(key($0)) }
        problems = draft.problems(zone: zone)
        guard problems.isEmpty else { SRHaptic.bad(); return }
        SRHaptic.tap()
        jobs.start(draft.start(zone: zone, notes: notes), fallback: draft.sentence(zone: zone))
    }

    private func finish(_ id: String, typed: Bool) {
        jobs.clear(TripJobs.startKey)
        jobs.clear(TripJobs.createKey)
        dismiss()
        onCreated(id, typed)
    }

    static func freshDraft() -> TripStartDraft {
        let calendar = Calendar.current
        // The demo starts where its planning trip is: Rome, five days out.
        let ahead = SRDemo.isOn ? 5 : 14
        let start = calendar.date(byAdding: .day, value: ahead, to: calendar.startOfDay(for: Date())) ?? Date()
        let end = calendar.date(byAdding: .day, value: SRDemo.isOn ? 4 : 3, to: start) ?? start
        var draft = TripStartDraft(startDate: start.addingTimeInterval(12 * 3600), endDate: end.addingTimeInterval(12 * 3600))
        if SRDemo.isOn { draft.destination = "Rome, Italy" }
        return draft
    }
}

// MARK: - Research, where you can see it

/// The research as it runs: a line per stage, ticked when it is done, with
/// what it found ("Found 38 places", "3 need booking — …"). Leave and it
/// carries on; Cancel stops it on the server.
struct TripResearchProgress: View {
    let summary: String
    let destination: String
    let onCancel: () -> Void
    @ObservedObject private var jobs = TripJobs.shared
    @ScaledMetric(relativeTo: .headline) private var tick: CGFloat = 26

    private var job: StagedJob? { jobs.startJob[TripJobs.startKey] }
    private var progress: TripDecisions.StartProgress { TripDecisions.progress(job) }
    private var failure: String? {
        if case .failed(let why) = jobs.states[TripJobs.startKey] { return why }
        if case .failed(let why) = jobs.states[TripJobs.createKey] { return why }
        return progress.failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary)
                        .font(SR.Text.label(12))
                        .foregroundStyle(TripPalette.accent)
                    Text("Researching \(TripCityGuideCard.city(destination))")
                        .font(SR.Text.hero(30))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Usually 1 to 3 minutes. What it finds is kept for this trip.")
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    if progress.lines.isEmpty {
                        line(id: "setup", title: "Setting up the trip…", detail: nil, state: .running, last: true)
                    }
                    ForEach(Array(progress.lines.enumerated()), id: \.element.id) { i, l in
                        line(id: l.id, title: title(l), detail: detail(l), state: l.state, last: i == progress.lines.count - 1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .srGlassCard(.paper)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(progress.total > 0 ? "Research, \(progress.count)" : "Research starting")
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(TripPalette.overdue)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Label("You can leave — we'll let you know when it's ready.", systemImage: "bell")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { SRHaptic.tap(); onCancel() } label: { TripButtonLabel(failure == nil ? "Cancel" : "Start again") }
                    .srButton(.regular)
                    .accessibilityIdentifier("trips.start.cancel")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .accessibilityIdentifier("trips.start.research")
    }

    /// Done: what it found; running: what it is doing.
    private func title(_ l: TripDecisions.StartProgress.Line) -> String {
        switch l.state {
        case .done: return l.detail ?? l.label
        case .running: return l.label + "…"
        default: return l.label
        }
    }

    private func detail(_ l: TripDecisions.StartProgress.Line) -> String? {
        switch l.state {
        case .done: return nil
        default: return l.detail
        }
    }

    private func line(id: String, title: String, detail: String?, state: JobStageState, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                icon(state)
                    .frame(width: tick, height: tick)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SR.Text.title(15))
                        .foregroundStyle(state == .waiting || state == .skipped ? SR.inkMuted : SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .accessibilityValue(Self.spoken(state))
            if !last { Divider().overlay(SR.divider) }
        }
    }

    @ViewBuilder
    private func icon(_ state: JobStageState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(SR.Text.label(12))
                .foregroundStyle(SR.paper)
                .frame(width: tick, height: tick)
                .background(Circle().fill(TripPalette.confirmed))
        case .running:
            ProgressView().tint(TripPalette.accent)
        case .failed:
            Image(systemName: "xmark.circle.fill").font(SR.Text.title(17)).foregroundStyle(TripPalette.overdue)
        case .skipped:
            Image(systemName: "minus.circle").font(SR.Text.title(17)).foregroundStyle(SR.inkMuted)
        case .waiting, .unknown:
            Circle().strokeBorder(TripPalette.line, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        }
    }

    static func spoken(_ state: JobStageState) -> String {
        switch state {
        case .done: return "Done"
        case .running: return "Working on it"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        case .waiting, .unknown: return "Waiting"
        }
    }
}

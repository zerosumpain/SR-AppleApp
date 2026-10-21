import SwiftUI

// v8 (2026-10-21): the trip page before you go — a planning home (plan
// §5.3, mockups 4a/4b/8). Top to bottom: the brief as chips (each fact's
// source, guesses in amber with Right / Change), the quick questions, the
// planner's open proposals (trip shapes first), the days, what to book by
// when — and "Tell the planner…" fixed at the bottom, which opens the
// conversation at half height so the plan stays in view.
//
// `TripScreen` (TripsScreens.swift) lays these out by phase; this file
// holds the pieces and the sheets they open.

// MARK: - The brief

/// What the planner knows, as chips. A tap on one an editor can change opens
/// the brief at it; an assumed one offers Right (keep it, now as said) or
/// Change. Members read it.
struct TripBriefStrip: View {
    let tripId: String
    let brief: TripBrief
    /// Open the brief sheet, at an item.
    var onEdit: (BriefItem) -> Void
    /// Change an assumption that is not a field (dinner times…): in words.
    var onTalk: (String) -> Void
    @ObservedObject private var store = TripStore.shared
    @State private var failure: String?

    private var decides: Bool { TripDecisions.canDecide(store.bundles[tripId]?.can ?? .owner) }

    /// Preferences and constraints stay off the phone (no memory on the wire);
    /// what is left is the trip's facts.
    private var items: [BriefItem] {
        brief.items.filter { $0.kind != "preference" && $0.kind != "constraint" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TripFlow(spacing: 6, lineSpacing: 6) {
                ForEach(items) { item in chip(item) }
            }
            if !brief.missing.isEmpty {
                Text("Still to find out: " + brief.missing.joined(separator: "; "))
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure {
                Text(failure).font(SR.Text.secondary(13)).foregroundStyle(TripPalette.overdue)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip.brief")
    }

    @ViewBuilder
    private func chip(_ item: BriefItem) -> some View {
        let look = TripChip(item.label, icon: Self.symbol(item), style: .brief(item.origin))
        if decides && item.isAssumed {
            Menu {
                Section(item.detail ?? item.note ?? "The planner assumed this so it could carry on.") {
                    Button { confirm(item) } label: { Label("Right", systemImage: "checkmark") }
                    Button { change(item) } label: { Label("Change", systemImage: "pencil") }
                }
            } label: { look }
            .accessibilityLabel("\(item.label), assumed")
            .accessibilityHint("Say if it's right, or change it")
        } else if decides && item.editable {
            Button { SRHaptic.tap(); onEdit(item) } label: { look }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.label), \(item.origin.label.lowercased())")
                .accessibilityHint("Change it")
        } else {
            look
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.label), \(item.origin.label.lowercased())")
        }
    }

    private func confirm(_ item: BriefItem) {
        SRHaptic.ok()
        failure = nil
        Task { if let why = await store.patchBrief(.confirm(key: item.key), tripId: tripId) { failure = why } }
    }

    private func change(_ item: BriefItem) {
        if Self.patchable.contains(item.kind) {
            onEdit(item)
        } else {
            onTalk("About “\(item.label)”: ")
        }
    }

    /// The kinds the brief sheet edits directly; anything else is said in words.
    static let patchable: Set<String> = ["dates", "travellers", "pace", "destination"]

    static func symbol(_ item: BriefItem) -> String {
        switch item.kind {
        case "destination": return "mappin.and.ellipse"
        case "dates": return "calendar"
        case "travellers": return "person.2"
        case "pace": return "figure.walk"
        case "modes": return "tram"
        case "stay": return "bed.double"
        case "transport": return "airplane"
        case "booking": return "ticket"
        case "must": return "star"
        case "assumption": return "questionmark.circle"
        default: return "info.circle"
        }
    }
}

/// "Tell the planner…": fixed at the bottom of the trip. What is typed
/// comes back as a change to approve, a choice of options or a question.
struct TripTellPlannerBar: View {
    let canEdit: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var mic: CGFloat = 40

    var body: some View {
        Button { SRHaptic.tap(); action() } label: {
            HStack(spacing: 10) {
                Text(canEdit ? "Tell the planner…" : "Ask the planner…")
                    .font(SR.Text.body(17))
                    .foregroundStyle(SR.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "mic.fill")
                    .font(SR.Text.title(16))
                    .foregroundStyle(TripPalette.onAccent)
                    .frame(width: mic, height: mic)
                    .background(Circle().fill(TripPalette.accentFill))
                    .accessibilityHidden(true)
            }
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .frame(minHeight: 52)
            .contentShape(Capsule())
            .srGlass(.paper, in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityLabel(canEdit ? "Tell the planner" : "Ask the planner")
        .accessibilityHint("Opens the conversation at half height, over the plan")
        .accessibilityIdentifier("trip.tellPlanner")
    }
}

/// The brief, editable: dates, who, pace — straight to the server, no chat —
/// and every fact the planner holds with where it came from.
struct TripBriefSheet: View {
    let tripId: String
    /// The item tapped, to scroll to.
    var focus: String?
    var onTalk: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TripStore.shared
    @State private var start = Date()
    @State private var end = Date()
    @State private var travellers: [TripStart.Traveller] = []
    @State private var newName = ""
    @State private var newAge = ""
    @State private var pace = "normal"
    @State private var loaded = false
    @State private var failure: String?

    private var bundle: TripBundle? { store.bundles[tripId] }
    private var zone: TimeZone { TripClock(bundle?.trip.timeZone ?? "UTC").zone }
    private var busy: Bool { store.isBusy("brief:\(tripId)") }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                Form {
                    Section("When") {
                        DatePicker("First day", selection: $start, displayedComponents: .date)
                        DatePicker("Last day", selection: $end, in: start..., displayedComponents: .date)
                        Button { save(.dates(start: day(start), end: day(end))) } label: { TripButtonLabel("Save the dates") }
                            .disabled(busy || (day(start) == bundle?.trip.startDate && day(end) == bundle?.trip.endDate))
                    }
                    .environment(\.timeZone, zone)
                    .id("dates")

                    Section("Who's going") {
                        ForEach(Array(travellers.enumerated()), id: \.offset) { i, t in
                            HStack {
                                Text(t.age.map { "\(t.name), \(Int($0))" } ?? t.name).font(SR.Text.body(16))
                                Spacer()
                                Button(role: .destructive) { travellers.remove(at: i) } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(TripPalette.overdue)
                                .accessibilityLabel("Take \(t.name) off the trip")
                            }
                        }
                        HStack {
                            TextField("Name", text: $newName).textInputAutocapitalization(.words)
                            TextField("Age", text: $newAge).keyboardType(.numberPad).frame(maxWidth: 70)
                            Button("Add") { add() }
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        Button { save(.travellers(travellers)) } label: { TripButtonLabel("Save who's going") }
                            .disabled(busy || travellers.isEmpty)
                    }
                    .id("travellers")

                    Section("Pace") {
                        Picker("Pace", selection: $pace) {
                            Text("Relaxed").tag("relaxed")
                            Text("Normal").tag("normal")
                            Text("Packed").tag("packed")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: pace) { _, new in
                            guard loaded, new != bundle?.trip.pace.rawValue else { return }
                            save(.pace(new))
                        }
                    }
                    .id("pace")

                    if let brief = bundle?.brief {
                        Section {
                            ForEach(brief.items.filter { $0.kind != "preference" && $0.kind != "constraint" }) { item in
                                factRow(item).id(item.key)
                            }
                        } header: {
                            Text("What the planner knows")
                        } footer: {
                            Text("You said · From your notes · Found · Assumed — where each fact came from. An assumption is the planner's working guess, so it can carry on; say if it's right.")
                        }
                    }
                    if let failure {
                        Section { Text(failure).foregroundStyle(TripPalette.overdue) }
                    }
                }
                .onAppear {
                    load()
                    if let focus { scroller.scrollTo(Self.anchor(focus), anchor: .top) }
                }
            }
            .scrollContentBackground(.hidden)
            .srGround(.warm)
            .navigationTitle("The brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { if busy { ProgressView() } }
            }
        }
        .accessibilityIdentifier("trip.brief.sheet")
    }

    /// The section (or fact row) a brief key opens at: the three fields have
    /// sections of their own; anything else is its row.
    static func anchor(_ key: String) -> String { key }

    private func factRow(_ item: BriefItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label(item.label, systemImage: TripBriefStrip.symbol(item))
                    .font(SR.Text.title(15))
                    .foregroundStyle(item.isAssumed ? TripPalette.assumed : SR.ink)
                Spacer(minLength: 6)
                Text(item.origin.label)
                    .font(SR.Text.label(12))
                    .foregroundStyle(item.isAssumed ? TripPalette.assumed : SR.inkMuted)
            }
            if let detail = item.detail {
                Text(detail).font(SR.Text.secondary(13)).foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The owner's site shows the note; the phone gets it only for
            // facts that are not from memory.
            if let note = item.note {
                Text(note).font(SR.Text.secondary(12)).foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if item.isAssumed && TripDecisions.canDecide(bundle?.can ?? .owner) {
                HStack(spacing: 10) {
                    Button { save(.confirm(key: item.key)) } label: { TripButtonLabel("Right", icon: "checkmark") }
                        .srButton(.regular)
                    Button {
                        if TripBriefStrip.patchable.contains(item.kind) {
                            // The fields above edit it.
                        } else {
                            dismiss()
                            onTalk("About “\(item.label)”: ")
                        }
                    } label: { TripButtonLabel("Change", icon: "pencil") }
                        .srButton(.regular)
                }
                .controlSize(.small)
                .disabled(busy)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func day(_ date: Date) -> String { TripClock(zone.identifier).localDate(date) }

    private func load() {
        guard !loaded, let bundle else { return }
        let clock = TripClock(bundle.trip.timeZone)
        start = clock.date(bundle.trip.startDate, minutes: 12 * 60) ?? Date()
        end = clock.date(bundle.trip.endDate, minutes: 12 * 60) ?? Date()
        travellers = (bundle.knownProfile?.travellers ?? []).map { TripStart.Traveller(name: $0.name, age: $0.age, personId: $0.personId) }
        pace = bundle.trip.pace.rawValue
        loaded = true
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        travellers.append(TripStart.Traveller(name: name, age: Double(newAge.trimmingCharacters(in: .whitespaces)), personId: nil))
        newName = ""
        newAge = ""
    }

    private func save(_ patch: BriefPatch) {
        failure = nil
        Task {
            if let why = await store.patchBrief(patch, tripId: tripId) {
                SRHaptic.bad()
                failure = why
            } else {
                SRHaptic.ok()
            }
        }
    }
}

// MARK: - The days, as a group

/// The days in one glass group: each a row — its number in its map colour,
/// the date, the weather, the stops and how full it is in words. A tap opens
/// the map-led day.
struct TripDaysGroup: View {
    let days: [PlannedDay]
    let bundle: TripBundle
    let today: String
    let open: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.date) { i, day in
                Button { SRHaptic.tap(); open(day.date) } label: {
                    HStack(spacing: 8) {
                        TripDayListRow(number: i + 1, day: day, bundle: bundle, today: today)
                        Image(systemName: "chevron.right")
                            .font(SR.Text.label(12))
                            .foregroundStyle(SR.inkMuted)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trip-day-\(day.date)")
                if i < days.count - 1 {
                    Divider().overlay(SR.divider).padding(.leading, 14)
                }
            }
        }
        .srGlassCard(.paper)
    }
}

// MARK: - Trip shapes

/// Two or three whole plans to swipe between, each solved and checked: its
/// days a line each, its trade-offs, what it leaves out, and "Use this plan".
/// Shown after a guided start, and from the planning home while any are open.
struct TripShapePager: View {
    let tripId: String
    var onChange: ((TripChangeRecord) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TripStore.shared
    @State private var current: String?
    @State private var compare: ComparePair?
    @State private var message: String?
    @State private var asked = false

    struct ComparePair: Hashable {
        let left: TripProposal
        let right: TripProposal
    }

    private var bundle: TripBundle? { store.bundles[tripId] }
    private var shapes: [TripProposal] {
        (bundle?.proposals ?? []).filter { $0.kind == .shape && $0.status == .open }
    }
    private var index: Int { shapes.firstIndex { $0.id == current } ?? 0 }
    private var zone: TimeZone { TripClock(bundle?.trip.timeZone ?? "UTC").zone }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(shapes.isEmpty ? "Ways to do the trip" : (shapes.count == 1 ? "A way to do the trip" : "\(shapes.count) ways to do the trip"))
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                    Text("Each is a whole plan, checked against opening hours and walking times.")
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                if shapes.isEmpty {
                    empty.padding(.horizontal, 20)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 10) {
                            ForEach(shapes) { shape in
                                card(shape)
                                    .containerRelativeFrame(.horizontal) { width, _ in shapes.count > 1 ? max(240, width - 48) : width - 32 }
                                    .id(shape.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $current)
                    if shapes.count > 1 {
                        TripPageDots(count: shapes.count, current: index).frame(maxWidth: .infinity)
                    }
                }
                if let message {
                    Text(message).font(SR.Text.secondary(13)).foregroundStyle(TripPalette.overdue).padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 8)
        }
        .srGround(.warm)
        .navigationTitle(bundle.map { TripCityGuideCard.city($0.trip.destination) } ?? "Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Later") { dismiss() } }
            if shapes.count >= 2 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Compare") {
                        let other = index + 1 < shapes.count ? index + 1 : 0
                        compare = ComparePair(left: shapes[index], right: shapes[other == index ? 1 : other])
                    }
                    .accessibilityIdentifier("trip.compare.open")
                }
            }
        }
        .navigationDestination(item: $compare) { pair in
            TripCompareView(left: pair.left, right: pair.right, tripId: tripId) { change in
                onChange?(change)
                dismiss()
            }
        }
        .task {
            // Just made: the shapes may still be drafting.
            if shapes.isEmpty { await store.refreshDecisions(tripId) }
        }
        .accessibilityIdentifier("trips.shapes")
    }

    @ViewBuilder
    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.isBusy("shapes:\(tripId)") ? "Drafting ways to do the trip…" : "No trip shapes are open. Ask for some, or carry on with the plan as it is.")
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if TripDecisions.canDecide(bundle?.can ?? .owner) {
                Button {
                    Task {
                        let (_, failure) = await store.requestProposals(.shapes, tripId: tripId, busyKey: "shapes:\(tripId)")
                        message = failure
                    }
                } label: { TripButtonLabel("Draft three ways to do it", icon: "sparkles") }
                    .srButton(.regular)
                    .disabled(store.isBusy("shapes:\(tripId)"))
            }
        }
    }

    private func card(_ p: TripProposal) -> some View {
        let currency = TripDecisions.currencySymbol(timeZone: bundle?.trip.timeZone ?? "")
        let busy = store.isBusy(p.id)
        return VStack(alignment: .leading, spacing: 12) {
            Text(p.shape?.headline ?? p.title)
                .font(SR.Text.display(23))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !p.why.isEmpty {
                Text(p.why)
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !p.preview.isEmpty {
                TripSceneMap(scene: TripMapScene.overview(p.preview, stays: bundle?.stays ?? []), interactive: false) { _ in }
                    .frame(height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
                    .accessibilityLabel("Map of this plan, a colour a day")
            }
            if let days = p.shape?.days, !days.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Circle().fill(TripPalette.day(i)).frame(width: 9, height: 9).accessibilityHidden(true)
                            Text(Self.weekday(day.date, zone: zone))
                                .font(SR.Text.title(14))
                                .foregroundStyle(SR.ink)
                                .frame(minWidth: 32, alignment: .leading)
                            Text(day.line)
                                .font(SR.Text.secondary(14))
                                .foregroundStyle(SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            TripFlow(spacing: 6, lineSpacing: 6) {
                ForEach(TripDecisions.chips(p, currencySymbol: currency)) { chip in
                    TripChip(chip.text, icon: chip.symbol, style: chip.id == "quiet" ? .highlight : (chip.tone == .warn ? .warning : .tradeoff))
                }
            }
            .accessibilityElement(children: .combine)
            if let leaves = p.shape?.leavesOut, !leaves.isEmpty {
                Label("Leaves out: " + TripDecisions.list(leaves), systemImage: "minus.circle")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if TripDecisions.canDecide(bundle?.can ?? .owner) {
                Button { use(p) } label: {
                    if busy { ProgressView().tint(TripPalette.onAccent).frame(maxWidth: .infinity) } else {
                        TripButtonLabel("Use this plan", fill: true)
                    }
                }
                .tripPrimary()
                .disabled(busy)
                .accessibilityIdentifier("trips.shapes.use")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 480, alignment: .topLeading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip.proposal.card")
    }

    static func weekday(_ date: String, zone: TimeZone) -> String {
        String(TripFormat.day(date, zone: zone).prefix(3))
    }

    private func use(_ p: TripProposal) {
        SRHaptic.tap()
        message = nil
        Task {
            switch await store.accept(p, tripId: tripId) {
            case .done(let change):
                SRHaptic.ok()
                if let change { onChange?(change) }
                dismiss()
            case .stale:
                message = "The plan moved on while you were choosing — this is the plan now."
            case .failed(let why):
                SRHaptic.bad()
                message = why
            }
        }
    }
}

// MARK: - The plan's history

/// Every version of the plan, newest first; one saved with its facts can be
/// put back (a new version, never a rewrite).
struct TripVersionsView: View {
    let tripId: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TripStore.shared
    @State private var versions: [TripVersionRow] = []
    @State private var loading = true
    @State private var failure: String?

    var body: some View {
        List {
            if loading {
                ProgressView().frame(maxWidth: .infinity).srPlainRow()
            }
            ForEach(versions) { v in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Version \(v.version)").font(SR.Text.title(16)).foregroundStyle(SR.ink)
                        Spacer()
                        Text(when(v.createdAt)).font(SR.Text.mono(12)).foregroundStyle(SR.inkMuted)
                    }
                    ForEach(v.changes.prefix(3), id: \.self) { line in
                        Text(line).font(SR.Text.secondary(13)).foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if v.restorable && v.version != versions.first?.version {
                        Button { restore(v) } label: { TripButtonLabel("Put this version back", icon: "arrow.uturn.backward") }
                            .srButton(.regular)
                            .controlSize(.small)
                            .disabled(store.isBusy("undo:\(tripId)"))
                    }
                }
                .padding(.vertical, 6)
                .srPlainRow()
            }
            if let failure {
                Text(failure).font(SR.Text.secondary(13)).foregroundStyle(TripPalette.overdue).srPlainRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .srGround(.quiet)
        .navigationTitle("Plan history")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        .task { await load() }
        .accessibilityIdentifier("trip.versions")
    }

    private func when(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        return date.map { $0.formatted(.relative(presentation: .named)) } ?? ""
    }

    private func load() async {
        do {
            versions = try await TripsAPI.versions(trip: tripId)
        } catch {
            failure = error.localizedDescription
        }
        loading = false
    }

    private func restore(_ v: TripVersionRow) {
        Task {
            if let why = await store.restore(v.version, tripId: tripId) {
                failure = why
            } else {
                SRHaptic.ok()
                dismiss()
            }
        }
    }
}

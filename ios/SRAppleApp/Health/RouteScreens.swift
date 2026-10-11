import SwiftUI
import MapKit

// Planned routes, pushed onto the Health tab's stack — /health/plan and
// /health/routes on the phone.
//
// Plan → pick one of three → save → the route's own screen. Following it,
// taking it offline and sharing it live hang off that last screen.

// MARK: - Saved routes

struct RoutesScreen: View {
    @StateObject private var store = RoutesStore()
    @ObservedObject private var queue = RecordingQueue.shared
    @ObservedObject private var offline = OfflineMaps.shared

    var body: some View {
        List {
            // The headline, and the screen's one orange action: plan another.
            RoutesBand(
                saved: store.rows,
                loaded: store.state == .loaded,
                offline: offline.saved.count,
                waiting: queue.pending.count
            )
            .srInkRow()

            Section {
                NavigationLink(value: HealthRoute.nearbyRoutes) {
                    SRRow(title: "Published routes nearby", subtitle: "Waymarked trails within 15 km", icon: "signpost.right.and.left")
                }
                .srGlassRow()
                if !offline.saved.isEmpty {
                    NavigationLink(value: HealthRoute.offlineMaps) {
                        SRRow(
                            title: "Offline maps",
                            subtitle: "\(offline.saved.count) route\(offline.saved.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: Int64(offline.totalBytes), countStyle: .file))",
                            icon: "arrow.down.circle"
                        )
                    }
                    .srGlassRow()
                }
            }

            if !queue.pending.isEmpty {
                Section {
                    SRRow(
                        title: queue.pending.count == 1 ? "1 walk waiting to upload" : "\(queue.pending.count) walks waiting to upload",
                        subtitle: queue.lastError ?? "Sent when there is signal.",
                        icon: "icloud.and.arrow.up"
                    )
                    .srGlassRow()
                }
            }

            if store.rows.isEmpty {
                if store.state == .loaded {
                    SREmpty(
                        title: "No saved routes",
                        icon: "map",
                        message: "Plan one, or save a published route, and it appears here."
                    )
                    .srBareRow()
                } else {
                    TrailStateView(state: store.state, noun: "route", retry: reload)
                        .srBareRow()
                }
            } else {
                Section {
                    ForEach(store.rows) { row in
                        NavigationLink(value: RouteRef(id: row.id, name: row.name)) {
                            RouteListRow(row: row, offline: offline.saved.contains { $0.id == row.id })
                        }
                        .srGlassRow()
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await store.delete(row.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    SRSectionLabel(text: "Saved", trailing: "\(store.rows.count)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.vital)
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable {
            await store.load()
            await queue.flush()
        }
        .task {
            await store.load()
            await queue.flush()
        }
    }

    private func reload() {
        Task { await store.load() }
    }
}

struct RouteListRow: View {
    let row: PlannedRouteSummary
    /// Its map is on the phone, so it works with no signal. Said on the row,
    /// because that is the thing to know before setting out.
    var offline = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Sport.icon(row.sport))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(SR.accent)
                .frame(width: 26, height: 26)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(row.summaryLine)
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.inkSecondary)
                if row.source == "imported" || offline {
                    HStack(spacing: 10) {
                        if row.source == "imported" {
                            Text("PUBLISHED ROUTE")
                        }
                        if offline {
                            Label("OFFLINE", systemImage: "arrow.down.circle.fill")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .font(SR.Text.mono())
                    .tracking(0.8)
                    .foregroundStyle(SR.inkMuted)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, SR.rowPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Plan

struct PlanRouteScreen: View {
    @EnvironmentObject private var router: Router
    @StateObject private var planner = RoutePlanner()
    @State private var placing: Pin = .start
    @State private var name = ""
    @FocusState private var typing: Bool

    enum Pin { case start, finish }

    var body: some View {
        List {
            Section {
                PlanMap(planner: planner, placing: placing)
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("plan-map")
                if planner.plan == nil {
                    pinHint
                }
            }

            if let plan = planner.plan {
                candidates(plan)
            } else {
                describe
                form
            }
        }
        .listStyle(.insetGrouped)
        .srPaper()
        .navigationTitle(planner.plan == nil ? "Plan a route" : "Pick one")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if planner.plan != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Change") { planner.clearPlan() }
                }
            }
        }
        .alert("Route planner", isPresented: Binding(
            get: { planner.error != nil },
            set: { if !$0 { planner.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(planner.error ?? "")
        }
        .task {
            await planner.locate()
            await planner.suggest()
        }
        .onChange(of: planner.sport) { _, _ in Task { await planner.suggest() } }
    }

    @ViewBuilder
    private var pinHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            if planner.shape == .toPlace {
                Picker("Tap the map to place", selection: $placing) {
                    Text("Start").tag(Pin.start)
                    Text("Finish").tag(Pin.finish)
                }
                .pickerStyle(.segmented)
            }
            Text(pinLine)
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .srGlassRow()
        .padding(.vertical, 6)
        .onChange(of: planner.shape) { _, shape in placing = shape == .toPlace && planner.finish == nil ? .finish : .start }
    }

    private var pinLine: String {
        if planner.busy == .locating { return "Finding where you are…" }
        let from = planner.start == nil ? "No start yet" : "From \(planner.startLabel)"
        if planner.shape == .loop { return "\(from). Tap the map to move the start." }
        let to = planner.finish == nil ? "no finish yet" : "to \(planner.finishLabel ?? "the pin")"
        return "\(from), \(to). Tap the map to place the \(placing == .start ? "start" : "finish")."
    }

    // MARK: Words

    private var describe: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                TextField("“8 km hilly loop from the station”", text: $planner.request, axis: .vertical)
                    .font(SR.Text.body())
                    .lineLimit(1...3)
                    .focused($typing)
                    .submitLabel(.go)
                    .onSubmit { Task { await planner.interpret() } }
                    .accessibilityIdentifier("plan-request")
                HStack {
                    if planner.busy == .reading { ProgressView().tint(SR.accent) }
                    Spacer()
                    Button("Read it") {
                        typing = false
                        Task { await planner.interpret() }
                    }
                    .srButton(.regular)
                    .disabled(planner.request.trimmingCharacters(in: .whitespaces).isEmpty || planner.busy != nil)
                }
                ForEach(planner.reading, id: \.self) { line in
                    Text(line)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .srGlassRow()
            .padding(.vertical, 6)
        } header: {
            SRSectionLabel(text: "Describe it")
        } footer: {
            Text("This only fills the form below. Nothing is planned until you press Plan.")
                .font(SR.Text.secondary(12))
                .foregroundStyle(SR.inkMuted)
        }
    }

    // MARK: Form

    private var form: some View {
        Section {
            Picker("Sport", selection: $planner.sport) {
                ForEach(RouteSport.allCases) { s in
                    Label(s.label, systemImage: s.icon).tag(s)
                }
            }
            .srGlassRow()

            Picker("Shape", selection: $planner.shape) {
                ForEach(RoutePlanner.Shape.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .srGlassRow()

            if planner.shape == .loop {
                VStack(alignment: .leading, spacing: 4) {
                    Stepper(value: $planner.distanceKm, in: 0.5...100, step: planner.distanceKm < 10 ? 0.5 : 1) {
                        HStack {
                            Text("Distance").font(SR.Text.body())
                            Spacer()
                            Text("\(TrailFormat.km(fromKm: planner.distanceKm)) km")
                                .font(SR.Text.mono(15))
                                .foregroundStyle(SR.ink)
                        }
                    }
                    if let suggestion = planner.suggestion {
                        Text(suggestion)
                            .font(SR.Text.secondary(12))
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .srGlassRow()
            }

            Picker("Climb", selection: $planner.climb) {
                ForEach(RoutePlanner.Climb.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .srGlassRow()

            if planner.climb != .any {
                Toggle("Spread the climbing evenly", isOn: $planner.steady)
                    .font(SR.Text.body())
                    .tint(SR.accent)
                    .srGlassRow()
            }
            Toggle("Allow out-and-back stretches", isOn: $planner.allowOutAndBack)
                .font(SR.Text.body())
                .tint(SR.accent)
                .srGlassRow()

            Button {
                typing = false
                Task { await planner.planRoute() }
            } label: {
                HStack {
                    Spacer()
                    if planner.busy == .planning {
                        ProgressView().tint(SR.paper)
                        Text("Planning — up to a minute").font(SR.Text.body())
                    } else {
                        Text("Plan").font(SR.Text.body())
                    }
                    Spacer()
                }
            }
            .srButton(.prominent)
            .disabled(!planner.canPlan)
            .srBareRow()
            .padding(.vertical, 8)
            .accessibilityIdentifier("plan-go")
        } header: {
            SRSectionLabel(text: "The spec")
        }
    }

    // MARK: Candidates

    @ViewBuilder
    private func candidates(_ plan: RoutePlan) -> some View {
        Section {
            ForEach(plan.candidates) { c in
                Button {
                    SRHaptic.tap()
                    planner.chosen = c.rank
                } label: {
                    CandidateRow(candidate: c, chosen: c.rank == planner.chosenCandidate?.rank)
                }
                .buttonStyle(.plain)
                .srGlassRow()
                .accessibilityIdentifier("plan-candidate-\(c.rank)")
            }
        } header: {
            SRSectionLabel(text: "Three ways round", trailing: "\(plan.candidates.count)")
        } footer: {
            if let why = plan.rationale.first {
                Text(why)
                    .font(SR.Text.secondary(12))
                    .foregroundStyle(SR.inkMuted)
            }
        }

        Section {
            TextField(planner.chosenCandidate.map { planner.defaultName(for: $0) } ?? "Name", text: $name)
                .font(SR.Text.body())
                .srGlassRow()
            Button {
                Task {
                    if let ref = await planner.save(name: name) {
                        router.pop(on: .health)
                        router.push(ref, on: .health)
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    if planner.busy == .saving { ProgressView().tint(SR.paper) }
                    Text("Save this route").font(SR.Text.body())
                    Spacer()
                }
            }
            .srButton(.prominent)
            .disabled(planner.busy != nil)
            .srBareRow()
            .padding(.vertical, 8)
            .accessibilityIdentifier("plan-save")
        } header: {
            SRSectionLabel(text: "Keep it")
        }
    }
}

/// One of the three candidates: its numbers, its score, and why.
struct CandidateRow: View {
    let candidate: RouteCandidate
    let chosen: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(chosen ? SR.accent : SR.inkMuted)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Option \(candidate.rank)")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Spacer()
                    Text("SCORE \(RouteFormat.score(candidate.score))")
                        .font(SR.Text.mono())
                        .tracking(0.8)
                        .foregroundStyle(chosen ? SR.accent : SR.inkMuted)
                }
                Text(candidate.summaryLine)
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.inkSecondary)
                ForEach(candidate.notes.prefix(3), id: \.self) { note in
                    Text(note)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, SR.rowPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The planning map: the start and finish pins, and once planned, every
/// candidate — the chosen one in the accent, the others quiet beneath it.
struct PlanMap: View {
    @ObservedObject var planner: RoutePlanner
    let placing: PlanRouteScreen.Pin
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let plan = planner.plan {
                    ForEach(plan.candidates.filter { $0.rank != planner.chosenCandidate?.rank }) { c in
                        MapPolyline(coordinates: c.coordinates)
                            .stroke(SR.inkMuted.opacity(0.55), lineWidth: 3)
                    }
                    if let c = planner.chosenCandidate {
                        MapPolyline(coordinates: c.coordinates)
                            .stroke(SR.accent, lineWidth: 4)
                    }
                }
                if let start = planner.start {
                    Annotation("Start", coordinate: start, anchor: .center) { PlanPin(fill: SR.good) }
                        .annotationTitles(.hidden)
                }
                if planner.shape == .toPlace, let finish = planner.finish {
                    Annotation("Finish", coordinate: finish, anchor: .center) { PlanPin(fill: SR.ink) }
                        .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .onTapGesture { point in
                // Pins move only while the spec is open; a plan on screen is
                // being compared, and a stray tap must not invalidate it.
                guard planner.plan == nil, let at = proxy.convert(point, from: .local) else { return }
                SRHaptic.tap()
                if placing == .finish && planner.shape == .toPlace {
                    planner.finish = at
                    planner.finishLabel = "the pin"
                } else {
                    planner.start = at
                    planner.startLabel = "the pin"
                }
            }
        }
        .onChange(of: planner.plan?.candidates.count) { _, _ in camera = .automatic }
        .onChange(of: planner.start?.latitude) { _, _ in
            if planner.plan == nil, let s = planner.start, planner.finish == nil {
                camera = .region(MKCoordinateRegion(center: s, latitudinalMeters: 3000, longitudinalMeters: 3000))
            }
        }
    }
}

private struct PlanPin: View {
    let fill: Color

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(SR.paper, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

// MARK: - Published routes nearby

struct NearbyRoutesScreen: View {
    @EnvironmentObject private var router: Router
    @StateObject private var store = NearbyRoutesStore()
    @State private var sport: RouteSport = .walk
    @State private var here: CLLocationCoordinate2D?

    var body: some View {
        List {
            Section {
                Picker("Sport", selection: $sport) {
                    ForEach(RouteSport.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                }
                .srGlassRow()
            }
            if store.rows.isEmpty {
                if store.state == .loaded {
                    SREmpty(
                        title: "Nothing published nearby",
                        icon: "signpost.right.and.left",
                        message: "No waymarked \(sport.label.lowercased()) routes in OpenStreetMap within 15 km."
                    )
                    .srBareRow()
                } else {
                    TrailStateView(state: store.state, noun: "route", retry: reload)
                        .srBareRow()
                }
            } else {
                Section {
                    ForEach(store.rows) { r in
                        Button {
                            Task {
                                if let ref = await store.save(r, sport: sport) { router.push(ref, on: .health) }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(r.name).font(SR.Text.title()).foregroundStyle(SR.ink)
                                    Text(line(r)).font(SR.Text.mono(13)).foregroundStyle(SR.inkSecondary)
                                }
                                Spacer()
                                if store.saving == r.osmId {
                                    ProgressView().tint(SR.accent)
                                } else {
                                    Image(systemName: "square.and.arrow.down").foregroundStyle(SR.accent)
                                }
                            }
                            .padding(.vertical, SR.rowPadding)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.saving != nil)
                        .srGlassRow()
                    }
                } header: {
                    SRSectionLabel(text: "From OpenStreetMap", trailing: "\(store.rows.count)")
                } footer: {
                    Text("Tap one to save it to your routes.")
                        .font(SR.Text.secondary(12))
                        .foregroundStyle(SR.inkMuted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .srPaper()
        .navigationTitle("Published routes")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Published routes", isPresented: Binding(
            get: { store.error != nil },
            set: { if !$0 { store.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.error ?? "")
        }
        .task {
            here = await OneFix.current()
            reload()
        }
        .onChange(of: sport) { _, _ in reload() }
    }

    private func line(_ r: DiscoveredRoute) -> String {
        var parts: [String] = []
        if let km = r.distanceKm { parts.append("\(TrailFormat.km(fromKm: km)) km") }
        if let ref = r.ref { parts.append(ref) }
        if let op = r.operator { parts.append(op) }
        return parts.isEmpty ? "Waymarked route" : parts.joined(separator: " · ")
    }

    private func reload() {
        guard let here else { return }
        Task { await store.load(near: here, sport: sport) }
    }
}

// MARK: - One saved route

struct PlannedRouteScreen: View {
    let ref: RouteRef
    @StateObject private var store = PlannedRouteStore()

    var body: some View {
        Group {
            if let detail = store.detail {
                PlannedRouteBody(detail: detail)
            } else {
                ScrollView {
                    TrailStateView(state: store.state, noun: "route", retry: reload)
                        .padding(.top, 40)
                }
            }
        }
        .srPaper()
        .navigationTitle(ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable { await store.load(ref.id) }
        .task { if store.detail == nil { await store.load(ref.id) } }
    }

    private func reload() {
        Task { await store.load(ref.id) }
    }
}

struct PlannedRouteBody: View {
    let detail: PlannedRouteDetail
    @State private var following = false
    @ObservedObject private var gifts = RouteGiftsStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // The headline, as an activity and a segment have theirs: the
                // name, and distance lit.
                SRInkBand(kicker: kicker) {
                    SRInkTitle(text: detail.name, size: 28)
                    SRInkCellGrid(figures: Self.figures(detail))
                }

                SRRouteMap(route: detail.coordinates)
                    .frame(height: 300)
                    .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
                    .accessibilityIdentifier("route-map")

                Button {
                    following = true
                } label: {
                    Label("Follow this route", systemImage: "figure.walk.motion")
                        .frame(maxWidth: .infinity)
                }
                .srButton(.prominent)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("route-follow")

                OfflineRow(detail: detail)
                    .padding(.horizontal, 16)

                if !gifts.recipients.isEmpty {
                    Menu {
                        ForEach(gifts.recipients) { person in
                            Button(person.name) { Task { await gifts.send(routeId: detail.id, to: person) } }
                        }
                    } label: {
                        Label("Send to someone in the family", systemImage: "paperplane")
                            .frame(maxWidth: .infinity)
                    }
                    .srButton(.regular)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("route-send")
                }

                if elevations.count > 2 {
                    VStack(alignment: .leading, spacing: 6) {
                        SRSectionLabel(text: "Profile")
                        ElevationChart(points: elevations)
                            .frame(height: 140)
                    }
                    .padding(.horizontal, 16)
                }

                if let notes = detail.notes, !notes.isEmpty {
                    Text(notes)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .padding(.horizontal, 16)
                }

                if !detail.waypoints.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SRSectionLabel(text: "Waypoints", trailing: "\(detail.waypoints.count)")
                        ForEach(detail.waypoints) { w in
                            Text(w.note.map { "\(w.name) — \($0)" } ?? w.name)
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.ink)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .fullScreenCover(isPresented: $following) {
            FollowRouteScreen(detail: detail)
        }
        .task { if gifts.recipients.isEmpty { await gifts.load() } }
        .alert("Route", isPresented: Binding(get: { gifts.message != nil }, set: { if !$0 { gifts.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(gifts.message ?? "")
        }
    }

    private var kicker: String {
        "\(Sport.label(detail.sport)) · \(detail.source == "imported" ? "Published route" : "Planned")"
    }

    static func figures(_ detail: PlannedRouteDetail) -> [SRInkFigure] {
        var figures = [SRInkFigure(label: "Distance", value: TrailFormat.km(detail.distanceM), unit: "km", lit: true)]
        if let up = detail.ascentM, up >= 1 {
            figures.append(SRInkFigure(label: "Up", value: TrailFormat.metres(up), unit: "m"))
        }
        if let down = detail.descentM, down >= 1 {
            figures.append(SRInkFigure(label: "Down", value: TrailFormat.metres(down), unit: "m"))
        }
        if let time = detail.durationS, time > 0 {
            figures.append(SRInkFigure(label: "Takes about", value: TrailFormat.duration(time)))
        }
        if let score = detail.score {
            figures.append(SRInkFigure(label: "Loop score", value: RouteFormat.score(score), unit: "/100"))
        }
        return figures
    }

    /// Distance along the route against height, from the route's own points —
    /// the saved route carries no separate profile.
    private var elevations: [ElevationPoint] {
        var out: [ElevationPoint] = []
        var along = 0.0
        var previous: CLLocation?
        for p in detail.route {
            let here = CLLocation(latitude: p.lat, longitude: p.lng)
            if let previous { along += here.distance(from: previous) }
            previous = here
            if let ele = p.ele { out.append(ElevationPoint(d: along, e: ele)) }
        }
        // A phone chart draws ~200 points; a 4,000-point route is payload.
        let every = max(1, out.count / 200)
        return out.enumerated().filter { $0.offset % every == 0 || $0.offset == out.count - 1 }.map(\.element)
    }
}

// MARK: - Offline

/// Download this route's map for no signal — or how far that has got, or how
/// much it takes.
struct OfflineRow: View {
    let detail: PlannedRouteDetail
    @ObservedObject private var maps = OfflineMaps.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(SR.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SR.Text.title()).foregroundStyle(SR.ink)
                Text(subtitle)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if case .downloading(let f) = maps.state(for: detail.id) {
                    ProgressView(value: f).tint(SR.accent)
                }
            }
            Spacer()
            switch maps.state(for: detail.id) {
            case .none, .failed:
                Button("Download") { maps.download(detail) }
                    .srButton(.regular)
                    .accessibilityIdentifier("route-download")
            case .ready:
                Button(role: .destructive) { maps.delete(detail.id) } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Remove the offline map")
            case .downloading:
                EmptyView()
            }
        }
        .padding(14)
        .srGlassCard()
    }

    private var icon: String {
        if case .ready = maps.state(for: detail.id) { return "checkmark.circle.fill" }
        return "arrow.down.circle"
    }

    private var title: String {
        switch maps.state(for: detail.id) {
        case .none: return "Offline map"
        case .downloading: return "Downloading…"
        case .ready: return "Available offline"
        case .failed: return "Download stopped"
        }
    }

    private var subtitle: String {
        switch maps.state(for: detail.id) {
        case .none: return "The map along this route, to follow it with no signal. A few MB."
        case .downloading(let f): return "\(Int((f * 100).rounded()))%"
        case .ready(let bytes): return "\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) on this iPhone. The route itself is kept too."
        case .failed(let why): return why
        }
    }
}

/// Every route with a map on this phone, and what each takes.
struct OfflineMapsScreen: View {
    @ObservedObject private var maps = OfflineMaps.shared

    var body: some View {
        List {
            if maps.saved.isEmpty {
                SREmpty(title: "No offline maps", icon: "arrow.down.circle",
                        message: "Open a saved route and press Download to keep its map on this iPhone.")
                    .srBareRow()
            } else {
                Section {
                    ForEach(maps.saved) { s in
                        NavigationLink(value: RouteRef(id: s.routeId, name: s.name)) {
                            SRRow(
                                title: s.name,
                                subtitle: ByteCountFormatter.string(fromByteCount: Int64(s.bytes), countStyle: .file)
                                    + (s.complete ? "" : " · incomplete"),
                                icon: "map"
                            )
                        }
                        .srGlassRow()
                        .swipeActions {
                            Button(role: .destructive) { maps.delete(s.routeId) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } header: {
                    SRSectionLabel(text: "On this iPhone",
                                   trailing: ByteCountFormatter.string(fromByteCount: Int64(maps.totalBytes), countStyle: .file))
                } footer: {
                    Text("Map data © OpenStreetMap contributors, OpenMapTiles, served by OpenFreeMap.")
                        .font(SR.Text.secondary(12))
                        .foregroundStyle(SR.inkMuted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .srPaper()
        .navigationTitle("Offline maps")
        .navigationBarTitleDisplayMode(.inline)
    }
}

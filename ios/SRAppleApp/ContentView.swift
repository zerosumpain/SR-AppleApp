import SwiftUI
import MapKit

/// The app.
///
/// Four tabs. Chat and News are NATIVE now — they were a Safari sheet over
/// strangeramblings.com, which worked and never looked like the site, because a
/// web view in a native chrome looks like a web view. Companion keeps the health
/// and family views it always had, restyled onto the same system.
///
/// The whole app is light-locked. That is not laziness about dark mode: the site
/// has no dark mode. Its palette is one warm cream ground with ink type, and the
/// ink is chrome — a bar, a footer, one ledger. Inverting it would not be the
/// same design with different values, it would be a different design. CI runs the
/// simulator in DARK appearance deliberately, so a regression here shows up as a
/// screenshot rather than as a surprise on somebody's phone.
struct ContentView: View {
    @ObservedObject var companion: Companion
    @ObservedObject var outbox: Outbox
    @ObservedObject var location: LocationCollector
    @StateObject private var site = SitePairingModel()
    @State private var tab = Tab.chat

    enum Tab: Hashable { case chat, news, companion, connect }

    var body: some View {
        TabView(selection: $tab) {
            chatTab
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag(Tab.chat)

            newsTab
                .tabItem { Label("News", systemImage: "newspaper") }
                .tag(Tab.news)

            CompanionScreen(companion: companion, outbox: outbox, location: location)
                .tabItem { Label("Companion", systemImage: "heart.text.square") }
                .tag(Tab.companion)

            SitePairingScreen(model: site)
                .tabItem { Label("Connect", systemImage: "qrcode") }
                .tag(Tab.connect)
        }
        .tint(SR.accent)
        .preferredColorScheme(.light)
        .task { await site.check() }
    }

    @ViewBuilder
    private var chatTab: some View {
        if site.paired {
            ThreadListScreen()
        } else {
            SRShell(path: "/jkai") {
                SiteUnpairedNotice(what: "your threads") { tab = .connect }
            }
        }
    }

    @ViewBuilder
    private var newsTab: some View {
        if site.paired {
            NewsScreen()
        } else {
            SRShell(path: "/news") {
                SiteUnpairedNotice(what: "the news desk") { tab = .connect }
            }
        }
    }
}

/// Health, family and sync — the app's original job, on the system.
struct CompanionScreen: View {
    @ObservedObject var companion: Companion
    @ObservedObject var outbox: Outbox
    @ObservedObject var location: LocationCollector

    @State private var server = ""
    @State private var code = ""
    @State private var scannerPresented = false
    @State private var scannedPairing: PairingPayload?
    @State private var confirmPairing = false
    @State private var showCode = false
    @State private var pane = 0
    @State private var confirmDisconnect = false

    private enum PairingField: Hashable { case server, code }
    @FocusState private var pairingFocus: PairingField?

    var body: some View {
        SRShell(
            path: "/health",
            kicker: companion.paired ? "Connected" : "Not paired",
            footer: footerLines
        ) {
            SRSection {
                SectionHead(
                    kicker: "A / Companion",
                    title: ["A little", "closer"],
                    strap: "Your health stays yours. Your family sees the location you choose to share, and nothing else."
                )
                if companion.paired {
                    if let profile = companion.profile {
                        Figure(value: profile.name, label: "Connected as")
                    }
                    panePicker
                } else {
                    pairing
                }
            }

            if companion.paired {
                SRSection(tinted: true) {
                    switch pane {
                    case 1: healthPane
                    case 2: familyPane
                    default: syncPane
                    }
                }
            }

            SRSection(isLast: true) {
                SRLabel(text: "Sync")
                    .padding(.bottom, 10)
                Text(companion.message)
                    .font(SR.body(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sync-status")
                HStack(spacing: 18) {
                    Figure(value: "\(companion.queueCount)", label: "Waiting")
                    if let last = companion.lastUpload {
                        Figure(value: last.formatted(date: .omitted, time: .shortened), label: "Last upload")
                    }
                }
                .padding(.top, 12)
            }
        }
        .confirmationDialog("Disconnect this iPhone?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await companion.disconnect() } }
        } message: {
            Text("Stops syncing, pauses location sharing and revokes this device. Health records already uploaded stay on the website.")
        }
        .sheet(isPresented: $scannerPresented, onDismiss: { confirmPairing = scannedPairing != nil }) {
            PairingScanner { value in
                do { scannedPairing = try PairingPayload.parse(value) }
                catch {
                    scannedPairing = nil
                    companion.message = error.localizedDescription
                }
            }
        }
        .alert("Connect to this server?", isPresented: $confirmPairing) {
            Button("Cancel", role: .cancel) { scannedPairing = nil }
            Button("Connect") {
                if let payload = scannedPairing {
                    server = payload.server
                    code = payload.code
                    scannedPairing = nil
                    connect()
                }
            }
        } message: { Text(scannedPairing?.server ?? "") }
    }

    private var footerLines: [String] {
        ["Strange Ramblings · companion",
         "Health is scoped to you · family sees location only",
         "Targets 10 minutes still, 30 seconds moving"]
    }

    private var panePicker: some View {
        HStack(spacing: 0) {
            ForEach(Array(["Sync", "My health", "Family"].enumerated()), id: \.offset) { index, label in
                let current = pane == index
                Button { pane = index } label: {
                    Text(label.uppercased())
                        .font(SR.monoMedium(12))
                        .tracking(1.1)
                        .foregroundStyle(current ? SR.paper : SR.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(current ? SR.ink : Color.clear)
                        .overlay(Rectangle().strokeBorder(SR.line, lineWidth: current ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 18)
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Open Connect & privacy on your companion dashboard, then create a pairing QR code.")
                .font(SR.body(15))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SRButton(title: "Pair by QR code", filled: true, disabled: companion.busy) {
                pairingFocus = nil
                scannedPairing = nil
                scannerPresented = true
            }

            SRLabel(text: "Or enter it by hand").padding(.top, 6)

            TextField("HTTPS server address", text: $server)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(SR.body(15))
                .padding(.horizontal, 12).padding(.vertical, 11)
                .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
                .focused($pairingFocus, equals: .server)
                .submitLabel(.next)
                .onSubmit { pairingFocus = .code }

            Group {
                if showCode { TextField("One-time pairing code", text: $code) }
                else { SecureField("One-time pairing code", text: $code) }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(SR.body(15))
            .padding(.horizontal, 12).padding(.vertical, 11)
            .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
            .focused($pairingFocus, equals: .code)
            .submitLabel(.go)
            .onSubmit { connect() }

            Toggle(isOn: $showCode) {
                Text("Show pairing code").font(SR.body(14)).foregroundStyle(SR.inkSecondary)
            }
            .tint(SR.accent)

            SRButton(title: "Connect", filled: true, disabled: companion.busy || code.isEmpty) { connect() }

            Text("Health and location uploads start only after you choose to enable them.")
                .font(SR.body(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func connect() {
        guard !companion.busy, !code.isEmpty else { return }
        pairingFocus = nil
        Task {
            await companion.pair(server: server, code: code)
            if companion.paired { code = "" }
        }
    }

    private var syncPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SRLabel(text: "My health permissions")
            Text("Selected categories are sent to your private dashboard. Family members cannot read them. The first sync includes up to 30 days.")
                .font(SR.body(14))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(["steps", "heart_rate", "resting_heart_rate", "sleep", "workout"], id: \.self) { kind in
                Toggle(isOn: Binding(
                    get: { outbox.state.healthEnabled.contains(kind) },
                    set: { companion.setHealth(kind, enabled: $0) }
                )) {
                    Text(HealthCollector.labels[kind] ?? kind)
                        .font(SR.body(15))
                        .foregroundStyle(SR.ink)
                }
                .tint(SR.accent)
                .disabled(companion.busy)
            }

            SRButton(title: "Review Apple Health permissions", disabled: companion.busy || outbox.state.healthEnabled.isEmpty) {
                Task { await companion.authorizeHealth() }
            }

            Text("Apple does not reveal whether you denied read access, so missing records may mean no data or no permission. Turning a category off stops future uploads; delete what is already there on the website.")
                .font(SR.body(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(SR.divider).frame(height: 1).padding(.vertical, 4)

            Toggle(isOn: Binding(
                get: { outbox.state.sharing },
                set: { value in Task { await companion.setSharing(value) } }
            )) {
                Text("Share location with my family").font(SR.body(15)).foregroundStyle(SR.ink)
            }
            .tint(SR.accent)
            .disabled(companion.busy)

            Text(location.status)
                .font(SR.body(14))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SRButton(title: "Enable Always location access", disabled: !outbox.state.sharing) {
                location.requestAlways()
            }
            SRButton(title: companion.busy ? "Syncing…" : "Sync now", filled: true, disabled: companion.busy) {
                Task { await companion.sync() }
            }
            SRButton(title: "Disconnect this iPhone", disabled: companion.busy) {
                confirmDisconnect = true
            }
        }
    }

    private var healthPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRLabel(text: "Only you can see this")
            if companion.records.isEmpty {
                Text("No uploaded health records yet. Enable categories under Sync and review Apple Health permissions.")
                    .font(SR.body(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SRLedger {
                    ForEach(companion.records.prefix(50)) { record in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(HealthCollector.labels[record.kind] ?? record.kind)
                                    .font(SR.bodyMedium(15))
                                    .foregroundStyle(SR.ink)
                                if let stage = record.stage {
                                    Text(stage.replacingOccurrences(of: "_", with: " "))
                                        .font(SR.body(14))
                                        .foregroundStyle(SR.inkSecondary)
                                }
                                if let activity = record.activity {
                                    Text(activity).font(SR.body(14)).foregroundStyle(SR.inkSecondary)
                                }
                                Text("\(record.source) · \(record.start)")
                                    .font(SR.mono(12))
                                    .foregroundStyle(SR.inkGhost)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if let value = record.value {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(value.formatted())
                                        .font(SR.display(20))
                                        .foregroundStyle(SR.ink)
                                    if let unit = record.unit {
                                        Text(unit.uppercased())
                                            .font(SR.mono(12))
                                            .foregroundStyle(SR.inkMuted)
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SR.paper)
                    }
                }
            }
            Text("The latest uploaded records. Heart rate is not a live feed, and sleep records can overlap between sources.")
                .font(SR.body(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var familyPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRLabel(text: "Family locations")
            if companion.family.isEmpty {
                Text("No family locations available.")
                    .font(SR.body(15))
                    .foregroundStyle(SR.inkSecondary)
            }
            SRLedger {
                ForEach(companion.family) { member in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(member.name).font(SR.bodyMedium(16)).foregroundStyle(SR.ink)
                        if let point = member.location {
                            let stale = (parseTimestamp(point.recorded)?.timeIntervalSinceNow ?? -.infinity) < -1200
                            SRPill(text: stale ? "Stale" : "Latest", tone: stale ? SR.warn : SR.good)
                            Text("±\(Int(point.accuracy)) m · \(point.moving ? "Moving" : "Stationary")")
                                .font(SR.mono(12))
                                .foregroundStyle(SR.inkMuted)
                            Text(point.recorded).font(SR.mono(12)).foregroundStyle(SR.inkGhost).lineLimit(1)
                            SRButton(title: "Open in Maps") {
                                MKMapItem(placemark: MKPlacemark(
                                    coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                                )).openInMaps()
                            }
                        } else {
                            Text(member.sharing ? "Waiting for a location" : "Location sharing paused")
                                .font(SR.body(14))
                                .foregroundStyle(SR.inkSecondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SR.paper)
                }
            }
            SRButton(title: "Refresh family locations") {
                Task {
                    do { try await companion.refresh() }
                    catch { companion.message = error.localizedDescription }
                }
            }
        }
    }
}

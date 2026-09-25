import SwiftUI
import UIKit

/// Settings, as a place rather than a page.
///
/// What was here before was one long editorial scroll carrying five unrelated
/// subjects — a battery instrument, location presets, the motion gate, Apple
/// Health permissions and sync status — because there was nowhere else for any
/// of them to go. A phone's answer to five subjects is five rows and five
/// screens, each of which fits.
///
/// The Connect tab is gone from the tab bar and lives here, under Connections.
/// Pairing is setup: something you do once, from a QR code on another screen,
/// and then never again. A permanent slot on the tab bar for it was the single
/// clearest piece of clutter in the app.
struct SettingsScreen: View {
    @ObservedObject var outbox: Outbox
    @ObservedObject var companion: Companion
    @ObservedObject var location: LocationCollector
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var site: SitePairingModel
    @ObservedObject var alerts: AlertStore
    @ObservedObject var connections: ConnectionsStore
    /// Where something else wanted this sheet to open. A "Connect" button three
    /// screens away should land on the pairing screen, not on the hub.
    let target: Router.SettingsTarget?

    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    enum Route: Hashable { case notifications, connections, health, location, log, about }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    link(.notifications, "Notifications", "Where each kind of alert goes", "bell.badge")
                    link(.connections, "Connections", connectionsSubtitle, "qrcode")
                } header: {
                    SRSectionLabel(text: "The app")
                }

                Section {
                    link(.health, "Apple Health", "\(outbox.state.healthEnabled.count) of \(HealthCatalogue.groupOrder.count) categories", "heart.text.square")
                    link(.location, "Location & battery", draft, "location")
                    link(.log, "Gate history", "When GPS slept, and why", "list.bullet.rectangle")
                } header: {
                    SRSectionLabel(text: "What it collects")
                }

                Section {
                    link(.about, "About", "Version, licences and what this holds", "info.circle")
                }
            }
            .listStyle(.insetGrouped)
            .srPaper()
            .navigationTitle("Settings")
            // Inline, not large. A large title renders BLANK on this OS with this
            // appearance proxy — the bar lays out at full height and paints no text.
            // Verified in CI screenshots; inline titles in the same build draw in
            // Archivo Black correctly. A compact bar also gives a list more of the
            // screen, which on a phone is the thing actually being asked for.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .notifications: AlertRoutingScreen(alerts: alerts)
                case .connections: ConnectionsScreen(companion: companion, site: site, connections: connections)
                case .health: AppleHealthScreen(outbox: outbox, companion: companion, location: location)
                case .location: LocationSettingsScreen(outbox: outbox, companion: companion, location: location, battery: battery)
                case .log: ActivityLogScreen(outbox: outbox)
                case .about: AboutScreen()
                }
            }
        }
        .task {
            // Push the requested screen once, on open. Doing it in `onAppear`
            // instead would re-push every time the reader navigated back to the
            // hub, which is a settings screen you cannot leave.
            switch target {
            case .notifications: path.append(Route.notifications)
            case .connections: path.append(Route.connections)
            case .health: path.append(Route.health)
            case .location: path.append(Route.location)
            case .none: break
            }
        }
    }

    /// A lapsed site connection outranks the pairing summary: it is the thing
    /// the reader came here to fix.
    private var connectionsSubtitle: String {
        if connections.count > 0 {
            return connections.count == 1 ? "A site connection needs you" : "\(connections.count) site connections need you"
        }
        return site.paired && companion.paired
            ? "Both connected"
            : site.paired ? "Website connected" : companion.paired ? "Companion connected" : "Not connected"
    }

    private var draft: String {
        outbox.state.location.matchingPreset?.label ?? "Custom"
    }

    @ViewBuilder
    private func link(_ route: Route, _ title: String, _ subtitle: String, _ icon: String) -> some View {
        NavigationLink(value: route) {
            SRRow(title: title, subtitle: subtitle, icon: icon)
        }
        .srGlassRow()
        .accessibilityIdentifier("settings-\(route)")
    }
}

/// Both pairings, and the difference between them, on one screen.
///
/// They are two credentials to two different servers and conflating them would
/// mean revoking a phone's health sync to stop it reading chat. The two panels
/// say which is which — the likeliest mistake by a wide margin is scanning the
/// wrong QR, so the scanner names that error specifically when it happens.
struct ConnectionsScreen: View {
    @ObservedObject var companion: Companion
    @ObservedObject var site: SitePairingModel
    @ObservedObject var connections: ConnectionsStore

    @State private var scanningSite = false
    @State private var scannedSite: SitePairing?
    @State private var confirmSite = false

    @State private var scanningCompanion = false
    @State private var scannedCompanion: PairingPayload?
    @State private var confirmCompanion = false
    @State private var server = ""
    @State private var code = ""
    @State private var showCode = false
    @State private var confirmDisconnect = false
    private enum Field: Hashable { case server, code }
    @FocusState private var focus: Field?

    var body: some View {
        List {
            // MARK: What the site holds
            //
            // First, because when it is not empty it is why the reader is here.
            // Only once the site is paired: without that, the phone cannot know.
            if site.paired {
                SiteConnectionsSection(store: connections)
            }

            // MARK: Website
            Section {
                if site.paired {
                    SRRow(title: "Connected", subtitle: site.ownerEmail, icon: "checkmark.circle.fill", tone: SR.good)
                        .srGlassRow()
                    Button(role: .destructive) { SRHaptic.tap(); site.signOut() } label: {
                        SRRow(title: "Disconnect from the website", icon: "xmark.circle", tone: SR.error)
                    }
                    .buttonStyle(.plain)
                    .srGlassRow()
                } else {
                    Button {
                        SRHaptic.tap()
                        scannedSite = nil
                        scanningSite = true
                    } label: {
                        SRRow(title: site.busy ? "Connecting…" : "Scan the chat & news code",
                              subtitle: "strangeramblings.com/apple-app → Connect & privacy",
                              icon: "qrcode.viewfinder")
                    }
                    .buttonStyle(.plain)
                    .disabled(site.busy)
                    .srGlassRow()
                    .accessibilityIdentifier("site-pair-scan")
                }
                if let message = site.message {
                    Text(message)
                        .font(SR.Text.secondary())
                        .foregroundStyle(site.paired ? SR.inkMuted : SR.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .srGlassRow()
                        .padding(.vertical, 6)
                }
            } header: {
                SRSectionLabel(text: "The website", trailing: site.paired ? "Connected" : nil)
            } footer: {
                Text("Chat threads, the news desk, your health figures and alerts. A device token, not a password — the website can revoke it at any moment, and it expires after ninety days.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .padding(.vertical, 4)
            }

            // MARK: Companion
            Section {
                if companion.paired {
                    if let profile = companion.profile {
                        SRRow(title: "Connected", subtitle: profile.name, icon: "checkmark.circle.fill", tone: SR.good)
                            .srGlassRow()
                    }
                    Button { SRHaptic.tap(); Task { await companion.sync() } } label: {
                        SRRow(title: companion.busy ? "Syncing…" : "Sync now",
                              subtitle: companion.queueCount > 0 ? "\(companion.queueCount) waiting" : nil,
                              icon: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.plain)
                    .disabled(companion.busy)
                    .srGlassRow()
                    Button(role: .destructive) { confirmDisconnect = true } label: {
                        SRRow(title: "Disconnect this iPhone", icon: "xmark.circle", tone: SR.error)
                    }
                    .buttonStyle(.plain)
                    .disabled(companion.busy)
                    .srGlassRow()
                } else {
                    Button {
                        SRHaptic.tap()
                        focus = nil
                        scannedCompanion = nil
                        scanningCompanion = true
                    } label: {
                        SRRow(title: "Pair by QR code",
                              subtitle: "The health & location code on the same page",
                              icon: "qrcode.viewfinder")
                    }
                    .buttonStyle(.plain)
                    .disabled(companion.busy)
                    .srGlassRow()
                    .accessibilityIdentifier("companion-pair-scan")

                    manualPairing
                }
                if companion.paired == false, !companion.message.isEmpty {
                    Text(companion.message)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .srGlassRow().padding(.vertical, 6)
                }
            } header: {
                SRSectionLabel(text: "The companion", trailing: companion.paired ? "Connected" : nil)
            } footer: {
                Text("Apple Health uploads and family location. A different server and a different credential: disconnecting either leaves the other running.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .srPaper()
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await site.check()
            await connections.refresh()
        }
        .sheet(isPresented: $scanningSite, onDismiss: { confirmSite = scannedSite != nil }) {
            PairingScanner { value in
                do { scannedSite = try SitePairing.parse(value) }
                catch {
                    scannedSite = nil
                    site.message = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $scanningCompanion, onDismiss: { confirmCompanion = scannedCompanion != nil }) {
            PairingScanner { value in
                do { scannedCompanion = try PairingPayload.parse(value) }
                catch {
                    scannedCompanion = nil
                    companion.message = error.localizedDescription
                }
            }
        }
        // The origin, shown before anything is sent to it. A QR is a URL
        // somebody else controls, so the confirmation names where it points.
        .alert("Connect to this server?", isPresented: $confirmSite) {
            Button("Cancel", role: .cancel) { scannedSite = nil }
            Button("Connect") {
                if let payload = scannedSite {
                    scannedSite = nil
                    Task { await site.pair(payload) }
                }
            }
        } message: { Text(scannedSite?.server ?? "") }
        .alert("Connect to this server?", isPresented: $confirmCompanion) {
            Button("Cancel", role: .cancel) { scannedCompanion = nil }
            Button("Connect") {
                if let payload = scannedCompanion {
                    server = payload.server
                    code = payload.code
                    scannedCompanion = nil
                    connectCompanion()
                }
            }
        } message: { Text(scannedCompanion?.server ?? "") }
        .confirmationDialog("Disconnect this iPhone?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await companion.disconnect() } }
        } message: {
            Text("Stops syncing, pauses location sharing and revokes this device. Health records already uploaded stay on the website.")
        }
    }

    /// The typed fallback. Kept because a QR needs a second screen, and the one
    /// time you need to pair is the time the other screen is not to hand.
    private var manualPairing: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Or enter it by hand")

            TextField("HTTPS server address", text: $server)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(SR.Text.body(15))
                .padding(.horizontal, 12).padding(.vertical, 12)
                .frame(minHeight: SR.tapTarget)
                .background(SR.surface)
                .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
                .focused($focus, equals: .server)
                .submitLabel(.next)
                .onSubmit { focus = .code }

            Group {
                if showCode { TextField("One-time pairing code", text: $code) }
                else { SecureField("One-time pairing code", text: $code) }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(SR.Text.body(15))
            .padding(.horizontal, 12).padding(.vertical, 12)
            .frame(minHeight: SR.tapTarget)
            .background(SR.surface)
            .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
            .focused($focus, equals: .code)
            .submitLabel(.go)
            .onSubmit { connectCompanion() }

            Toggle(isOn: $showCode) {
                Text("Show pairing code").font(SR.Text.secondary()).foregroundStyle(SR.inkSecondary)
            }
            .tint(SR.accent)

            Button { connectCompanion() } label: {
                Text("CONNECT")
                    .font(SR.Text.label())
                    .tracking(1.3)
                    .foregroundStyle(SR.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(companion.busy || code.isEmpty ? SR.inkGhost : SR.accent)
            }
            .buttonStyle(.plain)
            .disabled(companion.busy || code.isEmpty)
        }
        .padding(.vertical, 10)
        .srGlassRow()
    }

    private func connectCompanion() {
        guard !companion.busy, !code.isEmpty else { return }
        focus = nil
        Task {
            await companion.pair(server: server, code: code)
            if companion.paired {
                code = ""
                SRHaptic.ok()
            }
        }
    }
}

/// What Apple Health hands over, and where it goes.
struct AppleHealthScreen: View {
    @ObservedObject var outbox: Outbox
    @ObservedObject var companion: Companion
    @ObservedObject var location: LocationCollector

    private let groups = HealthCatalogue.groupOrder

    var body: some View {
        List {
            Section {
                ForEach(groups, id: \.self) { group in
                    Toggle(isOn: Binding(
                        get: { outbox.state.healthEnabled.contains(group) },
                        set: { value in SRHaptic.select(); companion.setHealth(group, enabled: value) }
                    )) {
                        Text(HealthCatalogue.label(forGroup: group))
                            .font(SR.Text.body(16))
                            .foregroundStyle(SR.ink)
                    }
                    .tint(SR.accent)
                    .disabled(companion.busy)
                    .srGlassRow()
                    .frame(minHeight: SR.tapTarget)
                }

                Button {
                    SRHaptic.tap()
                    Task { await companion.authorizeHealth() }
                } label: {
                    SRRow(title: "Review Apple Health permissions",
                          subtitle: companion.healthReviewNeeded ? "Some categories have not been allowed yet" : nil,
                          icon: "heart.text.square")
                }
                .buttonStyle(.plain)
                .disabled(companion.busy || outbox.state.healthEnabled.isEmpty)
                .srGlassRow()
            } header: {
                SRSectionLabel(text: "Categories")
            } footer: {
                Text("Health is read on a schedule iOS controls, not on a timer of ours, so these cost far less than location. Apple does not reveal whether you denied read access, so missing records may mean no data or no permission. Turning one off stops future uploads; delete what is already there on the website.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .padding(.vertical, 4)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { outbox.state.sharing },
                    set: { value in Task { await companion.setSharing(value) } }
                )) {
                    Text("Share location with my family")
                        .font(SR.Text.body(16))
                        .foregroundStyle(SR.ink)
                }
                .tint(SR.accent)
                .disabled(companion.busy)
                .srGlassRow()
                .frame(minHeight: SR.tapTarget)

                Text(location.status)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .srGlassRow().padding(.vertical, 6)

                Button {
                    SRHaptic.tap()
                    location.requestAlways()
                } label: {
                    SRRow(title: "Enable Always location access", icon: "location.fill")
                }
                .buttonStyle(.plain)
                .disabled(!outbox.state.sharing)
                .srGlassRow()
            } header: {
                SRSectionLabel(text: "Family location")
            } footer: {
                Text("Family members see the position you share and nothing else. Your health data is never shared with them.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .padding(.vertical, 4)
            }

            Section {
                SRRow(title: "Waiting to upload", subtitle: nil) {
                    Text("\(companion.queueCount)").font(SR.Text.mono(15)).foregroundStyle(SR.ink)
                }
                .srGlassRow()
                if let last = companion.lastUpload {
                    SRRow(title: "Last upload") {
                        Text(last.formatted(date: .abbreviated, time: .shortened))
                            .font(SR.Text.mono(13))
                            .foregroundStyle(SR.ink)
                    }
                    .srGlassRow()
                }
                Text(companion.message)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .srGlassRow().padding(.vertical, 6)
                    .accessibilityIdentifier("sync-status")
            } header: {
                SRSectionLabel(text: "Sync")
            }
        }
        .listStyle(.insetGrouped)
        .srPaper()
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What this app is, and what it holds.
struct AboutScreen: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                SRRow(title: "Version") {
                    Text(version).font(SR.Text.mono(13)).foregroundStyle(SR.inkMuted)
                }
                .srGlassRow()
                Link(destination: SiteClient.shared.webURL("apple-app")) {
                    SRRow(title: "Connect & privacy on the web", icon: "safari") {
                        Image(systemName: "arrow.up.forward").foregroundStyle(SR.inkMuted)
                    }
                }
                .srGlassRow()
            } header: {
                SRSectionLabel(text: "This app")
            }

            Section {
                Text("""
                     Health is scoped to you. Family membership grants access to shared \
                     locations only — there is no public health projection, no family \
                     health endpoint and no administrator view that bypasses it.

                     Your own recorded track is more tightly scoped still: the family tab \
                     shares a latest position, a track is a history, and a month of \
                     positions says where somebody sleeps, works and takes their children.

                     Server operators with filesystem access still control the stored \
                     data. This is not end-to-end encryption and does not claim to be.
                     """)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            } header: {
                SRSectionLabel(text: "What this holds")
            }

            Section {
                Text("Archivo Black, DM Sans, DM Mono and JetBrains Mono, all under the SIL Open Font Licence. Their licences ship in the app bundle.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            } header: {
                SRSectionLabel(text: "Typefaces")
            }
        }
        .listStyle(.insetGrouped)
        .srPaper()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

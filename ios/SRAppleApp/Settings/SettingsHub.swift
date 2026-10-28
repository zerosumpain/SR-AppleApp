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
    /// Where alerts go and the website's pairing are the owner's; everything
    /// this phone collects is everyone's.
    @ObservedObject private var access = AccessStore.shared
    @ObservedObject private var bikePresence = BikePresence.shared
    @ObservedObject private var hold = LocationHoldStore.shared

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: Router
    @State private var path = NavigationPath()
    @AppStorage(SRAppearance.key) private var appearance: SRAppearance = .system

    enum Route: Hashable { case notifications, connections, health, location, hold, bike, captures, log, about, viewAs, deleteAccount }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // The App Review demo, and the way out of it. Empty otherwise.
                ReviewDemoSettingsSection()

                Section {
                    if access.current.owner {
                        link(.notifications, "Notifications", "Where each kind of alert goes", "bell.badge")
                    }
                    link(.connections, "Connections", connectionsSubtitle, "qrcode")
                    // Which build the family's phones are offered, chosen here
                    // rather than on the site's /admin/access/app.
                    if AccessStore.ownerSite {
                        NavigationLink {
                            AppReleaseScreen()
                        } label: {
                            SRRow(title: "Release to the family", subtitle: "Choose which app build the family get", icon: "paperplane")
                        }
                        .srGlassRow()
                        .accessibilityIdentifier("settings-app-release")
                    }
                    if site.paired {
                        NavigationLink {
                            DevicePrivacyScreen()
                        } label: {
                            SRRow(title: "Lock Screen privacy", subtitle: "Notification details and journey Live Activities", icon: "lock")
                        }
                        .srGlassRow()
                    }
                } header: {
                    SRSectionLabel(text: "The app")
                }

                Section {
                    Picker(selection: $appearance) {
                        ForEach(SRAppearance.allCases) { Text($0.label).tag($0) }
                    } label: {
                        SRRow(title: "Appearance", subtitle: "Light, dark, or match the phone", icon: "circle.lefthalf.filled")
                    }
                    .pickerStyle(.menu)
                    .tint(SR.accent)
                    .srGlassRow()
                    .accessibilityIdentifier("settings-appearance")
                    // The palette is a sheet of its own, so the app can be
                    // seen redrawing behind it; this one gives way to it.
                    Button {
                        SRHaptic.tap()
                        router.openColours()
                    } label: {
                        SRRow(title: "Colours", subtitle: "Pick a palette, or change any tile's colour", icon: "paintpalette")
                    }
                    .buttonStyle(.plain)
                    .srGlassRow()
                    .accessibilityIdentifier("settings-colours")
                    // Your circle, as the family sees it: a picture in place
                    // of your initials. The site keeps it, so family only.
                    if access.familyBoards && site.paired {
                        NavigationLink {
                            FamilyPhotoScreen()
                        } label: {
                            SRRow(title: "Your photo", subtitle: "Shown to the family in place of your initials", icon: "person.crop.circle")
                        }
                        .srGlassRow()
                        .accessibilityIdentifier("settings-family-photo")
                    }
                } header: {
                    SRSectionLabel(text: "Appearance")
                }

                // Which tiles Home shows, in what order and at what size. Everyone has a
                // Home, so everyone has this; it lists only what they may use.
                Section {
                    NavigationLink {
                        HomeCustomizeScreen()
                    } label: {
                        SRRow(title: "Home", subtitle: "Choose, arrange and size the tiles on Home", icon: "square.grid.2x2")
                    }
                    .srGlassRow()
                    .accessibilityIdentifier("settings-home")
                    #if DEBUG
                    // The widgets, drawn in the app: a UI test cannot reach
                    // the Home Screen, so this is how CI photographs them.
                    if SRDemo.isShowcase && access.familyBoards && site.paired {
                        NavigationLink {
                            FamilyWidgetGallery()
                        } label: {
                            SRRow(title: "Widget previews", subtitle: "Demo only", icon: "rectangle.3.group")
                        }
                        .srGlassRow()
                        .accessibilityIdentifier("settings-widget-previews")
                    }
                    #endif
                } header: {
                    SRSectionLabel(text: "Home")
                }

                Section {
                    link(.health, "Apple Health", "\(outbox.state.healthEnabled.count) of \(HealthCatalogue.groupOrder.count) categories", "heart.text.square")
                    link(.location, "Location & battery", draft, "location")
                    // The owner's alone, and only on his own seat: nobody else's
                    // phone draws it, and View as hides it (`LocationHoldStore.offered`).
                    if LocationHoldStore.offered {
                        link(.hold, "Hold my location", hold.hold?.line() ?? "Show the family a fixed place for a while", "location.slash")
                    }
                    link(.bike, "Bike", bikePresence.bike?.name ?? "Mark rides on your e-bike", "bicycle")
                    // The owner's, like Captures itself: the Action Button
                    // recipe, the speaker models, the screenshot deny list.
                    if AccessStore.ownerSite {
                        link(.captures, "Captures", "Shortcut, speaker models, your voice and screenshots", "waveform.badge.mic")
                    }
                    link(.log, "Gate history", "When GPS slept, and why", "list.bullet.rectangle")
                } header: {
                    SRSectionLabel(text: "What it collects")
                }

                // The owner's alone, on the REAL answer — viewing as a member
                // must not take away the way back.
                if access.isRealOwner {
                    Section {
                        link(.viewAs, "View as", access.viewingAs.map { "Viewing as \($0.name)" } ?? "Check someone's access before it reaches them", "eye")
                    } header: {
                        SRSectionLabel(text: "Testing")
                    }
                }

                Section {
                    link(.about, "About", "Version, licences and what this holds", "info.circle")
                }

                // Last, and apart: App Store 5.1.1(v). Never for the owner,
                // whose account is the website's to manage.
                switch deletionLane {
                case .ownerManaged:
                    Section {
                        SRRow(title: "Your account", subtitle: "The owner account is managed on the website, not from the app.", icon: "person.crop.circle")
                            .srGlassRow()
                            .accessibilityIdentifier("settings-owner-account")
                    } header: {
                        SRSectionLabel(text: "Account")
                    }
                case .site, .companion:
                    Section {
                        NavigationLink(value: Route.deleteAccount) {
                            SRRow(title: "Delete account", subtitle: "Your account and its data, for good", icon: "trash", tone: SR.error)
                        }
                        .srGlassRow()
                        .accessibilityIdentifier("settings-deleteAccount")
                    } header: {
                        SRSectionLabel(text: "Account")
                    }
                case .unpaired:
                    EmptyView()
                }
            }
            .listStyle(.insetGrouped)
            .srPaper()
            .navigationTitle("Settings")
            // Inline, not large. A large title renders BLANK on this OS with this
            // appearance proxy — the bar lays out at full height and paints no text.
            // Verified in CI screenshots; inline titles in the same build draw in
            // Inter Display correctly. A compact bar also gives a list more of the
            // screen, which on a phone is the thing actually being asked for.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .notifications:
                    if access.current.owner { AlertRoutingScreen(alerts: alerts) }
                case .connections: ConnectionsScreen(companion: companion, site: site, connections: connections)
                case .health: AppleHealthScreen(outbox: outbox, companion: companion, location: location)
                case .location: LocationSettingsScreen(outbox: outbox, companion: companion, location: location, battery: battery)
                case .hold: if LocationHoldStore.offered { LocationHoldScreen() }
                case .bike: BikeScreen(bike: bikePresence)
                case .captures: if AccessStore.ownerSite { CaptureSettingsScreen() }
                case .log: ActivityLogScreen(outbox: outbox)
                case .about: AboutScreen()
                case .viewAs:
                    if access.isRealOwner { ViewAsScreen() }
                case .deleteAccount:
                    if deletionLane == .site || deletionLane == .companion {
                        DeleteAccountScreen(companion: companion, site: site, lane: deletionLane)
                    }
                }
            }
        }
        .task {
            // Push the requested screen once, on open. Doing it in `onAppear`
            // instead would re-push every time the reader navigated back to the
            // hub, which is a settings screen you cannot leave.
            switch target {
            case .notifications: if access.current.owner { path.append(Route.notifications) }
            case .connections: path.append(Route.connections)
            case .health: path.append(Route.health)
            case .location: path.append(Route.location)
            case .hold: if LocationHoldStore.offered { path.append(Route.hold) }
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
        // A member's site credential is the app's business, not theirs.
        guard access.current.owner else { return companion.paired ? "Companion connected" : "Not connected" }
        return site.paired && companion.paired
            ? "Both connected"
            : site.paired ? "Website connected" : companion.paired ? "Companion connected" : "Not connected"
    }

    private var deletionLane: AccountDeletionLane {
        AccountDeletionPolicy.lane(isOwner: access.isRealOwner, sitePaired: site.paired, companionPaired: companion.paired)
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

/// Saved against this phone's site credential; private defaults for every new pairing.
struct DevicePrivacyScreen: View {
    private struct Choice: Codable {
        var notificationDetails: Bool
        var liveActivityEnabled: Bool
    }
    @State private var choice = Choice(notificationDetails: false, liveActivityEnabled: false)
    @State private var ready = false
    @State private var saving = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("Show notification details", isOn: $choice.notificationDetails)
                Toggle("Show journey Live Activities", isOn: $choice.liveActivityEnabled)
            } footer: {
                Text("Both are off by default. Details can include names, places, tasks and step counts. Live Activities can show family journeys while this phone is locked. Information already delivered cannot be recalled.")
            }
            .disabled(!ready || saving)
            Section {
                Button(saving ? "Saving…" : "Save choices") { Task { await save() } }
                    .disabled(!ready || saving)
                if let message { Text(message).font(SR.Text.secondary()) }
            }
        }
        .navigationTitle("Lock Screen privacy")
        .task {
            do {
                choice = try await SiteClient.shared.send("api/native/push", asSelf: true)
                ready = true
            } catch { message = error.localizedDescription }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let body = try JSONEncoder().encode(choice)
            choice = try await SiteClient.shared.send("api/native/push", method: "PATCH", body: body, asSelf: true)
            if !choice.liveActivityEnabled { await JourneyLive.shared.endAll() }
            message = "Saved for this iPhone."
        } catch { message = error.localizedDescription }
    }
}

/// This phone's connections, paired with ONE code.
///
/// Health & location (the companion server) and chat & news (this site) are
/// still two credentials, so revoking one never takes the other — but they are
/// set up together, from the one code at strangeramblings.com/welcome, and
/// always as the same person: the code connects only a phone signed in as the
/// person it was made for, and health & location are then fetched through the
/// site (`CodePairing`). Before 2026-10-19 there were two QR codes for whoever
/// was signed in to the browser showing them, and a son's phone became his
/// father's.
struct ConnectionsScreen: View {
    @ObservedObject var companion: Companion
    @ObservedObject var site: SitePairingModel
    @ObservedObject var connections: ConnectionsStore
    @ObservedObject private var access = AccessStore.shared
    @ObservedObject private var pairing = CodePairing.shared

    @State private var scanning = false
    @State private var scanned: PairingPayload?
    @State private var confirmScanned = false
    @State private var typed = ""
    @State private var showCode = false
    @State private var confirmDisconnect = false
    @FocusState private var typing: Bool

    var body: some View {
        List {
            // MARK: What the site holds
            //
            // First, because when it is not empty it is why the reader is here.
            // Only once the site is paired: without that, the phone cannot know.
            if site.paired && access.current.owner {
                SiteConnectionsSection(store: connections)
            }

            pairSection
            websiteSection
            companionSection
        }
        .listStyle(.insetGrouped)
        .srPaper()
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        // The moment of pairing is the onboarding: ask about the household here.
        .srSharingQuestion(companion: companion, onPairing: true)
        .task {
            await site.check()
            await connections.refresh()
        }
        .sheet(isPresented: $scanning, onDismiss: { confirmScanned = scanned != nil }) {
            PairingScanner { value in
                do { scanned = try PairingPayload.parse(value) }
                catch {
                    scanned = nil
                    pairing.message = error.localizedDescription
                }
            }
        }
        .sheet(item: $pairing.pending, onDismiss: { Task { await site.check() } }) { _ in
            ConfirmIdentitySheet(pairing: pairing, companion: companion)
        }
        // The origin, shown before anything is sent to it. A QR is a URL
        // somebody else controls, so the confirmation names where it points.
        .alert("Connect to this server?", isPresented: $confirmScanned) {
            Button("Cancel", role: .cancel) { scanned = nil }
            Button("Connect") {
                if let payload = scanned {
                    scanned = nil
                    Task {
                        await pairing.scanned(payload, companion: companion)
                        await site.check()
                    }
                }
            }
        } message: { Text(scanned?.server ?? "") }
        .confirmationDialog("Disconnect this iPhone?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await companion.disconnect() } }
        } message: {
            Text("Stops syncing, pauses location sharing and revokes this device. Health records already uploaded stay on the website.")
        }
    }

    /// The one code: scanned, or typed when the other screen is not to hand.
    private var pairSection: some View {
        Section {
            Button {
                SRHaptic.tap()
                typing = false
                scanned = nil
                scanning = true
            } label: {
                SRRow(title: pairing.busy ? "Connecting…" : "Pair with a code",
                      subtitle: "Scan it at strangeramblings.com/welcome",
                      icon: "qrcode.viewfinder")
            }
            .buttonStyle(.plain)
            .disabled(pairing.busy)
            .srGlassRow()
            .accessibilityIdentifier("pair-scan")

            typedCode

            if let message = pairing.message {
                Text(message)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .srGlassRow()
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("pair-message")
            }
        } header: {
            SRSectionLabel(text: "Pair this iPhone")
        } footer: {
            Text("One code connects everything: chat, news, health and location. It only works on a phone signed in as the person it was made for — the app checks, and asks you to sign in if it needs to.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .padding(.vertical, 4)
        }
    }

    private var typedCode: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Or type it")
            Group {
                if showCode { TextField("Pairing code", text: $typed) }
                else { SecureField("Pairing code", text: $typed) }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(SR.Text.body(15))
            .padding(.horizontal, 12).padding(.vertical, 12)
            .frame(minHeight: SR.tapTarget)
            .background(SR.surface)
            .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
            .focused($typing)
            .submitLabel(.go)
            .onSubmit { redeem(typed, server: nil) }

            Toggle(isOn: $showCode) {
                Text("Show pairing code").font(SR.Text.secondary()).foregroundStyle(SR.inkSecondary)
            }
            .tint(SR.accent)

            Button { redeem(typed, server: nil) } label: {
                Text("CONNECT")
                    .font(SR.Text.label())
                    .tracking(1.3)
                    .foregroundStyle(SR.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(pairing.busy || typed.isEmpty ? SR.inkGhost : SR.accent)
            }
            .buttonStyle(.plain)
            .disabled(pairing.busy || typed.isEmpty)
            .accessibilityIdentifier("pair-typed")
        }
        .padding(.vertical, 10)
        .srGlassRow()
    }

    /// The website's credential: who this phone is signed in as, and a way out.
    @ViewBuilder
    private var websiteSection: some View {
        if site.paired {
            Section {
                SRRow(title: "Connected", subtitle: site.ownerEmail, icon: "checkmark.circle.fill", tone: SR.good)
                    .srGlassRow()
                Button(role: .destructive) { SRHaptic.tap(); site.signOut() } label: {
                    SRRow(title: "Disconnect from the website", icon: "xmark.circle", tone: SR.error)
                }
                .buttonStyle(.plain)
                .srGlassRow()
                if let message = site.message {
                    Text(message)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .srGlassRow()
                        .padding(.vertical, 6)
                }
            } header: {
                SRSectionLabel(text: "The website", trailing: "Connected")
            } footer: {
                Text("Chat threads, the news desk, your health figures and alerts. A device token, not a password — the website can revoke it at any moment, and it expires after ninety days.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .padding(.vertical, 4)
            }
        }
    }

    /// The companion's credential: health uploads and family location.
    @ViewBuilder
    private var companionSection: some View {
        if companion.paired {
            Section {
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
            } header: {
                SRSectionLabel(text: "Health & location", trailing: "Connected")
            } footer: {
                Text("Apple Health uploads and family location. A different server and a different credential: disconnecting either leaves the other running.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .padding(.vertical, 4)
            }
        } else if site.paired {
            // Paired to the site but not the companion — someone whose health
            // connection was turned off, or never offered. Fetched through the
            // site, so it is the same person; not in the family, nothing happens.
            Section {
                Button {
                    SRHaptic.tap()
                    Task {
                        if let problem = await CodePairing.connectCompanion(companion, replacing: false) {
                            pairing.message = problem
                        }
                    }
                } label: {
                    SRRow(title: companion.busy ? "Connecting…" : "Connect health & location", icon: "heart.text.square")
                }
                .buttonStyle(.plain)
                .disabled(companion.busy)
                .srGlassRow()
                .accessibilityIdentifier("companion-connect")
            } header: {
                SRSectionLabel(text: "Health & location")
            }
        }
    }

    private func redeem(_ code: String, server: URL?) {
        guard !pairing.busy, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        typing = false
        Task {
            if await pairing.pair(code: code, server: server, companion: companion) == .connected {
                typed = ""
                await site.check()
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
                    // Its own sheet, never a sync: a sync runs on every return
                    // to the foreground, and these went grey under the thumb.
                    .disabled(companion.askingHealth)
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
                .disabled(companion.askingHealth || outbox.state.healthEnabled.isEmpty)
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
                    get: { companion.profile?.stepsSharing == true },
                    set: { value in Task { await companion.setStepsSharing(value) } }
                )) {
                    Text("Share daily steps with my family")
                        .font(SR.Text.body(16))
                        .foregroundStyle(SR.ink)
                }
                .tint(SR.accent)
                // Not while `me` has not answered (unpaired, or the first
                // sync since launch still uploading): off would be a guess,
                // and flipping a guess shows nothing.
                .disabled(companion.savingSteps || companion.profile == nil)
                .srGlassRow()
                Text("Off by default. When enabled, family members can see your daily count and ranking in the app, widgets and step notifications. This is separate from private Health uploads and location sharing.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            } header: { SRSectionLabel(text: "Family steps consent") }

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
                .disabled(companion.savingSharing)
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
                Text("Permitted family members see your shared location and journey status. Parents may see their named wards’ history. Daily steps are shared only if you enable the separate steps option above.")
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
    @ObservedObject private var update = AppUpdate.shared
    @State private var checking = false
    /// Every release's notes, on request. Its own sheet: About is already
    /// inside the router's one.
    @State private var showingNotes = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        // A TestFlight build is 0.1.<run> with <run> as its build number too
        // (testflight.yml), so the build only earns a mention when it differs.
        return short.hasSuffix(".\(build)") ? short : "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                SRRow(title: "Version") {
                    Text(version).font(SR.Text.mono(13)).foregroundStyle(SR.inkMuted)
                }
                .srGlassRow()
                // Installed from strangeramblings.com/app: nothing updates it
                // but this (AppUpdate), so it can be asked for, too.
                if AppUpdate.isAdHoc {
                    Button {
                        checking = true
                        Task { await update.check(force: true); checking = false }
                    } label: {
                        SRRow(title: "Check for updates", icon: "arrow.down.circle") {
                            if checking { ProgressView() }
                            else if update.upToDate { Text("Up to date").font(SR.Text.mono(13)).foregroundStyle(SR.inkMuted) }
                        }
                    }
                    .disabled(checking)
                    .srGlassRow()
                }
                Button { showingNotes = true } label: {
                    SRRow(title: "What's new", icon: "sparkles") {
                        Image(systemName: "chevron.right").foregroundStyle(SR.inkMuted)
                    }
                }
                .srGlassRow()
                .accessibilityIdentifier("about-whats-new")
                Link(destination: SiteClient.shared.webURL("welcome")) {
                    SRRow(title: "Pairing on the web", icon: "safari") {
                        Image(systemName: "arrow.up.forward").foregroundStyle(SR.inkMuted)
                    }
                }
                .srGlassRow()
            } header: {
                SRSectionLabel(text: "This app")
            }

            Section {
                Text("""
                     Your Health uploads are stored on the server for your dashboard. \
                     Family steps are shared only when you turn on the separate steps \
                     option. The site owner's Health dashboard may publish selected figures.

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
                Text("Inter Display, DM Sans, DM Mono and JetBrains Mono, all under the SIL Open Font Licence. Their licences ship in the app bundle.")
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
        .sheet(isPresented: $showingNotes) {
            WhatsNewSheet(releases: WhatsNew.all(owner: AccessStore.shared.current.owner), history: true)
        }
    }
}

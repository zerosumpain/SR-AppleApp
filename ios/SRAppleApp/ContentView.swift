import SwiftUI
import MapKit

private let paper = Color(red: 0.929, green: 0.894, blue: 0.831)
private let ink = Color(red: 0.102, green: 0.063, blue: 0.031)
private let accent = Color(red: 0.769, green: 0.341, blue: 0.039)
struct ContentView: View {
    @ObservedObject var companion: Companion
    @ObservedObject var outbox: Outbox
    @ObservedObject var location: LocationCollector
    @State private var server = ""
    @State private var code = ""
    @State private var tab = 0
    @State private var confirmDisconnect = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("STRANGE RAMBLINGS / APPLE").font(.system(.caption, design: .monospaced)).tracking(1)
                    Text("A little closer.").font(.system(size: 44, weight: .black)).tracking(-2).accessibilityAddTraits(.isHeader)
                    Text("Your health stays yours. Your family can see your shared location.").foregroundStyle(.secondary)
                    Divider()
                    if companion.paired {
                        Text(companion.profile.map { "Connected as \($0.name)" } ?? "Connected device").font(.headline)
                        Picker("View", selection: $tab) { Text("Sync").tag(0); Text("My health").tag(1); Text("Family").tag(2) }.pickerStyle(.segmented)
                        if tab == 0 { settings }
                        if tab == 1 { healthView }
                        if tab == 2 { familyView }
                    } else { pairing }
                    Divider()
                    Text(companion.message).font(.callout).accessibilityIdentifier("sync-status")
                    if let last = companion.lastUpload { Text("Last uploaded \(last.formatted())").font(.caption) }
                    Text("\(companion.queueCount) records waiting to upload").font(.caption)
                }.padding(22)
            }.background(paper).foregroundStyle(ink).tint(accent)
                .navigationTitle("SR Companion").navigationBarTitleDisplayMode(.inline)
                .confirmationDialog("Disconnect this iPhone?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                    Button("Disconnect", role: .destructive) { Task { await companion.disconnect() } }
                } message: { Text("Stops syncing, pauses location sharing and revokes this device. Already uploaded health records remain on the website.") }
        }
    }
    private var pairing: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect your iPhone").font(.title2.bold())
            Text("Sign in to the companion website and open Connect & privacy to create a pairing code.")
            TextField("HTTPS server address", text: $server).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            SecureField("One-time pairing code", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            Button("Connect") { Task { await companion.pair(server: server, code: code); if companion.paired { code = "" } } }.buttonStyle(.borderedProminent).disabled(companion.busy || code.isEmpty)
            Text("Health and location uploads start only after you choose to enable them.").font(.caption)
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("My health permissions").font(.title2.bold())
            Text("Selected categories are sent to your private server dashboard. Family members cannot read them. Initial sync includes up to 30 days.").font(.callout)
            ForEach(["steps", "heart_rate", "resting_heart_rate", "sleep", "workout"], id: \.self) { kind in
                Toggle(HealthCollector.labels[kind]!, isOn: Binding(get: { outbox.state.healthEnabled.contains(kind) }, set: { companion.setHealth(kind, enabled: $0) })).disabled(companion.busy)
            }
            Button("Review Apple Health permissions") { Task { await companion.authorizeHealth() } }.buttonStyle(.bordered).disabled(companion.busy || outbox.state.healthEnabled.isEmpty)
            Text("Apple does not reveal whether you denied read access. Missing records may mean no data or no permission. Turning a category off stops future uploads; delete existing uploads on the website.").font(.caption)
            Divider()
            Toggle("Share location with my family", isOn: Binding(get: { outbox.state.sharing }, set: { value in Task { await companion.setSharing(value) } }))
            Text(location.status).font(.callout)
            Button("Enable Always location access") { location.requestAlways() }.disabled(!outbox.state.sharing)
            Text("Targets: 10 minutes stationary, 30 seconds moving. iOS may pause or delay updates. Frequent GPS use affects battery life. Reopen after force-quitting.").font(.caption)
            Button(companion.busy ? "Syncing…" : "Sync now") { Task { await companion.sync() } }.buttonStyle(.borderedProminent).disabled(companion.busy)
            Button("Disconnect this iPhone", role: .destructive) { confirmDisconnect = true }.disabled(companion.busy)
        }
    }
    private var healthView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Only you can see this").font(.title2.bold())
            if companion.records.isEmpty { Text("No uploaded health records yet. Enable categories in Sync and review Apple Health permissions.") }
            ForEach(companion.records.prefix(50)) { record in
                VStack(alignment: .leading, spacing: 5) {
                    Text(HealthCollector.labels[record.kind] ?? record.kind).font(.headline)
                    if let stage = record.stage { Text(stage.replacingOccurrences(of: "_", with: " ")) }
                    if let activity = record.activity { Text(activity) }
                    if let value = record.value { Text("\(value.formatted()) \(record.unit ?? "")").font(.title3.bold()) }
                    Text(record.source).font(.caption)
                    Text(record.start).font(.caption).foregroundStyle(.secondary)
                }
                Divider()
            }
            Text("Latest uploaded records. Heart rate is not a live feed. Sleep records can overlap between sources.").font(.caption)
        }
    }
    private var familyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Family locations").font(.title2.bold())
            if companion.family.isEmpty { Text("No family locations available.") }
            ForEach(companion.family) { member in
                VStack(alignment: .leading, spacing: 8) {
                    Text(member.name).font(.headline)
                    if let point = member.location {
                        Text("Recorded \(point.recorded)").font(.caption)
                        let stale = (ISO8601DateFormatter().date(from: point.recorded)?.timeIntervalSinceNow ?? -.infinity) < -1200
                        Text(stale ? "Stale location" : "Latest available location").foregroundStyle(stale ? accent : ink)
                        Text("Accuracy ±\(Int(point.accuracy)) m · \(point.moving ? "Moving" : "Stationary")").font(.caption)
                        Button("Open in Maps") {
                            MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))).openInMaps()
                        }
                    } else { Text(member.sharing ? "Waiting for a location" : "Location sharing paused") }
                }; Divider()
            }
            Button("Refresh family locations") { Task { do { try await companion.refresh() } catch { companion.message = error.localizedDescription } } }
        }
    }
}

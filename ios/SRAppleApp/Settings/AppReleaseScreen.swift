import SwiftUI

/// Settings → Release to the family: the owner chooses which build of the app
/// the family's phones are offered, from his own phone (John, 2026-10-27:
/// "release new versions of the app to the family instead of having to go to
/// the main site").
///
/// The same record and the same copies as /admin/access/app#releases
/// (`GET|POST /api/native/app-release`): a newer copy is a release, an older
/// one a roll back, and /app, /install and every family phone's hourly update
/// check follow at once. Only copies GitHub still holds as ad-hoc builds are
/// here — a merge to main makes one; a branch's TestFlight upload does not.
struct AppReleases: Decodable, Equatable {
    struct Current: Decodable, Equatable {
        let build: Int
        let commit: String?
        let at: String
        let by: String?
    }

    struct Build: Decodable, Equatable, Identifiable {
        let run: Int
        let commit: String?
        let builtAt: String?
        let version: String
        /// "released", "waiting" (newer than the family's) or "older".
        let state: String
        var id: Int { run }
    }

    struct TestFlight: Decodable, Equatable {
        let build: Int
        let commit: String?
        let at: String?
        let branch: String?
    }

    let release: Current?
    let offered: Int?
    let builds: [Build]
    let testflight: TestFlight?

    /// The newest copy the family have not been given: the one to release.
    var next: Build? { builds.filter { $0.state == "waiting" }.max { $0.run < $1.run } }
}

@MainActor
final class AppReleaseStore: ObservableObject {
    @Published private(set) var releases: AppReleases?
    @Published private(set) var loading = false
    /// The build on its way to the family; one at a time.
    @Published private(set) var releasing: Int?
    @Published var message: String?
    @Published var done: String?

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            // As the owner's own phone, whoever the app is being viewed as.
            let fresh: AppReleases = try await SiteClient.shared.send("api/native/app-release", asSelf: true)
            if fresh != releases { releases = fresh }
            message = nil
        } catch {
            message = "Could not read the releases: \(error.localizedDescription)"
        }
    }

    func release(_ build: AppReleases.Build) async {
        guard releasing == nil else { return }
        releasing = build.run
        defer { releasing = nil }
        struct Reply: Decodable { let released: Int }
        do {
            let body = try JSONEncoder().encode(["build": build.run])
            let _: Reply = try await SiteClient.shared.send("api/native/app-release", method: "POST", body: body, asSelf: true)
            SRHaptic.ok()
            done = "The family are offered \(build.version) now."
            await load()
        } catch {
            SRHaptic.bad()
            message = "Not released: \(error.localizedDescription)"
        }
    }
}

struct AppReleaseScreen: View {
    @StateObject private var store = AppReleaseStore()
    /// The build waiting on "Release …?" or "Roll back …?".
    @State private var confirming: AppReleases.Build?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(familyLine)
                        .font(SR.Text.title(17))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("This phone runs \(Self.thisBuild).")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                    if let next = store.releases?.next {
                        Button {
                            SRHaptic.tap()
                            confirming = next
                        } label: {
                            Label(store.releasing == next.run ? "Releasing…" : "Release \(next.version) to the family",
                                  systemImage: "paperplane.fill")
                                .font(SR.Text.title(16))
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SR.accent)
                        .disabled(store.releasing != nil)
                        .padding(.top, 4)
                        .accessibilityIdentifier("app-release-next")
                    }
                }
                .padding(.vertical, 6)
                .srGlassRow()
            } footer: {
                if let done = store.done {
                    Text(done).foregroundStyle(SR.good)
                } else if let message = store.message {
                    Text(message).foregroundStyle(SR.error)
                }
            }

            if let builds = store.releases?.builds, !builds.isEmpty {
                Section {
                    ForEach(builds) { row($0) }
                } header: {
                    SRSectionLabel(text: "Copies GitHub holds", trailing: "\(builds.count)")
                } footer: {
                    Text("Releasing one offers it to every family phone at once: /app, the install link and the app's own update check. An older one rolls the family back.")
                }
            }

            if let testflight = store.releases?.testflight, let branch = testflight.branch, branch != "main" {
                Section {
                    Text("The newest TestFlight build, \(testflight.build), came from \(branch). The family get a build only once it is merged to main.")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .srGlassRow()
                }
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.quiet)
        .navigationTitle("Release to the family")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.releases == nil && store.loading { ProgressView().tint(SR.accent) }
        }
        .task { await store.load() }
        .srRefreshable { await store.load() }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            if let build = confirming {
                Button(build.state == "older" ? "Roll back to \(build.version)" : "Release \(build.version)") {
                    Task { await store.release(build) }
                }
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text("Every family phone is offered it straight away. You can change your mind here at any time.")
        }
        .accessibilityIdentifier("app-release-screen")
    }

    private var familyLine: String {
        guard let releases = store.releases else { return store.loading ? "Reading the releases…" : "Releases could not be read." }
        guard let current = releases.release else { return "Nothing has been released to the family yet." }
        let version = releases.builds.first { $0.run == (releases.offered ?? current.build) }?.version ?? "0.1.\(current.build)"
        let when = parseTimestamp(current.at).map { " since \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""
        return "The family are on \(version)\(when)."
    }

    private var confirmTitle: String {
        guard let build = confirming else { return "" }
        return build.state == "older" ? "Roll the family back to \(build.version)?" : "Release \(build.version) to the family?"
    }

    private func row(_ build: AppReleases.Build) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(build.version).font(SR.Text.title(16)).foregroundStyle(SR.ink)
                    chip(build.state)
                }
                Text(built(build)).font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 8)
            if build.state != "released" {
                Button(build.state == "older" ? "Roll back" : "Release") {
                    SRHaptic.tap()
                    confirming = build
                }
                .font(SR.Text.title(14))
                .buttonStyle(.bordered)
                .tint(build.state == "older" ? SR.inkSecondary : SR.accent)
                .disabled(store.releasing != nil)
                .accessibilityIdentifier("app-release-\(build.run)")
            }
        }
        .padding(.vertical, 4)
        .srGlassRow()
    }

    private func chip(_ state: String) -> some View {
        let (text, tone): (String, Color) = {
            switch state {
            case "released": return ("Family", SR.good)
            case "waiting": return ("New", SR.accent)
            default: return ("Older", SR.inkMuted)
            }
        }()
        return Text(text.uppercased())
            .font(SR.Text.label(10))
            .tracking(0.6)
            .foregroundStyle(tone)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tone.opacity(0.14)))
    }

    private func built(_ build: AppReleases.Build) -> String {
        let when = build.builtAt.flatMap(parseTimestamp).map { "Built \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Build \(build.run)"
        let commit = build.commit.map { " · \($0.prefix(7))" } ?? ""
        return when + commit
    }

    /// "0.1.174 (174)", from the bundle.
    static var thisBuild: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

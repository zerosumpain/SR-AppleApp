import SwiftUI
import UIKit

/// "A new version is ready", for a copy installed from strangeramblings.com/app.
///
/// That copy is signed ad hoc (scripts/asc-adhoc.py) for phones that cannot use
/// TestFlight, and nothing updates it: iOS only updates what the App Store or
/// TestFlight installed. So it asks SR-Main (`/api/native/app-update`) for the
/// newest copy and, when that is newer, offers the same `itms-services:` link
/// the /app page uses. iOS still asks before installing; this only means the
/// person does not have to know when to look.
///
/// A TestFlight copy asks too, but takes only a build the owner SENT this
/// phone (`pushed`, from /admin/access/app → Send a build): TestFlight updates
/// itself, so the family's build is never its business. A pushed build is
/// offered whatever this phone runs — older is a rollback — and a push of
/// category `app-update` makes the app ask at once rather than within the hour.
/// An Xcode run never asks (no `SRCommit`).
@MainActor
final class AppUpdate: ObservableObject {
    static let shared = AppUpdate()

    struct Available: Equatable {
        let version: String
        let build: String
        let install: URL
        /// Sent to this phone by the owner, rather than the family's build.
        var pushed = false
    }

    /// What a push of this category is: the owner sent this phone a build.
    nonisolated static let pushCategory = "app-update"

    @Published private(set) var available: Available?
    /// Set by a check that found nothing newer, for Settings → About.
    @Published private(set) var upToDate = false

    private struct Reply: Decodable {
        struct Build: Decodable {
            let version: String
            let build: String
            let commit: String?
            let install: String
            let pushed: Bool?
        }
        let build: Build?
    }

    /// Ad hoc: the only kind of copy that ships its provisioning profile, and
    /// was built by CI (which stamps `SRCommit`). An Xcode run has the first
    /// but not the second.
    // Nonisolated: facts about the bundle, read by `PhoneIdentity` from any
    // request builder, which the main actor's class would otherwise forbid.
    nonisolated static var isAdHoc: Bool {
        Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil && !ownCommit.isEmpty
    }

    nonisolated static var ownCommit: String { (Bundle.main.infoDictionary?["SRCommit"] as? String) ?? "" }
    static var ownBuild: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0 }

    /// Newer means a later build of DIFFERENT code. Adding a phone rebuilds the
    /// same commit under a new number, and that is not worth an install.
    static func isNewer(build: String, commit: String?, thanBuild own: Int, commit ownCommit: String) -> Bool {
        (Int(build) ?? 0) > own && commit != ownCommit
    }

    /// Whether to offer what the site answered. A build the owner sent this
    /// phone: any build but the one it runs. The family's: an ad-hoc copy only,
    /// and only a later build of different code.
    static func shouldOffer(build: String, commit: String?, pushed: Bool, adHoc: Bool, thanBuild own: Int, commit ownCommit: String) -> Bool {
        if pushed { return (Int(build) ?? 0) > 0 && Int(build) != own }
        return adHoc && isNewer(build: build, commit: commit, thanBuild: own, commit: ownCommit)
    }

    private var lastChecked: Date?
    private static let snoozePrefix = "appUpdate.snoozedUntil."

    /// On launch and on each return to the foreground, at most hourly; `force`
    /// from Settings. Quiet on every failure: no prompt is the safe answer.
    func check(force: Bool = false) async {
        guard !Self.ownCommit.isEmpty, !SRDemo.isOn, SiteClient.shared.isPaired else { return }
        if !force, let lastChecked, Date().timeIntervalSince(lastChecked) < 3600 { return }
        lastChecked = Date()
        guard let reply: Reply = try? await SiteClient.shared.send("api/native/app-update", asSelf: true) else { return }
        guard let latest = reply.build, let url = URL(string: latest.install),
              Self.shouldOffer(build: latest.build, commit: latest.commit, pushed: latest.pushed == true, adHoc: Self.isAdHoc,
                               thanBuild: Self.ownBuild, commit: Self.ownCommit)
        else {
            available = nil
            upToDate = true
            return
        }
        upToDate = false
        if !force, let until = UserDefaults.standard.object(forKey: Self.snoozePrefix + latest.build) as? Date, until > Date() { return }
        available = Available(version: latest.version, build: latest.build, install: url, pushed: latest.pushed == true)
    }

    /// Ask again tomorrow about this build.
    func later() {
        if let available {
            UserDefaults.standard.set(Date().addingTimeInterval(24 * 3600), forKey: Self.snoozePrefix + available.build)
        }
        available = nil
    }

    /// Hand the install link to iOS, which asks, then replaces the app in place.
    func install() {
        guard let available else { return }
        self.available = nil
        UIApplication.shared.open(available.install)
    }
}

extension View {
    /// The prompt itself, on the app's root.
    func appUpdatePrompt(_ update: AppUpdate) -> some View {
        alert(
            update.available?.pushed == true ? "A version of SR was sent to this phone" : "A new version of SR is ready",
            isPresented: Binding(get: { update.available != nil }, set: { if !$0, update.available != nil { update.later() } }),
            presenting: update.available
        ) { _ in
            Button("Update") { update.install() }
            Button("Later", role: .cancel) { update.later() }
        } message: { available in
            Text("Version \(available.version). Tap Install when your phone asks; you stay signed in.")
        }
    }
}

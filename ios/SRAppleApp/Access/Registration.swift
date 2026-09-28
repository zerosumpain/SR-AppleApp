import Foundation
import SwiftUI
import AuthenticationServices
import UserNotifications

/// Joining from the app: sign in with Google or Apple, then wait for the owner.
///
/// Before this, every person was added on the website first and then paired the
/// phone by scanning a QR from a second screen. Now a person who downloads the
/// app first signs in here; the site records a request and hands the phone a
/// credential that can reach exactly one thing — `/api/native/me`, which says
/// whether the request is still pending. Until the owner approves it the app
/// shows `ReviewScreen` and nothing else: no tabs, no Health, no Today.
///
/// Approval turns the same credential into an ordinary member's. The phone
/// then asks the site for its companion pairing (`api/native/companion-pair`)
/// so health and location connect without a QR.
///
/// Spec: SR-Main docs/superpowers/specs/2026-09-28-people-and-app-registration.md
enum RegistrationStatus: String, Codable {
    /// Signed in, waiting for the owner.
    case pending
    /// The owner said no. The credential still answers `me`, so the screen can say so.
    case declined
    /// Approved: the app proper.
    case active
}

/// Which of the three things the app shows. PURE, so the rule is testable.
enum AppEntry: Equatable {
    case welcome
    case reviewing(RegistrationStatus)
    case app
}

enum EntryPolicy {
    /// - A phone paired either way — the owner's, a family member's from a QR —
    ///   is the app, whatever else is true. Nobody set up today sees Welcome.
    /// - A registrant still waiting (or declined) sees the review screen: the
    ///   site credential they hold reaches nothing else.
    /// - "I have a pairing code" (`skipped`) is the old way in, kept.
    static func entry(
        status: RegistrationStatus?,
        sitePaired: Bool,
        companionPaired: Bool,
        skipped: Bool,
        demo: Bool = false
    ) -> AppEntry {
        if demo { return .app }
        if sitePaired, let status, status != .active { return .reviewing(status) }
        if companionPaired || sitePaired || skipped || status == .active { return .app }
        return .welcome
    }
}

@MainActor
final class RegistrationStore: ObservableObject {
    static let shared = RegistrationStore()

    /// Nil until this phone has signed in from Welcome. Persisted, so a
    /// registrant who opens the app offline still sees the review screen.
    @Published private(set) var status: RegistrationStatus?
    @Published private(set) var name: String?
    @Published private(set) var email: String?
    /// "I have a pairing code": the Welcome screen is set aside for good.
    @Published private(set) var skipped: Bool
    @Published var busy = false
    @Published var message: String?

    private static let key = "registration"
    /// Where Google's sign-in hands back. Not registered in Info.plist:
    /// `ASWebAuthenticationSession` catches its own callback scheme.
    static let callbackScheme = "srapp"

    private struct Saved: Codable {
        var status: RegistrationStatus?
        var name: String?
        var email: String?
        var skipped: Bool
    }

    private init() {
        #if DEBUG
        // UI tests: every run starts as a phone nobody has set up, whatever
        // an earlier test on the same simulator chose.
        if ProcessInfo.processInfo.arguments.contains("-SRFreshInstall") {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
        #endif
        let saved = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        status = saved?.status
        name = saved?.name
        email = saved?.email
        skipped = saved?.skipped ?? false
        #if DEBUG
        if SRDemo.isRegistrant {
            status = .pending
            name = "Sam"
            email = "sam@example.com"
        }
        #endif
    }

    private func persist() {
        #if DEBUG
        if SRDemo.isOn || SRDemo.isRegistrant { return }
        #endif
        let saved = Saved(status: status, name: name, email: email, skipped: skipped)
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func entry(companionPaired: Bool) -> AppEntry {
        #if DEBUG
        if SRDemo.isRegistrant { return .reviewing(.pending) }
        return EntryPolicy.entry(status: status, sitePaired: SiteClient.shared.isPaired,
                                 companionPaired: companionPaired, skipped: skipped, demo: SRDemo.isOn)
        #else
        return EntryPolicy.entry(status: status, sitePaired: SiteClient.shared.isPaired,
                                 companionPaired: companionPaired, skipped: skipped)
        #endif
    }

    func skipToPairing() {
        skipped = true
        persist()
    }

    // MARK: - Signing in

    /// Google, through the website's own sign-in in a private browser sheet.
    /// The site ends at `srapp://registered?code=…` with a one-time code.
    func signInWithGoogle(_ session: WebAuthenticationSession) async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            let start = SiteClient.shared.webURL("native/register?provider=google")
            let callback = try await session.authenticate(
                using: start,
                callbackURLScheme: Self.callbackScheme,
                preferredBrowserSession: .ephemeral
            )
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let error = items.first(where: { $0.name == "error" })?.value {
                message = error
                return
            }
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                message = "The sign-in did not finish. Try again."
                return
            }
            try await SiteClient.shared.redeem(code: code)
            await refresh()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Closing the sheet is a choice, not a failure.
        } catch {
            message = error.localizedDescription
        }
    }

    /// Sign in with Apple, natively. The site checks the identity token against
    /// Apple's public keys and answers with the same one-time code.
    func signInWithApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { message = error.localizedDescription }
            return
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                message = "Apple did not send a sign-in. Try again."
                return
            }
            // Apple gives the name only on the FIRST sign-in, so it travels now
            // or never; the site keeps it with the request.
            let given = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            busy = true
            message = nil
            defer { busy = false }
            do {
                struct Code: Decodable { let code: String }
                var body = ["identityToken": token]
                if !given.isEmpty { body["name"] = given }
                let reply: Code = try await SiteClient.shared.sendAnonymous(
                    "api/native/register/apple", body: try JSONEncoder().encode(body)
                )
                try await SiteClient.shared.redeem(code: reply.code)
                await refresh()
            } catch {
                message = error.localizedDescription
            }
        }
    }

    // MARK: - Waiting

    private struct Me: Decodable {
        let role: String?
        let status: String?
        let name: String?
        let email: String?
        let ownerEmail: String?
    }

    /// Ask the site where this phone stands. Returns true when this call is
    /// the one that found the request approved.
    @discardableResult
    func refresh() async -> Bool {
        guard SiteClient.shared.isPaired else { return false }
        do {
            let data = try await SiteClient.shared.call("api/native/me", method: "GET")
            let me = try JSONDecoder().decode(Me.self, from: data)
            let before = status
            if me.role == "registrant" {
                status = RegistrationStatus(rawValue: me.status ?? "") ?? .pending
                name = me.name ?? name
                email = me.email ?? email
            } else {
                // A member or the owner. Only a phone that registered here
                // records it; a phone paired by QR never had a status.
                if status != nil { status = .active }
                let flags = (try? JSONDecoder().decode(AppAccess.self, from: data)) ?? .nothing
                AccessStore.shared.adopt(siteRole: me.role, flags: flags)
            }
            persist()
            return before != nil && before != .active && status == .active
        } catch SiteError.expired {
            // Withdrawn or revoked on the website: back to the start.
            reset()
            return false
        } catch {
            // Offline is not an answer. Keep what we had.
            return false
        }
    }

    /// Approved: connect health and location through the site, no QR. A
    /// refusal (not in the family) is fine — Health just stays unconnected.
    func connectCompanion(_ companion: Companion) async {
        guard status == .active, !companion.paired, SiteClient.shared.isPaired else { return }
        struct Pair: Decodable { let server: String; let code: String }
        guard let pair: Pair = try? await SiteClient.shared.send(
            "api/native/companion-pair", method: "POST", body: Data("{}".utf8)
        ) else { return }
        await companion.pair(server: pair.server, code: pair.code)
    }

    /// Take the request back: the site deletes it and this phone's credential.
    func withdraw() async {
        busy = true
        defer { busy = false }
        _ = try? await SiteClient.shared.call("api/native/register", method: "DELETE")
        SiteClient.shared.signOut()
        reset()
    }

    /// Sign out on this phone only; the request stays with the owner.
    func signOut() {
        SiteClient.shared.signOut()
        reset()
    }

    private func reset() {
        status = nil
        name = nil
        email = nil
        message = nil
        persist()
    }

    /// From a background refresh: if the owner approved while the app was
    /// shut, say so once.
    static func backgroundPass() async {
        let store = RegistrationStore.shared
        guard let status = store.status, status != .active else { return }
        guard await store.refresh() else { return }
        let content = UNMutableNotificationContent()
        content.title = "You're in"
        content.body = "Your Strange Ramblings account was approved. Open the app to get started."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "registration-approved", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

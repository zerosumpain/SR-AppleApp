import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit

/// One code connects the whole phone — the site, and through it health &
/// location — and only for the person it was made for.
///
/// There used to be two QR codes at /welcome, each minted for whoever was
/// signed in to the browser showing them. On 2026-10-19 the owner's son scanned
/// both from the owner's screen and his phone became the owner's: owner chat,
/// and his Apple Health and location uploaded into the owner's record.
///
/// Now the code is redeemed with who this phone is signed in as — the site
/// credential it already holds, or, if it holds none, a Google or Apple sign-in
/// made here for this one code (`api/native/register/apple` or
/// `welcome/app?confirm=`, answered with an identity for that code alone). The
/// site connects it only if that person is the code's (SR-Main
/// `/api/native/pair`: 428 sign in first, 409 someone else's code). Health &
/// location are then fetched through the new site credential
/// (`api/native/companion-pair`), so the two pairings are always one person.
@MainActor
final class CodePairing: ObservableObject {
    static let shared = CodePairing()

    /// A code waiting on "Confirm it's you".
    struct Pending: Identifiable, Equatable {
        let id = UUID()
        let code: String
        let server: URL?
    }

    @Published var pending: Pending?
    @Published var busy = false
    /// The last refusal or failure, in the site's own words.
    @Published var message: String?

    enum Outcome: Equatable {
        case connected
        case needsSignIn
        case refused(String)
    }

    private var appleNonce: String?

    /// Redeem a scanned or typed code. `server` nil means this phone's site.
    @discardableResult
    func pair(code raw: String, server: URL?, identity: String? = nil, companion: Companion) async -> Outcome {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return refuse("Type the code from strangeramblings.com/welcome.") }
        busy = true
        defer { busy = false }
        message = nil
        do {
            try await SiteClient.shared.redeem(code: code, at: server, identity: identity)
        } catch SiteError.status(428, _) {
            pending = Pending(code: code, server: server)
            return .needsSignIn
        } catch {
            pending = nil
            return refuse(error.localizedDescription)
        }
        pending = nil
        await RegistrationStore.shared.pairedByCode()
        if let problem = await Self.connectCompanion(companion, replacing: true) {
            message = "Connected to the website. Health & location did not connect: \(problem)"
        }
        SRHaptic.ok()
        return .connected
    }

    /// Health & location through this phone's site credential: the companion
    /// pairing is always the same person as the site's. `replacing`: a phone
    /// whose companion is connected (to whoever) is disconnected first. Nil
    /// when connected, or when health & location are not this person's to
    /// have (not in the family); otherwise the reason.
    static func connectCompanion(_ companion: Companion, replacing: Bool) async -> String? {
        guard SiteClient.shared.isPaired else { return nil }
        if companion.paired && !replacing { return nil }
        struct Pair: Decodable { let server: String; let code: String }
        let pair: Pair
        do {
            pair = try await SiteClient.shared.send("api/native/companion-pair", method: "POST", body: Data("{}".utf8), asSelf: true)
        } catch SiteError.status(403, _) {
            return nil
        } catch {
            return error.localizedDescription
        }
        // Only once there is a pairing to replace it with.
        if companion.paired {
            await companion.disconnect()
            if companion.paired { return companion.message }
        }
        await companion.pair(server: pair.server, code: pair.code)
        return companion.paired ? nil : companion.message
    }

    // MARK: - Confirm it's you

    /// Google, through the site's sign-in in a private sheet, asked about this
    /// code only: the site answers `srapp://registered?identity=…`.
    func confirmWithGoogle(_ session: WebAuthenticationSession, companion: Companion) async {
        guard let pending else { return }
        do {
            let start = SiteClient.shared.webURL("welcome/app?confirm=\(Self.hash(pending.code))")
            let callback = try await session.authenticate(
                using: start,
                callbackURLScheme: RegistrationStore.callbackScheme,
                preferredBrowserSession: .ephemeral
            )
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let error = items.first(where: { $0.name == "error" })?.value { message = error; return }
            guard let identity = items.first(where: { $0.name == "identity" })?.value else {
                message = "The sign-in did not finish. Try again."
                return
            }
            await finish(pending, identity: identity, companion: companion)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Closing the sheet is a choice, not a failure.
        } catch {
            message = error.localizedDescription
        }
    }

    /// For the Apple button's request: a fresh nonce, returned hashed for Apple.
    func startAppleSignIn() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let nonce = Data(bytes).base64EncodedString()
        appleNonce = nonce
        return Self.hex(SHA256.hash(data: Data(nonce.utf8)))
    }

    /// Sign in with Apple, natively; the site checks the token and answers
    /// with an identity for this code.
    func confirmWithApple(_ result: Result<ASAuthorization, Error>, companion: Companion) async {
        guard let pending else { return }
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { message = error.localizedDescription }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else {
                message = "Apple did not send a sign-in. Try again."
                return
            }
            appleNonce = nil
            struct Identity: Decodable { let identity: String }
            do {
                let body = try JSONEncoder().encode(["identityToken": token, "nonce": nonce, "confirm": Self.hash(pending.code)])
                let reply: Identity = try await SiteClient.shared.sendAnonymous("api/native/register/apple", body: body)
                await finish(pending, identity: reply.identity, companion: companion)
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func cancel() {
        pending = nil
    }

    private func finish(_ pending: Pending, identity: String, companion: Companion) async {
        if case .refused(let why) = await pair(code: pending.code, server: pending.server, identity: identity, companion: companion) {
            message = why
        }
    }

    private func refuse(_ why: String) -> Outcome {
        message = why
        SRHaptic.bad()
        return .refused(why)
    }

    /// What the site is told instead of the code while this phone signs in.
    static func hash(_ code: String) -> String {
        hex(SHA256.hash(data: Data(code.utf8)))
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// "Confirm it's you": the sign-in a code asks for when this phone is signed
/// in as nobody yet. The code connects only if the person who signs in is the
/// one it was made for. Presented from `CodePairing.pending`, so it closes
/// itself once the code is spent or refused — the screen behind shows why.
struct ConfirmIdentitySheet: View {
    @ObservedObject var pairing: CodePairing
    let companion: Companion
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SRPageHeader(
                        kicker: "Pairing",
                        title: "Confirm it’s you",
                        strap: "A pairing code is for one person. Sign in as the person this phone is for — if the code is not theirs, nothing is connected."
                    )
                    VStack(spacing: 12) {
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.email]
                            request.nonce = pairing.startAppleSignIn()
                        } onCompletion: { result in
                            Task { await pairing.confirmWithApple(result, companion: companion) }
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 50)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("confirm-apple")

                        Button {
                            SRHaptic.tap()
                            Task { await pairing.confirmWithGoogle(webAuthenticationSession, companion: companion) }
                        } label: {
                            SRButtonLabel(title: "Continue with Google", icon: "globe", fill: true)
                        }
                        .srButton(.regular)
                        .controlSize(.large)
                        .accessibilityIdentifier("confirm-google")
                    }
                    .disabled(pairing.busy)

                    if pairing.busy { ProgressView().frame(maxWidth: .infinity) }
                    if let message = pairing.message {
                        Text(message)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.error)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("confirm-error")
                    }
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 24)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .srPaper()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { pairing.cancel(); dismiss() }
                }
            }
        }
    }
}

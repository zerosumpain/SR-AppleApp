import SwiftUI
import AuthenticationServices
import UserNotifications

/// The first screen on a phone nobody has set up: sign in to ask for an account.
///
/// Shown only when the phone holds neither pairing (see `EntryPolicy`), so
/// nobody already using the app ever sees it. "I have a pairing code" is the
/// old way in — an invite from the website, a QR on another screen — and opens
/// the app as it always opened.
struct WelcomeScreen: View {
    @ObservedObject var registration: RegistrationStore
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.colorScheme) private var colorScheme
    @State private var enteringCode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SRMark()
                    .padding(.top, 24)
                SRPageHeader(
                    kicker: "Strange Ramblings",
                    title: "Ask for an account",
                    strap: "Sign in so John knows who you are. He reviews every request, and this app opens once he has said yes."
                )

                VStack(spacing: 12) {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = registration.startAppleSignIn()
                    } onCompletion: { result in
                        Task { await registration.signInWithApple(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("welcome-apple")

                    Button {
                        SRHaptic.tap()
                        Task { await registration.signInWithGoogle(webAuthenticationSession) }
                    } label: {
                        SRButtonLabel(title: "Continue with Google", icon: "globe", fill: true)
                    }
                    .srButton(.regular)
                    .controlSize(.large)
                    .accessibilityIdentifier("welcome-google")
                }
                .disabled(registration.busy)

                if registration.busy {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if let message = registration.message {
                    Text(message)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("welcome-error")
                }

                VStack(alignment: .leading, spacing: 8) {
                    SRLabel(text: "Already invited?")
                    Button {
                        SRHaptic.select()
                        enteringCode = true
                    } label: {
                        Text("I have a pairing code")
                            .font(SR.Text.bodyMedium())
                            .foregroundStyle(SR.accentInk)
                            .underline()
                    }
                    .accessibilityIdentifier("welcome-have-code")
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.bottom, 40)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .srPaper()
        .sheet(isPresented: $enteringCode) {
            PairingCodeSheet(registration: registration)
        }
    }
}

/// "I have a pairing code": type it, or go on without one.
///
/// A typed code is asked of the site first as the App Review code, then
/// redeemed as an ordinary one-time pairing code (`RegistrationStore.submit`).
/// "Continue without a code" is the old way in — the app, unconnected, with
/// the QR scanner under Settings → Connections.
struct PairingCodeSheet: View {
    @ObservedObject var registration: RegistrationStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SRPageHeader(
                        kicker: "Already invited",
                        title: "Enter your code",
                        strap: "Type the pairing code you were given. Codes from a QR can be scanned instead, from Settings once you are in."
                    )

                    TextField("Pairing code", text: $code)
                        .font(SR.Text.mono(17))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit { Task { await submit() } }
                        .padding(14)
                        .srGlassCard()
                        .accessibilityIdentifier("code-field")

                    if let problem {
                        Text(problem)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.error)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("code-error")
                    }

                    Button {
                        SRHaptic.tap()
                        Task { await submit() }
                    } label: {
                        SRButtonLabel(title: "Continue", icon: "arrow.right", fill: true)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .disabled(registration.busy || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("code-submit")

                    if registration.busy {
                        ProgressView().frame(maxWidth: .infinity)
                    }

                    Button {
                        SRHaptic.select()
                        dismiss()
                        registration.skipToPairing()
                    } label: {
                        Text("Continue without a code")
                            .font(SR.Text.bodyMedium())
                            .foregroundStyle(SR.accentInk)
                            .underline()
                    }
                    .padding(.top, 4)
                    .accessibilityIdentifier("code-skip")
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 24)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .srPaper()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("code-cancel")
                }
            }
        }
    }

    private func submit() async {
        guard !registration.busy else { return }
        focused = false
        problem = nil
        if let refusal = await registration.submit(code: code) {
            SRHaptic.bad()
            problem = refusal
        } else {
            SRHaptic.ok()
            dismiss()
        }
    }
}

/// Signed in, and waiting. The ONLY screen a registrant can reach: no tabs,
/// no Health, nothing the owner has not said yes to.
struct ReviewScreen: View {
    @ObservedObject var registration: RegistrationStore
    let status: RegistrationStatus
    @Environment(\.scenePhase) private var scenePhase
    @State private var notifyAsked = false
    @State private var confirmWithdraw = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SRMark().padding(.top, 24)
                if status == .declined {
                    SRPageHeader(
                        kicker: "Not approved",
                        title: "Your request was not approved",
                        strap: "John has not given this account access. If you think that is a mistake, ask him directly."
                    )
                } else {
                    SRPageHeader(
                        kicker: "Waiting",
                        title: "Your account is being reviewed",
                        strap: "John has your request. This screen changes by itself once he has said yes — there is nothing else to do."
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    SRLabel(text: "Signed in as")
                    if let name = registration.name, !name.isEmpty {
                        Text(name).font(SR.Text.title()).foregroundStyle(SR.ink)
                    }
                    if let email = registration.email {
                        Text(email).font(SR.Text.mono(13)).foregroundStyle(SR.inkSecondary)
                    }
                }
                .accessibilityIdentifier("review-who")

                if status == .pending {
                    VStack(spacing: 12) {
                        Button {
                            SRHaptic.tap()
                            Task { await registration.refresh() }
                        } label: {
                            SRButtonLabel(title: "Check again", icon: "arrow.clockwise", fill: true)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .disabled(registration.busy)
                        .accessibilityIdentifier("review-check")

                        if !notifyAsked {
                            Button {
                                notifyAsked = true
                                Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
                            } label: {
                                SRButtonLabel(title: "Tell me when I'm in", icon: "bell", fill: true)
                            }
                            .srButton(.regular)
                            .controlSize(.large)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Button("Sign out on this iPhone") { registration.signOut() }
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.accentInk)
                        .accessibilityIdentifier("review-sign-out")
                    Button("Delete my account") { confirmWithdraw = true }
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.error)
                        .accessibilityIdentifier("review-withdraw")
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.bottom, 40)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .srRefreshable { await registration.refresh() }
        .srPaper()
        // App Store 5.1.1(v): a registrant's account IS the request and this
        // phone's sign-in, and withdrawing deletes both on the site.
        .confirmationDialog("Delete your account?", isPresented: $confirmWithdraw, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await registration.withdraw() } }
        } message: {
            Text("Your request, your name and email with it, and your sign-in on this iPhone are deleted. You can ask again later.")
        }
        .task { await registration.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await registration.refresh() } }
        }
    }
}

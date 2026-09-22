import SwiftUI

/// Connecting the phone to strangeramblings.com.
///
/// This is the SECOND pairing in the app and it is deliberately not the first
/// one. The companion pairing connects to the health and family server; this one
/// connects to the website for chat and news. Two servers, two credentials, so
/// that revoking one never silently takes the other with it — the screen says so
/// rather than leaving the reader to work it out from two identical buttons.
@MainActor
final class SitePairingModel: ObservableObject {
    @Published var busy = false
    @Published var message: String?
    @Published var paired = SiteClient.shared.isPaired
    @Published var ownerEmail: String?

    private struct Me: Decodable { let ownerEmail: String; let label: String?; let expiresAt: String }

    func check() async {
        guard SiteClient.shared.isPaired else { paired = false; return }
        do {
            let me: Me = try await SiteClient.shared.send("api/native/me")
            ownerEmail = me.ownerEmail
            paired = true
            message = nil
        } catch SiteError.expired {
            // The credential is gone — revoked, or ninety days old. Drop it
            // locally too, so the app stops presenting a token the server has
            // already forgotten.
            SiteClient.shared.signOut()
            paired = false
            message = "This iPhone was disconnected. Pair it again from the website."
        } catch {
            // A network failure is not a revocation. Keep the credential.
            message = "Could not reach the site. It will retry."
        }
    }

    func pair(_ payload: SitePairing) async {
        busy = true
        defer { busy = false }
        do {
            try await SiteClient.shared.pair(payload)
            paired = true
            message = nil
            await check()
        } catch {
            message = error.localizedDescription
        }
    }

    func signOut() {
        SiteClient.shared.signOut()
        paired = false
        ownerEmail = nil
        message = "Disconnected on this iPhone. Revoke it on the website too if it was lost."
    }
}

struct SitePairingScreen: View {
    @ObservedObject var model: SitePairingModel
    @State private var scanning = false
    @State private var scanned: SitePairing?
    @State private var confirming = false

    var body: some View {
        SRShell(
            path: "/jkai · /news",
            kicker: model.paired ? "Connected" : "Not connected",
            footer: [
                "Strange Ramblings",
                "A paired iPhone reads as you, and only what you can read",
                "Revoke it at /admin/access/devices",
            ]
        ) {
            SRSection {
                SectionHead(
                    kicker: "A / Connect",
                    title: model.paired ? ["Connected", "to the site"] : ["Bring the site", "to your pocket"],
                    strap: model.paired
                        ? "This iPhone can read your chat threads and the news desk. It holds a device token, not a password, and the website can revoke it at any moment."
                        : "Open Admin → Access → Devices on the website, create a pairing QR code, and scan it here. The code works once and expires in ten minutes."
                )

                if model.paired {
                    connected
                } else {
                    disconnected
                }
            }

            SRSection(tinted: true, isLast: true) {
                SRLabel(text: "What this is not")
                    .padding(.bottom, 10)
                Text("This is separate from the companion pairing on the first tab. That one connects to your health and family server; this one connects to the website. Disconnecting either leaves the other running.")
                    .font(SR.body(15))
                    .lineSpacing(4)
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await model.check() }
        .sheet(isPresented: $scanning, onDismiss: { confirming = scanned != nil }) {
            PairingScanner { value in
                do { scanned = try SitePairing.parse(value) }
                catch {
                    scanned = nil
                    model.message = error.localizedDescription
                }
            }
        }
        .alert("Connect to this server?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) { scanned = nil }
            Button("Connect") {
                if let payload = scanned {
                    scanned = nil
                    Task { await model.pair(payload) }
                }
            }
        } message: {
            // The origin, shown before anything is sent to it. A QR is a URL
            // somebody else controls, so the confirmation names where it points.
            Text(scanned?.server ?? "")
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let email = model.ownerEmail {
                Figure(value: email, label: "Signed in as")
            }
            if let message = model.message {
                Text(message)
                    .font(SR.body(14))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SRButton(title: "Disconnect this iPhone") { model.signOut() }
        }
    }

    private var disconnected: some View {
        VStack(alignment: .leading, spacing: 16) {
            SRButton(title: model.busy ? "Connecting…" : "Scan pairing code", filled: true, disabled: model.busy) {
                scanned = nil
                scanning = true
            }
            .accessibilityIdentifier("site-pair-scan")

            if let message = model.message {
                Text(message)
                    .font(SR.body(14))
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Chat and the news desk stay empty until this iPhone is connected.")
                .font(SR.body(14))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What a tab shows before the phone is paired.
struct SiteUnpairedNotice: View {
    let what: String
    let onConnect: () -> Void

    var body: some View {
        SRSection(isLast: true) {
            SectionHead(
                kicker: "A / Not connected",
                title: ["Connect to", "read \(what)"],
                strap: "This iPhone is not paired with strangeramblings.com yet. Create a pairing code under Admin → Access → Devices and scan it."
            )
            SRButton(title: "Connect", filled: true, action: onConnect)
        }
    }
}

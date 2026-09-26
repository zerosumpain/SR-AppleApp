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

    /// `role` and the flags arrived with member access; a site older than
    /// that sends neither, and `ownerEmail` may be absent for a member.
    private struct Me: Decodable {
        let ownerEmail: String?
        let label: String?
        let expiresAt: String?
        let role: String?
    }

    func check() async {
        guard SiteClient.shared.isPaired else { paired = false; return }
        do {
            let data = try await SiteClient.shared.call("api/native/me", method: "GET")
            let me = try JSONDecoder().decode(Me.self, from: data)
            // The flags sit beside `role` at the top level, so the same
            // lenient decoder reads them from the same bytes.
            let flags = (try? JSONDecoder().decode(AppAccess.self, from: data)) ?? .nothing
            AccessStore.shared.adopt(siteRole: me.role, flags: flags)
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

import SwiftUI

/// Settings → Delete account (App Store guideline 5.1.1(v): an app that
/// creates accounts lets the person delete theirs, and its data, from inside
/// the app).
///
/// Two ways to ask, because a phone may hold either pairing:
///
/// - **The website** (`DELETE /api/native/account`) when this phone has a site
///   credential. The site asks the companion server first, then deletes
///   everything it holds — synchronous, so "done" means done.
/// - **The companion server** (`POST /api/apple/account/delete`) for a phone
///   paired to it alone. It deletes what this phone uploaded at once, and the
///   website finishes the rest within a minute or two.
///
/// The OWNER's phone never offers it: the owner's account is the website's
/// configuration, and the site and the companion server both refuse anyway.
enum AccountDeletionLane: Equatable {
    /// This phone is the owner's: say where the account is managed instead.
    case ownerManaged
    case site
    case companion
    /// Nothing paired: there is nothing here to delete.
    case unpaired
}

enum AccountDeletionPolicy {
    /// What the confirm field must hold. Typed, not tapped: a second tap is
    /// too easy to give by accident for something that cannot be undone.
    static let confirmWord = "DELETE"

    /// PURE. `isOwner` is the REAL owner (`AccessStore.isRealOwner`), so
    /// viewing the app as somebody never turns the button on.
    static func lane(isOwner: Bool, sitePaired: Bool, companionPaired: Bool) -> AccountDeletionLane {
        if isOwner { return .ownerManaged }
        if sitePaired { return .site }
        if companionPaired { return .companion }
        return .unpaired
    }

    /// Case and surrounding space do not matter; the word does.
    static func confirmed(_ typed: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == confirmWord
    }

    /// What goes, in the words the screen uses. One list, so the screen and
    /// the tests agree on it.
    static let deleted: [String] = [
        "Your account and your access to Strange Ramblings",
        "Your chat threads, research, notes and workflows",
        "Your Drive files and any connected mailbox",
        "Everything this app uploaded: health records and location history",
        "Your family steps, your saved and read news, and your place on the family board",
        "Your sign-in on this iPhone and every other phone",
    ]

    static let kept: [String] = [
        "Apple Health on this iPhone — the app only ever read it",
        "Family tasks other people wrote: your name is taken off them",
        "The household's own record of you (Life360), which the owner keeps",
    ]
}

/// Runs the deletion and puts the phone back to a fresh install.
@MainActor
final class AccountDeletionStore: ObservableObject {
    @Published private(set) var busy = false
    @Published var error: String?

    /// True when the account is gone and the phone has been reset.
    func delete(lane: AccountDeletionLane, companion: Companion, site: SitePairingModel) async -> Bool {
        guard !busy else { return false }
        // The App Review demo has no account: "deleting" it is leaving the
        // demo — back to Welcome, nothing sent, nothing on the phone touched.
        // (The `-SRDemo` screenshot harness does nothing at all.)
        if ReviewDemo.isActive {
            ReviewDemo.shared.leave()
            return true
        }
        if SRDemo.isOn { return false }
        busy = true
        error = nil
        defer { busy = false }
        do {
            switch lane {
            case .site:
                do {
                    _ = try await SiteClient.shared.call("api/native/account", method: "DELETE")
                } catch SiteError.expired where companion.paired {
                    // The site credential had already gone: ask the companion server.
                    try await companion.requestAccountDeletion()
                }
            case .companion:
                try await companion.requestAccountDeletion()
            case .ownerManaged, .unpaired:
                return false
            }
        } catch SiteError.expired {
            self.error = "This iPhone is no longer signed in, so it cannot delete the account. Ask the owner to remove it."
            return false
        } catch {
            self.error = error.localizedDescription
            return false
        }
        await Self.resetPhone(companion: companion, site: site)
        return true
    }

    /// Both pairings off, the registration forgotten, the Welcome screen back.
    /// The servers have already revoked both credentials; this is the phone
    /// catching up without asking them anything.
    static func resetPhone(companion: Companion, site: SitePairingModel) async {
        await companion.forgetAfterAccountDeletion()
        site.signOut()
        AccessStore.shared.siteChanged(paired: false)
        RegistrationStore.shared.forgetAfterAccountDeletion()
    }
}

/// The screen: what goes, what stays, a typed confirmation, then the button.
struct DeleteAccountScreen: View {
    @ObservedObject var companion: Companion
    @ObservedObject var site: SitePairingModel
    let lane: AccountDeletionLane

    @StateObject private var store = AccountDeletionStore()
    @State private var typed = ""
    @State private var confirming = false

    var body: some View {
        List {
            Section {
                Text("This deletes your Strange Ramblings account and everything it holds. It cannot be undone.")
                    .font(SR.Text.body(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }

            Section {
                ForEach(AccountDeletionPolicy.deleted, id: \.self) { line in
                    SRRow(title: line, icon: "trash", tone: SR.error).srGlassRow()
                }
            } header: {
                SRSectionLabel(text: "Deleted")
            }

            Section {
                ForEach(AccountDeletionPolicy.kept, id: \.self) { line in
                    SRRow(title: line, icon: "checkmark.circle").srGlassRow()
                }
            } header: {
                SRSectionLabel(text: "Not deleted")
            } footer: {
                if lane == .companion {
                    Text("What this iPhone uploaded goes straight away; the rest of your account follows within a couple of minutes.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
            }

            Section {
                TextField("Type \(AccountDeletionPolicy.confirmWord) to confirm", text: $typed)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(SR.Text.body(15))
                    .padding(.horizontal, 12).padding(.vertical, 12)
                    .frame(minHeight: SR.tapTarget)
                    .background(SR.surface)
                    .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
                    .accessibilityIdentifier("delete-account-confirm")

                Button(role: .destructive) {
                    confirming = true
                } label: {
                    HStack {
                        Text(store.busy ? "Deleting…" : "Delete my account")
                            .font(SR.Text.bodyMedium(16))
                            .foregroundStyle(SR.error)
                        Spacer()
                        if store.busy { ProgressView() }
                    }
                    .frame(minHeight: SR.tapTarget)
                }
                .disabled(!AccountDeletionPolicy.confirmed(typed) || store.busy)
                .accessibilityIdentifier("delete-account-button")

                if let error = store.error {
                    Text(error)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                SRSectionLabel(text: "Confirm")
            }
        }
        .listStyle(.insetGrouped)
        .srPaper()
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete your account?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete account and data", role: .destructive) {
                Task { _ = await store.delete(lane: lane, companion: companion, site: site) }
            }
        } message: {
            Text("Your account and its data are deleted, and this iPhone is signed out of both connections.")
        }
    }
}

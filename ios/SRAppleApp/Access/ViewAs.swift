import SwiftUI

/// Settings → View as: the owner sees the app as somebody else would — their
/// tabs, their cards, their family view — before a permission change reaches
/// them.
///
/// The list is the site's (`previewAs`, sent in the owner's view alone), so
/// who appears here and what they are shown is decided in one place, next to
/// the rules it previews. The phone only swaps what it obeys: `AccessStore`
/// holds the choice in memory, and a relaunch is always the owner.
///
/// It is a look, not a sign-in. The site's own lanes (chat, news, games) still
/// answer as the owner, because the credential on this phone is the owner's;
/// what changes is what the app OFFERS — which is the thing access groups
/// decide on a member's phone.
struct ViewAsScreen: View {
    @ObservedObject private var access = AccessStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if access.previews.isEmpty {
                    Text("Nobody else is on the app yet — or the site has not sent their views. They arrive with the family view, every 30 seconds.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .srGlassRow()
                }
                ForEach(access.previews) { preview in
                    Button {
                        SRHaptic.tap()
                        access.view(as: preview)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preview.name).font(SR.Text.title()).foregroundStyle(SR.ink)
                                Text(Self.summary(preview.view))
                                    .font(SR.Text.mono())
                                    .foregroundStyle(SR.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            if access.viewingAs?.email == preview.email {
                                Image(systemName: "checkmark").foregroundStyle(SR.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .srGlassRow()
                    .accessibilityIdentifier("view-as-\(preview.email)")
                }
            } header: {
                SRSectionLabel(text: "See the app as")
            } footer: {
                Text("Their tabs, cards and family view, as their phone would show them. Chat, news and games still read as you. Nothing is saved: relaunching the app, or Exit on the banner, brings you back.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            if access.viewingAs != nil {
                Section {
                    Button {
                        SRHaptic.select()
                        access.view(as: nil)
                    } label: {
                        SRButtonLabel(title: "Back to yourself", icon: "arrow.uturn.backward", fill: true)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .srBareRow()
                    .accessibilityIdentifier("view-as-exit")
                }
            }
        }
        .listStyle(.insetGrouped)
        .srPaper()
        .navigationTitle("View as")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "CHAT · NEWS · FAMILY" — what their phone would offer, or "NOTHING YET".
    static func summary(_ view: HouseholdView) -> String {
        guard let flags = view.access?.flags else { return "NO ACCESS SENT" }
        let named: [(Bool, String)] = [
            (flags.chat, "chat"), (flags.news, "news"), (flags.family, "family"), (flags.games, "games"),
            (flags.research, "research"), (flags.notes, "notes"), (flags.intel, "intel"),
        ]
        let on = named.filter { $0.0 }.map { $0.1.uppercased() }
        return on.isEmpty ? "TODAY AND HEALTH ONLY" : on.joined(separator: " · ")
    }
}

/// Floating above the tab bar while the owner views the app as somebody.
struct ViewingAsBanner: View {
    let name: String
    let exit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye").font(.system(size: 13, weight: .semibold))
            Text("VIEWING AS \(name.uppercased())")
                .font(SR.Text.label())
                .tracking(1.1)
                .lineLimit(1)
            Button("Exit", action: exit)
                .font(SR.Text.bodyMedium(14))
                .padding(.leading, 4)
                .accessibilityIdentifier("viewing-as-exit")
        }
        .foregroundStyle(SR.paper)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(SR.accentDeep, in: Capsule())
        .shadow(color: SR.ink.opacity(0.2), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
    }
}

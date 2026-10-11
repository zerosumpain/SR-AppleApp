import SwiftUI
import UIKit

// MARK: - The banner at the top of every tab

extension View {
    /// The "a connection needs you" banner, docked above this tab's navigation
    /// bar for as long as anything needs the owner.
    ///
    /// Applied ONCE per tab, to the tab's ROOT view inside its
    /// `NavigationStack`, so it docks under the navigation bar and the
    /// content scrolls beneath it. NOT on the stack itself: there, iOS 26 laid
    /// the inset OVER the bar — the `sr.` mark and every toolbar button (new
    /// thread, thread actions, the settings cog) were hidden behind it and
    /// untappable. CI's screenshots and three chat UI tests caught it.
    func srConnectionsBanner(_ store: ConnectionsStore, onDetails: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            ConnectionsBanner(store: store, onDetails: onDetails)
        }
    }
}

/// The banner itself, or nothing.
///
/// Dismissable: the cross takes it down for the problems it is showing, and
/// only a new one — or one that was fixed and came back — puts it up again.
/// Everything stays listed in Settings → Connections.
///
/// What it can show depends on who is holding the phone: the site's
/// connections are the owner's alone (the server refuses anyone else), and
/// everybody sees problems with their OWN phone's health link.
struct ConnectionsBanner: View {
    @ObservedObject var store: ConnectionsStore
    let onDetails: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if store.bannerMode == .full, let lead = store.visible.first {
                full(lead)
            }
        }
        .animation(.snappy(duration: 0.25), value: store.bannerMode)
    }

    private func full(_ lead: ConnectionItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SR.error)
                    .accessibilityHidden(true)
                Text(kicker.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.4)
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { withAnimation(.snappy) { store.dismiss() } } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SR.inkMuted)
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .accessibilityHint("Hides this until something else needs you")
                .accessibilityIdentifier("connections-banner-dismiss")
            }

            // Side by side at ordinary sizes; stacked once the reader's text is
            // large enough that a button beside two lines would squeeze them to
            // a word a line.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    summary(lead)
                    fixButton(lead)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    summary(lead)
                    fixButton(lead)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .srGlassCard(.paper, radius: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(SR.error.opacity(0.55), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connections-banner")
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var count: Int { store.visible.count }

    private var kicker: String {
        count == 1 ? (store.visible.first?.isPersonal == true ? "Your iPhone needs you" : "A connection needs you")
            : "\(count) things need you"
    }

    private func summary(_ lead: ConnectionItem) -> some View {
        Button {
            SRHaptic.tap()
            onDetails()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lead.headline)
                        .font(SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subline(lead))
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SR.inkGhost)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows everything that needs you")
        .accessibilityIdentifier("connections-banner-details")
    }

    private func subline(_ lead: ConnectionItem) -> String {
        count > 1 ? "\(lead.subline) · and \(count - 1) more" : lead.subline
    }

    @ViewBuilder
    private func fixButton(_ lead: ConnectionItem) -> some View {
        ConnectionFixButton(item: lead, store: store)
    }
}

/// Fix: Safari for the site's connections, the app itself for the phone's own.
struct ConnectionFixButton: View {
    let item: ConnectionItem
    @ObservedObject var store: ConnectionsStore

    var body: some View {
        if let fix = item.localFix {
            Button {
                SRHaptic.tap()
                store.runLocalFix?(fix)
            } label: {
                SRButtonLabel(title: fix.buttonTitle, icon: fix == .syncNow ? "arrow.triangle.2.circlepath" : "heart")
            }
            .srButton(.prominent)
            .accessibilityLabel("\(fix.buttonTitle): \(item.headline)")
            .accessibilityIdentifier("connection-fix-\(item.id)")
        } else if let url = item.fixURL {
            Button {
                SRHaptic.tap()
                ConnectionFix.open(url)
            } label: {
                SRButtonLabel(title: "Fix", icon: "safari")
            }
            .srButton(.prominent)
            .accessibilityLabel("Fix \(item.label) in Safari")
            .accessibilityIdentifier("connection-fix-\(item.id)")
        }
    }
}

/// Where Fix goes.
///
/// SAFARI, never an in-app web view. Re-authorising is an OAuth consent that
/// starts from the site, and the site only lets its owner start it: the session
/// that proves that lives in Safari's cookies. A web view here would have no
/// session, land on the sign-in page, and — for Google — be refused outright,
/// because Google blocks OAuth in embedded browsers.
enum ConnectionFix {
    @MainActor static func open(_ url: URL) {
        UIApplication.shared.open(url)
    }
}

// MARK: - One connection, in full

/// A connection in a list: what is wrong, what to do, since when, and Fix.
struct ConnectionAttentionRow: View {
    let item: ConnectionItem
    @ObservedObject var store: ConnectionsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRRow(title: item.headline, subtitle: item.detail.isEmpty ? nil : item.detail, icon: item.icon, tone: SR.error)
            if let hint = item.fixHint, !hint.isEmpty {
                Text(hint)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 36)
            }
            HStack(alignment: .center, spacing: 12) {
                if let since = item.sinceDate {
                    Text("SINCE \(since.formatted(.relative(presentation: .named)).uppercased())")
                        .font(SR.Text.mono())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ConnectionFixButton(item: item, store: store)
            }
            .padding(.leading, 36)
            .padding(.bottom, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connection-\(item.id)")
    }
}

// MARK: - The sheet the banner opens

/// Every connection that needs the owner. Opened by the banner's chevron and
/// by tapping a "connections" notification.
struct ConnectionsSheet: View {
    @ObservedObject var store: ConnectionsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !store.personal.isEmpty {
                    Section {
                        ForEach(store.personal) { item in
                            ConnectionAttentionRow(item: item, store: store).srGlassRow()
                        }
                    } header: {
                        SRSectionLabel(text: "This iPhone", trailing: "\(store.personal.count)")
                    }
                }
                if store.items.isEmpty {
                    if store.personal.isEmpty {
                        Section {
                            SRRow(title: "Nothing needs you", subtitle: "Everything is connected and working.",
                                  icon: "checkmark.circle.fill", tone: SR.good)
                                .srGlassRow()
                        }
                    }
                } else {
                    Section {
                        ForEach(store.items) { item in
                            ConnectionAttentionRow(item: item, store: store).srGlassRow()
                        }
                    } header: {
                        SRSectionLabel(text: "Needs you", trailing: "\(store.count)")
                    } footer: {
                        ConnectionsFootnote(checkedAt: store.checkedAt)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .srPaper()
            .navigationTitle("Connections")
            // Inline: a custom face in the large-title slot paints nothing on
            // iOS 26. See `SRChrome`.
            .navigationBarTitleDisplayMode(.inline)
            .srRefreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("connections-sheet-done")
                }
            }
            .task { await store.refresh() }
        }
    }
}

/// What Fix does, and when the site last looked. Said under every list of
/// these, because "why is this opening Safari" is the obvious question.
struct ConnectionsFootnote: View {
    let checkedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fix opens the site in Safari, where you are signed in — the account's consent screen needs that session.")
            if let checkedAt {
                Text("Checked \(checkedAt.formatted(.relative(presentation: .named))).")
            }
        }
        .font(SR.Text.mono())
        .foregroundStyle(SR.inkMuted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }
}

// MARK: - Settings → Connections

/// "Site connections that need you" — the section at the top of Settings →
/// Connections. Not a pairing: the two pairings below it are THIS iPhone's
/// credentials; these are accounts the website holds.
struct SiteConnectionsSection: View {
    @ObservedObject var store: ConnectionsStore

    var body: some View {
        Section {
            if store.items.isEmpty {
                SRRow(title: "Nothing needs you", subtitle: "Gmail, calendars and the rest are all authorised.",
                      icon: "checkmark.circle.fill", tone: SR.good)
                    .srGlassRow()
            } else {
                ForEach(store.items) { item in
                    ConnectionAttentionRow(item: item, store: store).srGlassRow()
                }
            }
        } header: {
            SRSectionLabel(text: "Site connections that need you", trailing: store.items.isEmpty ? nil : "\(store.count)")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Accounts the website signs in to for you. Separate from the two pairings below, which are this iPhone's own.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if !store.items.isEmpty { ConnectionsFootnote(checkedAt: store.checkedAt) }
            }
            .padding(.vertical, 4)
        }
    }
}

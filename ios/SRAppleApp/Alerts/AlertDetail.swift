import SwiftUI

/// One alert, read in full.
///
/// A Today row is two lines of title and nothing else; the inbox clips the body
/// at four. Neither is somewhere to READ an alert — a failed deploy's reason or
/// a health note's figures sit in the body, which is exactly the part cut off.
/// So a tap opens the whole thing: what it is, when, everything it said, and —
/// when the site attached a page — the one button that goes there.
///
/// Opening it marks it read, on the site too: an alert read in full is the
/// plainest case of "seen".
struct AlertDetailScreen: View {
    let alert: SiteAlert
    @ObservedObject var alerts: AlertStore
    /// Set when shown from Today, where "Dismiss from Today" means something.
    var onDismissFromToday: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: alert.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AlertTone.of(alert))
                        .frame(width: 34, height: 34)
                        .background(AlertTone.of(alert).opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.category.uppercased())
                            .font(SR.Text.label())
                            .tracking(1.3)
                            .foregroundStyle(SR.inkMuted)
                        Text(when)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    }
                }

                Text(alert.title)
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if !alert.body.isEmpty {
                    Text(alert.body)
                        .font(SR.Text.body())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                VStack(spacing: 10) {
                    if let path = alert.url {
                        Button {
                            SRHaptic.tap()
                            openURL(SiteClient.shared.webURL(path))
                        } label: {
                            SRButtonLabel(title: "Open on the web", icon: "safari", fill: true)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .accessibilityIdentifier("alert-detail-open")
                    }
                    if let onDismissFromToday {
                        Button {
                            SRHaptic.select()
                            onDismissFromToday()
                            dismiss()
                        } label: {
                            SRButtonLabel(title: "Dismiss from Today", icon: "xmark")
                        }
                        .srButton()
                        .controlSize(.large)
                        .accessibilityIdentifier("alert-detail-dismiss")
                    }
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 20)
        }
        .srPaper()
        .navigationTitle("Alert")
        .navigationBarTitleDisplayMode(.inline)
        .task { await alerts.markRead(alert.id) }
    }

    private var when: String {
        guard let date = parseTimestamp(alert.createdAt) else { return shortAgo(alert.createdAt) }
        let ago = shortAgo(alert.createdAt)
        let stamp = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        return ago.isEmpty ? stamp : "\(stamp) · \(ago) ago"
    }
}

/// The colour an alert's glyph takes — shared by the inbox and the detail.
enum AlertTone {
    static func of(_ alert: SiteAlert) -> Color {
        if alert.isAlert { return SR.error }
        if alert.isWarning { return SR.warn }
        return SR.accentInk
    }
}

extension SiteAlert {
    /// What Today holds when the inbox has not answered yet: the title, and no
    /// body. The detail screen still opens, and says what it has.
    init(latest row: TodayAlerts.Latest) {
        self.init(
            id: row.id, category: row.category, title: row.title, body: "",
            url: nil, severity: row.severity, createdAt: row.createdAt, read: false
        )
    }
}

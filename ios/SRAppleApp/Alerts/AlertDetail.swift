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
                HStack(alignment: .center, spacing: 10) {
                    // The glyph in its tone, plain: a loop is kept for the
                    // figure that matters, not for decoration.
                    Image(systemName: alert.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AlertTone.of(alert))
                        .frame(width: 34, height: 34)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            SRPencilDot(word: alert.category, size: 10)
                            Text(alert.category.uppercased())
                                .font(SR.Text.kicker())
                                .tracking(SR.Notes.kickerTracking)
                                .foregroundStyle(SR.Notes.pen)
                        }
                        if stamped == nil {
                            Text(when)
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                        }
                    }
                    Spacer(minLength: 8)
                    // When it was raised, stamped on the page as the
                    // notebook dates an entry: the day, then the time and
                    // how long ago.
                    if let stamped {
                        SRDateStamp(text: stamped.day, sub: stamped.time, tilt: -3, seed: seedFor(alert.id))
                            .padding(.trailing, 4)
                    }
                }

                Text(alert.title)
                    .font(SR.Text.display(24))
                    .tracking(-24 * 0.02)
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
                    if let id = alert.commissionId {
                        NavigationLink { CommissionDetailScreen(id: id) } label: {
                            SRButtonLabel(title: "Open the double-check", icon: "sparkles", fill: true)
                        }.srButton(.prominent)
                    }
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

    /// The stamp's two lines — "Sun 11 Oct" over "07:42 · 2h ago" — or nil
    /// when the time will not parse, and the plain line says what it can.
    private var stamped: (day: String, time: String)? {
        guard let date = parseTimestamp(alert.createdAt) else { return nil }
        let ago = shortAgo(alert.createdAt)
        let time = date.formatted(date: .omitted, time: .shortened)
        return (date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                ago.isEmpty ? time : "\(time) · \(ago) ago")
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

import SwiftUI
import UIKit

/// The inbox.
///
/// Everything the site raised, including what went to WhatsApp instead of here
/// — "what has the site been telling me" is a question about the day, not about
/// a channel, and a list that hid the WhatsApp ones would be a list that lies
/// by omission.
struct AlertsScreen: View {
    @ObservedObject var alerts: AlertStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            ForEach(alerts.recent) { alert in
                row(alert).srPlainRow()
            }
        }
        .listStyle(.plain)
        .srPaper()
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await alerts.refresh() }
        .overlay {
            if alerts.recent.isEmpty && !alerts.loading {
                SREmpty(
                    title: "Nothing yet",
                    icon: "bell",
                    message: "Builds, deploys, health and intel appear here as they happen."
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    SRHaptic.tap()
                    Task { await alerts.markAllRead() }
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .disabled(alerts.unread == 0)
                .accessibilityLabel("Mark all read")
            }
        }
        .task { await alerts.refresh() }
    }

    @ViewBuilder
    private func row(_ alert: SiteAlert) -> some View {
        Button {
            guard let path = alert.url else { return }
            SRHaptic.tap()
            openURL(SiteClient.shared.webURL(path))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: alert.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tone(alert))
                    .frame(width: 22)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.title)
                        .font(SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(alert.body)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(alert.category.uppercased()) · \(shortAgo(alert.createdAt))")
                        .font(SR.Text.mono())
                        .tracking(1)
                        .foregroundStyle(SR.inkGhost)
                }

                Spacer(minLength: 4)

                if !alert.read {
                    Circle().fill(SR.accent).frame(width: 7, height: 7).padding(.top, 6)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("alert-\(alert.id)")
    }

    private func tone(_ alert: SiteAlert) -> Color {
        if alert.isAlert { return SR.error }
        if alert.isWarning { return SR.warn }
        return SR.accentInk
    }
}

/// Where each kind of alert goes.
///
/// The one screen the brief asked for by name: a switch per category for
/// WhatsApp and a switch for this iPhone, and the sentence explaining why one
/// of them is best-effort.
struct AlertRoutingScreen: View {
    @ObservedObject var alerts: AlertStore

    var body: some View {
        List {
            Section {
                permissionRow
            } header: {
                SRSectionLabel(text: "On this iPhone").srPlainRow().padding(.vertical, 6)
            } footer: {
                Text("""
                     This app has no push certificate, so the site cannot wake it. \
                     It collects what is waiting whenever iOS grants it a background \
                     refresh — usually several times a day, and sooner if you open the \
                     app. Anything that has to arrive the moment it happens should stay \
                     on WhatsApp.
                     """)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkGhost)
                    .srPlainRow()
                    .padding(.vertical, 8)
            }

            Section {
                ForEach(alerts.routes) { route in
                    NavigationLink {
                        RouteDetail(alerts: alerts, routeId: route.id)
                    } label: {
                        SRRow(title: route.label, subtitle: route.destination) {
                            EmptyView()
                        }
                    }
                    .srPlainRow()
                }
            } header: {
                SRSectionLabel(text: "Categories").srPlainRow().padding(.vertical, 6)
            }
        }
        .listStyle(.plain)
        .srPaper()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await alerts.readPermission()
            await alerts.loadRoutes()
        }
        .overlay(alignment: .bottom) {
            if let message = alerts.message { SRBanner(text: message, tone: SR.error) }
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch alerts.permission {
        case .authorized, .provisional, .ephemeral:
            SRRow(title: "Notifications allowed", subtitle: "iOS will show alerts from this app", icon: "checkmark.circle.fill", tone: SR.good)
                .srPlainRow()
        case .denied:
            Button {
                SRHaptic.tap()
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                SRRow(title: "Notifications are off", subtitle: "Turn them on in iOS Settings", icon: "bell.slash", tone: SR.error) {
                    Image(systemName: "arrow.up.forward.app").foregroundStyle(SR.inkGhost)
                }
            }
            .buttonStyle(.plain)
            .srPlainRow()
        default:
            Button {
                Task { await alerts.requestPermission() }
            } label: {
                SRRow(title: "Allow notifications", subtitle: "Needed before anything can appear on this iPhone", icon: "bell.badge", tone: SR.accent)
            }
            .buttonStyle(.plain)
            .srPlainRow()
        }
    }
}

/// One category: two switches and, where it has one, its floor.
struct RouteDetail: View {
    @ObservedObject var alerts: AlertStore
    let routeId: String

    private var route: AlertRoute? { alerts.routes.first { $0.id == routeId } }

    /// The floors offered. Not a free-text field: a number somebody types into a
    /// box is a number somebody can type 0 into by accident, and "never" is
    /// already expressed by turning both switches off.
    private let floors: [(label: String, seconds: Int)] = [
        ("Every time", 0),
        ("At most hourly", 3600),
        ("At most every 3 hours", 3 * 3600),
        ("At most every 6 hours", 6 * 3600),
        ("At most once a day", 24 * 3600),
    ]

    var body: some View {
        Group {
            if let route {
                List {
                    Section {
                        Toggle(isOn: Binding(
                            get: { route.whatsapp },
                            set: { value in Task { await alerts.setRoute(route, whatsapp: value) } }
                        )) {
                            SRRow(title: "WhatsApp", subtitle: "Arrives immediately", icon: "phone.bubble")
                        }
                        .tint(SR.accent)
                        .srPlainRow()

                        Toggle(isOn: Binding(
                            get: { route.native },
                            set: { value in Task { await alerts.setRoute(route, native: value) } }
                        )) {
                            SRRow(title: "This iPhone", subtitle: "On the next background refresh", icon: "iphone")
                        }
                        .tint(SR.accent)
                        .srPlainRow()
                    } header: {
                        SRSectionLabel(text: "Deliver to").srPlainRow().padding(.vertical, 6)
                    } footer: {
                        Text(route.description)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkGhost)
                            .srPlainRow()
                            .padding(.vertical, 8)
                    }

                    Section {
                        ForEach(floors, id: \.seconds) { floor in
                            Button {
                                Task { await alerts.setRoute(route, floor: floor.seconds) }
                            } label: {
                                SRRow(title: floor.label) {
                                    if route.minIntervalSeconds == floor.seconds {
                                        Image(systemName: "checkmark").foregroundStyle(SR.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .srPlainRow()
                        }
                    } header: {
                        SRSectionLabel(text: "How often").srPlainRow().padding(.vertical, 6)
                    } footer: {
                        Text("A floor applies to the whole category, in both channels. Health ships at three hours: the figures move all day and a phone that says so all day is a phone you switch off.")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkGhost)
                            .srPlainRow()
                            .padding(.vertical, 8)
                    }
                }
                .listStyle(.plain)
                .srPaper()
                .navigationTitle(route.label)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ProgressView().tint(SR.accent).frame(maxWidth: .infinity, maxHeight: .infinity).srPaper()
            }
        }
    }
}

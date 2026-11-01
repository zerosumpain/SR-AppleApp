import SwiftUI
import UIKit

// MARK: - The store

/// The morning report, from the site (`/api/native/briefing`, `?day=`).
///
/// The owner's alone: the site refuses anyone else (403), and the entry on
/// Home is not drawn for them. The newest report is kept on disk
/// (`MorningReportCache`), so the screen opens on this morning's words while
/// the read is in flight — or failing, on a train. A failed read keeps what
/// is on screen; only a refusal (401/403) takes it away.
@MainActor
final class MorningReportStore: ObservableObject {
    static let shared = MorningReportStore()

    @Published private(set) var report: NativeBriefing?
    @Published private(set) var loading = false
    /// Whether a read has answered at least once since launch.
    @Published private(set) var loaded = false
    /// The site has no report for what was asked (404).
    @Published private(set) var missing = false
    @Published var message: String?
    /// The day on screen; nil is the newest.
    @Published private(set) var day: String?

    private let client = SiteClient.shared

    init() {
        if !SRDemo.isOn, let cached = MorningReportCache.load() { report = cached }
    }

    /// The days the picker offers: the report's own list, newest first, or
    /// at least the day on screen.
    var days: [String] {
        guard let report else { return [] }
        return report.days.isEmpty ? [report.day] : report.days
    }

    func load(day: String? = nil) async {
        guard AccessStore.ownerSite, !loading else { return }
        loading = true
        defer { loading = false; loaded = true }
        do {
            let fetched: NativeBriefing = try await client.send(NativeBriefing.path(day: day))
            report = fetched
            self.day = day
            missing = false
            message = nil
            // Only the newest is kept: it is what a cold start should open on.
            if day == nil || day == fetched.days.first {
                MorningReportCache.save(fetched)
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            let status = (error as? SiteError)?.status
            if status == 401 || status == 403 {
                reset()
                message = error.localizedDescription
            } else if status == 404 {
                // Nothing for that day. Asked for the newest, there is none
                // at all; asked for an older day, the newest stays up.
                if day == nil {
                    report = nil
                    MorningReportCache.clear()
                }
                missing = report == nil
                message = report == nil ? nil : "No report for \(NativeBriefing.shortLabel(day ?? ""))."
            } else {
                message = error.localizedDescription
            }
        }
    }

    /// A revoked credential, or a refusal: nothing of the report stays.
    func reset() {
        report = nil
        day = nil
        missing = false
        message = nil
        MorningReportCache.clear()
    }
}

/// The newest report, on disk for a cold start. Personal (the day, the
/// family, the inbox), so: this app's own container, excluded from backups,
/// and deleted on a refusal or a revoke (`SiteClient.revoke`). One older than
/// `maxAge` is not shown.
enum MorningReportCache {
    struct Entry: Codable {
        let report: NativeBriefing
        let savedAt: Date
    }

    static let maxAge: TimeInterval = 3 * 24 * 60 * 60

    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("morning-report.json")
    }

    static func load(now: Date = Date(), from file: URL = url) -> NativeBriefing? {
        guard let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              now.timeIntervalSince(entry.savedAt) <= maxAge
        else { return nil }
        return entry.report
    }

    static func save(_ report: NativeBriefing, now: Date = Date(), to file: URL = url) {
        guard let data = try? JSONEncoder().encode(Entry(report: report, savedAt: now)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = file
        try? target.setResourceValues(values)
    }

    static func clear(at file: URL = url) {
        try? FileManager.default.removeItem(at: file)
    }
}

/// The morning report, pushed onto a stack: from Home's "Worth knowing"
/// tile, or `Router.openMorningReport`. `day` nil is the newest.
struct MorningReportRef: Hashable {
    var day: String? = nil
}

// MARK: - The screen

/// The morning report: the verified prose, what connects across the day, and
/// the nineteen things the briefing looked at, grouped as the web page groups
/// them. Every card's facts are a tap away; "Full detail" is the web page.
struct MorningReportScreen: View {
    var day: String? = nil
    @ObservedObject private var store = MorningReportStore.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                if let report = store.report {
                    content(report)
                } else if store.missing {
                    SREmpty(title: "No morning report yet", icon: "sun.horizon",
                            message: "The briefing is written at 7:00 each morning. It will be here once the first one has run.")
                } else if let message = store.message, !store.loading {
                    SREmpty(title: "Couldn't load the report", icon: "exclamationmark.triangle", message: message,
                            actionLabel: "Try again", action: { retry() })
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                        .accessibilityLabel("Loading the morning report")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("morning-report-screen")
        .srGround(.quiet)
        .navigationTitle("Morning report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SRBarMark() } }
        // A link in the prose may be a site path: resolve it before it opens.
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == nil, let resolved = BriefingLinks.resolve(url.relativeString) {
                return .systemAction(resolved)
            }
            return .systemAction
        })
        .task { await store.load(day: day ?? store.day) }
        .srRefreshable { await store.load(day: store.day) }
        .overlay(alignment: .bottom) {
            if store.report != nil, let message = store.message { SRBanner(text: message, tone: SR.error) }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ report: NativeBriefing) -> some View {
        header(report)
        prose(report)
        if !report.connections.isEmpty { connections(report) }
        if report.factors.isEmpty {
            Text("This day's report was written before the factor cards. The full detail is on the web page.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        } else {
            ForEach(report.grouped, id: \.group) { section in
                SRSectionLabel(text: section.group.title, trailing: "\(section.factors.count)")
                    .padding(.top, 10)
                    .padding(.horizontal, 4)
                ForEach(section.factors) { factor in
                    MorningFactorCard(factor: factor, hue: Self.hue(section.group)) { href in open(href) }
                }
            }
        }
        if !report.gaps.isEmpty { gaps(report) }
        if let page = BriefingLinks.resolve(report.pageUrl) {
            Link(destination: page) {
                SRButtonLabel(title: "Full detail", icon: "safari", fill: true)
            }
            .srButton(.regular)
            .controlSize(.large)
            .padding(.top, 12)
            .accessibilityIdentifier("morning-report-full-detail")
        }
    }

    private func header(_ report: NativeBriefing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRPageHeader(kicker: "Morning report",
                         title: report.title.isEmpty ? "Briefing" : report.title,
                         strap: report.dateLabel.isEmpty ? nil : report.dateLabel)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips(report) }
                VStack(alignment: .leading, spacing: 8) { chips(report) }
            }
        }
    }

    @ViewBuilder
    private func chips(_ report: NativeBriefing) -> some View {
        if store.days.count > 1 {
            Menu {
                // Buttons rather than a bound Picker: the choice starts a
                // read, and the report on screen says which day it is.
                ForEach(store.days, id: \.self) { day in
                    Button {
                        SRHaptic.select()
                        let newest = store.days.first
                        Task { await store.load(day: day == newest ? nil : day) }
                    } label: {
                        if day == report.day {
                            Label(NativeBriefing.shortLabel(day), systemImage: "checkmark")
                        } else {
                            Text(NativeBriefing.shortLabel(day))
                        }
                    }
                }
            } label: {
                SRButtonLabel(title: NativeBriefing.shortLabel(report.day), icon: "calendar")
            }
            .srButton(.regular)
            .accessibilityLabel("Day: \(NativeBriefing.shortLabel(report.day))")
            .accessibilityIdentifier("morning-report-day")
        }
        if let mode = report.mode?.label { chip(mode, tone: SR.accentInk) }
        if !report.verified { chip("Unverified", tone: SR.warn) }
        if store.loading { ProgressView().controlSize(.small) }
    }

    private func chip(_ text: String, tone: Color) -> some View {
        Text(text.uppercased())
            .font(SR.Text.label(12))
            .tracking(1)
            .foregroundStyle(tone)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tone.opacity(0.14)))
    }

    private func prose(_ report: NativeBriefing) -> some View {
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 10) {
                let headline = report.headline.trimmingCharacters(in: .whitespacesAndNewlines)
                if !headline.isEmpty && !report.markdown.contains(headline) {
                    Text(headline)
                        .font(SR.Text.display(20))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if report.markdown.isEmpty {
                    Text("No words for this day — the cards below say what was found.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    MarkdownText(raw: report.markdown)
                }
            }
        }
        .accessibilityIdentifier("morning-report-prose")
    }

    private func connections(_ report: NativeBriefing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "Connections",
                           trailing: report.actionable > 0 ? "\(report.actionable) to act on" : nil)
                .padding(.top, 10)
                .padding(.horizontal, 4)
            SRCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(report.connections.enumerated()), id: \.offset) { index, connection in
                        if index > 0 { Divider().overlay(SR.divider) }
                        MorningConnectionRow(connection: connection, labels: report.labels(for: connection))
                    }
                }
            }
        }
        .accessibilityIdentifier("morning-report-connections")
    }

    private func gaps(_ report: NativeBriefing) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SRSectionLabel(text: "Couldn't check")
                .padding(.top, 10)
            ForEach(Array(report.gaps.enumerated()), id: \.offset) { _, gap in
                (Text(gap.section).font(SR.Text.bodyMedium(14)).foregroundStyle(SR.inkSecondary)
                 + Text(gap.reason.isEmpty ? "" : " — \(gap.reason)").font(SR.Text.secondary()).foregroundStyle(SR.inkMuted))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
    }

    private func retry() {
        Task { await store.load(day: store.day) }
    }

    private func open(_ href: String?) {
        guard let url = BriefingLinks.resolve(href) else { return }
        SRHaptic.tap()
        openURL(url)
    }

    /// Each group in a feature's hue, so the page reads by colour as Home does.
    static func hue(_ group: FactorCard.Group) -> SR.Hue {
        switch group {
        case .place: return SR.Hue.trips
        case .body: return SR.Hue.health
        case .day: return SR.Hue.tasks
        case .homeFamily: return SR.Hue.family
        case .intelligence: return SR.Hue.news
        case .systems: return SR.Hue.flows
        case .other: return SR.Hue.daydream
        }
    }
}

// MARK: - Rows and cards

/// One connection: what joins the factors, and which ones. One that asks for
/// something to be done carries the accent and a bolt.
private struct MorningConnectionRow: View {
    let connection: NativeBriefing.Connection
    let labels: [String]
    @ScaledMetric(relativeTo: .body) private var mark: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: connection.action ? "bolt.fill" : "link")
                .font(.footnote.weight(.bold))
                .foregroundStyle(connection.action ? SR.accentInk : SR.inkMuted)
                .frame(width: mark)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(connection.text)
                    .font(connection.action ? SR.Text.title(16) : SR.Text.body(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !labels.isEmpty {
                    Text(labels.joined(separator: " · "))
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, connection.action ? 10 : 0)
        .background {
            if connection.action {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SR.accent.opacity(0.10))
            }
        }
        .padding(.vertical, connection.action ? 4 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(connection.action ? "To act on: \(connection.text)" : connection.text)
    }
}

/// One factor: its symbol in its group's hue, its number and name, the
/// headline, and — a tap away — its facts. A card that is stale, failed,
/// empty or off says so in a chip and is drawn quieter.
private struct MorningFactorCard: View {
    let factor: FactorCard
    let hue: SR.Hue
    let open: (String?) -> Void
    @State private var expanded = false
    @ScaledMetric(relativeTo: .body) private var mark: CGFloat = 34
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                SRHaptic.tap()
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                summary
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityHint(expanded ? "Hides the facts" : "Shows the facts")
            .accessibilityAddTraits(.isButton)
            if expanded {
                facts
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .overlay(alignment: .leading) {
            if factor.status == .failed || factor.status == .stale {
                Capsule().fill(tone).frame(width: 3).padding(.vertical, 14)
            }
        }
        .accessibilityIdentifier("morning-factor-\(factor.key)")
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(hue.onFill)
                .frame(width: mark, height: mark)
                .background(Circle().fill(hue.gradient))
                .opacity(factor.status.isQuiet ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 4) {
                // The number and name, then the chip: the chip drops under
                // them when the type is too big for one line.
                let title = (Text("\(factor.n)  ").font(SR.Text.mono(12)).foregroundStyle(SR.inkMuted)
                             + Text(factor.label.uppercased()).font(SR.Text.label(12)).foregroundStyle(SR.inkSecondary))
                if typeSize.isAccessibilitySize {
                    title.fixedSize(horizontal: false, vertical: true)
                    badge
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        title.fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        badge
                    }
                }
                if !factor.line.isEmpty {
                    Text(factor.line)
                        .font(factor.headline.isEmpty ? SR.Text.secondary(15) : SR.Text.title(16))
                        .foregroundStyle(factor.headline.isEmpty ? SR.inkMuted : SR.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !typeSize.isAccessibilitySize {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SR.inkGhost)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var badge: some View {
        if let text = factor.status.badge {
            Text(text.uppercased())
                .font(SR.Text.label(12))
                .tracking(0.8)
                .foregroundStyle(tone)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(tone.opacity(0.14)))
                .fixedSize()
        } else if factor.hasAction {
            Image(systemName: "bolt.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(SR.accentInk)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            if factor.facts.isEmpty {
                Text("No facts on this card today.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            ForEach(Array(factor.facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 { Divider().overlay(SR.divider) }
                MorningFactRow(fact: fact, open: open)
            }
            let detail = factor.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty && detail != factor.line {
                Text(detail)
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    /// The card's own symbol, or a neutral one when this OS has no symbol of
    /// that name — an unknown name draws nothing at all.
    private var symbol: String {
        UIImage(systemName: factor.icon) != nil ? factor.icon : "circle.dashed"
    }

    private var tone: Color {
        switch factor.status {
        case .failed: return SR.error
        case .stale: return SR.warn
        case .ok: return SR.good
        case .empty, .off, .other: return SR.inkMuted
        }
    }

    private var spoken: String {
        var parts = ["\(factor.n). \(factor.label)"]
        if let badge = factor.status.badge { parts.append(badge) }
        if !factor.line.isEmpty { parts.append(factor.line) }
        return parts.joined(separator: ". ")
    }
}

/// One fact: its label, the value, what it means, and where it goes.
private struct MorningFactRow: View {
    let fact: FactorCard.Fact
    let open: (String?) -> Void

    var body: some View {
        let link = BriefingLinks.resolve(fact.href)
        VStack(alignment: .leading, spacing: 3) {
            if !fact.label.isEmpty {
                Text(fact.label.uppercased())
                    .font(SR.Text.label(12))
                    .tracking(0.8)
                    .foregroundStyle(fact.action ? SR.accentInk : SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !fact.value.isEmpty {
                Text(fact.value)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let assessment = fact.assessment {
                Text(assessment)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if link != nil {
                Button { open(fact.href) } label: {
                    Label(link?.host == BriefingLinks.origin.host ? "Open" : "Open in Safari",
                          systemImage: "arrow.up.right.square")
                        .font(SR.Text.label(13))
                        .foregroundStyle(SR.accentInk)
                        .frame(minHeight: SR.tapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(link?.host ?? "")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

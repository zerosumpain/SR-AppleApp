import SwiftUI

/// The sign-off sheet for a double-check: what it will read, what it will not
/// touch, how you will know it worked, and its limits — then your OK.
///
/// Plain words first. The receipts (content hashes, the plan's fingerprint,
/// the raw queries, the event log) sit in "The fine print", folded.
///
/// The approval binds what is on screen: `decide` sends the revision and the
/// plan's hash this sheet was drawn from, with a fresh operation key, and the
/// site refuses it if the plan moved underneath. Nothing here approves from a
/// push or on a timer.
struct CommissionDetailScreen: View {
    let id: String
    @ObservedObject private var store = CommissionStore.shared
    @Environment(\.openURL) private var openURL
    private var commission: DaydreamCommission? { store.commissions.first { $0.id == id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let c = commission {
                    content(c)
                } else if let error = store.error {
                    Text(error)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.error)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(SR.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("commission-screen")
        .srGround(.quiet)
        .navigationTitle("Double-check")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            repeat {
                await store.load(id: id)
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
            } while !Task.isCancelled
        }
        .srRefreshable { await store.load(id: id) }
    }

    // MARK: - The sheet

    @ViewBuilder
    private func content(_ c: DaydreamCommission) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(c.label.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(DaydreamCommissionStatus.tone(for: c.state))
                .accessibilityIdentifier("commission-state")
            Text(c.spec.title)
                .font(SR.Text.display(24))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }

        CommissionProgressTrack(
            step: c.step,
            attention: c.state == "needs_attention",
            stopped: ["declined", "cancelled"].contains(c.state)
        )

        if !c.spec.outcome.isEmpty {
            Text(c.spec.outcome)
                .font(SR.Text.body(17))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let sentence = Self.progressSentence(c) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if ["queued", "running"].contains(c.state) {
                    ProgressView().controlSize(.small)
                }
                Text(sentence)
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DaydreamCommissionStatus.tone(for: c.state).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("commission-progress")
        }

        if let message = c.error ?? store.error {
            Text(message)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.error)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let result = c.result { report(c, result) }

        plan(c)

        actions(c)

        Button {
            SRHaptic.tap()
            openURL(SiteClient.shared.webURL(DaydreamNote.defaultPath(for: c.thoughtId)))
        } label: {
            SRButtonLabel(title: "The original note", icon: "safari", fill: true)
        }
        .srButton()
        .accessibilityIdentifier("commission-original")

        finePrint(c)
    }

    // MARK: - The plan, in plain words

    @ViewBuilder
    private func plan(_ c: DaydreamCommission) -> some View {
        let reads = c.readLabels
        let waiting = c.canApprove
        block(
            waiting ? "What will happen" : "What it reads",
            icon: "doc.text",
            lines: reads.isEmpty ? ["It re-reads the sources the note cited, and nothing else."] : reads,
            id: "commission-reads"
        )
        if !c.spec.exclusions.isEmpty {
            block(waiting ? "What won't happen" : "What it does not do", icon: "xmark", lines: c.spec.exclusions,
                  id: "commission-exclusions")
        }
        if !c.spec.acceptance.isEmpty {
            block("You'll know it worked when", icon: "checkmark", lines: c.spec.acceptance, id: "commission-acceptance")
        }
        if let correction = c.spec.ownerCorrection, !correction.isEmpty {
            block("Your correction", icon: "pencil", lines: [correction], id: "commission-correction")
        }
        block("Limits", icon: "hourglass", lines: c.spec.budget.plainLimits, id: "commission-limits")
    }

    private func block(_ title: String, icon: String, lines: [String], id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: title)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SR.accentInk)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(SR.Text.body(16))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }

    // MARK: - Your OK

    @ViewBuilder
    private func actions(_ c: DaydreamCommission) -> some View {
        if c.canApprove || c.canCancel || c.state == "needs_attention" {
            VStack(spacing: 10) {
                if c.canApprove {
                    action("Approve and run", "approve", c, icon: "checkmark", prominent: true)
                    if c.state != "deferred" {
                        action("Not now — ask me in a week", "defer", c, icon: "clock")
                    }
                    action("Decline", "decline", c, icon: "xmark")
                }
                if c.state == "needs_attention" {
                    action("Try again", "retry", c, icon: "arrow.clockwise", prominent: true)
                }
                if c.canCancel {
                    action("Stop the check", "cancel", c, icon: "stop")
                }
            }
            .padding(.top, 4)
        }
    }

    private func action(_ title: String, _ decision: String, _ c: DaydreamCommission, icon: String,
                        prominent: Bool = false) -> some View {
        Button {
            SRHaptic.tap()
            Task { await store.decide(c, decision: decision) }
        } label: {
            SRButtonLabel(title: title, icon: icon, fill: true)
        }
        .srButton(prominent ? .prominent : .regular)
        .controlSize(prominent ? .large : .regular)
        .disabled(store.busy)
        .accessibilityLabel(title)
        .accessibilityIdentifier("commission-\(decision)")
    }

    // MARK: - The report

    private func report(_ c: DaydreamCommission, _ result: EvidenceReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "What the sources say now")
            Text(result.summary)
                .font(SR.Text.body(17))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("commission-evidence-report")
            ForEach(Array(result.evidence.enumerated()), id: \.offset) { index, evidence in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(evidence.text.isEmpty ? "Nothing came back from this source." : evidence.text)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        if !evidence.contentHash.isEmpty {
                            Text("RECEIPT · SHA-256")
                                .font(SR.Text.label())
                                .tracking(1)
                                .foregroundStyle(SR.inkMuted)
                            Text(evidence.contentHash)
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.label(for: evidence))
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 5) {
                            Image(systemName: evidence.wasRead ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .font(.system(size: 11, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(evidence.wasRead ? "Read" : "Could not be reached")
                            if !evidence.retrievedAt.isEmpty {
                                Text("· \(shortAgo(evidence.retrievedAt))")
                            }
                        }
                        .font(SR.Text.mono())
                        .foregroundStyle(evidence.wasRead ? SR.good : SR.warn)
                    }
                }
                .tint(SR.inkSecondary)
                .padding(12)
                .background(SR.ink.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("commission-source-\(index)")
            }
        }
    }

    // MARK: - The fine print

    private func finePrint(_ c: DaydreamCommission) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 16) {
                if !c.spec.reuseAssessment.isEmpty {
                    fine("Built from what already exists", c.spec.reuseAssessment)
                }
                if !c.spec.effects.isEmpty {
                    fine("What an OK allows", c.spec.effects)
                }
                if !c.spec.currentBehaviour.isEmpty || !c.spec.improvedBehaviour.isEmpty {
                    fine("Before and after", [c.spec.currentBehaviour, c.spec.improvedBehaviour].filter { !$0.isEmpty })
                }
                if !c.events.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SRSectionLabel(text: "History", trailing: "\(c.events.count)")
                        ForEach(c.events.sorted { $0.sequence < $1.sequence }) { event in
                            HStack(alignment: .firstTextBaseline) {
                                Text(event.summary)
                                    .font(SR.Text.secondary())
                                    .foregroundStyle(SR.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text(shortAgo(event.at))
                                    .font(SR.Text.mono())
                                    .foregroundStyle(SR.inkMuted)
                            }
                        }
                    }
                }
                if !c.spec.reads.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SRSectionLabel(text: "The exact look-ups")
                        ForEach(Array(c.spec.reads.enumerated()), id: \.offset) { _, read in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(read.tool).font(SR.Text.label()).foregroundStyle(SR.ink)
                                Text(read.args.pretty)
                                    .font(SR.Text.mono())
                                    .foregroundStyle(SR.inkMuted)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    SRSectionLabel(text: "Plan")
                    Text("Revision \(c.revision) · updated \(shortAgo(c.updatedAt))")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                    Text("SHA-256 \(c.specHash)")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .textSelection(.enabled)
                }
                if ["awaiting_approval", "deferred", "needs_attention"].contains(c.state) {
                    Button {
                        SRHaptic.tap()
                        Task { await store.prepare(thoughtId: c.thoughtId) }
                    } label: {
                        SRButtonLabel(title: "Redraw the plan after a correction", icon: "arrow.triangle.2.circlepath", fill: true)
                    }
                    .srButton()
                    .disabled(store.busy)
                    .accessibilityIdentifier("commission-redraw")
                }
                Button {
                    SRHaptic.tap()
                    openURL(SiteClient.shared.webURL("/jkai/develop/backlog?item=\(c.backlogSlug)"))
                } label: {
                    SRButtonLabel(title: "Its entry in the build queue", icon: "list.bullet.rectangle", fill: true)
                }
                .srButton()
                .accessibilityIdentifier("commission-backlog")
            }
            .padding(.top, 10)
        } label: {
            Text("The fine print")
                .font(SR.Text.bodyMedium(16))
                .foregroundStyle(SR.ink)
        }
        .tint(SR.inkSecondary)
        .accessibilityIdentifier("commission-fine-print")
    }

    private func fine(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SRSectionLabel(text: title)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Words

    /// One sentence for where it has got to. `nil` when the report says it.
    static func progressSentence(_ c: DaydreamCommission) -> String? {
        let reads = c.spec.reads.count
        switch c.state {
        case "awaiting_approval":
            return "Nothing happens until you say so."
        case "deferred":
            return "Put off for now — it will ask again in a week. You can still approve it today."
        case "queued":
            return "Approved. It starts in a moment, and carries on if you close the app."
        case "running":
            let what = reads == 1 ? "its source" : reads > 1 ? "its \(reads) sources" : "its sources"
            return "Re-reading \(what) now. It carries on if you close the app; the report lands here."
        case "needs_attention":
            return "It could not finish on its own. Try again within the same limits, or stop it."
        case "declined":
            return "You declined this. Nothing was read."
        case "cancelled":
            return "Stopped. Nothing more will be read."
        default:
            return nil
        }
    }
}

/// Proposed → Approved → Checking → Report ready. A double-check that needs
/// you shows a warning at Checking; one declined or stopped greys its step.
struct CommissionProgressTrack: View {
    let step: Int
    var attention = false
    var stopped = false

    static let titles = ["Proposed", "Approved", "Checking", "Report ready"]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<Self.titles.count, id: \.self) { index in
                VStack(spacing: 6) {
                    marker(index)
                        .frame(width: 22, height: 22)
                    Text(Self.titles[index])
                        .font(SR.Text.mono())
                        .foregroundStyle(index <= step ? SR.ink : SR.inkMuted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(alignment: .top) {
            // The rail the markers sit on, from the first centre to the last.
            GeometryReader { proxy in
                let inset = proxy.size.width / CGFloat(Self.titles.count * 2)
                Rectangle()
                    .fill(SR.line)
                    .frame(width: max(0, proxy.size.width - inset * 2), height: 2)
                    .offset(x: inset, y: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("commission-track")
    }

    @ViewBuilder
    private func marker(_ index: Int) -> some View {
        if attention && index == step {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SR.warn)
                .frame(width: 22, height: 22)
                .background(Circle().fill(SR.paper))
        } else if index < step || (index == step && index == Self.titles.count - 1) {
            Circle()
                .fill(SR.accentInk)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SR.paper)
                )
                .frame(width: 18, height: 18)
        } else if index == step {
            Circle()
                .fill(stopped ? SR.inkMuted : SR.accent)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(SR.paper, lineWidth: 3))
        } else {
            Circle()
                .fill(SR.paper)
                .overlay(Circle().strokeBorder(SR.line, lineWidth: 2))
                .frame(width: 18, height: 18)
        }
    }

    private var spoken: String {
        let at = Self.titles[min(max(step, 0), Self.titles.count - 1)]
        if attention { return "Step \(step + 1) of 4, \(at), needs you" }
        if stopped { return "Stopped at step \(step + 1) of 4, \(at)" }
        return "Step \(step + 1) of 4, \(at)"
    }
}

import SwiftUI

struct CommissionList: View {
    @ObservedObject private var store = CommissionStore.shared
    @State private var filter = "all"
    private var visible: [DaydreamCommission] {
        store.commissions.filter {
            switch filter {
            case "approval": return ["awaiting_approval", "deferred"].contains($0.state)
            case "progress": return ["queued", "running"].contains($0.state)
            case "attention": return $0.state == "needs_attention"
            case "outcomes": return ["completed", "cancelled", "declined"].contains($0.state)
            default: return true
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Your improvements", trailing: "\(store.commissions.count)")
            Picker("Improvement status", selection: $filter) {
                Text("All").tag("all"); Text("Awaiting approval").tag("approval")
                Text("In progress").tag("progress"); Text("Needs attention").tag("attention"); Text("Outcomes").tag("outcomes")
            }.pickerStyle(.menu)
            if let error = store.error { Text(error).font(SR.Text.secondary()).foregroundStyle(SR.error) }
            ForEach(visible) { commission in
                Button { store.destination = CommissionDestination(id: commission.id) } label: {
                    SRCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(commission.label).font(SR.Text.label()).foregroundStyle(SR.accentInk)
                            Text(commission.spec.title).font(SR.Text.body()).foregroundStyle(SR.ink)
                            Text("Next: \(commission.nextActor)").font(SR.Text.secondary()).foregroundStyle(SR.inkMuted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(.plain)
            }
        }
    }
}

struct CommissionDetailScreen: View {
    let id: String
    @ObservedObject private var store = CommissionStore.shared
    @Environment(\.openURL) private var openURL
    private var commission: DaydreamCommission? { store.commissions.first { $0.id == id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let c = commission {
                    Text(c.label).font(SR.Text.label()).foregroundStyle(SR.accentInk)
                    Text(c.spec.title).font(SR.Text.display(24)).accessibilityAddTraits(.isHeader)
                    Text(c.spec.outcome).font(SR.Text.body())
                    Text("Next: \(c.nextActor)").font(SR.Text.secondary()).foregroundStyle(SR.inkMuted)
                    Group {
                        block("Current observation", [c.spec.currentBehaviour])
                        block("Improved behaviour", [c.spec.improvedBehaviour])
                        if let correction = c.spec.ownerCorrection { block("Your correction", [correction]) }
                        block("Existing capabilities", c.spec.reuseAssessment)
                        block("Success criteria", c.spec.acceptance)
                        block("Scope of approval", c.spec.effects)
                        block("Limits", c.spec.exclusions)
                    }
                    Text("Up to \(c.spec.budget.maxReads) reads per attempt · \(c.spec.budget.maxAttempts) attempts total · \(c.spec.budget.maxWallSeconds) seconds per attempt")
                        .font(SR.Text.secondary()).foregroundStyle(SR.inkMuted)
                    DisclosureGroup("Approved source queries") {
                        ForEach(Array(c.spec.reads.enumerated()), id: \.offset) { _, read in
                            VStack(alignment: .leading) { Text(read.tool).bold(); Text(read.args.pretty).font(SR.Text.mono()).textSelection(.enabled) }
                        }
                    }
                    if let message = c.error ?? store.error { Text(message).foregroundStyle(SR.error).font(SR.Text.secondary()) }
                    if c.canApprove {
                        action("Approve evidence refresh", "approve", c, prominent: true)
                        action("Defer 7 days", "defer", c)
                        action("Decline", "decline", c)
                    }
                    if c.state == "needs_attention" { action("Retry within approved scope", "retry", c, prominent: true) }
                    if c.canCancel { action("Cancel", "cancel", c) }
                    if ["awaiting_approval", "deferred", "needs_attention"].contains(c.state) {
                        Button("Update after a correction") { Task { await store.prepare(thoughtId: c.thoughtId) } }.srButton().disabled(store.busy)
                    }
                    if let result = c.result {
                        block("Evidence report", [result.summary])
                        ForEach(Array(result.evidence.enumerated()), id: \.offset) { _, evidence in
                            DisclosureGroup("\(evidence.tool) · \(evidence.status)") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(evidence.text).textSelection(.enabled)
                                    Text("Query result · \(evidence.retrievedAt)").font(SR.Text.secondary()).foregroundStyle(SR.inkMuted)
                                    Text(evidence.contentHash).font(SR.Text.mono()).textSelection(.enabled)
                                }
                            }
                        }
                    }
                    SRSectionLabel(text: "History", trailing: "\(c.events.count) events")
                    ForEach(c.events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.summary).font(SR.Text.body())
                            Text(shortAgo(event.at)).font(SR.Text.secondary()).foregroundStyle(SR.inkMuted)
                        }
                    }
                    Button("Original suggestion") { openURL(SiteClient.shared.webURL(DaydreamNote.defaultPath(for: c.thoughtId))) }.srButton()
                    Button("Backlog group") { openURL(SiteClient.shared.webURL("/jkai/develop/backlog?item=\(c.backlogSlug)")) }.srButton()
                } else if let error = store.error { Text(error).foregroundStyle(SR.error) }
                else { ProgressView() }
            }.padding(SR.gutter).frame(maxWidth: .infinity, alignment: .leading)
        }
        .srGround(.quiet).navigationTitle("Daydream improvement").navigationBarTitleDisplayMode(.inline)
        .task {
            repeat {
                await store.load(id: id)
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
            } while !Task.isCancelled
        }
        .srRefreshable { await store.load(id: id) }
    }
    private func block(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: title)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in Text(line).font(SR.Text.body()).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func action(_ title: String, _ decision: String, _ c: DaydreamCommission, prominent: Bool = false) -> some View {
        Button { Task { await store.decide(c, decision: decision) } } label: { SRButtonLabel(title: title, icon: decision == "approve" ? "checkmark" : "arrow.right") }
            .srButton(prominent ? .prominent : .regular).disabled(store.busy)
    }
}

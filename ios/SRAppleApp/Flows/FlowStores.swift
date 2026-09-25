import Foundation
import Combine

/// What happened to a write, in the terms a screen acts on.
enum FlowWriteResult: Equatable {
    case saved
    /// 409: somebody (the web canvas, jkai, another phone) saved first. The
    /// store has already reloaded; the edit on screen was NOT applied.
    case conflict
    /// 422 with a field: the message belongs beside that field.
    case invalid(field: String?, message: String)
    case failed(String)
}

private let flowEncoder = JSONEncoder()

private func encodeBody(_ object: [String: JSONValue]) throws -> Data {
    try flowEncoder.encode(JSONValue.object(object))
}

// MARK: - The list

@MainActor
final class FlowListStore: ObservableObject {
    /// A workflow the model is still building. Kept on the phone because the
    /// list endpoint knows nothing of `building` — only the detail does.
    struct PendingBuild: Identifiable, Hashable {
        let slug: String
        let title: String
        var error: String?
        var id: String { slug }
    }

    @Published private(set) var workflows: [FlowSummary] = []
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    @Published private(set) var building: [PendingBuild] = []
    @Published private(set) var busySlug: String?
    @Published var query = ""
    @Published var message: String?

    private let client = SiteClient.shared
    private var polls: [String: Task<Void, Never>] = [:]

    private var filtered: [FlowSummary] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return workflows }
        return workflows.filter {
            $0.title.lowercased().contains(term)
                || ($0.description ?? "").lowercased().contains(term)
                || $0.trigger.description.lowercased().contains(term)
        }
    }

    var attention: [FlowSummary] { filtered.filter(\.needsAttention) }
    var rest: [FlowSummary] { filtered.filter { !$0.needsAttention } }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false; loaded = true }
        do {
            let list: FlowList = try await client.send("api/native/workflows")
            workflows = list.workflows
            message = nil
        } catch SiteError.expired {
            message = "This iPhone needs pairing again."
        } catch {
            message = workflows.isEmpty ? error.localizedDescription : "Could not refresh — showing what loaded last."
        }
    }

    /// Start a run. Returns its id so the caller can open it.
    func run(_ flow: FlowSummary) async -> String? {
        busySlug = flow.slug
        defer { busySlug = nil }
        do {
            let started: FlowRunStarted = try await client.send(
                "api/native/workflows/\(flow.slug)/run", method: "POST", body: try encodeBody([:])
            )
            SRHaptic.ok()
            message = "Started “\(flow.title)”."
            return started.runId.isEmpty ? nil : started.runId
        } catch {
            SRHaptic.bad()
            message = error.localizedDescription
            return nil
        }
    }

    /// Pause or resume a schedule. Only a cron trigger has one to pause.
    func setEnabled(_ flow: FlowSummary, _ enabled: Bool) async {
        guard flow.trigger.kind == .cron else { return }
        busySlug = flow.slug
        defer { busySlug = nil }
        var body: [String: JSONValue] = ["kind": .string("cron"), "enabled": .bool(enabled)]
        if let cron = flow.trigger.cron { body["cron"] = .string(cron) }
        body["timezone"] = .string(flow.trigger.timezone ?? FlowDefaults.timezone)
        do {
            try await client.call("api/native/workflows/\(flow.slug)/trigger", method: "PUT", body: try encodeBody(body))
            SRHaptic.select()
            message = enabled ? "Schedule resumed." : "Schedule paused."
            await load()
        } catch {
            SRHaptic.bad()
            message = error.localizedDescription
        }
    }

    func delete(_ flow: FlowSummary) async {
        let before = workflows
        workflows.removeAll { $0.slug == flow.slug }
        do {
            try await client.call("api/native/workflows/\(flow.slug)", method: "DELETE")
            SRHaptic.ok()
            message = "Deleted “\(flow.title)”."
        } catch {
            workflows = before
            SRHaptic.bad()
            message = error.localizedDescription
        }
    }

    /// Blank (`prompt == nil`) or described. A described one comes back
    /// `building: true` and is watched here until the model is done.
    func create(title: String, prompt: String?) async -> FlowCreated? {
        var body: [String: JSONValue] = [:]
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            body["prompt"] = .string(prompt)
            if !trimmedTitle.isEmpty { body["title"] = .string(trimmedTitle) }
        } else {
            body["title"] = .string(trimmedTitle.isEmpty ? "Untitled workflow" : trimmedTitle)
        }
        do {
            let created: FlowCreated = try await client.send(
                "api/native/workflows", method: "POST", body: try encodeBody(body)
            )
            SRHaptic.ok()
            if created.building {
                let label = trimmedTitle.isEmpty ? "New workflow" : trimmedTitle
                building.insert(PendingBuild(slug: created.slug, title: label), at: 0)
                watch(created.slug)
            } else {
                await load()
            }
            return created
        } catch {
            SRHaptic.bad()
            message = error.localizedDescription
            return nil
        }
    }

    func dismissBuild(_ slug: String) {
        polls[slug]?.cancel()
        polls[slug] = nil
        building.removeAll { $0.slug == slug }
    }

    /// Poll the detail until the model has finished. Three seconds is the
    /// scale a build takes (tens of seconds); faster would be chatter.
    private func watch(_ slug: String) {
        polls[slug]?.cancel()
        polls[slug] = Task { [weak self] in
            var attempts = 0
            while !Task.isCancelled, attempts < 200 {
                attempts += 1
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                do {
                    let detail: FlowDetail = try await self.client.send("api/native/workflows/\(slug)")
                    if let error = detail.buildError {
                        self.markFailed(slug, error)
                        return
                    }
                    if !detail.building {
                        self.building.removeAll { $0.slug == slug }
                        self.message = "“\(detail.title)” is ready."
                        SRHaptic.ok()
                        await self.load()
                        return
                    }
                } catch {
                    // A transient failure keeps polling; a missing workflow stops.
                    if (error as? SiteError)?.status == 404 {
                        self.markFailed(slug, "The workflow went away while it was being built.")
                        return
                    }
                }
            }
        }
    }

    private func markFailed(_ slug: String, _ error: String) {
        if let index = building.firstIndex(where: { $0.slug == slug }) {
            building[index].error = error
        }
        SRHaptic.bad()
    }
}

enum FlowDefaults {
    static let timezone = "Europe/London"
}

// MARK: - One workflow

@MainActor
final class FlowDetailStore: ObservableObject {
    let slug: String
    @Published private(set) var detail: FlowDetail?
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published var message: String?
    /// Proposals the server has no endpoint for yet (404) are hidden, not
    /// shown with buttons that cannot work.
    @Published private(set) var fixesUnavailable = false
    @Published private(set) var catalogue: FlowCatalogue?

    private let client = SiteClient.shared
    private var buildPoll: Task<Void, Never>?

    init(slug: String) { self.slug = slug }

    var layout: [FlowLayoutRow] { FlowLayout.rows(for: detail?.steps ?? []) }

    var fixProposals: [FlowFixProposal] { fixesUnavailable ? [] : (detail?.fixProposals ?? []) }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let fetched: FlowDetail = try await client.send("api/native/workflows/\(slug)")
            detail = fetched
            if fetched.building { pollWhileBuilding() }
        } catch SiteError.expired {
            message = "This iPhone needs pairing again."
        } catch {
            message = error.localizedDescription
        }
    }

    private func pollWhileBuilding() {
        guard buildPoll == nil else { return }
        buildPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                let fetched: FlowDetail? = try? await self.client.send("api/native/workflows/\(self.slug)")
                if let fetched {
                    self.detail = fetched
                    if !fetched.building {
                        self.buildPoll = nil
                        return
                    }
                }
            }
        }
    }

    /// Apply ops against the version on screen.
    func amend(_ ops: [JSONValue]) async -> FlowWriteResult {
        guard !ops.isEmpty else { return .saved }
        saving = true
        defer { saving = false }
        do {
            let body = try flowEncoder.encode(FlowAmendRequest(ops: ops, expectedVersion: detail?.version))
            let result: FlowAmendResult = try await client.send(
                "api/native/workflows/\(slug)/amend", method: "POST", body: body
            )
            SRHaptic.ok()
            message = result.outcomes.count == 1 ? sentence(result.outcomes[0].summary) : "Saved \(result.outcomes.count) changes."
            await load()
            return .saved
        } catch SiteError.invalid(let text, let field) {
            SRHaptic.bad()
            return .invalid(field: field, message: text)
        } catch SiteError.status(let code, _) where code == 409 {
            SRHaptic.bad()
            await load()
            message = "Changed somewhere else first — reloaded. Your edit was not saved."
            return .conflict
        } catch SiteError.status(let code, let text) where code == 422 {
            SRHaptic.bad()
            return .invalid(field: nil, message: text)
        } catch {
            SRHaptic.bad()
            return .failed(error.localizedDescription)
        }
    }

    private func sentence(_ text: String) -> String {
        guard let first = text.first else { return "Saved." }
        return first.uppercased() + text.dropFirst() + "."
    }

    func setTrigger(kind: FlowTriggerKind, cron: String?, timezone: String, enabled: Bool) async -> FlowWriteResult {
        saving = true
        defer { saving = false }
        var body: [String: JSONValue] = ["kind": .string(kind == .cron ? "cron" : "manual"), "enabled": .bool(enabled)]
        if kind == .cron {
            if let cron { body["cron"] = .string(cron) }
            body["timezone"] = .string(timezone)
        }
        do {
            try await client.call("api/native/workflows/\(slug)/trigger", method: "PUT", body: try encodeBody(body))
            SRHaptic.ok()
            await load()
            return .saved
        } catch SiteError.invalid(let text, let field) {
            SRHaptic.bad()
            return .invalid(field: field, message: text)
        } catch SiteError.status(let code, let text) where code == 422 || code == 400 {
            SRHaptic.bad()
            return .invalid(field: nil, message: text)
        } catch {
            SRHaptic.bad()
            return .failed(error.localizedDescription)
        }
    }

    /// The trigger card's switch: same schedule, flipped.
    func toggleEnabled(_ enabled: Bool) async {
        guard let trigger = detail?.trigger, trigger.kind == .cron else { return }
        let result = await setTrigger(kind: .cron, cron: trigger.cron, timezone: trigger.timezone ?? FlowDefaults.timezone, enabled: enabled)
        switch result {
        case .saved: message = enabled ? "Schedule on." : "Schedule paused."
        case .invalid(_, let text), .failed(let text): message = text
        case .conflict: break
        }
    }

    func run() async -> String? {
        do {
            let started: FlowRunStarted = try await client.send(
                "api/native/workflows/\(slug)/run", method: "POST", body: try encodeBody([:])
            )
            SRHaptic.ok()
            // The run shows in recent runs on the next read.
            Task { await self.load() }
            return started.runId.isEmpty ? nil : started.runId
        } catch {
            SRHaptic.bad()
            message = error.localizedDescription
            return nil
        }
    }

    func resolve(_ proposal: FlowFixProposal, accept: Bool) async {
        do {
            try await client.call(
                "api/native/workflows/\(slug)/fix-proposals/\(proposal.id)",
                method: "POST",
                body: try encodeBody(["action": .string(accept ? "accept" : "dismiss")])
            )
            SRHaptic.ok()
            message = accept ? "Fix applied to “\(proposal.nodeLabel)”." : "Fix dismissed."
            detail?.fixProposals.removeAll { $0.id == proposal.id }
            await load()
        } catch SiteError.status(let code, _) where code == 404 {
            // The endpoint has not shipped yet: hide the banner rather than
            // keep offering a button that cannot work.
            fixesUnavailable = true
        } catch SiteError.status(let code, _) where code == 409 {
            await load()
            message = "That step changed since the fix was proposed — reloaded."
        } catch {
            SRHaptic.bad()
            message = error.localizedDescription
        }
    }

    /// PATCH takes a title and nothing else.
    func rename(to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await client.call(
                "api/native/workflows/\(slug)", method: "PATCH", body: try encodeBody(["title": .string(trimmed)])
            )
            detail?.title = trimmed
            SRHaptic.select()
        } catch {
            SRHaptic.bad()
            message = error.localizedDescription
        }
    }

    func delete() async -> Bool {
        do {
            try await client.call("api/native/workflows/\(slug)", method: "DELETE")
            SRHaptic.ok()
            return true
        } catch {
            SRHaptic.bad()
            message = error.localizedDescription
            return false
        }
    }

    func ask(_ instruction: String) async throws -> FlowProposal {
        try await client.send(
            "api/native/workflows/\(slug)/ask",
            method: "POST",
            body: try encodeBody(["instruction": .string(instruction)])
        )
    }

    func loadCatalogue() async {
        guard catalogue == nil else { return }
        do {
            catalogue = try await client.send("api/native/workflows/node-types")
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - One run

@MainActor
final class FlowRunStore: ObservableObject {
    let runId: String
    @Published private(set) var detail: FlowRunDetail?
    @Published var message: String?

    private let client = SiteClient.shared

    init(runId: String) { self.runId = runId }

    func load() async {
        do {
            detail = try await client.send("api/native/workflows/runs/\(runId)")
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    /// Re-read every two seconds while the run is live. Bound to the view's
    /// task, so leaving the screen stops it.
    func follow() async {
        await load()
        var ticks = 0
        while !Task.isCancelled, ticks < 300, let run = detail?.run, !run.state.isFinished {
            ticks += 1
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await load()
        }
    }
}

// MARK: - Today's card

/// How many workflows want looking at, for Today.
///
/// Its own request, after Today's first paint, rather than a field on
/// `/api/native/today`: the today payload does not carry workflows, and adding
/// the workflow list to the one call the app opens on would make the first
/// screen wait for the slowest thing on the site.
@MainActor
final class FlowAttentionStore: ObservableObject {
    @Published private(set) var flows: [FlowSummary] = []

    private let client = SiteClient.shared

    func load() async {
        guard client.isPaired else { return }
        do {
            let list: FlowList = try await client.send("api/native/workflows")
            flows = list.workflows.filter(\.needsAttention)
        } catch {
            // Silent: a missing card is the right failure for a summary.
        }
    }
}

import SwiftUI

// MARK: - The two gates the phone answers
//
// A turn can stop and ask for a plan approval or an answer to a question. Both
// used to show "Needs the website". They are answered here now, through the
// same `PATCH /api/workflows/orchestrator/chat` the web uses (`plan_ack`,
// `clarify_ack`), which has always been on the device lane.
//
// The other three stay on the desk, on purpose: `confirm` approves a command
// the agent wants to RUN, `approval` the same for a tool, and `secret_request`
// asks for a credential. A thumb on a train is not where those get approved,
// and an app that could would be one stolen phone from running anything.
//
// The stream is still dropped the moment a gate opens — that is what lets the
// site's WhatsApp escalation fire if nobody answers (see `ChatStore.handle`).
// Answering picks the same job back up from its last event.

struct PlanGate: Hashable {
    struct Step: Hashable, Identifiable {
        let id: String
        let title: String
        let detail: String
    }
    let planId: String
    let summary: String?
    let steps: [Step]
    let files: [String]

    init?(_ json: [String: Any]) {
        guard let planId = json["planId"] as? String,
              let plan = json["plan"] as? [String: Any] else { return nil }
        self.planId = planId
        summary = plan["summary"] as? String
        steps = (plan["steps"] as? [[String: Any]] ?? []).enumerated().map { index, raw in
            Step(
                id: raw["id"] as? String ?? "\(index)",
                title: raw["title"] as? String ?? "Step \(index + 1)",
                detail: raw["detail"] as? String ?? ""
            )
        }
        files = (plan["filesToTouch"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let path = raw["path"] as? String else { return nil }
            return "\(raw["action"] as? String ?? "change") \(path)"
        }
    }
}

struct ClarifyGate: Hashable {
    struct Question: Hashable, Identifiable {
        let id: String
        let text: String
        let choices: [String]
    }
    let clarifyId: String
    let questions: [Question]

    init?(_ json: [String: Any]) {
        guard let clarifyId = json["clarifyId"] as? String else { return nil }
        self.clarifyId = clarifyId
        questions = (json["questions"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let id = raw["id"] as? String, let text = raw["text"] as? String else { return nil }
            let choices = (raw["kind"] as? String) == "choice" ? (raw["choices"] as? [String] ?? []) : []
            return Question(id: id, text: text, choices: choices)
        }
        if questions.isEmpty { return nil }
    }
}

/// A plan, waiting on a yes.
struct PlanCard: View {
    let plan: PlanGate
    let answering: Bool
    let answer: (_ decision: String, _ adjustment: String?) -> Void
    @State private var adjusting = false
    @State private var adjustment = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRLabel(text: "Plan")
            if let summary = plan.summary, !summary.isEmpty {
                Text(summary)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.accent)
                            .frame(minWidth: 16, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(SR.Text.body(15))
                                .foregroundStyle(SR.ink)
                            if !step.detail.isEmpty {
                                Text(step.detail)
                                    .font(SR.Text.secondary())
                                    .foregroundStyle(SR.inkMuted)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }
            if !plan.files.isEmpty {
                Text(plan.files.prefix(6).joined(separator: "\n") + (plan.files.count > 6 ? "\n+\(plan.files.count - 6) more" : ""))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }

            HStack(spacing: 10) {
                Button {
                    SRHaptic.ok()
                    answer("approved", nil)
                } label: {
                    SRButtonLabel(title: "Approve", icon: "checkmark")
                }
                .srButton(.prominent)

                Menu {
                    Button { adjusting = true } label: { Label("Suggest a change", systemImage: "pencil") }
                    Button(role: .destructive) { answer("rejected", nil) } label: { Label("Reject", systemImage: "xmark") }
                } label: {
                    SRButtonLabel(title: "Other", icon: "ellipsis")
                }
                .srButton(.regular)
            }
            .disabled(answering)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .srGlassCard(.paper)
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .strokeBorder(SR.accent.opacity(0.55), lineWidth: 1)
        )
        .alert("Suggest a change", isPresented: $adjusting) {
            TextField("What should be different?", text: $adjustment)
            Button("Cancel", role: .cancel) { adjustment = "" }
            Button("Send") {
                let text = adjustment.trimmingCharacters(in: .whitespacesAndNewlines)
                adjustment = ""
                if !text.isEmpty { answer("adjusted", text) }
            }
        }
    }
}

/// Questions back from jkai, answered in place.
struct ClarifyCard: View {
    let gate: ClarifyGate
    let answering: Bool
    let answer: ([String: String]) -> Void
    @State private var answers: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRLabel(text: gate.questions.count == 1 ? "A question" : "\(gate.questions.count) questions")
            ForEach(gate.questions) { question in
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.text)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if question.choices.isEmpty {
                        TextField("Your answer", text: binding(question.id), axis: .vertical)
                            .font(SR.Text.body())
                            .lineLimit(1...4)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .srGlass(.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        // Choices as a column of rows, not a segmented control:
                        // a choice is often a sentence, and segments truncate.
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(question.choices, id: \.self) { choice in
                                Button {
                                    SRHaptic.select()
                                    answers[question.id] = choice
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: answers[question.id] == choice ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(answers[question.id] == choice ? SR.accent : SR.inkMuted)
                                        Text(choice)
                                            .font(SR.Text.body(15))
                                            .foregroundStyle(SR.ink)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(minHeight: SR.tapTarget)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Button {
                SRHaptic.ok()
                answer(answers.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            } label: {
                SRButtonLabel(title: "Answer", icon: "arrow.up")
            }
            .srButton(.prominent)
            .disabled(answering || !complete)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .srGlassCard(.paper)
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .strokeBorder(SR.accent.opacity(0.55), lineWidth: 1)
        )
    }

    private var complete: Bool {
        gate.questions.allSatisfy { !(answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func binding(_ id: String) -> Binding<String> {
        Binding(get: { answers[id] ?? "" }, set: { answers[id] = $0 })
    }
}

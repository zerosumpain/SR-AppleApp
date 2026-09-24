import SwiftUI

/// What a thread runs on. `GET /api/native/chat/conversations/:id/model`.
struct ThreadModel: Decodable {
    struct Choice: Decodable, Hashable, Identifiable {
        let provider: String
        let modelId: String
        let label: String
        let group: String
        var id: String { "\(provider)|\(modelId)" }
    }
    struct Current: Decodable, Hashable {
        let provider: String
        let modelId: String
        let label: String
    }
    let current: Current
    let locked: Bool
    var thinkingLevel: String?
    let supportsThinking: Bool
    let levels: [String]
    let choices: [Choice]
}

@MainActor
final class ThreadModelStore: ObservableObject {
    @Published private(set) var model: ThreadModel?
    @Published private(set) var saving = false
    @Published var message: String?
    let conversationId: String
    private let client = SiteClient.shared

    init(conversationId: String) { self.conversationId = conversationId }

    func load() async {
        do {
            model = try await client.send("api/native/chat/conversations/\(conversationId)/model")
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func choose(_ choice: ThreadModel.Choice) async {
        await patch(["modelProvider": choice.provider, "modelId": choice.modelId])
    }

    /// `nil` is "Auto": the provider's own default.
    func setThinking(_ level: String?) async {
        await patch(["thinkingLevel": level ?? "auto"])
    }

    private func patch(_ body: [String: String]) async {
        saving = true
        defer { saving = false }
        do {
            let _: EmptyReply = try await client.send(
                "api/native/chat/conversations/\(conversationId)",
                method: "PATCH",
                body: try JSONEncoder().encode(body)
            )
            SRHaptic.select()
            // Re-read rather than patch locally: a model change also changes
            // which thinking levels exist, and the server is the one that knows.
            await load()
        } catch {
            message = error.localizedDescription
            SRHaptic.bad()
        }
    }
}

/// Model and thinking, from the thread's menu — never the composer.
///
/// The composer is where you type. A model chip beside it is a control you
/// brush past forty times for every once you mean to use it, which is why the
/// web's picker lives in the header and this lives behind the ellipsis.
struct ThreadModelSheet: View {
    @StateObject private var store: ThreadModelStore
    @Environment(\.dismiss) private var dismiss

    init(conversationId: String) {
        _store = StateObject(wrappedValue: ThreadModelStore(conversationId: conversationId))
    }

    var body: some View {
        NavigationStack {
            List {
                if let model = store.model {
                    modelSection(model)
                    thinkingSection(model)
                } else if store.message == nil {
                    HStack { Spacer(); ProgressView().tint(SR.accent); Spacer() }.srGlassRow()
                }
                if let message = store.message {
                    Text(message)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.error)
                        .srGlassRow()
                }
            }
            .listStyle(.insetGrouped)
            .srGround(.quiet)
            .disabled(store.saving)
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await store.load() }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func modelSection(_ model: ThreadModel) -> some View {
        Section {
            if model.locked {
                row(model.current.label, detail: nil, selected: true).srGlassRow()
            } else {
                ForEach(model.choices) { choice in
                    Button {
                        Task { await store.choose(choice) }
                    } label: {
                        row(choice.label, detail: groupLabel(choice.group), selected:
                            choice.provider == model.current.provider && choice.modelId == model.current.modelId)
                    }
                    .buttonStyle(.plain)
                    .srGlassRow()
                }
            }
        } header: {
            SRSectionLabel(text: "Model")
        } footer: {
            Text(model.locked
                 ? "Fixed once a thread has its first message, because its price is set then. Start a new thread to use another."
                 : "The site's default, the Codex models, and the ones you have used lately.")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkMuted)
        }
    }

    @ViewBuilder
    private func thinkingSection(_ model: ThreadModel) -> some View {
        Section {
            if model.supportsThinking {
                Button { Task { await store.setThinking(nil) } } label: {
                    row("Auto", detail: "The model decides", selected: model.thinkingLevel == nil)
                }
                .buttonStyle(.plain)
                .srGlassRow()
                ForEach(model.levels, id: \.self) { level in
                    Button { Task { await store.setThinking(level) } } label: {
                        row(level.capitalized, detail: nil, selected: model.thinkingLevel == level)
                    }
                    .buttonStyle(.plain)
                    .srGlassRow()
                }
            } else {
                Text("This model does not take a thinking level.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .srGlassRow()
            }
        } header: {
            SRSectionLabel(text: "Thinking")
        } footer: {
            if model.supportsThinking {
                Text("Can be changed at any point. More thinking is slower and costs more.")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
            }
        }
    }

    private func row(_ title: String, detail: String?, selected: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SR.Text.body())
                    .foregroundStyle(SR.ink)
                if let detail {
                    Text(detail).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(SR.accent)
            }
        }
        .frame(minHeight: SR.tapTarget)
        .contentShape(Rectangle())
    }

    private func groupLabel(_ group: String) -> String? {
        switch group {
        case "default": return "DEFAULT"
        case "codex": return "CODEX"
        default: return nil
        }
    }
}

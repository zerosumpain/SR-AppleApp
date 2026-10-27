import SwiftUI

// "Allow users to add game types they want to see in the future" (John,
// 2026-10-27): a short form at the foot of the Games page, and the family's
// list under it with a +1 each. The site keeps the list
// (`/api/native/games/suggestions`); a name somebody already asked for is a
// +1 on theirs rather than a second row, so the list reads as what the family
// wants most. Everybody in the family sees it, the owner included — that is
// how an idea reaches whoever builds the next game.

@MainActor
final class GameSuggestionsStore: ObservableObject {
    @Published private(set) var list: GameSuggestionList?
    @Published private(set) var working = false
    /// The last refusal, in the site's words, for the form or the list.
    @Published var problem: String?
    /// The site said this person is not in the family (403): the section is
    /// not for them, so it is not drawn.
    @Published private(set) var outside = false

    private let client = SiteClient.shared
    private static let path = "api/native/games/suggestions"

    var suggestions: [GameSuggestion] { list?.suggestions ?? [] }

    func load() async {
        do {
            let next: GameSuggestionList = try await client.send(Self.path)
            if next != list { list = next }
        } catch is CancellationError {
            return
        } catch SiteError.status(let code, _) where code == 403 {
            outside = true
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            // Quietly: the ideas are a footnote to the page, and a list on
            // screen stays as it was until the next read.
        }
    }

    /// Suggest a game. True when the site took it.
    func suggest(_ draft: GameSuggestionDraft) async -> Bool {
        guard draft.isReady else { return false }
        return await change(Body(name: draft.cleanName, note: draft.cleanNote))
    }

    /// +1, or take a +1 back.
    func vote(_ suggestion: GameSuggestion) async {
        _ = await change(Body(id: suggestion.id, vote: !suggestion.voted))
    }

    /// Take an idea off the list (whoever asked for it, or a parent).
    func remove(_ suggestion: GameSuggestion) async {
        _ = await change(Body(id: suggestion.id, remove: true))
    }

    private func change(_ body: Body) async -> Bool {
        guard !working else { return false }
        working = true
        defer { working = false }
        do {
            let next: GameSuggestionList = try await client.send(Self.path, method: "POST", body: try JSONEncoder().encode(body))
            list = next
            problem = nil
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    /// The POST's body. Nil fields are left out of the JSON.
    private struct Body: Encodable {
        var name: String? = nil
        var note: String? = nil
        var id: String? = nil
        var vote: Bool? = nil
        var remove: Bool? = nil
    }
}

/// The foot of the Games page: "Suggest a game", then the family's ideas.
struct GameSuggestionsSection: View {
    @StateObject private var store = GameSuggestionsStore()
    @State private var composing = false

    var body: some View {
        if store.outside {
            EmptyView()
        } else {
            section
        }
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Games you’d like", trailing: store.suggestions.isEmpty ? nil : "\(store.suggestions.count)")

            Button {
                SRHaptic.tap()
                composing = true
            } label: {
                SRCard(interactive: true) {
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SR.Hue.daydream.onFill)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(SR.Hue.daydream.gradient))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Suggest a game")
                                .font(SR.Text.title())
                                .foregroundStyle(SR.ink)
                            Text("Something you’d like to play here one day. The family can +1 it.")
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(SR.accent)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: SR.tapTarget)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("games-suggest")

            if !store.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(store.suggestions.enumerated()), id: \.element.id) { index, idea in
                        if index > 0 { Divider().overlay(SR.divider) }
                        row(idea)
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 6)
                .srGlassCard(.paper)
            }

            if let problem = store.problem, store.list != nil {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await store.load() }
        .sheet(isPresented: $composing) {
            SuggestGameSheet(store: store)
        }
    }

    private func row(_ idea: GameSuggestion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(idea.name)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !idea.note.isEmpty {
                    Text(idea.note)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(idea.byline)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 8)
            Button {
                SRHaptic.select()
                Task { await store.vote(idea) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: idea.voted ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 13, weight: .semibold))
                    Text("+1")
                        .font(SR.Text.title(14))
                }
                .foregroundStyle(idea.voted ? SR.paper : SR.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Capsule().fill(idea.voted ? SR.accentDeep : SR.surface))
                .overlay(Capsule().strokeBorder(idea.voted ? Color.clear : SR.line, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.working)
            .accessibilityLabel(idea.voted ? "Take back your +1" : "+1 \(idea.name)")
            .accessibilityAddTraits(idea.voted ? .isSelected : [])
            .accessibilityIdentifier("games-suggestion-vote-\(idea.id)")
        }
        .padding(.vertical, 10)
        .contextMenu {
            if idea.mine || store.list?.parent == true {
                Button(role: .destructive) {
                    Task { await store.remove(idea) }
                } label: {
                    Label("Take it off the list", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("games-suggestion-\(idea.id)")
    }
}

/// The form: a name, and a line about it if they like.
private struct SuggestGameSheet: View {
    @ObservedObject var store: GameSuggestionsStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = GameSuggestionDraft()
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    SRPageHeader(kicker: "Games", title: "Suggest a game",
                                 strap: "What would you like to play here? A name is enough; a line about it helps.")

                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The game")
                        TextField("Moon lander, kart race…", text: $draft.name)
                            .font(SR.Text.body())
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.next)
                            .focused($nameFocused)
                            .padding(SR.cardPadding)
                            .srGlassCard(.paper)
                            .accessibilityIdentifier("games-suggest-name")
                        SRSectionLabel(text: "How it would play (optional)")
                        TextField("Tilt the phone to land gently…", text: $draft.note, axis: .vertical)
                            .font(SR.Text.body())
                            .lineLimit(2...5)
                            .padding(SR.cardPadding)
                            .srGlassCard(.paper)
                            .accessibilityIdentifier("games-suggest-note")
                    }

                    if let problem = store.problem {
                        Label(problem, systemImage: "exclamationmark.circle")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        SRHaptic.tap()
                        Task {
                            if await store.suggest(draft) {
                                SRHaptic.ok()
                                dismiss()
                            }
                        }
                    } label: {
                        SRButtonLabel(title: "Suggest it", icon: "paperplane.fill", fill: true)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .disabled(!draft.isReady || store.working)
                    .accessibilityIdentifier("games-suggest-send")
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .srGround(.warm)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("games-suggest-cancel")
                }
            }
            .onAppear {
                store.problem = nil
                nameFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }
}

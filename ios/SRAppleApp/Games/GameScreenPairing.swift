import SwiftUI
import UIKit

// "Show on TV", for any game with a TV board — the games the lobby lists in
// `screens` (today Azul). The TV opens strangeramblings.com/games/<game>,
// which is public (a TV has no login) and shows four letters; somebody in the
// room types them here, the phone posts `{action:"screen", code}` to the room,
// and the site sends that TV a ticket for the room. The TV then follows the
// table until the game ends. Nothing here knows which game it is beyond its id.
//
// The post goes straight through `SiteClient`, not the room's `GameRoomLink`:
// "No TV is showing that code" is a 404, and a link reads a 404 as the room
// having gone.

enum GameScreenPairing {
    enum Outcome: Equatable {
        case paired
        /// The site's sentence, for the person typing.
        case refused(String)
    }

    /// Pair the TV showing `code` with the room.
    @MainActor
    static func pair(roomId: String, code: String) async -> Outcome {
        var body = GameActionBody(action: "screen")
        body.code = code
        do {
            _ = try await SiteClient.shared.post("api/native/games/\(roomId)", body: try JSONEncoder().encode(body))
            return .paired
        } catch SiteError.status(_, let sentence) {
            let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            return .refused(text.isEmpty ? "That didn't work. Check the letters on the TV and try again." : text)
        } catch {
            return .refused(error.localizedDescription)
        }
    }

    /// Whether this game's rooms offer "Show on TV": the lobby lists it. A
    /// room opened before any lobby was read offers it too, and the site
    /// says so if it cannot.
    static func offered(_ game: String, lobby: GamesLobby?) -> Bool {
        lobby?.screens.contains(game) ?? true
    }
}

/// The big "Show on TV" button, for a lobby set up for the TV.
struct GameShowOnTVButton: View {
    let prefix: String
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            TableButtonLabel(title: "Show on TV", icon: "tv")
        }
        .buttonStyle(TableSolidButtonStyle())
        .accessibilityHint("Pairs a TV showing the board with this game")
        .accessibilityIdentifier("\(prefix)-tv")
    }
}

/// The toolbar's quieter way in, for a room not set up for the TV.
struct GameShowOnTVToolbarButton: View {
    let prefix: String
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            Image(systemName: "tv")
        }
        .accessibilityLabel("Show on TV")
        .accessibilityIdentifier("\(prefix)-tv-toolbar")
    }
}

/// The sheet: where to open the board, the four letters, and the answer —
/// the site's sentence when it refuses, a tick and "On the TV" when it pairs.
struct GameScreenPairingSheet: View {
    let roomId: String
    let game: String
    let prefix: String

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var working = false
    @State private var refusal: String?
    @State private var paired = false
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    SRPageHeader(kicker: GameNames.title(game), title: paired ? "On the TV" : "Show on TV",
                                 strap: paired ? nil : GameScreenCode.instruction(game))
                    if paired {
                        pairedCard
                    } else {
                        steps
                        codeField
                        if let refusal { refusalLine(refusal) }
                        sendButton
                    }
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .srGround(.warm)
            .navigationTitle("Show on TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(paired ? "Done" : "Cancel") { dismiss() }
                        .accessibilityIdentifier("\(prefix)-tv-close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("\(prefix)-tv-sheet")
        .onAppear { typing = true }
    }

    private var steps: some View {
        TableHowToList(steps: [
            TableHowToStep(icon: "tv", title: "On the TV",
                           text: "Open \(GameScreenCode.address(game)) in its browser, or cast a laptop that has it open."),
            TableHowToStep(icon: "character.cursor.ibeam", title: "Type its letters",
                           text: "The board shows four letters. Type them below and the TV picks up this game."),
        ])
    }

    private var codeField: some View {
        TextField("BCDF", text: $code)
            .font(SR.Text.figure(34))
            .tracking(10)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .submitLabel(.go)
            .focused($typing)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
            .onChange(of: code) { _, typed in
                let kept = GameScreenCode.typing(typed)
                if kept != typed { code = kept }
                refusal = nil
                // Four letters is a whole code: send it without another tap.
                if kept.count == GameScreenCode.length, !working { send() }
            }
            .onSubmit { send() }
            .accessibilityLabel("The four letters on the TV")
            .accessibilityIdentifier("\(prefix)-tv-code")
    }

    private func refusalLine(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(SR.Text.bodyMedium(15))
            .foregroundStyle(SR.error)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("\(prefix)-tv-refusal")
    }

    private var sendButton: some View {
        Button { send() } label: {
            if working {
                ProgressView().tint(SR.paper)
            } else {
                TableButtonLabel(title: "Show it", icon: "tv")
            }
        }
        .buttonStyle(TableSolidButtonStyle())
        .disabled(working || GameScreenCode.normalise(code) == nil)
        .accessibilityLabel("Show it on the TV")
        .accessibilityIdentifier("\(prefix)-tv-send")
    }

    private var pairedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(SR.Text.hero(40))
                    .foregroundStyle(SR.good)
                    .tablePopIn()
                    .accessibilityHidden(true)
                Text("On the TV")
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
            }
            Text("The TV shows this game now and follows it to the end. Every phone still shows the whole table.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { dismiss() } label: {
                TableButtonLabel(title: "Back to the table", icon: "arrow.uturn.backward")
            }
            .buttonStyle(TableSolidButtonStyle())
            .accessibilityIdentifier("\(prefix)-tv-done")
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(prefix)-tv-paired")
    }

    private func send() {
        guard !working, let whole = GameScreenCode.normalise(code) else { return }
        working = true
        refusal = nil
        Task {
            let outcome = await GameScreenPairing.pair(roomId: roomId, code: whole)
            working = false
            switch outcome {
            case .paired:
                typing = false
                paired = true
                SRHaptic.ok()
                UIAccessibility.post(notification: .announcement, argument: "On the TV")
            case .refused(let sentence):
                refusal = sentence
                SRHaptic.bad()
                UIAccessibility.post(notification: .announcement, argument: sentence)
            }
        }
    }
}

import SwiftUI

// The banner across every page while a game lobby is open for me (John,
// 2026-10-27: "have a lobby banner across all pages when there's one open").
//
// A slim strip ABOVE the tabs, the way the review demo's strip is, rather than
// an overlay: stacked, it pushes each page down by its own height and never
// sits over a control — a composer, a tab, the ⊞ — even for a moment. It
// offers one lobby (`LobbyBannerPick`): an invite to answer first, else a
// lobby I am already waiting in. Join or Open takes me there; the cross puts
// that lobby's banner away for good. It stays off the Games tab, which lists
// the same lobbies itself, and off the demo (its screenshots are approved as
// they are) unless a UI test asks for it.

/// Word from a room screen that a parent closed its lobby, for the banner to
/// say on whichever page is open.
enum GameLobbyNews {
    static let closedName = Notification.Name("sr.games.lobby-closed")

    /// `line`: "Dad closed the Chess lobby."
    static func closed(_ line: String) {
        NotificationCenter.default.post(name: closedName, object: line)
    }
}

extension View {
    /// The open-lobby banner, above everything this view holds. Applied once,
    /// round the tabs, in `ContentView`.
    func srGameLobbyBanner(_ store: GamesStore, router: Router) -> some View {
        modifier(GameLobbyBanner(store: store, router: router))
    }
}

struct GameLobbyBanner: ViewModifier {
    let store: GamesStore
    let router: Router

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            // Its own view, observing the store and the router itself: the
            // tabs below are not rebuilt when only the banner changes.
            GameLobbyStrip(store: store, router: router)
            content
        }
    }
}

/// The strip itself: nothing at all when there is nothing to say.
private struct GameLobbyStrip: View {
    @ObservedObject var store: GamesStore
    @ObservedObject var router: Router
    @ObservedObject private var access = AccessStore.shared

    var body: some View {
        Group {
            if !Self.allowed || !access.allows(.games) {
                EmptyView()
            } else if let note = store.closedNote {
                closed(note)
            } else if router.tab != .games, let lobby = store.bannerLobby {
                offer(lobby)
            }
        }
        .animation(.snappy, value: store.closedNote)
        .animation(.snappy, value: store.bannerLobby?.roomId)
    }

    /// Off in the demo, whose screenshots were approved without it; a UI
    /// test that wants it passes `-SRLobbyBanner`.
    private static var allowed: Bool {
        guard SRDemo.isOn else { return true }
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-SRLobbyBanner")
        #else
        return false
        #endif
    }

    // MARK: - An open lobby

    /// The game's badge, who and what in two short lines, the answer (Join
    /// or Open) as a solid button, and a full-size cross to put it away.
    /// In the game's own shelf colour, so a Chess lobby and a Boggle invite
    /// look like the tiles they came from.
    private func offer(_ lobby: LobbyBannerCandidate) -> some View {
        let hue = GamesArt.hue(lobby.game)
        return HStack(spacing: 8) {
            Button { go(lobby) } label: {
                HStack(spacing: 10) {
                    Image(systemName: GamesArt.icon(lobby.game))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(hue.base)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(hue.onFill.opacity(0.94)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kicker(lobby).uppercased())
                            .font(SR.Text.label(12))
                            .tracking(1)
                            .opacity(0.85)
                            .lineLimit(1)
                        Text(lobby.line)
                            .font(SR.Text.bodyMedium(15))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        if store.busy == lobby.roomId {
                            ProgressView().tint(hue.base)
                        } else {
                            Text(lobby.action)
                                .font(SR.Text.title(15))
                        }
                    }
                    .foregroundStyle(hue.base)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(hue.onFill))
                }
                .frame(minHeight: SR.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(SRPressStyle())
            .disabled(store.busy == lobby.roomId)
            .accessibilityLabel("\(lobby.line). \(lobby.action)")
            .accessibilityIdentifier("lobby-banner-open")

            Button {
                SRHaptic.select()
                withAnimation(.snappy) { store.dismissBanner(lobby.roomId) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: SR.tapTarget, height: SR.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide this lobby")
            .accessibilityIdentifier("lobby-banner-dismiss")
        }
        .foregroundStyle(hue.onFill)
        .padding(.leading, SR.gutter - 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                hue.gradient
                RadialGradient(colors: [Color.white.opacity(0.22), Color.clear],
                               center: .topLeading, startRadius: 0, endRadius: 260)
            }
            .ignoresSafeArea(edges: .top)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lobby-banner")
    }

    /// What kind of news it is, above the line that says whose.
    private func kicker(_ lobby: LobbyBannerCandidate) -> String {
        lobby.kind == .invite ? "Game invite" : "Lobby open"
    }

    /// Join an invite and open its room, or open a lobby I am already in.
    private func go(_ lobby: LobbyBannerCandidate) {
        SRHaptic.tap()
        switch lobby.kind {
        case .waiting:
            router.openGame(lobby.roomId, game: lobby.game)
        case .invite:
            guard let invite = store.invites.first(where: { $0.roomId == lobby.roomId }) else {
                router.show(.games)
                return
            }
            Task {
                if await store.join(invite) {
                    SRHaptic.ok()
                    router.openGame(invite.roomId, game: invite.game)
                } else {
                    SRHaptic.bad()
                    // Gone or refused: the Games page says why (`store.message`).
                    router.show(.games)
                }
            }
        }
    }

    // MARK: - A lobby a parent closed

    private func closed(_ note: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 14, weight: .bold))
                .accessibilityHidden(true)
            Text(note)
                .font(SR.Text.bodyMedium(15))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                store.closedNote = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: SR.tapTarget, height: SR.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(SR.paper)
        .padding(.leading, SR.gutter)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(SR.ink.ignoresSafeArea(edges: .top))
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lobby-banner-closed")
        // Said, then gone: a few seconds is long enough to read one line.
        .task(id: note) {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled, store.closedNote == note { store.closedNote = nil }
        }
    }
}

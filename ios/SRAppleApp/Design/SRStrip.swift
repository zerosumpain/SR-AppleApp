import SwiftUI
import UIKit

/// The strip of chips under the bar on Family, Games and Health — the same
/// furniture on each, so the top of every tab reads the same way (John,
/// 2026-10-21: "one layout for all").
///
/// What a chip does is the page's business: on Family a chip is a favourite
/// place, and choosing it frames the map there; on Games and Health it opens
/// a section. A chip that is a place to GO (`selected` never set) reads as a
/// door; one that filters the page stays lit while it holds.
struct SRChip: Identifiable, Equatable {
    let id: String
    let title: String
    var icon: String? = nil
    /// A small figure after the title — people at a place, invites waiting.
    var count: Int? = nil
}

struct SRChipStrip: View {
    let chips: [SRChip]
    /// The chip holding the page, if any.
    var selected: String? = nil
    var identifier = "chip-strip"
    let choose: (SRChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let on = chip.id == selected
                    Button {
                        SRHaptic.select()
                        choose(chip)
                    } label: {
                        HStack(spacing: 5) {
                            if let icon = chip.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            Text(chip.title)
                                .font(SR.Text.title(14))
                                .lineLimit(1)
                            if let count = chip.count, count > 0 {
                                Text("\(count)")
                                    .font(SR.monoMedium(12))
                                    .foregroundStyle(on ? SR.paper.opacity(0.85) : SR.inkMuted)
                            }
                        }
                        .foregroundStyle(on ? SR.paper : SR.ink)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(on ? SR.accentDeep : SR.surface))
                        .overlay(Capsule().strokeBorder(on ? Color.clear : SR.line, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chip.count.map { "\(chip.title), \($0)" } ?? chip.title)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("\(identifier)-\(chip.id)")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 6)
        }
        // A horizontal scroll view in a stack grows to fill what it is
        // offered; its own height is the chips'.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

extension View {
    /// A strip pinned under the bar with the page scrolling behind both, as
    /// every tab's page scrolls behind the `sr.` mark.
    ///
    /// A plain inset on every OS. `safeAreaBar` stretched iOS 26's
    /// scroll-edge effect down under the strip, which painted a grey band
    /// across the top of Health with a shadow over everything scrolling
    /// under it (John, 2026-10-27). Inset, the effect stays the bar's own
    /// height, as on every other tab, and the chips — opaque capsules —
    /// float over the page.
    func srPinnedStrip<Strip: View>(@ViewBuilder _ strip: () -> Strip) -> some View {
        safeAreaInset(edge: .top, spacing: 0) { strip() }
    }

    /// The top of a tab's first page, the same on every tab: Home on the left
    /// (John, 2026-10-27: "move the home icon to the top left"), the `sr.`
    /// mark in the middle. The page adds its own trailing items. On Home
    /// itself the left is empty: it is where the house would take you.
    func srTabBar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) { SRHomeButton() }
            ToolbarItem(placement: .principal) { SRBarMark() }
        }
    }

    /// The tray along the foot of a page: a tab's first page, or More. Inset
    /// rather than overlaid, so the page's last row scrolls up clear of it.
    func srTray(_ place: SRTray.Place) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { SRTray(place: place) }
    }
}

/// The house at the top left of every tab's first page: Home, from anywhere,
/// on its own first page. It replaced the ⊞ that opened the hub, which is the
/// tray's More now.
struct SRHomeButton: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        // Anywhere but Home's own first page — More opened over Home too.
        if router.tab != .today || !router.today.isEmpty {
            Button {
                SRHaptic.tap()
                router.goHome()
            } label: {
                Image(systemName: "house")
            }
            .accessibilityLabel("Home")
            .accessibilityHint("The family, the briefing and every tile")
            .accessibilityIdentifier("open-home")
        }
    }
}

/// The tray: the places on the bar — Family, Games, Chat, Health, as this
/// person may open them — and More, which opens the More apps page. Home is
/// not in it: Home is the house at the top left (John, 2026-10-27).
///
/// Drawn by the app, not the system's tab bar. The system bar cannot leave
/// out the tab that is showing — Home is still a tab underneath, so it keeps
/// its stack and its state — and cannot hold a button that is not a tab, as
/// More is. So the system bar is hidden (`ContentView`) and this sits on the
/// first page of every tab and on More. Pages pushed above those have no
/// tray, as a game room or a chat thread never had a bar: Back leads out.
///
/// It steps aside while the keyboard is up, as the system bar did, rather
/// than riding up on top of it.
struct SRTray: View {
    enum Place: Equatable {
        case tab(Router.Tab)
        case more
    }

    let place: Place
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var games: GamesStore
    @ObservedObject private var access = AccessStore.shared
    @State private var keyboard = false

    var body: some View {
        // A ZStack, not a Group: a Group passes its modifiers on to its
        // children, so while the keyboard has the tray hidden there would be
        // nothing left to hear the keyboard go and the tray would never come
        // back. The ZStack is always there, empty and sizeless when hidden.
        ZStack {
            if !keyboard {
                SRGlassGroup(spacing: 4) {
                    HStack(spacing: 2) {
                        ForEach(tabs, id: \.self) { tab in
                            item(title: title(tab), symbol: symbol(tab), on: place == .tab(tab),
                                 badge: tab == .games ? games.invites.count : 0,
                                 identifier: "tray-\(tab.rawValue)") { choose(tab) }
                        }
                        item(title: "More", symbol: "square.grid.2x2", on: place == .more, badge: 0,
                             identifier: "open-hub") { openMore() }
                    }
                    .padding(5)
                    .srGlass(.paper, in: Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 2)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sr-tray")
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.snappy) { keyboard = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.snappy) { keyboard = false }
        }
    }

    /// The bar's places without Home, in the bar's order (`AccessPolicy.bar`).
    private var tabs: [Router.Tab] {
        AccessPolicy.bar(for: access.current).filter { $0 != .today }
    }

    private func item(title: String, symbol: String, on: Bool, badge: Int, identifier: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: on ? .semibold : .medium))
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(SR.Text.label(10))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Capsule().fill(SR.error))
                                .offset(x: 10, y: -5)
                        }
                    }
                Text(title)
                    .font(SR.Text.label(10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? SR.accentDeep : SR.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                if on { Capsule().fill(SR.accentDeep.opacity(0.14)) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge)" : title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }

    /// Another place: its tab, as it was left. The place already showing:
    /// back to its first page, as a tab bar does.
    private func choose(_ tab: Router.Tab) {
        SRHaptic.select()
        if router.tab == tab {
            router.popToRoot(tab)
        } else {
            router.tab = tab
        }
    }

    /// More, pushed onto the tab that is showing — one bar, one Back. On
    /// More already, nothing.
    private func openMore() {
        guard place != .more else { return }
        SRHaptic.tap()
        router.openHub()
    }

    private func title(_ tab: Router.Tab) -> String {
        switch tab {
        case .family: return "Family"
        case .games: return "Games"
        case .chat: return "Chat"
        case .health: return "Health"
        case .today: return "Home"
        case .news: return "News"
        case .flows: return "Flows"
        }
    }

    private func symbol(_ tab: Router.Tab) -> String {
        switch tab {
        case .family: return "person.2.wave.2"
        case .games: return "gamecontroller"
        case .chat: return "bubble.left.and.bubble.right"
        case .health: return "heart.text.square"
        case .today: return "house"
        case .news: return "newspaper"
        case .flows: return "point.3.connected.trianglepath.dotted"
        }
    }
}

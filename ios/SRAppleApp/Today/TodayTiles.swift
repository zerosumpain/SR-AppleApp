import SwiftUI

/// The four doors under the family — Ask and Readiness, then Daydream and
/// Play — each one unit tall and two across, two to a row.
///
/// Squares, not rows, because each is a door rather than a reading — one tap
/// and you are where the thing is. Which of them a person gets follows what
/// they may use; the grid fills left to right, so a member with only Health
/// and Games still gets a tidy pair.
enum TodayTile: String, CaseIterable, Identifiable {
    case ask, health, daydream, games

    var id: String { rawValue }

    /// In reading order. Ask needs chat over the site credential; Daydream is
    /// the owner's loop; Health is everyone's (the Move ring is this phone's).
    static func kinds(access: AppAccess, sitePaired: Bool) -> [TodayTile] {
        allCases.filter { tile in
            switch tile {
            case .ask: return access.chat && sitePaired
            case .health: return true
            case .daydream: return access.owner && sitePaired
            case .games: return AccessPolicy.allows(.games, access)
            }
        }
    }
}

/// The grid itself: rows of two, one column at the accessibility text sizes,
/// where a square would clip its own words.
///
/// Plain stacks at a fixed (scaled) height, not a lazy grid of aspect-ratio
/// cells: four tiles never need laziness, and a lazy grid re-negotiating
/// square cells whenever the safe area moved (the tab bar shrinking on
/// scroll, even with Today behind another tab) was work for nothing.
struct TodayTileGrid<Tile: View>: View {
    let tiles: [TodayTile]
    @ViewBuilder let tile: (TodayTile) -> Tile
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Half the width: a 390pt screen less the gutters and the gap leaves
    /// tiles ~169pt wide, so one unit down to two across is ~82pt.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 82

    var body: some View {
        let folded = typeSize.isAccessibilitySize
        let rows: [[TodayTile]] = folded
            ? tiles.map { [$0] }
            : stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0..<min($0 + 2, tiles.count)]) }
        VStack(spacing: SR.cardGap) {
            ForEach(rows, id: \.first) { row in
                HStack(spacing: SR.cardGap) {
                    ForEach(row) { kind in
                        tile(kind)
                            .frame(maxWidth: .infinity)
                            .frame(height: folded ? nil : side)
                            .frame(minHeight: folded ? 72 : nil)
                    }
                    // A lone tile keeps its half, not the whole row.
                    if !folded && row.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
    }
}

/// A paper tile, one unit tall and two across: the mark, the name, a
/// chevron. Nothing else — the counts ride on the mark's badge, and the
/// reasons are one tap away (John asked for them this spare, 2026-10-05).
struct TodayTileCard<Visual: View>: View {
    let title: String
    @ViewBuilder let visual: () -> Visual

    var body: some View {
        HStack(spacing: 12) {
            visual()
            Text(title)
                .font(SR.Text.title(17))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SR.inkGhost)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, SR.cardPadding - 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .srGlassCard(.paper, interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
    }
}

/// The one filled control on Today: jkai and the family's messages, behind
/// one door. The chat mark and the words, centred — no microphone (John
/// asked for it this plain, 2026-10-05).
struct TodayAskTile: View {
    var body: some View {
        HStack(spacing: 10) {
            disc("bubble.left")
            Text("JkAi & Msgs")
                .font(SR.Text.title(17))
                .foregroundStyle(SR.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, SR.cardPadding - 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        // Deeper than the accent so the cream words hold 5:1 on it.
        .background(SR.accentDeep, in: RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
    }

    private func disc(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(SR.paper)
            .frame(width: 36, height: 36)
            .background(SR.paper.opacity(0.18), in: Circle())
            .accessibilityHidden(true)
    }
}

/// What the daydream loop noticed, as a door: how many notes wait for your
/// call, and the newest of them. The notes open in their own page, in More.
struct TodayDaydreamTile: View {
    @ObservedObject private var store = DaydreamStore.shared
    @ObservedObject private var feedback = NoticedFeedback.shared
    @ObservedObject private var commissions = CommissionStore.shared

    var body: some View {
        // The site's count when it has sent one (it counts every note, not
        // just the ones on this phone), moved by answers given here.
        let waiting = store.toDecide(feedback: feedback, commissions: commissions)
        let newest = store.notes.first { store.bucket(for: $0, feedback: feedback, commissions: commissions) == .decide }
        let state = waiting == 0 ? "all caught up" : "\(waiting) to decide"
        TodayTileCard(title: "Daydream") {
            TodayTileGlyph(symbol: "sparkles", tone: SR.accentInk, count: waiting)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daydream, \(state)" + ((newest ?? store.notes.first).map { ". \($0.title)" } ?? ""))
        .accessibilityAddTraits(.isButton)
        // Once a launch: the detailed read is what knows the true count.
        .task { if !store.loaded { await store.load() } }
    }
}

/// Invitations first, then a game in progress, then the shelf.
struct TodayGamesTile: View {
    @EnvironmentObject private var games: GamesStore

    var body: some View {
        let (title, subline) = lines
        TodayTileCard(title: "Play") {
            TodayTileGlyph(symbol: "gamecontroller.fill", tone: SR.accent, count: games.invites.count)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Play, \(title)" + (subline.map { ". \($0)" } ?? ""))
        .accessibilityAddTraits(.isButton)
        .task { if games.lobby == nil { await games.load() } }
    }

    private var lines: (String, String?) {
        if let invite = games.invites.first {
            let count = games.invites.count
            return (count == 1 ? "1 invitation" : "\(count) invitations",
                    "\(invite.hostName) · \(GameNames.title(invite.game))")
        }
        if let room = games.rooms.first {
            let count = games.rooms.count
            return (count == 1 ? "1 in progress" : "\(count) in progress", GameNames.title(room.game))
        }
        return ("Play together", "\(GameKind.allCases.count) quick games")
    }
}

/// A glyph on a soft disc of its own colour, with an optional count.
struct TodayTileGlyph: View {
    let symbol: String
    let tone: Color
    var count: Int = 0

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tone)
            .frame(width: 38, height: 38)
            .background(tone.opacity(0.14), in: Circle())
            .overlay(alignment: .topTrailing) {
                if count > 0 { TodayCountBadge(count: count, fill: tone).offset(x: 6, y: -4) }
            }
            .accessibilityHidden(true)
    }
}

/// A small filled count: the tile's new notes, the bell's unread.
struct TodayCountBadge: View {
    let count: Int
    var fill: Color = SR.accentDeep

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(SR.Text.label())
            .monospacedDigit()
            .foregroundStyle(SR.paper)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(fill, in: Capsule())
            .overlay(Capsule().stroke(SR.paper, lineWidth: 2))
            .fixedSize()
    }
}

// MARK: - The bell

/// The alert inbox, top right, made to be seen.
///
/// Filled and in the accent while anything is unread, with the count on it,
/// and every five seconds it rings — once, briefly — until the inbox is read.
/// Only while Today is in front, and not with Reduce Motion on: then the
/// colour and the count carry it alone.
struct TodayBell: View {
    let unread: Int
    /// Today is on screen and the app is in front. Off it, the bell stays
    /// still: nobody is there to see it, and a view that never settles keeps
    /// the app from ever going idle.
    var active = true
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rings = 0

    /// How long between rings.
    static let interval: Duration = .seconds(5)

    var body: some View {
        Button(action: action) {
            ringing(Image(systemName: unread > 0 ? "bell.fill" : "bell"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(unread > 0 ? SR.accentDeep : SR.ink)
                .frame(width: 44, height: 44)
                // Inside the 44-point frame, not hanging off its corner: on
                // iOS 26 a bar item sits in a glass capsule that CLIPS to its
                // bounds, and a badge lifted above them lost its top — the
                // number read as cut off.
                .overlay(alignment: .topTrailing) {
                    if unread > 0 { TodayCountBadge(count: unread).offset(x: -1, y: 3) }
                }
                .contentShape(Rectangle())
        }
        .accessibilityLabel(unread > 0 ? "Alerts, \(unread) unread" : "Alerts")
        .accessibilityIdentifier("today-bell")
        // Restarts whenever the inbox goes from read to unread and back.
        .task(id: unread > 0 && active && !reduceMotion) {
            guard unread > 0, active, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard !Task.isCancelled else { break }
                rings += 1
            }
        }
    }

    @ViewBuilder
    private func ringing(_ image: Image) -> some View {
        if #available(iOS 18.0, *) {
            image.symbolEffect(.wiggle, value: rings)
        } else {
            image.symbolEffect(.bounce, value: rings)
        }
    }
}

// MARK: - The urgent banner

extension TodayAlerts {
    /// The alert the banner across Today shows: the newest unread one at the
    /// loudest level, unless it was waved away here. Nothing quieter ever
    /// takes the banner — the bell is for those.
    static func urgent(in recent: [SiteAlert], dismissed: Set<String>) -> SiteAlert? {
        recent.first { $0.isAlert && !$0.read && !dismissed.contains($0.id) }
    }
}

/// An urgent alert, pinned under the bar until it is opened or dismissed.
struct TodayUrgentBanner: View {
    let alert: SiteAlert
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SR.errorOnDark)
                        .frame(width: 32, height: 32)
                        .background(SR.errorOnDark.opacity(0.2), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kicker)
                            .font(SR.Text.label())
                            .tracking(1.2)
                            .foregroundStyle(SR.errorOnDark)
                            .lineLimit(1)
                        Text(alert.title)
                            .font(SR.Text.title(15))
                            .foregroundStyle(SR.cream)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Urgent: \(alert.title)")
            .accessibilityHint("Opens the alert")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("today-urgent")

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SR.creamOnDark)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss urgent alert")
            .accessibilityIdentifier("today-urgent-dismiss")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .srGlass(.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// "URGENT · 2M AGO".
    private var kicker: String {
        let ago = shortAgo(alert.createdAt)
        return (ago.isEmpty ? "Urgent" : "Urgent · \(ago) ago").uppercased()
    }
}

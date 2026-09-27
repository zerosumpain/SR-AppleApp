import SwiftUI

/// The four squares under the family: Ask and Health, then Daydream and Games.
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

/// The grid itself. Two columns of squares; one column of rows at the
/// accessibility text sizes, where a square would clip its own words.
struct TodayTileGrid<Tile: View>: View {
    let tiles: [TodayTile]
    @ViewBuilder let tile: (TodayTile) -> Tile
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let folded = typeSize.isAccessibilitySize
        let columns = Array(repeating: GridItem(.flexible(), spacing: SR.cardGap), count: folded ? 1 : 2)
        LazyVGrid(columns: columns, spacing: SR.cardGap) {
            ForEach(tiles) { kind in
                tile(kind)
                    .frame(maxWidth: .infinity, minHeight: folded ? 120 : nil)
                    .aspectRatio(folded ? nil : 1, contentMode: .fit)
            }
        }
    }
}

/// A paper tile: something to look at top-left, a chevron top-right, and a
/// kicker, a title and one line at the foot.
struct TodayTileCard<Visual: View>: View {
    let kicker: String
    let title: String
    let subline: String?
    @ViewBuilder let visual: () -> Visual

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                visual()
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SR.inkGhost)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(kicker.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                Text(title)
                    .font(SR.Text.title(18))
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let subline {
                    Text(subline)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .srGlassCard(.paper, interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
    }
}

/// The one filled control on Today: a new thread with the keyboard up.
struct TodayAskTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                disc("bubble.left")
                Spacer(minLength: 4)
                disc("mic")
            }
            Spacer(minLength: 8)
            Text("Ask jkai\nanything")
                .font(SR.Text.title(22))
                .foregroundStyle(SR.paper)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Deeper than the accent so the cream words hold 5:1 on it.
        .background(SR.accentDeep, in: RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
    }

    private func disc(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(SR.paper)
            .frame(width: 44, height: 44)
            .background(SR.paper.opacity(0.18), in: Circle())
            .accessibilityHidden(true)
    }
}

/// A glyph on a soft disc of its own colour, with an optional count.
struct TodayTileGlyph: View {
    let symbol: String
    let tone: Color
    var count: Int = 0

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(tone)
            .frame(width: 44, height: 44)
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
                .overlay(alignment: .topTrailing) {
                    if unread > 0 { TodayCountBadge(count: unread).offset(x: 4, y: -2) }
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
                            .foregroundStyle(SR.paper)
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

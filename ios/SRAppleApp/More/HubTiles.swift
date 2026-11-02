import SwiftUI

// The More page's furniture: each door's picture (`HubArt`), the door itself
// at each of its sizes (`HubTile`), the grid that places them
// (`HubGridLayout`, from `HubLayout.pack`), and Sync now (`HubSyncButton`).

/// A door's colour and picture, by its id — the Games page's art, for what
/// the door opens. The colours are the reader's palette's feature hues, so a
/// door wears the same colour as its tile on Home, and a palette change
/// repaints the page.
enum HubArt {
    static func hue(_ id: String) -> SR.Hue {
        switch id {
        case "trips": return .trips
        case "news": return .news
        // Drive's blue: files, kept; it is the "Ask jkai" hue, which no door
        // here wears.
        case "drive": return .chat
        case "daydream": return .daydream
        case "wildmind": return .wildmind
        // Captures in the red of a recording light.
        case "captures": return .alerts
        case "steps": return .steps
        case "tasks": return .tasks
        case "backlog": return .backlog
        case "messages": return .messages
        case "landgrab": return .family
        case "games": return .games
        case "flows": return .flows
        // Tabs that can sit in More when the tray is full.
        case "chat": return .chat
        case "health": return .health
        case "family": return .family
        case "travel": return .move
        case "offline": return .health
        case "settings": return settings
        default: return .flows
        }
    }

    /// Settings is the one door with no feature of its own, so no feature's
    /// hue: a deep slate, the same under every palette, that sits quietly
    /// among the bright ones and still has a picture on it.
    static var settings: SR.Hue {
        SR.Hue(base: Color(hex: 0x2B2850), glow: Color(hex: 0x6C67A6), onFill: .white)
    }

    static func motif(_ id: String) -> GamesTileMotif {
        switch id {
        case "trips": return .map
        case "news": return .lines
        case "drive": return .blocks
        case "daydream": return .sparkles
        case "wildmind": return .hills
        case "captures": return .waveform
        case "steps": return .track
        case "tasks": return .checks
        case "backlog": return .cards
        case "messages": return .bubbles
        case "landgrab": return .hexes
        case "games": return .dice
        case "flows": return .nodes
        case "chat": return .bubbles
        case "health": return .rings
        case "family": return .map
        case "travel": return .arc
        // Play nearby: phones finding each other, in rings.
        case "offline": return .rings
        case "settings": return .sliders
        default: return .dots
        }
    }
}

/// A door: its picture edge to edge — the hue's gradient, a sheen, its motif
/// and its mark large and faint — with its mark again as a logo, its name,
/// and as much of its live line and purpose as its size has room for. A
/// count sits on it when something waits.
///
/// `size` is its place in the grid; nil is the one-column list the
/// accessibility text sizes get, where a door is as tall as its words.
struct HubTile: View {
    let entry: HubEntry
    let size: HubTileSize?
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The logo grows with the type, within what a cell can hold.
    @ScaledMetric(relativeTo: .headline) private var markScale: CGFloat = 1

    /// The Games tiles' corner, a little tighter on a one-cell door.
    private var corner: CGFloat { size == .small ? 20 : 26 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        // A grid cell fixes the door's height; a list row takes its words'.
        let maxHeight: CGFloat? = size == nil ? nil : .infinity
        Button {
            SRHaptic.tap()
            action()
        } label: {
            content
                .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .topLeading)
                .foregroundStyle(entry.hue.onFill)
                .background {
                    TileArtBackdrop(motif: entry.motif, hue: entry.hue, symbol: entry.icon, symbolSide: symbolSide)
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                .shadow(color: entry.hue.base.opacity(0.26), radius: size == .small ? 8 : 12, y: 5)
                .contentShape(shape)
        }
        .buttonStyle(SRPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint(entry.hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(entry.identifier ?? "more-\(entry.id)")
    }

    /// Everything the door says, for VoiceOver — the small doors show only a
    /// name, so the count and the live line are heard here.
    private var spoken: String {
        var parts = [entry.title]
        if let status = entry.status { parts.append(status) }
        if entry.count > 0, entry.status == nil { parts.append("\(entry.count) waiting") }
        return parts.joined(separator: ", ")
    }

    private var symbolSide: CGFloat {
        switch size {
        case .big: return 112
        case .wide, .banner: return 62
        case .tall: return 66
        case .small: return 46
        case nil: return 84
        }
    }

    @ViewBuilder
    private var content: some View {
        switch size {
        case .big: big
        case .wide, .banner: wide
        case .tall: tall
        case .small: small
        case nil: row
        }
    }

    // MARK: The sizes

    /// 2x2: the logo and the count, then the name large, the live line and
    /// what it is for while the type leaves room.
    private var big: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                mark(44)
                Spacer(minLength: 4)
                countBadge
            }
            Spacer(minLength: 4)
            Text(entry.title)
                .font(SR.Text.display(22))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            statusLine(13)
            if typeSize < .xLarge {
                Text(entry.hint)
                    .font(SR.Text.secondary(12))
                    .opacity(0.88)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }

    /// 2x1: the logo beside the name and the live line.
    private var wide: some View {
        HStack(alignment: .center, spacing: 10) {
            mark(36)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(SR.Text.display(17))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                statusLine(12)
            }
            Spacer(minLength: 0)
            countBadge
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }

    /// 1x2: the logo at the top, the name and live line at the foot.
    private var tall: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 2) {
                mark(34)
                Spacer(minLength: 0)
                countBadge
            }
            Spacer(minLength: 2)
            Text(entry.title)
                .font(SR.Text.display(16))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if let status = entry.status {
                Text(status)
                    .font(SR.Text.title(12))
                    .opacity(0.92)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(11)
    }

    /// 1x1: the logo and the name; the rest is VoiceOver's.
    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 2) {
                mark(28)
                Spacer(minLength: 0)
                countBadge
            }
            Spacer(minLength: 2)
            Text(entry.title)
                .font(SR.Text.title(13))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding(9)
    }

    /// The accessibility sizes' row: everything, at the height it needs.
    private var row: some View {
        HStack(alignment: .top, spacing: 14) {
            mark(44)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(SR.Text.display(20))
                    .fixedSize(horizontal: false, vertical: true)
                if let status = entry.status {
                    Text(status)
                        .font(SR.Text.title(14))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(entry.hint)
                    .font(SR.Text.secondary(14))
                    .opacity(0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            countBadge
        }
        .padding(16)
    }

    // MARK: Pieces

    /// The door's logo: its mark in its own colour on a disc of the light it
    /// is drawn in, as the Games tiles carry theirs.
    private func mark(_ side: CGFloat) -> some View {
        // Grows with the type, but never past half again its size: a cell
        // is only so big.
        let scaled = side * min(max(markScale, 1), size == nil ? 1.6 : 1.25)
        return Image(systemName: entry.icon)
            .font(.system(size: scaled * 0.44, weight: .bold))
            .foregroundStyle(entry.hue.base)
            .frame(width: scaled, height: scaled)
            .background(RoundedRectangle(cornerRadius: scaled * 0.3, style: .continuous).fill(entry.hue.onFill.opacity(0.94)))
            .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var countBadge: some View {
        if entry.count > 0 {
            Text("\(entry.count)")
                .font(SR.Text.label(12))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 22, minHeight: 22)
                .background(Capsule().fill(SR.error))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                .accessibilityHidden(true)
        }
    }

    /// The live line, or a blank one so names sit level across a row.
    private func statusLine(_ points: CGFloat) -> some View {
        Text(entry.status ?? " ")
            .font(SR.Text.title(points))
            .opacity(entry.status == nil ? 0 : 0.92)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Places the doors where `HubLayout.pack` put them: four columns of square
/// cells across whatever width the page has, the gaps between them the same
/// both ways. Its subviews come in the order of `placements`.
struct HubGridLayout: Layout {
    let placements: [HubPlacement]
    var spacing: CGFloat

    private func cell(_ width: CGFloat) -> CGFloat {
        let columns = CGFloat(HubLayout.columns)
        return max(0, (width - spacing * (columns - 1)) / columns)
    }

    private func span(_ count: Int, cell: CGFloat) -> CGFloat {
        CGFloat(count) * cell + CGFloat(max(0, count - 1)) * spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 360, height: 0)).width
        let rows = HubLayout.rows(placements)
        return CGSize(width: width, height: span(rows, cell: cell(width)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let unit = cell(bounds.width)
        for (index, subview) in subviews.enumerated() {
            guard index < placements.count else { break }
            let p = placements[index]
            let origin = CGPoint(x: bounds.minX + CGFloat(p.column) * (unit + spacing),
                                 y: bounds.minY + CGFloat(p.row) * (unit + spacing))
            subview.place(at: origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: span(p.size.columns, cell: unit), height: span(p.size.rows, cell: unit)))
        }
    }
}

/// Sync now, at the top right of the More page and nowhere else on it: a
/// hot capsule unlike any door, so the one thing on the page that acts
/// rather than opens looks it. The arrows turn while a sync runs — still
/// under Reduce Motion, where the words say it — and VoiceOver hears when
/// the phone last synced and what the last sync said.
struct HubSyncButton: View {
    let syncing: Bool
    let lastUpload: Date?
    /// The companion's last word: VoiceOver's hint.
    let message: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var glyph: CGFloat = 13

    /// The palette's three loudest hues, so it is vivid in every palette.
    private var fill: LinearGradient {
        LinearGradient(colors: [SR.Hue.alerts.glow, SR.Hue.family.base, SR.Hue.games.base],
                       startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        Button {
            SRHaptic.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                arrows
                Text(syncing ? "Syncing…" : "Sync now")
                    .font(SR.Text.label(13))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(minHeight: 32)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
            .shadow(color: SR.Hue.family.base.opacity(0.45), radius: 7, y: 3)
            // The capsule is drawn smaller than the 44-point target it sits in.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(syncing ? "Syncing" : "Sync now")
        .accessibilityValue(lastUpload.map { "Last synced \($0.formatted(date: .omitted, time: .shortened))" } ?? "Not synced yet")
        .accessibilityHint(message)
        .accessibilityIdentifier("more-sync")
    }

    /// The arrows, turning on the display's clock while a sync runs; the
    /// timeline is paused, and draws nothing new, the rest of the time.
    private var arrows: some View {
        let spinning = syncing && !reduceMotion
        return TimelineView(.animation(minimumInterval: nil, paused: !spinning)) { context in
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: glyph, weight: .bold))
                .rotationEffect(.degrees(spinning ? Self.angle(context.date) : 0))
        }
        .accessibilityHidden(true)
    }

    /// One turn every 1.2 seconds.
    static func angle(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360
    }
}

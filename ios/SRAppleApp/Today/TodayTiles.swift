import SwiftUI

/// Today's small furniture that outlived it: the tile card and glyph More
/// draws its places with, the bell, and the urgent banner. Home's own tiles
/// are in `Home/`.

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

/// A glyph on a soft disc of its own colour, with an optional count.
struct TodayTileGlyph: View {
    let symbol: String
    let tone: Color
    var count: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: symbol)
            // One hop when the count changes — a new invitation, a new note
            // — and never on its own. Still under Reduce Motion.
            .symbolEffect(.bounce, value: reduceMotion ? 0 : count)
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
            .srNumeric(Double(count))
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
        // The whole card answers, not just its button: a tap on the glass's
        // edge used to fall through to whatever card was scrolled beneath the
        // banner (Family opened instead of the alert). The ✕ still dismisses.
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: open)
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

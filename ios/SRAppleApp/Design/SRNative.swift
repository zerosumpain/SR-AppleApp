import SwiftUI
import UIKit

/// The native half of the design system.
///
/// `SRComponents.swift` is a port of the WEBSITE: a bar with a URL path in it, a
/// lettered kicker, a headline hand-broken into lines, a three-line mono strip at
/// the foot of every scroll. On a 390pt screen that furniture is most of the
/// first screenful, and none of it is what an iPhone reader is looking for —
/// they want the threads, the figures, the story.
///
/// So the page chrome stops being the app's chrome. Navigation goes to
/// `NavigationStack` and the system bar; lists go to `List`; search goes to
/// `.searchable`; refresh goes to `.refreshable`. What stays is everything that
/// makes it Strange Ramblings and not a template: the cream ground, the ink
/// type, the burnt-orange accent, the four faces, zero radius, hairline rules.
///
/// The rule for anything new: **the SR design system supplies the paint, UIKit
/// supplies the furniture.** A component here exists only where the system has
/// no equivalent (a figure tile, a hairline card) or where the system's default
/// would be the wrong colour.

// MARK: - System chrome, painted

enum SRChrome {
    /// Teach UIKit the palette once, at launch.
    ///
    /// SwiftUI's `.toolbarBackground` covers a bar at a time and says nothing
    /// about the large-title face, the back-chevron tint or the tab bar's
    /// unselected item. The appearance proxy covers all of it in one place, and
    /// a screen that forgets to style itself still comes out right — which is
    /// the opposite of the failure mode `SRShell` had, where a screen that
    /// forgot came out as a system-grey page in the middle of a cream app.
    static func install() {
        let paper = UIColor(SR.paper)
        let ink = UIColor(SR.ink)
        let accent = UIColor(SR.accent)

        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = paper
        // A hairline, not the system's 0.33pt grey — the app has exactly one
        // rule weight and this is it.
        bar.shadowColor = UIColor(SR.line)
        bar.titleTextAttributes = [
            .foregroundColor: ink,
            .font: scaled(SR.Face.bodyBold, 17, .headline),
        ]
        bar.largeTitleTextAttributes = [
            .foregroundColor: ink,
            // Archivo Black at 30 with the tracking the site gives a headline.
            // -0.6 is the same value `SectionHead` uses; a display face set
            // loose reads as a different typeface.
            .font: scaled(SR.Face.display, 30, .largeTitle),
            .kern: -0.6,
        ]
        let back = UIBarButtonItemAppearance(style: .plain)
        back.normal.titleTextAttributes = [
            .foregroundColor: accent,
            .font: scaled(SR.Face.monoMedium, 13, .caption1),
        ]
        bar.backButtonAppearance = back

        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactScrollEdgeAppearance = bar
        UINavigationBar.appearance().tintColor = accent

        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = paper
        tabs.shadowColor = UIColor(SR.line)
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.selected.iconColor = accent
            item.selected.titleTextAttributes = [
                .foregroundColor: accent,
                .font: scaled(SR.Face.monoMedium, 10, .caption2),
            ]
            item.normal.iconColor = UIColor(SR.inkMuted)
            item.normal.titleTextAttributes = [
                .foregroundColor: UIColor(SR.inkMuted),
                .font: scaled(SR.Face.mono, 10, .caption2),
            ]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs

        // A cream app with a white grouped-table ground looks like two apps.
        UITableView.appearance().backgroundColor = paper
        UICollectionView.appearance().backgroundColor = paper
        UITextField.appearance().tintColor = accent
        UITextView.appearance().tintColor = accent
    }

    /// A bundled face at a size that still answers the reader's text setting.
    ///
    /// `UIFont(name:size:)` is fixed, exactly as `Font.custom(name:size:)` is.
    /// `UIFontMetrics` is the UIKit half of `relativeTo:`. A missing face falls
    /// back to the system font rather than crashing — `Font.custom` already
    /// fails that way silently, and `SiteTests.testEveryNamedFontIsRegistered`
    /// is what actually catches a face that did not ship.
    static func scaled(_ name: String, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont {
        let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .semibold) // dynamic-type-exempt: the base the metric scales, below
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }
}

// MARK: - Haptics

/// The feedback an iPhone gives and a web page cannot.
///
/// Deliberately thin. Haptics that fire on everything stop meaning anything, so
/// there are four: a tap landed, a selection moved, something succeeded, and
/// something failed. Nothing fires on a scroll or on an arriving token — a
/// buzzing pocket during a streamed answer is a bug, not a flourish.
enum SRHaptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func ok() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func bad() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// MARK: - Surfaces

/// A hairline card. Zero radius, no shadow, the opaque surface token.
///
/// `--card-bg` is 7% ink and reads as transparent the moment it sits over
/// anything, which on a phone it always does; `--surface-elevated` is the
/// opaque one and the reason this does not take a tint parameter.
struct SRCard<Content: View>: View {
    var accented: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(SR.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SR.surface)
            .overlay(alignment: .leading) {
                if accented { Rectangle().fill(SR.accent).frame(width: 3) }
            }
            .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
    }
}

/// A mono eyebrow above a group. The list-section header, in the app's voice.
struct SRSectionLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(SR.Text.label())
                .tracking(1.4)
                .foregroundStyle(SR.inkMuted)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing.uppercased())
                    .font(SR.Text.mono())
                    .tracking(1)
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// One figure, said once.
///
/// From /health: a number with no frame is a number nobody can act on, so a
/// tile carries the unit and the window as well as the value. `caption` is the
/// window — "today", "7-day mean" — and it is not optional by accident.
struct SRStatTile: View {
    let value: String
    var unit: String? = nil
    let label: String
    var caption: String? = nil
    /// A movement worth colouring. `nil` means "no opinion", which is the
    /// honest default for most figures.
    var trend: Trend? = nil
    var onTap: (() -> Void)? = nil

    enum Trend { case up, down, flat }

    var body: some View {
        let tile = VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(SR.Text.figure())
                    .foregroundStyle(SR.ink)
                    // No `minimumScaleFactor`. It was the escape hatch that made
                    // the grid look fine at every text size by quietly undoing
                    // the reader's setting — the tile folds to one column now
                    // instead, and the number stays the size it was asked to be.
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(SR.Text.mono(13))
                        .foregroundStyle(SR.inkMuted)
                }
                if let trend {
                    Image(systemName: trend == .up ? "arrow.up.right" : trend == .down ? "arrow.down.right" : "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(trend == .flat ? SR.inkGhost : SR.accentInk)
                }
            }

            if let caption {
                Text(caption)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SR.cardPadding)
        .frame(minHeight: 96, alignment: .topLeading)
        .background(SR.surface)
        .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value) \(unit ?? "")\(caption.map { ", \($0)" } ?? "")")

        if let onTap {
            Button { SRHaptic.tap(); onTap() } label: { tile }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
        } else {
            tile
        }
    }
}

/// Two tiles across — one, once the reader has asked for larger text.
///
/// Three columns is 118pt a tile and a four-digit step count stops fitting, so
/// the phone's grid is two. At an accessibility text size two stops fitting for
/// the same reason, and the wrong answer is to shrink the number back down:
/// somebody who asked for bigger text getting smaller text is the whole failure
/// in one gesture. So the grid folds instead.
struct SRTileGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: columns, spacing: SR.cardGap) { content }
    }

    private var columns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: SR.cardGap)]
            : [GridItem(.flexible(), spacing: SR.cardGap), GridItem(.flexible(), spacing: SR.cardGap)]
    }
}

/// A row in a list: title, optional sub-line, optional trailing figure.
///
/// Written rather than taken from `List`'s defaults because the defaults set
/// SF Pro, and one system-font row in a page of DM Sans is the thing a reader
/// sees before they see anything else.
struct SRRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tone: Color? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tone ?? SR.accent)
                    .frame(width: 24, alignment: .center)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, SR.rowPadding)
        .frame(minHeight: SR.tapTarget)
        .contentShape(Rectangle())
    }
}

extension SRRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, icon: String? = nil, tone: Color? = nil) {
        self.init(title: title, subtitle: subtitle, icon: icon, tone: tone) { EmptyView() }
    }
}

/// The empty state, said once and the same way everywhere.
///
/// `ContentUnavailableView` is the system's and it is the right shape; it is
/// wrapped only so the face and the accent come from here.
struct SREmpty: View {
    let title: String
    let icon: String
    var message: String? = nil
    /// Two parameters, not one `(label:run:)` tuple.
    ///
    /// The tuple is what crashed the compiler. Coercing an inferred
    /// `(label: String, run: () -> Task<(), Never>)` into
    /// `(label: String, run: () -> Void)` took swift-frontend down with a stack
    /// dump rather than a diagnostic — no file, no line, just "Command
    /// SwiftCompile failed". Two plain parameters never form that tuple, so a
    /// future call site written inline gets an ordinary error at worst.
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(SR.inkMuted)
            Text(title)
                .font(SR.Text.display(19))
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action, let actionLabel {
                Button { SRHaptic.tap(); action() } label: {
                    Text(actionLabel.uppercased())
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.paper)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(SR.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// The one-line "something happened" strip, above the safe area.
struct SRBanner: View {
    let text: String
    var tone: Color = SR.ink

    var body: some View {
        Text(text)
            .font(SR.Text.secondary(14))
            .foregroundStyle(SR.paper)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 11)
            .background(tone)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Modifiers

extension View {
    /// Paper under a scroll view, edge to edge.
    ///
    /// `.background(SR.paper)` alone leaves the system's grouped-list ground
    /// showing through a `List`, which is the two-apps look again.
    func srPaper() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(SR.paper.ignoresSafeArea())
    }

    /// A plain list row with no system insets or separators of its own.
    func srPlainRow() -> some View {
        self
            .listRowBackground(SR.paper)
            .listRowInsets(EdgeInsets(top: 0, leading: SR.gutter, bottom: 0, trailing: SR.gutter))
            .listRowSeparatorTint(SR.divider)
    }
}

import SwiftUI

/// How far the day's drawer is pulled up over its map.
enum TripDrawerDetent: CaseIterable {
    /// The glance: where you are and what's next, over a big map.
    case peek
    /// Half and half.
    case half
    /// The whole plan; a strip of map left showing above it.
    case full

    /// Tapping the grabber walks up, then back down to the glance.
    var next: TripDrawerDetent {
        switch self {
        case .peek: return .half
        case .half: return .full
        case .full: return .peek
        }
    }
}

/// The map-led day's sheet (red team 2026-10-15, proposal A): drawn over the
/// map, not a system sheet, so the day's own pushes (a stop) and sheets
/// (Edit plan) still come from the day screen. Drag it by its header; what
/// is under the header scrolls on its own at every height.
struct TripDrawer<Header: View, Content: View>: View {
    @Binding var detent: TripDrawerDetent
    /// The height it settles at, for the map to frame around. Written when
    /// it settles, not on every frame of a drag.
    @Binding var covered: CGFloat
    /// The glance's height: room for the header and a line more.
    var peek: CGFloat = 230
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    /// How far the finger has pulled from where it settled. It goes back to 0
    /// with the same spring as the new height (a drag ended or cancelled),
    /// not in one un-animated jump before the spring starts.
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.35, dampingFraction: 0.86))) private var drag: CGFloat = 0
    /// The header's own height, measured: the glance is never shorter, so
    /// a tall "where you are" never spills out of the drawer.
    @State private var headerHeight: CGFloat = 0

    /// The drawer's top corners: the one radius that is neither a card's
    /// (`SR.Glass.radius`) nor an inner row's (`SR.Glass.innerRadius`) —
    /// a sheet's edge over a full-bleed map (trip design rules, 2026-10-21).
    private static var radius: CGFloat { 22 }
    private static var spring: Animation { .spring(response: 0.35, dampingFraction: 0.86) }

    var body: some View {
        GeometryReader { geo in
            let stops = heights(geo.size.height)
            let settled = stops[detent] ?? peek
            let full = stops[.full] ?? geo.size.height
            let height = min(max(settled - drag, stops[.peek] ?? peek), full)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    grabber
                    header
                }
                .padding(.horizontal, SR.gutter)
                .padding(.bottom, 10)
                .background {
                    GeometryReader { g in Color.clear.preference(key: TripDrawerHeaderHeight.self, value: g.size.height) }
                }
                .contentShape(Rectangle())
                .gesture(
                    // Measured on the screen, not on the header: the header
                    // moves with the finger, so in its own space every frame's
                    // move shifted the next reading — the drawer shook.
                    DragGesture(minimumDistance: 6, coordinateSpace: .global)
                        .updating($drag) { value, state, _ in state = value.translation.height }
                        .onEnded { value in
                            let landing = settled - value.predictedEndTranslation.height
                            let nearest = TripDrawerDetent.allCases.min {
                                abs((stops[$0] ?? 0) - landing) < abs((stops[$1] ?? 0) - landing)
                            } ?? detent
                            withAnimation(Self.spring) { detent = nearest }
                        }
                )
                Divider().opacity(0.5)
                ScrollView {
                    content
                        .padding(.horizontal, SR.gutter)
                        .padding(.top, 12)
                        // The part below the screen at this height, so the
                        // end of the plan can still be scrolled into view.
                        .padding(.bottom, 24 + full - settled)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            // Always laid out at full height and slid, never resized: a drag
            // moves one layer instead of laying the whole plan out again on
            // every frame.
            .frame(height: full, alignment: .top)
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: Self.radius, topTrailingRadius: Self.radius, style: .continuous)
                    .fill(SR.paper)
                    .shadow(color: .black.opacity(0.16), radius: 14, y: -2)
                    .ignoresSafeArea(edges: .bottom)
            }
            .offset(y: full - height)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .onAppear { covered = settled }
            .onChange(of: detent) { _, _ in covered = stops[detent] ?? peek }
            .onChange(of: geo.size.height) { _, total in covered = heights(total)[detent] ?? peek }
            .onChange(of: headerHeight) { _, _ in covered = heights(geo.size.height)[detent] ?? peek }
            .onPreferenceChange(TripDrawerHeaderHeight.self) { headerHeight = $0 }
        }
        .accessibilityIdentifier("trip-drawer")
    }

    private func heights(_ total: CGFloat) -> [TripDrawerDetent: CGFloat] {
        // At least the header and a sliver of what is under it; at most 60 %.
        let peekHeight = min(max(peek, headerHeight + 24), total * 0.6)
        return [
            .peek: peekHeight,
            .half: max(peekHeight + 60, total * 0.56),
            .full: max(peekHeight + 120, total - 72),
        ]
    }

    /// The handle, and a button for anyone who can't drag.
    private var grabber: some View {
        Button {
            SRHaptic.select()
            withAnimation(Self.spring) { detent = detent.next }
        } label: {
            Capsule()
                .fill(SR.inkMuted.opacity(0.45))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(detent == .full ? "Show the map" : "Show more of the plan")
        .accessibilityIdentifier("trip-drawer-grabber")
    }
}

/// The drawer header's measured height.
private struct TripDrawerHeaderHeight: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

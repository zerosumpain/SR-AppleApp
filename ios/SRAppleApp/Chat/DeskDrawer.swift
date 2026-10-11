import SwiftUI

// MARK: - The desk drawer
//
// On the web, /jkai is a chat column beside a desk: each answer's evidence as a
// page of blocks. A phone has no room beside anything, so the desk is a drawer
// from the right edge, over the thread: the toolbar's Desk button or a swipe in
// from the right edge opens it, a drag back or a tap on the scrim closes it.
// The left edge stays the system's — that is swipe-back.

/// The drawer's furniture: scrim, sheet, drag to close. Content is the desk.
struct DeskDrawer<Content: View>: View {
    @Binding var isOpen: Bool
    @ViewBuilder var content: Content

    @GestureState private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.88, 420)
            ZStack(alignment: .trailing) {
                if isOpen {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                        .transition(.opacity)
                        .accessibilityLabel("Close desk")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { close() }

                    content
                        .frame(width: width)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(SR.surface.ignoresSafeArea(edges: .bottom))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(SR.line).frame(width: 0.75).ignoresSafeArea(edges: .bottom)
                        }
                        .offset(x: max(0, drag))
                        // Simultaneous, so the desk's own scroll view keeps
                        // its vertical drags; only a sideways one moves the sheet.
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 14)
                                .updating($drag) { value, state, _ in
                                    // Only a sideways drag moves the sheet; a
                                    // vertical one belongs to the scroll view.
                                    if abs(value.translation.width) > abs(value.translation.height) {
                                        state = value.translation.width
                                    }
                                }
                                .onEnded { value in
                                    let sideways = abs(value.translation.width) > abs(value.translation.height)
                                    if sideways && (value.translation.width > width * 0.3 || value.predictedEndTranslation.width > width * 0.6) {
                                        close()
                                    }
                                }
                        )
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                        .accessibilityElement(children: .contain)
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { close() }
                        .accessibilityIdentifier("desk-drawer")
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .trailing)
        }
        .allowsHitTesting(isOpen)
    }

    private func close() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.28)) { isOpen = false }
    }
}

/// What the drawer shows: the head, a pager across the thread's pages, and the
/// page's blocks — or Today, when the thread has put nothing on the desk yet.
struct DeskView: View {
    let turns: [DeskTurn]
    let close: () -> Void

    /// Into `DeskPager.pages(of:)`; `nil` is Today.
    @State private var index: Int?
    /// The turn asked about has no page; an earlier one is on show.
    @State private var held: Bool
    @StateObject private var today = TodayStore()

    init(turns: [DeskTurn], focus: String?, close: @escaping () -> Void) {
        self.turns = turns
        self.close = close
        let choice = DeskPager.choose(turns: turns, focus: focus)
        _index = State(initialValue: choice.index)
        _held = State(initialValue: choice.held)
    }

    private var pages: [DeskTurn] { DeskPager.pages(of: turns) }

    private var page: PanelPage {
        if let index, index < pages.count, let page = pages[index].page { return page }
        return DeskToday.page(from: today.payload)
    }

    private var showingToday: Bool { index == nil || (index ?? 0) >= pages.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            Divider().overlay(SR.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if held && !showingToday {
                        quietLine
                    }
                    ForEach(page.sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            if !section.label.isEmpty {
                                Text(section.label.uppercased())
                                    .font(SR.Text.label(12))
                                    .tracking(1.6)
                                    .foregroundStyle(SR.inkMuted)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(section.blocks) { block in
                                DeskBlockView(block: block)
                            }
                        }
                    }
                    if showingToday && today.loading && today.payload == nil {
                        ProgressView().tint(SR.accent).frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                // A new page starts at its top, not where the last one was left.
                .id(showingToday ? "today" : "page-\(index ?? -1)")
            }
            .scrollIndicators(.hidden)
        }
        .task(id: showingToday) {
            if showingToday && today.payload == nil { await today.load() }
        }
    }

    // MARK: Head

    private var head: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                kicker
                Spacer(minLength: 6)
                pager
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SR.ink)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close desk")
                .accessibilityIdentifier("desk-close")
            }
            if !page.head.title.isEmpty {
                Text(page.head.title.uppercased())
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if let standfirst = page.head.standfirst, !standfirst.isEmpty {
                Text(standfirst)
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var kicker: some View {
        let words = page.head.context.filter { !$0.isEmpty }
        let lead = Text((page.head.kicker.isEmpty ? "Desk" : page.head.kicker).uppercased())
            .foregroundStyle(SR.accent)
        let rest = Text(words.isEmpty ? "" : " · " + words.joined(separator: " · ").uppercased())
            .foregroundStyle(SR.inkMuted)
        return (lead + rest)
            .font(SR.Text.label(12))
            .tracking(1.4)
            .lineLimit(2)
    }

    /// ◂ n/m ▸ across the thread's pages, with Today before the first.
    @ViewBuilder
    private var pager: some View {
        if !pages.isEmpty {
            HStack(spacing: 2) {
                pagerButton("chevron.left", label: "Previous page", enabled: !showingToday) {
                    guard let index else { return }
                    move(to: index == 0 ? nil : index - 1)
                }
                Text(showingToday ? "Today" : "\((index ?? 0) + 1)/\(pages.count)")
                    .font(SR.Text.mono(12))
                    .foregroundStyle(SR.inkSecondary)
                    .monospacedDigit()
                    .accessibilityLabel(showingToday ? "Today" : "Page \((index ?? 0) + 1) of \(pages.count)")
                    .accessibilityIdentifier("desk-pager")
                pagerButton("chevron.right", label: "Next page", enabled: showingToday || (index ?? 0) < pages.count - 1) {
                    move(to: showingToday ? 0 : (index ?? 0) + 1)
                }
            }
        }
    }

    private func pagerButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? SR.ink : SR.inkGhost)
                .frame(width: 32, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func move(to target: Int?) {
        SRHaptic.select()
        index = target
        held = false
    }

    private var quietLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle").font(.system(size: 12))
            Text("Quiet turn · desk held")
                .font(SR.Text.label(12))
                .tracking(0.6)
            Spacer(minLength: 0)
        }
        .foregroundStyle(SR.inkMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SR.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .accessibilityLabel("Quiet turn. The desk is holding an earlier page.")
    }
}

// MARK: - The tool line under an answer

/// `● 4 tools · on the desk`, under an answer.
///
/// The web prints the run's steps as a tool lane; the phone folds them to one
/// line. A tap opens the desk at this turn (when it has a page); the chevron —
/// or a long press — unfolds the steps as before.
struct DeskToolLine: View {
    let steps: [ToolStep]
    let onDesk: Bool
    var openDesk: (() -> Void)?
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(steps.contains(where: \.failed) ? SR.error : SR.accent)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(SR.Text.label(12))
                    .tracking(0.4)
                    .foregroundStyle(onDesk ? SR.inkSecondary : SR.inkMuted)
                if onDesk {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SR.accent)
                }
                if !steps.isEmpty {
                    Button(action: toggle) {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SR.inkMuted)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
            .onTapGesture { primary() }
            .onLongPressGesture(minimumDuration: 0.4) {
                SRHaptic.select()
                toggle()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(onDesk ? "Opens the desk at this answer" : (open ? "Hides the steps" : "Shows the steps"))
            .accessibilityAction { primary() }
            .accessibilityAction(named: open ? "Hide steps" : "Show steps") { toggle() }
            .accessibilityIdentifier("chat-tool-line")

            if open && !steps.isEmpty { ToolStepList(steps: steps) }
        }
    }

    private var label: String {
        let tools = steps.count == 1 ? "1 tool" : "\(steps.count) tools"
        switch (steps.isEmpty, onDesk) {
        case (true, _): return "On the desk"
        case (false, true): return "\(tools) · on the desk"
        case (false, false): return tools
        }
    }

    private func primary() {
        if onDesk, let openDesk {
            SRHaptic.tap()
            openDesk()
        } else {
            toggle()
        }
    }

    private func toggle() {
        guard !steps.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.15)) { open.toggle() }
    }
}

/// Which assistant turns are on screen, for opening the desk on the one being
/// read. A reference type on purpose: it is written on every row appearing and
/// read only when the drawer opens, so it must not redraw the transcript.
final class DeskVisibility {
    var onScreen: Set<String> = []
}

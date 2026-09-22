import SwiftUI

/// The news desk.
///
/// The stream is built as a RANKED-MOVES LEDGER, which is the /health pattern
/// that fits it: a numeral, a column saying what the thing IS, then the content,
/// with the hairline between rows drawn as the container's own ground showing
/// through a 1px gap. A news row and a ranked move are the same shape — a
/// position, a provenance, a claim, and a reason it is where it is.
struct NewsScreen: View {
    @StateObject private var store = NewsStore()
    @State private var opened: NewsStory?

    var body: some View {
        SRShell(
            path: "/news",
            kicker: store.feed.map { "\($0.stories.count) stories" },
            footer: footerLines
        ) {
            SRSection {
                SectionHead(
                    kicker: sectionKicker,
                    title: ["The wire,", "ranked"],
                    strap: strap
                )
                viewPicker
            }

            SRSection(tinted: true, isLast: true) {
                if store.loading && store.stories.isEmpty {
                    loadingRow
                } else if store.stories.isEmpty {
                    emptyRow
                } else {
                    SRLedger {
                        ForEach(store.stories) { story in
                            NewsLedgerRow(
                                story: story,
                                saved: store.isSaved(story),
                                kept: store.isKept(story),
                                busy: store.busyKey == story.key,
                                onOpen: { opened = story },
                                onAction: { action in Task { await store.act(action, on: story) } }
                            )
                        }
                    }
                }
            }
        }
        .task { if store.feed == nil { await store.load() } }
        .refreshable { await store.load(force: true) }
        .overlay(alignment: .bottom) {
            if let message = store.message {
                SRToast(text: message)
            }
        }
        .sheet(item: $opened) { story in
            NewsStoryScreen(story: story)
        }
    }

    private var sectionKicker: String {
        let anchors = store.feed?.anchorCount ?? 0
        return anchors > 0
            ? "A / \(store.view.label) · \(anchors) anchors"
            : "A / \(store.view.label)"
    }

    private var strap: String {
        switch store.view {
        case .forYou:
            let anchors = store.feed?.anchorCount ?? 0
            return anchors == 0
                ? "Nothing in the knowledge base to rank against yet, so this is the top wire in its own order."
                : "Ranked against \(anchors) things the knowledge base already holds. What did not correlate stays, below the fold."
        case .best:
            return "Ranked on heat rather than points. Raw scores are not comparable across wires, and one wire does not vote at all."
        case .favourites:
            return "Everything you saved, from the phone or from the desk. Same rows."
        case .new:
            return "Newest first, straight off the wires."
        case .top:
            return "The front pages, deduplicated. A story on two wires keeps the second sighting as evidence rather than dropping it."
        }
    }

    private var footerLines: [String] {
        guard let feed = store.feed else { return [] }
        var lines = ["Strange Ramblings · the desk"]
        let wires = feed.sources.map { "\($0.label) \($0.count)" }.joined(separator: " · ")
        lines.append(wires)
        if let updated = isoDate(feed.updatedAt) {
            let stamp = updated.formatted(date: .omitted, time: .shortened)
            lines.append(feed.cached ? "Cached · \(stamp)" : "Fetched · \(stamp)")
        }
        return lines
    }

    private var viewPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(NewsView.allCases) { item in
                    let current = item == store.view
                    Button {
                        Task { await store.select(item) }
                    } label: {
                        Text(item.label.uppercased())
                            .font(SR.monoMedium(12))
                            .tracking(1.2)
                            .foregroundStyle(current ? SR.paper : SR.inkSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(current ? SR.ink : Color.clear)
                            .overlay(Rectangle().strokeBorder(SR.line, lineWidth: current ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("news-view-\(item.rawValue)")
                    .accessibilityAddTraits(current ? [.isSelected] : [])
                }
            }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView().tint(SR.accent)
            Text("Reading the wires…").font(SR.body(14)).foregroundStyle(SR.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.view == .favourites ? "Nothing saved yet." : "No stories.")
                .font(SR.bodyMedium(16))
                .foregroundStyle(SR.ink)
            Text(store.view == .favourites
                 ? "Save a story from any view and it lands here, and on the desk."
                 : "Pull down to fetch the wires again.")
                .font(SR.body(14))
                .foregroundStyle(SR.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
    }
}

/// One row of the ledger.
///
/// `grid-template-columns: 56px minmax(0, 1.5fr) …` on the web. On a phone the
/// numeral column narrows to 34pt and the rest stacks, but the shape holds: a
/// display-font numeral in accent, then what the thing IS, then the claim.
struct NewsLedgerRow: View {
    let story: NewsStory
    let saved: Bool
    let kept: Bool
    let busy: Bool
    let onOpen: () -> Void
    let onAction: (NewsAction) -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(story.rank)")
                    .font(SR.display(24))
                    .foregroundStyle(story.read ? SR.ink.opacity(0.3) : SR.accent)
                    .frame(width: 34, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    // The eyebrow's two halves STACK rather than sitting side by
                    // side. "TOOL" fits on one line and "FIELD STUDY №6" wraps to
                    // two, and then rows in the same list start their titles at
                    // different heights — the grid's alignment must not be
                    // decided by the length of a label.
                    HStack(spacing: 8) {
                        Text(story.sourceLabel.uppercased())
                            .font(SR.monoMedium(12))
                            .tracking(1)
                            .foregroundStyle(SR.inkSecondary)
                        Text(shortAgo(story.publishedAt))
                            .font(SR.mono(12))
                            .foregroundStyle(SR.inkGhost)
                        if story.score > 0 {
                            Text("\(story.score)▲")
                                .font(SR.mono(12))
                                .foregroundStyle(SR.inkGhost)
                        }
                        if story.commentCount > 0 {
                            Text("\(story.commentCount)◇")
                                .font(SR.mono(12))
                                .foregroundStyle(SR.inkGhost)
                        }
                    }

                    Text(story.title)
                        .font(SR.bodyMedium(16))
                        .foregroundStyle(story.read ? SR.inkMuted : SR.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(story.domain)
                        .font(SR.mono(12))
                        .foregroundStyle(SR.inkGhost)
                        .lineLimit(1)

                    if let correlation = story.correlation {
                        CorrelationNote(correlation: correlation)
                    }

                    if !story.alsoOn.isEmpty {
                        Text("ALSO ON \(story.alsoOn.map(\.sourceLabel).joined(separator: ", ").uppercased())")
                            .font(SR.mono(12))
                            .tracking(0.8)
                            .foregroundStyle(SR.accentInk)
                    }

                    HStack(spacing: 10) {
                        if saved { SRPill(text: "Saved", tone: SR.accent) }
                        if kept { SRPill(text: "In graph", tone: SR.good) }
                        if busy { ProgressView().scaleEffect(0.6).tint(SR.accent) }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SR.paper)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("news-row-\(story.key)")
        .accessibilityLabel("\(story.title), \(story.sourceLabel)")
        // The four row actions. A swipe would be invisible; a context menu is
        // the one iOS affordance that can carry four verbs without spending a
        // column of the ledger on them.
        .contextMenu {
            ForEach([NewsAction.favourite, .graph, .note, .research], id: \.rawValue) { action in
                Button {
                    onAction(action)
                } label: {
                    Label(action == .favourite && saved ? "Remove from saved" : action.label,
                          systemImage: action.icon)
                }
            }
        }
    }
}

/// Why a row surfaced. The explaining sentence goes in BODY font, not mono —
/// the tripwire ledger's rule, because a sentence set in a label face reads as
/// a label and stops being read.
struct CorrelationNote: View {
    let correlation: NewsCorrelation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(correlation.names.joined(separator: " · ").uppercased())
                .font(SR.monoMedium(12))
                .tracking(1)
                .foregroundStyle(SR.accentInk)
            Text(correlation.why)
                .font(SR.body(14))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let evidence = correlation.evidence, evidence.notes > 0 {
                Text("\(evidence.notes) note\(evidence.notes == 1 ? "" : "s") already")
                    .font(SR.mono(12))
                    .foregroundStyle(SR.inkGhost)
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Rectangle().fill(SR.accentInk.opacity(0.35)).frame(width: 2)
        }
    }
}

/// A transient message. Ink, because it is chrome.
struct SRToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SR.body(14))
            .foregroundStyle(SR.paper)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SR.ink)
            .padding(.horizontal, SR.gutter)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

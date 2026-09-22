import SwiftUI

/// The news desk.
///
/// The row is still the RANKED-MOVES LEDGER — a numeral, a provenance, a claim
/// and a reason it is where it is — because a news row and a ranked move really
/// are the same shape. What went is the page around it: a masthead with "THE
/// WIRE, / RANKED" set across two lines, a standfirst explaining the current
/// view, and a three-line mono footer naming every wire and its count. On a
/// phone that is most of a screenful before the first headline.
///
/// The standfirst survives as one caption line under the view chips, because it
/// is the only place that says what `for you` is ranking against; the rest is
/// now the navigation bar's job.
struct NewsScreen: View {
    @StateObject private var store = NewsStore()

    var body: some View {
        List {
            Section {
                viewPicker.srPlainRow().padding(.vertical, 4).listRowSeparator(.hidden)
                Text(strap)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .srPlainRow()
                    .padding(.bottom, 8)
                    .listRowSeparator(.hidden)
            }

            Section {
                ForEach(store.stories) { story in
                    NavigationLink(value: story) {
                        NewsLedgerRow(
                            story: story,
                            saved: store.isSaved(story),
                            kept: store.isKept(story),
                            busy: store.busyKey == story.key,
                            onAction: { action in Task { await store.act(action, on: story) } }
                        )
                    }
                    .srPlainRow()
                }
            }
        }
        .listStyle(.plain)
        .srPaper()
        .navigationTitle("News")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: NewsStory.self) { NewsStoryScreen(story: $0) }
        .task { if store.feed == nil { await store.load() } }
        .refreshable { await store.load(force: true) }
        .overlay {
            if store.loading && store.stories.isEmpty {
                ProgressView().tint(SR.accent)
            } else if store.stories.isEmpty && !store.loading {
                SREmpty(
                    title: store.view == .favourites ? "Nothing saved yet" : "No stories",
                    icon: store.view == .favourites ? "bookmark" : "newspaper",
                    message: store.view == .favourites
                        ? "Save a story from any view and it lands here, and on the desk."
                        : "Pull down to fetch the wires again."
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let feed = store.feed, let updated = isoDate(feed.updatedAt) {
                    Text((feed.cached ? "Cached " : "") + updated.formatted(date: .omitted, time: .shortened))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRBanner(text: message) }
        }
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
            return "The front pages, deduplicated. A story on two wires keeps the second sighting as evidence."
        }
    }

    /// The five views, as chips that scroll.
    ///
    /// Not a `Picker(.segmented)`: five segments on a 390pt screen gives each
    /// one 66 points, into which "Favourites" does not go, and the system
    /// truncates rather than wrapping. Chips keep every label legible and let
    /// the row scroll.
    private var viewPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NewsView.allCases) { item in
                    let current = item == store.view
                    Button {
                        SRHaptic.select()
                        Task { await store.select(item) }
                    } label: {
                        Text(item.label.uppercased())
                            .font(SR.Text.label())
                            .tracking(1.2)
                            .foregroundStyle(current ? SR.paper : SR.inkSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: 38)
                            .background(current ? SR.ink : Color.clear)
                            .overlay(Rectangle().strokeBorder(SR.line, lineWidth: current ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("news-view-\(item.rawValue)")
                    .accessibilityAddTraits(current ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
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
    let onAction: (NewsAction) -> Void

    var body: some View {
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
                            .foregroundStyle(SR.inkMuted)
                        if story.score > 0 {
                            Text("\(story.score)▲")
                                .font(SR.mono(12))
                                .foregroundStyle(SR.inkMuted)
                        }
                        if story.commentCount > 0 {
                            Text("\(story.commentCount)◇")
                                .font(SR.mono(12))
                                .foregroundStyle(SR.inkMuted)
                        }
                    }

                    Text(story.title)
                        .font(SR.bodyMedium(16))
                        .foregroundStyle(story.read ? SR.inkMuted : SR.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(story.domain)
                        .font(SR.mono(12))
                        .foregroundStyle(SR.inkMuted)
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
                    .foregroundStyle(SR.inkMuted)
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

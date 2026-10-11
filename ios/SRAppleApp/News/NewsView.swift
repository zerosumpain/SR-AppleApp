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
    @ObservedObject private var access = AccessStore.shared

    var body: some View {
        // A scroll of cards rather than a `List`: a NavigationLink inside a list
        // row earns a disclosure chevron, and beside a lifted card it floats in
        // the gutter pointing at nothing.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                viewPicker
                // The strap is the page talking about itself, so it is written
                // in the margin's hand rather than set as a label.
                Text(strap)
                    .font(SR.Text.marginalia(16))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SR.gutter + 4)
                    .padding(.bottom, 4)

                ForEach(store.stories) { story in
                    NavigationLink(value: story) {
                        NewsLedgerRow(
                            story: story,
                            saved: store.isSaved(story),
                            kept: store.isKept(story),
                            busy: store.busyKey == story.key,
                            actions: AccessPolicy.newsActions(can: store.feed?.can, access: access.current),
                            onAction: { action in Task { await store.act(action, on: story) } }
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, SR.gutter)
                }
            }
            .padding(.bottom, 28)
        }
        .srGround(.wire)
        .navigationTitle("News")
        // Inline, not large. A large title renders BLANK on this OS with this
        // appearance proxy — the bar lays out at full height and paints no text.
        // Verified in CI screenshots; inline titles in the same build draw in
        // Inter Display correctly. A compact bar also gives a list more of the
        // screen, which on a phone is the thing actually being asked for.
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.feed == nil { await store.load() } }
        .srRefreshable { await store.load(force: true) }
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
            ToolbarItem(placement: .principal) { SRBarMark() }
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
    /// The five views as index tabs: card stock in a hand-drawn box, the
    /// current one filled in the deep orange the prominent button uses. Square
    /// cornered, as card is cut, rather than glass capsules.
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
                            .font(SR.Text.kicker())
                            .tracking(SR.Notes.kickerTracking)
                            .foregroundStyle(current ? SR.paper : SR.inkSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: 40)
                            .background(current ? SR.accentDeep : SR.Notes.card)
                            .overlay {
                                if !current {
                                    SRInkBox(seed: seedFor(item.label))
                                        .stroke(SR.inkSecondary.opacity(0.7), style: .ink(1.2))
                                        .accessibilityHidden(true)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("news-view-\(item.rawValue)")
                    .accessibilityAddTraits(current ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }
}

/// A story as a row of the blog's contents page, on its own index card.
///
/// The phone version of `ContentsRows`: the wire and the time on the first
/// rule in the writing orange, a dotted leader running to the story's place in
/// the ranking, then the headline in Inter ExtraBold and the reason it is here
/// in Fraunces. The rank is the row's number, not decoration — the leader is
/// what ties it to the line it belongs to.
struct NewsLedgerRow: View {
    let story: NewsStory
    let saved: Bool
    let kept: Bool
    let busy: Bool
    /// Only the verbs this reader may use — a member without research is
    /// never offered "Commission research", rather than offered it and refused.
    let actions: [NewsAction]
    let onAction: (NewsAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // One line whatever the wire is called: the stamp line truncates
            // before it wraps, so every title in the list starts at the same
            // height and the leader always has the line to run along.
            HStack(alignment: .center, spacing: 10) {
                Text("\(story.sourceLabel) · \(shortAgo(story.publishedAt))".uppercased())
                    .font(SR.Text.kicker())
                    .tracking(SR.Notes.kickerTracking)
                    .foregroundStyle(story.read ? SR.inkMuted : SR.Notes.pen)
                    .lineLimit(1)
                    .layoutPriority(1)
                SRDottedLeader()
                    .frame(minWidth: 12)
                Text("\(story.rank)")
                    .font(SR.Text.display(20))
                    .tracking(-20 * 0.02)
                    .monospacedDigit()
                    .foregroundStyle(story.read ? SR.inkGhost : SR.Notes.pen)
                    .layoutPriority(1)
            }

            Text(story.title)
                .font(SR.Text.display(19))
                .tracking(-19 * 0.02)
                .foregroundStyle(story.read ? SR.inkMuted : SR.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(meta)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)

            if let correlation = story.correlation {
                CorrelationNote(correlation: correlation)
            }

            if !story.alsoOn.isEmpty {
                Text("ALSO ON \(story.alsoOn.map(\.sourceLabel).joined(separator: ", ").uppercased())")
                    .font(SR.Text.kicker())
                    .tracking(SR.Notes.kickerTracking)
                    .foregroundStyle(SR.accentInk)
            }

            if saved || kept || busy {
                HStack(spacing: 10) {
                    if saved { SRPill(text: "Saved", tone: SR.Notes.pen) }
                    if kept { SRPill(text: "In graph", tone: SR.good) }
                    if busy { ProgressView().scaleEffect(0.6).tint(SR.accent) }
                }
                .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Every story is on card. A read one keeps its card and lets its ink
        // fade, which is how a page you have been through looks — the old
        // "sink into the glass" has no paper equivalent that still reads.
        .srGlassCard(.paper, interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        .accessibilityIdentifier("news-row-\(story.key)")
        .accessibilityLabel("\(story.title), \(story.sourceLabel)")
        // The four row actions. A swipe would be invisible; a context menu is
        // the one iOS affordance that can carry four verbs without spending a
        // column of the ledger on them.
        .contextMenu {
            ForEach(actions, id: \.rawValue) { action in
                Button {
                    onAction(action)
                } label: {
                    Label(action == .favourite && saved ? "Remove from saved" : action.label,
                          systemImage: action.icon)
                }
            }
        }
    }

    /// The domain, then the wire's own counts when it gave any.
    private var meta: String {
        var parts = [story.domain]
        if story.score > 0 { parts.append("\(story.score)▲") }
        if story.commentCount > 0 { parts.append("\(story.commentCount)◇") }
        return parts.joined(separator: " · ")
    }
}

/// Why a row surfaced. The explaining sentence goes in BODY font, not mono —
/// the tripwire ledger's rule, because a sentence set in a label face reads as
/// a label and stops being read.
struct CorrelationNote: View {
    let correlation: NewsCorrelation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The names it matched are the knowledge base's tags, so each gets
            // its pencil dot: the same name is the same colour on every row.
            PencilledNames(names: correlation.names)
            Text(correlation.why)
                .font(SR.Text.serif(16))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let evidence = correlation.evidence, evidence.notes > 0 {
                Text("\(evidence.notes) note\(evidence.notes == 1 ? "" : "s") already")
                    .font(SR.Text.marginalia(15))
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(.leading, 12)
        // The blog's sidenote on a phone: a slip with a 3pt petrol bar.
        .overlay(alignment: .leading) {
            Rectangle().fill(SR.accentInk.opacity(0.6)).frame(width: 3)
        }
    }
}

/// The knowledge-base names a row matched, each with its pencil dot.
///
/// A plain wrapping run would need a flow layout for a handful of short
/// words; one line that truncates keeps the slip to the height of a rule, and
/// VoiceOver still reads every name from the label.
private struct PencilledNames: View {
    let names: [String]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(names.prefix(3).enumerated()), id: \.offset) { _, name in
                HStack(spacing: 7) {
                    SRPencilDot(word: name)
                    Text(name.uppercased())
                        .font(SR.Text.kicker())
                        .tracking(SR.Notes.kickerTracking)
                        .foregroundStyle(SR.accentInk)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(names.joined(separator: ", "))
    }
}

/// A transient message, on a sticky slip like `SRBanner`: the note is the same
/// warm paper at night, so its ink is resolved in the light palette.
struct SRToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SR.Text.marginalia(16))
            .foregroundStyle(SR.Notes.stickyInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: [SR.Notes.stickyTop, SR.Notes.stickyBottom],
                               startPoint: UnitPoint(x: 0.33, y: 0.03),
                               endPoint: UnitPoint(x: 0.67, y: 0.97)),
                in: RoundedRectangle(cornerRadius: 2, style: .continuous)
            )
            .shadow(color: Color(hex: SR.Fixed.ink, alpha: 0.22), radius: 7, x: 0, y: 6)
            .environment(\.colorScheme, .light)
            .rotationEffect(.degrees(-1))
            .padding(.horizontal, SR.gutter)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

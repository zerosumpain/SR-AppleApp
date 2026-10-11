import SwiftUI
import UIKit

/// One story, read in the app.
///
/// Opening this IS the read event — the server records it on the fetch, the same
/// way the desk records on navigation, so there is no second call for the phone
/// to forget to make.
struct NewsStoryScreen: View {
    let story: NewsStory
    @StateObject private var store = StoryStore()
    @Environment(\.dismiss) private var dismiss
    @State private var acting = false
    @ObservedObject private var access = AccessStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
            SRSection {
                // The blog post's margin on a phone: the date stamp sits on its
                // own rules above the title, tilted as a stamp is.
                if let stamp = stamp {
                    SRDateStamp(text: stamp.date, sub: stamp.time, tilt: -3, seed: seedFor(story.title))
                        .padding(.leading, 4)
                        .padding(.bottom, 18)
                }
                SectionHead(
                    kicker: "A / \(story.sourceLabel) · \(shortAgo(story.publishedAt)) ago",
                    title: titleLines,
                    strap: story.domain
                )
                meta
            }

            if let correlation = story.correlation {
                SRSection(tinted: true) {
                    SRLabel(text: "Why this surfaced")
                        .padding(.bottom, 12)
                    CorrelationNote(correlation: correlation)
                }
            }

            SRSection(isLast: store.article?.mode == "external") {
                articleBody(for: store.article)
            }

            if !story.alsoOn.isEmpty {
                SRSection(tinted: true, isLast: true) {
                    SRLabel(text: "Also carried by")
                        .padding(.bottom, 12)
                    ForEach(story.alsoOn) { also in
                        Link(destination: URL(string: also.discussionUrl) ?? SiteClient.defaultOrigin) {
                            // A receipt line: the wire, a dotted leader, its counts.
                            HStack(alignment: .center, spacing: 8) {
                                Text(also.sourceLabel)
                                    .font(SR.bodyMedium(15))
                                    .foregroundStyle(SR.accentInk)
                                    .layoutPriority(1)
                                SRDottedLeader()
                                    .frame(minWidth: 12)
                                Text("\(also.score)▲ \(also.commentCount)◇")
                                    .font(SR.mono(12))
                                    .foregroundStyle(SR.inkMuted)
                                    .layoutPriority(1)
                            }
                            .padding(.vertical, 9)
                        }
                    }
                }
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .srPaper()
        .navigationTitle(story.sourceLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: URL(string: story.url.isEmpty ? story.discussionUrl : story.url) ?? SiteClient.defaultOrigin) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share this story")
            }
        }
        .task { await store.load(source: story.source, id: story.storyId) }
    }

    /// Fold the headline at a sensible measure rather than letting the phone
    /// decide. `SectionHead` takes lines because the break is a decision.
    private var titleLines: [String] {
        let words = story.title.split(separator: " ")
        guard words.count > 4 else { return [story.title] }
        var lines: [String] = []
        var current = ""
        for word in words {
            if current.count + word.count + 1 > 22 && !current.isEmpty {
                lines.append(current)
                current = String(word)
            } else {
                current = current.isEmpty ? String(word) : "\(current) \(word)"
            }
        }
        if !current.isEmpty { lines.append(current) }
        // Three lines of Inter Display at 30pt is most of a phone screen.
        return Array(lines.prefix(3))
    }

    /// The publication date for the stamp: "11 Oct" over "SUN 09:30", in
    /// en-GB order whatever the phone's region, because the stamp is copy.
    private var stamp: (date: String, time: String)? {
        guard let published = isoDate(story.publishedAt) else { return nil }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_GB")
        day.dateFormat = "d MMM"
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_GB")
        time.dateFormat = "EEE HH:mm"
        return (day.string(from: published), time.string(from: published))
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if story.score > 0 {
                    Figure(value: "\(story.score)", label: "Points")
                }
                if story.commentCount > 0 {
                    Figure(value: "\(story.commentCount)", label: "Comments")
                }
                Figure(value: String(format: "%.2f", story.heat), label: "Heat")
            }

            HStack(spacing: 10) {
                SRButton(title: "Open article", filled: true) {
                    open(store.article?.finalUrl ?? story.url)
                }
                SRButton(title: "Discussion") {
                    open(story.discussionUrl)
                }
            }

            // The row's verbs as icons on discs of card stock with the
            // card's hairline — not glass, and not looped: a loop is kept
            // for the figure that matters.
            HStack(spacing: 10) {
                ForEach(AccessPolicy.newsActions(can: store.article?.can, access: access.current), id: \.rawValue) { action in
                    Button {
                        SRHaptic.tap()
                        Task { await act(action) }
                    } label: {
                        Image(systemName: action.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(SR.inkSecondary)
                            .frame(width: 48, height: 48)
                            .background(SR.Notes.card, in: Circle())
                            .overlay { Circle().strokeBorder(SR.line, lineWidth: 1) }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(acting)
                    .opacity(acting ? 0.45 : 1)
                    .accessibilityLabel(action.label)
                }
            }
        }
    }

    @ViewBuilder
    private func articleBody(for article: NewsArticle?) -> some View {
        if store.loading {
            HStack(spacing: 10) {
                ProgressView().tint(SR.accent)
                Text("Fetching the article…").font(SR.Text.marginalia(16)).foregroundStyle(SR.inkMuted)
            }
        } else if let article {
            VStack(alignment: .leading, spacing: 16) {
                // The summary is the piece's lede, set as the blog sets one:
                // Fraunces italic in soft ink, no bar — the face is the mark.
                if !article.summary.isEmpty {
                    Text(article.summary)
                        .font(SR.Text.marginalia(19))
                        .lineSpacing(4)
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let message = article.message {
                    Text(message)
                        .font(SR.Text.marginalia(16))
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !article.content.isEmpty {
                    Text(article.content)
                        .font(SR.body(16))
                        .lineSpacing(6)
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if article.truncated {
                    Text("This is the opening of the article. Open it in full to keep reading.")
                        .font(SR.Text.marginalia(15))
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !article.content.isEmpty {
                    // The whole piece is here, so it ends as a post ends.
                    SREndMark(seed: seedFor(story.title) + 7)
                }
            }
        } else if let message = store.message {
            Text(message)
                .font(SR.body(14))
                .foregroundStyle(SR.error)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerLines: [String] {
        var lines = [story.domain]
        if let author = story.author, !author.isEmpty { lines.append("by \(author)") }
        if let published = isoDate(story.publishedAt) {
            lines.append(published.formatted(date: .abbreviated, time: .shortened))
        }
        return lines
    }

    private func open(_ raw: String) {
        guard let url = URL(string: raw), url.scheme == "https" || url.scheme == "http" else { return }
        UIApplication.shared.open(url)
    }

    private func act(_ action: NewsAction) async {
        acting = true
        defer { acting = false }
        await store.act(action, on: story)
    }
}

/// A figure with a frame. A number on its own is a number with no frame, which
/// is the failure /health names for a header figure — so every one of these
/// carries the label that says what it measures.
///
/// Set as a reading in the notes: Inter ExtraBold, tabular and tight, over a
/// petrol label. Settings and the activity log pass "—" for a reading they do
/// not have; that is drawn as the notes' Fraunces dash, and VoiceOver hears
/// that there is no reading rather than a dash.
struct Figure: View {
    let value: String
    let label: String
    /// Ring the number in ink: the page's one reading that answers its
    /// title. The ring goes round the digits alone, as the site's InkRing
    /// does, never round the label under them.
    var ringed: Bool = false

    var body: some View {
        let missing = value == "—" || value == "\u{2014}"
        VStack(alignment: .leading, spacing: 3) {
            if missing {
                Text("\u{2014}")
                    .font(SR.Text.serif(18))
                    .foregroundStyle(SR.inkMuted)
            } else {
                Text(value)
                    .font(SR.Text.figure(22))
                    .tracking(-22 * 0.03)
                    .monospacedDigit()
                    .foregroundStyle(SR.ink)
                    .srInkRing(seed: 31, pad: 12, visible: ringed)
            }
            Text(label.uppercased())
                .font(SR.Text.kicker())
                .tracking(SR.Notes.kickerTracking)
                .foregroundStyle(SR.accentInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(missing ? "\(label), no reading yet" : "\(label), \(value)")
    }
}

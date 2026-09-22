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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
            SRSection {
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
                            HStack {
                                Text(also.sourceLabel)
                                    .font(SR.bodyMedium(15))
                                    .foregroundStyle(SR.accentInk)
                                Spacer()
                                Text("\(also.score)▲ \(also.commentCount)◇")
                                    .font(SR.mono(12))
                                    .foregroundStyle(SR.inkMuted)
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
        // Three lines of Archivo Black at 30pt is most of a phone screen.
        return Array(lines.prefix(3))
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

            HStack(spacing: 10) {
                ForEach([NewsAction.favourite, .graph, .note, .research], id: \.rawValue) { action in
                    Button {
                        Task { await act(action) }
                    } label: {
                        Image(systemName: action.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(SR.inkSecondary)
                            .frame(width: 44, height: 40)
                            .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(acting)
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
                Text("Fetching the article…").font(SR.body(14)).foregroundStyle(SR.inkMuted)
            }
        } else if let article {
            VStack(alignment: .leading, spacing: 16) {
                if !article.summary.isEmpty {
                    Text(article.summary)
                        .font(SR.bodyMedium(16))
                        .lineSpacing(5)
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(SR.accent).frame(width: 3)
                        }
                }

                if let message = article.message {
                    Text(message)
                        .font(SR.body(14))
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
                        .font(SR.mono(12))
                        .foregroundStyle(SR.inkMuted)
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
struct Figure: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(SR.display(22))
                .foregroundStyle(SR.ink)
            Text(label.uppercased())
                .font(SR.mono(12))
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

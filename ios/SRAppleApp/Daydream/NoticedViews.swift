import SwiftUI

/// One daydream note: what kind of thing it is, the title (a link to the note
/// on the site), the body, and the three answers.
///
/// The same row on Today (inside a card) and on the Health tab (a list row),
/// so every control is its own plain button — inside a `List` row a default
/// button makes the WHOLE row one tap target, and a thumbs-up would also open
/// the note.
struct NoticedNoteRow: View {
    let note: DaydreamNote
    @ObservedObject private var feedback = NoticedFeedback.shared
    @Environment(\.openURL) private var openURL
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            kicker

            Button {
                SRHaptic.tap()
                openURL(link)
            } label: {
                Text(note.title)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the note on the website")
            .accessibilityIdentifier("noticed-title")

            if !note.body.isEmpty {
                Text(note.body)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .lineSpacing(2)
                    .lineLimit(expanded ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(expanded ? "Shows less" : "Shows all of it")
            }

            actions
        }
        .padding(.vertical, 4)
    }

    // MARK: - Parts

    private var kicker: some View {
        HStack(spacing: 6) {
            Image(systemName: note.channel.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SR.accent)
                .accessibilityHidden(true)
            Text(note.outcome.label.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.accent)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(shortAgo(note.createdAt))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
        }
    }

    private var actions: some View {
        let current = feedback.verdict(for: note)
        return HStack(spacing: 6) {
            if current == .never {
                Image(systemName: "nosign")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SR.inkMuted)
                Text("Won't show this kind again")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            } else {
                verdictButton(.useful, icon: "hand.thumbsup", label: "Useful", id: "noticed-useful", current: current)
                verdictButton(.notUseful, icon: "hand.thumbsdown", label: "Not useful", id: "noticed-not-useful", current: current)
                Menu {
                    Button(role: .destructive) {
                        send(.never)
                    } label: {
                        Label("Never show this kind", systemImage: "nosign")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SR.inkMuted)
                        .frame(width: 40, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More")
                .accessibilityIdentifier("noticed-more")
            }
            Spacer(minLength: 4)
            if feedback.didFail(note) {
                Text("Not saved. Try again.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.error)
            } else if let status = statusLine(current) {
                Text(status)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
    }

    private func verdictButton(_ verdict: DaydreamVerdict, icon: String, label: String, id: String,
                               current: DaydreamVerdict?) -> some View {
        let on = current == verdict
        return Button {
            send(verdict)
        } label: {
            Image(systemName: on ? "\(icon).fill" : icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? SR.accent : SR.inkMuted)
                .frame(width: 40, height: 34)
                .background(on ? SR.accent.opacity(0.12) : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? AccessibilityTraits.isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func statusLine(_ verdict: DaydreamVerdict?) -> String? {
        switch verdict {
        case .useful: return "Useful"
        case .notUseful: return "Noted"
        case .never, .none: return nil
        }
    }

    private func send(_ verdict: DaydreamVerdict) {
        SRHaptic.tap()
        let note = self.note
        Task { await feedback.record(verdict, for: note) }
    }

    /// The note on the site. A path goes through the paired origin, as every
    /// other site link does; an absolute https address is taken as sent.
    private var link: URL {
        if note.url.hasPrefix("https://"), let absolute = URL(string: note.url) { return absolute }
        return SiteClient.shared.webURL(note.url)
    }
}

/// Today's "Noticed" card: the latest two notes, in one sheet.
struct NoticedCard: View {
    let notes: [DaydreamNote]

    var body: some View {
        let shown = Array(notes.prefix(2))
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Noticed")
                .padding(.horizontal, 4)
            SRCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, note in
                        NoticedNoteRow(note: note)
                            .padding(.vertical, 6)
                        if index < shown.count - 1 {
                            Rectangle().fill(SR.divider).frame(height: 1).padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }
}

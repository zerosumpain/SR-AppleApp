import SwiftUI

/// Welcome back and the Morning Bulletin (§9.9).
///
/// After more than a day of the town's time away the frame carries a few
/// welcome-back cards (`me.welcomeBack`: how long it was, how many live here,
/// the Bulletin's headlines, the mail); after every Regional Day the county
/// carries this town's Bulletin. They swipe as cards, every one can be read
/// aloud, and under them is what Bramble built and zoned today, each with
/// Undo, then the mail — Bramble's notes on what the standing orders did. Closing the sheet tells the server this phone has seen the
/// town as it is now (`seen`), so the next open replays only what is new.
struct WelcomeBackSheet: View {
    @ObservedObject var store: HometownsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page = 0
    /// The paged cards need a height; it grows with the reader's text size.
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 260

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    if cards.isEmpty {
                        SREmpty(title: store.say("bulletin.quiet"), icon: "newspaper",
                                message: store.level == .kid ? "Nothing new since you last looked." : "No news since your last visit.")
                    } else if typeSize.isAccessibilitySize {
                        // At the largest sizes no fixed height fits a card: every card, one under another.
                        VStack(spacing: SR.cardGap) {
                            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in cardView(card) }
                        }
                        .accessibilityIdentifier("hometowns-welcome-cards")
                    } else {
                        TabView(selection: $page) {
                            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                                cardView(card).tag(index).padding(.bottom, 28)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: cards.count > 1 ? .always : .never))
                        .indexViewStyle(.page(backgroundDisplayMode: .always))
                        .frame(height: cardHeight)
                        .accessibilityIdentifier("hometowns-welcome-cards")
                    }
                    // Bramble's builds and zoning of today, undoable from here too (decision 11).
                    HometownsDeputyUndoList(store: store)
                    mail
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 12)
            }
            .srGround(.warm)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("hometowns-welcome-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { store.seenWelcome() }
        .accessibilityIdentifier("hometowns-welcome")
    }

    private var title: String {
        (store.wire?.me?.welcomeBack.isEmpty ?? true) ? (store.level == .kid ? "Today's news" : "Bulletin") : store.say("bramble.welcome")
    }

    /// Welcome back first, then the Bulletin's headlines it does not already repeat.
    private var cards: [HometownsCard] {
        let welcome = store.wire?.me?.welcomeBack ?? []
        let bulletin = (store.wire?.county?.bulletin ?? []).filter { b in !welcome.contains(b) }
        return welcome + bulletin
    }

    private func cardView(_ card: HometownsCard) -> some View {
        let line = store.say(card.key, card.data)
        let news = card.key.hasPrefix("bulletin")
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HometownsMascot(advisor: card.key.hasPrefix("bulletin.money") ? "penny" : "bramble", size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(news ? (store.level == .kid ? "MORNING NEWS" : "MORNING BULLETIN") : "WELCOME BACK")
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(SR.accent)
                    if news {
                        // A masthead's double rule.
                        VStack(spacing: 2) {
                            Rectangle().fill(SR.ink.opacity(0.5)).frame(height: 1.5)
                            Rectangle().fill(SR.ink.opacity(0.5)).frame(height: 0.75)
                        }
                        .frame(maxWidth: 140)
                        .accessibilityHidden(true)
                    }
                }
            }
            Text(line)
                .font(SR.Text.display(21))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { store.readAloud(line) } label: { HometownsBigLabel(title: "Read aloud", icon: "speaker.wave.2.fill") }
                .srButton(.regular)
                .accessibilityIdentifier("hometowns-read-\(card.key)")
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
    }

    /// Bramble's notes and anything else in the mail, newest first.
    @ViewBuilder
    private var mail: some View {
        let inbox = (store.wire?.me?.inbox ?? []).reversed()
        if !inbox.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: store.level == .kid ? "Letters" : "Mail", trailing: "\(inbox.count)")
                VStack(spacing: 0) {
                    ForEach(Array(inbox.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(SR.divider) }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.kind.hasPrefix("deputy") ? "pawprint.fill" : "envelope.open.fill")
                                .foregroundStyle(SR.accent)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.copy.has(item.kind) ? store.say(item.kind, item.data) : HometownsCatalogue.humanised(item.kind))
                                    .font(SR.Text.bodyMedium(15))
                                    .foregroundStyle(SR.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Day \(item.day)")
                                    .font(SR.Text.mono())
                                    .foregroundStyle(SR.inkMuted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 4)
                .srGlassCard(.paper)
            }
            .accessibilityIdentifier("hometowns-mail-list")
        }
    }
}

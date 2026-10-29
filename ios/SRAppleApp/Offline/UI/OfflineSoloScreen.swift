import SwiftUI

/// One offline game, from the Games page (`SoloGameRef`): how to play it, and
/// Play — alone against the phone, or hosted for phones nearby.
///
/// The page leads with the game's badge and this phone's record, so the
/// first screenful says what it is, how you have done and where Play is;
/// the rules follow for anyone new to it.
///
/// The room it starts covers the screen as it does from Play offline, and
/// only while this page started it: a room opened elsewhere keeps its own
/// cover, so two pages never try to raise one each.
struct OfflineSoloScreen: View {
    let kind: String
    @ObservedObject private var session = OfflineSession.shared
    @ObservedObject private var results = OfflineResultStore.shared
    @State private var launched = false

    private var item: OfflineCatalogueItem? {
        OfflineCatalogue.item(OfflinePlayModes.offlineId(for: kind))
    }

    var body: some View {
        Group {
            if let item {
                page(item)
            } else {
                SREmpty(title: "Not an offline game yet", icon: "wifi.slash",
                        message: "This game needs the internet for now. Play nearby has games that do not.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .srPaper()
            }
        }
        .navigationTitle(item?.info.title ?? "Offline")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("offline-solo-screen")
        .fullScreenCover(isPresented: roomShown) {
            OfflineRoomScreen()
        }
    }

    private func page(_ item: OfflineCatalogueItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                OfflineGameHero(item: item, kicker: "Offline · \(item.info.playersLabel)")
                if let problem = session.problem, session.stage == .idle {
                    SRBanner(text: problem, tone: SR.error)
                        .onTapGesture { session.dismissProblem() }
                }
                record(item)
                OfflinePlayButtons(item: item) { start in
                    launched = true
                    start.run(session)
                }
                .disabled(session.inRoom)
                OfflineHowToCard(info: item.info)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
    }

    /// This phone's record at the game, or — before the first game — who
    /// it is against, so the space is never a blank.
    @ViewBuilder
    private func record(_ item: OfflineCatalogueItem) -> some View {
        if let tally = results.queue.tallies[item.id], tally.played > 0 {
            OfflineTallyStrip(tally: tally)
                .accessibilityIdentifier("offline-solo-best")
        } else {
            HStack(spacing: 12) {
                Image(systemName: recordSymbol(item))
                    .font(SR.Text.title(17))
                    .foregroundStyle(SR.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(SR.accent.opacity(0.14)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    // A game that needs other people is not "Just you".
                    Text(item.canPlaySolo ? item.opponentLine : "With phones nearby")
                        .font(SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                    Text("Your first score here becomes the one to beat.")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .combine)
        }
    }

    private func recordSymbol(_ item: OfflineCatalogueItem) -> String {
        if !item.canPlaySolo { return "person.2.fill" }
        return item.soloBots > 0 ? "cpu" : "person.fill"
    }

    private var roomShown: Binding<Bool> {
        Binding(
            get: { launched && session.inRoom },
            set: { shown in
                guard !shown else { return }
                launched = false
                if session.inRoom { session.leave() }
            }
        )
    }
}

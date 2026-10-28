import SwiftUI

/// One offline game, from the Games page (`SoloGameRef`): how to play it, and
/// Play — alone against the phone, or hosted for phones nearby.
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
                ScrollView {
                    VStack(alignment: .leading, spacing: SR.sectionGap) {
                        SRPageHeader(kicker: "Offline · \(item.info.playersLabel)", title: item.info.title,
                                     strap: item.info.blurb)
                        if let problem = session.problem, session.stage == .idle {
                            SRBanner(text: problem, tone: SR.error)
                                .onTapGesture { session.dismissProblem() }
                        }
                        if let tally = results.queue.tallies[item.id], tally.played > 0 {
                            bestCard(tally)
                        }
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

    private func bestCard(_ tally: OfflineTally) -> some View {
        SRCard {
            HStack(spacing: 16) {
                figure("\(tally.played)", label: "played")
                if tally.won > 0 { figure("\(tally.won)", label: "won") }
                if let best = tally.best { figure("\(best)", label: "best") }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-solo-best")
    }

    private func figure(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(SR.Text.figure(24))
                .foregroundStyle(SR.ink)
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
        }
    }
}

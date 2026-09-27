import SwiftUI

/// Daydream: everything the loop noticed lately, one card a note.
///
/// Opened from Today's tile and from More. Rated notes stay here — this is
/// the record, not the inbox — but only the unrated ones count as new on
/// the tile.
struct DaydreamScreen: View {
    @ObservedObject private var store = DaydreamStore.shared
    @ObservedObject private var feedback = NoticedFeedback.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SR.cardGap) {
                VStack(alignment: .leading, spacing: 6) {
                    SRSectionLabel(text: "Daydream", trailing: fresh > 0 ? "\(fresh) new" : nil)
                    Text("What jkai noticed while nobody was asking. Rate a note and the loop learns what is worth saying.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)

                if store.notes.isEmpty {
                    if store.loaded {
                        SREmpty(
                            title: "Nothing noticed yet",
                            icon: "sparkles",
                            message: "The loop writes a note or two every 45 minutes, when it has something worth saying. They land here."
                        )
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                } else {
                    ForEach(store.notes) { note in
                        SRCard {
                            NoticedNoteRow(note: note)
                        }
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("daydream-screen")
        .srGround(.quiet)
        .navigationTitle("Daydream")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SRBarMark() } }
        .task { await store.load() }
        .srRefreshable { await store.load() }
    }

    /// Unrated: what the tile calls new.
    private var fresh: Int { store.notes.filter { feedback.verdict(for: $0) == nil }.count }
}

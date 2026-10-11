import SwiftUI

/// The one question a newly paired phone is asked: does this person share
/// where they are with the household.
///
/// Off unless they say yes. "Not now", and swiping the sheet away, only record
/// that it was answered: they never send sharing off, so the question cannot
/// unshare somebody. The same switch stays in Settings.
struct SharingQuestionSheet: View {
    let answer: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    // A page of the notebook rather than a system sheet: the ruled paper, the
    // page head (kicker, Inter title), the pin in a loop drawn round it, and
    // the app's two buttons. The question is the only thing on the page.
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "location.circle")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(SR.accent)
                .frame(width: 46, height: 46)
                .overlay {
                    SRInkStroke(shape: SRInkLoop(seed: 29), tone: SR.accent, lineWidth: 1.8)
                }
                .accessibilityHidden(true)

            // The page head, a size down from `SRPageHeader`'s so the
            // question and both answers fit the half-height sheet.
            VStack(alignment: .leading, spacing: 6) {
                Text("FAMILY LOCATION")
                    .font(SR.Text.kicker())
                    .tracking(SR.Notes.kickerTracking)
                    .foregroundStyle(SR.Notes.pen)
                Text(SharingQuestion.title)
                    .font(SR.Text.hero(28))
                    .tracking(-28 * 0.035)
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(SharingQuestion.message)
                .font(SR.Text.body())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                SRHaptic.ok()
                answer(true)
                dismiss()
            } label: {
                SRButtonLabel(title: "Share", icon: "location.fill", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityLabel("Share")
            .accessibilityIdentifier("sharing-question-share")

            Button {
                SRHaptic.tap()
                answer(false)
                dismiss()
            } label: {
                SRButtonLabel(title: "Not now", fill: true)
            }
            .srButton(.regular, seed: 53)
            .controlSize(.large)
            .accessibilityLabel("Not now")
            .accessibilityIdentifier("sharing-question-not-now")
        }
        .padding(.horizontal, SR.gutter)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { SRNotebookPaper() }
        .presentationDetents([.medium, .large])
    }
}

extension View {
    /// Puts the household question to this phone when it is due.
    ///
    /// `onPairing`: false checks once, when the view first appears (an install
    /// that was paired before the question existed); true checks when pairing
    /// completes — on the first `/me` after it, not on `paired` flipping, so the
    /// server's own sharing answer is already in (see `Companion.refresh()`).
    /// Kept apart because the app-level view cannot present over the
    /// Settings sheet that pairing happens in — the screen doing the pairing
    /// has to ask.
    func srSharingQuestion(companion: Companion, onPairing: Bool) -> some View {
        modifier(SharingQuestionPresenter(companion: companion, onPairing: onPairing))
    }
}

private struct SharingQuestionPresenter: ViewModifier {
    @ObservedObject var companion: Companion
    let onPairing: Bool
    @State private var asking = false
    @State private var answered = false

    func body(content: Content) -> some View {
        content
            .task {
                guard !onPairing else { return }
                check()
            }
            .onChange(of: companion.profile?.id) { _, id in
                guard onPairing, id != nil else { return }
                check()
            }
            .sheet(isPresented: $asking, onDismiss: {
                // Swiped away: the same as "Not now" — recorded as answered,
                // and nothing sent.
                if !answered { Task { await companion.answerSharingQuestion(false) } }
            }) {
                SharingQuestionSheet { share in
                    answered = true
                    Task { await companion.answerSharingQuestion(share) }
                }
            }
    }

    private func check() {
        answered = false
        asking = companion.sharingQuestionDue()
    }
}

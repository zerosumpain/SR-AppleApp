import SwiftUI

/// The one question a newly paired phone is asked: does this person share
/// where they are with the household.
///
/// Off unless they say yes. "Not now", and swiping the sheet away, both leave
/// sharing off — and say so to the server, so a re-pair of an account that was
/// sharing before cannot carry on sharing without being asked. The same switch
/// stays in Settings.
struct SharingQuestionSheet: View {
    let answer: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "location.circle")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(SR.accent)
                .accessibilityHidden(true)

            Text(SharingQuestion.title)
                .font(SR.Text.display())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)

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
                Text("Share")
                    .font(SR.Text.bodyMedium())
                    .foregroundStyle(SR.paper)
                    .frame(maxWidth: .infinity, minHeight: SR.tapTarget)
                    .background(SR.accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sharing-question-share")

            Button {
                SRHaptic.tap()
                answer(false)
                dismiss()
            } label: {
                Text("Not now")
                    .font(SR.Text.bodyMedium())
                    .foregroundStyle(SR.ink)
                    .frame(maxWidth: .infinity, minHeight: SR.tapTarget)
                    .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sharing-question-not-now")
        }
        .padding(.horizontal, SR.gutter)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SR.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}

extension View {
    /// Puts the household question to this phone when it is due.
    ///
    /// `onPairing`: false checks once, when the view first appears (an install
    /// that was paired before the question existed); true checks when pairing
    /// completes. Kept apart because the app-level view cannot present over the
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
            .onChange(of: companion.paired) { _, paired in
                guard onPairing, paired else { return }
                check()
            }
            .sheet(isPresented: $asking, onDismiss: {
                // Swiped away: the default, which is off.
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

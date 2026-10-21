import SwiftUI

/// "Open the trip at this question": what a tapped question notification, an
/// `sr://trips/<id>/questions/<qid>` link or the Home tile asks of the
/// planning home, which is pushed as the trip (`TripRef`) and reads this to
/// scroll to the question.
///
/// A box rather than a field on `TripRef`: the trip's navigation value is the
/// planning screens' own, and a question to show is a one-off — taken once,
/// so going back to the trip later opens it at the top as usual.
@MainActor
final class TripQuestionFocus: ObservableObject {
    static let shared = TripQuestionFocus()

    /// Trip id → the question to bring into view.
    @Published private(set) var pending: [String: String] = [:]

    private init() {}

    func request(tripId: String, questionId: String) {
        pending[tripId] = questionId
    }

    /// The question waiting for this trip, once.
    func take(tripId: String) -> String? {
        pending.removeValue(forKey: tripId)
    }

    /// The scroll id a question card wears, so it can be scrolled to:
    /// `.id(TripQuestionFocus.anchor(question.id))`.
    nonisolated static func anchor(_ questionId: String) -> String { "trip-question-\(questionId)" }
}

extension View {
    /// On the planning home's scroll content: scrolls to the question a
    /// notification or link named, when the screen appears and whenever
    /// another is asked for while it is open. Each card needs
    /// `.id(TripQuestionFocus.anchor(question.id))`.
    func tripQuestionFocus(tripId: String, scroller: ScrollViewProxy) -> some View {
        modifier(TripQuestionFocusModifier(tripId: tripId, scroller: scroller))
    }
}

private struct TripQuestionFocusModifier: ViewModifier {
    let tripId: String
    let scroller: ScrollViewProxy
    @ObservedObject private var focus = TripQuestionFocus.shared

    func body(content: Content) -> some View {
        content
            .task { await show() }
            .onChange(of: focus.pending[tripId]) { _, wanted in
                guard wanted != nil else { return }
                Task { await show() }
            }
    }

    private func show() async {
        guard let question = focus.take(tripId: tripId) else { return }
        // A beat for the cards to be laid out: a push lands before its
        // content has measured, and an id not yet laid out scrolls nowhere.
        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(.snappy) { scroller.scrollTo(TripQuestionFocus.anchor(question), anchor: .top) }
    }
}

import SwiftUI

/// Maths Sprint on one phone: the clock, my sum and my score, a keypad, and
/// everyone's running total.
///
/// The keypad is built from the page's width (three keys a row, each at
/// least a tap target tall), so it fits a 375-point phone at any text size;
/// the sum itself scales down rather than wrap. What I have typed stays on
/// this phone until Enter — only the answer travels.
struct OfflineSprintView: View {
    let context: OfflineGameContext<OfflineSprintRules>
    @State private var typed = ""
    /// The sum an answer was sent for, so a double tap sends once; the next
    /// view (a new index) or a refusal clears it.
    @State private var sentFor: Int?

    private var view: OfflineSprintRules.PlayerView { context.view }
    private var mine: OfflineSprintRules.Mine? { view.me }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SRPageHeader(kicker: kicker, title: title)
                    .accessibilityIdentifier("offline-sprint-header")
                clockBar
                if let mine, view.phase == .playing || view.phase == .countdown {
                    problemCard(mine)
                    keypad
                }
                board
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .onChange(of: mine?.index) { _, _ in
            sentFor = nil
            typed = ""
            if let right = mine?.lastRight { if right { SRHaptic.tap() } else { SRHaptic.bad() } }
        }
        .onChange(of: view.phase) { _, new in
            if new == .playing { SRHaptic.select() }
            if new == .done { SRHaptic.ok() }
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil { sentFor = nil }
        }
    }

    // MARK: - Words

    private var kicker: String {
        guard let mine else { return "Maths Sprint · watching" }
        return "Maths Sprint · \(mine.right) right"
    }

    private var title: String {
        switch view.phase {
        case .countdown: return "Ready…"
        case .playing: return mine.map { "\($0.score) points" } ?? "Racing"
        case .done, .over:
            guard let top = view.board.first else { return "Time's up" }
            if view.board.count == 1 { return "\(top.score) points" }
            return top.id == context.me ? "You win" : "\(top.name) wins"
        }
    }

    // MARK: - The clock

    private var clockBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SR.accent)
                .accessibilityHidden(true)
            switch view.phase {
            case .countdown:
                Text("Starting in")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.inkSecondary)
                OfflineCountdown(clock: context.clock, until: view.startsAt, font: SR.Text.figure(24), tone: SR.accent)
            case .playing:
                Text("Time left")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.inkSecondary)
                OfflineCountdown(clock: context.clock, until: view.endsAt, font: SR.Text.figure(24))
            case .done, .over:
                Text("Time's up")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.inkSecondary)
            }
            Spacer(minLength: 8)
            if let streak = mine?.streak, streak >= 2 {
                SRGlassChip(text: "\(streak) in a row", icon: "flame.fill", tone: SR.accent)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 12)
        .srGlassCard(.paper)
    }

    // MARK: - My sum

    private func problemCard(_ mine: OfflineSprintRules.Mine) -> some View {
        VStack(spacing: 10) {
            Text(mine.problem.map { "\($0) =" } ?? "Get ready")
                .font(SR.Text.hero(40))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel(mine.problem.map { "What is \(spoken($0))?" } ?? "Get ready")
            Text(typed.isEmpty ? " " : typed)
                .font(SR.Text.figure(34))
                .foregroundStyle(SR.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(SR.surface))
                .accessibilityLabel(typed.isEmpty ? "No answer typed" : "Your answer, \(typed)")
                .accessibilityIdentifier("offline-sprint-typed")
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity)
        .srGlassCard(.paper)
    }

    /// "12 × 7" read as words: VoiceOver says "minus" for "−", not "dash".
    private func spoken(_ text: String) -> String {
        text.replacingOccurrences(of: "−", with: "minus")
            .replacingOccurrences(of: "×", with: "times")
            .replacingOccurrences(of: "÷", with: "divided by")
    }

    // MARK: - The keypad

    private var canAnswer: Bool {
        view.phase == .playing && mine?.problem != nil && sentFor == nil
    }

    private var keypad: some View {
        let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["⌫", "0", "Enter"]]
        return VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in keyButton(key) }
                }
            }
        }
        .disabled(!canAnswer)
        .opacity(canAnswer ? 1 : 0.5)
    }

    private func keyButton(_ key: String) -> some View {
        Button {
            press(key)
        } label: {
            Group {
                if key == "⌫" {
                    Image(systemName: "delete.left")
                        .font(.system(size: 20, weight: .semibold))
                } else {
                    Text(key)
                        .font(key == "Enter" ? SR.Text.title() : SR.Text.figure(26))
                }
            }
            .foregroundStyle(key == "Enter" ? SR.paper : SR.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                    .fill(key == "Enter" ? SR.accent : SR.surface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key == "⌫" ? "Delete" : key)
        .accessibilityIdentifier("offline-sprint-key-\(key == "⌫" ? "delete" : key.lowercased())")
    }

    private func press(_ key: String) {
        switch key {
        case "⌫":
            if !typed.isEmpty { typed.removeLast() }
            SRHaptic.select()
        case "Enter":
            guard let mine, let value = Int(typed), canAnswer else { return }
            sentFor = mine.index
            context.send(.answer(index: mine.index, value: value))
        default:
            guard typed.count < 5 else { return }
            typed += key
            SRHaptic.select()
        }
    }

    // MARK: - Everyone

    private var board: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: view.board.count == 1 ? "Score" : "Scores")
            VStack(spacing: 0) {
                ForEach(Array(view.board.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    HStack(spacing: 12) {
                        OfflineInitial(name: row.name, size: 28, tone: OfflineSeatColour.of(seat(of: row.id)))
                        Text(row.id == context.me ? "\(row.name) (you)" : row.name)
                            .font(SR.Text.title(16))
                            .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(row.right) right")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                        Text("\(row.score)")
                            .font(SR.Text.figure(22))
                            .foregroundStyle(SR.ink)
                    }
                    .frame(minHeight: SR.tapTarget)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
            .accessibilityIdentifier("offline-sprint-board")
        }
    }

    private func seat(of id: String) -> Int {
        context.players.firstIndex { $0.id == id } ?? 0
    }
}

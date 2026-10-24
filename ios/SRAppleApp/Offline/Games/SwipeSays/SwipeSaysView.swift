import SwiftUI
import UIKit

/// Swipe Says on one phone: the prompt panel, its shrinking window, four
/// arrow buttons for anyone who would rather tap than swipe, and everyone's
/// running total.
///
/// The panel is a `SwipeSaysSurface` — a UIKit view that reads its touches'
/// hardware timestamps — under the drawn prompt. Each prompt arrives in the
/// host's view a moment before it is due; `OfflineStimulus` shows it on the
/// first frame at or after the host's `showAt` and remembers that frame, and
/// a swipe is timed from that frame to the instant it was recognised, here.
/// Only the milliseconds and the direction are sent, so a slow link never
/// costs anybody points.
struct SwipeSaysView: View {
    let context: OfflineGameContext<SwipeSaysRules>
    @StateObject private var stimulus = OfflineStimulus()
    /// My answer to the open prompt, shown at once rather than after the host's echo.
    @State private var local: SwipeSaysRules.Answer?
    @State private var localNumber = 0

    /// A swipe this long (host clock) before a prompt is due is taken as a
    /// late swipe at the last one and ignored, not as jumping the gun.
    private static let earlyWindow: Double = 0.5

    private var view: SwipeSaysRules.PlayerView { context.view }

    var body: some View {
        Group {
            switch view.phase {
            case .playing: playingScreen
            case .finished, .over: finishedScreen
            }
        }
        .onAppear { arm() }
        .onChange(of: view.number) { _, _ in arm() }
        .onChange(of: view.phase) { _, _ in arm() }
        .onChange(of: context.clock) { _, _ in arm() }
        .onDisappear { stimulus.reset() }
    }

    // MARK: - Playing

    private var playingScreen: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("PROMPT \(view.number) OF \(view.total)")
                    .font(SR.Text.label(12))
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if playing {
                    Text("\(myScore) pts")
                        .font(SR.Text.mono(14))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityLabel("Your score, \(myScore) points")
                }
            }
            arena
            timeBar
            Text(footer)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
            if playing { arrowButtons }
            SwipeSaysScoreStrip(rows: view.rows, me: context.me)
        }
        .padding(.horizontal, SR.gutter)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srGround(.warm)
    }

    /// The prompt panel, which is also where the swipes land.
    private var arena: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill(SR.ink)
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                GeometryReader { geo in
                    let side = max(0, min(geo.size.width, geo.size.height))
                    SwipeSaysPanel(face: face, side: side)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(arenaLabel)
            .accessibilityIdentifier("offline-swipe-says-prompt")

            if playing {
                SwipeSaysSurface { direction, timestamp in
                    swiped(direction, at: timestamp)
                }
                .accessibilityHidden(true)
                .accessibilityIdentifier("offline-swipe-says-surface")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        .frame(maxWidth: 420, minHeight: 160, maxHeight: .infinity)
    }

    /// How much of the open prompt's window is left, as a bar.
    private var timeBar: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let fraction = windowLeft()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.line)
                    Capsule()
                        .fill(fraction < 0.3 ? SR.error : SR.accent)
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: 420)
        .accessibilityHidden(true)
    }

    /// Four arrows, the same as swiping: for VoiceOver, Switch Control, or
    /// anyone who would rather tap.
    private var arrowButtons: some View {
        HStack(spacing: 8) {
            ForEach(SwipeSaysRules.Direction.allCases, id: \.self) { direction in
                Button {
                    swiped(direction, at: CACurrentMediaTime())
                } label: {
                    Image(systemName: Self.symbol(direction))
                        .font(.system(size: 22, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(SR.ink)
                .srGlassCard(.paper, radius: SR.Glass.innerRadius, interactive: true)
                .accessibilityLabel("Swipe \(direction.word)")
                .accessibilityIdentifier("offline-swipe-says-\(direction.rawValue)")
            }
        }
        .frame(maxWidth: 420)
    }

    // MARK: - What the panel shows

    /// Whether I am in this match and still here (not a spectator).
    private var playing: Bool {
        view.rows.contains { $0.id == context.me && !$0.away }
    }

    private var myScore: Int {
        view.rows.first { $0.id == context.me }?.score ?? 0
    }

    /// My answer to the open prompt: the host's word if it has spoken, else my own.
    private var myAnswer: SwipeSaysRules.Answer? {
        view.myAnswer ?? (localNumber == view.number ? local : nil)
    }

    /// The open prompt's window is over on this phone.
    private var windowClosed: Bool {
        context.clock.now() >= view.closesAt
    }

    private var face: SwipeSaysPanel.Face {
        if let answer = myAnswer { return .answered(answer) }
        guard let prompt = view.prompt else { return .waiting("Done") }
        if stimulus.shown {
            if windowClosed {
                guard prompt.isCircle, playing else { return .waiting("Time!") }
                return .answered(SwipeSaysRules.Answer(direction: nil, ms: nil, verdict: .held,
                                                       points: SwipeSaysRules.holdPoints))
            }
            return .prompt(prompt)
        }
        if let last = view.myLast { return .result(last) }
        return .waiting(view.number == 1 ? "Get ready" : "Ready…")
    }

    private var arenaLabel: String {
        switch face {
        case .prompt(let prompt): return prompt.instruction
        case .answered(let answer), .result(let answer): return Self.verdictText(answer)
        case .waiting(let text): return text
        }
    }

    private var footer: String {
        if !playing { return "You are watching this match." }
        if let answer = myAnswer {
            return answer.verdict == .tooSoon ? "Too soon — wait for the prompt." : "Waiting for the next prompt."
        }
        if stimulus.shown, let prompt = view.prompt, !windowClosed { return prompt.instruction + "!" }
        return "Arrow: swipe that way. Red: the opposite. Circle: hold still."
    }

    /// The share of the open prompt's window still left, 0…1 (full until it shows).
    private func windowLeft() -> CGFloat {
        guard view.phase == .playing, stimulus.shown, myAnswer == nil else {
            return view.phase == .playing && myAnswer == nil ? 1 : 0
        }
        let total = max(0.001, view.closesAt - view.showAt)
        let left = (view.closesAt - context.clock.now()) / total
        return CGFloat(min(1, max(0, left)))
    }

    // MARK: - Finished

    private var finishedScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "All \(view.total) prompts", title: finishedTitle)
                SwipeSaysFinalTable(rows: view.rows, me: context.me, champions: view.champions)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("offline-swipe-says-final")
    }

    private var finishedTitle: String {
        let names = view.champions.map { $0 == context.me ? "You" : context.name(of: $0) }
        if names.count == 1 { return names[0] == "You" ? "You win" : "\(names[0]) wins" }
        return names.isEmpty ? "Nobody scored" : "A tie"
    }

    // MARK: - Acting

    /// Point the stimulus at the open prompt, or rest it once they are done.
    private func arm() {
        if view.phase == .playing {
            if localNumber != view.number {
                stimulus.reset()
                local = nil
                localNumber = view.number
            }
            stimulus.arm(at: view.showAt, clock: context.clock)
        } else {
            stimulus.reset()
        }
    }

    /// A swipe (or an arrow button) at its own local timestamp.
    private func swiped(_ direction: SwipeSaysRules.Direction, at timestamp: Double) {
        guard view.phase == .playing, playing, myAnswer == nil, let prompt = view.prompt else { return }
        let number = view.number
        if let ms = stimulus.reactionMs(touchedAt: timestamp) {
            let answer = SwipeSaysRules.judge(prompt, direction: direction, ms: ms,
                                              windowMs: view.windowMs, arrivedEarly: false)
            localNumber = number
            local = answer
            if answer.verdict == .right { SRHaptic.ok() } else { SRHaptic.bad() }
            context.send(.swipe(prompt: number, direction: direction, ms: ms))
        } else {
            // Long before the prompt: a late swipe at the last one. Let it go.
            guard context.clock.host(fromLocal: timestamp) >= view.showAt - Self.earlyWindow else { return }
            localNumber = number
            local = SwipeSaysRules.Answer(direction: direction, ms: nil, verdict: .tooSoon, points: 0)
            SRHaptic.bad()
            context.send(.early(prompt: number, direction: direction))
        }
    }

    // MARK: - Words and symbols

    static func symbol(_ direction: SwipeSaysRules.Direction) -> String {
        switch direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
    }

    static func verdictText(_ answer: SwipeSaysRules.Answer) -> String {
        switch answer.verdict {
        case .right: return "Right, plus \(answer.points)"
        case .held: return "Held still, plus \(answer.points)"
        case .wrong: return "Wrong way"
        case .tooSoon: return "Too soon"
        case .tooSlow: return "Too slow"
        case .missed: return "Missed it"
        }
    }
}

/// What the prompt panel draws: the prompt itself, a verdict, or a word
/// while the next one is on its way. Sized from `side`, never from content.
struct SwipeSaysPanel: View {
    enum Face {
        case prompt(SwipeSaysRules.Prompt)
        case answered(SwipeSaysRules.Answer)
        case result(SwipeSaysRules.Answer)
        case waiting(String)
    }

    let face: Face
    let side: CGFloat

    var body: some View {
        VStack(spacing: max(4, side * 0.04)) {
            switch face {
            case .prompt(let prompt):
                promptGlyph(prompt)
            case .answered(let answer), .result(let answer):
                Image(systemName: good(answer) ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: max(24, side * 0.32), weight: .bold))
                    .foregroundStyle(good(answer) ? SR.goodOnDark : SR.errorOnDark)
                Text(headline(answer))
                    .font(SR.Text.display(26))
                    .foregroundStyle(SR.paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let ms = answer.ms, answer.verdict == .right {
                    Text("\(ms) ms")
                        .font(SR.Text.mono(15))
                        .foregroundStyle(SR.paper.opacity(0.75))
                        .lineLimit(1)
                }
            case .waiting(let text):
                Text(text)
                    .font(SR.Text.hero(40))
                    .foregroundStyle(SR.paper.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func promptGlyph(_ prompt: SwipeSaysRules.Prompt) -> some View {
        if let direction = prompt.direction {
            Image(systemName: SwipeSaysView.symbol(direction))
                .font(.system(size: max(24, side * 0.5), weight: .black))
                .foregroundStyle(prompt.red ? SR.errorOnDark : SR.paper)
            if prompt.red {
                Text("OPPOSITE")
                    .font(SR.Text.label(14))
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.errorOnDark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        } else {
            Image(systemName: "circle")
                .font(.system(size: max(24, side * 0.5), weight: .black))
                .foregroundStyle(SR.accent)
            Text("HOLD STILL")
                .font(SR.Text.label(14))
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func good(_ answer: SwipeSaysRules.Answer) -> Bool {
        answer.verdict == .right || answer.verdict == .held
    }

    private func headline(_ answer: SwipeSaysRules.Answer) -> String {
        switch answer.verdict {
        case .right, .held: return "+\(answer.points)"
        case .wrong: return "Wrong way"
        case .tooSoon: return "Too soon"
        case .tooSlow: return "Too slow"
        case .missed: return "Missed"
        }
    }
}

/// Everyone's running total, highest first: one row each so five names fit
/// on a 375pt phone, each name truncating rather than pushing the row wide.
struct SwipeSaysScoreStrip: View {
    let rows: [SwipeSaysRules.Row]
    let me: String

    var body: some View {
        VStack(spacing: 4) {
            ForEach(SwipeSaysScoreStrip.ranked(rows)) { row in
                HStack(spacing: 8) {
                    Text(row.id == me ? "You" : row.name)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if row.answered {
                        Image(systemName: "hand.point.up.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SR.inkMuted)
                            .accessibilityLabel("Answered")
                    }
                    Spacer(minLength: 6)
                    if let last = row.last {
                        Text(row.lastPoints > 0 ? "+\(row.lastPoints)" : SwipeSaysScoreStrip.short(last))
                            .font(SR.Text.mono(13))
                            .foregroundStyle(row.lastPoints > 0 ? SR.good : SR.inkMuted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text(row.away ? "left" : "\(row.score)")
                        .font(SR.Text.mono(15))
                        .foregroundStyle(SR.ink)
                        .frame(minWidth: 40, alignment: .trailing)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-swipe-says-scores")
    }

    /// Highest total first; seat order breaks a tie, so rows don't shuffle.
    static func ranked(_ rows: [SwipeSaysRules.Row]) -> [SwipeSaysRules.Row] {
        rows.enumerated()
            .sorted { a, b in a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset }
            .map(\.element)
    }

    static func short(_ verdict: SwipeSaysRules.Verdict) -> String {
        switch verdict {
        case .right, .held: return "ok"
        case .wrong: return "wrong"
        case .tooSoon: return "soon"
        case .tooSlow: return "slow"
        case .missed: return "miss"
        }
    }
}

/// The final totals, after the last prompt, with a crown on the winner.
struct SwipeSaysFinalTable: View {
    let rows: [SwipeSaysRules.Row]
    let me: String
    let champions: [String]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(SwipeSaysScoreStrip.ranked(rows).enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    Text(row.id == me ? "You" : row.name)
                        .font(SR.Text.title())
                        .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if champions.contains(row.id) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SR.accent)
                            .accessibilityLabel("Winner")
                    }
                    Spacer(minLength: 8)
                    Text("\(row.score)")
                        .font(SR.Text.display(20))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityLabel("\(row.score) points")
                }
                .frame(minHeight: SR.tapTarget)
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
    }
}

/// The swipe pad: a UIKit view, so each swipe carries `UITouch.timestamp` —
/// the same clock the display link stamps the prompt's frame with. A swipe
/// counts the moment the finger has travelled `threshold` points; the
/// longer axis decides the direction.
struct SwipeSaysSurface: UIViewRepresentable {
    let onSwipe: (SwipeSaysRules.Direction, Double) -> Void

    func makeUIView(context: Context) -> SwipeSaysSurfaceView {
        let view = SwipeSaysSurfaceView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: SwipeSaysSurfaceView, context: Context) {
        view.onSwipe = onSwipe
    }
}

final class SwipeSaysSurfaceView: UIView {
    var onSwipe: ((SwipeSaysRules.Direction, Double) -> Void)?
    /// How far a finger must move to be a swipe, points.
    static let threshold: CGFloat = 24
    private var startPoint: CGPoint?
    private var fired = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        startPoint = touch.location(in: self)
        fired = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !fired, let touch = touches.first, let startPoint else { return }
        let point = touch.location(in: self)
        let dx = point.x - startPoint.x
        let dy = point.y - startPoint.y
        guard max(abs(dx), abs(dy)) >= Self.threshold else { return }
        fired = true
        let direction: SwipeSaysRules.Direction
        if abs(dx) > abs(dy) {
            direction = dx > 0 ? .right : .left
        } else {
            direction = dy > 0 ? .down : .up
        }
        onSwipe?(direction, touch.timestamp)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        startPoint = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        startPoint = nil
    }
}

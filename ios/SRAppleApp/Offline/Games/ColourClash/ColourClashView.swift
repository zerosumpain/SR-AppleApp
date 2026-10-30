import SwiftUI
import UIKit

/// Colour Clash on one phone: the card going by, what to do about it, and the
/// running scores.
///
/// Like Quick Draw, the whole table is the button — a `TapSurface` over
/// everything, so a touch keeps its hardware timestamp. Each card appears when
/// this phone's `OfflineStimulus` reaches the frame due at the card's host
/// time; the reaction is measured from that frame to the touch, here, and the
/// view sends the number. Every ink also has its own shape, and VoiceOver reads
/// the word and the ink, so nobody has to tell colours apart to play.
///
/// The card slaps down fresh each time (a quick scale-in, no fade to wait
/// for, so the stimulus is on screen the frame it is due), framed in its own
/// ink. A tap answers at once on this phone: a green tick or a red cross
/// stamped on the card with the milliseconds, and the edge of the screen
/// glows the same colour. Progress through the deck is a row of pips.
struct ColourClashView: View {
    let context: OfflineGameContext<ColourClashRules>
    @StateObject private var stimulus = OfflineStimulus()
    /// The card the stimulus is aimed at.
    @State private var armedIndex = -1
    /// My tap on the card on screen, shown at once rather than after the echo.
    @State private var localMs: Int?
    @State private var localIndex = -1
    /// Whether my tap on the card on screen was on a match.
    @State private var localGood = false

    private var view: ColourClashRules.PlayerView { context.view }

    var body: some View {
        Group {
            switch view.phase {
            case .ready, .running: table
            case .result, .over: result
            }
        }
        .onAppear { arm() }
        .onChange(of: view.index) { _, _ in arm() }
        .onChange(of: view.phase) { _, _ in arm() }
        .onChange(of: context.clock) { _, _ in arm() }
        .onDisappear { stimulus.reset() }
    }

    // MARK: - The table

    private var table: some View {
        ZStack {
            VStack(spacing: 14) {
                header
                rule
                card
                feedback
                ColourClashLegend()
                Spacer(minLength: 0)
                ColourClashScores(rows: view.rows, me: context.me)
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 10)
                    .srGlassCard(.paper)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, SR.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityElement(children: .contain)

            if let ms = tapMs, localIndex == view.index {
                ColourClashEdgeGlow(good: localGood)
                    .id("glow-\(localIndex)-\(ms)")
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if playing && view.phase == .running {
                TapSurface(label: accessibilityText) { touched(at: $0) }
                    .ignoresSafeArea()
                    .accessibilityIdentifier("offline-colour-clash-surface")
            }
        }
        .srGround(.warm)
        .accessibilityIdentifier("offline-colour-clash-table")
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(cardLine)
                    .font(SR.Text.label(13))
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if let mine = myRow {
                    Text(mine.points == 1 || mine.points == -1 ? "\(mine.points) pt" : "\(mine.points) pts")
                        .font(SR.Text.title(16))
                        .monospacedDigit()
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(SR.accent.opacity(0.14)))
                        .srNumeric(Double(mine.points))
                        .accessibilityLabel("Your score \(mine.points)")
                }
            }
            progressPips
        }
    }

    /// The deck as a row of pips, filled up to the card on screen.
    private var progressPips: some View {
        let done = view.phase == .ready ? 0 : min(max(view.index + 1, 0), view.cardCount)
        let dots = PlayTableMath.progressDots(done: done, count: view.cardCount, cap: 30)
        return HStack(spacing: 3) {
            ForEach(0..<dots.total, id: \.self) { index in
                Capsule()
                    .fill(index < dots.filled ? SR.accent : SR.inkGhost.opacity(0.3))
                    .frame(height: 5)
            }
        }
        .srAnimation(.snappy(duration: 0.2), value: dots.filled)
        .accessibilityHidden(true)
    }

    private var cardLine: String {
        if view.phase == .ready { return "\(view.cardCount) CARDS · GET READY" }
        let number = min(max(view.index + 1, 1), view.cardCount)
        return "CARD \(number) OF \(view.cardCount)"
    }

    /// The one rule, always in sight.
    private var rule: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(SR.Text.title(18))
                .foregroundStyle(SR.accent)
                .accessibilityHidden(true)
            Text(instruction)
                .font(SR.Text.bodyMedium())
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
    }

    /// One line on what to do now.
    private var instruction: String {
        if !playing { return "You are watching this match." }
        if view.phase == .ready { return "Tap only when the word names its own ink." }
        if visibleCard == nil { return "Watch for the card." }
        if myMs != nil { return "Tapped. Wait for the next card." }
        return "Same word and ink? Tap anywhere. Otherwise, don't."
    }

    private var card: some View {
        ZStack {
            ColourClashCardFace(card: visibleCard, countdownUntil: view.phase == .ready ? view.firstAt : nil,
                                clock: context.clock)
                .id(visibleCard == nil ? -1 : view.index)
                .transition(.asymmetric(insertion: .scale(scale: 1.12), removal: .identity))
            if let ms = tapMs, localIndex == view.index, visibleCard != nil {
                ColourClashVerdict(good: localGood, ms: ms)
                    .id("verdict-\(localIndex)")
            }
        }
        .frame(maxWidth: 440, maxHeight: 220)
        .srAnimation(.spring(response: 0.22, dampingFraction: 0.62), value: visibleCard == nil ? -1 : view.index)
    }

    /// The card, once this phone has drawn the frame that shows it.
    private var visibleCard: ColourClashRules.Card? {
        guard view.phase == .running, let card = view.card, stimulus.shown, armedIndex == view.index else { return nil }
        return card
    }

    /// My time on the card on screen: the host's word if it has spoken, else my own.
    private var myMs: Int? {
        view.myMs ?? (localIndex == view.index ? localMs : nil)
    }

    /// My own tap's time, for the stamp: shown the instant I tap.
    private var tapMs: Int? {
        localIndex == view.index ? localMs : nil
    }

    private var myRow: ColourClashRules.Row? {
        view.rows.first { $0.id == context.me }
    }

    /// Whether I am in this match and still here (not a spectator).
    private var playing: Bool {
        if let mine = myRow { return !mine.away }
        return false
    }

    /// My tap, then the last scored card's verdict.
    private var feedback: some View {
        VStack(spacing: 4) {
            Text(tapLine)
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(lastLine)
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-colour-clash-feedback")
    }

    private var tapLine: String {
        guard let ms = myMs else { return " " }
        return "Tapped · \(ms) ms"
    }

    private var lastLine: String {
        guard let last = view.last, let card = view.lastCard else { return " " }
        let what = "\(card.word.word) in \(card.ink.rawValue)"
        let verdict = last.match ? "a match" : "no match"
        if let mine = last.points[context.me] {
            let sign = mine > 0 ? "+\(mine)" : "\(mine)"
            return "Last card: \(what), \(verdict) · you \(sign)"
        }
        return "Last card: \(what), \(verdict)"
    }

    private var accessibilityText: String {
        guard let card = visibleCard else { return "Waiting for the next card." }
        if myMs != nil { return "Tapped. Waiting for the next card." }
        return "The word \(card.word.rawValue), in \(card.ink.rawValue) ink, \(card.ink.shapeName). Double-tap if they match."
    }

    // MARK: - The final table

    private var result: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "All \(view.cardCount) cards", title: resultTitle)
                ColourClashScores(rows: view.rows, me: context.me, ranked: true)
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 12)
                    .srGlassCard(.paper)
                if view.phase == .result {
                    HStack(spacing: 10) {
                        PlayTableClockRing(clock: context.clock, until: view.resultUntil,
                                           total: ColourClashRules.resultPause, size: 34)
                        Text("Final table in")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                        OfflineCountdown(clock: context.clock, until: view.resultUntil, font: SR.Text.mono(), tone: SR.inkMuted)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("offline-colour-clash-result")
    }

    private var resultTitle: String {
        let names = view.champions.map { $0 == context.me ? "You" : context.name(of: $0) }
        if names.count == 1 { return names[0] == "You" ? "You win" : "\(names[0]) wins" }
        return names.isEmpty ? "Nobody won" : "A tie"
    }

    // MARK: - Acting

    /// Aim the stimulus at the card on screen, or rest it when there is none.
    private func arm() {
        guard view.phase == .running, view.card != nil else {
            stimulus.reset()
            armedIndex = -1
            return
        }
        if armedIndex != view.index {
            stimulus.reset()
            armedIndex = view.index
            localMs = nil
            localIndex = view.index
        }
        stimulus.arm(at: view.shownAt, clock: context.clock)
    }

    /// A touch on the table, at its own hardware timestamp.
    private func touched(at timestamp: Double) {
        guard view.phase == .running, playing, let card = visibleCard, myMs == nil else { return }
        guard let ms = stimulus.reactionMs(touchedAt: timestamp) else { return }
        let index = view.index
        localIndex = index
        localMs = ms
        localGood = card.isMatch
        if card.isMatch { SRHaptic.ok() } else { SRHaptic.bad() }
        context.send(.tap(card: index, ms: ms))
    }
}

// MARK: - Inks

extension ColourClashRules.Hue {
    /// The ink itself. Fixed values, chosen to read on the card's light face in
    /// either appearance.
    var color: Color {
        switch self {
        case .red: return Color(red: 0.84, green: 0.13, blue: 0.13)
        case .blue: return Color(red: 0.10, green: 0.36, blue: 0.85)
        case .green: return Color(red: 0.11, green: 0.56, blue: 0.24)
        case .orange: return Color(red: 0.90, green: 0.47, blue: 0.0)
        case .purple: return Color(red: 0.48, green: 0.24, blue: 0.77)
        }
    }

    /// Each ink's shape, so colour is never the only cue.
    var symbol: String {
        switch self {
        case .red: return "circle.fill"
        case .blue: return "square.fill"
        case .green: return "triangle.fill"
        case .orange: return "diamond.fill"
        case .purple: return "star.fill"
        }
    }

    var shapeName: String {
        switch self {
        case .red: return "circle"
        case .blue: return "square"
        case .green: return "triangle"
        case .orange: return "diamond"
        case .purple: return "star"
        }
    }
}

/// The card: a light face framed in its ink, the word printed in that ink,
/// and the ink's shape in two corners. Sized from its own width, so it fits
/// any phone.
struct ColourClashCardFace: View {
    let card: ColourClashRules.Card?
    /// Before the first card, the lead-in countdown in its place.
    let countdownUntil: Double?
    let clock: OfflineHostClock

    /// The face stays light in dark mode: the inks are tuned for it.
    private var face: Color { Color(red: 0.98, green: 0.97, blue: 0.94) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return shape
            .fill(face)
            .overlay {
                if let card {
                    shape
                        .inset(by: 8)
                        .stroke(card.ink.color.opacity(0.55), lineWidth: 3)
                } else {
                    shape.stroke(SR.line, lineWidth: 1)
                }
            }
            .aspectRatio(1.6, contentMode: .fit)
            .overlay { content }
            .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier("offline-colour-clash-card")
    }

    private var content: some View {
        GeometryReader { geo in
            let glyph = max(min(geo.size.height * 0.16, 34), 14)
            ZStack {
                if let card {
                    Image(systemName: card.ink.symbol)
                        .font(.system(size: glyph, weight: .bold))
                        .foregroundStyle(card.ink.color)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(geo.size.height * 0.12)
                    Image(systemName: card.ink.symbol)
                        .font(.system(size: glyph, weight: .bold))
                        .foregroundStyle(card.ink.color)
                        .rotationEffect(.degrees(180))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(geo.size.height * 0.12)
                    Text(card.word.word)
                        .font(.system(size: max(geo.size.height * 0.34, 22), weight: .black, design: .rounded))
                        .foregroundStyle(card.ink.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .padding(.horizontal, geo.size.width * 0.12)
                } else if let countdownUntil {
                    VStack(spacing: 4) {
                        Text("First card in")
                            .font(SR.Text.mono(13))
                            .foregroundStyle(Color.black.opacity(0.55))
                        OfflineCountdown(clock: clock, until: countdownUntil, font: SR.Text.hero(56),
                                         tone: Color.black.opacity(0.8))
                    }
                } else {
                    Image(systemName: "eye")
                        .font(.system(size: glyph * 1.2, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.22))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var label: String {
        if let card {
            return "The word \(card.word.rawValue), in \(card.ink.rawValue) ink, \(card.ink.shapeName)."
        }
        return countdownUntil != nil ? "Get ready. The first card is coming." : "Waiting for the next card."
    }
}

/// My tap's verdict, stamped on the card the instant I tap: a tick or a
/// cross, and how quick it was.
struct ColourClashVerdict: View {
    let good: Bool
    let ms: Int
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tone = good ? Color(hex: 0x1E9E52) : Color(hex: 0xD3343A)
        let down = landed || reduceMotion
        return HStack(spacing: 8) {
            Image(systemName: good ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(SR.Text.display(26))
            Text("\(ms) ms")
                .font(SR.Text.title(18))
                .monospacedDigit()
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(tone))
        .shadow(color: tone.opacity(0.45), radius: 8, x: 0, y: 4)
        .scaleEffect(down ? 1 : 1.6)
        .opacity(down ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 10)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, !landed else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { landed = true }
        }
    }
}

/// The screen's edge glowing green or red after a tap, fading out once.
struct ColourClashEdgeGlow: View {
    let good: Bool
    @State private var faded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tone = good ? Color(hex: 0x1E9E52) : Color(hex: 0xD3343A)
        return Rectangle()
            .strokeBorder(tone, lineWidth: 14)
            .blur(radius: 10)
            .opacity(faded || reduceMotion ? 0 : 0.85)
            .onAppear {
                guard !reduceMotion, !faded else { return }
                withAnimation(.easeOut(duration: 0.6)) { faded = true }
            }
    }
}

/// Which shape goes with which ink: five equal columns, so it fits any width.
struct ColourClashLegend: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ColourClashRules.Hue.allCases, id: \.self) { hue in
                VStack(spacing: 3) {
                    Image(systemName: hue.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(hue.color)
                    Text(hue.rawValue)
                        .font(SR.Text.label(12))
                        .foregroundStyle(SR.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(hue.rawValue) ink, \(hue.shapeName)")
            }
        }
        .padding(.vertical, 8)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
        .accessibilityIdentifier("offline-colour-clash-legend")
    }
}

/// Everyone's points, one row each, with what the last card gave them; at
/// the end, ranked with a place disc each.
struct ColourClashScores: View {
    let rows: [ColourClashRules.Row]
    let me: String
    var ranked: Bool = false

    /// Seat order while playing; best first once ranked.
    private var shown: [ColourClashRules.Row] {
        ranked ? rows.sorted { $0.points > $1.points } : rows
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                scoreRow(row, index: index)
            }
        }
        .frame(maxWidth: 440)
        .accessibilityIdentifier("offline-colour-clash-scores")
    }

    private func scoreRow(_ row: ColourClashRules.Row, index: Int) -> some View {
        let mine = row.id == me
        return HStack(spacing: 10) {
            if ranked {
                Text("\(place(index))")
                    .font(SR.Text.title(15))
                    .monospacedDigit()
                    .foregroundStyle(place(index) == 1 ? Color(hex: 0x4A3203) : SR.ink)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(place(index) == 1 ? Color(hex: 0xF5C451) : SR.inkGhost.opacity(0.25)))
                    .accessibilityHidden(true)
            }
            Text(mine ? "You" : row.name)
                .font(SR.Text.bodyMedium(16))
                .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            if row.quickest {
                Image(systemName: "bolt.fill")
                    .font(SR.Text.label(12))
                    .foregroundStyle(Color(hex: 0xE0A21C))
                    .accessibilityLabel("Quickest on the last card")
            }
            Spacer(minLength: 6)
            if row.away {
                Text("left")
                    .font(SR.Text.mono(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize()
            } else if let delta = row.lastPoints {
                Text(delta > 0 ? "+\(delta)" : "\(delta)")
                    .font(SR.Text.mono(13))
                    .foregroundStyle(delta > 0 ? SR.good : (delta < 0 ? SR.error : SR.inkMuted))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill((delta > 0 ? SR.good : (delta < 0 ? SR.error : SR.inkGhost)).opacity(0.12)))
                    .fixedSize()
                    .accessibilityLabel("Last card \(delta) points")
            }
            Text("\(row.points)")
                .font(SR.Text.figure(18))
                .foregroundStyle(SR.ink)
                .frame(minWidth: 32, alignment: .trailing)
                .srNumeric(Double(row.points))
                .accessibilityLabel("\(row.points) points")
        }
        .frame(minHeight: 36)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(mine ? SR.accent.opacity(0.1) : Color.clear)
        )
        .accessibilityElement(children: .combine)
    }

    /// Place on the table, ties sharing a place.
    private func place(_ index: Int) -> Int {
        let list = shown
        guard index < list.count else { return index + 1 }
        let points = list[index].points
        return (list.firstIndex { $0.points == points } ?? index) + 1
    }
}

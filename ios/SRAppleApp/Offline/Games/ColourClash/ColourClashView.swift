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
struct ColourClashView: View {
    let context: OfflineGameContext<ColourClashRules>
    @StateObject private var stimulus = OfflineStimulus()
    /// The card the stimulus is aimed at.
    @State private var armedIndex = -1
    /// My tap on the card on screen, shown at once rather than after the echo.
    @State private var localMs: Int?
    @State private var localIndex = -1

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
            VStack(spacing: 12) {
                header
                Text(instruction)
                    .font(SR.Text.bodyMedium())
                    .foregroundStyle(SR.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                ColourClashCardFace(card: visibleCard, countdownUntil: view.phase == .ready ? view.firstAt : nil,
                                    clock: context.clock)
                    .frame(maxWidth: 420, maxHeight: 190)
                feedback
                ColourClashLegend()
                Spacer(minLength: 0)
                ColourClashScores(rows: view.rows, me: context.me)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, SR.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityElement(children: .contain)

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
                    .font(SR.Text.mono(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel("Your score \(mine.points)")
            }
        }
    }

    private var cardLine: String {
        if view.phase == .ready { return "\(view.cardCount) CARDS · GET READY" }
        let number = min(max(view.index + 1, 1), view.cardCount)
        return "CARD \(number) OF \(view.cardCount)"
    }

    /// One line on what to do now.
    private var instruction: String {
        if !playing { return "You are watching this match." }
        if view.phase == .ready { return "Tap only when the word names its own ink." }
        if visibleCard == nil { return "Watch for the card." }
        if myMs != nil { return "Tapped. Wait for the next card." }
        return "Same word and ink? Tap anywhere. Otherwise, don't."
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
                ColourClashScores(rows: view.rows, me: context.me)
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 12)
                    .srGlassCard(.paper)
                if view.phase == .result {
                    HStack(spacing: 8) {
                        Text("Final table in")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                        OfflineCountdown(clock: context.clock, until: view.resultUntil, font: SR.Text.mono(), tone: SR.inkMuted)
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

/// The card: a light face with the word printed in its ink, and the ink's
/// shape either side. Sized from its own width, so it fits any phone.
struct ColourClashCardFace: View {
    let card: ColourClashRules.Card?
    /// Before the first card, the lead-in countdown in its place.
    let countdownUntil: Double?
    let clock: OfflineHostClock

    /// The face stays light in dark mode: the inks are tuned for it.
    private var face: Color { Color(red: 0.98, green: 0.97, blue: 0.94) }

    var body: some View {
        RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
            .fill(face)
            .overlay {
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                    .stroke(SR.line, lineWidth: 1)
            }
            .aspectRatio(1.6, contentMode: .fit)
            .overlay { content }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier("offline-colour-clash-card")
    }

    private var content: some View {
        GeometryReader { geo in
            let glyph = max(min(geo.size.height * 0.2, 40), 14)
            VStack(spacing: geo.size.height * 0.06) {
                if let card {
                    HStack(spacing: glyph * 0.6) {
                        Image(systemName: card.ink.symbol)
                            .font(.system(size: glyph, weight: .bold))
                        Image(systemName: card.ink.symbol)
                            .font(.system(size: glyph, weight: .bold))
                    }
                    .foregroundStyle(card.ink.color)
                    Text(card.word.word)
                        .font(.system(size: max(geo.size.height * 0.32, 20), weight: .heavy, design: .rounded))
                        .foregroundStyle(card.ink.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                } else if let countdownUntil {
                    Text("First card in")
                        .font(SR.Text.mono(13))
                        .foregroundStyle(Color.black.opacity(0.55))
                    OfflineCountdown(clock: clock, until: countdownUntil, font: SR.Text.hero(48),
                                     tone: Color.black.opacity(0.8))
                } else {
                    Image(systemName: "eye")
                        .font(.system(size: glyph, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.25))
                }
            }
            .padding(.horizontal, 12)
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

/// Which shape goes with which ink: five equal columns, so it fits any width.
struct ColourClashLegend: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ColourClashRules.Hue.allCases, id: \.self) { hue in
                VStack(spacing: 3) {
                    Image(systemName: hue.symbol)
                        .font(.system(size: 14, weight: .bold))
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
        .accessibilityIdentifier("offline-colour-clash-legend")
    }
}

/// Everyone's points, one row each, with what the last card gave them.
struct ColourClashScores: View {
    let rows: [ColourClashRules.Row]
    let me: String

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.id == me ? "You" : row.name)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if row.quickest {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SR.accent)
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
                            .fixedSize()
                            .accessibilityLabel("Last card \(delta) points")
                    }
                    Text("\(row.points)")
                        .font(SR.Text.mono(15))
                        .foregroundStyle(SR.ink)
                        .frame(minWidth: 28, alignment: .trailing)
                        .accessibilityLabel("\(row.points) points")
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: 420)
        .accessibilityIdentifier("offline-colour-clash-scores")
    }
}

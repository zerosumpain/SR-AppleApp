import SwiftUI
import UIKit

// The shared furniture of the Play nearby games G to W (Go Fish to
// Whack-a-Mole), drawn so fifteen games feel like one set rather than
// fifteen forms: a status banner that says whose go it is in colour, a clock
// that drains as a ring, big thumb-sized buttons, a felt table for the card
// games, the players seated round it, a pop of words at the moments that
// matter, a short burst for a win, and this phone's bests.
//
// It lives beside Go Fish only because a game's folder is where its view's
// helpers go; every type is prefixed `NearbyPlay` so nothing collides with
// the shell's `Offline…` kit, which these build on but never change.
//
// Performance: every clock here runs on a FINITE timeline that stops at its
// last frame (`NearbyPlayFiniteSchedule`), every pop and burst ends by
// itself, and the felt's weave is drawn once per size — nothing ticks while
// a screen is idle.

// MARK: - Metrics

enum NearbyPlayMetrics {
    /// A game's action button: the owner asked for bigger buttons in games.
    static let button: CGFloat = 58
    /// The one big action on a screen (Higher, Lower, SNAP).
    static let bigButton: CGFloat = 72
    /// A control's corner.
    static let radius: CGFloat = 18
}

// MARK: - Voice

/// What VoiceOver says at a moment a sighted player sees pop up.
enum NearbyPlayVoice {
    static func say(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning, !text.isEmpty else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}

// MARK: - A clock that stops

/// A timeline that ticks every `step` until `end`, draws one last frame at
/// `end`, and then stops: no frames are spent on a clock that has run out.
struct NearbyPlayFiniteSchedule: TimelineSchedule {
    let end: Date
    var step: TimeInterval = 1.0 / 20.0

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> NearbyPlayTicks {
        var pace = step
        if case .lowFrequency = mode { pace = 1 }
        return NearbyPlayTicks(from: startDate, to: end, step: pace)
    }
}

/// A countdown on the host's clock as a ring that drains, with the seconds
/// in the middle. It turns to the warning colour in the last few seconds and,
/// for the player whose clock it is, ticks the hand on the last three.
struct NearbyPlayClockRing: View {
    let clock: OfflineHostClock
    /// Host-clock seconds.
    let until: Double
    /// The whole window, seconds: what a full ring stands for.
    let total: Double
    var size: CGFloat = 54
    var tone: Color = SR.accent
    var track: Color = SR.ink.opacity(0.12)
    var ink: Color = SR.ink
    var urgentTone: Color = SR.error
    /// The figure's colour in the last seconds; nil keeps `urgentTone`.
    var urgentInk: Color? = nil
    var urgentBelow: Double = 5
    /// Tick the hand on each of the last three seconds.
    var ticks: Bool = false

    var body: some View {
        let end = Date().addingTimeInterval(max(0, until - clock.now()))
        TimelineView(NearbyPlayFiniteSchedule(end: end, step: NearbyPlayClockMath.ringStep(total: total))) { timeline in
            NearbyPlayRingFace(left: end.timeIntervalSince(timeline.date), total: total, size: size,
                               tone: tone, track: track, ink: ink, urgentTone: urgentTone,
                               urgentInk: urgentInk ?? urgentTone, urgentBelow: urgentBelow, ticks: ticks)
        }
        .frame(width: size, height: size)
    }
}

private struct NearbyPlayRingFace: View {
    let left: Double
    let total: Double
    let size: CGFloat
    let tone: Color
    let track: Color
    let ink: Color
    let urgentTone: Color
    let urgentInk: Color
    let urgentBelow: Double
    let ticks: Bool

    var body: some View {
        let fraction = NearbyPlayClockMath.fraction(left: left, total: total)
        let seconds = NearbyPlayClockMath.shownSeconds(left: left)
        let urgent = left > 0 && left <= urgentBelow
        let line = max(3, size * 0.1)
        ZStack {
            Circle()
                .stroke(track, lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(urgent ? urgentTone : tone, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(seconds)")
                .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(urgent ? urgentInk : ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(line)
        }
        .frame(width: size, height: size)
        .onChange(of: seconds) { _, now in
            if ticks && now > 0 && now <= 3 { SRHaptic.select() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seconds == 1 ? "1 second left" : "\(seconds) seconds left")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A thin bar that drains to a host-clock instant, for a window too short
/// for a ring to read (a prompt, a call).
struct NearbyPlayClockBar: View {
    let clock: OfflineHostClock
    let until: Double
    let total: Double
    var tone: Color = SR.accent
    var urgentTone: Color = SR.error
    var track: Color = SR.ink.opacity(0.1)
    var height: CGFloat = 8

    var body: some View {
        let end = Date().addingTimeInterval(max(0, until - clock.now()))
        TimelineView(NearbyPlayFiniteSchedule(end: end, step: 1.0 / 30.0)) { timeline in
            let fraction = NearbyPlayClockMath.fraction(left: end.timeIntervalSince(timeline.date), total: total)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    Capsule()
                        .fill(fraction < 0.3 ? urgentTone : tone)
                        .frame(width: max(0, geo.size.width * CGFloat(fraction)))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 3, 2, 1, GO — each digit landing with a bump and a tick, then the word.
struct NearbyPlayCountdownHero: View {
    let clock: OfflineHostClock
    let until: Double
    var size: CGFloat = 120
    var tone: Color = SR.accent
    var goText: String = "GO!"

    var body: some View {
        let end = Date().addingTimeInterval(max(0, until - clock.now()))
        TimelineView(NearbyPlayFiniteSchedule(end: end, step: 0.1)) { timeline in
            NearbyPlayCountdownDigit(seconds: NearbyPlayClockMath.shownSeconds(left: end.timeIntervalSince(timeline.date)),
                                     size: size, tone: tone, goText: goText)
        }
    }
}

private struct NearbyPlayCountdownDigit: View {
    let seconds: Int
    let size: CGFloat
    let tone: Color
    let goText: String
    @State private var bump = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(seconds > 0 ? "\(seconds)" : goText)
            .font(.system(size: size, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tone)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .scaleEffect(bump ? 1.18 : 1)
            .shadow(color: tone.opacity(0.35), radius: size * 0.08, x: 0, y: size * 0.04)
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: seconds)
            .onChange(of: seconds) { _, _ in
                SRHaptic.select()
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.08)) { bump = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { bump = false }
                }
            }
            .accessibilityLabel(seconds > 0 ? "Starting in \(seconds)" : "Go")
    }
}

// MARK: - Whose go it is

/// What sits at the banner's leading edge.
enum NearbyPlayMark: Equatable {
    case none
    /// An SF Symbol in a disc.
    case symbol(String)
    /// A player's initial in their colour.
    case person(String)
}

/// The top of a game: a kicker, what is happening in big type, what to do
/// in one line, and (trailing) usually the clock. When it is THIS phone's go
/// the whole card fills with the accent, so "your turn" is seen from across
/// the room before a word is read.
struct NearbyPlayBanner<Trailing: View>: View {
    let kicker: String
    let title: String
    var strap: String? = nil
    /// It is this phone's move.
    var mine: Bool = false
    /// The colour of whoever is acting.
    var tone: Color = SR.accent
    var mark: NearbyPlayMark = .none
    let trailing: Trailing

    init(kicker: String, title: String, strap: String? = nil, mine: Bool = false,
         tone: Color = SR.accent, mark: NearbyPlayMark = .none, @ViewBuilder trailing: () -> Trailing) {
        self.kicker = kicker
        self.title = title
        self.strap = strap
        self.mine = mine
        self.tone = tone
        self.mark = mark
        self.trailing = trailing()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
        HStack(alignment: .center, spacing: 12) {
            markView
            words
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(SR.accentDeep)
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0)],
                                          startPoint: .top, endPoint: .center))
            }
            .opacity(mine ? 1 : 0)
        }
        .overlay(alignment: .leading) {
            if !mine {
                Capsule().fill(tone).frame(width: 4).padding(.vertical, 16).padding(.leading, 1)
            }
        }
        .srGlassCard(.paper)
        .srAnimation(.snappy(duration: 0.3), value: mine)
        .accessibilityElement(children: .combine)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(kicker.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(mine ? SR.paper.opacity(0.85) : SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(SR.Text.display(24))
                .foregroundStyle(mine ? SR.paper : SR.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let strap {
                Text(strap)
                    .font(SR.Text.secondary())
                    .foregroundStyle(mine ? SR.paper.opacity(0.92) : SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .none:
            EmptyView()
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(mine ? SR.accentDeep : SR.paper)
                .frame(width: 46, height: 46)
                .background(Circle().fill(mine ? SR.paper : tone))
                .accessibilityHidden(true)
        case .person(let name):
            OfflineInitial(name: name, size: 46, tone: tone)
                .overlay { Circle().strokeBorder(mine ? SR.paper : Color.clear, lineWidth: 3) }
        }
    }
}

extension NearbyPlayBanner where Trailing == EmptyView {
    init(kicker: String, title: String, strap: String? = nil, mine: Bool = false,
         tone: Color = SR.accent, mark: NearbyPlayMark = .none) {
        self.init(kicker: kicker, title: title, strap: strap, mine: mine, tone: tone, mark: mark) { EmptyView() }
    }
}

/// The ring as the banner wants it: paper on the accent when it is my go.
struct NearbyPlayBannerClock: View {
    let clock: OfflineHostClock
    let until: Double
    let total: Double
    let mine: Bool

    var body: some View {
        NearbyPlayClockRing(clock: clock, until: until, total: total, size: 54,
                            tone: mine ? SR.paper : SR.accent,
                            track: mine ? SR.paper.opacity(0.25) : SR.ink.opacity(0.12),
                            ink: mine ? SR.paper : SR.ink,
                            urgentTone: mine ? Color(hex: 0xFFC83D) : SR.error,
                            urgentInk: mine ? SR.paper : SR.error,
                            ticks: mine)
    }
}

// MARK: - Buttons

enum NearbyPlayButtonKind {
    /// The one thing to do now.
    case primary
    /// Anything else.
    case secondary
    /// Something that costs: Liar!, a bomb.
    case danger
    /// Right / yes / higher.
    case go
}

/// A big, full-width game button with a word and a symbol: at least 58
/// points tall, the label scaling with the reader's text size.
struct NearbyPlayButton: View {
    let title: String
    var icon: String? = nil
    var kind: NearbyPlayButtonKind = .primary
    var enabled: Bool = true
    var minHeight: CGFloat = NearbyPlayMetrics.button
    /// Lit as chosen (a call already made).
    var chosen: Bool = false
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: NearbyPlayMetrics.radius, style: .continuous)
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(SR.Text.title(19))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(SR.Text.title(18))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background {
                ZStack {
                    shape.fill(fill)
                    if kind != .secondary || chosen {
                        shape.fill(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                                                  startPoint: .top, endPoint: .center))
                    }
                }
            }
            .overlay { shape.strokeBorder(rim, lineWidth: chosen ? 3 : 1) }
            .contentShape(shape)
        }
        .buttonStyle(SRPressStyle())
        .disabled(!enabled)
        .opacity(enabled || chosen ? 1 : 0.45)
    }

    private var fill: Color {
        if chosen { return SR.accentDeep }
        switch kind {
        case .primary: return SR.accentDeep
        case .secondary: return SR.surface
        case .danger: return SR.error
        case .go: return SR.good
        }
    }

    private var ink: Color {
        if chosen { return SR.paper }
        return kind == .secondary ? SR.ink : SR.paper
    }

    private var rim: Color {
        if chosen { return SR.paper.opacity(0.6) }
        return kind == .secondary ? SR.line : Color.white.opacity(0.18)
    }
}

// MARK: - Moments

/// Words that pop over the play for a moment — "Go fish!", "Hit!", "+3" —
/// and are read out to VoiceOver. `token` changes to pop it again; 0 shows
/// nothing. It ends by itself and never takes a touch.
struct NearbyPlayCallout: View {
    let text: String
    var icon: String? = nil
    var tone: Color = SR.accentDeep
    let token: Int
    var hold: Double = 1.4

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(SR.Text.display(22))
            }
            Text(text)
                .font(SR.Text.display(22))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(SR.paper)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Capsule().fill(tone))
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5) }
        .shadow(color: tone.opacity(0.4), radius: 14, x: 0, y: 6)
        .scaleEffect(shown || reduceMotion ? 1 : 0.6)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: token) {
            guard token > 0 else { return }
            let pop: Animation = reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.6)
            withAnimation(pop) { shown = true }
            NearbyPlayVoice.say(text)
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { shown = false }
        }
    }
}

/// A short burst of coloured flecks from the middle — a round won, a pair
/// found. Finite: about a second on one timeline that then stops. Never under
/// Reduce Motion.
struct NearbyPlayBurst: View {
    let token: Int
    var colours: [Color] = NearbyPlayBurst.defaultColours
    var duration: Double = 1.1
    var count: Int = 36

    @State private var start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var defaultColours: [Color] {
        var out = Array(SR.PersonHue.all.prefix(5))
        out.append(SR.accent)
        return out
    }

    var body: some View {
        Group {
            if let start, !reduceMotion {
                let palette = colours.isEmpty ? [SR.accent] : colours
                let length = duration
                let pieces = count
                TimelineView(NearbyPlayFiniteSchedule(end: start.addingTimeInterval(length), step: 1.0 / 60.0)) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSince(start)
                        NearbyPlayBurst.draw(in: &context, size: size, t: t, duration: length, count: pieces, colours: palette)
                    }
                }
            } else {
                Color.clear
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: token) {
            guard token > 0 else { return }
            start = Date()
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.15) * 1_000_000_000))
            if !Task.isCancelled { start = nil }
        }
    }

    /// Flecks fly out on the golden angle, slow, fall a little and fade.
    static func draw(in context: inout GraphicsContext, size: CGSize, t: Double, duration: Double,
                     count: Int, colours: [Color]) {
        guard t >= 0, t <= duration, !colours.isEmpty else { return }
        let p = t / duration
        let ease = 1 - (1 - p) * (1 - p)
        let reach = Double(min(size.width, size.height)) * 0.55
        let cx = Double(size.width) / 2
        let cy = Double(size.height) / 2
        for i in 0..<count {
            let angle = Double(i) * 2.399963
            let speed = 0.45 + 0.55 * (Double((i * 37) % 17) / 16.0)
            let x = cx + cos(angle) * reach * speed * ease
            let y = cy + sin(angle) * reach * speed * ease + 90 * t * t
            var piece = context
            piece.opacity = 1 - p
            piece.translateBy(x: CGFloat(x), y: CGFloat(y))
            piece.rotate(by: .radians(angle + t * 7))
            let side = CGFloat(6 + (i % 3) * 2)
            piece.fill(Path(CGRect(x: -side / 2, y: -side * 0.3, width: side, height: side * 0.6)),
                       with: .color(colours[i % colours.count]))
        }
    }
}

/// A short shake, for a wrong move: drive `animatableData` up by one with
/// a linear animation and the view shakes once.
struct NearbyPlayShake: GeometryEffect {
    var travel: CGFloat = 8
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes * 2), y: 0))
    }
}

/// A bump in size when `token` changes: a score ticking up, a card landing.
struct NearbyPlayBump: ViewModifier {
    let token: Int
    var scale: CGFloat = 1.14
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(up ? scale : 1)
            .onChange(of: token) { _, _ in
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.08)) { up = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { up = false }
                }
            }
    }
}

extension View {
    /// Bump when `token` changes.
    func nearbyPlayBump(_ token: Int, scale: CGFloat = 1.14) -> some View {
        modifier(NearbyPlayBump(token: token, scale: scale))
    }
}

// MARK: - The table

/// The cloth a card game is played on. Fixed colours, the same in light and
/// dark — a card table is green in a dark room too — so everything on it
/// uses `NearbyPlayFeltInk`, never the ground's tokens.
enum NearbyPlayFeltTone {
    /// Green baize: Whist, Higher or Lower.
    case baize
    /// A pond: Go Fish.
    case pond
    /// Plum velvet: Old Maid.
    case plum
    /// Midnight: Snap.
    case navy
    /// A tavern table: Liar's Dice.
    case tavern
    /// The sea: Sea Battle.
    case ocean
    /// A lawn: Whack-a-Mole.
    case lawn

    var glow: Color {
        switch self {
        case .baize: return Color(hex: 0x2F9A63)
        case .pond: return Color(hex: 0x2E8FCB)
        case .plum: return Color(hex: 0x9A4A86)
        case .navy: return Color(hex: 0x3C4FB4)
        case .tavern: return Color(hex: 0x9C6634)
        case .ocean: return Color(hex: 0x2289AE)
        case .lawn: return Color(hex: 0x6CC04A)
        }
    }

    var base: Color {
        switch self {
        case .baize: return Color(hex: 0x145A3B)
        case .pond: return Color(hex: 0x123F6E)
        case .plum: return Color(hex: 0x4A1840)
        case .navy: return Color(hex: 0x161E57)
        case .tavern: return Color(hex: 0x4A2A12)
        case .ocean: return Color(hex: 0x0B3A55)
        case .lawn: return Color(hex: 0x2E7A2A)
        }
    }

    var rim: Color {
        switch self {
        case .baize: return Color(hex: 0x0C3D27)
        case .pond: return Color(hex: 0x0B2A4C)
        case .plum: return Color(hex: 0x30102A)
        case .navy: return Color(hex: 0x0D1240)
        case .tavern: return Color(hex: 0x2E1909)
        case .ocean: return Color(hex: 0x072A3E)
        case .lawn: return Color(hex: 0x1D5419)
        }
    }
}

/// Type and marks on the felt: white at strengths, which holds on every tone.
enum NearbyPlayFeltInk {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.82)
    static let faint = Color.white.opacity(0.55)
    static let gold = Color(hex: 0xFFD166)
    static let chip = Color.black.opacity(0.24)
}

/// A felt panel with a soft light from above, a fine weave and a raised rim.
struct NearbyPlayFelt<Content: View>: View {
    var tone: NearbyPlayFeltTone = .baize
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    shape.fill(RadialGradient(colors: [tone.glow, tone.base], center: .top, startRadius: 8, endRadius: 460))
                    NearbyPlayWeave()
                        .equatable()
                        .clipShape(shape)
                    shape.strokeBorder(tone.rim, lineWidth: 3)
                    shape.inset(by: 7).stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
            }
            .shadow(color: tone.base.opacity(0.3), radius: 12, x: 0, y: 6)
    }
}

/// The weave: a fine lattice of dots, drawn once per size.
struct NearbyPlayWeave: View, Equatable {
    var body: some View {
        Canvas { context, size in
            var dots = Path()
            let step: CGFloat = 9
            var y: CGFloat = step / 2
            var row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? step / 2 : step
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                    x += step
                }
                y += step
                row += 1
            }
            context.fill(dots, with: .color(Color.white.opacity(0.06)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A speech bubble on the felt: the latest thing that happened.
struct NearbyPlayBubble: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(SR.Text.title(16))
                    .foregroundStyle(Color(hex: 0x3A3550))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(Color(hex: 0x1F1D2B))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0xFFFDF8)))
        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
        .accessibilityElement(children: .combine)
    }
}

/// A small figure in a capsule: "Pond 23", "Books 4/13".
struct NearbyPlayStat: View {
    let icon: String
    let text: String
    var onFelt: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(SR.Text.label(12))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.mono(13))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(onFelt ? NearbyPlayFeltInk.primary : SR.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(onFelt ? NearbyPlayFeltInk.chip : SR.ink.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The players

/// One player round the table, as the strip draws them.
struct NearbyPlaySeat: Identifiable, Equatable {
    let id: String
    let name: String
    let tone: Color
    var isMe: Bool = false
    /// Their move: a gold ring and a lift.
    var acting: Bool = false
    /// Knocked out, safe or gone: drawn faint.
    var faded: Bool = false
    /// A figure on the avatar: cards held, dice left.
    var badge: String? = nil
    /// The line under the name.
    var detail: String = ""
    /// A symbol beside the name: a crown, a flame.
    var mark: String? = nil
    var markTone: Color = NearbyPlayFeltInk.gold
    /// What VoiceOver says for the seat.
    var spoken: String = ""
}

/// Everyone at the table in one row, sharing the width equally, so five
/// players fit a 375pt phone with their names truncating, never the row.
struct NearbyPlaySeatStrip: View {
    let seats: [NearbyPlaySeat]
    var onFelt: Bool = true
    var avatar: CGFloat = 40

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(seats) { seat in
                NearbyPlaySeatChip(seat: seat, onFelt: onFelt, avatar: avatar)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct NearbyPlaySeatChip: View {
    let seat: NearbyPlaySeat
    let onFelt: Bool
    let avatar: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ring: Color { onFelt ? NearbyPlayFeltInk.gold : SR.accent }
    private var nameInk: Color { onFelt ? NearbyPlayFeltInk.primary : SR.ink }
    private var detailInk: Color { onFelt ? NearbyPlayFeltInk.secondary : SR.inkMuted }

    var body: some View {
        VStack(spacing: 3) {
            avatarView
            HStack(spacing: 3) {
                if let mark = seat.mark {
                    Image(systemName: mark)
                        .font(SR.Text.label(12))
                        .foregroundStyle(seat.markTone)
                        .accessibilityHidden(true)
                }
                Text(seat.isMe ? "You" : seat.name)
                    .font(SR.Text.label(12))
                    .foregroundStyle(seat.acting ? ring : nameInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
            }
            if !seat.detail.isEmpty {
                Text(seat.detail)
                    .font(SR.Text.mono(12))
                    .foregroundStyle(detailInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .opacity(seat.faded ? 0.5 : 1)
        .srAnimation(.snappy(duration: 0.25), value: seat.acting)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seat.spoken.isEmpty ? (seat.isMe ? "You" : seat.name) : seat.spoken)
    }

    private var avatarView: some View {
        ZStack(alignment: .topTrailing) {
            OfflineInitial(name: seat.name, size: avatar, tone: seat.faded ? Color.gray : seat.tone)
                .padding(4)
                .overlay {
                    Circle().strokeBorder(ring, lineWidth: seat.acting ? 3 : 0)
                }
                .scaleEffect(seat.acting && !reduceMotion ? 1.06 : 1)
                .shadow(color: seat.acting ? ring.opacity(0.55) : Color.clear, radius: 8, x: 0, y: 0)
            if let badge = seat.badge {
                Text(badge)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x1F1D2B))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Capsule().fill(Color(hex: 0xFFFDF8)))
                    .overlay { Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.75) }
                    .offset(x: 4, y: -2)
            }
        }
    }
}

/// A place in a disc — gold, silver, bronze, then plain; 0 is no place.
struct NearbyPlayPlaceDisc: View {
    let place: Int

    var body: some View {
        let colours = NearbyPlayPlaceDisc.colours(place)
        Text(place > 0 ? "\(place)" : "–")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(colours.ink)
            .frame(width: 26, height: 26)
            .background(Circle().fill(colours.fill))
            .accessibilityHidden(true)
    }

    static func colours(_ place: Int) -> (fill: Color, ink: Color) {
        switch place {
        case 1: return (Color(hex: 0xF2C14E), Color(hex: 0x4A3203))
        case 2: return (Color(hex: 0xC9CED8), Color(hex: 0x2C3140))
        case 3: return (Color(hex: 0xD99A6C), Color(hex: 0x3D1E08))
        default: return (SR.ink.opacity(0.1), SR.inkMuted)
        }
    }
}

// MARK: - Cards turning over

/// A card that turns face up with a flip when it changes, rather than
/// simply appearing.
struct NearbyPlayFlipCard: View {
    let card: OfflineCard?
    let width: CGFloat
    var selected: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let card {
                OfflineCardFace(card: card, width: width, selected: selected)
                    .id(card.id)
                    .transition(reduceMotion ? AnyTransition.opacity : NearbyPlayFlip.reveal)
            } else {
                OfflineCardBack(width: width)
                    .transition(AnyTransition.opacity)
            }
        }
        .frame(width: width, height: width * OfflineCardMetrics.aspect)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: card?.id)
    }
}

/// The turn of a card about its upright axis.
struct NearbyPlayFlipModifier: ViewModifier {
    let degrees: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(degrees), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .opacity(abs(degrees) >= 89 ? 0 : 1)
    }
}

enum NearbyPlayFlip {
    static var reveal: AnyTransition {
        AnyTransition.asymmetric(
            insertion: AnyTransition.modifier(active: NearbyPlayFlipModifier(degrees: -90),
                                              identity: NearbyPlayFlipModifier(degrees: 0)),
            removal: AnyTransition.opacity
        )
    }
}

// MARK: - Bests on this phone

/// The bests store as the views use it: a demo never writes.
enum NearbyPlayBestBook {
    static func best(_ gameId: String) -> Int? {
        NearbyPlayBestStore().best(gameId)?.value
    }

    static func record(_ gameId: String, value: Int, rule: NearbyPlayBestRule) -> NearbyPlayBestOutcome {
        if SRDemo.isOn {
            return NearbyPlayBestMath.merge(NearbyPlayBestStore().best(gameId), value: value, rule: rule).outcome
        }
        return NearbyPlayBestStore().record(gameId, value: value, rule: rule)
    }
}

/// "New best on this phone!" — or this phone's best beside today's figure.
struct NearbyPlayBestLine: View {
    let outcome: NearbyPlayBestOutcome
    /// Today's figure.
    let value: Int
    /// How a figure reads: "231 ms", "42 points".
    let format: (Int) -> String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: outcome.improved ? "trophy.fill" : "trophy")
                .font(SR.Text.display(24))
                .foregroundStyle(SR.warn)
                .symbolEffect(.bounce, value: outcome.beatAnOldBest)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(format(outcome.best))
                .font(SR.Text.figure(22))
                .foregroundStyle(outcome.beatAnOldBest ? SR.accent : SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        if outcome.beatAnOldBest { return "New best on this phone!" }
        if outcome.improved { return "Your first best on this phone" }
        return "Best on this phone"
    }

    private var detail: String {
        if outcome.beatAnOldBest, let previous = outcome.previous { return "Was \(format(previous))" }
        if outcome.improved { return "Now beat it" }
        return "This game: \(format(value))"
    }
}

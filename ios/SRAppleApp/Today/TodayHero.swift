import SwiftUI
import UIKit

// MARK: - First light
//
// Today opens on a short strip of live sky. The sun in it is the readiness
// ring — the three rings and the score for the owner, the Move ring for
// anybody else — and one tap on it is Health. Under it, a line for the day so
// far: when each of the family first went out, the stops of a trip running
// today, sunrise and sunset where the place is known, and a glowing dot for
// now. Press and drag along the line to scrub through the day.
//
// It replaces the Health door, not the family: the family card still comes
// next and still sits on the first screen. The hero is one fixed height
// (scaled with the text size, never with the data), so nothing under it ever
// moves when a figure arrives — a card that moved under the thumb is how the
// step board came to need three taps (TodayFirstTapTests).
//
// Nothing moves unless data changes or you touch it. The sky is re-read once
// a minute and only while Today is in front; there is no Canvas, no loop, no
// blur and no mesh gradient. The rules are `TodaySkyModel.swift`'s; this file
// only draws them.

/// Today's hero: gathers the inputs from the stores and redraws once a
/// minute, while it is being looked at.
struct TodayHero: View {
    let vitals: [TodayVital]
    let lead: TodayHeroLead
    let people: [TodayHeroInput.Person]
    /// How recently the site heard from each of them, by subject: the edge of
    /// their chip, as on the family card.
    var freshness: [String: FamilyPerson.Freshness] = [:]
    /// This phone's own last position, for where the sky is worked out.
    let selfFix: (lat: Double, lon: Double)?
    /// The trip's stops may be drawn: the site is paired and trips are this
    /// person's (the owner's, or the family's).
    let showsTrip: Bool
    let showsFamily: Bool
    /// Today is in front and the app is active: the minute tick runs.
    let live: Bool
    let openHealth: () -> Void
    let openFamily: () -> Void
    let openTripDay: (TripDayRef) -> Void

    /// The same store `TodayTripCard` watches, for the running day's stops.
    @ObservedObject private var trips = TripStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The sun comes up once a launch. Coming back to Today later, it is
    /// simply where it should be. Only ever touched on the main thread, by
    /// the hero's own views; `nonisolated(unsafe)` so the canvas's `@State`
    /// defaults can read it.
    nonisolated(unsafe) static var hasRisen = false
    /// How far the sky runs on under the family card.
    static let overhang: CGFloat = 48

    var body: some View {
        // Off screen or in the background the period is a day, which is as
        // good as still; both branches are the same schedule type.
        TimelineView(.periodic(from: .now, by: live ? 60 : 86_400)) { context in
            TodayHeroCanvas(
                model: TodayHeroModel.make(input(context.date)),
                vitals: vitals,
                lead: lead,
                freshness: freshness,
                live: live,
                folded: typeSize.isAccessibilitySize,
                showsFamily: showsFamily,
                openHealth: openHealth,
                openFamily: openFamily,
                openTripDay: openTripDay
            )
            .equatable()
        }
    }

    /// The model's inputs at an instant. The sky's clock is the real one
    /// moved by `SRDemo.clockShift` (zero outside the showcase); whether a
    /// trip is running, and how far through it you are, go by the real one.
    private func input(_ real: Date) -> TodayHeroInput {
        let now = real.addingTimeInterval(SRDemo.clockShift)
        let zone = TimeZone.current
        var tripDay: TodayHeroInput.TripDay?
        var tripPlace: TripLatLng?
        var tripZone: TimeZone?
        if showsTrip, let running = trips.running(now: real) {
            let id = running.bundle.trip.id
            let clock = TripClock(running.bundle.trip.timeZone)
            tripPlace = TripWeatherStore.place(running.bundle)
            tripZone = clock.zone
            if let day = trips.day(id, running.date) {
                let progress = trips.progress(id, running.date, now: real)
                let done = Set(progress?.doneStopIds ?? [])
                // Where you are: the stop you are at, or the one you are
                // heading for.
                let here: Int? = {
                    switch progress?.phase {
                    case .at(let i)?, .heading(let i)?: return i
                    default: return nil
                    }
                }()
                let stops = day.stops.enumerated().compactMap { index, stop -> TodayHeroInput.Stop? in
                    // By the wall clock: `TripClock.date` adds the minutes
                    // as elapsed time, an hour out on a clock-change day.
                    guard let at = TodayHeroModel.instant(running.date, minutes: stop.arriveMin, zone: clock.zone) else { return nil }
                    return TodayHeroInput.Stop(id: stop.id, title: stop.title, at: at.addingTimeInterval(SRDemo.clockShift),
                                               done: done.contains(stop.id), here: index == here)
                }
                tripDay = TodayHeroInput.TripDay(tripId: id, date: running.date, stops: stops)
            }
        }
        let place = TodaySky.place(selfFix: selfFix, trip: tripPlace, tripZone: tripZone, zone: zone, at: now)
        return TodayHeroInput(now: now, zone: zone, place: place.place, placeIsFix: place.isFix,
                              people: showsFamily ? people : [], trip: tripDay)
    }
}

// MARK: - The canvas

/// The sky, the sun and the horizon, drawn from one model.
///
/// Equatable on what it draws — the model, the rings, the lead, whether it
/// is live, whether it is folded, and the chips' edges — and never on the
/// closures, so a family or trip publish that leaves all of that alone does
/// not redraw it.
struct TodayHeroCanvas: View, Equatable {
    let model: TodayHeroModel
    let vitals: [TodayVital]
    let lead: TodayHeroLead
    var freshness: [String: FamilyPerson.Freshness] = [:]
    let live: Bool
    /// The accessibility text sizes: a static sun beside its figure, and the
    /// horizon under them.
    let folded: Bool
    let showsFamily: Bool
    let openHealth: () -> Void
    let openFamily: () -> Void
    let openTripDay: (TripDayRef) -> Void

    /// Everything is a share of this: `k = heroHeight / 164`.
    @ScaledMetric(relativeTo: .body) private var heroHeight: CGFloat = 164
    /// One character of the bubble's mono face, for keeping it on screen.
    @ScaledMetric(relativeTo: .caption) private var charWidth: CGFloat = 7.2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 with the sun on the horizon at five in the morning, 1 where it is.
    @State private var risen: Double = TodayHero.hasRisen ? 1 : 0
    /// The hero's own opacity: a fade in under Reduce Motion, instead of the rise.
    @State private var shown: Double = TodayHero.hasRisen ? 1 : 0
    /// Where a finger is along the horizon, once a press has turned into a
    /// scrub. Back to nil, and the sun back to now, when it lifts.
    @GestureState(resetTransaction: Transaction(animation: SRMotion.settle)) private var scrubX: CGFloat? = nil
    /// The marker the scrub last landed near, so the tick fires on a new one.
    @State private var scrubMarker: String?
    /// VoiceOver's place on the horizon (`accessibilityAdjustableAction`).
    @State private var focus: Int?

    /// The horizon's inset from each edge: the gutter, and room for half a chip.
    static let inset: CGFloat = SR.gutter + 11

    nonisolated static func == (a: TodayHeroCanvas, b: TodayHeroCanvas) -> Bool {
        a.model == b.model && a.vitals == b.vitals && a.lead == b.lead && a.live == b.live
            && a.folded == b.folded && a.showsFamily == b.showsFamily && a.freshness == b.freshness
    }

    /// x of a point along the horizon.
    static func x(_ frac: Double, width: CGFloat) -> CGFloat {
        inset + CGFloat(max(0, min(1, frac))) * max(0, width - 2 * inset)
    }

    /// The point along the horizon under an x.
    static func frac(atX x: CGFloat, width: CGFloat) -> Double {
        let span = width - 2 * inset
        guard span > 0 else { return 0 }
        return Double(max(0, min(1, (x - inset) / span)))
    }

    var body: some View {
        let k = heroHeight / 164
        Group {
            if folded { foldedBody } else { fullBody(k) }
        }
        .opacity(shown)
        .onAppear(perform: rise)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-hero")
    }

    /// The sun at its moment, or at the scrubbed one.
    private struct Moment {
        let frac: Double
        let lift: Double
        let sky: SkyLayers
    }

    private func moment(width: CGFloat) -> Moment {
        guard let scrubX else {
            return Moment(frac: model.nowFrac * risen, lift: model.lift * risen, sky: model.sky)
        }
        let frac = Self.frac(atX: scrubX, width: width)
        let minute = Self.minute(frac)
        return Moment(frac: frac, lift: TodaySky.lift(minute: minute, sun: model.sun),
                      sky: TodaySky.layers(minute: minute, sun: model.sun))
    }

    private static func minute(_ frac: Double) -> Double {
        TodaySky.windowStartMin + frac * (TodaySky.windowEndMin - TodaySky.windowStartMin)
    }

    private static func clock(_ minute: Double) -> String {
        let m = Int(minute.rounded(.down))
        let wrapped = ((m % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }

    // MARK: Layouts

    private func fullBody(_ k: CGFloat) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let now = moment(width: w)
            let d = 88 * k
            let sunX = min(max(Self.x(now.frac, width: w), Self.inset + d / 2), max(Self.inset + d / 2, w - Self.inset - d / 2))
            // 72k on the horizon, 50k at its highest.
            let sunY = 72 * k - 22 * k * CGFloat(now.lift)
            ZStack(alignment: .topLeading) {
                horizonBand(width: w, lineY: 20 * k, compact: false)
                    .frame(width: w, height: 44 * k)
                    .position(x: w / 2, y: 142 * k)

                if !lead.word.isEmpty {
                    tag(sunX: sunX, sunY: sunY, diameter: d, width: w)
                        .transaction { if reduceMotion { $0.animation = nil } }
                        .srAnimation(SRMotion.tick, value: model.minuteKey)
                }

                sunButton(diameter: d, showsFigure: true)
                    .position(x: sunX, y: sunY)
                    .transaction { if reduceMotion { $0.animation = nil } }
                    .srAnimation(SRMotion.tick, value: model.minuteKey)

                if let scrubX {
                    bubble(atX: scrubX, width: w)
                        .position(x: bubbleX(scrubX, width: w), y: 106 * k)
                }
            }
            .frame(width: w, height: geo.size.height)
            .background(alignment: .top) {
                sky(now.sky, sunX: sunX, sunFromBottom: heroHeight + TodayHero.overhang - sunY)
                    .padding(.bottom, -TodayHero.overhang)
            }
        }
        .frame(height: heroHeight)
    }

    /// The accessibility sizes: no arc to ride, so the sun stands still
    /// beside its figure and word, and the horizon runs under both.
    private var foldedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                sunButton(diameter: 64, showsFigure: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lead.figure)
                        .font(SR.Text.figure())
                        .monospacedDigit()
                        .foregroundStyle(SR.ink)
                        .srNumeric(lead.figureValue)
                    if !lead.word.isEmpty {
                        Text(lead.word.uppercased())
                            .font(SR.Text.label())
                            .tracking(1.2)
                            .foregroundStyle(SR.inkSecondary)
                    }
                }
                // The sun's own label already says both.
                .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 12)

            GeometryReader { geo in
                ZStack {
                    horizonBand(width: geo.size.width, lineY: 22, compact: true)
                    if let scrubX {
                        bubble(atX: scrubX, width: geo.size.width)
                            .position(x: bubbleX(scrubX, width: geo.size.width), y: -14)
                    }
                }
            }
            .frame(height: 44)
        }
        .background(alignment: .top) {
            GeometryReader { geo in
                let now = moment(width: geo.size.width)
                sky(now.sky, sunX: SR.gutter + 32, sunFromBottom: geo.size.height + TodayHero.overhang - 44)
                    .padding(.bottom, -TodayHero.overhang)
            }
        }
    }

    // MARK: Parts

    private func sky(_ layers: SkyLayers, sunX: CGFloat, sunFromBottom: CGFloat) -> some View {
        let reduce = reduceMotion
        return TodaySkyView(sky: layers, sunX: sunX, sunFromBottom: sunFromBottom)
            .transaction { if reduce { $0.animation = nil } }
            .srAnimation(SRMotion.tick, value: model.minuteKey)
            // Parallax on the sky alone, never on anything you press: as the
            // page scrolls up, the sky follows at under half the speed.
            .visualEffect { content, proxy in
                content.offset(y: reduce ? 0 : max(0, -proxy.frame(in: .scrollView).minY) * 0.4)
            }
    }

    /// The word beside the sun, on whichever side has the room: trailing
    /// while the sun is in the morning half, leading after.
    private func tag(sunX: CGFloat, sunY: CGFloat, diameter: CGFloat, width: CGFloat) -> some View {
        let trailing = sunX < width / 2
        return HStack(spacing: 0) {
            if trailing {
                Color.clear.frame(width: max(0, sunX + diameter / 2 + 10))
                TodaySunTag(word: lead.word)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                TodaySunTag(word: lead.word)
                Color.clear.frame(width: max(0, width - (sunX - diameter / 2 - 10)))
            }
        }
        .frame(width: width)
        .position(x: width / 2, y: sunY)
    }

    /// The sun: one button into Health, and a long press for the day's
    /// figures.
    private func sunButton(diameter: CGFloat, showsFigure: Bool) -> some View {
        Button(action: openHealth) {
            TodaySun(lead: lead, vitals: vitals, diameter: diameter, progress: risen,
                     dusk: model.sky.petrol > 0.2, showsFigure: showsFigure)
        }
        .buttonStyle(SRPressStyle())
        .contentShape(Circle())
        .contextMenu {
            Button("Open Health", systemImage: "heart") { openHealth() }
            if showsFamily {
                Button("Open Family", systemImage: "person.2") { openFamily() }
            }
        } preview: {
            TodayHeroPeek(lead: lead)
        }
        .accessibilityLabel("Health. " + lead.spoken)
        .accessibilityHint("Opens Health")
        .accessibilityAction(named: "Today's figures") {
            UIAccessibility.post(notification: .announcement, argument: TodayHeroPeek.spoken(lead))
        }
        .accessibilityIdentifier("today-health")
    }

    /// The line, with its tap, its scrub and its VoiceOver.
    private func horizonBand(width: CGFloat, lineY: CGFloat, compact: Bool) -> some View {
        TodayHorizon(markers: model.markers, nowFrac: model.nowFrac, freshness: freshness,
                     lineY: lineY, compact: compact)
            .contentShape(Rectangle())
            .gesture(scrub)
            .onTapGesture(count: 1, coordinateSpace: .local) { location in
                tap(atX: location.x, width: width)
            }
            .onChange(of: scrubX) { old, new in
                scrubbed(from: old, to: new, width: width)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today so far")
            .accessibilityValue(spokenValue)
            .accessibilityAdjustableAction { direction in
                step(direction)
            }
            .accessibilityAction {
                defaultAction()
            }
            .accessibilityIdentifier("today-horizon")
    }

    private func bubble(atX x: CGFloat, width: CGFloat) -> some View {
        let minute = Self.minute(Self.frac(atX: x, width: width))
        let near = nearest(toMinute: minute)
        return TodayScrubBubble(text: Self.clock(minute) + (near.map { " · \($0.short)" } ?? ""))
    }

    /// The bubble's centre: on the finger, kept inside the gutters.
    private func bubbleX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let minute = Self.minute(Self.frac(atX: x, width: width))
        let text = Self.clock(minute) + (nearest(toMinute: minute).map { " · \($0.short)" } ?? "")
        let half = CGFloat(text.count) * charWidth / 2 + 12
        let low = SR.gutter + half
        let high = width - SR.gutter - half
        return high > low ? min(max(x, low), high) : width / 2
    }

    // MARK: Touch

    /// Hold for a moment, then drag: a plain swipe that starts on the line
    /// still scrolls the page.
    private var scrub: some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($scrubX) { value, state, transaction in
                guard case .second(true, let drag?) = value else { return }
                // The sun follows the finger with no ease.
                transaction.animation = nil
                state = drag.location.x
            }
    }

    /// A tick when the press turns into a scrub, and one each time the scrub
    /// lands near a marker it was not near before. Never on movement alone.
    private func scrubbed(from old: CGFloat?, to new: CGFloat?, width: CGFloat) {
        guard let new else {
            scrubMarker = nil
            return
        }
        let near = nearest(toMinute: Self.minute(Self.frac(atX: new, width: width)))?.id
        if old == nil {
            SRHaptic.select()
        } else if let near, near != scrubMarker {
            SRHaptic.select()
        }
        if let near { scrubMarker = near }
    }

    /// The marker within twenty minutes of a minute, nearest first.
    private func nearest(toMinute minute: Double) -> HorizonMarker? {
        model.markers
            .map { ($0, abs(Self.minute($0.frac) - minute)) }
            .filter { $0.1 <= 20 }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// A tap goes to the nearest marker within 22pt of it; anywhere else on
    /// the line, to the family.
    private func tap(atX x: CGFloat, width: CGFloat) {
        let hit = model.markers
            .filter { $0.target != HorizonMarker.Target.none }
            .map { ($0, abs(Self.x($0.frac, width: width) - x)) }
            .filter { $0.1 <= 22 }
            .min { $0.1 < $1.1 }?
            .0
        if let hit {
            SRHaptic.tap()
            open(hit.target)
        } else if showsFamily {
            SRHaptic.tap()
            openFamily()
        }
    }

    private func open(_ target: HorizonMarker.Target) {
        switch target {
        case .family:
            openFamily()
        case .tripDay(let tripId, let date):
            openTripDay(TripDayRef(tripId: tripId, date: date))
        case .none:
            if showsFamily { openFamily() }
        }
    }

    // MARK: VoiceOver

    /// "Now 10:40", or the marker VoiceOver has stepped to.
    private var spokenValue: String {
        if let focus, model.markers.indices.contains(focus) { return model.markers[focus].spoken }
        return "Now " + Self.clock(Double(model.minuteKey))
    }

    private func step(_ direction: AccessibilityAdjustmentDirection) {
        guard !model.markers.isEmpty else { return }
        switch direction {
        case .increment:
            focus = min((focus ?? -1) + 1, model.markers.count - 1)
        case .decrement:
            focus = max((focus ?? model.markers.count) - 1, 0)
        @unknown default:
            break
        }
    }

    /// The marker stepped to, if it goes anywhere; else the family, or the
    /// trip's day when there is no family to open.
    private func defaultAction() {
        if let focus, model.markers.indices.contains(focus), model.markers[focus].target != HorizonMarker.Target.none {
            open(model.markers[focus].target)
        } else if showsFamily {
            openFamily()
        } else if let trip = model.markers.first(where: { if case .tripDay = $0.target { return true } else { return false } }) {
            open(trip.target)
        }
    }

    // MARK: Sunrise

    /// The first Today of a launch: the sun climbs from the horizon at five
    /// in the morning to where it is, and the rings sweep in behind it.
    /// Under Reduce Motion it is simply there, and the hero fades in.
    private func rise() {
        guard !TodayHero.hasRisen else { return }
        TodayHero.hasRisen = true
        if reduceMotion {
            risen = 1
            withAnimation(SRMotion.fadeIn) { shown = 1 }
        } else {
            shown = 1
            withAnimation(SRMotion.rise) { risen = 1 }
        }
    }
}

// MARK: - The sky

/// The sky itself: five SR tokens, each a gradient at the strength the model
/// gives it, over the page's grain. Opacity and position are all that ever
/// change, so it animates on any OS the app runs on and never mixes a colour.
///
/// Positions are measured from its bottom edge, which is fixed — the top may
/// run up under a glass bar on iOS 26.
struct TodaySkyView: View {
    let sky: SkyLayers
    let sunX: CGFloat
    /// The sun's centre, up from the sky's bottom edge.
    let sunFromBottom: CGFloat

    /// On iOS 26 the bar is glass and the sky runs on under it. Before, the
    /// bar is opaque paper with a hairline, and the sky fades in below it.
    private static var underGlassBar: Bool {
        if #available(iOS 26.0, *) { return true } else { return false }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let sunY = h - sunFromBottom
            ZStack {
                LinearGradient(colors: [SR.accentInk, SR.accentInk.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .opacity(sky.petrol)
                LinearGradient(stops: [.init(color: SR.ink, location: 0), .init(color: SR.ink.opacity(0), location: 0.7)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(sky.ink)
                glow(SR.accentDeep, radius: w * 0.8)
                    .position(x: sunX, y: h - TodayHero.overhang)
                    .opacity(sky.deep)
                glow(SR.accent, radius: w * 0.7)
                    .position(x: sunX, y: sunY)
                    .opacity(sky.accent)
                glow(SR.warn, radius: w * 0.45)
                    .position(x: sunX, y: sunY)
                    .opacity(sky.warm)
                SRGrain(opacity: 0.035)
            }
            .frame(width: w, height: h)
            .mask { fade(height: h) }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .modifier(UnderGlassBar(enabled: Self.underGlassBar))
    }

    /// A round glow, drawn once and moved by position, so it can travel
    /// with the sun.
    private func glow(_ color: Color, radius: CGFloat) -> some View {
        RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
    }

    /// Opaque to 60% of the way down, then fading out over the cards. Under
    /// an opaque bar it also fades in over its first 12pt, so the sky meets
    /// the paper rather than butting against it.
    private func fade(height: CGFloat) -> some View {
        let top = Self.underGlassBar ? 0 : min(0.3, 12 / max(height, 1))
        return LinearGradient(
            stops: [
                .init(color: .black.opacity(top > 0 ? 0 : 1), location: 0),
                .init(color: .black, location: top),
                .init(color: .black, location: 0.6),
                .init(color: .black.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private struct UnderGlassBar: ViewModifier {
        let enabled: Bool

        @ViewBuilder
        func body(content: Content) -> some View {
            if enabled {
                content.ignoresSafeArea(edges: .top)
            } else {
                content
            }
        }
    }
}

// MARK: - The sun

/// The sun's face: glass, a glow in the readiness band's colour, the rings,
/// and the figure in the middle.
struct TodaySun: View {
    let lead: TodayHeroLead
    let vitals: [TodayVital]
    let diameter: CGFloat
    /// The rings' sunrise sweep.
    let progress: Double
    /// Petrol is up: the band's glow halves, or it reads as a lamp at night.
    let dusk: Bool
    var showsFigure = true

    var body: some View {
        let side = diameter - 8
        let lineScale: CGFloat = vitals.count >= 3 ? 0.075 : 0.10
        let hole = TodayRings.hole(side: side, count: vitals.count, lineScale: lineScale)
        ZStack {
            Color.clear
                .srGlass(.paper, in: Circle(), interactive: true)
            Circle()
                .fill(RadialGradient(colors: [lead.bandTint.opacity(0.35 * (dusk ? 0.5 : 1)), lead.bandTint.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: diameter / 2))
            TodayRings(vitals: vitals, progress: progress, lineScale: lineScale, stagger: true,
                       dimmed: lead.stale ? ["recovery", "readiness"] : [])
                .frame(width: side, height: side)
            if showsFigure {
                figure
                    .frame(width: hole * 0.92, height: hole * 0.92)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
    }

    /// The biggest of three sizes that fits the hole — never squashed.
    private var figure: some View {
        ViewThatFits {
            Text(lead.figure).font(SR.Text.figure(24)).monospacedDigit()
            Text(lead.figure).font(SR.Text.figure(20)).monospacedDigit()
            Text(lead.figure).font(SR.Text.label()).monospacedDigit()
        }
        .lineLimit(1)
        .foregroundStyle(SR.ink)
        .srNumeric(lead.figureValue)
    }
}

/// The word that rides beside the sun: PRIMED, MOVE.
struct TodaySunTag: View {
    let word: String

    var body: some View {
        Text(word.uppercased())
            .font(SR.Text.label())
            .tracking(1.2)
            .foregroundStyle(SR.inkSecondary)
            .fixedSize()
            .accessibilityHidden(true)
    }
}

// MARK: - The horizon

/// The day so far as a line: done in ink, to come in a hairline, now a
/// glowing dot. On it, the family's first times out, the trip's stops, and
/// sunrise and sunset above it.
struct TodayHorizon: View {
    let markers: [HorizonMarker]
    let nowFrac: Double
    let freshness: [String: FamilyPerson.Freshness]
    /// Where the line runs, down from the band's top.
    let lineY: CGFloat
    /// The accessibility sizes: people as dots, no initials.
    let compact: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let start = TodayHeroCanvas.inset
            let end = max(start, w - TodayHeroCanvas.inset)
            let nowX = TodayHeroCanvas.x(nowFrac, width: w)
            ZStack {
                Rectangle()
                    .fill(SR.inkSecondary.opacity(0.5))
                    .frame(width: max(0, nowX - start), height: 1.5)
                    .position(x: (start + nowX) / 2, y: lineY)
                Rectangle()
                    .fill(SR.line)
                    .frame(width: max(0, end - nowX), height: 1)
                    .position(x: (nowX + end) / 2, y: lineY)
                ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                    mark(marker)
                        .position(x: TodayHeroCanvas.x(marker.frac, width: w), y: y(marker))
                        // Chips that meet overlap as the family card's do:
                        // the earlier on top. Stops and the sun's glyphs sit
                        // under any chip.
                        .zIndex(isPerson(marker) ? Double(markers.count - index) + 10 : 1)
                }
                // The one live dot with a glow.
                Circle()
                    .fill(SR.accent)
                    .frame(width: 8, height: 8)
                    .shadow(color: SR.accent.opacity(0.5), radius: 5)
                    .position(x: nowX, y: lineY)
                    .zIndex(100)
            }
            .frame(width: w, height: geo.size.height)
        }
    }

    private func isPerson(_ marker: HorizonMarker) -> Bool {
        if case .person = marker.kind { return true }
        return false
    }

    private func y(_ marker: HorizonMarker) -> CGFloat {
        switch marker.kind {
        case .sunrise, .sunset: return lineY - 10 - 6
        default: return lineY
        }
    }

    @ViewBuilder
    private func mark(_ marker: HorizonMarker) -> some View {
        switch marker.kind {
        case .person(let initials, let out, let subject):
            let edge = TodayFamilyCard.edge(freshness[subject] ?? .unknown)
            if compact {
                Circle()
                    .fill(out ? SR.ink : SR.surface)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(edge, lineWidth: 1.5))
            } else {
                Text(initials)
                    .font(SR.Text.label(12))
                    .foregroundStyle(out ? SR.paper : SR.inkMuted)
                    .lineLimit(1)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(out ? SR.ink : SR.surface))
                    .overlay(Circle().strokeBorder(edge, lineWidth: 1.5))
            }
        case .stop(let done, let here):
            if here {
                Circle()
                    .fill(SR.accent)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(SR.paper, lineWidth: 2))
            } else if done {
                Circle()
                    .fill(SR.accentInk)
                    .frame(width: 7, height: 7)
            } else {
                Circle()
                    .strokeBorder(SR.accentInk, lineWidth: 1.5)
                    .frame(width: 7, height: 7)
            }
        case .sunrise:
            Image(systemName: "sunrise.fill")
                .font(.system(size: 11))
                .foregroundStyle(SR.inkGhost)
        case .sunset:
            Image(systemName: "sunset.fill")
                .font(.system(size: 11))
                .foregroundStyle(SR.inkGhost)
        }
    }
}

/// The time under a scrubbing finger, and what is there: "14:20 · Sam out".
struct TodayScrubBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SR.Text.label())
            .foregroundStyle(SR.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 28)
            .srGlass(.paper, in: Capsule())
            .accessibilityIdentifier("today-scrub-bubble")
    }
}

// MARK: - The long press

/// What a long press on the sun shows: the owner's figures — readiness and
/// its word, then resting heart rate, HRV, sleep and steps where measured,
/// and the verdict's advice — or, for anybody else, the Move ring and no
/// more. The figures live here and in Health, never on Today's face.
struct TodayHeroPeek: View {
    let lead: TodayHeroLead

    /// Which figures, in which order.
    static let keys = ["rhr", "hrv", "sleep", "steps"]

    static func cells(_ lead: TodayHeroLead) -> [HealthFigure] {
        keys.compactMap { key in lead.figures.first { $0.key == key && $0.measured } }
    }

    /// The same, read out by the sun's "Today's figures" action.
    static func spoken(_ lead: TodayHeroLead) -> String {
        guard lead.ownerSite else {
            return "Move \(lead.figure)" + (lead.moveDetail.map { ", \($0)" } ?? "")
        }
        var parts = ["Readiness \(lead.figure)" + (lead.word.isEmpty ? "" : ", \(lead.word)")]
        parts += cells(lead).map { "\($0.label) \($0.displayWithUnit)" + ($0.deltaDisplay.map { ", \($0)" } ?? "") }
        if let advice = lead.recommendation, !advice.isEmpty { parts.append(advice) }
        return parts.joined(separator: ". ")
    }

    var body: some View {
        Group {
            if lead.ownerSite { owner } else { member }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(SR.paper)
    }

    private var owner: some View {
        let cells = Self.cells(lead)
        let rows = stride(from: 0, to: cells.count, by: 2).map { Array(cells[$0..<min($0 + 2, cells.count)]) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(lead.figure)
                    .font(SR.Text.figure())
                    .monospacedDigit()
                    .foregroundStyle(SR.ink)
                if !lead.word.isEmpty {
                    Text(lead.word.uppercased())
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.inkSecondary)
                }
            }
            if !rows.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(row) { figure in
                                cell(figure)
                            }
                        }
                    }
                }
            }
            if let advice = lead.recommendation, !advice.isEmpty {
                Text(advice)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .lineLimit(3)
            }
        }
    }

    private func cell(_ figure: HealthFigure) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(figure.label)
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
            Text(figure.displayWithUnit)
                .font(SR.Text.figure(22))
                .foregroundStyle(SR.ink)
            if let delta = figure.deltaDisplay {
                Text(delta)
                    .font(SR.Text.label())
                    .foregroundStyle(figure.improving == true ? SR.good : SR.inkMuted)
            }
        }
    }

    private var member: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Move".uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkSecondary)
            Text(lead.figure)
                .font(SR.Text.figure())
                .monospacedDigit()
                .foregroundStyle(SR.ink)
            if let detail = lead.moveDetail {
                Text(detail)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
            }
        }
    }
}

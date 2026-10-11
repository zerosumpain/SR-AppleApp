import SwiftUI
import UIKit

/// The valley, drawn as the site's notes chapter draws it: pencil on the
/// page rather than a game's map pasted onto it.
///
/// Three layers, so a pinch costs almost nothing:
///
/// 1. **The ground** is one picture, made once per terrain version and colour
///    scheme (`WildmindRaster`, off the main thread) and scaled by the
///    compositor as the reader zooms. Unseen cells are clear, so what nobody
///    has explored is the page's own ruled paper.
/// 2. **The pen** — the coast in petrol, the dashed edge of the known, trails,
///    huts, fires, animals, the two people, place names — is a `Canvas` over
///    it, redrawn as the view moves. It is a few hundred strokes at most.
/// 3. **The frame** — the double neat line, the moon, the day's stamp — stays
///    put whatever the map does.
///
/// Pinch to zoom (up to six times), drag to pan once zoomed; at the whole
/// valley a drag scrolls the page as usual. Tapping a person pins their card
/// under the map (the screen's job; this view only reports the choice).
struct WildmindMap: View {
    let snapshot: WildmindSnapshot
    let grid: WildmindGrid
    let state: WildmindState
    @Binding var selected: String?

    @Environment(\.colorScheme) private var scheme
    @State private var picture: CGImage?
    @State private var lines = WildmindLines()
    @State private var zoom: CGFloat = 1
    @State private var zoomAtStart: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panAtStart: CGSize = .zero

    private var shape: WildmindMapShape { WildmindMapShape(w: grid.w, h: grid.h) }

    /// The picture's cache key: a new version, a new size or the other
    /// scheme is a new picture; a poll that changed nobody's ground is not.
    private var pictureKey: String {
        "\(grid.version)|\(grid.w)x\(grid.h)|\(scheme == .dark ? "night" : "day")"
    }

    var body: some View {
        // The frame takes the map's own proportions at the column's width,
        // between nine and seventeen rules tall, as the site's phone frame is.
        Color.clear
            .aspectRatio(CGFloat(max(1, shape.width)) / CGFloat(max(1, shape.height)), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 288, maxHeight: 544)
            .overlay {
                GeometryReader { geometry in
                    map(in: geometry.size)
                }
            }
            // Room for the stamp, which hangs over the frame's foot.
            .padding(.bottom, 26)
            .task(id: pictureKey) { await draw() }
    }

    // MARK: - The map

    private func layout(_ size: CGSize, zoom: CGFloat? = nil, pan: CGSize? = nil) -> WildmindMapLayout {
        WildmindMapLayout(size: size, shape: shape, zoom: zoom ?? self.zoom, pan: pan ?? self.pan)
    }

    @ViewBuilder
    private func map(in size: CGSize) -> some View {
        let plan = layout(size)
        let zoomed = zoom > 1.01
        ZStack(alignment: .topLeading) {
            if let picture {
                Image(decorative: picture, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .overlay {
                        // Night over the seen ground only: petrol, faint.
                        SR.accentInk.opacity(snapshot.time.night * 0.11)
                            .mask { Image(decorative: picture, scale: 1).resizable() }
                    }
                    .frame(width: plan.mapSize.width, height: plan.mapSize.height)
                    .position(plan.mapCentre)
                    .accessibilityHidden(true)
            }

            Canvas { context, canvasSize in
                drawPen(in: &context, layout: self.layout(canvasSize))
            }
            .contentShape(Rectangle())
            .onTapGesture { selected = nil }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WildmindWords.mapSummary(snapshot, state: state, places: placeNames))
            .accessibilityAddTraits(.isImage)

            ForEach(snapshot.people) { person in
                personButton(person, layout: plan)
            }

            if zoomed {
                Button {
                    SRHaptic.tap()
                    withAnimation(.easeOut(duration: 0.25)) {
                        zoom = 1
                        zoomAtStart = 1
                        pan = .zero
                        panAtStart = .zero
                    }
                } label: {
                    Text("WHOLE VALLEY")
                        .font(SR.Text.kicker())
                        .tracking(SR.Notes.stampTracking)
                        .foregroundStyle(SR.accentInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(SR.paper)
                        .overlay {
                            SRStampBox(seed: 627).stroke(SR.accentInk.opacity(0.75), style: .ink(1.3))
                        }
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .position(x: plan.inner.minX + 62, y: plan.inner.minY + 26)
                .accessibilityLabel("Show the whole valley")
                .accessibilityIdentifier("wildmind-map-reset")
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(Rectangle().inset(by: 7))
        .overlay { neatLine.accessibilityHidden(true) }
        .overlay(alignment: .topTrailing) {
            if snapshot.time.isNight && state != .offline {
                SRMoonDoodle(width: 48).padding(.top, 18).padding(.trailing, 22)
            }
        }
        .overlay(alignment: .bottomTrailing) { stamp }
        .gesture(dragGesture(size), including: zoomed ? .all : .subviews)
        .simultaneousGesture(magnifyGesture(size))
    }

    private func dragGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let wanted = CGSize(width: panAtStart.width + value.translation.width,
                                    height: panAtStart.height + value.translation.height)
                pan = layout(size).clamp(wanted)
            }
            .onEnded { _ in panAtStart = pan }
    }

    private func magnifyGesture(_ size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(6, max(1, zoomAtStart * value.magnification))
                pan = layout(size).clamp(pan)
            }
            .onEnded { _ in
                zoomAtStart = zoom
                panAtStart = pan
            }
    }

    /// The person's tap target: 44 points round the disc, read as their tag.
    @ViewBuilder
    private func personButton(_ person: WildmindPerson, layout: WildmindMapLayout) -> some View {
        let cell = grid.cell(x: person.x, z: person.z)
        let point = layout.point(cell.x, cell.y)
        if layout.inner.contains(point) {
            Button {
                SRHaptic.select()
                selected = selected == person.id ? nil : person.id
            } label: {
                Color.clear
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .position(point)
            .accessibilityLabel(WildmindWords.tag(person, pastTense: state.pastTense))
            .accessibilityHint("Shows their card under the map")
            .accessibilityAddTraits(selected == person.id ? .isSelected : [])
            .accessibilityIdentifier("wildmind-person-\(person.id)")
        }
    }

    // MARK: - The frame

    /// The double neat line (`inkLine(r, 0, 4, 1000, 4, .5, .0012)`, seeds
    /// 611 on): outer at the edge in ink, inner six points in, finer.
    private var neatLine: some View {
        Canvas { context, size in
            for (ring, inset, width, tone) in [(0, CGFloat(1), CGFloat(1.6), SR.ink), (1, CGFloat(7), CGFloat(0.8), SR.inkSecondary)] {
                let w = size.width
                let h = size.height
                let corners = [
                    CGPoint(x: inset, y: inset), CGPoint(x: w - inset, y: inset),
                    CGPoint(x: w - inset, y: h - inset), CGPoint(x: inset, y: h - inset),
                ]
                var path = Path()
                for side in 0..<4 {
                    let a = corners[side]
                    let b = corners[(side + 1) % 4]
                    let length = hypot(b.x - a.x, b.y - a.y)
                    guard length > 0 else { continue }
                    var r = InkRNG(611 + ring * 4 + side)
                    let stroke = InkGeometry.line(&r, 0, 4, 1000, 4, amp: 0.5, bow: 0.0012)
                    let place = CGAffineTransform(translationX: 0, y: -4)
                        .concatenating(CGAffineTransform(scaleX: length / 1000, y: 1))
                        .concatenating(CGAffineTransform(rotationAngle: atan2(b.y - a.y, b.x - a.x)))
                        .concatenating(CGAffineTransform(translationX: a.x, y: a.y))
                    path.addPath(Path(ink: [stroke]).applying(place))
                }
                context.stroke(path, with: .color(tone), style: .ink(width))
            }
        }
        .allowsHitTesting(false)
    }

    /// "DAY 5 / SPRING" across the frame's foot, tilted, on its own paper —
    /// faded when the valley has stopped answering.
    @ViewBuilder
    private var stamp: some View {
        let text = state == .betweenLives ? "Between" : (snapshot.time.day.map { "Day \($0)" } ?? "Day \u{2014}")
        let sub = state == .betweenLives ? "lives" : WildmindWords.stampSub(state, time: snapshot.time)
        SRDateStamp(text: text, sub: sub, seed: 621, mono: true)
            .opacity(state == .stale || state == .offline ? 0.6 : 0.88)
            .padding(.trailing, 24)
            .offset(y: 26)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - The pen

    private var placeNames: [String] {
        grid.regions.sorted { ($0.isLandmark ? 0 : 1) < ($1.isLandmark ? 0 : 1) }.map(\.name)
    }

    private func colour(for person: WildmindPerson) -> Color {
        person.isMain ? SR.accent : person.id == "companion" ? SR.accentInk : SR.Notes.ochre
    }

    private func drawPen(in context: inout GraphicsContext, layout: WildmindMapLayout) {
        let m = layout.mark

        // Coast and the edge of the known.
        var coast = Path()
        for s in lines.coast {
            coast.move(to: layout.point(s.x0, s.y0))
            coast.addLine(to: layout.point(s.x1, s.y1))
        }
        context.stroke(coast, with: .color(SR.accentInk), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        var edge = Path()
        for s in lines.edge {
            edge.move(to: layout.point(s.x0, s.y0))
            edge.addLine(to: layout.point(s.x1, s.y1))
        }
        context.stroke(edge, with: .color(SR.inkMuted), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))

        // Animals: small muted dots, a wolf a little larger.
        for animal in snapshot.animals {
            let c = grid.cell(x: animal.x, z: animal.z)
            let p = layout.point(c.x, c.y)
            let wolf = animal.species < snapshot.species.count && snapshot.species[animal.species] == "wolf"
            let r = (wolf ? 0.6 : 0.45) * m
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(SR.inkMuted.opacity(animal.tame ? 1 : 0.85)))
        }

        // Structures: the glow of a lit one first, then the hut itself.
        for structure in snapshot.structures where structure.lit {
            let c = grid.cell(x: structure.x, z: structure.z)
            let p = layout.point(c.x, c.y)
            let r = 3 * m
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [SR.accent.opacity(0.4), SR.accent.opacity(0)]),
                                               center: p, startRadius: 0, endRadius: r))
        }
        for structure in snapshot.structures where structure.kind != .fire {
            let c = grid.cell(x: structure.x, z: structure.z)
            let p = layout.point(c.x, c.y)
            let side = 1.2 * m
            let square = Path(CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side))
            let tone = SR.inkSecondary.opacity(structure.complete ? 1 : 0.5)
            if structure.kind == .pen {
                context.stroke(square, with: .color(tone), lineWidth: 1.2)
            } else {
                context.fill(square, with: .color(tone))
            }
        }
        // Fires: burning ground and hearths, in the orange pen.
        let hearths = snapshot.structures.filter { $0.kind == .fire && $0.lit }.map { WildmindPoint(x: $0.x, z: $0.z) }
        for fire in snapshot.fires + hearths {
            let c = grid.cell(x: fire.x, z: fire.z)
            let p = layout.point(c.x, c.y)
            let r = 0.8 * m
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(SR.accent))
        }

        // Trails: a dotted pencil line behind each person.
        for person in snapshot.people where !person.trail.isEmpty {
            var trail = Path()
            let points = (person.trail + [WildmindPoint(x: person.x, z: person.z)]).map { point -> CGPoint in
                let c = grid.cell(x: point.x, z: point.z)
                return layout.point(c.x, c.y)
            }
            trail.addLines(points)
            context.stroke(trail, with: .color(colour(for: person).opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round, dash: [0.1, 3.6]))
        }

        // People: a disc on a paper halo, and a tick the way they face. The
        // dead are an empty ring.
        var taken: [CGRect] = []
        for person in snapshot.people {
            let c = grid.cell(x: person.x, z: person.z)
            let p = layout.point(c.x, c.y)
            let tone = colour(for: person)
            let r = 1.5 * m
            let disc = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            taken.append(CGRect(x: p.x - r - 2, y: p.y - r - 2, width: r * 2 + 4, height: r * 2 + 4))
            if person.alive {
                let facing = shape.direction(heading: person.heading)
                var tick = Path()
                tick.move(to: p)
                tick.addLine(to: CGPoint(x: p.x + CGFloat(facing.dx) * 2.6 * m, y: p.y + CGFloat(facing.dy) * 2.6 * m))
                context.stroke(tick, with: .color(SR.paper), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                context.stroke(tick, with: .color(tone), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                context.stroke(disc, with: .color(SR.paper), lineWidth: 3)
                context.fill(disc, with: .color(tone))
            } else {
                let ring = Path(ellipseIn: CGRect(x: p.x - r * 1.25, y: p.y - r * 1.25, width: r * 2.5, height: r * 2.5))
                context.fill(ring, with: .color(tone.opacity(0.14)))
                context.stroke(ring, with: .color(tone), style: StrokeStyle(lineWidth: 2, dash: [2.5, 2]))
            }
            if selected == person.id {
                var loop = Path()
                var rng = InkRNG(seedFor(person.name) + 3)
                Ink.ring(&rng, cx: Double(p.x), cy: Double(p.y), rx: Double(r * 2.4), ry: Double(r * 2.2),
                         turns: 1.12, wob: 0.06, into: &loop)
                context.stroke(loop, with: .color(tone), style: .ink(1.6))
            }
        }

        // Words over the map, each on a patch of paper rubbed clear: the
        // people's tags first, then the places, skipping any that would
        // land on another.
        let bounds = layout.inner.insetBy(dx: 4, dy: 4)
        for person in snapshot.people {
            let c = grid.cell(x: person.x, z: person.z)
            let p = layout.point(c.x, c.y)
            guard bounds.contains(p) else { continue }
            let tone = colour(for: person)
            let words = WildmindWords.tag(person, pastTense: state.pastTense)
            let rest = String(words.dropFirst(person.name.count))
            let text = context.resolve(
                (Text(person.name).foregroundStyle(tone) + Text(rest).foregroundStyle(SR.inkSecondary))
                    .font(SR.Text.marginalia(16))
            )
            let size = text.measure(in: CGSize(width: bounds.width * 0.7, height: 80))
            let reach: CGFloat = 1.5 * m + 22
            let options = [
                CGRect(x: p.x + reach * 0.6, y: p.y - reach - size.height / 2, width: size.width, height: size.height),
                CGRect(x: p.x - reach * 0.6 - size.width, y: p.y - reach - size.height / 2, width: size.width, height: size.height),
                CGRect(x: p.x + reach * 0.6, y: p.y + reach - size.height / 2, width: size.width, height: size.height),
                CGRect(x: p.x - reach * 0.6 - size.width, y: p.y + reach - size.height / 2, width: size.width, height: size.height),
            ]
            guard let spot = options.first(where: { bounds.contains($0) && !taken.contains(where: $0.insetBy(dx: -3, dy: -2).intersects) })
            else { continue }
            taken.append(spot.insetBy(dx: -4, dy: -2))
            rubClear(spot, in: &context)
            context.draw(text, in: spot)
            // A pen arrow from the words back to the disc.
            let from = CGPoint(x: spot.midX < p.x ? spot.maxX - 4 : spot.minX + 4,
                               y: spot.midY < p.y ? spot.maxY + 1 : spot.minY - 1)
            let gap = 1.5 * m + 4
            let dx = p.x - from.x
            let dy = p.y - from.y
            let distance = max(1, hypot(dx, dy))
            let to = CGPoint(x: p.x - dx / distance * gap, y: p.y - dy / distance * gap)
            var arrow = Path()
            var rng = InkRNG(631 + (person.isMain ? 0 : 1))
            Ink.arrow(&rng, Double(from.x), Double(from.y), Double(to.x), Double(to.y), bow: 0.16, into: &arrow)
            context.stroke(arrow, with: .color(SR.inkSecondary), style: .ink(1.2))
        }

        if snapshot.stats.met == false && snapshot.people.count > 1 {
            let note = context.resolve(Text("they haven\u{2019}t met yet").font(SR.Text.marginalia(15)).foregroundStyle(SR.inkMuted))
            let size = note.measure(in: CGSize(width: bounds.width, height: 60))
            let spot = CGRect(x: bounds.minX + 6, y: bounds.minY + 6, width: size.width, height: size.height)
            if !taken.contains(where: spot.intersects) {
                taken.append(spot)
                rubClear(spot, in: &context)
                context.draw(note, in: spot)
            }
        }

        // Places: a pencil cross for each, its name where there is room —
        // landmarks first; the rest only once the reader has zoomed in.
        let places = grid.regions
            .filter { $0.isLandmark || $0.kind == "h" || layout.zoom >= 1.8 }
            .sorted { rank($0) < rank($1) }
        var written = 0
        let limit = layout.zoom >= 1.5 ? 16 : 8
        for place in places {
            let c = grid.cell(x: place.x, z: place.z)
            let p = layout.point(c.x, c.y)
            guard bounds.contains(p) else { continue }
            var cross = Path()
            var rng = InkRNG(seedFor(place.name))
            Ink.line(&rng, Double(p.x) - 4, Double(p.y) - 4, Double(p.x) + 4, Double(p.y) + 4, amp: 0.4, bow: 0.02, into: &cross)
            Ink.line(&rng, Double(p.x) - 4, Double(p.y) + 4, Double(p.x) + 4, Double(p.y) - 4, amp: 0.4, bow: 0.02, into: &cross)
            context.stroke(cross, with: .color(SR.inkSecondary), style: .ink(1.2))
            guard written < limit else { continue }
            let name = context.resolve(Text(place.name).font(SR.Text.marginalia(13)).foregroundStyle(SR.inkSecondary))
            let size = name.measure(in: CGSize(width: 180, height: 60))
            let options = [
                CGRect(x: p.x + 9, y: p.y - size.height / 2, width: size.width, height: size.height),
                CGRect(x: p.x - 9 - size.width, y: p.y - size.height / 2, width: size.width, height: size.height),
                CGRect(x: p.x - size.width / 2, y: p.y - 8 - size.height, width: size.width, height: size.height),
                CGRect(x: p.x - size.width / 2, y: p.y + 8, width: size.width, height: size.height),
            ]
            guard let spot = options.first(where: { bounds.contains($0) && !taken.contains(where: $0.insetBy(dx: -3, dy: -1).intersects) })
            else { continue }
            taken.append(spot.insetBy(dx: -4, dy: -1))
            rubClear(spot, in: &context)
            context.draw(name, in: spot)
            written += 1
        }

        // The scale bar, bottom left: a hand line with end ticks.
        if let scale = WildmindWords.scale(pointsPerMetre: Double(layout.unit) / grid.metresPerCell, room: 110) {
            let length = CGFloat(Double(scale.metres) * Double(layout.unit) / grid.metresPerCell)
            let x0 = bounds.minX + 8
            let y0 = bounds.maxY - 10
            let words = context.resolve(Text(scale.words.uppercased()).font(SR.Text.kicker()).foregroundStyle(SR.inkMuted))
            let size = words.measure(in: CGSize(width: 220, height: 40))
            let patch = CGRect(x: x0 - 2, y: y0 - size.height - 6, width: max(length, size.width) + 4, height: size.height + 12)
            rubClear(patch, in: &context)
            var bar = Path()
            var rng = InkRNG(651)
            Ink.line(&rng, Double(x0), Double(y0), Double(x0 + length), Double(y0), amp: 0.4, bow: 0.01, into: &bar)
            bar.move(to: CGPoint(x: x0, y: y0 - 4))
            bar.addLine(to: CGPoint(x: x0, y: y0 + 3))
            bar.move(to: CGPoint(x: x0 + length, y: y0 - 4))
            bar.addLine(to: CGPoint(x: x0 + length, y: y0 + 3))
            context.stroke(bar, with: .color(SR.inkSecondary), style: .ink(1.3))
            context.draw(words, at: CGPoint(x: x0, y: y0 - 5), anchor: .bottomLeading)
        }
    }

    private func rank(_ region: WildmindRegion) -> Int {
        region.isLandmark ? 0 : region.kind == "h" ? 1 : 2
    }

    /// A patch of paper wiped clear behind a word: a soft-edged smudge, then
    /// the patch itself.
    private func rubClear(_ rect: CGRect, in context: inout GraphicsContext) {
        let patch = rect.insetBy(dx: -4, dy: -1)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 2.5))
            layer.fill(Path(roundedRect: patch.insetBy(dx: -1, dy: -1), cornerRadius: 3), with: .color(SR.paper))
        }
        context.fill(Path(roundedRect: patch, cornerRadius: 2), with: .color(SR.paper))
    }

    // MARK: - The picture

    /// Make the ground's picture and outlines for this grid and scheme, off
    /// the main thread, unless the last one made is this one.
    @MainActor private func draw() async {
        let key = pictureKey
        if let cached = WildmindPictureCache.last, cached.key == key {
            picture = cached.image
            lines = cached.lines
            return
        }
        let grid = self.grid
        let shape = self.shape
        let palette = scheme == .dark ? WildmindPalette.night : WildmindPalette.light
        let made = await Task.detached(priority: .userInitiated) { () -> (WildmindPixels, WildmindLines) in
            let pixels = WildmindRaster.render(grid, shape: shape, palette: palette,
                                               pixelsPerCell: WildmindRaster.pixelsPerCell(shape))
            let outline = WildmindOutline.lines(grid)
            return (pixels, WildmindLines(coast: outline.coast, edge: outline.edge))
        }.value
        guard !Task.isCancelled, let image = WildmindPictureCache.image(made.0) else { return }
        WildmindPictureCache.last = (key: key, image: image, lines: made.1)
        picture = image
        lines = made.1
    }
}

/// The coast and the edge of the known, in grid cells.
struct WildmindLines: Equatable, Sendable {
    var coast: [WildmindSegment] = []
    var edge: [WildmindSegment] = []
}

/// The last picture made, so leaving the page and coming back does not make
/// it again. One is enough: a phone shows one valley in one scheme at a time.
@MainActor
enum WildmindPictureCache {
    static var last: (key: String, image: CGImage, lines: WildmindLines)?

    static func image(_ pixels: WildmindPixels) -> CGImage? {
        guard pixels.width > 0, pixels.height > 0,
              let provider = CGDataProvider(data: Data(pixels.rgba) as CFData) else { return nil }
        return CGImage(
            width: pixels.width, height: pixels.height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}

/// Where everything lands in the frame, for one zoom and pan.
struct WildmindMapLayout {
    let size: CGSize
    let shape: WildmindMapShape
    let zoom: CGFloat
    let pan: CGSize

    /// The map sits ten points inside the frame, as on the site.
    static let inset: CGFloat = 10

    var inner: CGRect { CGRect(origin: .zero, size: size).insetBy(dx: Self.inset, dy: Self.inset) }

    /// Points per cell at the whole valley.
    var fit: CGFloat {
        guard shape.width > 0, shape.height > 0, inner.width > 0, inner.height > 0 else { return 1 }
        return min(inner.width / CGFloat(shape.width), inner.height / CGFloat(shape.height))
    }

    /// Points per cell now.
    var unit: CGFloat { fit * zoom }

    /// The size marks are drawn at: they grow a little as the reader zooms,
    /// never so much that a hut covers a field.
    var mark: CGFloat { min(5, max(3, unit * 0.8)) }

    var mapSize: CGSize { CGSize(width: CGFloat(shape.width) * unit, height: CGFloat(shape.height) * unit) }

    var mapCentre: CGPoint { CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height) }

    /// A point in grid cells (not turned), on the frame.
    func point(_ x: Double, _ y: Double) -> CGPoint {
        let placed = shape.place(x, y)
        return CGPoint(x: mapCentre.x - mapSize.width / 2 + CGFloat(placed.x) * unit,
                       y: mapCentre.y - mapSize.height / 2 + CGFloat(placed.y) * unit)
    }

    /// A pan that keeps the zoomed map over the frame: no further than its
    /// overhang either way, and none at all at the whole valley.
    func clamp(_ wanted: CGSize) -> CGSize {
        let overX = max(0, (mapSize.width - inner.width) / 2)
        let overY = max(0, (mapSize.height - inner.height) / 2)
        return CGSize(width: min(overX, max(-overX, wanted.width)), height: min(overY, max(-overY, wanted.height)))
    }
}

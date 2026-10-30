import SwiftUI

/// What one finger on the field is doing. A class held in `@State`, so the
/// gesture's bookkeeping changes nothing SwiftUI watches.
final class MinesweeperTouch {
    var active = false
    var token = 0
    /// Where this touch came down: a new start means a new touch, even if the
    /// last one was cancelled without an end.
    var start: CGPoint = .zero
    var cell: Int? = nil
    /// Moved far enough that it is not a tap.
    var moved = false
    var panning = false
    /// The long press fired: lifting the finger does nothing more.
    var held = false
    /// A second finger pinched during this touch.
    var pinched = false
    var panBase: MinesweeperViewport? = nil
    var pinchBase: MinesweeperViewport? = nil
}

/// The field: drawn in one Canvas, redrawn every frame only while something
/// moves, and read by one gesture that tells a tap from a hold from a pan,
/// with a pinch beside it to zoom.
struct MinesweeperBoardView: View {
    @ObservedObject var game: MinesweeperGame
    @ObservedObject var camera: MinesweeperCamera
    @ObservedObject var pulse: MinesweeperPulse
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var touch = MinesweeperTouch()
    /// True while the drag gesture is live. SwiftUI resets it when the system
    /// cancels the gesture (a sheet, the back swipe, a call), which `onEnded`
    /// never hears about; see `touchMaybeCancelled`.
    @GestureState private var fingerDown = false

    /// A finger that moves further than this is panning, not tapping.
    private static let slop: Double = 10

    var body: some View {
        GeometryReader { geo in
            fieldLayer
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear { camera.layout(width: Double(geo.size.width), height: Double(geo.size.height)) }
                .onChange(of: geo.size) { _, size in
                    camera.layout(width: Double(size.width), height: Double(size.height))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
        .accessibilityIdentifier("minesweeper-board")
    }

    @ViewBuilder
    private var fieldLayer: some View {
        if voiceOver {
            interactiveField
                .accessibilityElement(children: .contain)
                .accessibilityLabel(summary)
                .accessibilityChildren { MinesweeperAccessibleField(game: game) }
        } else {
            interactiveField
                .accessibilityElement()
                .accessibilityLabel(summary)
        }
    }

    private var interactiveField: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !pulse.live)) { timeline in
            fieldFrame(at: timeline.date)
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(magnifyGesture)
        .onChange(of: fingerDown) { _, down in
            if !down { touchMaybeCancelled() }
        }
    }

    private func fieldFrame(at date: Date) -> some View {
        // Paused, the timeline's date is when it stopped: draw at the real now so
        // everything that finished since is drawn settled.
        let now = pulse.live ? date.timeIntervalSinceReferenceDate : Date().timeIntervalSinceReferenceDate
        let scene = MinesweeperScene(board: game.board, fx: game.fx, viewport: camera.viewport(at: now), now: now,
                                     press: game.press, veiled: game.paused || game.stage == .intro,
                                     calm: reduceMotion)
        let painter = MinesweeperPainter(palette: MinesweeperPalette.shared(dark: colorScheme == .dark))
        return Canvas { context, size in
            painter.draw(scene, in: &context, size: size)
        }
    }

    private var summary: String {
        let b = game.board
        let flags = b.minesLeft == 1 ? "1 mine left to flag" : "\(b.minesLeft) mines left to flag"
        return "Minefield, \(b.width) squares across and \(b.height) down, \(b.mineCount) mines, \(flags)."
    }

    // MARK: - One finger: tap, hold or pan

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($fingerDown) { _, state, _ in state = true }
            .onChanged { value in dragChanged(value) }
            .onEnded { value in dragEnded(value) }
    }

    private func dragChanged(_ value: DragGesture.Value) {
        if !touch.active || value.startLocation != touch.start { touchBegan(at: value.startLocation) }
        guard !touch.pinched else { return }
        let dx = Double(value.translation.width), dy = Double(value.translation.height)
        if !touch.moved && (dx * dx + dy * dy).squareRoot() > Self.slop {
            touch.moved = true
            game.pressEnded()
        }
        guard touch.moved, let base = touch.panBase, base.canPan else { return }
        touch.panning = true
        var next = base
        next.offsetX += dx
        next.offsetY += dy
        camera.set(next.rubberBanded())
    }

    private func touchBegan(at point: CGPoint) {
        touch.active = true
        touch.start = point
        touch.token += 1
        touch.moved = false
        touch.panning = false
        touch.held = false
        touch.pinched = false
        camera.freeze()
        let here = camera.viewport(at: MinesweeperPulse.now())
        touch.panBase = here
        let cell = here.cellIndex(x: Double(point.x), y: Double(point.y))
        touch.cell = cell
        guard let cell, game.acceptsTouch else { return }
        game.pressBegan(cell)
        scheduleHold(token: touch.token, cell: cell)
    }

    private func scheduleHold(token: Int, cell: Int) {
        let tracker = touch
        let game = self.game
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(MinesweeperPainter.holdTime * 1_000_000_000))
            guard tracker.active, tracker.token == token, !tracker.moved, !tracker.pinched else { return }
            tracker.held = true
            game.hold(cell)
        }
    }

    private func dragEnded(_ value: DragGesture.Value) {
        let wasPinched = touch.pinched, wasPanning = touch.panning, wasHeld = touch.held, wasMoved = touch.moved
        let cell = touch.cell, base = touch.panBase
        touch.active = false
        touch.token += 1
        game.pressEnded()
        if wasPinched {
            camera.glide(to: camera.viewport(at: MinesweeperPulse.now()).clamped(), duration: 0.25)
            return
        }
        if wasPanning, let base {
            // A fling carries on a little way, then the field settles inside its edges.
            let dx = Double(value.translation.width), dy = Double(value.translation.height)
            let fx = Double(value.predictedEndTranslation.width), fy = Double(value.predictedEndTranslation.height)
            var target = base
            target.offsetX += dx + (fx - dx) * 0.5
            target.offsetY += dy + (fy - dy) * 0.5
            camera.glide(to: target.clamped(), duration: 0.45)
            return
        }
        guard !wasHeld, !wasMoved, let cell else { return }
        game.tap(cell)
    }

    /// The gesture state went back to idle. After a normal lift `onEnded` has
    /// already tidied up; after a cancel it never runs, so the press (and the
    /// ticking it keeps going) would be left on. Checked a turn later, so a
    /// normal end always gets there first.
    private func touchMaybeCancelled() {
        let tracker = touch
        let token = tracker.token
        let game = self.game
        let camera = self.camera
        Task { @MainActor in
            guard tracker.active, tracker.token == token else { return }
            tracker.active = false
            tracker.token += 1
            tracker.pinchBase = nil
            game.pressEnded()
            camera.glide(to: camera.viewport(at: MinesweeperPulse.now()).clamped(), duration: 0.25)
        }
    }

    // MARK: - Two fingers: pinch to zoom

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if touch.pinchBase == nil {
                    touch.pinched = true
                    game.pressEnded()
                    camera.freeze()
                    touch.pinchBase = camera.viewport(at: MinesweeperPulse.now())
                }
                guard let base = touch.pinchBase else { return }
                let focus = value.startLocation
                let next = base.zoomed(to: base.scale * Double(value.magnification),
                                       focusX: Double(focus.x), focusY: Double(focus.y))
                camera.set(next)
            }
            .onEnded { _ in
                touch.pinchBase = nil
            }
    }
}

/// The field for VoiceOver: one element per square, in reading order, each
/// saying what it shows. Activating a square taps it; the Flag action plants
/// or lifts a flag.
struct MinesweeperAccessibleField: View {
    @ObservedObject var game: MinesweeperGame

    var body: some View {
        let board = game.board
        VStack(spacing: 0) {
            ForEach(0..<board.height, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<board.width, id: \.self) { column in
                        MinesweeperAccessibleSquare(game: game, index: row * board.width + column,
                                                    label: label(row: row, column: column, board: board))
                    }
                }
            }
        }
    }

    private func label(row: Int, column: Int, board: MinesweeperBoard) -> String {
        let i = row * board.width + column
        let place = "Row \(row + 1), column \(column + 1)"
        switch board.cells[i] {
        case .hidden:
            if board.status == .lost && board.mines[i] { return "\(place), mine" }
            return "\(place), covered"
        case .flagged:
            return "\(place), flagged"
        case .revealed:
            if board.mines[i] { return "\(place), mine, exploded" }
            let n = board.counts[i]
            if n == 0 { return "\(place), clear" }
            return n == 1 ? "\(place), 1 mine touching" : "\(place), \(n) mines touching"
        }
    }
}

struct MinesweeperAccessibleSquare: View {
    let game: MinesweeperGame
    let index: Int
    let label: String

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                game.tap(index)
            }
            .accessibilityAction(named: Text("Flag")) {
                game.flagFromVoiceOver(index)
            }
    }
}

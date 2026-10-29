import Foundation

/// Where the field sits in the board's window: how big a square is drawn and
/// where the top-left corner of the field is, in points. Pinch, pan, the zoom
/// button and every tap's square all go through here, so the drawing and the
/// finger always agree.
///
/// `scale` 1 is the whole field fitted in the window. A big field (Expert on
/// a small phone) starts zoomed in so a square is a fair target for the first
/// dig, and zooming in never stops short of `zoomedCell` points a square.
struct MinesweeperViewport: Equatable, Sendable {
    var columns: Int
    var rows: Int
    var viewWidth: Double
    var viewHeight: Double
    var scale: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0

    /// The square the zoom button and the opening view aim for.
    static let zoomedCell: Double = 40
    /// Never drawn bigger than this, however far the pinch goes.
    static let largestCell: Double = 72
    /// Fitted squares smaller than this start zoomed in to `zoomedCell`.
    static let smallestFitted: Double = 30

    init(columns: Int, rows: Int, width: Double, height: Double) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        viewWidth = max(1, width)
        viewHeight = max(1, height)
        scale = 1
        if fitCell < Self.smallestFitted { scale = zoomedScale }
        self = centred(onColumn: Double(self.columns) / 2, row: Double(self.rows) / 2)
    }

    /// The square, in points, with the whole field in view.
    var fitCell: Double { max(1, min(viewWidth / Double(columns), viewHeight / Double(rows))) }
    var cell: Double { fitCell * scale }
    var contentWidth: Double { cell * Double(columns) }
    var contentHeight: Double { cell * Double(rows) }
    var maxScale: Double { max(1, Self.largestCell / fitCell) }
    /// The scale that draws a square at `zoomedCell`.
    var zoomedScale: Double { min(maxScale, max(1, Self.zoomedCell / fitCell)) }
    /// Worth offering a zoom button: zooming in makes a real difference.
    var canZoom: Bool { zoomedScale > 1.05 }
    var isZoomedIn: Bool { scale > 1.02 }
    /// Some of the field is out of the window, so a finger can drag it.
    var canPan: Bool { contentWidth > viewWidth + 0.5 || contentHeight > viewHeight + 0.5 }

    /// The allowed range for the corner on one axis: pinned to the edges when
    /// the field is wider than the window, centred when it is narrower.
    private static func limits(content: Double, view: Double) -> ClosedRange<Double> {
        if content <= view {
            let mid = (view - content) / 2
            return mid...mid
        }
        return (view - content)...0
    }

    var xLimits: ClosedRange<Double> { Self.limits(content: contentWidth, view: viewWidth) }
    var yLimits: ClosedRange<Double> { Self.limits(content: contentHeight, view: viewHeight) }

    /// The same view with the field kept inside the window.
    func clamped() -> MinesweeperViewport {
        var v = self
        v.scale = min(maxScale, max(1, scale))
        v.offsetX = min(v.xLimits.upperBound, max(v.xLimits.lowerBound, offsetX))
        v.offsetY = min(v.yLimits.upperBound, max(v.yLimits.lowerBound, offsetY))
        return v
    }

    /// Past an edge while a finger drags, the field gives a little and then
    /// resists, like a scroll view's bounce.
    func rubberBanded() -> MinesweeperViewport {
        var v = self
        v.offsetX = Self.rubber(offsetX, xLimits)
        v.offsetY = Self.rubber(offsetY, yLimits)
        return v
    }

    private static func rubber(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        if value > range.upperBound { return range.upperBound + (value - range.upperBound) * 0.35 }
        if value < range.lowerBound { return range.lowerBound - (range.lowerBound - value) * 0.35 }
        return value
    }

    /// The square under a point in the window, if there is one.
    func cellIndex(x: Double, y: Double) -> Int? {
        let c = Int(((x - offsetX) / cell).rounded(.down))
        let r = Int(((y - offsetY) / cell).rounded(.down))
        guard c >= 0, c < columns, r >= 0, r < rows else { return nil }
        return r * columns + c
    }

    /// The field position (in squares) under a point in the window.
    func fieldPoint(x: Double, y: Double) -> (column: Double, row: Double) {
        ((x - offsetX) / cell, (y - offsetY) / cell)
    }

    /// Zooms to `newScale`, keeping the field point under `focus` where it is.
    func zoomed(to newScale: Double, focusX: Double, focusY: Double) -> MinesweeperViewport {
        let at = fieldPoint(x: focusX, y: focusY)
        var v = self
        v.scale = min(maxScale, max(1, newScale))
        v.offsetX = focusX - at.column * v.cell
        v.offsetY = focusY - at.row * v.cell
        return v.clamped()
    }

    /// The field point (in squares) brought to the middle of the window.
    func centred(onColumn column: Double, row: Double) -> MinesweeperViewport {
        var v = self
        v.offsetX = viewWidth / 2 - column * cell
        v.offsetY = viewHeight / 2 - row * cell
        return v.clamped()
    }

    /// The whole field in view.
    func fitted() -> MinesweeperViewport {
        var v = self
        v.scale = 1
        return v.centred(onColumn: Double(columns) / 2, row: Double(rows) / 2)
    }

    /// Zoomed in to a comfortable square, centred on `index` (or the middle).
    func zoomedIn(on index: Int?) -> MinesweeperViewport {
        var v = self
        v.scale = zoomedScale
        guard let index, index >= 0, index < columns * rows else {
            let mid = fieldPoint(x: viewWidth / 2, y: viewHeight / 2)
            return v.centred(onColumn: mid.column, row: mid.row)
        }
        return v.centred(onColumn: Double(index % columns) + 0.5, row: Double(index / columns) + 0.5)
    }

    /// The window changed size (a card came up, the phone turned): keep the
    /// same field point in the middle and the same square size where it fits.
    /// A field showing whole stays whole: the end card rising must not crop it.
    func resized(width: Double, height: Double) -> MinesweeperViewport {
        let mid = fieldPoint(x: viewWidth / 2, y: viewHeight / 2)
        let keptCell = cell
        var v = self
        v.viewWidth = max(1, width)
        v.viewHeight = max(1, height)
        if !isZoomedIn { return v.fitted() }
        v.scale = min(v.maxScale, max(1, keptCell / v.fitCell))
        return v.centred(onColumn: mid.column, row: mid.row)
    }

    /// Part of the way from here to `other`, for the camera's glides.
    func blended(to other: MinesweeperViewport, _ t: Double) -> MinesweeperViewport {
        let k = min(1, max(0, t))
        var v = other
        v.scale = scale + (other.scale - scale) * k
        v.offsetX = offsetX + (other.offsetX - offsetX) * k
        v.offsetY = offsetY + (other.offsetY - offsetY) * k
        return v
    }
}

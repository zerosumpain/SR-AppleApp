import SwiftUI

/// The lawn the game is played on: a checked grass board with a few tufts,
/// the maze's stone walls, and an edge that says whether it is a wall
/// (a hedge, Classic) or a way through (a dashed line, Wrap and Maze).
///
/// It changes only when the layout or the appearance does, so it is its own
/// canvas under the moving one and is not redrawn every frame.
struct SnakeBoardView: View, Equatable {
    let columns: Int
    let rows: Int
    let mode: SnakeMode
    /// Names the walls for `==`, so the set is not compared on every redraw.
    let layout: String
    let walls: Set<SnakePoint>
    let dark: Bool

    static func == (lhs: SnakeBoardView, rhs: SnakeBoardView) -> Bool {
        lhs.columns == rhs.columns && lhs.rows == rhs.rows && lhs.mode == rhs.mode
            && lhs.layout == rhs.layout && lhs.dark == rhs.dark
    }

    var body: some View {
        let art = SnakeBoardArt(columns: columns, rows: rows, mode: mode, walls: walls, paint: SnakeBoardPaint.of(dark: dark))
        Canvas { context, size in
            art.draw(in: context, size: size)
        }
        .accessibilityHidden(true)
    }
}

struct SnakeBoardArt {
    let columns: Int
    let rows: Int
    let mode: SnakeMode
    let walls: Set<SnakePoint>
    let paint: SnakeBoardPaint

    func draw(in context: GraphicsContext, size: CGSize) {
        let cell = size.width / CGFloat(max(1, columns))
        let board = CGRect(origin: .zero, size: size)
        context.fill(Path(board), with: .color(paint.grass))
        context.fill(checks(cell: cell), with: .color(paint.grassAlt))
        context.stroke(tufts(cell: cell), with: .color(paint.tuft),
                       style: StrokeStyle(lineWidth: max(1, cell * 0.06), lineCap: .round))
        // The edge first, so a maze's border walls sit over the dashes.
        drawEdge(context, board: board, cell: cell)
        drawWalls(context, cell: cell)
    }

    private func checks(cell: CGFloat) -> Path {
        var path = Path()
        for y in 0..<rows {
            for x in 0..<columns where (x + y) % 2 == 1 {
                path.addRect(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
            }
        }
        return path
    }

    /// A few blades of grass in about one cell in seven, always the same ones.
    private func tufts(cell: CGFloat) -> Path {
        var path = Path()
        for y in 0..<rows {
            for x in 0..<columns {
                let hash = (x &* 73_856_093) ^ (y &* 19_349_663)
                guard abs(hash) % 7 == 0, !walls.contains(SnakePoint(x, y)) else { continue }
                let bx = (CGFloat(x) + 0.3 + CGFloat(abs(hash) % 5) * 0.08) * cell
                let by = (CGFloat(y) + 0.78) * cell
                let h = cell * 0.2
                path.move(to: CGPoint(x: bx, y: by))
                path.addLine(to: CGPoint(x: bx - cell * 0.06, y: by - h))
                path.move(to: CGPoint(x: bx + cell * 0.08, y: by))
                path.addLine(to: CGPoint(x: bx + cell * 0.08, y: by - h * 1.25))
                path.move(to: CGPoint(x: bx + cell * 0.16, y: by))
                path.addLine(to: CGPoint(x: bx + cell * 0.24, y: by - h))
            }
        }
        return path
    }

    /// Stone blocks with a drop shadow and a lit top edge.
    private func drawWalls(_ context: GraphicsContext, cell: CGFloat) {
        guard !walls.isEmpty else { return }
        var blocks = Path()
        var bevels = Path()
        for wall in walls {
            let rect = CGRect(x: CGFloat(wall.x) * cell, y: CGFloat(wall.y) * cell, width: cell, height: cell)
            blocks.addRoundedRect(in: rect.insetBy(dx: -0.25, dy: -0.25), cornerSize: CGSize(width: cell * 0.12, height: cell * 0.12))
            let inner = rect.insetBy(dx: cell * 0.12, dy: cell * 0.12)
            bevels.addRoundedRect(in: inner, cornerSize: CGSize(width: cell * 0.1, height: cell * 0.1))
        }
        var shadow = context
        shadow.translateBy(x: cell * 0.06, y: cell * 0.16)
        shadow.fill(blocks, with: .color(Color.black.opacity(0.28)))
        let rect = blocks.boundingRect
        context.fill(blocks, with: .linearGradient(Gradient(colors: [paint.stoneTop, paint.stoneBottom]),
                                                   startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                                   endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
        context.stroke(blocks, with: .color(paint.stoneEdge), lineWidth: max(1, cell * 0.05))
        context.stroke(bevels, with: .color(Color.white.opacity(0.18)), lineWidth: max(0.75, cell * 0.04))
    }

    private func drawEdge(_ context: GraphicsContext, board: CGRect, cell: CGFloat) {
        if mode.edgesKill {
            let inset = max(2, cell * 0.1)
            let hedge = Path(roundedRect: board.insetBy(dx: inset / 2, dy: inset / 2), cornerRadius: SnakeLayout.radius)
            context.stroke(hedge, with: .color(paint.hedge), lineWidth: inset)
        } else {
            let edge = Path(roundedRect: board.insetBy(dx: 1, dy: 1), cornerRadius: SnakeLayout.radius)
            context.stroke(edge, with: .color(Color.white.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [cell * 0.3, cell * 0.25]))
        }
    }
}

/// Sizes the board and its pieces share.
enum SnakeLayout {
    static let radius: CGFloat = 16

    /// The biggest whole-half-point cell that fits the board in `size`.
    static func cell(for size: CGSize, columns: Int, rows: Int) -> CGFloat {
        let raw = min(size.width / CGFloat(max(1, columns)), size.height / CGFloat(max(1, rows)))
        return max(8, (raw * 2).rounded(.down) / 2)
    }
}

/// A small drawing of a maze's walls, for its chip on the card.
struct SnakeMazeThumb: View {
    let maze: SnakeMaze
    let dark: Bool

    var body: some View {
        let paint = SnakeBoardPaint.of(dark: dark)
        let walls = maze.walls
        Canvas { context, size in
            let cell = size.width / CGFloat(SnakeRules.columns)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paint.grass))
            var path = Path()
            for wall in walls {
                path.addRect(CGRect(x: CGFloat(wall.x) * cell, y: CGFloat(wall.y) * cell, width: cell, height: cell))
            }
            context.fill(path, with: .color(paint.stoneBottom))
        }
        .aspectRatio(CGFloat(SnakeRules.columns) / CGFloat(SnakeRules.rows), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)
    }
}

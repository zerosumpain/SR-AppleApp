import Foundation

/// A steady pair of hands: tilts the board to roll the marble along the way
/// through, one cell at a time, easing off before each corner. It drives the
/// demo (so the screenshots move) and the tests use it to show every level
/// can be finished by a ball that obeys the physics.
enum TiltMazeAutopilot {
    /// How fast it likes to roll down a straight, cells a second.
    static let cruise = 3.2
    /// …and round a corner.
    static let cornering = 1.3

    /// The tilt to give the board now, for `run` following `path` (the
    /// way from the start to the goal, round the holes).
    static func tilt(for run: TiltMazeRun, path: [TiltMazeCell]) -> TiltMazeVector {
        guard run.steerable, !path.isEmpty else { return .zero }
        let ball = run.ball
        let level = run.level
        let here = level.cell(under: ball.position)

        // Where on the way the marble is: the cell it is over, or the nearest.
        var at = path.firstIndex(of: here) ?? -1
        if at < 0 {
            var nearest = Double.infinity
            for (i, cell) in path.enumerated() {
                let d = cell.centre.distance(to: ball.position)
                if d < nearest {
                    nearest = d
                    at = i
                }
            }
        }
        at = max(0, at)
        let targetIndex = min(at + 1, path.count - 1)
        let target = path[targetIndex].centre

        // Off the middle of the corridor, come back to it first: aim at a
        // point between this cell's middle and the next one's.
        let current = path[at].centre
        let across = TiltMazeVector(x: target.x - current.x, y: target.y - current.y)
        var aim = target
        if across.x != 0 {
            aim.y = current.y
        } else if across.y != 0 {
            aim.x = current.x
        }

        var dx = aim.x - ball.x, dy = aim.y - ball.y
        let distance = (dx * dx + dy * dy).squareRoot()
        var speed = cruise
        if targetIndex + 1 < path.count {
            let after = path[targetIndex + 1]
            let turnX = after.x - path[targetIndex].x, turnY = after.y - path[targetIndex].y
            let goingX = path[targetIndex].x - path[at].x, goingY = path[targetIndex].y - path[at].y
            if turnX != goingX || turnY != goingY { speed = min(speed, cornering + 1.6 * distance) }
        } else {
            speed = min(speed, 0.8 + 2 * distance)
        }
        if distance > 1e-6 {
            dx /= distance
            dy /= distance
        }
        let wanted = min(speed, 0.4 + distance * 4)
        let wantVX = dx * wanted, wantVY = dy * wanted
        // Lean towards the speed it wants: an acceleration, as a tilt.
        let gain = 5.0
        let ax = (wantVX - ball.vx) * gain, ay = (wantVY - ball.vy) * gain
        return TiltMazePhysics.clampTilt(TiltMazeVector(x: ax / TiltMazeRules.gravity, y: ay / TiltMazeRules.gravity))
    }
}

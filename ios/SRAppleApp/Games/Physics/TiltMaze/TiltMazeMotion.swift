import Foundation
import CoreMotion

/// Which way the phone is tipped, both ways at once, for Tilt Maze.
///
/// `PhysicsTilt` reads only side to side, which is all a car or a lander
/// needs; a labyrinth needs forwards and back as well. This is the same
/// sensor read the same way — device-motion gravity, no permission prompt,
/// switched on only while a maze is being played and off the moment it
/// stops — with both axes. It asks `PhysicsTilt` whether tilt is on offer at
/// all (a sensor, and not the demo), so the two games always agree.
///
/// The first reading after `start` or `recentre` is level: however the phone
/// is held then becomes flat, so a maze can be played lying on a sofa. The
/// lean is measured by `TiltMazeLean`, which feels the same at any angle.
@MainActor
final class TiltMazeMotion {
    /// Whether this phone can steer by tilt.
    let available: Bool
    private var manager: CMMotionManager?
    /// The gravity reading that counts as level.
    private var middle: CMAcceleration?
    /// A sample from before the latest `start` is the last maze's, left in
    /// the manager when it stopped: never taken as level.
    private var startedAt: TimeInterval = 0

    init() {
        available = PhysicsTilt.isAvailable
    }

    func start() {
        guard available else { return }
        let manager = self.manager ?? CMMotionManager()
        self.manager = manager
        guard !manager.isDeviceMotionActive else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates()
    }

    func stop() {
        if let manager, manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
    }

    /// The way the phone is held now becomes level.
    func recentre() { middle = nil }

    /// The board's tilt from level, in g: x towards the right edge of the
    /// screen, y towards the bottom (the way a marble would roll). Nil until
    /// the sensor has a fresh reading.
    func lean() -> TiltMazeVector? {
        guard let motion = manager?.deviceMotion else { return nil }
        // Both clocks count from boot. Half a second in, take whatever there
        // is, so a clock quirk can never leave the marble deaf to the tilt.
        if middle == nil && motion.timestamp < startedAt
            && ProcessInfo.processInfo.systemUptime - startedAt < 0.5 { return nil }
        let gravity = motion.gravity
        if middle == nil { middle = gravity }
        let level = middle ?? gravity
        return TiltMazeLean.lean(gx: gravity.x, gy: gravity.y, gz: gravity.z,
                                 levelX: level.x, levelY: level.y, levelZ: level.z)
    }
}

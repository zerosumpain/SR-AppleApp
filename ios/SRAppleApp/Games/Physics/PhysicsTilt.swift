import Foundation
import CoreMotion

/// The phone's side-to-side tilt, for the physics games' steering.
///
/// Read from Core Motion's device-motion gravity, which needs no permission
/// prompt (the Motion & Fitness permission covers the step and activity
/// history, not the live attitude). The sensor is switched on only when a
/// game starts and off the moment it stops or the screen goes, so it is never
/// left running behind the player's back. Updates are pulled each frame —
/// no queue, no callbacks across threads.
///
/// The first reading after `start` is "straight": however the player happens
/// to hold the phone becomes the middle, so lying on a sofa works as well as
/// sitting up.
@MainActor
final class PhysicsTilt {
    /// Whether this phone has the sensor (the simulator does not).
    let available: Bool
    private var manager: CMMotionManager?
    private var middle: Double?

    /// Whether a game on this phone can steer by tilt: there is a sensor,
    /// and this is not the demo (where a scripted pilot drives instead).
    nonisolated static var isAvailable: Bool { !SRDemo.isOn && hasSensor }
    private nonisolated static let hasSensor = CMMotionManager().isDeviceMotionAvailable

    init() {
        available = Self.isAvailable
    }

    func start() {
        guard available else { return }
        let manager = self.manager ?? CMMotionManager()
        self.manager = manager
        middle = nil
        guard !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates()
    }

    func stop() {
        if let manager, manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        middle = nil
    }

    /// Start again from however the phone is held now.
    func recentre() { middle = nil }

    /// Tilt right of the middle, in g: about −1…1, 0 when level. Nil until
    /// the sensor has a first reading.
    func lean() -> Double? {
        guard let gravity = manager?.deviceMotion?.gravity else { return nil }
        let x = gravity.x
        if middle == nil { middle = x }
        return x - (middle ?? x)
    }
}

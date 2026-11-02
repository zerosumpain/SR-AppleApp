import Combine
import UIKit

/// Long jobs (photo sync, re-sending old workouts) run flat out only while
/// the app is on screen. On charge, with the screen on, this keeps it from
/// locking while one of them has work left, so the job stays live instead
/// of dropping to the slow background wakes. Off charge it never holds the
/// screen: the battery is the person's.
///
/// Other screens (a marble race, a trip listener) set the idle timer
/// themselves; this only ever undoes what it did.
@MainActor
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()

    /// Why the screen is being kept on, when it is.
    @Published private(set) var holding = false
    @Published private(set) var charging = false
    private var reasons = Set<String>()
    private var active = false
    private var bag = Set<AnyCancellable>()

    /// Pure: whether to keep the screen on.
    nonisolated static func shouldHold(active: Bool, charging: Bool, reasons: Int) -> Bool {
        active && charging && reasons > 0
    }

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        readBattery()
        active = UIApplication.shared.applicationState == .active
        let centre = NotificationCenter.default
        centre.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .sink { _ in Task { @MainActor in KeepAwake.shared.readBattery(); KeepAwake.shared.apply() } }
            .store(in: &bag)
        centre.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { _ in Task { @MainActor in KeepAwake.shared.active = true; KeepAwake.shared.apply() } }
            .store(in: &bag)
        centre.publisher(for: UIApplication.willResignActiveNotification)
            .sink { _ in Task { @MainActor in KeepAwake.shared.active = false; KeepAwake.shared.apply() } }
            .store(in: &bag)
    }

    /// A job saying it has work left (`true`) or is done or paused (`false`).
    func set(_ reason: String, _ busy: Bool) {
        let changed = busy ? reasons.insert(reason).inserted : reasons.remove(reason) != nil
        if changed { apply() }
    }

    private func readBattery() {
        let state = UIDevice.current.batteryState
        charging = state == .charging || state == .full
    }

    private func apply() {
        let hold = Self.shouldHold(active: active, charging: charging, reasons: reasons.count)
        guard hold != holding else { return }
        holding = hold
        UIApplication.shared.isIdleTimerDisabled = hold
    }
}

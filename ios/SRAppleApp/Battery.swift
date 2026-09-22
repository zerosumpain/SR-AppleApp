import Foundation
import Combine
import UIKit

/// What sharing your location is costing, measured rather than assumed.
///
/// ## What this can and cannot tell you
///
/// iOS does **not** expose per-app energy use to the app itself. Nothing here
/// can say "the companion used 8% of your battery" — that number is only in
/// Settings → Battery, and no API returns it.
///
/// What it CAN do is measure the device's drain over the periods when sharing
/// was on, and set it beside what that drain bought: points recorded, and how
/// accurate they were. That is a comparison you can act on — switch the preset,
/// leave it a day, read the two numbers again — which is the actual question
/// ("what is the right balance"), where a fabricated per-app percentage would
/// only have looked like an answer.
///
/// Every screen that shows these says device-wide, for the same reason.
///
/// ## Why charging samples are thrown away
///
/// The level goes UP on charge. A window that spans a charge shows negative
/// drain, and averaged over a day that quietly reports the app as free.
struct BatterySample: Codable, Equatable {
    let at: Date
    /// 0–1. iOS reports this in 1% steps with monitoring on, and -1 when it
    /// cannot read it at all (the simulator does this).
    let level: Double
    let charging: Bool
    /// Whether location sharing was running when this was taken. A drain figure
    /// that mixed both is not about sharing.
    let sharing: Bool
}

/// A window between two consecutive samples, once the unusable ones are gone.
struct DrainWindow {
    let seconds: TimeInterval
    let dropped: Double
}

enum BatteryMaths {
    /// Drain per hour across the usable windows, as a percentage.
    ///
    /// Returns nil rather than 0 when there is nothing to say. Zero is a
    /// measurement ("it used none") and absence is not; printing one for the
    /// other is how a dashboard ends up confidently wrong.
    static func drainPerHour(_ samples: [BatterySample], sharingOnly: Bool) -> Double? {
        let windows = usableWindows(samples, sharingOnly: sharingOnly)
        let seconds = windows.reduce(0) { $0 + $1.seconds }
        let dropped = windows.reduce(0) { $0 + $1.dropped }
        // An hour of evidence minimum. Below that the 1% reporting step is most
        // of the signal: one step over four minutes extrapolates to 15%/hour.
        guard seconds >= 3600, dropped > 0 else { return nil }
        return (dropped / seconds) * 3600 * 100
    }

    /// Pairs of consecutive samples that describe real discharge.
    static func usableWindows(_ samples: [BatterySample], sharingOnly: Bool) -> [DrainWindow] {
        let ordered = samples.sorted { $0.at < $1.at }
        var windows: [DrainWindow] = []
        for (previous, current) in zip(ordered, ordered.dropFirst()) {
            // Either end charging invalidates the window: the level rose, or it
            // held flat on the charger and would read as "used nothing".
            if previous.charging || current.charging { continue }
            if previous.level < 0 || current.level < 0 { continue }
            if sharingOnly && !(previous.sharing && current.sharing) { continue }
            let seconds = current.at.timeIntervalSince(previous.at)
            // A gap longer than this is the app having been suspended or shut,
            // and attributing a whole night's drain to it would be a lie.
            guard seconds > 0, seconds <= 3600 else { continue }
            let dropped = previous.level - current.level
            guard dropped >= 0 else { continue }
            windows.append(DrainWindow(seconds: seconds, dropped: dropped))
        }
        return windows
    }

    /// Hours of usable evidence — what the drain figure is standing on.
    static func measuredHours(_ samples: [BatterySample], sharingOnly: Bool) -> Double {
        usableWindows(samples, sharingOnly: sharingOnly).reduce(0) { $0 + $1.seconds } / 3600
    }
}

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var level: Double = -1
    @Published private(set) var charging = false

    private let outbox: Outbox
    /// Plain `let`, never `@Published` — a timer handle that the function
    /// starting it also reads is the read-own-write shape that loops.
    private var timer: Timer?

    /// Sampled every five minutes. Often enough to see a preset change inside a
    /// few hours, rare enough that the sampling is not itself a cost.
    private static let interval: TimeInterval = 300
    /// Two weeks at five-minute spacing. Bounded because this rides in the same
    /// atomically-written state file as the upload queue.
    static let maxSamples = 4032

    init(outbox: Outbox) {
        self.outbox = outbox
        UIDevice.current.isBatteryMonitoringEnabled = true
        read()
    }

    deinit { timer?.invalidate() }

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func read() {
        let device = UIDevice.current
        level = Double(device.batteryLevel)
        charging = device.batteryState == .charging || device.batteryState == .full
    }

    /// Take a reading. Best effort throughout — a battery sample must never be
    /// the reason a location fails to save.
    func sample() {
        read()
        guard level >= 0 else { return }
        let entry = BatterySample(at: Date(), level: level, charging: charging, sharing: outbox.state.sharing)
        try? outbox.change {
            $0.battery.append(entry)
            if $0.battery.count > Self.maxSamples {
                $0.battery.removeFirst($0.battery.count - Self.maxSamples)
            }
        }
    }
}

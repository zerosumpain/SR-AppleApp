import Foundation
import Combine
import WidgetKit

/// The app's half of the "Health today" widget: today's activity rings, this
/// phone's steps and — for the owner — the readiness score, left on the
/// shared Keychain shelf (`FamilyShelf`, account `.health`).
///
/// Everything here is what Home already holds: the rings from
/// `ActivityRingsStore`, which watches Apple Health on this phone; the steps
/// from `LiveSteps`, the same count the step board lays over your row; the
/// readiness from Home's own request (`TodayStore`, the owner's alone). The
/// widget extension never reads Apple Health and asks for nothing.
///
/// Home calls `attach` once (one line in `TodayScreen`); from then on a ring
/// moving or a new payload saves a snapshot — and reloads the widget only
/// when it moved enough to see (`HealthWidget.worthReload`): the rings move
/// with every Watch sync.
///
/// Never in demo mode, never while viewing the app as somebody, and only
/// while the family widgets are this phone's (`FamilyWidgetBridge.sync`
/// clears every snapshot the moment they are not).
@MainActor
final class HealthWidgetBridge {
    static let shared = HealthWidgetBridge()

    private var bag: Set<AnyCancellable> = []
    private var pending: Task<Void, Never>?

    private init() {}

    private static var active: Bool {
        if SRDemo.isOn { return false }
        let access = AccessStore.shared
        return access.viewingAs == nil && access.familyBoards
    }

    /// Follow Home's payload and rings. Again with new stores replaces the
    /// old subscription.
    func attach(today: TodayStore, rings: ActivityRingsStore) {
        bag.removeAll()
        today.$payload.combineLatest(rings.$rings)
            // A refresh moves both in the same breath; one save for both.
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] payload, rings in
                self?.update(health: payload?.health, rings: rings)
            }
            .store(in: &bag)
    }

    private func update(health: TodayHealth?, rings: ActivityRingsStore.Rings?) {
        guard Self.active else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            let steps = await LiveSteps.today()
            guard !Task.isCancelled, Self.active else { return }
            let made = Self.snapshot(health: AccessStore.ownerSite ? health : nil, rings: rings, steps: steps)
            // The shelf holds what the widget last drew: only a change worth
            // a reload is written, so small moves add up until they are one.
            guard HealthWidget.worthReload(from: FamilyShelf.load(HealthWidgetSnapshot.self, .health), to: made) else { return }
            if FamilyShelf.save(made, .health) {
                WidgetCenter.shared.reloadTimelines(ofKind: FamilyWidgetKind.health)
            }
        }
    }

    /// The shelf's snapshot of today. The gallery draws this too.
    static func snapshot(health: TodayHealth?, rings: ActivityRingsStore.Rings?, steps: Int?, now: Date = Date()) -> HealthWidgetSnapshot {
        let readiness = health?.readiness
        return HealthWidgetSnapshot(
            day: HealthWidget.day(now),
            rings: (rings?.all ?? []).compactMap { $0 }.map {
                HealthWidgetRing(key: $0.key, label: $0.label, value: $0.value, goal: $0.goal, unit: $0.unit)
            },
            steps: steps,
            readiness: readiness.map { Int($0.score.rounded()) },
            readinessLabel: readiness.map(\.label),
            savedAt: now
        )
    }
}

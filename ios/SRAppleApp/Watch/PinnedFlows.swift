import Foundation
import Combine

/// The workflows the owner pinned to the Watch. Up to three, kept on this
/// phone: which flows deserve a button on a wrist is a choice about this
/// person's day, not a property of the flow, so the site is not told.
@MainActor
final class PinnedFlows: ObservableObject {
    static let shared = PinnedFlows()
    /// Three fit on a watch face without scrolling, and a wrist is too easy to
    /// tap by accident to want more side effects within reach.
    static let limit = 3
    static let key = "watch.pinned-flows"

    @Published private(set) var pins: [WatchSnapshot.PinnedFlow]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([WatchSnapshot.PinnedFlow].self, from: data) {
            pins = Array(saved.prefix(Self.limit))
        } else {
            pins = []
        }
    }

    func isPinned(_ slug: String) -> Bool { pins.contains { $0.slug == slug } }

    var isFull: Bool { pins.count >= Self.limit }

    /// Pin or unpin. Pinning a fourth does nothing — the control says so first.
    func toggle(slug: String, title: String) {
        if let index = pins.firstIndex(where: { $0.slug == slug }) {
            pins.remove(at: index)
        } else {
            guard !isFull else { return }
            pins.append(WatchSnapshot.PinnedFlow(slug: slug, title: title))
        }
        save()
    }

    /// Keep a pinned flow's title current, and drop one the site no longer has.
    func reconcile(with flows: [FlowSummary]) {
        guard !pins.isEmpty, !flows.isEmpty else { return }
        let bySlug = Dictionary(flows.map { ($0.slug, $0.title) }, uniquingKeysWith: { first, _ in first })
        let next = pins.compactMap { pin in
            bySlug[pin.slug].map { WatchSnapshot.PinnedFlow(slug: pin.slug, title: $0) }
        }
        guard next != pins else { return }
        pins = next
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pins) { defaults.set(data, forKey: Self.key) }
    }
}

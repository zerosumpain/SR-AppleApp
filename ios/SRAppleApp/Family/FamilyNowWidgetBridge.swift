import Foundation
import WidgetKit

/// The app's half of the "Family now" widget: each time `FamilyStore` reads a
/// family view that changed, it leaves a privacy-minimal snapshot of it on
/// the shared Keychain shelf (`FamilyShelf`, account `.familyNow`) and tells
/// WidgetKit — only when the snapshot changed. `FamilyStore.load()` calls
/// `save` — the one line the store carries for it.
///
/// The widget cannot read the view for itself: it comes over the companion
/// pairing, whose credential stays in the app. Cleared with every other
/// widget's snapshot on sign-out, revoke or a refusal
/// (`FamilyWidgetBridge.clear`).
///
/// Like `FamilyWidgetBridge`: never in demo mode (the simulator's Keychain is
/// not a phone's), never while viewing the app as somebody — the widget is
/// this phone's person — and only while this person may see the family.
@MainActor
enum FamilyNowWidgetBridge {
    private static var active: Bool {
        if SRDemo.isOn { return false }
        let access = AccessStore.shared
        return access.viewingAs == nil && access.familyBoards && access.allows(.family)
    }

    /// This phone's own view, as read — never a "View as" one.
    static func save(_ view: HouseholdView?) {
        guard active else { return }
        guard let view, view.showsHousehold else {
            // Nobody to show: a "none" viewer, or no view at all.
            if FamilyShelf.read(.familyNow) != nil, FamilyShelf.write(nil, .familyNow) {
                WidgetCenter.shared.reloadTimelines(ofKind: FamilyWidgetKind.familyNow)
            }
            return
        }
        let made = snapshot(view)
        // Compared without the timestamp: the store reads every fifteen
        // seconds while a map is up, and most reads change nothing here.
        guard !made.sameContent(as: FamilyShelf.load(FamilyNowSnapshot.self, .familyNow)) else { return }
        if FamilyShelf.save(made, .familyNow) {
            WidgetCenter.shared.reloadTimelines(ofKind: FamilyWidgetKind.familyNow)
        }
    }

    /// The shelf's snapshot of a view. The gallery draws this too.
    static func snapshot(_ view: HouseholdView, now: Date = Date()) -> FamilyNowSnapshot {
        let initials = view.initials
        // Colour slots dealt as `SR.PersonHue.assign` deals them — the
        // subjects sorted — so a circle on the widget is the colour of the
        // same person's pin.
        let slots = Dictionary(uniqueKeysWithValues: Array(Set(view.people.map(\.subject))).sorted().enumerated().map { ($1, $0) })
        // Distance from home where home is known, as the Orbit measures it.
        let home = FamilyOrbitMath.home(people: view.people, watch: view.watch)
        let people = view.people.map { person -> FamilyNow.Input in
            let km = home.flatMap { home in
                person.position.map { FamilyOrbitMath.distanceKm(home, GeoPoint(lat: $0.lat, lon: $0.lon)) }
            }
            return FamilyNow.Input(
                name: person.name, initials: initials[person.subject] ?? person.initial, isSelf: person.isSelf,
                status: person.status, movingMode: person.moving?.mode, place: person.placeName, km: km,
                battery: person.batteryPct, lastSeenAt: person.lastSeenAt, hue: slots[person.subject] ?? 0
            )
        }
        return FamilyNow.snapshot(people, now: now)
    }
}

/// Where the glance widgets' links land (`GlanceLink`). Somebody without the
/// tab lands on Today, as every other way in does (`Router.show`).
extension Router {
    func openGlance(_ link: GlanceLink) {
        switch link {
        case .family:
            show(.family)
        case .health:
            show(.health)
        case .games(let room, let game):
            if let room { openGame(room, game: game) } else { show(.games) }
        }
    }
}

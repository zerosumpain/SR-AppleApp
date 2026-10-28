import SwiftUI

// The physics games — Lander and Car Race — are played on this phone, with
// no room on the site: they work with no signal at all, and keep their bests
// here (`PhysicsScores.swift`). They sit on the Games shelf beside the room
// games as `GameKind` cases, but a card opens the game itself rather than
// the new-game sheet.

/// Navigation value for a physics game, pushed on the Games stack.
struct PhysicsGameRef: Hashable {
    let kind: GameKind
}

extension GameKind {
    /// Played on this phone, offline, rather than in a room on the site.
    var playsOnPhone: Bool { self == .lander || self == .carRace }

    /// The shelf this game belongs on, for a games page that groups by kind.
    /// Only the physics games say so here; the others are the shelf's business.
    var physicsCategory: String? { playsOnPhone ? "physics" : nil }
}

/// The physics game for `kind`.
struct PhysicsGameScreen: View {
    let kind: GameKind

    var body: some View {
        switch kind {
        case .carRace:
            CarRaceScreen()
        default:
            LanderScreen()
        }
    }
}

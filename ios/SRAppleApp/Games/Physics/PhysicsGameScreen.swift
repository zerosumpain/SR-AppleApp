import SwiftUI

// The games played on this phone — the physics games (Lander, Car Race, Car
// Racer+, Mini Golf, Pinball, Tilt Maze, Orbit) and the puzzles (Solitaire,
// 2048, Minesweeper, Snake) — with no room on the site: they work with no
// signal at all, and keep their bests here (`PhysicsScores.swift` and each
// game's own store). They sit on the Games shelf beside the room games as
// `GameKind` cases, but a card opens the game itself rather than the new-game
// sheet.

/// Navigation value for a game played on this phone, pushed on the Games stack.
struct PhysicsGameRef: Hashable {
    let kind: GameKind
}

extension GameKind {
    /// The games played on this phone, offline, rather than in a room on the site.
    static let onPhone: Set<GameKind> = [
        .lander, .carRace, .carRacerPlus, .miniGolf, .pinball, .tiltMaze, .orbit,
        .solitaire, .merge2048, .minesweeper, .snake, .skyHopper,
    ]

    /// Played on this phone, offline, rather than in a room on the site.
    var playsOnPhone: Bool { Self.onPhone.contains(self) }

    /// The shelf this game belongs on, for a games page that groups by kind.
    /// Only the phone's own games say so here; the others are the shelf's business.
    var physicsCategory: String? { playsOnPhone ? GameCategory.of(rawValue).rawValue : nil }
}

/// The game played on this phone for `kind`.
struct PhysicsGameScreen: View {
    let kind: GameKind

    var body: some View {
        switch kind {
        case .carRace:
            CarRaceScreen()
        case .carRacerPlus:
            CarProScreen()
        case .miniGolf:
            MiniGolfScreen()
        case .pinball:
            PinballScreen()
        case .tiltMaze:
            TiltMazeScreen()
        case .orbit:
            OrbitScreen()
        case .solitaire:
            SolitaireScreen()
        case .merge2048:
            Merge2048Screen()
        case .minesweeper:
            MinesweeperScreen()
        case .snake:
            SnakeScreen()
        case .skyHopper:
            SkyHopperScreen()
        default:
            LanderScreen()
        }
    }
}

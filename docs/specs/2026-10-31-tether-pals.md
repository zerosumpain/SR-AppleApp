# Tether Pals

Status: built 2026-10-31 (overnight, unattended). Lane `phone`, id `tether-pals`, Swift case
`tetherPals`, folder `ios/SRAppleApp/Games/Physics/TetherPals/`. The family's idea: "A 2D
platformer that requires teamwork. You would have basic controls (left, right, jump) and you
would be able to be tied together sometimes and sometimes be required to stack on top of each
other in order to cross larger gaps."

## The game

A side-on co-op platformer on one phone. Two or three round little pals (Pip — coral, Bo —
sky blue, Kit — mint) must **all** reach the flag. A level is cleared only when every pal is
standing in the flag's zone at the same moment (for 0.3 s). Each level is one hand-made
screen, 16 × 10 tiles, drawn in Canvas in a pastel world of our own.

### Rules (all in `TetherPalsLogic.swift`, Foundation only)

- A fixed step of 1/120 s. Units are tiles; y grows downward. A pal is a 0.8 × 0.8 box.
- **Left, right, jump.** Run 4.5 tiles/s, instant on the ground, air steering at 40 tiles/s².
  A jump rises 1.6 tiles: a 1-tile step is easy, a 2-tile wall is not. Coyote time 0.08 s and
  a 0.12 s jump buffer make jumps forgiving. Full-height jumps only (no variable height): a
  child's quick tap still jumps properly.
- **Stacking.** Pals are one-way platforms for each other: you pass through a pal sideways
  but land on their head from above. To climb on, walk into your pal and jump. A pal carrying
  someone walks at 60 % speed and carries the rider along (the stack shuffles together).
- **The head boost** (decision): a jump off a pal's head is a springy one — 2.2 tiles high
  and up to 7 tiles/s sideways. That is what lets a stack "cross larger gaps": a 4-tile pit
  is too far for any pal alone (max ≈ 3.2 tiles) but easy off a friend's head, and a 2-tile
  wall is easy from a head (3.0 tiles) but impossible from the ground (1.6). Tests prove both.
- **The rope** (tied levels only): consecutive pals (Pip–Bo, Bo–Kit) are joined by a 4-tile
  rope. When it is taut: two pals on the ground share the pull (walking drags your pal along
  at half speed); a pal on the ground holds firm against one in the air (so a pal who slips
  off an edge dangles, and is hauled up as the other walks away — up a pit wall or up a
  2-tile ledge); two pals in the air share it. Decision: a grounded pal is never dragged by an
  airborne one — it is predictable, nobody gets yanked into a pit by a falling friend.
- **Buttons, doors, bridges**, in two colours (gold and blue). A door is solid unless a
  button of its colour is pressed; a bridge is solid only while one is pressed. A door never
  shuts (nor a bridge appears) on a pal standing in it.
- **Prickles and pits.** Touching prickles or falling off the bottom pops a pal back to its
  start after 0.7 s. In a tied level the whole team pops together (the rope would otherwise
  yank across the screen). Nobody is ever out for long, and Restart is always there.
- No timer ends a run. The clock runs from the first button press to the flag.

### Levels (`TetherPalsLevels.swift`), one new trick at a time

| # | Name | Trick | Par |
|---|---|---|---|
| 1 | First steps | run, jump a gap, climb a stair | 25 s |
| 2 | Up on my head | stack to reach a high ledge; a button makes a step for your pal | 40 s |
| 3 | Hold the door | take turns holding buttons either side of a door | 35 s |
| 4 | Big leap | head boost over a 4-tile pit; a button makes a bridge | 35 s |
| 5 | Prickle wall | prickles; over a wall, then open its door from behind | 40 s |
| 6 | High button | stand on a head to reach a button on a shelf | 40 s |
| 7 | Tied together | the rope: jump gaps together | 30 s |
| 8 | Haul away | climb up, then haul your pal up after you | 35 s |
| 9 | Up and up | two climbs, two hauls | 45 s |
| 10 | Rope and doors | rope, doors and a haul | 50 s |
| 11 | Two keys | gold and blue buttons, a boost and a climb | 50 s |
| 12 | All together now | doors, a pit and a haul, tied | 60 s |

Every level carries a scripted walkthrough (`TetherPalsMove`s) that the demo plays and the
tests run through the real rules, for teams of two and three: every level is proved
solvable. Pars are 3–6 × the autopilot's time.

## Players and controls

- **Solo** (two pals): one strip — ◀ ▶, a big **Swap** button (switches which pal you drive;
  the others stand still) and **Jump**.
- **2 players / 3 players** (two / three pals): one strip per player, stacked along the
  bottom, colour-matched to their pal, each ◀ ▶ Jump. Every finger is tracked on its own
  (`UIView` multi-touch, as Pinball's `PinballTouchPad`), so all thumbs work at once; a
  finger can slide between ◀ and ▶. The hit zones are pure maths (`TetherPalsPadLayout`),
  tested. No pass-the-phone: the shared goal is the co-op.
- The pad holds the system swipe-back while on screen (`SwipeBackHold`); the back button stays.
- VoiceOver: the pad is one element with custom actions per pal (step left, step right,
  jump, swap); the board describes where each pal is and what it stands on.

## Scoring, bests, progression

- A cleared level records the team time; the best per level is kept, plus a star when the best
  is under par. Levels open in order (one past the furthest cleared). The intro card shows
  stars and bests per level and remembers the last level and player count.
- `TetherPalsRecords` in `UserDefaults` under `tether-pals.records.v1`, lenient decoding,
  saved the moment a level is cleared. The demo (`SRDemo.isOn`) never saves and opens every
  level.

## Screens

- **Start card** (`tether-pals-intro`): kicker, hook "Everyone to the flag. Nobody gets left
  behind.", four how-to rows, the player picker (Solo / 2 players / 3 players), the level
  strip (locked, open, starred), best and par, Play (`tether-pals-start`).
- **Ready**: the level behind a hint with the level's tip and "Press any button to start".
- **Playing**: HUD (Level, Time, Best, Pause `tether-pals-pause`); a line with the level
  name, rope/par chips and Restart (`tether-pals-restart-level`); the board
  (`tether-pals-board`); the pad (`tether-pals-pad`).
- **Pause card** (`tether-pals-paused`): the level's tip, Resume, **Show me how**
  (`tether-pals-show-me`: the pals play the level's own walkthrough from the start, untimed and
  not kept, then it is "Your turn" — so a stuck child is never stuck), Restart
  (`tether-pals-restart`), Levels. Leaving the app pauses; resuming waits for a button press.
- **Result card** (`tether-pals-over`): LEVEL CLEARED / NEW BEST / ALL LEVELS CLEARED, the
  time, best, par and star chips, pops on the way, what opened; Next level
  (`tether-pals-next`), Play again (`tether-pals-again`), Levels. Confetti on a clear.
- Feedback: haptics on landing on a head, a boost, a button, a pal reaching the flag (tap /
  select), a pop (bad), a clear (ok); poofs, dust, boost sparkles, flag sparkles and
  confetti in the Canvas; nothing bobs or bursts under Reduce Motion.

## Files

Pure (Foundation only, in `PURE`): `TetherPalsLogic.swift` (rules, world, step, events),
`TetherPalsLevels.swift` (level parsing and the 12 levels with scripts),
`TetherPalsAutopilot.swift` (the scripted pilot), `TetherPalsRecords.swift` (records, store,
result), `TetherPalsPadLayout.swift` (pad hit zones, time formatting, effects random).

SwiftUI: `TetherPalsScreen.swift`, `TetherPalsSession.swift`, `TetherPalsCards.swift`,
`TetherPalsControls.swift`, `TetherPalsPainter.swift`.

Registry: `GameModels.swift` (case, title, line, blurb, icon `person.2.fill`, difficulty line),
`GameRoomViews.swift`, `PhysicsGameScreen.swift` (`onPhone` + switch), `GamesShelf.swift`
(`"tether-pals": .physics`), `GamesPagePlan.swift` (motif `.hills`, `newGames`),
`Access/WhatsNew.swift` (a release at the top), `scripts/home-check.sh` (`PURE`, `TESTS`).

## Tests

`ios/SRAppleAppTests/TetherPalsLogicTests.swift` (rules: running, jumping, the 1-tile step
and 2-tile wall, landing on a head, carrying, head boost, the 4-tile pit, rope drag and
haul, buttons/doors/bridges, prickles and pits pop, tied pops, the all-home rule,
determinism) and `TetherPalsLevelsTests.swift` (every level parses with a flag and spawns,
every level is solved by its walkthrough for two and three pals and under par, the
teamwork levels cannot be done alone, the autopilot is deterministic, records keep the best
and open levels in order, round trip and older saves, pad hit zones, time format).
UI: `ios/SRAppleAppUITests/SuggestedTetherPalsUITests.swift` — demo launch, Games tab, On
this phone, the tile, start / playing / result screenshots.

## Left out, and why

- Phone-to-phone nearby play: one phone with a strip per player covers the ask; nearby would
  need the Play nearby contract and a shared engine sync (PHONE_GAMES §11 says add it last).
- Rope wrapping round corners: the rope is a straight distance limit; levels are drawn so
  hauls go up open ledges.

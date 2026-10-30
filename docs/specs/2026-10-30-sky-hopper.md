# Sky Hopper — spec (2026-10-30)

Lane `phone`, id `sky-hopper`, case `GameKind.skyHopper`, folder
`ios/SRAppleApp/Games/Physics/SkyHopper/`, screen `SkyHopperScreen`.
Fintan's idea, in the family's words: "You are constantly jumping on small
floating platforms some might have springs or power ups and you can either
your buttons or tilt to move across the screen."

Built unattended; every decision below was taken without asking and is
written down here.

## The game

An endless upward bouncer. Hop, a round little puffball, bounces by itself
every time it lands on a cloud. The player only steers left and right. The
sky scrolls up as Hop climbs; going off one side brings Hop in on the other.
A run ends when Hop falls below the bottom of the window.

- **World**: 100 units wide; height counts up. The window shows
  `viewHeight` units (set from the board's shape, 110–220). The camera only
  rises: it keeps Hop at 42 % of the window.
- **Physics** (fixed 1/120 s steps, `SkyHopperRules`): gravity 300 u/s²,
  bounce 165 u/s (about 45 u high), spring 290 u/s (about 140 u), steering
  top speed 120 u/s, eased at rate 10/s. Landing counts only while falling and
  only through the cloud's top edge (Hop passes up through clouds).
- **Clouds** (`SkyHopperCloudKind`):
  - *plain* — white;
  - *sliding* — pale blue with wind streaks, glides side to side, faster
    higher up;
  - *crumbly* — cream with cracks: one bounce, then it crumbles and falls;
  - *blinking* — the "few that vanish": see-through, fades out and back on a
    3-second cycle, solid only while it is showing. Only ever an extra cloud,
    never one the way up depends on.
- **Springs** sit on plain and sliding clouds; landing within 6 u of the
  spring launches Hop. A short column of stars floats above each spring.
- **Power-ups** (our own): *propeller cap* (3.2 s of steady lift, no landing
  needed), *bubble* (saves one fall: Hop bounces back up from the bottom),
  *magnet* (8 s: stars within 40 u fly to Hop).
- **Stars**: floating coins between clouds, 5 points each.
- **Height zones** (named in the status line, a toast on entering, sky
  colour follows): Meadow sky 0 m, High breeze 150 m, Sunset 400 m,
  Twilight 800 m, Starlight 1300 m, Edge of space 2000 m. 1 m = 5 u.

## Fairness and difficulty (`SkyHopperGenerator`, seeded SplitMix64)

The generator lays a *path* of clouds; each is the next cloud's guaranteed
stepping stone. Difficulty `d = min(1, climb / 7000 u)`:

- path gap `12 + 12d … 22 + 17d` units, never more than `fairGap` (40 u,
  below the 45 u bounce); at that gap Hop has time to steer 50 u (half the
  wrapping width) even from full speed the wrong way, so **any x is
  reachable** — tested;
- path clouds shrink from 18 to 14 wide; sliding chance 5 % → 35 %, crumbly
  0 → 22 % (none below 30 m); path clouds are never blinking;
- extra clouds 60 % → 25 % a gap (more at the start);
- springs 12 % → 7 %; power-ups 8 % → 1.5 % a path cloud;
- the first 30 seconds are fixed in kind: the start is a full-width home
  cloud, the 4th path cloud has a spring, the 10th a propeller cap.

## Controls

Chosen on the start card (`SkyHopperControl`): **Tilt** (default when the
phone has a sensor) or **Buttons**.

- Tilt: `PhysicsTilt`, read once a frame; 0.03 g dead zone, 0.30 g is full
  speed. The first reading of every start and resume is "straight"; a
  recentre button (`sky-hopper-recentre`) sits under the board.
- Buttons: two big hold buttons (`sky-hopper-left`, `sky-hopper-right`),
  half the width each, under the board. Used automatically with no motion
  sensor and for VoiceOver (where each activation steers for 0.35 s).
- Demo (`SRDemo.isOn`): seed 7, an autopilot (`SkyHopperAutopilot`) that
  climbs for about 20 seconds of play, then lets Hop fall, so the results
  card appears; nothing saved.

## Scoring, bests and progression

- Score = metres climbed + 5 × stars. HUD: Score, Best, Stars, Pause.
- `SkyHopperRecords` under `sky-hopper.records.v1`: a best (score, metres,
  stars, games) per control, `"tilt"` and `"buttons"`; total stars; games;
  last control and colour. Lenient decoding. Demo games are not saved.
- Hop's colours open with stars collected across all games: Sunny (0), Mint
  (50), Berry (150), Ocean (300), Rainbow (600). A toast the moment one opens
  mid-run; listed on the results card; picked on the start card.

- A run lasts minutes, not hours, so (like Snake) a run in progress is not
  kept across launches; leaving the app pauses it, leaving the screen ends it.

## Players

One player on this phone. (The idea is single-player; no pass-the-phone.)

## Screens

- **Start card** (`sky-hopper-intro`): kicker SKY HOPPER, "Bounce from cloud
  to cloud. Don't look down.", four how-to rows (steering, springs, power-ups,
  crumbly clouds), Tilt/Buttons tiles with that control's best, colour
  swatches, Play (`sky-hopper-start`).
- **Ready**: the sky visible with Hop on the home cloud and a hint ("Tap the
  sky to start"); a tap on the board or a steer button starts. After a
  pause the same hint says "carry on".
- **Playing**: HUD on top (`sky-hopper-score`, `sky-hopper-best`,
  `sky-hopper-stars`, `sky-hopper-pause`), zone line with power-up timers,
  the sky (`sky-hopper-board`, spoken description), the controls.
  Back button hidden while steering (buttons are held).
- **Pause card** (`sky-hopper-paused`): Resume, Restart, Menu.
- **Results card** (`sky-hopper-over`): kicker NEW BEST (good) or GAME OVER
  (error), how it ended ("A crumbly cloud gave way at 212 m."), a tip, chips
  for Height, Stars, Score, a tally line, colours opened, Play again
  (`sky-hopper-again`) and Menu. Confetti on a new best (not under Reduce
  Motion).

Art is Canvas only: a sky gradient by zone, sun, distant clouds and hills
with parallax, stars at height, cartoon clouds, Hop with squash and stretch,
puffs, sparkles and "+5" pops. Reduce Motion: no shake, bob or confetti.
The board keeps its own palette (a framed window), so it reads in light
and dark; HUD and cards are SR.

## Files

Pure (Foundation only, in `PURE`):
- `SkyHopperLogic.swift` — random, rules, kinds, zones, game state, step.
- `SkyHopperGenerator.swift` — the seeded cloud and pickup layout.
- `SkyHopperAutopilot.swift` — the demo pilot.
- `SkyHopperRecords.swift` — controls, colours, bests, store.

SwiftUI: `SkyHopperScreen.swift` (screen, HUD, sky, card layer),
`SkyHopperSession.swift` (engine, `FrameTicker`, `PhysicsTilt`, sparks),
`SkyHopperCards.swift` (start, pause, results cards and their tiles),
`SkyHopperControls.swift` (hold arrows, tilt bar, HUD boxes, power chips),
`SkyHopperScene.swift` (the `Canvas` frame and parallax backdrop),
`SkyHopperArt.swift` (clouds, springs, pickups, Hop), `SkyHopperPaint.swift`
(the sky and Hop palettes).

## Registry edits

GameModels (case after `snake`, title, line, blurb, icon
`arrow.up.circle.fill`, difficulty group), GameRoomViews, `GameKind.onPhone`,
`PhysicsGameScreen` switch, `GameCategory.known` → `.physics`,
`GamesTileMotif.known` → `.bubbles` (round puffs read as clouds),
`GamesPagePlan.newGames`, What's new release `2026-10-30-sky-hopper`,
`scripts/home-check.sh` PURE and TESTS.

## Tests

`SkyHopperLogicTests.swift` and `SkyHopperRecordsTests.swift` (Linux):
determinism, random range, bounce/spring/landing-from-above, wrap, each
cloud kind, power-ups, stars and magnet, falling ends the run, bubble save,
camera never falls, scoring, zones, difficulty monotonic and capped, gaps
fair, reach covers the width, autopilot climbs many seeds, demo run ends,
records best per control, colours unlock, round trip and old save.

`SuggestedSkyHopperUITests.swift`: `-SRDemo`, Games tab, search, open,
start, screenshots "Suggested — Sky Hopper — start / playing / result"
(plus a soft "paused").

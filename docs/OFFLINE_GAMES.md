# Play nearby — offline games

Games for one phone or for phones in the same room, with **no internet, no server and
no pairing**. Alone, the phone runs the game and fills empty seats with computer players
(§5). Together, one phone hosts and *is* the server; up to four more join it, over
**Nearby** (MultipeerConnectivity: Bluetooth + peer-to-peer Wi-Fi, no router) and
**Wi-Fi / hotspot** (Network.framework TCP on a shared Wi-Fi, the host's Personal Hotspot,
or phone-to-phone Wi-Fi) *at the same time* — `OfflineDualLink`, so nobody has to pick.
Playing never calls Strange Ramblings; afterwards each phone's results wait in
`OfflineResultStore` and go to `POST api/native/games/offline-results` once it is online
and paired (§9).

This document is the contract. If you are adding a game, read **§3–§8** and copy the
reference game, Quick Draw (`ios/SRAppleApp/Offline/Games/QuickDraw/`).

---

## 1. Where things are

```
ios/SRAppleApp/Offline/
  Core/        Foundation-only. Compiled and tested on Linux by scripts/offline-check.sh.
    OfflineGameRules.swift   the OfflineGameRules protocol, OfflineGameInfo, OfflineGameCategory,
                             OfflinePlayer, OfflineStanding, OfflineRefusal, OfflineGameContext
    OfflineRNG.swift         the seeded generator (SplitMix64) — the only randomness
    OfflineCard.swift        OfflineCard / OfflineSuit: the shared 52-card deck
    OfflineClock.swift       OfflineUptime, OfflineHostClock, OfflineClockEstimator, OfflineReaction
    OfflineMatch.swift       OfflineCoding (JSON), OfflineMatch / OfflineMatchOf (type erasure), OfflineGameEntry
    OfflineWire.swift        OfflineEnvelope, OfflineMessage, OfflineLobby, OfflineViewPacket …
    OfflineRoom.swift        OfflineRoom: the host's pure room reducer
    OfflineAddress.swift     TCP framing, typed-address parsing, which local address to show,
                             OfflineName (names cut to Bonjour/MPC byte limits), OfflineTXT
    OfflineDiscovery.swift   OfflineTransport, OfflineFoundHost, merging two links' rooms,
                             OfflinePeerHealth, OfflineReconnect, OfflineRoundTrip
    OfflinePlayModes.swift   which games can be played alone / nearby, online → offline twins
    OfflineResults.swift     OfflineResult, OfflineResultQueue: results waiting to sync
    OfflineRulesAudit.swift  generic checks every game's tests run
    OfflineWords.swift       the word games' list: OfflineWordList (packed, sorted, binary search),
                             OfflineWords.shared (read from the bundle on first use)
  Words/       offline-words.txt — ~71k words of 3–9 letters from SR-Main's Boggle/Anagram lists
               (regenerate: node scripts/build-offline-words.mjs <SR-Main>); bundled as a resource
  Link/        OfflineLink protocol, OfflineNearbyLink (MPC), OfflineHotspotLink (NWListener/NWBrowser),
               OfflineDualLink (both at once — the default)
  Session/     OfflineSession (@MainActor ObservableObject, one shared instance),
               OfflineResultStore (the queue on disk, and the sync)
  UI/          OfflineGamesScreen (the page), OfflineRoomScreen (the cover: join/lobby/game/results),
               OfflineSoloScreen (one game from the Games page, `SoloGameRef`),
               OfflineCatalogue (the list of games), OfflineGameKit (cards, hand, countdown,
               standings, OfflineStimulus for reaction games)
  Games/<GameName>/
    <GameName>Logic.swift    the rules — Foundation only
    <GameName>View.swift     the SwiftUI view
ios/SRAppleAppTests/Offline<GameName>Tests.swift   the rules' tests
```

XcodeGen picks up every `.swift` under `ios/SRAppleApp` and `ios/SRAppleAppTests`
recursively: **creating files is all it takes** — never edit the project files.

How people get there: a **Play nearby** card on the Games page (`games-offline`) and an
always-on **Play nearby** tile in More (`more-offline`), both pushing `OfflineGamesRef()`,
registered once in `ContentView.placeDestinations()`. More shows it to everyone — paired
or not, games access or not.

---

## 2. How a room works

```
           guest phone                                      host phone (the server)
  ┌─────────────────────────┐                      ┌──────────────────────────────────┐
  │ OfflineSession (guest)  │ ── hello ──────────▶ │ OfflineSession (host)            │
  │                         │ ◀─ welcome, lobby ── │   OfflineRoom  (pure reducer)    │
  │ <Game>View(context)     │ ── action(Data) ───▶ │     └ OfflineMatchOf<Rules>      │
  │   context.send(.move)   │ ◀─ view(Data) ────── │         State + OfflineRNG       │
  │                         │ ◀─ refusal ───────── │   ~10 Hz Timer → room.tick(now)  │
  │   ping ────────────────▶│ ◀─ pong(hostNow) ─── │   room.outbox() → per-player     │
  └─────────────────────────┘                      │   lobby + view, only if changed  │
                                                   │ the host's own view is delivered │
                                                   │ locally through the same outbox  │
                                                   └──────────────────────────────────┘
```

- The **host holds the only real state** and runs every rule. Each player is sent only
  `Rules.view(of: state, for: theirId)` — the redaction happens on the host, so a guest's
  phone never holds another player's cards.
- **Guests send actions** (`OfflineMessage.action(seq:match:data:)`); an illegal one comes
  back as `refusal(seq:reason:)` and the room screen shows the sentence as a banner.
- The host is a player too and goes through **exactly the same path**: its actions go
  into `OfflineRoom.act`, its lobby and view come out of `OfflineRoom.outbox()`.
- The host ticks the running match ~10 times a second (`Rules.tick`) — timers, dealer turns,
  scheduled stimuli, "next round in 3".
- Up to **5 players including the host** (`OfflineRoom.capacity`). A sixth `hello` is
  refused with a sentence. A player who joins mid-match **watches** (spectator view,
  `view(of:for: nil)`) and plays the next one.
- A guest who drops **mid-match keeps their seat** (marked away) and the seat is **held
  for `OfflineRoom.seatHeld`** (the guest's reconnect patience plus 10 s): the game is not
  told, so a two-player match survives a radio blip. The same player id reconnecting in
  that time retakes the seat and is re-sent the lobby and their view. Once the hold runs
  out (or at once, for a guest who pressed Leave and sent `bye`), `Rules.playerLeft` is
  called, and if fewer than `info.minPlayers` remain, with no other seat still held, the
  match ends with `Rules.standings` as it stands. In the lobby a dropped guest is simply
  removed.
- **Host leaving ends the room** for everyone.
- After a match the lobby's phase is `.finished` with the standings; the host chooses
  *Play again* or *Pick another game*.

### Wire

One JSON object per message, `OfflineEnvelope { v: 1, message: OfflineMessage }`:

| message | direction | meaning |
|---|---|---|
| `hello(playerId:name:version:)` | guest → host | first thing on connecting |
| `welcome(playerId:hostId:roomName:)` | host → guest | you are in |
| `refused(reason:)` | host → guest | you are not (full, other version) |
| `lobby(OfflineLobby)` | host → all | players, chosen game, phase, match number, standings |
| `view(OfflineViewPacket)` | host → one | `gameId`, `match`, `data` = the game's `PlayerView` JSON, `over` |
| `action(seq:match:data:)` | guest → host | `data` = the game's `Action` JSON |
| `refusal(seq:reason:)` | host → guest | that action was illegal |
| `ping(id:sentAt:)` / `pong(id:sentAt:hostNow:)` | guest ↔ host | clock offset |
| `bye(reason:)` | either | leaving / room closed |

Choosing a game, Start and Play again are host-local decisions; guests see them in the
next `lobby`. MultipeerConnectivity carries each envelope as one reliable packet; the TCP
link frames each as a 4-byte big-endian length + JSON (`OfflineFraming`).

---

## 3. The rules contract (exact)

```swift
protocol OfflineGameRules {
    associatedtype State: Codable & Equatable
    associatedtype Action: Codable & Equatable
    associatedtype PlayerView: Codable & Equatable

    static var info: OfflineGameInfo { get }

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State
    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws
    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG)          // default: does nothing
    static func view(of state: State, for playerId: String?) -> PlayerView
    static func isOver(_ state: State) -> Bool
    static func standings(_ state: State) -> [OfflineStanding]
    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG)  // default: does nothing
}
```

Note the one refinement from the original sketch: `start` takes `rng: inout OfflineRNG`
(seeded by the host) instead of a raw seed, so *all* randomness — the deal and every later
draw — flows through one generator.

Conform with a **caseless enum** named `<GameName>Rules`:

```swift
enum CrazyEightsRules: OfflineGameRules { … }
```

Rules for the rules:

1. **Foundation only.** `<GameName>Logic.swift` must contain exactly one import:
   `import Foundation`. The check script fails otherwise.
2. **Times are host-clock seconds** (`Double`, the host's monotonic uptime). Use the `now`
   you are given; never call `Date()`, `ProcessInfo`, `CFAbsoluteTime…` in rules.
   Store deadlines as absolute host times in `State` (`turnEndsAt = now + 30`).
3. **Randomness only from `rng`** — `rng.int(below:)`, `rng.int(in:)`, `rng.double(in:)`,
   `rng.chance(_:)`, `rng.pick(_:)`, `rng.shuffle(&array)`, `rng.shuffled(array)`,
   `OfflineCard.shuffledDeck(&rng)`. Never `Int.random`, `.shuffled()`, `.randomElement()`,
   `UUID()`, nor the stdlib `…(using: &rng)` forms (their algorithm may change between Swift
   versions; ours are written out). The audit fails a game whose `start` is not reproducible.
4. **No iteration over `Set` or `Dictionary` where order matters** (turn order, deal order,
   tie-breaks, the order of rows in a view). Keep players in an array in seat order
   (`players` as given to `start`) and look things up by id. Dictionaries are fine for
   lookups (`scores: [String: Int]`).
5. **`apply` validates and throws `OfflineRefusal("Sentence for the player.")`** for anything
   illegal: not your turn, card not in hand, wrong phase, stale round. The sentence is shown
   verbatim — write it for a person ("It's Ben's turn.", "You don't have that card.").
   The host applies to a **copy**, so a throw after partial mutation is harmless.
6. **`tick` must be idempotent at a repeated `now`** (the audit ticks twice at the same
   instant and requires no change) and must cope with being called late (a ~10 Hz timer
   can jitter; compare `now >= deadline`, never `==`).
7. **`view(of:for:)` hides secrets.** Other players' hands become counts, hidden answers
   become nil, the deck becomes a count. `playerId == nil` is a spectator: show only public
   information. Keep views small and free of history the screen does not draw — every
   change is sent to every player.
8. **`isOver`** turns true once the match is decided (it is fine to keep a final "result"
   phase visible for a few seconds before it turns true, as Quick Draw does).
9. **`standings`** lists **every player who started**, exactly once, best first. Use
   `OfflineStanding.ranked(players, score: { … }, detail: { … }, lowerIsBetter: false)`;
   ties share a rank. It may be called mid-match (a player drop can end the match early).
10. **`playerLeft`**: skip their turns, fold or discard their hand, resolve anything that was
    waiting on them. If the game cannot continue, set your state so `isOver` is true (the
    room also ends any match that falls below `minPlayers`).
11. All nested types live **inside** the rules enum (`CrazyEightsRules.State`,
    `.Action`, `.PlayerView`, `.Phase`, …) so names never clash across games.
12. `Action` is usually an enum with associated values (`case play(card: OfflineCard)`,
    `case draw`, `case tap(round: Int, ms: Int)`); synthesized `Codable` is fine. Include a
    round/turn number in actions that could arrive late, and refuse stale ones.

### `OfflineGameInfo`

```swift
OfflineGameInfo(
    id: "crazy-eights",            // kebab-case, unique, stable (travels on the wire)
    title: "Crazy Eights",
    blurb: "Match the suit or the number; eights are wild.",   // one sentence
    category: .card,               // .card | .reaction | .skill
    minPlayers: 2, maxPlayers: 5,  // 1…5; most games 2…5
    symbol: "suit.club.fill",      // an SF Symbol that exists on iOS 17
    howToPlay: ["One short rule per line.", "Four to six lines."]
)
```

`info.playersLabel` → "2–5 players"; `info.allows(count)`.

### Shared Core types you will use

```swift
struct OfflinePlayer: Codable, Equatable, Hashable, Identifiable { let id: String; var name: String }
struct OfflineStanding: Codable, Equatable, Identifiable {
    let playerId: String; let name: String; let rank: Int; let score: Int; let detail: String?
    static func ranked(_ players: [OfflinePlayer], score: (OfflinePlayer) -> Int,
                       detail: (OfflinePlayer) -> String? = { _ in nil },
                       lowerIsBetter: Bool = false) -> [OfflineStanding]
}
struct OfflineRefusal: Error, Equatable, Codable { let reason: String; init(_ reason: String) }
struct OfflineRNG: RandomNumberGenerator, Codable, Equatable {
    init(seed: UInt64)
    mutating func next() -> UInt64
    mutating func int(below bound: Int) -> Int            // 0..<bound, bound > 0
    mutating func int(in range: ClosedRange<Int>) -> Int
    mutating func unit() -> Double                        // 0..<1
    mutating func double(in range: ClosedRange<Double>) -> Double
    mutating func chance(_ p: Double) -> Bool
    mutating func pick<T>(_ items: [T]) -> T?
    mutating func shuffle<T>(_ items: inout [T])
    mutating func shuffled<T>(_ items: [T]) -> [T]
}
enum OfflineReaction {
    static let anticipationMs = 100                        // under this = a guess, not a reaction
    static func ms(shownAt: Double?, touchedAt: Double) -> Int?
    static func counts(_ ms: Int) -> Bool
}
```

### The shared playing cards (`OfflineCard.swift`)

```swift
enum OfflineSuit: String, Codable, CaseIterable, Identifiable { case clubs, diamonds, hearts, spades
    var symbol: String   // ♣ ♦ ♥ ♠ (text presentation)
    var letter: String   // C D H S
    var isRed: Bool
    var name: String     // "clubs"
}
struct OfflineCard: Codable, Hashable, Identifiable, CustomStringConvertible {
    let suit: OfflineSuit
    let rank: Int                      // 1 = ace, 2…10, 11 = J, 12 = Q, 13 = K
    init(_ rank: Int, _ suit: OfflineSuit)   // OfflineCard(12, .hearts)
    var id: String        // "QH", "10S", "AD" — unique within ONE deck
    var rankText: String  // "A", "2"…"10", "J", "Q", "K"
    var text: String      // "Q♥"
    var name: String      // "queen of hearts" (VoiceOver, sentences)
    var highRank: Int     // ace = 14
    var isFace: Bool
    var isRed: Bool
    static func deck() -> [OfflineCard]                                    // 52, fixed order
    static func shuffledDeck(_ rng: inout OfflineRNG, decks: Int = 1) -> [OfflineCard]
    static func deal(_ count: Int, to hands: Int, from deck: inout [OfflineCard]) -> [[OfflineCard]]  // off the END
    static func sortedForHand(_ cards: [OfflineCard], acesHigh: Bool = true) -> [OfflineCard]
}
```

No jokers. With more than one deck, card ids repeat — `ForEach` over
`Array(cards.enumerated())` with `id: \.offset`.

---

## 4. The view contract

One SwiftUI view per game, `<GameName>View.swift`, shaped exactly like this:

```swift
import SwiftUI

struct CrazyEightsView: View {
    let context: OfflineGameContext<CrazyEightsRules>
    var body: some View { … }
}
```

`OfflineGameContext<Rules>` (Core/OfflineGameRules.swift) gives the view everything:

| property | type | meaning |
|---|---|---|
| `view` | `Rules.PlayerView` | what I may see now (decoded for you) |
| `me` | `String` | my player id — compare with ids in the view |
| `players` | `[OfflinePlayer]` | everyone in the room, seat order, host first |
| `isHost` | `Bool` | this phone hosts |
| `clock` | `OfflineHostClock` | host time (below) |
| `refusal` | `String?` | the host's last refusal of MY action; cleared by the next view |
| `send` | `(Rules.Action) -> Void` | send an action to the host |
| `name(of:)` | `(String) -> String` | a player's name by id |

Rules for views:

- **Never mutate game state.** Call `context.send(.something)` and wait for the next view.
  Local `@State` is only for things like a selected card or a typed answer before sending.
  It is fine to show the player's own action optimistically (Quick Draw does) until the
  host's view confirms it.
- The view is rebuilt on every packet; `@State`/`@StateObject` survive within a match (the
  room screen gives the view `.id("<game>-<match>")`, so they reset for a new match).
- **Refusals**: the room screen already shows `context.refusal` as a banner at the bottom;
  you may also show it inline, and `SRHaptic.bad()` on a new one, but you need not.
- **Leave / standings are not yours**: the room screen owns the navigation bar (Leave) and
  shows the final standings when the lobby phase becomes `.finished`. Your view only draws
  the running match.
- The view fills the space below the room's navigation bar. Use `ScrollView` for
  card/skill games whose content can grow; a full-screen `ZStack` for reaction games.
- Use `.srGround(.warm)` on a scrolling page, as other screens do.

### Host clock and countdowns

```swift
struct OfflineHostClock: Equatable {
    var offset: Double                                // host − local, seconds
    func now() -> Double                              // host time now
    func host(fromLocal local: Double) -> Double      // a touch timestamp → host time
    func local(fromHost host: Double) -> Double       // a host deadline → local uptime
    func secondsLeft(until hostTime: Double) -> Int   // whole seconds, never negative
}
```

The guest's offset is estimated by the session (ping/pong, best of the last 12 round trips;
typically within a few ms on Wi-Fi, ~10–30 ms over Bluetooth) and refined as pings return,
so read `context.clock` freshly rather than caching it.

A countdown to a host deadline in the state: `OfflineCountdown(clock: context.clock, until: view.turnEndsAt)`
(a `TimelineView` that ticks 4×/s; optional `font:` and `tone:`). For a custom one, wrap
in `TimelineView(.periodic(from: .now, by: 0.25)) { _ in … context.clock.secondsLeft(until:) … }`.

### Reaction games: measure locally, report the number

Copy Quick Draw. The pattern:

1. The **rules** put the stimulus time in the state and the view as an absolute host time
   (`drawAt = now + rng.double(in: 2...6)`), chosen in `start`/`tick`.
2. The **view** owns `@StateObject private var stimulus = OfflineStimulus()` and calls
   `stimulus.arm(at: view.drawAt, clock: context.clock)` in `.onAppear` and in
   `.onChange(of:)` for the round, the phase and `context.clock`; `stimulus.reset()` between
   rounds. `stimulus.shown` flips on the first display frame due at or after the host time,
   and `OfflineStimulus` remembers that frame's local timestamp.
3. Taps come from `TapSurface(label:onTouch:)` (Games/TapDuelScreen.swift), a UIKit view
   that reports `UITouch.timestamp` — the same clock as the display link. In the handler:
   `stimulus.reactionMs(touchedAt: timestamp)` → `Int?`; `nil` means the touch came before
   the stimulus showed (a false start).
4. **Send the measured milliseconds** (`context.send(.tap(round: r, ms: ms))`), or a
   false-start action. The host judges on reported times, never on arrival order, so
   Bluetooth latency does not decide who won. Treat `ms < OfflineReaction.anticipationMs`
   (100) as a false start in the rules, refuse absurd values, and optionally treat an action
   that reaches the host well before the stimulus time (Quick Draw: 0.5 s early) as false.
5. Close the round in `apply` once everybody still present has answered, or in `tick` at a
   deadline after the stimulus, so a phone that never answers cannot stall the game.

### Layout: nothing may leave a 375-point-wide screen

- Size boards, grids and cards **from the available width**, never from content:
  `GeometryReader { geo in let side = min(geo.size.width, 400) / CGFloat(columns) … }`,
  and give the reader an explicit height (`.aspectRatio(1, contentMode: .fit)` or
  `.frame(height: side * rows)`) — a bare `GeometryReader` in a `ScrollView` collapses.
- Horizontal page padding is `SR.gutter` (20) each side → **335 pt** of content on the
  narrowest phone; a card adds `SR.cardPadding + 2` (18) each side → **299 pt** inside an `SRCard`.
- Rows with names: `.lineLimit(1)` (+ `.truncationMode(.tail)`) on the name, `Spacer(minLength:)`
  between, `.fixedSize()` only on short fixed figures. Five player names must fit in one
  column of rows, not one row of columns.
- Free text: `.fixedSize(horizontal: false, vertical: true)` so it wraps.
- Big headline text: `.lineLimit(2).minimumScaleFactor(0.4…0.6)`.
- Buttons in a row: at most two side by side with `fill: true` labels and short titles
  (≤ 10 characters); otherwise stack them in a `VStack`.
- Hands of cards: `OfflineHand` overlaps cards to fit any width.
- Never `.frame(width:)` a constant wider than ~300 pt.

### Shared UI kit (`UI/OfflineGameKit.swift`)

```swift
OfflineCardFace(card: OfflineCard, width: CGFloat = 56, selected: Bool = false)
OfflineCardBack(width: CGFloat = 56)
OfflineHand(cards: [OfflineCard], cardWidth: CGFloat = 64, selected: Set<String> = [],
            playable: Set<String>? = nil, onTap: ((OfflineCard) -> Void)? = nil)   // fits its width
OfflineCardMetrics.aspect                       // 1.4 (height / width)
OfflineCountdown(clock: OfflineHostClock, until: Double, font: Font = SR.Text.figure(), tone: Color = SR.ink)
OfflineStimulus()                               // @MainActor ObservableObject: arm(at:clock:), reset(), shown, reactionMs(touchedAt:)
OfflineStandingsCard(standings: [OfflineStanding], me: String)
OfflineInitial(name: String, size: CGFloat = 32, tone: Color = SR.accent)
OfflineSeatColour.of(_ seat: Int) -> Color      // stable colour per seat index
OfflineHowToCard(info: OfflineGameInfo)         // the numbered rules card (in OfflineGamesScreen.swift)
TapSurface(label: String, onTouch: (Double) -> Void)   // Games/TapDuelScreen.swift
```

### The app's design system — exact signatures (check before you call anything else)

```swift
SRCard(accented: Bool = false, interactive: Bool = false) { content }
SRSectionLabel(text: String, trailing: String? = nil, prominent: Bool = false)
SRPageHeader(kicker: String, title: String, strap: String? = nil)
SRButtonLabel(title: String, icon: String? = nil, fill: Bool = false)
Button { … } label: { SRButtonLabel(…) }.srButton(.prominent | .regular).controlSize(.large)
.srGlassCard(_ kind: SRGlassKind = .paper, radius: CGFloat = SR.Glass.radius, interactive: Bool = false)
.srGlass(_ kind: SRGlassKind = .paper, in: some Shape, interactive: Bool = false)
SRGlassChip(text: String, icon: String? = nil, tone: Color = SR.inkSecondary)
SREmpty(title: String, icon: String, message: String? = nil, actionLabel: String? = nil, action: (() -> Void)? = nil)
SRBanner(text: String, tone: Color = SR.ink)
SRHaptic.tap() / .select() / .ok() / .bad()
.srGround(.warm)                 // SRMood: .warm .quiet .vital .wire
SR.Text.hero(34) display(22) title(17) body(16) bodyMedium(16) secondary(14) figure(28) label(12) mono(12) sectionTitle(15)
SR.ink inkSecondary inkMuted inkGhost paper surface accent accentDeep accentInk good warn error line divider
SR.gutter (20)  SR.sectionGap (28)  SR.cardGap (12)  SR.cardPadding (16)  SR.tapTarget (44)
SR.Glass.radius (26)  SR.Glass.innerRadius (16)  SRMotion.settle
```

Never `Font.custom(…)` or `UIFont(name:)` (a CI gate fails it); `SR.Text.*` scale with
Dynamic Type. `.font(.system(size:))` is acceptable for glyphs sized from a computed width
(card pips, board pieces). On an `SR.ink`/`SR.good`/`SR.error`/`SR.accent` fill, text is
`SR.paper`. Use only iOS 17 APIs (two-parameter `onChange(of:) { old, new in }` is fine).

---

## 5. Registering a game in the catalogue

`ios/SRAppleApp/Offline/UI/OfflineCatalogue.swift` holds one line per game:

```swift
static let items: [OfflineCatalogueItem] = [
    OfflineCatalogueItem(QuickDrawRules.self) { QuickDrawView(context: $0) },
    OfflineCatalogueItem(CrazyEightsRules.self) { CrazyEightsView(context: $0) },
]
```

A game whose rules have a computer player conforms to `OfflineBotRules` (in its own
`<GameName>BotLogic.swift`, Foundation only) — `botActions(state, for:, rng:)` returns
candidate actions best first, and the match applies the first the rules accept — and is
registered with `OfflineCatalogueItem(withBot: Rules.self)`. It can then be played alone
(`OfflinePlayModes.soloBots`), and a host can add computer players to empty seats. The
room moves bots on its tick after `OfflineRoom.botThink` and sends them nothing. Bots so
far: Crazy Eights, Dots and Boxes, Four in a Row.

**Word games** (Boggle, Anagram Blitz, Categories) are the offline twins of the site's
games of the same ids (`OfflinePlayModes.offlineTwin`). Boggle and Anagram Blitz judge
words on the host with `OfflineWords.shared.list`, the site's own list cut to nine
letters, solved at the deal so the reveal can show what nobody found; if the bundle ever
lacks the list they accept any word that fits rather than refusing everything. Categories
needs no list: the site's letter test, shared answers score nothing, and a review where
half the other players' vetoes strike an answer. All three end in a reveal that stays up
until everyone taps "See the table" (`.ready` / `.done`). Their views share
`UI/OfflineWordKit.swift`. Tests read the list from the source tree through
`OfflineWordsTests.install()` (the check script copies it beside the Linux package).

`OfflineCatalogueItem(Rules.self) { context in View }` builds both halves: the type-erased
`OfflineGameEntry(Rules.self)` the host's `OfflineRoom` starts matches from (via
`OfflineMatchOf<Rules>`), and a builder that decodes a view packet's bytes into
`Rules.PlayerView`, wraps it in an `OfflineGameContext<Rules>` and returns your view. The
catalogue page groups items by `info.category` in list order; the lobby's game picker
dims games whose player range does not fit.

**When several agents add games in parallel, do NOT edit `OfflineCatalogue.swift`.**
Create only your own files, and put the exact line to add in your summary; the integration
step adds all the lines at once (in one edit, so nobody's line is lost).

---

## 6. Tests: `ios/SRAppleAppTests/Offline<GameName>Tests.swift`

```swift
import XCTest
@testable import SRAppleApp

final class OfflineCrazyEightsTests: XCTestCase {
    private typealias Rules = CrazyEightsRules
    private let players = [OfflinePlayer(id: "a", name: "Ann"), OfflinePlayer(id: "b", name: "Ben"),
                           OfflinePlayer(id: "c", name: "Cat")]

    func testTheRulesPassTheAudit() {
        XCTAssertEqual(OfflineRulesAudit.problems(Rules.self), [])
    }

    func testDealing() {
        var rng = OfflineRNG(seed: 1)
        let state = Rules.start(players: players, now: 0, rng: &rng)
        …
    }

    func testAnIllegalMoveIsRefused() {
        …
        XCTAssertThrowsError(try Rules.apply(.play(card: x), by: "b", to: &state, now: 1, rng: &rng)) { error in
            XCTAssertEqual((error as? OfflineRefusal)?.reason, "It's Ann's turn.")
        }
    }
}
```

- The class is named `Offline<GameName>Tests` (the check script picks up
  `Offline*Tests.swift`, and `scripts/offline-check.sh <GameName>` filters by name).
- Test: the audit; the deal/setup; each legal move; each refusal path; the end condition
  and `standings` (ranks, ties); `playerLeft`; `tick` deadlines; and **redaction** —
  `view(of:for:)` for one player contains nothing of another's secrets, and the spectator
  view (`nil`) contains no secrets at all. A whole-match test through
  `OfflineRoom` (see `OfflineQuickDrawTests.testAWholeMatchThroughTheRoom`) is worth adding.
- Make states directly when that is easier than playing to them: `State` is your own
  struct, so `var state = Rules.State(…)` with a hand you choose is fine.
- **Every helper type in a test file must be `private`** (all test files compile into one
  target on CI; a non-private `struct Helper` in two files breaks the build). Do not use the
  name `SeededRandom` (it exists).
- Deterministic only: fixed seeds, fixed `now` values. Don't assert exact shuffles from a
  seed unless you computed them with the same code in the test.

`OfflineRulesAudit.problems(_:)` checks: kebab-case id, non-empty title/blurb/symbol/how-to,
`1 ≤ min ≤ max ≤ 5`, for every player count in range — the same seed reproduces `start`,
`State` and every `PlayerView` (each player and spectator) survive a JSON round trip,
`standings` lists each player exactly once, and `tick` twice at one instant changes nothing.

---

## 7. Running the check (Linux, Docker)

```bash
OFFLINE_CHECK_TMP=/tmp/claude-1000/-home-john/622874a1-b42a-4983-900a-4063b95fd522/scratchpad \
  scripts/offline-check.sh              # everything
OFFLINE_CHECK_TMP=… scripts/offline-check.sh CrazyEights   # only tests whose name matches
```

It builds a throwaway SwiftPM package in a fresh temp dir (under `$OFFLINE_CHECK_TMP`, else
`$TMPDIR`, else `/tmp`) whose library module is named **`SRAppleApp`** — so
`@testable import SRAppleApp` works unchanged — from every Foundation-only
`Offline/Core/*.swift` and every `Offline/Games/**/*Logic.swift`, with
`ios/SRAppleAppTests/Offline*Tests.swift` as the test target; runs `swift build` and
`swift test` in `swift:6.0-jammy` in Swift 5 language mode; and `swiftc -parse`s every
other `.swift` under `Offline/` (views, links, session) to catch syntax errors. It exits
non-zero on a Logic file importing anything but Foundation, a parse error, a build error,
a failing test, or a filter that matches no test. Runs are independent, so several agents
can run it at once (~20 s each).

**What it cannot check**: SwiftUI, UIKit, MultipeerConnectivity and Network.framework
code does not compile on Linux — only GitHub's macOS CI compiles it. So re-read every view
line by line before handing it back:

- every helper you call exists with exactly that signature (§4 lists them; grep the rest);
- every `if let`/`guard let` unwraps what is optional and nothing else;
- `switch` over your enums is exhaustive;
- `ForEach` data is `Identifiable` or has an `id:`;
- `@ViewBuilder` bodies contain only views, `if`/`switch`, and `let`;
- no `Font.custom`, no iOS 18+ API, no `.onChange(of:perform:)` single-parameter form;
- types referenced from Core are spelled as in §3.

---

## 8. Naming rules

- Folder `Offline/Games/<GameName>/` in UpperCamelCase (`CrazyEights`, `SpeedTap`).
- Files: `<GameName>Logic.swift`, `<GameName>View.swift`, tests
  `ios/SRAppleAppTests/Offline<GameName>Tests.swift`. Extra view files, if any:
  `<GameName><Thing>View.swift` in the same folder (they are parse-checked, not compiled, on Linux).
- Types: `<GameName>Rules` (the enum), `<GameName>View`, and any extra top-level view
  `<GameName><Thing>`; everything else nested inside `<GameName>Rules`. **Every new
  top-level type starts with the game's name** (or `Offline…` for shared ones — don't add
  shared ones from a game). Grep `ios/` before introducing any top-level name.
- `info.id`: the kebab-case of the title (`crazy-eights`), unique across all games.
- Accessibility identifiers: `<gameid>-<thing>` (`quick-draw-surface`, `crazy-eights-hand`).
- Never touch `OfflineCatalogue.swift`, Core, Link, Session or UI files from a game task —
  if a shared helper is missing, write a private one in your own files and mention it.

---

## 9. Connections, permissions and limits

- **Both links at once** (`OfflineDualLink`, transport `.auto`, the default): the host
  advertises on both under one room id (`OfflineRoom.roomKey`, 8 hex digits); a guest
  browses both and sees one row per room (`OfflineDiscovery.merge`), and joins by Wi-Fi
  first, then Nearby if that does not connect. Host peer keys are `nearby|…`/`hotspot|…`.
- **Nearby**: MultipeerConnectivity, service type `sr-play` (Info.plist `NSBonjourServices`
  lists `_sr-play._tcp` and `_sr-play._udp`), **`.none` encryption** (`.required` was the
  likeliest cause of sessions stuck connecting or dropping seconds in; both phones must
  run this version, as mismatched preferences do not connect), `.reliable` sends. The
  host advertises `room`, `v` and `rid`; guests list rooms by `rid`. The `MCPeerID` is
  made once and kept in UserDefaults — a fresh one per room left ghost peers in other
  phones' lists that hung for the whole invitation timeout. A join invites up to 3 times
  (8 s each); a connected guest stops browsing. A guest's first message reaching the host
  before its "connected" callback registers the peer rather than being dropped. MultipeerConnectivity cannot hang up on
  a single peer, so a refused guest leaves when it reads `refused`.
- **Wi-Fi / hotspot**: `NWListener` on TCP port **47474** when free (else any port, shown
  with the address), advertised as Bonjour `_srplay._tcp` with a TXT record (`rid`, `v`,
  built by `OfflineTXT`); guests use `NWBrowser` (`bonjourWithTXTRecord`), or type the
  address the host's lobby shows. `includePeerToPeer` is on, so two phones with no
  network in common still meet over phone-to-phone Wi-Fi. TCP: no Nagle delay,
  keepalive after 4 s, 12 s connect timeout.
- Both need the **Local Network** permission (`NSLocalNetworkUsageDescription` explains it).
  A browse started under the permission prompt finds nothing, and iOS stops advertising
  and browsing in the background: the session calls `refresh()` whenever the app comes to
  the front, and restarts an empty browse every 10 s.
- **Dropped guests rejoin**: a guest that loses the host mid-room looks for the same
  room id for 60 s (`OfflineReconnect.patience`) and rejoins its own seat (same player
  id); games with an away state take it back with `.back`. Each route of a join gets
  `OfflineReconnect.joinTimeout` (30 s, enough for Nearby's three invitations) up to the
  host's `welcome`: the dual link reports `.trying` when it falls back to its other route
  and the session restarts the timer. A connected guest re-sends `hello` every 2 s until
  welcomed, so one lost hello cannot leave it on "Joining…". A route that hung is tried
  last on the next attempt at that room (`OfflineDiscovery.routes(for:failed:)`).
- **Test connection** (lobby): a guest times a ping round trip; the host re-advertises and
  says who it has heard from (guests ping every 3 s once settled; `OfflinePeerHealth`).
- The host must keep the app open; the room screen disables auto-lock while it is up.
- A guest pings 2×/s until 5 clock samples are in, then every 3 s.
- Guests and host must run the same `OfflineEnvelope.version`; bump it when a message
  changes shape. New optional fields (`OfflineLobby.roomKey`, `OfflineLobbyPlayer.bot`)
  need no bump. A game's `Action`/`PlayerView` changing shape needs both phones updated —
  an undecodable view shows "This game needs a newer app".
- **Results sync later**: every finished match a phone played in is queued as one
  `OfflineResult` (its own rank and score; id `<roomKey>-<match>`, the same on every phone
  in the match) in Application Support, and sent in batches of 25 to
  `POST api/native/games/offline-results` `{ results: [...] }` → `{ recorded: [id],
  rejected: [id] }` when paired and online — at once, when the network returns, when the
  app comes to the front, and on a backoff (15 s → 15 min). A 404 keeps them waiting.
  On the wire each row's game is namespaced, `game: "offline:<id>"` with
  `source: "offline"` (`OfflineResultUpload`), so the offline Maths Sprint (no difficulty,
  10 a sum plus a streak bonus) can never land on the online `maths-sprint` board; the
  phone's own tallies keep the plain id. **The SR-Main route does not exist yet**: it
  should write one `game_results` row per caller keyed by (`offline-<id>`, user), so
  retries are idempotent, and answer `{ recorded, rejected }`. Until it ships every
  result stays on the phone (`.notReady`).

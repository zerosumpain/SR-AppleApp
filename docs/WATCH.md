# Apple Watch

What the companion does on a wrist, what it deliberately does not, and what
each step costs. Phases 0, 1 and 2 are built. Phase 3 is not (see below).

**Signing.** Phases 1 and 2 need two App Store profiles this repository does
not have yet (docs/TESTFLIGHT.md, "The Apple Watch app"). Until they exist the
TestFlight job uploads the iPhone app alone, exactly as before, and says so in
its log. CI builds everything for the simulator, where no profile is needed.

## What a watch is for, here

The phone does two jobs: it **collects** (HealthKit, location, the motion gate)
and it **reads the site** (Today, Chat, News, Flows). The Watch already does
most of the first job for free: what it records reaches the phone's HealthKit,
and the phone uploads it. So the watch app collects nothing and mirrors no tab.
It is two things:

1. **A glance:** Today, shrunk to what fits on a wrist.
2. **A few verbs that need no reading:** clear an alert, sync now, start a
   question to jkai.

## Two constraints that shape it

**Signing.** The TestFlight lane holds one distribution certificate and ONE App
Store profile, for the app. That is why the app has no widgets, no share
extension and no push (see `SRAppIntents.swift` and `AlertStore.swift`). A
watch app is a second target with its own bundle identifier and profile.
Complications are a WidgetKit extension, which is a third. The phases are cut so
that each new profile is a decision of its own.

**Credentials.** Both device tokens are in the Keychain as `…ThisDeviceOnly`,
and the README takes the question of who holds which credential seriously. So
the Watch starts out holding NONE. The phone pushes it a small snapshot over
WatchConnectivity, the Watch sends its actions back as messages, and the phone
makes every network call. Revoking the phone therefore revokes the Watch. The
cost is that a Watch away from its phone (on its own Wi-Fi or LTE) cannot
refresh; Phase 3 addresses that, if it ever matters.

## Phase 0: buttons on the alerts you already get (built)

iOS forwards a local notification to the Watch whenever the phone is locked and
the Watch is on a wrist, and it brings the notification category's actions with
it. A background action is handed back to this app on the phone, which iOS wakes
to handle it. Nothing on the Watch has to exist.

Until now every alert was raised with `categoryIdentifier = alert.category` and
no category was ever registered, so no alert had a button anywhere. Now:

| Category | Worn by | Buttons |
| --- | --- | --- |
| `sr.alert` | every site alert but a lapsed connection | **Mark read**, **Clear from Today** |
| `sr.connections` | a lapsed connection | none |

- **Two fixed identifiers, not one per site category.** A category is matched
  by identifier, and the site's categories are open-ended. An unregistered one
  would raise with no buttons at all. The site's category moves to `userInfo`,
  which it was already copied into, and the tap handler reads it from there. A
  notification raised before this change still routes, because the handler
  falls back to the identifier. Household and game notifications keep their
  own unregistered identifiers, so they have no buttons, and route as before.
  The personal-health connection check sets no identifier at all, so a tap on it
  used to land on Today; reading `userInfo` first now opens the connections
  list it was meant to.
- **Clear from Today** is local, exactly like the swipe on the Today card
  (`AlertStore.clearedFromToday`). A store a screen is already holding is told to
  re-read, so the card is right the moment the phone is unlocked.
- **Mark read** sends the same `{"read": [id]}` as opening an alert on the
  phone (`AlertStore.markRead`), then reads the unread count back from the site
  for the badge rather than subtracting one: the alert may already have been
  read on the website. It is owner-only, like every inbox call, because a
  notification can outlive the access that raised it. If the request fails,
  nothing changes, so the badge never drops against a server that disagrees.
- **Lapsed connections get no buttons.** The only fix is re-authorising in a
  browser, which a wrist cannot do, and clearing one would hide the only alert
  that means something has stopped working.
- **No button opens the app.** A `.foreground` action from a wrist is a request
  the Watch can only pass on. Every button does its whole job in the
  background, so it behaves the same on the Watch as on a lock-screen banner.
  Tapping the notification still opens the app, as before.

The limitation from `AlertStore.swift` still applies: with no push certificate
the phone PULLS alerts during background refresh, so an alert reaches the wrist
as late as it reaches the phone.

The routing is pure and covered by `AlertActionsTests`. Pressing a button is
device-only; see [Device testing](DEVICE-TESTING.md#apple-watch).

## Phase 1: the watch app (built; one new target, one new profile)

As built, and where it differs from the plan below:

- **Code.** `ios/SRAppleWatch/` (the app), `ios/Shared/WatchShared.swift`
  (`WatchSnapshot`, `WatchCommand`, `WatchReply`: compiled into the phone, the
  Watch and the complications, so the contract cannot drift), and
  `ios/SRAppleApp/Watch/WatchBridge.swift` (the phone's side).
- **When the snapshot is sent.** Not on named events: the bridge subscribes to
  the stores that already hold each input (Today's payload, the inbox the app
  shell holds, the connections, the upload queue and gate, the pins, the
  access) and sends when any moves, coalesced to one send per burst and
  skipped when only the timestamp changed. Still no network call of its own.
- **Figures.** Readiness and recovery (same sources as Today's rings), then
  HRV, resting heart rate and sleep when the site sent them.
- **Sync now** answers at once ("Syncing on your iPhone") and runs a sync with
  the 15-second collection window a background refresh gets: a sync can take
  longer than a Watch waits for a reply, and the next snapshot's queue count
  is the result.
- **Out of reach.** A command is sent with `sendMessage` when the phone is
  reachable and queued with `transferUserInfo` when it is not; the Watch says
  "Queued for your iPhone".
- **Spec.** `ios/app.yml` is the iPhone app alone; `ios/watch.yml` adds the two
  Watch targets; `ios/project.yml` includes both. Every bundle ID derives from
  `SR_BUNDLE_ID`, and each target names its own `SR_*_PROFILE`.
- **CI.** A step builds the Watch scheme for a watchOS simulator before the
  iPhone tests, and fetches the watchOS platform if the runner image lacks it.
  The job's timeout went from 35 to 50 minutes.
- **Tests.** `WatchBridgeTests`: who gets what in the snapshot, the context and
  every command round-tripping, malformed commands refused, the pin limit.

The plan, as written before it was built:

- **Target.** `SRAppleWatch`, a single-target SwiftUI watchOS app, watchOS 10+
  (the release alongside iOS 17), embedded in the iOS app through `project.yml`.
  Bundle identifier `com.strangeramblings.com.appleapp.watchkitapp`.
- **Phone side.** A `WatchBridge.swift` builds a small `Codable`
  `WatchSnapshot` and sends it with `updateApplicationContext`. That happens
  whenever the Today payload loads, alerts refresh or a `flush()` finishes, so it
  costs no extra network calls. It is built from what this person's access
  allows (`AccessStore`), exactly as their Today is: a family member's Watch
  never carries the owner's inbox or site figures. The snapshot holds:
  - readiness score and label; recovery, HRV, resting heart rate and sleep
    figures (from `TodayHealth`)
  - the three uncleared alerts Today would show (`TodayAlerts.rows`) and the
    unread count
  - sync health: queue count, last upload, motion-gate state. "An app that
    switches its own sensor off has to be watchable", and the wrist is where
    you would look.
  - whether a site connection needs re-authorising
- **Screens.**
  1. **Today:** the Readiness and Recovery rings from the snapshot. The Move
     ring is read on the Watch itself with `HKActivitySummaryQuery`, the way
     `MoveRingStore` does it on the phone, so it is live rather than hours
     behind the last upload.
  2. **Alerts:** swipe to mark read or clear, sent to the phone as a
     `sendMessage` and handled by `AlertStore`. The phone stays the single
     source of truth.
  3. **Status:** queue, last upload, gate state, and **Sync now** (the
     `SyncNowIntent` path).
- **Ask jkai.** Dictate on the Watch; the question lands in the phone's
  composer as `pendingQuestion`, **unsent**. This keeps the rule in
  `AskJkaiIntent`: a turn sent where you cannot watch it go wrong is not sent for
  you, and the Watch cannot answer any of chat's four gates. **Decided
  (2026-09-26):** it stays unsent. Sending from the wrist and reading the reply
  there was considered and turned down for that reason.
- **Design.** `SRRegister.ink`: cream type on ink. watchOS is always dark,
  the phone is light-locked, and the ink register exists for exactly this. Bundle
  two faces only: JetBrains Mono for labels, Archivo Black for figures.

### Build and CI changes

- **`project.yml`:** a watchOS `application` target with
  `WKCompanionAppBundleIdentifier`, and the iOS target depending on it so it is
  embedded. Signing settings move to per-target: `testflight.yml` passes ONE
  `PROVISIONING_PROFILE_SPECIFIER` on the command line, which would apply to
  both targets and fail the archive.
- **Portal:** register the watch App ID and mint its App Store profile.
- **`testflight.yml`:** a `WATCH_PROVISION_PROFILE_BASE64` secret;
  `install-signing.sh` installs both profiles, and `ExportOptions` maps both
  bundle identifiers.
- **`check.yml`:** build the watch scheme for a watchOS simulator inside the
  existing macOS job, not a second 10x runner. The `ios/` path filter already
  covers it.
- **Tests:** WatchConnectivity barely works in a simulator, so the snapshot
  builder stays pure and unit-tested, the same approach the motion gate takes.
  The round trip goes on the device checklist.

## Phase 2: complications and pinned flows (built; a third profile)

As built: `ios/SRAppleWatchWidgets/` has two complications, **Readiness**
(circular gauge, corner, inline, rectangular with recovery and unread) and
**Alerts** (unread count). They read the snapshot the Watch app writes to the
App Group, and the app reloads their timelines on every new snapshot.
Pinned workflows are chosen on the phone (a workflow's menu → Pin to Apple
Watch; three at most, kept on the phone, titles kept current from the list).
The phone runs one only if it is STILL pinned when the request arrives, so an
old snapshot on the wrist cannot start a workflow unpinned since.

The plan:

- **Complications and Smart Stack:** a WidgetKit extension on the Watch
  showing the Readiness ring and an unread count. It reads the snapshot through
  an App Group, which is one more capability on both App IDs.
- **Pinned flows:** run up to three chosen workflows, each behind a
  confirmation step, through the phone and
  `POST api/native/workflows/:slug/run`. A tap on a wrist is too easy to make by
  accident for a side effect without one.

## Phase 3 (optional, not built): refresh without the phone

Not built, deliberately. It needs a new endpoint on the site (SR-Main) that
mints and revokes a watch-scoped token, which is outside this repository;
building the Watch half against an endpoint that does not exist would be
guessing at its contract. Worth doing only if the phone is often left behind.

A read-only, watch-scoped token, minted on the phone and handed over WCSession,
good for `api/native/today` only. It would be listed and revocable beside the
other devices. Worth it only if the phone is often left behind.

## Deliberately not on the Watch

- Chat transcripts, the news desk, the movement map, the flow editor. They are
  reading and editing screens.
- HealthKit collection or location on the Watch. The phone already uploads what
  the Watch records, and a second collector would double-count steps, which the
  README already warns about for phone-plus-Watch sums.
- Workout tracking. Apple's Workout app does it, and the result reaches the
  server through HealthKit anyway.

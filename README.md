# SR-AppleApp

Native iPhone companion and private web/API pilot for Strange Ramblings.

- **Private health:** steps, heart rate, resting heart rate, sleep stages and workouts.
- **Family locations:** latest shared position, accuracy, recorded time and received time.
- **Your own movement, on a map:** a day listed as journeys and the stops between them, each drawn with the gaps left as gaps, and that day's heart rate, workouts, sleep and steps on one timeline under it. Scrubbing the timeline moves a dot along the track; picking an activity lights it and dims the rest of the day. Owner-only — the family tab shares a latest position, this shares a history.
- **Adaptive location recording:** targets 10 minutes stationary and 30 seconds moving, with a 3-minute stop threshold. These are best-effort recording intervals, not guaranteed GPS or upload schedules.
- **Motion-gated GPS (optional, off by default):** when the phone has been still long enough the app drops a geofence, switches GPS off and lets iOS suspend it. A geofence exit, significant change or visit departure wakes it; it then reads the movement the motion coprocessor recorded while it slept and decides whether to start GPS at all. Motion cannot wake a suspended app — the hardware log is what makes this work. Everything ambiguous fails towards running GPS rather than going quiet.
- **A history of that:** every time the gate opened or closed, with the cause, the duty cycle it adds up to, and what share of wakes found real movement. An app that switches its own sensor off has to be watchable.
- **Offline sync:** protected on-device queue, retry, idempotent ingestion, HealthKit change anchors/deletions, and server-side device revocation.

Health is always scoped to the authenticated person. Family membership grants access to shared locations only. No public health projection, family health endpoint, or administrator health-view bypass exists. Server operators with filesystem/database access still technically control the stored data; this is not end-to-end encryption.

## Test the running local preview

Run it locally (below) and open `/apple-app/` on the host you started it on.
There is also a long-running preview on the LAN; its address is in the private
ops notes rather than here, because this repository is public.

| Synthetic account | Family |
| --- | --- |
| `alex@example.test` | Demo family |
| `sam@example.test` | Demo family |
| `robin@example.test` | Separate family |

**There is no password.** Signing in uses the main site's Google session, and a
laptop on loopback has no main site to get one from, so the preview names an
account instead. That lane needs `DEMO_MODE=1` **and** a non-https origin, so it
cannot exist on production — see `server/session.mjs`.

Sign in as Alex, inspect My health, open Movement and pick a day from the strip — the seed writes six days of walks with real gaps between them, so the dashed hops and the "the phone was asleep" readout are the point, not a defect. The preview has no main site to fetch a Mapbox token from, so the track draws on a plain ground and the frame says so. Then switch to Family locations, and pause sharing under Connect & privacy. Sign in as Sam in a second browser/private window: Sam sees only Sam's health, and Alex's location disappears while paused. Robin cannot see either member of the demo family. Refresh the family tab after changing sharing in another window.

This HTTP preview contains synthetic data only. It is **not connected to production**, does not read Apple Health in the browser, and is not the iPhone app. Real-device pairing requires trusted HTTPS and an installed signed build.

## Signing in

The companion uses **the main site's account** — the same Google sign-in as the
rest of strangeramblings.com. It has no password of its own, no `sr_apple`
session cookie, and no scrypt hashes; opening an existing database drops the
`users.password` column outright, because a password hash is credential material
whether or not anything still reads it.

Two lanes reach the API, and only two:

| Caller | Credential | Notes |
| --- | --- | --- |
| Browser | the site's Auth.js session cookie | verified with `AUTH_SECRET`, the same way every extracted SR app's gateway does it |
| Paired iPhone | a device token from a pairing code | unchanged; background sync runs while the phone is locked and has no browser session |

**Authentication says who; the `users` table says whether.** Somebody the site
knows but this server does not gets a 403 telling them to ask the owner, not an
account. Family membership decides who can see a location, so it is never
inferred from a successful Google login.

A family member therefore needs two things: the ability to sign in to
strangeramblings.com (owner, or a guest on the allow-list), and a row here.

The container refuses to start on an https origin without `AUTH_SECRET`. Without
that check a missing secret would 401 every browser while the phone kept syncing
on its device token, hiding the fault for days.

### One page, both credentials

A phone can hold two, and both are minted from **Connect & privacy** on this
dashboard:

| Credential | Minted by | Grants |
| --- | --- | --- |
| Companion device token | this server | health upload, family location |
| Site device token | **the main site**, `/api/admin/native-devices` | jkai threads, the news desk |

Only the UI is shared. The site token is minted, listed and revoked by SR-Main
behind its own owner gate, and its QR arrives already rendered as a data URL —
this server never mints, stores or sees it. Drawing the QR here would have meant
vendoring a QR library to handle a credential that is none of its business.

`/admin/access/devices` on the main site 308s here; it existed for about an hour
on 2026-09-22.

### Why not the SR-Infra gateway

Every *extracted* application (Policy, Drive, Health, JKAI) sits behind the
~60-line gateway in `~/sr-infra/gateway/`, which validates this same cookie at the
edge and re-issues a 30-second HMAC assertion. That exists so the app can trust
an identity **header** — the gateway's real job is stripping every client-supplied
one first.

There is no header to strip here: identity comes from an encrypted JWE that
cannot be forged without `AUTH_SECRET`. Both designs need that secret in this
container, so a gateway would have bought process separation and nothing else, at
the cost of a second port, image, release lane and ingress change. The companion
is also not in `registry/apps.json` — one container, no release slots, nothing for
the kit's blue/green machinery to act on. `sessionIdentity` is copied from the kit
unchanged so the part that matters cannot drift.

## Repository

```
ios/                 SwiftUI app, HealthKit/Core Location collectors, XCTest
server/              Node HTTP API, SQLite, private browser dashboard
server/test/         API integration and privacy tests
.github/workflows/   Mac simulator checks and manual signed TestFlight upload
scripts/             Signing setup and repeatable browser verification
deploy/              Container configuration
```

Run API tests with Node **22.23.2** or later:

```sh
npm ci --ignore-scripts
npm test
APP_ORIGIN=http://127.0.0.1:5295 DEMO_MODE=1 npm run seed:demo
APP_ORIGIN=http://127.0.0.1:5295 DEMO_MODE=1 npm start
```

QR images are generated locally with the pinned `qrcode` package; no external QR service receives pairing credentials. SQLite is provided by Node; its experimental warning on Node 22 is expected. A single application process owns the database; do not scale replicas against the same SQLite file. Database files belong in the mounted volume, never Git.

For a local container:

```sh
APP_ORIGIN=http://127.0.0.1:5295 docker compose -f deploy/compose.yaml config
APP_ORIGIN=http://127.0.0.1:5295 docker compose -f deploy/compose.yaml up -d --build --wait
```

The long-running LAN preview is a separate Compose project with its **own
volume**, bound to loopback and reached through the existing preview gateway,
which forwards `/apple-app/` and `/api/apple/` without injecting the site's
owner session. It never touches production data, credentials or the Docker
socket. Its host, paths and volume name are deliberately not published here.

### Environment variables

| Variable | Required | Notes |
| --- | --- | --- |
| `APP_ORIGIN` | yes | the HTTPS origin the companion is served on |
| `DATABASE_PATH` | no | SQLite file path; defaults to `./data/apple.sqlite`, and Compose pins it to `/app/data/apple.sqlite` in the mounted volume rather than leaving it operator-settable through `pilot.env` |
| `AUTH_SECRET` | yes on https | verifies the main site's Auth.js session cookie; copied from the site's own environment. Only enforced when `APP_ORIGIN` is https — a non-https `APP_ORIGIN` (e.g. the local preview) can start without it |
| `APPLE_SERVICE_TOKEN` | no | shared bearer token for /health's service lane; empty = both service-lane reads 404 |
| `APPLE_SERVICE_OWNER` | no | the fixed owner (an email already in `users`) those reads are scoped to |
| `APPLE_HOUSEHOLD_TOKEN` | no | SR-Main's household lane (`/api/apple/household`, `/api/apple/household/events`), scoped to the owner's family; empty = both 404; must differ from `APPLE_SERVICE_TOKEN` |
| `APPLE_DOORBELL_URL` | no | POSTed (empty body, `Authorization: Bearer $APPLE_DOORBELL_TOKEN`) after each owner upload so /health pulls the export at once; empty = no ring, and /health still catches up on its own page-load backstop |
| `APPLE_DOORBELL_TOKEN` | no | the doorbell's own ring-only secret — distinct from `APPLE_SERVICE_TOKEN`, can only trigger a pull, and grants no read access |

## CI cost

The `ios` job runs on macOS, which GitHub bills at a **10x minute multiplier**
and which takes ~20 minutes cold. `check.yml` therefore runs on **pull requests
and `main`**, not on every branch push, and skips the Mac job entirely unless the
change touches `ios/`.

If jobs start failing in under ten seconds with no steps, that is not the code —
it is the Actions spending limit, and the message is only visible in the check
run's *annotations*, not in the logs or `gh run view`:

```sh
gh api repos/zerosumpain/SR-AppleApp/commits/<sha>/check-runs --jq '.check_runs[].id' \
  | xargs -I{} gh api repos/zerosumpain/SR-AppleApp/check-runs/{}/annotations \
      --jq '.[] | "\(.annotation_level): \(.message)"'
```

Re-running does not help; the job never starts.

## iPhone build and installation

The **Check app and API** GitHub workflow builds and tests on a hosted Mac. Its simulator `.app` artifact is **not installable on an iPhone**.

For an actual phone, follow [TestFlight setup](docs/TESTFLIGHT.md). This requires your Apple Developer membership, registered app and signing material. No Apple credentials were present when this repository was created. They must be entered in GitHub's protected `testflight` environment, not committed or pasted into chat.

On a Mac with Xcode and XcodeGen:

```sh
xcodegen generate --spec ios/project.yml
open ios/SRAppleApp.xcodeproj
```

Deployment target: iOS 17.0, iPhone only. Pair in the app using a one-time code from the dashboard. Pairing expires after 10 minutes; device credentials expire after 90 days and can be revoked immediately. A pairing code binds the phone to the person who generated it. Pair each family member's own phone with their own account.

## Pilot behaviour and limits

- Initial health history starts 30 days before the local app state was created. HR/RHR/sleep/workout changes use persisted HealthKit anchors. Deleted sample IDs remove the corresponding uploaded sample.
- Steps use HealthKit cumulative daily statistics, not raw phone-plus-Watch sums. The most recent 30 daily buckets are recomputed, allowing updated totals to replace older uploads. If a whole bucket disappears or permission is withdrawn, HealthKit's absence cannot reliably distinguish deletion from denied access; existing server totals remain until explicitly deleted. Historical bucket timezone changes and long-running backfills need further real-device validation.
- Sleep stages retain source and interval. The dashboard does not sum overlapping sources into a misleading sleep total.
- HR is available historical readings, not continuous real-time sensing. Watch-originated records must first reach the phone.
- HealthKit reads can fail while locked; retry after unlock. Apple deliberately does not disclose denied read permission, so empty data is not presented as confirmed permission.
- With motion gating on, GPS is switched off entirely while the phone is still. That trades latency for battery: movement is noticed on leaving the anchor, not the second somebody stands up. It refuses to sleep at all unless Always location access, significant-change monitoring, geofencing and a readable motion history are ALL available, and records a reason in the history when it cannot — the app keeps recording expensively rather than silently stopping. Motion & Fitness permission is required; step and activity history is read only to decide whether to start GPS and is never uploaded.
- Continuous/low-accuracy location monitoring and significant-change recovery detect movement. GPS drift is filtered; inaccurate or old fixes are discarded. Recording frequency does not equal sensor frequency. The best-effort timer works only while iOS runs the process. Suspension, force-quit, disabled Background App Refresh, low power and poor reception cause gaps. Stationary points are not fabricated from stale coordinates.
- Pausing sharing on the website hides the last position immediately. The phone stops collection when it next reaches the server. Pausing on an offline phone stops collection immediately; server visibility changes only once the pause reaches the server.
- Queue and anchors are persisted atomically with iOS file protection and excluded from backup. Tokens use device-only Keychain storage. The queue caps at 50,000 records and stops advancing collection when full. Uploads retry on subsequent events, foreground launch, a best-effort retry timer, and OS-scheduled background refresh.
- Browser and native history views are bounded recent-record views, not full historical analytics. A family location still opens explicitly in Apple Maps rather than being embedded. The **Movement** tab does embed a basemap, and what that costs is written out under [The movement map](#the-movement-map) rather than left to be discovered.
- Locations are retained for up to 30 days (pruned on ingestion); family reads expose the latest point only. Health records remain until deletion. Delete uploaded data revokes paired devices to prevent immediate automatic re-upload.
- Family account provisioning is administrator CLI-only, and deliberately so: `family` decides who can see a location, and there is nothing in a Google login to infer it from. See [site integration](docs/INTEGRATION.md).

## The movement map

A day's track on a basemap, with that day's health on a timeline under it.
Reading it is `GET /api/apple/track` for the geometry and
`GET /api/apple/timeline` for the health, both scoped to the signed-in person
on either lane. There is no user parameter to reject: `family` discloses a
LATEST position, this discloses a HISTORY, and a month of positions says where
somebody sleeps, works and takes their children. Reading your own track does
not depend on the sharing switch — that governs uploading and what the family
sees, and pausing it should not lock you out of what you already recorded.

**A break is judged on MOVEMENT, not on missing data.** `segmentsOf` decides
where a line may be drawn — runs of continuous recording. That is the wrong
question to ask of a day, and one real day showed both ways it goes wrong:

- A stop the phone sampled through is invisible to it. An hour at a desk with a
  fix every two minutes has no gap over ten minutes anywhere in it, so the walk
  in and the walk home come out as ONE journey that never happened.
- A stop the phone slept through leaves lone stationary fixes, and each becomes
  a "segment" of one point and nought metres. A real day read as seven
  segments, five of which were somebody standing still.

So `activitiesOf` joins two fixes into a journey when they are close in time
**and at least one of them reported moving** — the flag the phone's own movement
policy sets, which is the only thing that can tell a parked car from a slow one.
The day comes back as journeys and the stops between them, and a journey is
named by whichever HealthKit workout overlaps it, with the Watch's own distance
alongside the track's.

**Gaps are drawn as gaps.** The motion gate lets iOS suspend the app when you
are still, so a day is runs of fixes thirty seconds apart separated by hours of
nothing — in production the median gap is 37 seconds and the largest so far is
eight and a half hours, which is a night's sleep. Anything over ten minutes
starts a new segment, drawn as a dashed hop rather than joined, and distance is
summed within segments only. That makes the distance an undercount whenever the
phone slept through a journey, which is the honest direction to be wrong in.
Nothing here is called "distance travelled".

**What the basemap costs.** Tiles are raster images from Mapbox, using the main
site's own public token fetched from `/api/maps/config` on the same origin —
this server never holds a Mapbox credential. Mapbox therefore sees the tile
coordinates being viewed (an area, not the trace), the viewer's IP, and the
origin. It does not see the track, the times, or who is looking. If that trade
is not wanted, the map degrades on purpose: with no token, or a failed fetch,
the track draws on a plain ground with a scale bar and says so.

Two details that are not obvious and both fail silently if missed:

- The tiles are `<img>` elements rather than a WebGL map library, which is why
  the CSP only gains `img-src https://api.mapbox.com`. A GL map would have
  wanted `connect-src`, `worker-src blob:` and a looser `style-src` on a page
  showing a month of somebody's whereabouts, plus a megabyte of vendored code
  into a server with no bundler.
- The token is URL-restricted, and this server sends `Referrer-Policy:
  no-referrer`. A tile inheriting that arrives anonymous and is refused with a
  403 and nothing in the console. Each tile carries its own
  `referrerpolicy="strict-origin-when-cross-origin"`, which overrides the
  document policy for that element alone and sends the origin and nothing more.

**Days are the reader's days.** Everything is stored in UTC and bucketed using
the offset the browser reports, because a walk that starts at half past midnight
in summer otherwise lands on the day before. One offset covers the whole window,
so on the two days a year the clocks move an hour of fixes sits on the
neighbouring day. Named in `server/movement.mjs` rather than engineered around.

**Steps are not added up.** The phone uploads one HealthKit cumulative-sum row
per calendar day, so `timeline` returns step records rather than a total: a
window that overlaps two of them would otherwise report a day that never
happened. Sleep is unioned rather than summed for the same reason the health tab
already gives — stages overlap across sources.

## Validation

`npm test` verifies authentication, owner isolation, family boundaries, consent enforcement, input validation, idempotent retries, deletion isolation, pairing replay/expiry, CSRF and device revocation. It also covers the movement lane: that a track is readable by nobody but the person who recorded it, that pausing sharing does not lock you out of your own history, that a gap becomes a second segment rather than a straight line, that distance is never summed across one, that days bucket in the reader's timezone, and that sleep and workouts are selected by overlap so a night that began yesterday evening is not lost. XCTest checks movement cadence, bad GPS accuracy, HTTPS URL rules, queue persistence, corrupt-state handling, the motion-gate decision (including that unreadable motion turns GPS on rather than going quiet) and the duty-cycle arithmetic behind the history screen. Core Motion answers nothing in a simulator, so the gate's judgement is deliberately pure and the state machine itself is device-only. Browser checks cover sign-in, private records, family display, pause/resume, pairing, responsive layout, and the movement map end to end — that the trace draws, that a gap draws dashed, that scrubbing the timeline places a dot on the track and refuses to place one in a gap, and that the map pans and zooms.

[Device acceptance checklist](docs/DEVICE-TESTING.md) covers the remaining physical-iPhone checks. Passing API/simulator tests does not establish battery life, continuous background delivery, TestFlight installation or production integration.

## QR pairing

On the companion dashboard, open **Connect & privacy → Create pairing QR code**. In the iPhone app, choose **Pair by QR code**, allow camera access, scan the dashboard on another screen, and confirm the displayed server. The QR carries the HTTPS origin and a single-use token. It expires after ten minutes; creating another QR invalidates the previous token. The app rejects unrelated QR codes and non-HTTPS origins. Manual paste remains available, with a Show pairing code switch. The app uses a consistent light paper appearance even when the system is in dark mode.

## Chat and news, natively

The **Chat** and **News** tabs are native SwiftUI, not a web view. They read
`/api/native/*` on strangeramblings.com over a paired device token.

- **Chat** — the thread ledger with search across the whole archive, paged
  history, send, and a live SSE stream carrying tokens, reasoning and tool-step
  summaries. Markdown and fenced code render natively; a stop button cancels the
  turn. Attachments are listed, not composed — the phone does not upload.
- **News** — the five desk views (top, new, best, for you, saved), source and
  heat detail, cross-wire "also on" evidence, correlation against the knowledge
  base, and all four row actions (save, keep in graph, link in note, commission
  research). A saved story is the same row the desk shows.

Four turns a chat can take are **not** answerable here — a plan approval, a
dangerous-command confirmation, a clarification, and a credential request. All
four are desk-shaped. The app names the gate and offers the website rather than
spinning on a turn that will never resolve.

### Two pairings, deliberately

The app holds two independent credentials:

| Pairing | Server | Grants |
| --- | --- | --- |
| **Companion** | your health/family server, `/api/apple/*` | health upload, family location |
| **Connect** | strangeramblings.com, `/api/native/*` | chat threads, the news desk |

They are separate so revoking one never silently takes the other with it. The
site credential is minted at **Admin → Access → Devices**, is single-use, expires
in ten minutes, and the device token it yields lasts ninety days and is revocable
from that page at any time. Only the SHA-256 is stored server-side.

## Design

The app wears the site's design system — Archivo Black display, DM Sans body,
DM Mono brand mark, JetBrains Mono labels, the warm-brutalist palette from
`src/app.css`, radius 0 (pills and dots at 100), no shadows.

It follows the **/health methodology** rather than a reading of the tokens:
`SectionHead`'s mono kicker → uppercase headline as an array of lines →
standfirst; the ranked-moves ledger for the news stream; the tripwire ledger for
the thread list; and the rule that **ink is chrome and thin bands** — a tall
solid ink area reads as intensity, not editorial. Two colour registers exist
(`SRRegister.paper` / `.ink`) because a paper token is invisible on an ink band,
which is what every relighting bug on the website turned out to be.

The app is light-locked. That is not an omission: the site has no dark mode, and
the simulator in CI is booted in **dark** appearance on purpose so a regression
shows up as a screenshot.

Fonts are the four OFL families, instanced to static cuts and bundled under
`ios/SRAppleApp/Fonts/` with their licences. `Font.custom` fails silently on a
missing face, so `SiteTests.testEveryNamedFontIsRegistered` asserts all nine
arrived.

> `@auth/core` is pinned **exactly**, not with a caret. The session token is a
> cross-service contract with the main site — both must derive the same key from
> `AUTH_SECRET` — so a minor bump that changed the JWE format would silently stop
> every browser signing in while the phone kept working on its device token. Pin
> it to whatever SR-Main resolves (`0.41.3` as of 2026-09-22) and move both
> together.

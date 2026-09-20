# SR-AppleApp

Native iPhone companion and private web/API pilot for Strange Ramblings.

- **Private health:** steps, heart rate, resting heart rate, sleep stages and workouts.
- **Family locations:** latest shared position, accuracy, recorded time and received time.
- **Adaptive location recording:** targets 10 minutes stationary and 30 seconds moving, with a 3-minute stop threshold. These are best-effort recording intervals, not guaranteed GPS or upload schedules.
- **Offline sync:** protected on-device queue, retry, idempotent ingestion, HealthKit change anchors/deletions, and server-side device revocation.

Health is always scoped to the authenticated person. Family membership grants access to shared locations only. No public health projection, family health endpoint, or administrator health-view bypass exists. Server operators with filesystem/database access still technically control the stored data; this is not end-to-end encryption.

## Test the running local preview

Open **http://192.168.0.77:5275/apple-app/** on the local network.

| Synthetic account | Family |
| --- | --- |
| `alex@example.test` | Demo family |
| `sam@example.test` | Demo family |
| `robin@example.test` | Separate family |

All three use the **local-only** password `SR-local-demo-only!`.

Sign in as Alex, inspect My health, switch to Family locations, and pause sharing under Connect & privacy. Sign in as Sam in a second browser/private window: Sam sees only Sam's health, and Alex's location disappears while paused. Robin cannot see either member of the demo family. Refresh the family tab after changing sharing in another window.

This HTTP preview contains synthetic data only. It is **not connected to production**, does not read Apple Health in the browser, and is not the iPhone app. Real-device pairing requires trusted HTTPS and an installed signed build.

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
npm test
APP_ORIGIN=http://127.0.0.1:5295 DEMO_MODE=1 npm run seed:demo
APP_ORIGIN=http://127.0.0.1:5295 DEMO_MODE=1 npm start
```

No external Node runtime packages. SQLite is provided by Node; its experimental warning on Node 22 is expected. A single application process owns the database; do not scale replicas against the same SQLite file. Database files belong in the mounted volume, never Git.

For a local container:

```sh
APP_ORIGIN=http://127.0.0.1:5295 docker compose -f deploy/compose.yaml config
APP_ORIGIN=http://127.0.0.1:5295 docker compose -f deploy/compose.yaml up -d --build --wait
```

The persistent host preview is configured by `/home/john/docker/local/compose.apple-app.yaml` and uses its own `porkserv-local_apple_app_data` volume. The service binds only to loopback. The existing LAN preview gateway forwards `/apple-app/` and `/api/apple/` without injecting the site's synthetic owner session. It never uses production data, credentials, or the Docker socket.

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
- Continuous/low-accuracy location monitoring and significant-change recovery detect movement. GPS drift is filtered; inaccurate or old fixes are discarded. Recording frequency does not equal sensor frequency. The best-effort timer works only while iOS runs the process. Suspension, force-quit, disabled Background App Refresh, low power and poor reception cause gaps. Stationary points are not fabricated from stale coordinates.
- Pausing sharing on the website hides the last position immediately. The phone stops collection when it next reaches the server. Pausing on an offline phone stops collection immediately; server visibility changes only once the pause reaches the server.
- Queue and anchors are persisted atomically with iOS file protection and excluded from backup. Tokens use device-only Keychain storage. The queue caps at 50,000 records and stops advancing collection when full. Uploads retry on subsequent events, foreground launch, a best-effort retry timer, and OS-scheduled background refresh.
- Browser and native history views are bounded recent-record views, not full historical analytics. Maps open explicitly in Apple Maps rather than automatically sharing coordinates with an embedded third-party map.
- Locations are retained for up to 30 days (pruned on ingestion); family reads expose the latest point only. Health records remain until deletion. Delete uploaded data revokes paired devices to prevent immediate automatic re-upload.
- Real family account provisioning is administrator CLI-only for this pilot. Existing Strange Ramblings SSO, invitation management and legacy health analytics integration are not implemented. See [site integration](docs/INTEGRATION.md).

## Validation

`npm test` verifies authentication, owner isolation, family boundaries, consent enforcement, input validation, idempotent retries, deletion isolation, pairing replay/expiry, CSRF and device revocation. XCTest checks movement cadence, bad GPS accuracy, HTTPS URL rules, queue persistence and corrupt-state handling. Browser checks cover sign-in, private records, family display, pause/resume, pairing and responsive layout.

[Device acceptance checklist](docs/DEVICE-TESTING.md) covers the remaining physical-iPhone checks. Passing API/simulator tests does not establish battery life, continuous background delivery, TestFlight installation or production integration.

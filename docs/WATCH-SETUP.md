# Apple Watch: one-time setup

The Watch app and its complications are built by CI on every change, but
TestFlight only includes them once Apple knows about them. Until then every
upload is the iPhone app alone, with a warning in the log saying why. Nothing
breaks in the meantime.

## Part A: the only part done by hand (about 10 minutes)

At developer.apple.com/account → **Certificates, Identifiers & Profiles** →
**Identifiers**:

1. **+** → **App Groups** → identifier `group.com.strangeramblings.com.appleapp`.
2. **+** → **App IDs** → **App** → explicit bundle ID
   `com.strangeramblings.com.appleapp.watchkitapp`. Tick **App Groups** and
   **HealthKit**. Register, then open it, **Configure** App Groups, tick the
   group from step 1, **Save**.
3. **+** → **App IDs** → **App** → explicit bundle ID
   `com.strangeramblings.com.appleapp.watchkitapp.complications`. Tick **App
   Groups** only. Register, then **Configure** the same group and **Save**.

(With a different `APPLE_BUNDLE_ID`, use that in place of
`com.strangeramblings.com.appleapp` throughout.)

The App Store Connect API can register App IDs but cannot attach an App Group
to one, which is why this part stays manual.

## Then: run Upload to TestFlight

`scripts/asc-watch-profiles.py` runs first in the job. With the API key the job
already uploads with, it:

- finds the two App IDs and the Apple Distribution certificate the iPhone app's
  profile is signed with;
- makes a fresh App Store profile for each, named `SR CI <bundle ID>`, replacing
  the one from the previous run (a profile only carries the capabilities its
  App ID had when it was made, so a stale one would hide a fix);
- checks each has the App Group, and the Watch app's has HealthKit;
- hands them to `install-signing.sh`, which checks them again and archives all
  three targets.

If anything is missing it says exactly what, as a warning, and uploads the
iPhone app alone:

| The warning says | Fix |
| --- | --- |
| There is no App ID … | Part A, steps 2–3 |
| … does not have the App Group … attached | Part A: Configure App Groups on that App ID |
| … does not have HealthKit ticked | Part A, step 2 |
| App Store Connect refused the API key (401/403) | The key needs the **Admin** role, or App Manager with access to Certificates, Identifiers & Profiles: App Store Connect → Users and Access → Integrations. Or use the manual route below. |

## The manual route (only if the API key cannot manage profiles)

Make the two App Store profiles by hand under **Profiles**, with the same
Apple Distribution certificate, then add them to the `testflight` environment
as `WATCH_PROVISION_PROFILE_BASE64` and `WIDGET_PROVISION_PROFILE_BASE64`
(each file base64-encoded: `base64 -i file.mobileprovision | pbcopy` on a Mac).
Secrets, when both are set, are used instead of asking Apple.

## After it is on your wrist

See [Device testing](DEVICE-TESTING.md#the-watch-app-phases-1-and-2).

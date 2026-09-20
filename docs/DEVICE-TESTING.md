# Physical iPhone acceptance

Use a trusted HTTPS staging server and separate test accounts. Do not mistake simulator/unit tests for these checks.

- Pair using a fresh code; reusing or waiting more than 10 minutes rejects the code.
- Health/location stay off until selected. Grant a subset of HealthKit categories and deny another; no claim of confirmed read permission for the denied category.
- Sync steps, HR, RHR, sleep stages and workouts. Compare each against Apple Health for the same day/source/timezone. Check overlapping phone/Watch steps and overlapping sleep sources.
- Add, update and delete samples in Apple Health. Confirm idempotent uploads and sample deletions. Daily step-bucket removal has the limitation documented in README.
- Disable each health category while collecting, then sync. No newly queued records in that category are sent. An already in-flight request may have completed before the setting changed.
- Disable networking, collect several points, terminate/reopen the app, reconnect and sync. Queued records survive and retries do not create duplicates.
- Start stationary, walk for 10 minutes, stop for 5 minutes. Check GPS accuracy and recorded timestamps. Repeat with the screen locked, Background App Refresh disabled, low-power mode and after force-quit. Record actual gaps rather than assuming target intervals.
- Leave the phone locked overnight. Reopen after unlock and confirm deferred HealthKit data catches up.
- Pause location on the phone offline. New local points stop; the server may display the previous point until the pause is delivered. Pause from the browser online and confirm family reads immediately hide the previous location.
- Sign in as a second family member: location only, never the first person's health. Another family sees neither.
- Revoke the phone from the website: further device reads and uploads fail. Disconnect and re-pair successfully with a fresh code.
- Delete uploaded data: records disappear, devices and pending pair codes are revoked, sharing turns off, other people's records remain. Apple Health remains unchanged.
- Measure battery use for a full typical day against a baseline, including cellular upload. Review before inviting the family.

This is not an emergency tracking service. The interface must display stale/missing data rather than suggesting guaranteed coverage.

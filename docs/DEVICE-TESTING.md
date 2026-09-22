# Physical iPhone acceptance

Use a trusted HTTPS staging server and separate test accounts. Do not mistake simulator/unit tests for these checks.

- Scan a dashboard QR on another screen, confirm the server, and verify successful pairing. Cancel confirmation and verify no pairing occurs. Deny camera access and check Settings/manual-paste fallback. Scan an unrelated QR and check its error.
- With system dark appearance enabled, check server/code text, placeholders, keyboard, Show pairing code, and the scanner sheet.
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

## The motion gate

The state machine is device-only — Core Motion answers nothing in a simulator, so
none of this is covered by CI. The failure to look for is not a crash, it is
silence: an app that looks fine and records nothing.

- Turn the gate on (Settings → C / Movement, or pick Balanced) and press Apply.
  The Motion & Fitness sheet must appear THERE, in the foreground. Core Motion
  has no request API — the sheet appears on the first query — and iOS will not
  put one in front of a suspended app, so if it does not appear here it will
  never appear at all and the gate will never work. Grant it. If Always location access has not been granted, the history
  must show a STAYED ON line naming that, and GPS must keep running.
- Sit still for longer than the sleep threshold. The blue background-location
  indicator should disappear and the history should show GPS OFF with the anchor
  radius. Nothing else should change on the screen.
- Walk out of the anchor. Check the history shows WOKEN, then either GPS ON with
  what the motion log said, or BACK TO SLEEP with a re-anchor. Note how long the
  wake took — that latency is the thing being bought.
- Drive away from a sleeping phone. This must wake within about a minute even
  though the step count is zero; a step threshold alone would never catch it.
- Stand up, cross a room, sit down again. This should read as a blip and go back
  to sleep, not start GPS.
- Force-quit while asleep, then move. The app is relaunched by the geofence and
  must come back ASLEEP, not into continuous GPS — check the history for
  RELAUNCHED ASLEEP rather than SHARING ON. If the phone has already left the
  stored anchor, the wake reason should be "Anchor is already behind us".
- Leave it a full day. Read the hit rate on the history screen: if most wakes
  found nothing, widen the anchor and leave it another day. Compare the drain and
  points figures in section A against the same day with the gate off — that
  comparison is the entire point of the screen.
- Turn Motion & Fitness off in iOS Settings while the gate is on. The app must
  start GPS and say why, never go quiet.

This is not an emergency tracking service. The interface must display stale/missing data rather than suggesting guaranteed coverage.

## JKAI chat

- Open the JKAI tab before or after pairing health. Tap Open JKAI chat, sign in with the existing site Google account, and confirm the expected conversation library.
- Check keyboard/composer, streaming replies, thread switching, attachments, links, background/resume, Back to SR Companion, and reopening. Google sign-in and actual chat need a physical-device check.
- Confirm that a family companion account alone does not grant JKAI access. Chat uses the existing website session and owner gate; companion bearer tokens are never sent to it.
- The in-app browser does not install the PWA or provide its Home Screen push/offline guarantees. Test those in the separately installed PWA if needed.

- From the main Companion page, open JKAI, News, and Health; check the expected website and sign-in, then tap Back to SR Companion and reopen another link. Verify the native health pairing remains intact.

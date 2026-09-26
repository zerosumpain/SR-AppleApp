# Physical iPhone acceptance

Use a trusted HTTPS staging server and separate test accounts. Do not mistake simulator/unit tests for these checks.

- Scan a /welcome pairing QR on another screen, confirm the server, and verify successful pairing. Cancel confirmation and verify no pairing occurs. Deny camera access and check Settings/manual-paste fallback. Scan an unrelated QR and check its error.
- With system dark appearance enabled, check server/code text, placeholders, keyboard, Show pairing code, and the scanner sheet.
- Pair using a fresh code; reusing or waiting more than 10 minutes rejects the code.
- Health/location stay off until selected. Grant a subset of HealthKit categories and deny another; no claim of confirmed read permission for the denied category.
- Sync steps, HR, RHR, sleep stages and workouts. Compare each against Apple Health for the same day/source/timezone. Check overlapping phone/Watch steps and overlapping sleep sources.
- Add, update and delete samples in Apple Health. Confirm idempotent uploads and sample deletions. Daily step-bucket removal has the limitation documented in README.
- Disable each health category while collecting, then sync. No newly queued records in that category are sent. An already in-flight request may have completed before the setting changed.
- Disable networking, collect several points, terminate/reopen the app, reconnect and sync. Queued records survive and retries do not create duplicates.
- Start stationary, walk for 10 minutes, stop for 5 minutes. Check GPS accuracy and recorded timestamps. Repeat with the screen locked, Background App Refresh disabled, low-power mode and after force-quit. Record actual gaps rather than assuming target intervals.
- Leave the phone locked overnight. Reopen after unlock and confirm deferred HealthKit data catches up.
- Pause location on the phone offline. New local points stop; the server may display the previous point until the pause is delivered. Pause from strangeramblings.com/welcome online and confirm family reads immediately hide the previous location.
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

## Apple Watch

Phase 0 of [the watch plan](WATCH.md): buttons on the alerts the phone already
raises. Needs a paired Watch, notification permission granted, and a site
connection. A simulator cannot press a notification button.

- Lock the phone with the Watch on your wrist and let a background refresh raise
  an alert, or open the app, raise one and then lock it. The alert should arrive
  on the Watch with **Mark read** and **Clear from Today** under it.
- Press **Clear from Today** on the Watch. Unlock the phone: that row must be
  gone from the Today card and still listed on the Alerts screen.
- Press **Mark read** on the Watch. The badge should drop by one, and on
  unlocking, the Alerts screen should show that alert read and the others
  untouched. Mark an alert read on the website first and then press **Mark
  read** on its notification: the badge must not drop a second time. Repeat in
  flight mode: nothing should change, and the badge must not drop.
- Raise a lapsed-connection alert. It must arrive with NO buttons.
- On a family member's phone (not the owner's), no site alert should arrive at
  all. If one raised before a role change is still in Notification Centre,
  **Mark read** on it must do nothing.
- Tap an alert itself (not a button) on the phone. It must open the tab for its
  category, as before, and a connections alert must open the connections list.
- Do the same with the phone unlocked, from the lock-screen banner's long press.
  The buttons behave identically.

### The Watch app (Phases 1 and 2)

Needs a TestFlight build made with the Watch profiles (the upload log says
"uploading the iPhone app without the Watch app" when they are missing), and
the app installed on the Watch from the Watch app on the phone. WatchConnectivity
does not run between simulators reliably, so all of this is device-only.

- Open the phone app, then the Watch app. Today should show Readiness and
  Recovery matching the phone's rings within a few seconds, and "From iPhone ·
  now". With Apple Health's activity rings shared on the Watch, Move should
  match the Activity app; before that, "Show my Move ring" asks once.
- Pull the phone's Today to refresh after a health upload. The Watch's numbers
  follow without opening the Watch app again.
- **Alerts:** swipe a row, press **Clear**. It leaves the Watch at once and the
  phone's Today card. Press **Read** on another: the phone's badge drops by one.
  With the phone in flight mode the Watch says "Queued for your iPhone", and
  both happen when the phone is back.
- **Ask jkai:** dictate a question. The phone's chat composer must open with
  it waiting, UNSENT. Nothing may send on its own.
- **iPhone page:** the queue count, the last upload and the location gate match
  Settings on the phone. **Sync now** says "Syncing on your iPhone" and the
  queue drops.
- **Workflows:** pin one on the phone (a workflow's ••• menu → Pin to Apple
  Watch; a fourth pin is refused). It appears on the Watch. Running it asks
  first; after **Run** the site's run list shows it. Unpin it on the phone:
  it leaves the Watch, and an old copy of the page must not be able to run it.
- **Complications:** add Readiness and Alerts to a face. They show the same
  numbers as the app and update when the phone sends new ones.
- **A family member's Watch:** no Alerts or Workflows page, no unread count in
  the complication, and Ask only if they have chat.
- Revoke the phone's pairing on the website. The Watch keeps its last numbers
  (it holds no credential) but nothing it asks for succeeds.

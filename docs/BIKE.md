# The e-bike: field test with nRF Connect

The bike is an Amflow PR Carbon Pro (2027) on the Avinox drive. Avinox has no
public API, writes nothing to Apple Health, and sends nothing over ANT+ or
standard Bluetooth to other devices. Its only outside link is to Strava, which
this project retired. So everything the app learns about the bike comes from
the Bluetooth link the Avinox Ride app makes.

**Option A (built):** the app checks whether the bike is connected to the phone
and marks each location fix taken while it is (`bike: true`). The pilot sends
the marked stretches of each journey (`bikeSpans` on `/api/apple/journeys`), and
/health files that time as a "Captured e-bike ride" (`mtb`) rather than a
drive. The app never connects to the
bike, reads from it or writes to it. See `BikePresence.swift`.

**Option C (not built):** read the bike's own live data (battery, assist mode,
motor and rider power, cadence). This only works if the data is not encrypted.

This test answers four questions:

1. What Bluetooth services does the bike offer? Option A needs one to look it
   up by.
2. Can the app see the bike while the Avinox app holds the link?
3. Is the bike still connected to the phone **during a ride**? If not, option A
   marks nothing.
4. Is the live data plain or encrypted? This decides whether option C is
   possible.

Allow about 30 minutes stationary plus one normal ride.

## Safety rules for every step

- **Never press a write button** (the ↑ arrow) on any characteristic. Only
  read (↓) and subscribe (the triple ↓ / "notify" toggle). A write could change
  motor settings.
- Do the stationary steps with the bike on a stand or leaning, **assist off**
  or the bike in walk mode. Do not pedal under assist with the wheel off the
  ground.
- Disconnect nRF Connect from the bike before reopening the Avinox app.
- If iOS shows a **Bluetooth Pairing Request** while nRF Connect is connected,
  tap **Cancel**. Note that it appeared (it is an answer), but do not pair a
  second time. The bike is already bonded to the Avinox app.

## Before you start

- [ ] Install **nRF Connect for Mobile** (Nordic Semiconductor) from the App
      Store.
- [ ] Bike charged and switched on, phone near it.
- [ ] iOS Settings → Bluetooth: is the bike listed under **My Devices**?
      Write down the name exactly as shown: ________________

## Test 1: what the bike offers (stationary, ~10 min)

A bike that is connected to a phone usually stops advertising, so nRF Connect
cannot find it. Free the link first:

- [ ] Force-quit the **Avinox Ride** app (swipe it away).
- [ ] Switch the bike off and on again.
- [ ] Open nRF Connect → **Scanner**. Turn on the filter for named devices
      only. Find the bike: the name from above, or one with "Avinox", "DJI" or
      "Amflow" in it.

On the scanner row (tap it to expand), record:

- [ ] Name: ________________
- [ ] Advertised service UUIDs: ________________
- [ ] Manufacturer data (the company ID is the first 4 hex digits):
      ________________
- [ ] Signal strength (RSSI) next to the bike: ______ dBm

Then tap **Connect**. On the services list, record:

- [ ] Every **service** UUID. Take a screenshot of the whole list.
- [ ] Is **Device Information (0x180A)** there? Y / N. If yes, tap it and read
      Manufacturer, Model and Firmware: ________________
- [ ] Is **Battery Service (0x180F)** there? Y / N. Does the level match the
      bike's battery, or the display's? ______
- [ ] Any standard fitness service, which would be the jackpot? **Cycling
      Power 0x1818** / **Cycling Speed and Cadence 0x1816** / **Fitness
      Machine 0x1826** / **Heart Rate 0x180D**. Which: ______
- [ ] For each **other** (custom, 128-bit) service, expand it and screenshot
      its characteristics with their properties (Read / Write / Notify /
      Indicate).
- [ ] Did reading anything raise a pairing request or an "insufficient
      authentication / encryption" error? Y / N, and on which: ______

Leave it connected for Test 4, or **Disconnect** now if you are stopping here.

## Test 4: is the live data readable? (stationary, ~10 min)

This decides option C. It needs the Test 1 connection, with the Avinox app
still closed.

- [ ] In each custom service, turn on **notify** for every characteristic that
      offers it. Open the **Log** tab.
- [ ] Do packets arrive without doing anything? Roughly how often? ______
- [ ] Change the **assist mode** on the bar remote two or three times. Does one
      characteristic change **in step** with it, with the same few bytes
      flipping to the same values each time you return to a mode? Y / N
- [ ] Spin a crank backwards by hand, or the rear wheel on a stand with assist
      off. Does a value climb and fall with it? Y / N
- [ ] Or does **every** packet look like fresh random bytes, even when nothing
      changes? Y / N. If so, the data is encrypted and **option C is dead**.
      Stop there.
- [ ] Log tab → share icon → save the log. Send it back with the screenshots.
- [ ] **Disconnect** in nRF Connect.

## Test 2: can SR Companion see it? (needs the build with Settings → Bike)

- [ ] Open the **Avinox Ride** app and let it connect to the bike as usual.
- [ ] SR Companion → Settings → **Bike** → **Search for connected devices**.
      Allow Bluetooth when asked.
- [ ] Is the bike listed? Y / N
- [ ] If not, type the bike's **own service UUID** from Test 1 into the field
      (a custom one, ideally one that was advertised) and search again. Listed
      now? Y / N. Which UUID worked: ________________
- [ ] Tap the bike, then **Check now**. Does it say **Connected now**? Y / N
- [ ] Close the Avinox app, wait 30 s, and tap **Check now**. Does it change to
      **Not connected**? Y / N

## Test 3: is it connected during a ride? (one normal ride)

Option A only marks a ride if the bike is connected to the phone while you
ride.

- [ ] Before you set off, open the Avinox app and confirm it is connected. Then
      lock the phone and put it away as normal.
- [ ] Ride at least 20 minutes, partly above 16 km/h.
- [ ] Afterwards, without opening anything else first, check the Avinox app.
      Did it record the ride **live** (a track on the phone), or did it **sync
      afterwards** ("syncing ride data…")? ______
- [ ] SR Companion → Settings → Bike → **Check now** while still on the bike:
      connected? Y / N
- [ ] Note the ride's start and end times: ______ to ______. Claude can read the
      pilot's fixes for that window and count how many were marked `bike`.

If the Avinox app only syncs after the ride, the phone is probably not
connected while you ride. Option A would then need the app to hold its own
connection (the `bluetooth-central` background mode, still strictly
read-only). That is a separate change.

## What to send back

| Question | Answer |
|---|---|
| Bike's name in iOS Bluetooth | |
| Advertised service UUIDs | |
| 0x180A / 0x180F present | |
| Any standard fitness service | |
| Custom service UUIDs (screenshots) | |
| Pairing prompt or encryption error on read | |
| Notify data follows assist mode / crank (plain) or random (encrypted) | |
| SR Companion lists the bike (and with which UUID) | |
| Connected during the ride | |
| Ride window for the pilot check | |

Screenshots and the nRF Connect log can go straight into a chat with Claude.

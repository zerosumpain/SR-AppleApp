#!/usr/bin/env node
// Every bundled face must be asked for at a size that SCALES.
//
// `Font.custom(_:size:)` and `UIFont(name:size:)` both return a fixed size and
// ignore the reader's text setting completely. The app shipped 104 call sites
// on the fixed forms, so a phone set to Larger Text rendered identically to one
// set to the smallest — a property the web original has for free, because there
// the same values are `rem`.
//
// Fixing the helpers is not enough on its own: the next person to write a view
// reaches for `.custom(SR.Face.body, size: 15)` because that is what the old
// code looked like. So this is the gate. It runs on the cheap ubuntu job, not
// the 10x macOS one, because it is a grep and it should answer in a second.
//
//   node scripts/check-dynamic-type.mjs
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, sep } from 'node:path';

const ROOT = 'ios';

/** `UIFontMetrics` is UIKit's `relativeTo:`, and the appearance proxy needs it. */
const ALLOWED = [/relativeTo:/, /UIFontMetrics/, /dynamic-type-exempt/];

/**
 * Test targets are exempt, and not as a convenience.
 *
 * `testEveryNamedFontIsRegistered` asserts that each bundled face LOADS, and
 * the only way to ask that question is the fixed initialiser — a scaled font
 * would answer about the metrics rather than about the file. `Font.custom`
 * fails silently to the system font, so that test is the one thing standing
 * between a missing .ttf and a screen that renders perfectly in the wrong face.
 */
const EXEMPT_DIRS = ['SRAppleAppTests', 'SRAppleAppUITests'];

function swiftFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) {
      if (EXEMPT_DIRS.includes(entry)) continue;
      out.push(...swiftFiles(path));
    }
    else if (entry.endsWith('.swift')) out.push(path);
  }
  return out;
}

/**
 * Files where the SYSTEM face may not be fixed either: `.system(size:)` is
 * the same mistake in SF Pro, and an SF Symbol sized that way stays small
 * while the words beside it grow. A ratchet, file by file: the trip screens
 * first (plan §5.5), so a file is added here once it is clean, and the rest
 * of the app follows. Text styles (`.font(.footnote)`) or `@ScaledMetric`
 * are the fix.
 */
const NO_FIXED_SYSTEM = new Set([
  'ios/SRAppleApp/Trips/TripDrawer.swift',
  'ios/SRAppleApp/Trips/TripLink.swift',
  'ios/SRAppleApp/Trips/TripLive.swift',
  'ios/SRAppleApp/Trips/TripMap.swift',
  'ios/SRAppleApp/Trips/TripMapScene.swift',
  'ios/SRAppleApp/Trips/TripMeals.swift',
  'ios/SRAppleApp/Trips/TripOffPlan.swift',
  'ios/SRAppleApp/Trips/TripOffPlanRules.swift',
  'ios/SRAppleApp/Trips/TripOptionsSheet.swift',
  'ios/SRAppleApp/Trips/TripQuestionFocus.swift',
  'ios/SRAppleApp/Trips/TripReady.swift',
  'ios/SRAppleApp/Trips/TripShareShared.swift',
  'ios/SRAppleApp/Trips/TripStopScreen.swift',
  'ios/SRAppleApp/Trips/TripStory.swift',
  'ios/SRAppleApp/Trips/TripWeather.swift',
  'ios/SRAppleApp/Trips/TripWeatherStore.swift',
  'ios/SRAppleApp/Home/HomeTripWords.swift',
  'ios/SRAppleApp/Home/HomeTripsDoor.swift',
  'ios/SRAppleApp/Alerts/TripQuestionPushes.swift',
  'ios/SRAppleApp/Alerts/TripQuestionAlerts.swift',
]);

const offences = [];
for (const file of swiftFiles(ROOT)) {
  const lines = readFileSync(file, 'utf8').split('\n');
  lines.forEach((line, index) => {
    // Comments explain the rule; they do not break it.
    const code = line.replace(/\/\/.*$/, '').replace(/^\s*\/\/\/.*$/, '');
    const fixed =
      /Font\s*\.\s*custom\s*\(/.test(code) ||
      /\.custom\(\s*(SR\.)?Face\./.test(code) ||
      /UIFont\(name:/.test(code) ||
      (NO_FIXED_SYSTEM.has(file.split(sep).join('/')) && /\.system\(\s*size:/.test(code));
    if (!fixed) return;
    // Tested against the RAW line, so an inline exemption comment counts.
    if (ALLOWED.some((pattern) => pattern.test(line))) return;
    offences.push(`${file}:${index + 1}  ${line.trim()}`);
  });
}

if (offences.length > 0) {
  console.error('check-dynamic-type: a font was asked for at a FIXED size.\n');
  for (const offence of offences) console.error(`  ${offence}`);
  console.error(`
A font built this way never answers the reader's text setting. Use the helpers
in SR.Text (or SR.body / SR.mono, which scale too), or pass \`relativeTo:\`
yourself. In UIKit the equivalent is SRChrome.scaled(_:_:_:), which wraps
UIFontMetrics. In the files listed in NO_FIXED_SYSTEM, \`.system(size:)\` is
caught too: use a text style (\`.font(.footnote.weight(.semibold))\`) instead.
`);
  process.exit(1);
}
console.log('check-dynamic-type: OK — every bundled face scales.');

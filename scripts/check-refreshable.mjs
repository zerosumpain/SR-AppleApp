#!/usr/bin/env node
// Pull-to-refresh goes through `srRefreshable`, never a bare `.refreshable`.
//
// SwiftUI cancels a refresh action's task when the view redraws mid-refresh,
// and every store here redraws the screen on its first line (`loading = true`).
// A bare `.refreshable` therefore cancelled its own request within a frame and
// the app showed "cancelled" on every pull. `srRefreshable` (Design/SRNative)
// runs the work in a task SwiftUI cannot cancel.
//
//   node scripts/check-refreshable.mjs
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = 'ios';
const HOME = join('ios', 'SRAppleApp', 'Design', 'SRNative.swift');

function swiftFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) out.push(...swiftFiles(path));
    else if (entry.endsWith('.swift')) out.push(path);
  }
  return out;
}

const offences = [];
for (const file of swiftFiles(ROOT)) {
  if (file === HOME) continue;
  readFileSync(file, 'utf8').split('\n').forEach((line, index) => {
    const code = line.replace(/\/\/.*$/, '');
    if (/\.refreshable\s*[({]/.test(code)) offences.push(`${file}:${index + 1}  ${line.trim()}`);
  });
}

if (offences.length > 0) {
  console.error('check-refreshable: a bare `.refreshable` cancels its own request.\n');
  for (const offence of offences) console.error(`  ${offence}`);
  console.error('\nUse `.srRefreshable { … }` from Design/SRNative.swift instead.\n');
  process.exit(1);
}
console.log('check-refreshable: OK — every pull-to-refresh is shielded.');

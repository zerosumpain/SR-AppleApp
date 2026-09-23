#!/usr/bin/env node
// App Intent metadata must not name Apple's products.
//
// App Store Connect rejects a binary (ITMS-90626, "Invalid Siri Support") when
// an intent's title, description, parameter title or Siri phrase contains an
// Apple trademark. Build 10 was bounced on 2026-09-23 for the single word
// "iPhone" in SyncNowIntent's description. Nothing local catches it: the
// simulator build, the tests and the archive all pass, and the rejection
// arrives by email hours after the upload.
//
// Only the metadata is checked. A spoken `IntentDialog` is produced at run time
// and is not part of what App Store Connect reads, so "Connect this iPhone
// first" is fine there.
//
//   node scripts/check-intent-metadata.mjs
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = 'ios';
const BANNED = /\b(iphone|ipad|ipod|apple|siri|mac|macos|ios|watchos|apple\s*watch|airpods|homepod|carplay)\b/i;

/** The places App Store Connect reads from: each captures the literal(s) that follow. */
const METADATA = [
  /static\s+var\s+title\s*:\s*LocalizedStringResource\s*=\s*("(?:[^"\\]|\\.)*")/g,
  /IntentDescription\(\s*("(?:[^"\\]|\\.)*")/g,
  /@Parameter\(([^)]*)\)/g,
  /shortTitle:\s*("(?:[^"\\]|\\.)*")/g,
  /phrases:\s*\[([^\]]*)\]/g,
];

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
  const source = readFileSync(file, 'utf8');
  if (!/import\s+AppIntents/.test(source)) continue;
  for (const pattern of METADATA) {
    for (const match of source.matchAll(pattern)) {
      // `\(.applicationName)` is interpolation, not text anybody reads.
      const literals = (match[1].match(/"(?:[^"\\]|\\.)*"/g) ?? [])
        .map((literal) => literal.replace(/\\\([^)]*\)/g, ''));
      for (const literal of literals) {
        if (!BANNED.test(literal)) continue;
        const line = source.slice(0, match.index).split('\n').length;
        offences.push(`${file}:${line}  ${literal}`);
      }
    }
  }
}

if (offences.length > 0) {
  console.error('check-intent-metadata: App Intent metadata names an Apple product.\n');
  for (const offence of offences) console.error(`  ${offence}`);
  console.error(`
App Store Connect rejects the upload with ITMS-90626. Say "phone" or "this
device" instead — titles, descriptions, parameter titles and Siri phrases are
all checked.
`);
  process.exit(1);
}
console.log('check-intent-metadata: OK — no Apple trademarks in App Intent metadata.');

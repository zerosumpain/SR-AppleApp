// Launch flags and test transports must sit inside `#if DEBUG`.
//
// The demo FIXTURES compile in Release now: the App Review demo (a reviewer
// types the review code on Welcome, the site answers `{demo: true}`) runs on
// them in the shipped app. What must never reach a shipped app is a way in
// that skips the site: a `-SR…` launch argument (`-SRDemo`, `-SRDemoMember`,
// `-SRDemoRegistrant`, `-SRFreshInstall`, `-SRStubNetwork`) or the UI tests'
// stub transport (`SRStubURLProtocol`, which says yes to a known code). This
// is a text scan, so it runs on the cheap ubuntu job and answers in a second.
//
// It used to guard `SRDemo` itself, when the whole harness was DEBUG-only: the
// Health hub (#29) referenced it unguarded, every Debug CI job was green, and
// the TestFlight archive (Release) failed. That class of break is now caught by
// the macOS job's Release build, which compiles exactly what TestFlight does.
//
//   node scripts/check-demo-guard.mjs
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = 'ios/SRAppleApp';
const NAMES = /"-SR[A-Za-z]+"|\bSRStubURLProtocol\b|\buseLiveTransport\b/;

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return entry.endsWith('.swift') ? [path] : [];
  });
}

const failures = [];
for (const file of swiftFiles(ROOT)) {
  const lines = readFileSync(file, 'utf8').split('\n');
  // A stack of open conditionals: true where the branch is DEBUG-only.
  const stack = [];
  lines.forEach((raw, index) => {
    const line = raw.trim();
    if (line.startsWith('#if')) stack.push(/^#if\s+DEBUG\b/.test(line));
    else if (line.startsWith('#else') || line.startsWith('#elseif')) {
      if (stack.length) stack[stack.length - 1] = false;
    } else if (line.startsWith('#endif')) stack.pop();
    else if (!line.startsWith('//') && !line.startsWith('///') && NAMES.test(line) && !stack.includes(true)) {
      failures.push(`${file}:${index + 1}: ${line}`);
    }
  });
}

if (failures.length) {
  console.error('check-demo-guard: a launch flag or test transport outside #if DEBUG — it would ship in the App Store build:\n');
  for (const f of failures) console.error(`  ${f}`);
  process.exit(1);
}
console.log('check-demo-guard: OK — every launch flag and test transport is DEBUG-only.');

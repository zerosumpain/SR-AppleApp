// Every reference to the demo harness must sit inside `#if DEBUG`.
//
// `SRDemo` and `SRDemoFixtures` exist only in Debug builds. The macOS CI job
// builds and tests Debug, so an unguarded reference is green there and fails
// only when the TestFlight job archives Release — which is how the Health hub
// (#29) reached main and then could not ship. This is a text scan, so it runs
// on the cheap ubuntu job and answers in a second.
//
//   node scripts/check-demo-guard.mjs
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = 'ios/SRAppleApp';
const NAMES = /\bSRDemo(Fixtures|URLProtocol)?\b/;

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
  console.error('check-demo-guard: demo harness referenced outside #if DEBUG — the Release archive will not compile:\n');
  for (const f of failures) console.error(`  ${f}`);
  process.exit(1);
}
console.log('check-demo-guard: OK — every demo reference is DEBUG-only.');

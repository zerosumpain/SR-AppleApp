// What a phone says about itself, read from two request headers the app
// sends on every call (ios/SRAppleApp/Access/PhoneIdentity.swift):
//
//   X-SR-App:         <version>/<build>/<commit>[/<channel>]   0.1.136/136/68136470/adhoc
//   X-SR-Device:      <model>/<os>[/<name>]          iPhone15,2/26.0.1/Rory%27s%20iPhone
//
// Headers rather than body fields, because every JSON body this server takes
// is checked with `exactKeys` — a new field would 400 the whole upload from an
// old server, while a header an old server never reads costs nothing. The
// same grammar is parsed by SR-Main (`$lib/server/native-telemetry`); change
// both or neither.
//
// Everything is optional and everything is bounded: this is a label the
// device list prints, written by whoever holds a device token, so a value
// that does not fit its shape is dropped rather than stored.

const VERSION = /^[0-9]+(\.[0-9]+){0,3}$/;
const COMMIT = /^[0-9a-f]{7,40}$/;
const MODEL = /^[A-Za-z0-9][A-Za-z0-9,._-]{0,39}$/;
const NAME_MAX = 60;
// How the copy got onto the phone; absent from a build older than the field.
const CHANNELS = ['testflight', 'adhoc', 'xcode'];

function field(value, pattern) {
  return typeof value === 'string' && pattern.test(value) ? value : null;
}

function decodedName(raw) {
  if (!raw) return null;
  let name;
  try { name = decodeURIComponent(raw); } catch { return null; }
  name = name.replace(/[\u0000-\u001f\u007f]/g, '').trim();
  return name && name.length <= NAME_MAX ? name : null;
}

/**
 * The phone's telemetry from a Node request's headers, or null when it sent
 * none — an app build from before these headers existed.
 */
export function phoneTelemetry(headers) {
  const app = typeof headers['x-sr-app'] === 'string' ? headers['x-sr-app'].split('/') : [];
  const device = typeof headers['x-sr-device'] === 'string' ? headers['x-sr-device'].split('/') : [];
  const build = Number.parseInt(app[1] ?? '', 10);
  const out = {
    appVersion: field(app[0], VERSION),
    appBuild: Number.isInteger(build) && build > 0 && build < 2 ** 31 && /^[0-9]+$/.test(app[1]) ? build : null,
    appCommit: field(app[2], COMMIT),
    appChannel: CHANNELS.includes(app[3]) ? app[3] : null,
    deviceModel: field(device[0], MODEL),
    osVersion: field(device[1], VERSION),
    deviceName: decodedName(device.slice(2).join('/')),
  };
  return Object.values(out).some(v => v !== null) ? out : null;
}

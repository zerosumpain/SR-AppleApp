#!/usr/bin/env python3
"""Sign the archived app ad hoc, for phones that cannot use TestFlight.

TestFlight needs an App Store account of 13 or over, so a younger child's
phone cannot install from it. An ad-hoc build installs on any phone whose UDID
is in the developer account, from an `itms-services:` link on SR-Main's
/install page (SR-Main `$lib/server/adhoc-install`). This script, run by
`testflight.yml` after the archive:

1. registers the phone in the run's `adhoc_udid` input (named `adhoc_name`)
   when one is given — SR-Main's enrolment page passes it, or the owner from
   the Actions tab;
2. makes a fresh Ad Hoc profile for each target the archive holds, listing
   every enabled iOS device on the account;
3. writes ExportOptions-adhoc.plist for `xcodebuild -exportArchive`, and
   build.json — what SR-Main's install page says about the copy.

A UDID is never printed. It is read from the event payload rather than an
`env:` block, because GitHub prints a step's env in its log header and this
repo's logs are public; the workflow masks it too. Only device NAMES are logged
or written to build.json. Uses the same API key and helpers as
asc-watch-profiles.py. Exits non-zero on any failure; the workflow decides
whether that may cost the TestFlight upload (it may not).
"""
from __future__ import annotations

import base64
import importlib.util
import json
import os
import plistlib
import re
import sys
import time
from pathlib import Path

_spec = importlib.util.spec_from_file_location("asc_watch_profiles", Path(__file__).with_name("asc-watch-profiles.py"))
asc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(asc)  # type: ignore[union-attr]

NAME_PREFIX = "SR CI adhoc "
PROFILE_DIRS = [
    Path.home() / "Library/MobileDevice/Provisioning Profiles",
    Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
]


def clean_udid(raw: str | None) -> str | None:
    """A UDID as Apple writes it (`00008110-001A2C3E0E12801E`, or 40 hex on old phones), upper-cased."""
    if not raw:
        return None
    u = raw.strip().upper()
    return u if re.fullmatch(r"[0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F]{40}", u) else None


def clean_name(raw: str | None) -> str | None:
    if not raw:
        return None
    n = " ".join(raw.replace("’", "'").split())
    return n if 0 < len(n) <= 50 and re.fullmatch(r"[\w '.-]+", n) else None


def register_device(client, udid: str, name: str) -> None:
    found = client.call("GET", "/devices", query={"filter[udid]": udid, "limit": "5"})
    for item in found.get("data", []):
        if item["attributes"].get("status") != "ENABLED":
            client.call("PATCH", f"/devices/{item['id']}", body={
                "data": {"type": "devices", "id": item["id"], "attributes": {"status": "ENABLED"}},
            })
            print(f"Re-enabled {item['attributes'].get('name')} on the developer account.")
        else:
            print(f"{item['attributes'].get('name')} is already on the developer account.")
        return
    client.call("POST", "/devices", body={
        "data": {"type": "devices", "attributes": {"name": name, "udid": udid, "platform": "IOS"}},
    })
    print(f"Registered {name} on the developer account.")


def enabled_devices(client) -> list[dict]:
    reply = client.call("GET", "/devices", query={"filter[platform]": "IOS", "filter[status]": "ENABLED", "limit": "200"})
    return [{"id": d["id"], "name": d["attributes"].get("name") or "iPhone", "udid": d["attributes"].get("udid")} for d in reply.get("data", [])]


def fresh_adhoc_profile(client, bundle_ref: str, certificate: str, devices: list[dict], name: str) -> bytes:
    """New every run, like the App Store ones: a profile lists only the devices it was made with."""
    existing = client.call("GET", "/profiles", query={"filter[name]": name, "limit": "200"})
    for item in existing.get("data", []):
        if item["attributes"].get("name") == name:
            client.call("DELETE", f"/profiles/{item['id']}")
    created = client.call("POST", "/profiles", body={
        "data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_ADHOC"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_ref}},
                "certificates": {"data": [{"type": "certificates", "id": certificate}]},
                "devices": {"data": [{"type": "devices", "id": d["id"]} for d in devices]},
            },
        }
    })
    return base64.b64decode(created["data"]["attributes"]["profileContent"])


def export_options(team: str, profiles: dict[str, str]) -> dict:
    # `release-testing` is what Xcode 15.3 renamed `ad-hoc` to.
    return {
        "method": "release-testing",
        "teamID": team,
        "signingStyle": "manual",
        "signingCertificate": "Apple Distribution",
        "provisioningProfiles": profiles,
        "thinning": "<none>",
    }


def dispatch_inputs(event_path: str | None) -> dict:
    if not event_path or not Path(event_path).exists():
        return {}
    return json.loads(Path(event_path).read_text()).get("inputs") or {}


def main() -> int:
    env = os.environ
    team, bundle = env["APPLE_TEAM_ID"], env["BUNDLE_ID"]
    temp = Path(env["RUNNER_TEMP"])
    group = "group." + bundle

    inputs = dispatch_inputs(env.get("GITHUB_EVENT_PATH"))
    raw_udid = str(inputs.get("adhoc_udid") or "").strip()
    udid = clean_udid(raw_udid)
    if raw_udid and not udid:
        print("::error::adhoc_udid is not a UDID: 8 characters, a dash and 16 more (or 40 on older phones).")
        return 1
    name = clean_name(str(inputs.get("adhoc_name") or "")) or "iPhone"

    # key, App ID, needs HealthKit, needs the App Group. The extras only when
    # the archive holds them (install-signing.sh set their App Store UUIDs).
    targets = [("app", bundle, True, False)]
    if env.get("WATCH_PROFILE_UUID") and env.get("WIDGET_PROFILE_UUID"):
        targets += [("watch", bundle + ".watchkitapp", True, True), ("widget", bundle + ".watchkitapp.complications", False, True)]
    if env.get("LIVE_PROFILE_UUID"):
        targets.append(("live", bundle + ".live", False, False))
    if env.get("SHARE_PROFILE_UUID"):
        targets.append(("share", bundle + ".share", False, False))

    try:
        client = asc.Client(asc.token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_PRIVATE_KEY"]))
        certificate = asc.find_certificate(client, asc.decode_profile(base64.b64decode(env["PROVISION_PROFILE_BASE64"])))
        if udid:
            register_device(client, udid, name)
        devices = enabled_devices(client)
        if not devices:
            raise asc.Refused("There are no iOS devices on the developer account; an ad-hoc profile needs at least one.")
        print("This copy installs on: " + ", ".join(d["name"] for d in devices))

        profiles: dict[str, str] = {}
        for key, identifier, healthkit, grouped in targets:
            data = fresh_adhoc_profile(client, asc.find_bundle_id(client, identifier), certificate, devices, NAME_PREFIX + identifier)
            profile = asc.decode_profile(data)
            asc.check(profile, team, identifier, group if grouped else None, healthkit)
            if udid and udid not in [u.upper() for u in profile.get("ProvisionedDevices", [])]:
                raise asc.Refused(f"Apple's Ad Hoc profile for {identifier} does not list {name}.")
            for directory in PROFILE_DIRS:
                directory.mkdir(parents=True, exist_ok=True)
                (directory / f"{profile['UUID']}.mobileprovision").write_bytes(data)
            profiles[identifier] = profile["UUID"]
            with open(temp / "adhoc-profile-uuids", "a") as out:
                out.write(profile["UUID"] + "\n")
            print(f"Got an Ad Hoc profile for {identifier}.")
    except asc.Refused as reason:
        print(f"::error::Ad-hoc copy not made: {reason}")
        return 1

    (temp / "ExportOptions-adhoc.plist").write_bytes(plistlib.dumps(export_options(team, profiles)))
    archive = plistlib.loads((temp / "SRAppleApp.xcarchive" / "Info.plist").read_bytes())
    properties = archive.get("ApplicationProperties", {})
    (temp / "build.json").write_text(json.dumps({
        "bundleId": bundle,
        "version": properties.get("CFBundleShortVersionString"),
        "build": properties.get("CFBundleVersion"),
        "commit": env.get("GITHUB_SHA"),
        "builtAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "devices": [d["name"] for d in devices],
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

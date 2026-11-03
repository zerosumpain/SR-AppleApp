#!/usr/bin/env python3
"""Universal links for the iPhone app: the Associated Domains capability and a
profile that carries it, from Apple, every TestFlight run.

What it buys: a link on strangeramblings.com that the site's
apple-app-site-association file claims (an sr. tv party's QR,
/games/join/<CODE>; an install link, /app/<code>) opens the installed app by
itself instead of Safari. The app's side is `applinks:strangeramblings.com` in
SRAppleApp+Links.entitlements.

Run by the TestFlight job before `install-signing.sh`, with the API key the job
already has:

1. turns Associated Domains on for the app's App ID, if it is not on yet;
2. makes a fresh App Store profile for the app (`SR CI app`) — one made before
   the capability was on cannot carry it, which is why the profile in
   PROVISION_PROFILE_BASE64 is not enough;
3. checks the new profile holds everything the old one did, plus the domains;
4. puts its path in $GITHUB_ENV as PROVISION_PROFILE_PATH (install-signing.sh
   installs it instead of the secret's) and SR_APP_ENTITLEMENTS, the entitlements
   file the archive signs the app with.

It never fails the job. Anything refused is a `::warning::` and the archive is
signed as before, with the secret's profile and no universal links. One thing
to know: turning a capability on marks the App ID's OLD profiles invalid in the
developer account, so from then on the app's App Store profile comes from here
each run (as the Watch's and the ad-hoc copy's already do).

Uses asc-watch-profiles.py's helpers. Standard library only.
"""
from __future__ import annotations

import base64
import importlib.util
import os
import sys
from pathlib import Path

_spec = importlib.util.spec_from_file_location("asc_watch_profiles", Path(__file__).with_name("asc-watch-profiles.py"))
asc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(asc)  # type: ignore[union-attr]

PROFILE_NAME = "SR CI app"
DOMAINS_KEY = "com.apple.developer.associated-domains"
ENTITLEMENTS_FILE = "SRAppleApp/SRAppleApp+Links.entitlements"


def ensure_associated_domains(client, bundle_ref: str) -> None:
    # No `limit`: this relationship refuses it (400 PARAMETER_ERROR.ILLEGAL, 2026-11-03); an App ID has few capabilities.
    caps = client.call("GET", f"/bundleIds/{bundle_ref}/bundleIdCapabilities")
    if any(c["attributes"].get("capabilityType") == "ASSOCIATED_DOMAINS" for c in caps.get("data", [])):
        return
    client.call("POST", "/bundleIdCapabilities", body={
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {"capabilityType": "ASSOCIATED_DOMAINS"},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_ref}}},
        }
    })
    print("Turned Associated Domains on for the app's App ID.")


def check(new: dict, old: dict, team: str, bundle: str) -> None:
    got = new.get("Entitlements", {})
    if got.get("application-identifier") != f"{team}.{bundle}":
        raise asc.Refused(f"Apple made a profile for {got.get('application-identifier')}, not {team}.{bundle}.")
    if DOMAINS_KEY not in got:
        raise asc.Refused("The new profile has no Associated Domains, though the App ID should now.")
    # Everything the secret's profile let the app do, the new one must too
    # (HealthKit, push, Sign in with Apple, the keychain group…).
    missing = sorted(k for k in old.get("Entitlements", {}) if k not in got)
    if missing:
        raise asc.Refused(f"The new profile lacks what the current one has: {', '.join(missing)}.")


def main() -> int:
    env = os.environ
    team, bundle = env["APPLE_TEAM_ID"], env["BUNDLE_ID"]
    temp = Path(env["RUNNER_TEMP"])
    try:
        client = asc.Client(asc.token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_PRIVATE_KEY"]))
        old = asc.decode_profile(base64.b64decode(env["PROVISION_PROFILE_BASE64"]))
        bundle_ref = asc.find_bundle_id(client, bundle)
        ensure_associated_domains(client, bundle_ref)
        certificate = asc.find_certificate(client, old)
        data = asc.fresh_profile(client, bundle_ref, certificate, PROFILE_NAME)
        check(asc.decode_profile(data), old, team, bundle)
    except asc.Refused as reason:
        print(f"::warning::No universal links in this build: {reason}")
        return 0
    except Exception as error:  # never cost the upload
        print(f"::warning::No universal links in this build: {error!r}")
        return 0
    path = temp / "app-links.mobileprovision"
    path.write_bytes(data)
    with open(env["GITHUB_ENV"], "a", encoding="utf-8") as out:
        out.write(f"PROVISION_PROFILE_PATH={path}\n")
        out.write(f"SR_APP_ENTITLEMENTS={ENTITLEMENTS_FILE}\n")
    print("The app's profile carries Associated Domains: universal links are on in this build.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

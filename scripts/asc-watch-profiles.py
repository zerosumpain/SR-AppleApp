#!/usr/bin/env python3
"""Fetch the Watch app's and its complications' App Store profiles from Apple.

Run by the TestFlight job before `install-signing.sh`, so the owner does not
have to make two provisioning profiles by hand, convert them to base64 and
paste them into GitHub secrets. It uses the App Store Connect API key the job
already has for uploading.

What it needs from a person first (docs/WATCH-SETUP.md, Part A): the App Group
and the two App IDs, with the group attached to both. The API can register an
App ID but cannot attach an App Group to one, so that part stays by hand.

It never fails the job. Anything missing or refused is a `::warning::` saying
exactly what, and the job uploads the iPhone app alone, as it did before the
Watch app existed. Profiles set as secrets (WATCH_/WIDGET_PROVISION_PROFILE_BASE64)
win: when both are present this does nothing.

On success it writes two profiles to $RUNNER_TEMP and puts their paths in
$GITHUB_ENV as WATCH_PROFILE_PATH and WIDGET_PROFILE_PATH.

Standard library only, plus `openssl` (to sign the API token) and `security`
(to read a profile), both already on the macOS runner.
"""
from __future__ import annotations

import base64
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com/v1"
# Profiles this script owns, by name, so it can replace its own and never
# touches one somebody made by hand.
NAME_PREFIX = "SR CI "


class Refused(Exception):
    """A reason to fall back to the iPhone-only upload, worded for the owner."""


# MARK: - The API token


def der_to_raw(der: bytes, size: int = 32) -> bytes:
    """An ECDSA signature from openssl (DER: SEQUENCE { INTEGER r, INTEGER s })
    as JWS wants it: r and s, each left-padded to `size` bytes, end to end."""
    if der[0] != 0x30:
        raise ValueError("not a DER sequence")
    index = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        if der[index] != 0x02:
            raise ValueError("not a DER integer")
        length = der[index + 1]
        value = der[index + 2 : index + 2 + length]
        index += 2 + length
        value = value.lstrip(b"\x00")
        if len(value) > size:
            raise ValueError("integer too long")
        parts.append(value.rjust(size, b"\x00"))
    return parts[0] + parts[1]


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token(key_id: str, issuer: str, private_key_pem: str, now: int | None = None) -> str:
    now = int(time.time()) if now is None else now
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    claims = {"iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = b64url(json.dumps(header).encode()) + "." + b64url(json.dumps(claims).encode())
    with tempfile.NamedTemporaryFile("w", suffix=".p8", delete=False) as handle:
        handle.write(private_key_pem)
        key_path = handle.name
    try:
        os.chmod(key_path, 0o600)
        der = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key_path],
            input=signing_input.encode(), capture_output=True, check=True,
        ).stdout
    finally:
        os.unlink(key_path)
    return signing_input + "." + b64url(der_to_raw(der))


# MARK: - Calls


class Client:
    def __init__(self, bearer: str):
        self.bearer = bearer

    def call(self, method: str, path: str, body: dict | None = None, query: dict | None = None):
        url = API + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", "Bearer " + self.bearer)
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:400]
            if error.code in (401, 403):
                raise Refused(
                    f"App Store Connect refused the API key ({error.code}) for {method} {path}. "
                    "The key needs the Admin role (or App Manager with access to Certificates, "
                    "Identifiers & Profiles): App Store Connect → Users and Access → Integrations. "
                    f"Apple said: {detail}"
                ) from None
            raise Refused(f"App Store Connect answered {error.code} for {method} {path}: {detail}") from None


# MARK: - Profiles


def decode_profile(data: bytes) -> dict:
    """A .mobileprovision is CMS-signed; `security cms -D` gives the plist."""
    with tempfile.NamedTemporaryFile(suffix=".mobileprovision", delete=False) as handle:
        handle.write(data)
        path = handle.name
    try:
        out = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True, check=True).stdout
    finally:
        os.unlink(path)
    return plistlib.loads(out)


def find_bundle_id(client: Client, identifier: str, register: bool = False) -> str:
    # `filter[identifier]` matches by prefix, so the exact one is picked out.
    reply = client.call("GET", "/bundleIds", query={"filter[identifier]": identifier, "limit": "200"})
    for item in reply.get("data", []):
        if item["attributes"].get("identifier") == identifier:
            return item["id"]
    if register:
        # An App ID with no capabilities (the Live Activity extension needs
        # none), which the API can make on its own — no App Group to attach.
        created = client.call("POST", "/bundleIds", body={
            "data": {
                "type": "bundleIds",
                "attributes": {"identifier": identifier, "name": "SR " + identifier.split(".")[-1], "platform": "IOS"},
            }
        })
        print(f"Registered the App ID {identifier}.")
        return created["data"]["id"]
    raise Refused(
        f"There is no App ID {identifier} on the developer account yet. "
        "Do Part A of docs/WATCH-SETUP.md (the App Group and the two App IDs), then run this again."
    )


def find_certificate(client: Client, app_profile: dict) -> str:
    """The Apple Distribution certificate the iPhone app's profile is signed
    for, which is the one in DISTRIBUTION_P12_BASE64. Matched by its bytes."""
    wanted = {bytes(cert) for cert in app_profile.get("DeveloperCertificates", [])}
    reply = client.call("GET", "/certificates", query={"limit": "200"})
    for item in reply.get("data", []):
        content = item["attributes"].get("certificateContent")
        if content and base64.b64decode(content) in wanted:
            return item["id"]
    raise Refused(
        "Could not find the iPhone app's distribution certificate through the API. "
        "Make the two profiles by hand instead (docs/WATCH-SETUP.md, the manual route)."
    )


def check(profile: dict, team: str, identifier: str, group: str | None, healthkit: bool) -> None:
    entitlements = profile.get("Entitlements", {})
    if entitlements.get("application-identifier") != f"{team}.{identifier}":
        raise Refused(f"Apple made a profile for {entitlements.get('application-identifier')}, not {team}.{identifier}.")
    if group and group not in entitlements.get("com.apple.security.application-groups", []):
        raise Refused(
            f"The App ID {identifier} does not have the App Group {group} attached. "
            "In the developer account open that App ID, Configure App Groups, tick the group and Save "
            "(docs/WATCH-SETUP.md, Part A)."
        )
    if healthkit and not entitlements.get("com.apple.developer.healthkit"):
        raise Refused(f"The App ID {identifier} does not have HealthKit ticked (docs/WATCH-SETUP.md, Part A).")


def fresh_profile(client: Client, bundle_ref: str, certificate: str, name: str) -> bytes:
    """Replace this script's own profile for the App ID with a new one.

    New every run rather than reused: a profile only carries the capabilities
    its App ID had when it was made, so an old one would keep saying "no App
    Group" after the owner fixed it.
    """
    existing = client.call("GET", "/profiles", query={"filter[name]": name, "limit": "200"})
    for item in existing.get("data", []):
        if item["attributes"].get("name") == name:
            client.call("DELETE", f"/profiles/{item['id']}")
    created = client.call("POST", "/profiles", body={
        "data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_ref}},
                "certificates": {"data": [{"type": "certificates", "id": certificate}]},
            },
        }
    })
    return base64.b64decode(created["data"]["attributes"]["profileContent"])


def main() -> int:
    env = os.environ
    if env.get("WATCH_PROVISION_PROFILE_BASE64") and env.get("WIDGET_PROVISION_PROFILE_BASE64"):
        print("Watch profiles are set as secrets; not asking Apple for them.")
        return 0

    team, bundle = env["APPLE_TEAM_ID"], env["BUNDLE_ID"]
    group = "group." + bundle
    # key, App ID, HealthKit, needs the App Group, may be registered here.
    targets = [
        ("watch", bundle + ".watchkitapp", True, True, False),
        ("widget", bundle + ".watchkitapp.complications", False, True, False),
        # The iPhone's Live Activity extension (the family journey).
        ("live", bundle + ".live", False, False, True),
    ]
    temp = Path(env["RUNNER_TEMP"])
    try:
        client = Client(token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_PRIVATE_KEY"]))
        app_profile = decode_profile(base64.b64decode(env["PROVISION_PROFILE_BASE64"]))
        certificate = find_certificate(client, app_profile)
        written = {}
        for key, identifier, healthkit, grouped, register in targets:
            bundle_ref = find_bundle_id(client, identifier, register)
            data = fresh_profile(client, bundle_ref, certificate, NAME_PREFIX + identifier)
            check(decode_profile(data), team, identifier, group if grouped else None, healthkit)
            path = temp / f"{key}-api.mobileprovision"
            path.write_bytes(data)
            written[key] = path
            print(f"Got an App Store profile for {identifier} from Apple.")
    except Refused as reason:
        print(f"::warning::Watch app skipped: {reason} This upload is the iPhone app alone.")
        return 0
    except Exception as error:  # a surprise must not cost the iPhone upload
        print(f"::warning::Watch app skipped: could not get its profiles from Apple ({error!r}). "
              "This upload is the iPhone app alone.")
        return 0

    with open(env["GITHUB_ENV"], "a") as out:
        out.write(f"WATCH_PROFILE_PATH={written['watch']}\n")
        out.write(f"WIDGET_PROFILE_PATH={written['widget']}\n")
        out.write(f"LIVE_PROFILE_PATH={written['live']}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

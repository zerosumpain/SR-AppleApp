#!/bin/bash
set -euo pipefail
umask 077
printf '%s' "$DISTRIBUTION_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/certificate.p12"
printf '%s' "$PROVISION_PROFILE_BASE64" | base64 --decode > "$RUNNER_TEMP/profile.mobileprovision"
printf '%s' "$ASC_PRIVATE_KEY" > "$RUNNER_TEMP/AuthKey.p8"
SIGNING_PASSWORD=$(openssl rand -hex 32)
echo "::add-mask::$SIGNING_PASSWORD"
security create-keychain -p "$SIGNING_PASSWORD" "$RUNNER_TEMP/signing.keychain-db"
security set-keychain-settings -lut 21600 "$RUNNER_TEMP/signing.keychain-db"
security unlock-keychain -p "$SIGNING_PASSWORD" "$RUNNER_TEMP/signing.keychain-db"
security import "$RUNNER_TEMP/certificate.p12" -P "$DISTRIBUTION_P12_PASSWORD" -A -t cert -f pkcs12 -k "$RUNNER_TEMP/signing.keychain-db"
security set-key-partition-list -S apple-tool:,apple: -k "$SIGNING_PASSWORD" "$RUNNER_TEMP/signing.keychain-db" >/dev/null
security list-keychains -d user -s "$RUNNER_TEMP/signing.keychain-db"
security cms -D -i "$RUNNER_TEMP/profile.mobileprovision" > "$RUNNER_TEMP/profile.plist"
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$RUNNER_TEMP/profile.plist")
echo "PROFILE_UUID=$PROFILE_UUID" >> "$GITHUB_ENV"
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$RUNNER_TEMP/profile.mobileprovision" "$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"
python3 - <<'PY'
import os, plistlib
from pathlib import Path
profile = plistlib.loads(Path(os.environ['RUNNER_TEMP'], 'profile.plist').read_bytes())
assert profile['Entitlements'].get('com.apple.developer.healthkit'), 'Profile must enable HealthKit'
assert profile['Entitlements'].get('com.apple.developer.healthkit.background-delivery'), 'Profile must enable HealthKit background delivery'
assert profile['Entitlements']['application-identifier'] == os.environ['APPLE_TEAM_ID'] + '.' + os.environ['BUNDLE_ID'], 'Profile does not match team/bundle ID'
options = {'method': 'app-store-connect', 'destination': 'upload', 'teamID': os.environ['APPLE_TEAM_ID'], 'signingStyle': 'manual', 'provisioningProfiles': {os.environ['BUNDLE_ID']: profile['UUID']}}
Path(os.environ['RUNNER_TEMP'], 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
PY

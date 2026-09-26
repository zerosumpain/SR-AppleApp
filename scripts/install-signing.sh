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
for PROFILE_DIR in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  mkdir -p "$PROFILE_DIR"
  cp "$RUNNER_TEMP/profile.mobileprovision" "$PROFILE_DIR/$PROFILE_UUID.mobileprovision"
done
# The Watch app and its complications, when both of their profiles are set.
# Either missing means an iPhone-only upload (testflight.yml), so neither is
# installed: half a Watch app would fail the archive.
install_extra_profile() {
  local name="$1" base64="$2"
  printf '%s' "$base64" | base64 --decode > "$RUNNER_TEMP/$name.mobileprovision"
  security cms -D -i "$RUNNER_TEMP/$name.mobileprovision" > "$RUNNER_TEMP/$name.plist"
  local uuid
  uuid=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$RUNNER_TEMP/$name.plist")
  for PROFILE_DIR in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
    cp "$RUNNER_TEMP/$name.mobileprovision" "$PROFILE_DIR/$uuid.mobileprovision"
  done
  printf '%s' "$uuid"
}
WATCH_UUID=""
WIDGET_UUID=""
if [ -n "${WATCH_PROVISION_PROFILE_BASE64:-}" ] && [ -n "${WIDGET_PROVISION_PROFILE_BASE64:-}" ]; then
  WATCH_UUID=$(install_extra_profile watch "$WATCH_PROVISION_PROFILE_BASE64")
  WIDGET_UUID=$(install_extra_profile widget "$WIDGET_PROVISION_PROFILE_BASE64")
  echo "WATCH_PROFILE_UUID=$WATCH_UUID" >> "$GITHUB_ENV"
  echo "WIDGET_PROFILE_UUID=$WIDGET_UUID" >> "$GITHUB_ENV"
fi
export WATCH_UUID WIDGET_UUID
python3 - <<'PY'
import os, plistlib
from pathlib import Path
temp = os.environ['RUNNER_TEMP']
team, bundle = os.environ['APPLE_TEAM_ID'], os.environ['BUNDLE_ID']
profile = plistlib.loads(Path(temp, 'profile.plist').read_bytes())
assert profile['Entitlements'].get('com.apple.developer.healthkit'), 'Profile must enable HealthKit'
assert profile['Entitlements'].get('com.apple.developer.healthkit.background-delivery'), 'Profile must enable HealthKit background delivery'
assert profile['Entitlements']['application-identifier'] == team + '.' + bundle, 'Profile does not match team/bundle ID'
profiles = {bundle: profile['UUID']}
if os.environ.get('WATCH_UUID'):
    group = 'group.' + bundle
    watch = plistlib.loads(Path(temp, 'watch.plist').read_bytes())
    widget = plistlib.loads(Path(temp, 'widget.plist').read_bytes())
    assert watch['Entitlements']['application-identifier'] == team + '.' + bundle + '.watchkitapp', 'Watch profile does not match <bundle>.watchkitapp'
    assert watch['Entitlements'].get('com.apple.developer.healthkit'), 'Watch profile must enable HealthKit'
    assert group in watch['Entitlements'].get('com.apple.security.application-groups', []), 'Watch profile must include the App Group ' + group
    assert widget['Entitlements']['application-identifier'] == team + '.' + bundle + '.watchkitapp.complications', 'Complications profile does not match <bundle>.watchkitapp.complications'
    assert group in widget['Entitlements'].get('com.apple.security.application-groups', []), 'Complications profile must include the App Group ' + group
    profiles[bundle + '.watchkitapp'] = os.environ['WATCH_UUID']
    profiles[bundle + '.watchkitapp.complications'] = os.environ['WIDGET_UUID']
options = {'method': 'app-store-connect', 'destination': 'upload', 'teamID': team, 'signingStyle': 'manual', 'provisioningProfiles': profiles}
Path(temp, 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
PY

# Install on an iPhone without owning a Mac

The repository contains two distinct workflows:

1. **Check app and API:** automatic Linux API tests and hosted-Mac iPhone simulator build/XCTest. No Apple signing secrets needed. Both workflows use the macOS 26 runner and check for the iOS 26 SDK or newer before building.
2. **Upload to TestFlight:** manually run after configuring signing. Archives, signs and uploads to App Store Connect. Apple processing and beta review are separate from upload success.

## Apple account setup

Use your Apple Developer account in a browser:

1. Enrol in the paid Apple Developer Program if needed.
2. Register an explicit App ID. Suggested bundle ID: `com.strangeramblings.appleapp` (choose another if unavailable). Enable **HealthKit**, including background delivery in the provisioning entitlements.
3. Create the iOS app record in App Store Connect with that same bundle ID.
4. Create an **Apple Distribution** certificate and an App Store distribution provisioning profile for this App ID. Export the certificate and matching private key as password-protected PKCS#12 (`.p12`). If working entirely on Linux, generate a CSR/private key with OpenSSL, upload only the CSR to Apple, download the certificate and package it with the private key. Keep all private files outside Git.
5. Create an App Store Connect API key with permission to upload builds for this app. Save its private `.p8` key securely; Apple offers the download only once.

Use GitHub repository Settings → Environments → create **testflight**. Add environment variables:

- `APPLE_TEAM_ID`: your Apple team ID.
- `APPLE_BUNDLE_ID`: the registered bundle ID.

Add these environment secrets:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_PRIVATE_KEY`: full `.p8` file contents, including actual newlines.
- `DISTRIBUTION_P12_BASE64`: base64-encoded `.p12` file.
- `DISTRIBUTION_P12_PASSWORD`
- `PROVISION_PROFILE_BASE64`: base64-encoded App Store profile.

The workflow checks these settings before building. Temporary signing files and the runner keychain are removed after the run. Use a monotonically increasing build number if previous uploads predate this workflow's run counter. TestFlight's workflow run number supplies the default.

## Server for the first real-device test

The native app accepts **HTTPS origins only** and rejects redirects. Do not disable App Transport Security or send real health data to the HTTP demo preview.

Prepare a private staging deployment using `deploy/compose.yaml`, a fresh persistent volume, trusted TLS, real per-person accounts and the family assignments. A LAN-only TLS server can be used if its certificate is trusted by the iPhone; otherwise use an authenticated HTTPS staging hostname. This is an infrastructure step, not something TestFlight sets up.

The existing local preview is for browser tests with synthetic records. It cannot be pasted into the production-configured iPhone app because it is plain HTTP.

## Distribute and connect

1. Run **Upload to TestFlight** from GitHub Actions once the simulator check passes.
2. Wait for App Store Connect to finish processing. Complete export-compliance and beta information as requested.
3. Invite family as **external testers** (do not give them App Store Connect administrator access). Apple may require beta review before the build is available.
4. Install TestFlight and the app on your iPhone.
5. Sign in to the HTTPS companion website as yourself. Open Connect & privacy → Create pairing code.
6. In SR Companion, enter the server origin and that code. Select your health categories, review HealthKit permissions, enable location sharing and then Always location permission.
7. Follow the physical-device checklist. Repeat with a second account to verify privacy.

TestFlight builds expire after 90 days. A sustainable family rollout needs refreshed beta builds or an appropriate App Store distribution route. An uploaded simulator artifact cannot be sideloaded as a signed phone app.

References: [Apple SDK upload requirements](https://developer.apple.com/news/upcoming-requirements/?id=04282026a), [Apple Developer membership](https://developer.apple.com/programs/enroll/), [TestFlight](https://developer.apple.com/testflight/), [external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).

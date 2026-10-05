# Shiplog TestFlight setup

Confirmed by the owner on October 5, 2026:

- Developer team: `2NHJGX6A7S` — ANDREW DOUGLAS SEPECZI
- App bundle identifier: `com.drewsepeczi.shiplog`
- Initial version: `1.0.0`, build `1`
- iPhone only, iOS 18 or later
- Automatic signing; no extra capabilities required for the local journal

Verified on October 5, 2026:

- App ID registered under team `2NHJGX6A7S` for `com.drewsepeczi.shiplog`.
- App Store Connect record created as **Shiplog: Build Journal**, Apple ID `6819344413`, SKU `shiplog-ios`, English (U.S.). The plain Shiplog store name was unavailable; the owner selected this listing name. The installed app name remains Shiplog.
- Build 1 archived successfully without development signing, then exported with Apple's cloud-managed distribution certificate and an App Store provisioning profile. The exported app signature passed `codesign --verify --deep --strict`; distribution entitlements identify the confirmed team and bundle ID and disable `get-task-allow`.
- Initial artifacts: `.build/releases/Shiplog-1-unsigned.xcarchive` and `.build/releases/export-1/Shiplog.ipa`.
- Upload completed successfully through `xcodebuild -exportArchive` with explicit `destination=upload`; Xcode reported the uploaded package was processing.
- Created **Shiplog Internal**, group ID `5b25db42-c245-481e-8891-56cbe841c92d`, with the owner's existing Account Holder/Admin account as its one internal tester. Automatic distribution is enabled. Before Apple processing completed, the group showed zero builds and `No Builds Available`.

- After the collaborative browser reconnected, Apple processing was verified complete: version `1.0.0`, build `1` appears in iOS Builds and is assigned to Shiplog Internal. The group shows **1 Tester · 1 Build**, and the owner tester status is **Invited**, dated October 5, 2026. The build list shows one invitation and no installs yet.

### Build 2 update

Version `1.0.0 (2)` was archived, distribution-signed, uploaded, processed, and assigned to Shiplog Internal on October 5. App Store Connect showed the build ready with its internal group assigned. The build embeds `https://shiplog-agent.vercel.app` as its public agent URL; that alias remains active. Connection starts now direct the browser to `https://shiplog.fun`, and future native builds default to the new domain. No new build is required for the server-side connection and evidence-validation fixes.

Artifacts: `.build/releases/Shiplog-2.xcarchive` and `.build/releases/export-2/Shiplog.ipa`. Xcode reported upload success. The owner reported reaching repository selection on the physical iPhone in Build 2 and supplied the connection error; after the server-side fixes, the owner confirmed that the generated journal appears in Today.

TestFlight delivery, owner-reported Build 2 installation, and the first live GitHub-to-Today journal journey are verified. [Open the internal group](https://appstoreconnect.apple.com/teams/02799f60-e415-461a-8c86-a1dcf271737a/apps/6819344413/testflight/groups/5b25db42-c245-481e-8891-56cbe841c92d).

These settings live in `project.yml` and the generated Xcode project. Regeneration preserves the selected identity. The local macOS Developer ID certificate is not an iOS signing certificate. Xcode needs the enrolled Apple account or supported App Store Connect API authentication to create the iOS signing assets.

## First-time Apple account setup

1. Add the enrolled account in Xcode Settings → Apple Accounts/Accounts. Select the team above. Complete any sign-in or two-factor prompts yourself.
2. Open Shiplog's target → Signing & Capabilities. Confirm automatic signing, the team and bundle ID. If Xcode reports missing iOS components, install the compatible iOS platform/runtime through Settings → Components.
3. Register an explicit App ID for `com.drewsepeczi.shiplog` if Xcode has not already registered it through automatic signing.
4. In App Store Connect → Apps → + → New App, create an iOS record with this exact bundle ID. Use English as the initial language and `shiplog-ios` as the SKU. Use Shiplog as the name if available; a name conflict requires choosing an available store name. Accept required account agreements yourself.

The identities above were verified live during this first setup. Check the same record and team when preparing later uploads.

## Create an archive and signed IPA

With the account configured and a compatible iOS runtime installed:

```sh
SHIPLOG_BUILD_NUMBER=1 ./scripts/archive.sh
```

This runs strict Swift formatting checks, archives the Release scheme without development signing, then exports an App Store distribution-signed IPA using automatic provisioning. Distribution signing during export avoids requiring registered development devices. The script checks the bundle ID, signing team, build number, distribution entitlements and exported app signature. It does not upload or invite testers. Archives are kept in `.build/releases/Shiplog-<build>.xcarchive`, with the signed IPA in `.build/releases/export-<build>/Shiplog.ipa`. The script refuses to overwrite either path. Increment the build number for subsequent uploads. A failed attempt can leave incomplete artifacts; inspect them before removing or select a new build number.

`-allowProvisioningUpdates` permits Xcode to register/update identifiers, certificates and provisioning profiles under the configured team. The script uses Xcode's signed-in account; no password or API key is stored in the repository.

## Upload through Xcode

Use Xcode Organizer to open/select the archive, validate it, and choose Distribute App → the App Store Connect/TestFlight workflow. Keep version `1.0.0` and the chosen build number consistent. Normal App Store Connect upload allows later external testing and App Store submission. Choosing Internal Only limits that particular uploaded build to internal testing.

Alternatively, export a local App Store Connect IPA before uploading:

```sh
xcodebuild -exportArchive \
  -archivePath .build/releases/Shiplog-1.xcarchive \
  -exportOptionsPlist config/ExportOptions.plist \
  -exportPath .build/releases/export-1 \
  -allowProvisioningUpdates
```

The checked-in export configuration uses `destination=export`, so this command writes files locally. It does not upload. The archive script already performs this export; this separate command is useful when an archive exists but no export has been produced. The selected team and automatic distribution signing are explicit; automatic build-number changes are disabled.

## Install on the iPhone

After Apple finishes processing the uploaded build:

1. Open Shiplog in App Store Connect → TestFlight.
2. Complete any export compliance or test information Apple requires.
3. Create an internal group, for example `Shiplog Internal`.
4. Add the build and the owner's eligible App Store Connect account.
5. Install Apple's TestFlight app on the iPhone and accept the invitation.

Internal testing does not release the app publicly. TestFlight builds expire after 90 days. External testing is a separate workflow and may require beta review. Upload success, processing success, group assignment, and successful installation on the phone are separate verification steps.

## Apple references

- [Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
- [App record creation](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)
- [App ID registration](https://developer.apple.com/help/account/identifiers/register-an-app-id/)
- [App distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Internal TestFlight testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)

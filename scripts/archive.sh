#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

SHIPLOG_RELEASE_BUILD="${SHIPLOG_BUILD_NUMBER:-1}"
if [[ ! "$SHIPLOG_RELEASE_BUILD" =~ '^[1-9][0-9]*$' ]]; then
  print -u2 'SHIPLOG_BUILD_NUMBER must be a positive integer.'
  exit 1
fi
SHIPLOG_ARCHIVE_PATH="$PWD/.build/releases/Shiplog-$SHIPLOG_RELEASE_BUILD.xcarchive"
SHIPLOG_EXPORT_PATH="$PWD/.build/releases/export-$SHIPLOG_RELEASE_BUILD"
if [[ -e "$SHIPLOG_ARCHIVE_PATH" || -e "$SHIPLOG_EXPORT_PATH" ]]; then
  print -u2 'Archive or export already exists for this build number.'
  print -u2 'Select a new build number to preserve the existing release artifacts.'
  exit 1
fi

SHIPLOG_AGENT_BUILD_SETTINGS=()
if [[ -n "${SHIPLOG_AGENT_URL:-}" ]]; then
  SHIPLOG_AGENT_BUILD_SETTINGS+=("SHIPLOG_AGENT_URL=$SHIPLOG_AGENT_URL")
fi

xcrun swift-format lint --strict --recursive Shiplog ShiplogTests ShiplogUITests
xcodebuild -project Shiplog.xcodeproj -scheme Shiplog -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build/ReleaseDerivedData \
  -archivePath "$SHIPLOG_ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CURRENT_PROJECT_VERSION="$SHIPLOG_RELEASE_BUILD" "${SHIPLOG_AGENT_BUILD_SETTINGS[@]}" archive

SHIPLOG_ARCHIVED_APP="$SHIPLOG_ARCHIVE_PATH/Products/Applications/Shiplog.app"
SHIPLOG_AGENT_VERIFY_ARGS=()
if [[ -n "${SHIPLOG_AGENT_URL:-}" ]]; then
  SHIPLOG_AGENT_VERIFY_ARGS+=(--expected-url "$SHIPLOG_AGENT_URL")
fi
python3 scripts/check-agent-config.py "$SHIPLOG_ARCHIVED_APP" \
  --build-number "$SHIPLOG_RELEASE_BUILD" "${SHIPLOG_AGENT_VERIFY_ARGS[@]}"
SHIPLOG_ARCHIVED_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SHIPLOG_ARCHIVED_APP/Info.plist")
if [[ "$SHIPLOG_ARCHIVED_ID" != 'com.drewsepeczi.shiplog' ]]; then
  print -u2 "Unexpected archived bundle ID: $SHIPLOG_ARCHIVED_ID"
  exit 1
fi
# Distribution signing happens during export. This avoids requiring a registered
# development device just to prepare a TestFlight build.
xcodebuild -exportArchive -archivePath "$SHIPLOG_ARCHIVE_PATH" \
  -exportOptionsPlist config/ExportOptions.plist \
  -exportPath "$SHIPLOG_EXPORT_PATH" -allowProvisioningUpdates

SHIPLOG_VERIFICATION_PATH="$SHIPLOG_EXPORT_PATH/verified"
ditto -x -k "$SHIPLOG_EXPORT_PATH/Shiplog.ipa" "$SHIPLOG_VERIFICATION_PATH"
SHIPLOG_SIGNED_APP="$SHIPLOG_VERIFICATION_PATH/Payload/Shiplog.app"
codesign --verify --deep --strict "$SHIPLOG_SIGNED_APP"
python3 - "$SHIPLOG_EXPORT_PATH/DistributionSummary.plist" "$SHIPLOG_RELEASE_BUILD" <<'PY'
import plistlib
import sys

with open(sys.argv[1], 'rb') as file:
    entry = plistlib.load(file)['Shiplog.ipa'][0]
assert entry['team']['id'] == '2NHJGX6A7S', 'Unexpected signing team'
assert entry['buildNumber'] == sys.argv[2], 'Unexpected build number'
assert entry['entitlements']['application-identifier'] == '2NHJGX6A7S.com.drewsepeczi.shiplog'
assert entry['entitlements'].get('get-task-allow') is False, 'Development signature in distribution export'
PY
print "Verified distribution IPA ready: $SHIPLOG_EXPORT_PATH/Shiplog.ipa"
print 'Export is local. Upload separately through Xcode Organizer or an explicit upload export.'

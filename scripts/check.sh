#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcrun swift-format lint --strict --recursive Shiplog ShiplogTests ShiplogUITests
xcodebuild -project Shiplog.xcodeproj -scheme Shiplog \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
if [[ -n "${SHIPLOG_SIMULATOR_ID:-}" ]]; then
  xcodebuild -project Shiplog.xcodeproj -scheme Shiplog \
    -destination "platform=iOS Simulator,id=$SHIPLOG_SIMULATOR_ID" \
    -derivedDataPath .build/DerivedData -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO test
else
  print 'Build and lint complete. Set SHIPLOG_SIMULATOR_ID to run domain, persistence, and UI tests.'
fi

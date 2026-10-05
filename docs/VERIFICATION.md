# Verification — October 5, 2026

## Passed

- **17 XCTest tests on macOS**, using the actual app domain, validation, SwiftData schema, storage operations and exporter via `Package.swift`. Ten domain cases and seven persistence cases passed. Evidence: [core-tests.txt](evidence/core-tests.txt).
- **Complete Release iPhone source type check**, targeting arm64 iOS 18 against the installed iPhoneOS SDK, with Swift 6 and complete strict concurrency. Exit 0, no diagnostics.
- **Complete Debug iPhone source type check**, including preview fixtures, preview macros, isolated launch hooks and all SwiftUI views. Exit 0, no diagnostics.
- **Native UI-test source type check**, against the simulator SDK plus Apple's XCTest Swift overlay. Exit 0. This verifies compilation, not execution or locator correctness.
- **Strict swift-format lint** across app, unit-test and UI-test sources, no findings.
- Privacy manifest plist validation, asset JSON parsing, original app icon dimensions (1024 × 1024) and opaque RGB format.
- XcodeGen regeneration of the checked-in project, including an iPhone-only application target.
- **Complete unsigned iPhone Release build**, including asset compilation, linking, dSYM generation and app-bundle validation. `xcodebuild` reported `BUILD SUCCEEDED` after installing the official iOS 26.5 runtime. This is packaging proof, not signing or delivery proof.
- Release bundle inspection confirmed `com.drewsepeczi.shiplog`, version `1.0.0` / build `1`, iPhone-only support, iOS 18 minimum, encryption declaration and bundled privacy manifest. Neither Debug launch flag (`--preview-data`, `--ui-testing`) occurs in the Release executable.
- **Archive and distribution export succeeded** for build 1. The archive was unsigned; Xcode export then signed the IPA with a cloud-managed Apple Distribution certificate and an App Store provisioning profile. The exported signature passed strict verification, with `get-task-allow=false` and the confirmed `2NHJGX6A7S` application identifier. Development-profile archiving initially failed because the team has zero registered iOS devices; distribution export resolved this without device registration.
- **App Store Connect upload succeeded**, version `1.0.0` / build `1`, app Apple ID `6819344413`. Xcode reported the package was processing; the later browser check below confirmed completion.
- **TestFlight processing and internal delivery setup verified**: build `1.0.0 (1)` is processed and assigned to Shiplog Internal. The group shows one tester and one build, with the owner status `Invited`. No phone installation or test session is claimed.

## Environment gates

The environment initially reported a booted iPhone 17 Pro Max, then Xcode could not resolve that destination. A concurrent external process changed simulator runtimes. `simctl list runtimes` subsequently returned no installed runtimes, and booting a separate iPhone failed because its runtime bundle was unavailable.

The simulator build failed in `actool` with:

```
No available simulator runtimes for platform iphonesimulator.
SimServiceContext supportedRuntimes=[]
```

A scheme-based device build initially rejected destination discovery (`iOS 26.5 is not installed`). A target-based, SDK-only Release build initially hit the same asset compiler runtime gate. Installing Apple's official iOS 26.5 runtime and refreshing the current user's idle CoreSimulator service resolved asset compilation, and the unsigned Release build subsequently passed. The runtime was removed again before the signed archive attempt; the task is restoring it. No simulator runtime was deleted by this task.

**Not verified:** successful native UI-test execution, app screenshots, SwiftUI Canvas rendering, visual finish in light/dark appearance, VoiceOver, extreme Dynamic Type, installation on a physical device or public App Store delivery. Those remain required before public release. Debug and Release source checks are separate from these claims. The simulator app and test bundles built successfully; the first test run stalled on the new simulator's CoreLocation data migration during OS startup. The dedicated simulator was restarted without erasing its data for a second attempt. Both attempts were stopped after startup/launch stalled; no native UI-test pass is claimed. The first attempt reported `NSMachErrorDomain -308 (ipc/mig) server died` while the dedicated simulator was shutting down. The 17 shared domain/persistence tests passed separately on macOS.

## Reproduce

```sh
swift test --scratch-path .build/core -j 2
xcrun swift-format lint --strict --recursive Shiplog ShiplogTests ShiplogUITests
python3 scripts/typecheck.py
```

After an iOS runtime is available in Xcode Settings → Components:

```sh
xcrun simctl list devices available
SHIPLOG_SIMULATOR_ID=<available-iphone-udid> ./scripts/check.sh
```

UI tests retain screenshots as XCTest attachments when executed. Review [RELEASE.md](RELEASE.md) for the remaining on-device and distribution checks.

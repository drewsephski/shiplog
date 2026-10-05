# Verification — October 5, 2026

## Blog-style journal and refresh verification (October 5, 2026)

- Loaded journals now refresh quietly with a five-minute cooldown; pending generation polls every 30 seconds. Scene activation has one cancellable refresh task, and failed attempts also receive a cooldown. Day/time-zone changes refresh immediately.
- Today and individual History days share a full article: opening daily story, chronological work sections, complete paragraphs, source navigation, and editing. Generated text remains labeled as an AI draft; user edits remain protected.
- Prompt version `journal-synthesis-5` groups related evidence into blog sections. Its provider schema requires every unprotected source to be assigned exactly once; invalid drafts receive one revision and are never published without validation. The public Swift journal contract is unchanged. Real model trials covered all 12 current sources in four sections; production writing is configured as `openai/gpt-4.1`.
- **37 backend tests passed**, including ten isolated PostgreSQL integration tests, plus lint and strict TypeScript. **27 native tests and five UI journeys passed** on iOS 26.5, including full paragraphs and source navigation in Today/History. Swift formatting and strict type checks passed. Result bundle: `.build/DerivedData/Logs/Test/Test-Shiplog-2026.10.05_14-26-06--0500.xcresult`.
- Production deployment `f64a4ce` reached READY on both `shiplog.fun` and the Build 2 alias. A real authenticated generation job completed with prompt version `journal-synthesis-5`: four two-paragraph sections covering all 14 attributed sources, with no missing evidence. The actual server payload decoded and merged twice through the production Swift DTOs and in-memory SwiftData store: four entries and one narrative, without duplicates. This proves the contract and coverage, not calibrated factual accuracy.
- Today and History article screenshots from the successful UI run were visually reviewed. Paragraphs remain untruncated, work headings are readable, and source/edit navigation is reachable. Extreme Dynamic Type and physical Build 3 acceptance remain open.
- Build **1.0.0 (3)** was signed, exported, and uploaded to App Store Connect with `https://shiplog.fun` as its public agent URL. App Store Connect confirms the processed build is assigned to Shiplog Internal, with one tester. The new build's physical-device acceptance remains a separate check.


## Live setup and connection fixes

- Production deployment is live at `https://shiplog.fun` on Vercel project `shiplog-agent`. The Vercel-registered domain is attached, verified, and serves HTTPS with a valid certificate. `https://shiplog-agent.vercel.app` remains an active alias for TestFlight build 2; it is not redirected away from API requests.
- GitHub App **Shiplog Journal**, app ID `5201267`, is installed with read-only Contents, Pull requests, Issues, and Metadata access. Installation access was verified to contain only `drewsephski/shiplog`. GitHub user authorization, repository selection, expiring refresh tokens, and the configured Neon database were exercised live. Callback, installation setup, homepage, and signed webhook URLs now use `shiplog.fun`.
- Server credentials were provisioned without placing secrets in the native app or tracked files. The dedicated OpenRouter key and configured `openai/gpt-4.1-mini` model were exercised with real attributed evidence. A live production jobs request completed generation and persisted the October 5 journal with a narrative and six entries. The owner subsequently confirmed the generated journal appears in Today on the physical iPhone. Exact first-day latency and factual review remain separate acceptance checks.
- The physical-device test reported that submitting repository consent failed to return to Shiplog, followed by a `consent_required` error on retry. The browser policy now permits the `shiplog:` callback after form submission, CSRF tokens remain stable across reloads within one flow, and browser failures show recovery instructions. The provenance validator rejected raw commit SHAs from the model; its strict output schema now constrains citations to canonical evidence IDs and excludes protected evidence from generated entries. The corrected live model response passed validation before production generation.
- **35 backend tests passed**, including ten integration tests on isolated PostgreSQL, plus lint, strict TypeScript, and the production Next.js build. Production checks confirmed Build 2's API returns its pinned first-hop origin, followed by a browser redirect that establishes the secure OAuth cookie on `shiplog.fun`, and both domains serve HTML recovery pages with the native callback policy. The new native build configuration defaults to `shiplog.fun`.
- The domain migration initially exposed Build 2's strict same-host check on the sign-in start URL. The server now preserves its pinned first hop on the Vercel alias and performs the canonical handoff inside the browser before setting the OAuth cookie. This retains the app's origin protection without requiring a native update. The live server journal was also decoded with the production Swift DTOs and merged twice through the actual in-memory SwiftData store: six entries and one narrative, without duplicates.
- The background workflow succeeded against `https://shiplog.fun/api/jobs`: [run 37360583642](https://github.com/drewsephski/shiplog/actions/runs/37360583642). Its completed queue returned `processed: 0`; the separate direct production job above returned `processed: 1` and persisted a generated journal.
- TestFlight **1.0.0 (2)** was signed, uploaded, processed, and assigned to **Shiplog Internal**. Its bundle configuration uses the active Vercel alias. The owner reported reaching the GitHub repository-selection flow on an iPhone. After the connection, schema, and domain compatibility fixes, the owner confirmed that Today displays the generated journal on the physical iPhone in Build 2.

**Remaining acceptance gates:** factual review of generated entries, live edit/regeneration preservation, provider revocation and end-to-end deletion, private-repository handling, exact first-day latency, VoiceOver/extreme Dynamic Type, and updated public App Store privacy responses. APNs is not implemented. Public App Store release has not been submitted.

## Autonomous vertical verification (earlier local pass)

- 23 native core tests passed on macOS and the iOS simulator, including an on-disk V1-to-V2 migration, exact provenance, idempotent merges, and preserved offline edits/deletions.
- Four native UI journeys passed on the dedicated Shiplog QA simulator (iOS 26.5): GitHub-first onboarding and missing-configuration recovery, manual build/project/reflection, project archive/restore/deletion, and Settings/export/connection disclosure. Screenshots were captured and the onboarding, Today, and GitHub screens reviewed. Result bundle: `.build/DerivedData/Logs/Test/Test-Shiplog-2026.10.05_12-42-23--0500.xcresult`.
- 27 backend tests passed, including ten integration cases against an isolated real PostgreSQL instance using the production Neon SQL. GitHub/model calls were controlled fixtures. Checks cover one-time PKCE exchange, ownership, incremental IDs/hash stability, protected edits/deletes, expired leases, access revocation, webhook replay/teammate filtering, disconnect, durable day jobs, phone-independent scheduling, paged history including PostgreSQL microsecond precision, and regeneration after edits.
- Strict Swift formatting, Release/Debug iPhone source checking, native UI-test source checking, backend lint/strict TypeScript, production Next.js build, and privacy/Info.plist validation passed. A Release simulator package verified that the configured public agent URL, `shiplog` callback scheme, and an overridden build number survive Info.plist processing; the archive script now checks this.
- V1 model declarations are unchanged from `3aeca56`; aliases and the migration plan now live with V2.
- The collaborative browser loaded the local backend page and confirmed unauthenticated journal requests return 401. Screenshot automation failed, so no web screenshot or live authentication acceptance is claimed.

This supersedes the original local snapshot's native UI-test execution gate below. It does not change the previously distributed build 1 or claim a new TestFlight delivery.

This earlier pass used fixture providers; the live setup above supersedes its provider and delivery gates. See [agent setup and acceptance](../backend/README.md).

## Original release snapshot — passed

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

## Branding follow-up

The folded S identity and shared logo primitives were added after TestFlight build 1. Both final iPhone Release and simulator Debug builds passed with the new assets. Swift 6 type checks and strict formatting lint passed. The final Debug app installed and launched on the dedicated Shiplog QA simulator with the isolated `--ui-testing` store, and onboarding branding was visually checked in light and dark appearance. See [brand verification](../brand/README.md) for exports and screenshots. This resolves simulator app-launch and onboarding visual proof for this build; full native UI-test execution, physical-device acceptance and a new branded TestFlight build remain unverified.

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

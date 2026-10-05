# Shiplog

The folded S identity is shared by the app icon, Today, onboarding and Settings. Source artwork, scalable logo exports and regeneration instructions live in [brand/README.md](brand/README.md).

A GitHub-first journal for the things you build. Swift 6, SwiftUI, SwiftData; iOS 18 or later. A Next.js/Neon agent imports attributed GitHub activity and writes evidence-backed AI drafts. Manual journaling remains available offline. No production sample data or analytics.

## Run

Open `Shiplog.xcodeproj`, select the **Shiplog** scheme and an iPhone simulator, and run. Signing is configured for the owner-confirmed team `2NHJGX6A7S` and bundle ID `com.drewsepeczi.shiplog`. Add the enrolled Apple account in Xcode to enable automatic iOS signing. See [TestFlight setup](docs/TESTFLIGHT.md) for the signed archive and installation workflow. The project is checked in; XcodeGen is only needed to regenerate it after changing `project.yml`:

```sh
xcodegen generate
```

New installations lead with **Connect GitHub**. Authorize the GitHub App, choose repositories, and consent to the bounded data transfer. Shiplog scans the current local day, matches/creates projects, and presents generated build entries and a daily story with exact evidence links and confidence. Manual entry is secondary. Edits and deletions survive later generation. Review server-written days in History, and project evolution in Projects; the existing Insights surface is preserved. Destructive actions require confirmation.

Settings manages GitHub repository selection, local evening generation time, disconnect/server deletion, privacy, and versioned JSON export. SwiftData is the local cache, not the agent scheduler. Manual entries stay local; edits to generated text synchronize through a persistent outbox. Export is a portable record, not a restore feature. There is no CloudKit synchronization.

See [agent setup and live acceptance](backend/README.md). The default `SHIPLOG_AGENT_URL` build setting is empty: configure a deployed HTTPS agent before testing a live connection. Missing configuration is explained in the app; it never produces fictional GitHub activity.

## Preview and sample data

`Shiplog/Preview/PreviewFixtures.swift` contains explicitly fictional examples for SwiftUI previews. Previews use separate in-memory containers. Add `--preview-data` to the **Debug** scheme's launch arguments to explore a sample journal on a simulator. A visible sample banner stays on screen. It never opens the production store; all changes are discarded when the process exits. Release builds compile out this path and the fixtures.

`--ui-testing` likewise selects an empty, in-memory test container and forces onboarding for each launch. It is a Debug-only test hook.

## Check

Formatting uses Apple's bundled `swift-format`:

```sh
xcrun swift-format format --in-place --recursive Shiplog ShiplogTests ShiplogUITests
./scripts/check.sh
SHIPLOG_SIMULATOR_ID=<available-iphone-udid> ./scripts/check.sh
```

Domain tests cover distinct shipping days, streak grace, DST, year/week boundaries, time zones, future entries, archived projects, stable timeline ordering, and input validation. Persistence tests cover CRUD, disk reopening, cascade deletion, reflection upsert/removal, V1-to-V2 disk migration, generation idempotence, exact provenance, protected edits/deletions, JSON export, and sample-store isolation. Native UI tests cover onboarding, the first project/build/reflection, navigation, repository validation, archive/restore/delete, export preparation, and connection disclosure.

The same domain and SwiftData persistence sources also form a small Swift package for simulator-independent macOS checks:

```sh
swift test --scratch-path .build/core -j 2
```

This checks actual models and domain code, not the SwiftUI interface. On macOS, the fixture-isolation test verifies separate in-memory stores; on iOS it verifies the Debug preview factory directly.

UI tests require a bootable simulator runtime and disable parallel execution. They retain screenshots in the result bundle. Native VoiceOver and device acceptance require manual verification.

## Structure

- `App`: store bootstrap, recoverable failure, onboarding state, independent tab navigation.
- `Domain`: value records, validation, timeline grouping and deterministic statistics.
- `Persistence`: frozen V1, migrated V2 cache schema, explicit save/rollback operations and offline outbox.
- `Services`: provider-neutral activity/summary contracts, secure agent transport and versioned JSON export.
- `Design`: semantic colors, typography, empty states and reusable entry rows.
- `Features`: focused SwiftUI screens and draft editors with local state.
- `Preview`: Debug-only, in-memory sample fixtures.
- `backend`: GitHub App authentication, normalized evidence, synthesis, durable jobs, Neon schema and tests.

See [architecture](docs/ARCHITECTURE.md), [release checklist](docs/RELEASE.md), and [verification](docs/VERIFICATION.md).

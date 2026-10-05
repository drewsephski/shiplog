# Shiplog

A native iPhone journal for the things you build. Swift 6, SwiftUI, SwiftData. iOS 18 or later. No third-party runtime dependencies, account requirement, network traffic, or production sample data.

## Run

Open `Shiplog.xcodeproj`, select the **Shiplog** scheme and an iPhone simulator, and run. Signing is configured for the owner-confirmed team `2NHJGX6A7S` and bundle ID `com.drewsepeczi.shiplog`. Add the enrolled Apple account in Xcode to enable automatic iOS signing. See [TestFlight setup](docs/TESTFLIGHT.md) for the signed archive and installation workflow. The project is checked in; XcodeGen is only needed to regenerate it after changing `project.yml`:

```sh
xcodegen generate
```

New installations start with a brief onboarding and an empty journal. Create a project, log a build, and write a daily reflection. Review days in History, a project's evolution in Projects, and calendar-aware shipping statistics in Insights. Entries and projects can be edited; projects can be archived/restored. Destructive actions require confirmation.

Settings explains the future GitHub connection, documents privacy, and exports the entire local journal as versioned JSON. Export is a portable record, not a restore feature. SwiftData storage is local with normal iOS backup behavior; there is no CloudKit synchronization.

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

Domain tests cover distinct shipping days, streak grace, DST, year/week boundaries, time zones, future entries, archived projects, stable timeline ordering, and input validation. Persistence tests cover CRUD, disk reopening, cascade deletion, reflection upsert/removal, JSON export, and sample-store isolation. Native UI tests cover onboarding, the first project/build/reflection, navigation, repository validation, archive/restore/delete, export preparation, and connection disclosure.

The same domain and SwiftData persistence sources also form a small Swift package for simulator-independent macOS checks:

```sh
swift test --scratch-path .build/core -j 2
```

This checks actual models and domain code, not the SwiftUI interface. On macOS, the fixture-isolation test verifies separate in-memory stores; on iOS it verifies the Debug preview factory directly.

UI tests require a bootable simulator runtime and disable parallel execution. They retain screenshots in the result bundle. Native VoiceOver and device acceptance require manual verification.

## Structure

- `App`: store bootstrap, recoverable failure, onboarding state, independent tab navigation.
- `Domain`: value records, validation, timeline grouping and deterministic statistics.
- `Persistence`: frozen version 1 SwiftData schema, migration plan, explicit save/rollback operations.
- `Services`: provider-neutral activity and summary contracts, versioned JSON export.
- `Design`: semantic colors, typography, empty states and reusable entry rows.
- `Features`: focused SwiftUI screens and draft editors with local state.
- `Preview`: Debug-only, in-memory sample fixtures.

See [architecture](docs/ARCHITECTURE.md), [release checklist](docs/RELEASE.md), and [verification](docs/VERIFICATION.md).

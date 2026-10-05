# Architecture

## A narrative over evidence

A **Project** represents a repository or product. A **BuildEntry** describes meaningful work and belongs to a project. Entry kinds are feature, improvement, fix, release and learning; learning is included deliberately because building also involves discoveries. An entry carries an author origin and owns zero or more **SourceActivity** records. Commits and pull requests remain source evidence rather than becoming one entry each. User-authored entries contain no fabricated source data.

**JournalSummary** supports daily/weekly periods and manual/generated-draft origins, with input entry IDs for provenance. V1 only exposes handwritten daily reflections. Empty reflection text removes the reflection; it never creates output or affects statistics. Existing handwritten text must not be silently replaced by future generation.

The schema is versioned from the first build. `ShiplogSchemaV1` must remain frozen after release. Future model changes belong in a new schema and explicit migration stages. Deleting a project cascades its entries and their evidence; date reflections are independent and are retained. Archive preserves history and excludes the project from new-build selection and active-project statistics.

## State and persistence

One SwiftData container is injected at the app root. SwiftUI queries provide observation; screen-local `@State` owns editor drafts, sheets and search. There is no redundant view-model layer. Editors validate before mutating stored objects. All production mutations use explicit saves; a persistence failure rolls back the operation and displays recovery text without discarding the draft. Store boot failure never switches silently to an ephemeral store or erases the database.

SwiftData models stay on the main actor. Immutable, Sendable `EntryRecord` values cross future asynchronous service boundaries. Pure domain arithmetic accepts the clock and calendar explicitly, making DST and time-zone behavior testable. Day grouping and streaks use calendar days rather than 24-hour intervals. A current streak may end yesterday; it expires after an entire missed day. Multiple entries on one day count once. Future-dated entries are excluded. This-week counts follow the user's calendar week; active projects means unarchived projects with entries this week.

Reflections are keyed by a civil date. Entries are grouped by the user's current local calendar, so travel can change their day grouping. No background task, notification permission, credential, or network access is required. The Today clock updates on foreground and while visible; Insights periodically recalculates local week boundaries.

## Future GitHub connection

Implement an `ActivityProvider` adapter that owns GitHub transport/API models and OAuth/keychain credentials. The adapter exposes provider-neutral repository descriptors and cursor-paginated activity evidence. The UI should never decode GitHub payloads. Authentication, explicit repository selection, pagination, cancellation, rate limits, retries, revocation, account identity, and a persisted synchronization checkpoint are required before enabling import.

Normalize evidence identity from provider + repository + event type + provider ID. The database's unique `SourceActivity.identity` protects idempotence, but an importer must explicitly reconcile updates rather than relying on uniqueness as its entire conflict policy. Do not conflate a release event with proof of a live deployment. Stage candidates for review before generating or merging meaningful entries. Synchronize in an actor-owned repository and publish bounded immutable progress states; preserve local edits and provenance.

No placeholder adapter returns fictional remote activity. GitHub's current UI explicitly says no account is connected and nothing is imported.

## Future summaries

`SummaryService` accepts a complete selected-period snapshot and returns a `SummaryDraft` with exact input IDs. Deterministic saved data remains authoritative for totals. Before connecting a service, implement opt-in, credential protection, a privacy/data-transfer description, cancellation, failure recovery, input versioning and review/acceptance. Mark generated content as a draft; distinguish daily from weekly ranges and prevent stale drafts from overwriting current writing.

## Data and privacy

V1 makes no requests and includes no tracking SDKs. UserDefaults stores only onboarding completion (declared in the privacy manifest). Local SwiftData follows app sandbox/device protection and backup settings. JSON export contains all four model types and preserves relationships via stable IDs. Export is user-initiated through the system share sheet; it is not uploaded automatically. No import is exposed, and removing the app removes the journal unless retained in a device backup/export.

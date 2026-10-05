# Release readiness

The implementation is local-first. A successful simulator build is separate from signing, TestFlight delivery, App Review, and on-device acceptance.

Initial internal TestFlight distribution is configured: **1.0.0 (1)**, app ID `6819344413`, team `2NHJGX6A7S`, bundle ID `com.drewsepeczi.shiplog`. Shiplog Internal contains the processed build and the owner's invited account. See [TESTFLIGHT.md](TESTFLIGHT.md) and [VERIFICATION.md](VERIFICATION.md) for evidence boundaries.

Before public distribution:

- Reconfirm the selected team, bundle ID and existing App Store Connect record.
- Run the full native test suite and a Release build with the selected Xcode/runtime.
- Verify VoiceOver order and controls, all accessibility Dynamic Type sizes, increased contrast, light/dark appearance, keyboard navigation, small-screen reflow and long content on a real iPhone.
- Exercise cancellation/discard, past dates, midnight/week rollover, travel/time-zone changes, app relaunch, and archive/restore.
- Verify device persistence, backup behavior, export sharing to Files and failure recovery.
- Keep the current schema frozen once distributed; test migrations with archived stores when adding V2.
- Provide a hosted privacy policy, support contact, accurate App Store privacy responses, screenshots, age rating and localization review.
- Review the privacy manifest against actual required-reason APIs and any newly added dependencies.
- Confirm Release contains neither sample fixtures nor UI-test launch behavior.
- Archive, validate and sign through Xcode; upload to TestFlight and complete device acceptance.

GitHub/AI are intentionally unavailable. Do not enable their UI until authentication, data handling, synchronization and review behavior are implemented and verified.

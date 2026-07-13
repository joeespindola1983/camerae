# Project Structure

Camerae is now organized as a small monorepo:

```text
camerae/
  android/   Android implementation scaffold
  docs/      Shared product and engineering documentation
  ios/       Current iOS reference implementation
```

## iOS

The iOS app is the source of truth for the current product behavior. Major areas:

- Astrophotography timelapse capture and post-capture stacking.
- Repeatable capture projects.
- Reference-image overlay alignment.
- Motion, GPS, heading, grid, scale, and visual similarity HUDs.
- MP4 export for repeatable captures.

The 3.0 architecture separates the performance-sensitive layers into build targets:

- `CameraeCore`: versioned manifests, project/session catalogs and migration;
- `CameraeMedia`: thumbnail memory/disk pipeline and media services;
- `Camerae`: SwiftUI features, camera integration and composition root.

Swift Testing targets cover Core, Media and app-hosted component integration. XCTest has separate UI and performance schemes, and `processing/` uses CTest. Run the default suite with:

```sh
cd ios
xcodebuild -workspace Camerae.xcworkspace -scheme Camerae \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The architecture and implementation roadmap is documented in [`V3_PERFORMANCE_TDD_PLAN.md`](V3_PERFORMANCE_TDD_PLAN.md).

## Android

The Android app should follow the same user workflows, but not necessarily the same internal implementation. Camera and image-processing APIs differ enough that platform-native choices are preferred.

## Documentation

Use `docs/` for decisions that apply to both platforms, including product flows, data model notes, camera behavior, and alignment heuristics.

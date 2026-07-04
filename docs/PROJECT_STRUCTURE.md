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

## Android

The Android app should follow the same user workflows, but not necessarily the same internal implementation. Camera and image-processing APIs differ enough that platform-native choices are preferred.

## Documentation

Use `docs/` for decisions that apply to both platforms, including product flows, data model notes, camera behavior, and alignment heuristics.

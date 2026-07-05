# Camerae

Camerae is a camera app experiment focused on repeatable framing and astrophotography workflows.

## Repository Layout

- `ios/` - Current iOS application built with SwiftUI, AVFoundation, Vision, CoreMotion, and CoreLocation.
- `android/` - Android project scaffold for the future Camerae Android app.
- `processing/` - Local C++/OpenCV astrophotography processing lab and reusable algorithm core.
- `docs/` - Product, architecture, and implementation notes shared across platforms.

## Current Focus

The iOS app is the reference implementation. Android should follow the same product model, while using native platform APIs and libraries where appropriate.

## iOS Build

```sh
cd ios
xcodebuild \
  -project Camerae.xcodeproj \
  -scheme Camerae \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Processing Lab

```sh
brew install opencv pkg-config
cmake -S processing -B processing/build
cmake --build processing/build
```

Run local astro previews without deploying to a phone:

```sh
bash processing/scripts/compare_stacks.sh /path/to/frames milkyway
```

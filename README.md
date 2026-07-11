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
pod install
xcodebuild \
  -workspace Camerae.xcworkspace \
  -scheme Camerae \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The iOS target uses CocoaPods for Firebase and OpenCV, so CI and local command-line builds must build `Camerae.xcworkspace`, not `Camerae.xcodeproj`. ONNX Runtime/DeepSNR is temporarily disabled while CI/CD signing and distribution are stabilized.

## Release Flow

Camerae uses a lightweight GitFlow:

- `main` receives completed development work.
- `qa` receives stabilization builds for tester validation.
- `release/*` receives release candidates and future App Store Connect automation.
- Tags use `vMAJOR.MINOR.PATCH`, for example `v2.1.0`.

See `docs/GITFLOW.md` for branch, CI, and release details.

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

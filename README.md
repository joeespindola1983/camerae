# Camerae

Camerae is a camera app focused on repeatable framing, astrophotography, and assembling the resulting videos into a portfolio.

## Camerae 4

Version 4.0.0 introduces the Edit module. It discovers rendered Repeatable and Astro videos across the local library, filters them by source and type, lets the user build and preview an ordered sequence, and exports the result as a shareable 1080p MP4. Edit projects store references to source media instead of duplicating the original files.

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

The iOS target uses CocoaPods for Firebase Core and OpenCV, so CI and local command-line builds must build `Camerae.xcworkspace`, not `Camerae.xcodeproj`. ONNX Runtime/DeepSNR is temporarily disabled while CI/CD signing and distribution are stabilized.

## Release Flow

Camerae uses a lightweight GitFlow:

- `main` receives completed development work.
- `qa` receives stabilization builds for tester validation.
- `release/*` receives release candidates for local App Store Connect publication.
- Tags use `vMAJOR.MINOR.PATCH`, for example `v2.1.0`.

Releases run through the local macOS gate in `ios/scripts/release-gate.sh`; GitHub Actions workflows are manual-only.

Before a release, generate a browsable gallery of the principal SwiftUI screens with:

```bash
cd ios
./scripts/generate-ui-evidence.sh
```

Artifacts are written to `ios/build/ui-evidence/v<version>-<build>/`. During the release gate, the browsable PNG/HTML gallery is also archived under `docs/ui-evidence/v<version>-<build>/` and committed after publication, preserving the visual history without keeping IPA, ZIP, or Xcode build artifacts. The UI evidence flow uses deterministic empty projects and does not open the camera or run media processing.

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

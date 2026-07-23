# Camerae

Camerae is an iPhone and iPad camera app for repeatable framing, timelapse capture, astrophotography, image alignment, and local video creation.

[Website](https://www.camerae.app/) · [Changelog](CHANGELOG.md) · [GitFlow](docs/GITFLOW.md)

## Product

Camerae brings capture planning, visual alignment, and media processing into focused native workflows:

- **Repeatable** uses a reference image, camera and zoom locking, composition grids, overlays, and capture history to reproduce framing over time.
- **Astro** plans and captures night-sky sequences, then processes their frames through a reusable local image-processing pipeline.
- **Timelapse and video** keep capture orientation consistent, manage local sessions, generate MP4 output, preview media full screen, and share completed results.
- **Edit** discovers rendered Repeatable and Astro media, assembles an ordered sequence, previews it, and exports a shareable 1080p MP4 without duplicating source files.
- **Privacy-first storage** keeps projects, photos, videos, and processing inputs on the device unless the user explicitly exports or shares them.

The interface supports iPhone and iPad in Brazilian Portuguese, Spanish, English, French, German, and Russian. Capture supports portrait and landscape where the selected project requires it; the remaining application flow stays portrait-oriented.

## Current status

- Current production history: `v8.3.2`
- Primary platform: iOS and iPadOS
- UI: SwiftUI
- Capture: AVFoundation, CoreMotion, and CoreLocation
- Alignment: Vision and OpenCV
- Processing lab: C++ and OpenCV
- Android: planned from the shared product behavior after the iOS reference implementation stabilizes

## Repository

| Path | Purpose |
| --- | --- |
| `ios/` | Native iOS and iPadOS application, tests, release tooling, and screenshot automation |
| `processing/` | Reusable C++/OpenCV processing core and astrophotography laboratory |
| `android/` | Android project scaffold and portability notes |
| `docs/` | Product, architecture, release, visual evidence, and implementation documentation |

The public website is maintained separately in `camerae-frontend`.

## Build the iOS app

Requirements include a compatible Xcode installation, CocoaPods, and the local dependencies documented by the project.

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

Always build `Camerae.xcworkspace`. The standalone `.xcodeproj` does not include the CocoaPods dependencies used by Firebase and OpenCV.

## Test

Product changes follow TDD. The release gate runs localization and architecture checks, Swift tests, C++ processing tests, device builds, and visual evidence generation.

```sh
cd ios
scripts/release-gate.sh check
```

The processing laboratory can also be tested independently:

```sh
cmake -S processing -B processing/build -DBUILD_TESTING=ON
cmake --build processing/build
ctest --test-dir processing/build --output-on-failure
```

Generate a local astrophotography comparison without deploying to a device:

```sh
bash processing/scripts/compare_stacks.sh /path/to/frames milkyway
```

## Visual evidence

The screenshot workflow creates browsable iPhone and iPad galleries in every supported language:

```sh
cd ios
./scripts/generate-ui-evidence.sh --all-devices --all-locales --archive-tracked
```

Temporary output is written under `ios/build/ui-evidence/`. Release galleries are archived under `docs/ui-evidence/` so interface evolution can be reviewed without rebuilding old versions.

## Development and releases

Camerae currently uses a solo-developer GitFlow:

- All normal development begins on an up-to-date `develop`.
- Direct commits to `develop` are allowed; pull requests and short-lived branches are optional.
- `qa` is a deployment target for Firebase validation, never a development source.
- `release/vX.Y.Z` stabilizes one version.
- Every QA-approved candidate is reconciled into `develop`.
- `main` contains approved production releases and final `vX.Y.Z` tags.
- `CHANGELOG.md` is updated for every release candidate and finalized before its production tag.

After production approval, `main`, `develop`, and `qa` must all contain the tagged release before development of the next version begins. See [docs/GITFLOW.md](docs/GITFLOW.md) for the complete procedure.

## Release history

See [CHANGELOG.md](CHANGELOG.md) for dated release notes organized by version and product area.

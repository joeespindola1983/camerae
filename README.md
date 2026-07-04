# Camerae

Camerae is a camera app experiment focused on repeatable framing and astrophotography workflows.

## Repository Layout

- `ios/` - Current iOS application built with SwiftUI, AVFoundation, Vision, CoreMotion, and CoreLocation.
- `android/` - Android project scaffold for the future Camerae Android app.
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

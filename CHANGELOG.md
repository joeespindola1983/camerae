# Changelog

## v4.0.0

- Added Edit as a third project module for assembling a video portfolio from Camerae output.
- Added a global media catalog with Repeatable/Astro, video/timelapse, and project filters.
- Added thumbnails, ordered timelines, repeated clips, removal, reordering, and missing-media handling.
- Added sequential preview in horizontal and vertical canvases.
- Added cancellable 1080p/30 fps MP4 export with progress, validation, persistence, and sharing.
- Added Core, Media, integration, performance, and UI coverage following the project TDD workflow.

## v2.2.1-qa.1

- Fixed iOS archives to use the configured marketing version and build number in Firebase App Distribution.

## v2.2.0-qa.1

- Added a live elapsed-time display while recording Repeatable video clips.
- Refined Repeatable capture rows with readable titles, saved video duration, and a vertical-friendly layout.
- Added the ability to import a photo or video from the iOS Photo Library as the first Repeatable reference; videos provide a reference frame automatically.

## v2.1.0

- Added Firebase setup for `com.espindola.camerae` and a local Firebase App Distribution script.
- Added Repeatable alignment contour mode with RGB colors and fine/medium/thick line presets.
- Added reference blink mode with 2s, 5s, and 10s intervals plus 25%, 50%, and 100% opacity presets.
- Reorganized Repeatable alignment HUD controls into categories.
- Made Video the first/default Repeatable capture mode.
- Updated iOS CI to install CocoaPods and build `Camerae.xcworkspace`.
- Documented the Camerae GitFlow with `main`, `qa`, and `release/**` branches.

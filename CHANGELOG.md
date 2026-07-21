# Changelog

## v8.2.0-qa.1

- Completed the next-generation Repeatable project workspace with persistent Configuration and Captures sections, inline capture finalization, full-screen playback, sharing, and MP4 generation states.
- Added project reference-image management with placeholder, import and camera capture actions, stable thumbnails, reference replacement, and camera/lens locking after the first compatible media or photographed reference.
- Migrated the Repeatable capture HUD, information visibility, comparison timing, composition-grid selection, orientation handling, and capture completion behavior to the shared themed interface.
- Added shared alignment configuration for Repeatable timelapses and recorded videos, including correction models, crop limits, persisted settings, review/progress presentations, and reference-frame requirements.
- Moved timelapse alignment configuration to MP4 generation and added an explicit video alignment action while preserving tap-to-play behavior for recorded clips.
- Expanded Astro processing and shared workflow states while preserving module-specific Repeatable and Astro colors, components, and conditional controls.
- Hardened session manifests and catalogs for capture kinds, reference frames, rendered output discovery, empty-session cleanup, and restored project state.
- Expanded TDD coverage across configuration, capture tools, grids, catalogs, operation states, composition, references, alignment, and session persistence.

## v8.1.0-qa.1

- Added shared SwiftUI state components for Repeatable and Astro planning, camera availability, fallback, and reference/guide status using the module-specific design-system themes.
- Connected the new configuration interface to real capture preflight estimates so storage warnings remain actionable while blocked, unavailable, and error states prevent capture from starting.
- Added the themed custom-duration sheet with validated hour/minute input and quick presets for Repeatable timelapse and Astro sessions.
- Disabled manual Astro exposure controls in Automatic mode and preserved the existing legacy screens while the Next interface continues its staged migration.
- Expanded TDD coverage for planning gates, camera selection and fallback, reference states, custom durations, and conditional Astro controls.

## v7.0.0

- Extracted OpenCV alignment into the shared desktop C++ `camerae_vision` module, independent from Astro, Repeatable, Timelapse, and platform UI code.
- Added deterministic alignment feasibility coverage for `accept`, `review`, and `reject`, with stable typed diagnostics and versioned JSON schema 1 reports.
- Added the lightweight `CaptureFast` evaluator using reduced input, ORB, similarity/affine comparison, reference-feature caching, measured latency, and no image I/O, SIFT, or ECC.
- Added a reusable capture-alignment session with explicit reference invalidation, cancellation, resume, bounded cache diagnostics, and zero evaluation work while cancelled.
- Added an optional capture-support contract that is disabled by default and creates no evaluator or scheduled work until enabled.
- Added a desktop capture simulator with virtual cadence, latest-only backpressure, bounded pending frames, reduced decoding, decision distributions, latency percentiles, and approximate retained memory.
- Added conservative automatic final model selection across similarity, affine, and homography while preserving explicit model selection and exposing all candidate metrics through the desktop lab.
- Added seeded synthetic regression coverage for rigid, affine, perspective, and moving-object scenarios plus desktop benchmark guardrails for fast capture evaluation, final alignment, and retained memory.
- Expanded the release gate's C++ stage to explicitly cover both Camerae Processing and all Camerae Vision regression, benchmark, session, diagnostics, and simulator tests.
- Kept Camerae Vision integration with the live iOS and Android capture pipelines outside this release; that work remains a separate platform phase.

## v6.0.0

- Added a new branded entry experience, shared Camerae design tokens, bundled typography, module-specific themes, and redesigned project surfaces for Repeatable and Astro.
- Added direct project deletion with catalog, application, and integration coverage.
- Separated Astro planning from its live camera phase, keeping duration, format, exposure, interval, batch, and preflight controls in a dedicated setup screen.
- Improved orientation ownership so setup and project screens return to portrait while live capture can use the device orientation.
- Refined camera presentation, module navigation, responsive layouts, and reusable visual assets without changing existing project or session storage formats.
- Added an experimental desktop OpenCV alignment laboratory with ORB, AKAZE, and SIFT detectors; translation, similarity, affine, and homography models; optional CLAHE, mutual matching, RANSAC, and ECC; and reproducible diagnostics.
- Added desktop alignment feasibility classification (`accept`, `review`, or `reject`) based on geometric consistency, overlap, spatial coverage, deformation, and local edge residuals.
- Documented the future Camerae Vision module boundary and a deliberately staged Fast-model implementation plan; no mobile Camerae Vision integration is included in this release.
- Expanded Core, integration, and C++ coverage for project deletion, navigation composition, synthetic alignment, and processing regressions.

## v5.0.0

- Added duration presets and Custom planning for Repeatable video, Repeatable timelapse, and Astro captures.
- Added preflight estimates for completion time, frame count, final video duration, storage, energy, and effective Astro processing capability.
- Made HEIC the default still-image format with an explicit JPEG fallback based on runtime camera capabilities.
- Added conservative storage admission and active-capture guards that preserve finalization space and stop safely when capacity becomes critical.
- Added planned automatic completion, versioned capture plans, schema 5 migration, session repair, and project storage inventories.
- Added runtime Astro pipeline degradation for constrained memory, Low Power Mode, and thermal pressure.
- Added atomic validation and publication of rendered MP4 artifacts so a failed render cannot replace the last valid result.
- Added Core, Media, and integration coverage for planning, compatibility, recovery, storage safety, and Repeatable video presentation.
- Added a fail-closed local release gate for Git, signing, tests, builds, Firebase, and App Store Connect; automatic GitHub Actions triggers are disabled.
- Updated the iOS app icon and refined Repeatable video with a clip-size label, recording countdown, explicit early-stop retention, and safe-area-aware capture controls.

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

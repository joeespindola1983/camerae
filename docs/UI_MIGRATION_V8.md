# Camerae V8 UI migration

The V8 interface runs beside the legacy SwiftUI hierarchy until the complete workflow is proven on device.

## Active hierarchy

- `CameraeNextRootView` is the application entry point.
- `CameraeNextHomeView` owns the new module navigation.
- `CameraeNextProjectListView` routes Repeatable and Astro through `CameraeNextProjectCatalogView` and provides the Editor catalog.
- `CameraeNextProjectCatalogModel` owns ordering and progress filters; the legacy `ProjectListScreen` is no longer instantiated by the new hierarchy.
- `CameraeNextWorkflowConfigurationView` owns the portrait-only pre-capture configuration shared by Repeatable and Astro.
- `CameraeNextSessionCatalogView` owns the shared session library, filters empty capture shells, and routes Repeatable reopening and Astro processing.
- `CameraeNextCaptureCompletionView` owns the post-capture destination for both modules.
- `CameraeNextEditProjectView` owns the new Editor timeline, alignment entry point, and export confirmation.
- `CameraeNextEditExportView` owns Editor export status, cancellation, success, and sharing.
- `CameraeNextAlignmentView` presents OpenCV analysis without exposing matrices, pixel buffers, or implementation terminology.

## Compatibility bridge

- `AppRootView`, `EntryHomeView`, `RepeatableProjectRuntimeView`, `AstroProjectRuntimeView`, `CameraView`, `RepeatableCameraView`, `AstroProcessingView`, and `EditProjectRuntimeView` remain available.
- New camera configuration is passed through the optional `CameraeNextCaptureConfiguration` parameter. Existing call sites retain their previous defaults and setup screens.
- Capture controllers and Astro's mature processing engine are compatibility bridges. The active setup, catalog, session list, completion, Editor, alignment, and export surfaces do not instantiate their legacy equivalents.
- Capture is the only part of the new hierarchy that unlocks device orientation. All catalog, configuration, and editor screens restore portrait.

## Shared capture UI

`CameraeCaptureSessionPanel` is now used by both active capture workflows. `CameraeNextCaptureSessionPresentation` projects their domain-specific values into one six-metric contract and destructive running action. The panel uses maximum widths instead of fixed widths so compact iPhones can shrink it in portrait and landscape.

`CameraeNextCaptureToolCatalog` is the shared source of truth for capture helpers. Repeatable exposes trace, guides, blink comparison, sensors, and information. Astro consumes the same groups but only includes tools that are meaningful for its capture flow.

`CameraeNextGridStyle` provides rule of thirds, golden ratio, both golden spirals, diagonals, triangles, 4 × 4, and center cross. Its full-screen picker adapts to portrait and landscape and uses a dark preview layer plus a black-under-white grid stroke for contrast.

`CameraeNextOperationState` and `CameraeNextOperationOverlay` provide the shared idle, processing, success, failure, and cancellation contract used by new export operations.

## Alignment lifecycle

`CameraeNextAlignmentViewModel` owns the presentation state:

1. off or ready;
2. analyzing and cancellable;
3. applied, review, rejected, or failed;
4. stale after a timeline or asset fingerprint change;
5. explicit inclusion or exclusion in export.

Automatic mode preserves the analyzer plan. Position-only mode projects accepted corrections to translation while preserving the common crop and quality diagnostics. Review and rejected plans can never become export plans implicitly.

## Removal gate for legacy UI

Legacy capture and processing engines can be removed only after:

- capture-controller responsibilities are extracted from `CameraView` and `RepeatableCameraView` without duplicating AVFoundation behavior;
- the Astro processor is separated from `AstroProcessingView` so the new visual shell can own it directly;
- portrait/landscape capture snapshots are approved on supported iPhones;
- alignment cancellation, invalidation, review, and export pass on-device tests;
- the Firebase frameworks are confirmed embedded in an on-device Debug installation;
- no compatibility bridge is referenced by `CameraeNextRootView` descendants.

## TDD coverage

Presentation and policy tests cover workflow configuration, project filtering, temporary-project cleanup, capture metrics, completion, helper grouping, grid variants, session filtering, operation states, Editor export, and the full alignment lifecycle. The device-SDK build compiles the application and all integration tests; execution and snapshot approval remain an on-device step because no iOS Simulator runtime is installed in the current environment.

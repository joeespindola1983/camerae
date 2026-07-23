# Changelog

All notable Camerae changes are recorded in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Historical entries before this file was introduced were reconstructed from immutable Git tags and commit history. When the original release commit did not contain detailed notes, the entry is intentionally described as a consolidated historical milestone.

## [Unreleased]

**Status:** Development
**Areas:** Settings, capture, diagnostics, privacy, interface, release engineering, documentation

### Added

- Integrated Firebase Crashlytics for symbolicated QA and production crash reports.
- Added a testable crash-reporting adapter with allowlisted, non-personal module context.
- Added Release-only dSYM upload and explicit `qa`/`release` channel metadata.
- Added Crashlytics data-scope, privacy, and QA verification documentation.
- Added a Figma-aligned settings hub for privacy, diagnostics, capture defaults, performance, and storage.
- Added opt-out controls for Crashlytics and Analytics, enabled by default on new installs.
- Added per-module defaults: HEIC for Repeatable and DNG for Astro.
- Added runtime policies for capture quality, alignment cadence, storage warnings, and original-frame retention.

### Changed

- Established `develop` as the mandatory source for normal development.
- Made pull requests optional for the current solo-developer workflow.
- Required every QA-approved candidate to be reconciled into `develop`.
- Added a permanent changelog requirement to the release process.
- Replaced the Firebase Core-only pod with the locked Crashlytics dependency set.
- Refined the Home workflow cards and added a discreet Settings entry point.
- Applied performance preferences to AVFoundation and Camerae Vision while preserving thermal safety overrides.
- Kept low-storage safety stops mandatory even when optional warnings are hidden.
- Removed source frames only after a requested render completes successfully when original retention is disabled.

### Privacy

- Crash reporting is disabled in Debug and automated-test builds.
- Google Analytics, user IDs, project names, filesystem paths, locations, photos, and videos are excluded from diagnostic context.
- Applied saved opt-out state before the first diagnostics startup and kept Debug/test collection disabled by release policy.

## [8.3.2] - 2026-07-22

**Status:** Production
**Areas:** Capture, orientation, iPad, distribution, QA evidence

### Fixed

- Preserved the selected portrait or landscape orientation from camera startup through timelapse video generation.
- Declared the complete set of supported iPad orientations.
- Accepted modern and legacy Apple distribution identities in the release gate.

### Changed

- Declared App Store encryption compliance.
- Refreshed the App Store visual evidence gallery.

## [8.3.1] - 2026-07-22

**Status:** Production hotfix
**Areas:** Localization, workflow presentation, build system, QA evidence

### Fixed

- Corrected localized workflow presentation tests.
- Preserved CocoaPods workspace integration for command-line and distribution builds.

### Changed

- Completed localized configuration content and archived multilingual UI evidence.

## [8.3.0] - 2026-07-21

**Status:** Production
**Areas:** UI quality, iPhone, iPad, localization, release evidence

### Added

- Added a tracked, browsable visual history of the principal application screens.

### Changed

- Expanded QA evidence to cover iPhone and iPad layouts across the six supported languages.

## [8.2.0] - 2026-07-21

**Status:** Production
**Areas:** Repeatable, Astro, configuration workflows

### Changed

- Consolidated the configuration states and conditional workflow variations used by Repeatable and Astro.
- Prepared the updated project, capture, processing, and media flows for QA.

## [8.1.0] - 2026-07-20

**Status:** Production
**Areas:** Configuration UI, conditional states

### Added

- Added explicit UI states for project type, camera, capture timing, reference media, and module-specific configuration.

### Changed

- Improved parity between the designed workflows and their SwiftUI implementations.

## [8.0.0] - 2026-07-19

**Status:** Production major release
**Areas:** SwiftUI, Repeatable, Astro, alignment, media processing

### Added

- Introduced the new shared SwiftUI design-system migration for Repeatable and Astro.
- Added a conservative video-clip alignment pipeline.
- Added the Camerae Vision integration plan and reusable processing path.

### Changed

- Replaced the principal legacy workflow screens while retaining old implementations during migration.
- Unified shared module components and theme-driven presentation.

## [7.0.0] - 2026-07-19

**Status:** Production major release
**Areas:** Camerae Vision, alignment, diagnostics, performance

### Added

- Added a reusable capture-alignment session and automatic final alignment selection.
- Added typed alignment diagnostics and regression benchmarks.
- Added capture-quality evaluation and optional-capture support contracts.
- Added a desktop capture-quality simulator.

### Changed

- Extracted the shared Camerae Vision module for reuse by application and laboratory workflows.

## [6.0.0] - 2026-07-19

**Status:** Production major release
**Areas:** Release engineering, QA distribution

### Changed

- Consolidated the approved Camerae 5 release line into the next production baseline.
- Aligned the local release gate and Firebase QA promotion flow.

## [5.0.0] - 2026-07-14

**Status:** Production major release
**Areas:** Capture planning, storage, energy, recovery, release safety

### Added

- Added capture planning, storage admission, capability, and energy-domain models.
- Added HEIC capture storage and recovery support.
- Added preflight UI, planned completion, and persistent capture plans.
- Added storage-exhaustion protection for active captures.

### Changed

- Added schema 5 compatibility and project-storage inventory.
- Introduced a fail-closed local release gate and safer Firebase distribution.

## [4.0.0] - 2026-07-14

**Status:** Production major release
**Areas:** Edit, media library, alignment, performance, session UI

### Added

- Added the Edit module for discovering rendered Repeatable and Astro media.
- Added ordered sequence creation, preview, and shareable 1080p MP4 export without duplicating source files.
- Added a draggable alignment magnifier.

### Changed

- Redesigned timelapse session cards and improved card actions and navigation.
- Completed the Camerae 3 performance and TDD program before consolidating it into the 4.0 production tag.

## [2.1.0] - 2026-07-11

**Status:** Production minor release
**Areas:** Firebase, Repeatable alignment, GitFlow, build system

### Added

- Added Firebase distribution tooling and Repeatable alignment controls.

### Fixed

- Corrected command-line builds to use the CocoaPods workspace.

### Changed

- Documented the first lightweight Camerae GitFlow.

## [2.0.0] - 2026-07-07

**Status:** Production major release
**Areas:** iOS application

### Changed

- Consolidated the initial Camerae application into its second production generation.

## [1.6.0] - 2026-07-06

**Status:** Production minor release
**Areas:** iOS application

### Changed

- Historical stabilization milestone reconstructed from the final release tag.

## [1.5.0] - 2026-07-05

**Status:** Production minor release
**Areas:** iOS application

### Changed

- Historical stabilization milestone reconstructed from the final release tag.

## [1.4.0] - 2026-07-04

**Status:** Production minor release
**Areas:** iOS application

### Changed

- Historical stabilization milestone reconstructed from the final release tag.

## [1.3.0] - 2026-07-01

**Status:** Production minor release
**Areas:** Project foundation, iOS build

### Added

- Added the Camerae iOS application to the repository.
- Added the initial iOS build workflow.

## Historical QA candidates

These tags identify validated candidates but are not final production releases:

| Candidate | Date | Area | Description |
| --- | --- | --- | --- |
| `v2.2.0-qa.1` | 2026-07-12 | Distribution | Initial Camerae 2.2 QA build |
| `v2.2.1-qa.1` | 2026-07-12 | Distribution, build versioning | Follow-up QA build with build-setting version fixes |
| `v8.0.0-qa.1` | 2026-07-19 | Interface migration | Camerae 8.0 interface candidate |
| `v8.1.0-qa.1` | 2026-07-20 | Configuration UI | Camerae 8.1 conditional-state candidate |
| `v8.2.0-qa.1` | 2026-07-21 | Workflows | Camerae 8.2 workflow candidate |
| `v8.3.0-qa.1` | 2026-07-21 | Visual evidence | Camerae 8.3 UI validation candidate |
| `v8.3.1-qa.1` | 2026-07-22 | Localization | Camerae 8.3.1 localization hotfix candidate |
| `v8.3.2-qa.1` | 2026-07-22 | Orientation | Camerae 8.3.2 capture-orientation hotfix candidate |

[Unreleased]: https://github.com/joeespindola1983/camerae/compare/v8.3.2...develop
[8.3.2]: https://github.com/joeespindola1983/camerae/compare/v8.3.1...v8.3.2
[8.3.1]: https://github.com/joeespindola1983/camerae/compare/v8.3.0...v8.3.1
[8.3.0]: https://github.com/joeespindola1983/camerae/compare/v8.2.0...v8.3.0
[8.2.0]: https://github.com/joeespindola1983/camerae/compare/v8.1.0...v8.2.0
[8.1.0]: https://github.com/joeespindola1983/camerae/compare/v8.0.0...v8.1.0
[8.0.0]: https://github.com/joeespindola1983/camerae/compare/v7.0.0...v8.0.0
[7.0.0]: https://github.com/joeespindola1983/camerae/compare/v6.0.0...v7.0.0
[6.0.0]: https://github.com/joeespindola1983/camerae/compare/v5.0.0...v6.0.0
[5.0.0]: https://github.com/joeespindola1983/camerae/compare/v4.0.0...v5.0.0
[4.0.0]: https://github.com/joeespindola1983/camerae/compare/v2.1.0...v4.0.0
[2.1.0]: https://github.com/joeespindola1983/camerae/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/joeespindola1983/camerae/compare/v1.6.0...v2.0.0
[1.6.0]: https://github.com/joeespindola1983/camerae/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/joeespindola1983/camerae/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/joeespindola1983/camerae/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/joeespindola1983/camerae/releases/tag/v1.3.0

# Changelog

All notable Camerae changes are recorded in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Historical entries before this file was introduced were reconstructed from immutable Git tags and commit history. When the original release commit did not contain detailed notes, the entry is intentionally described as a consolidated historical milestone.

## App Store release status

This table is the operational source of truth for production submissions to
Apple. It is intentionally separate from internal QA and release-candidate
status. Update it whenever App Store Connect changes state; Firebase and other
test distributions do not require an entry here.

| Version | Apple status | Public availability | Last updated |
| --- | --- | --- | --- |
| `9.1.0` | In Review | Not yet available | 2026-07-30 |
| `8.5.1` | Approved | Available on the App Store | 2026-07-30 |

## [Unreleased]

### Added

- Added Repeatable Spatial Guidance on eligible LiDAR iPhones, with explicit
  capture start, automatic minimum-map completion, local world-map persistence,
  relocalization, and a dedicated Tripod project tab.
- Added draggable tripod-base and fixed 45-centimeter camera-direction controls,
  plus an estimated ghost tripod derived from mapped height and three nearby
  foot clusters with conservative fallbacks.
- Added a yellow plumb laser and ground halo, a clean reference screenshot, and
  navigation that restores the tripod and direction without rebuilding the
  captured wireframe.
- Added one black/white creation-contrast toggle and navigation-only black/white
  plus 25%/50%/100% appearance controls for tripod and camera.
- Added atomic remapping that preserves the last usable guide, keeps saved
  guides discoverable on incompatible devices, and offers safe recovery or
  continuation without Spatial Guidance.

### Changed

- Organized the canonical Figma file into stable design-system, workflow, domain, application, and website pages, and documented the corresponding design governance and Spatial Guidance handoff.
- Reconciled the canonical Spatial Guidance page with the validated
  center-and-direction flow and retained the earlier numeric pose-delta concept
  as legacy design evidence.

## [9.2.1] - 2026-07-29

**Status:** Approved
**Areas:** Repeatable mixed captures, project navigation, video duration, 4K/60 export

### Fixed

- Keeps project-card navigation keyed by the stable project ID so the recently opened project remains tappable while its metadata and list position refresh.
- Restores video duration from the project's latest recorded clip, normalizes near-preset recordings such as 29 seconds back to 30 seconds, and labels non-preset durations as Other.
- Preserve the recorded resolution, frame rate, HEVC codec, and source bitrate when exporting aligned Repeatable videos, including 4K at 60 fps, and reject silent capture or export downgrades.
- Select the largest full-sensor recording format before using stabilization support as a tie-breaker, preventing an unintended fallback to 1720 × 1290.
- Keep electronic video stabilization disabled for tripod-based Repeatable capture, preserving native field of view and resolution for alignment.

### Added

- Added obvious Photo, Video, and Timelapse SF Symbol badges to capture-type selection and every project capture card.
- Added independent editable defaults for Photo, Video, and Timelapse inside the same Repeatable project.

### Changed

- Locks only the project's physical camera and zoom after the first capture; all other capture settings remain preselected and editable.
- Migrates legacy immutable capture configurations to schema 3 hardware contracts with independent per-type presets.

## [9.2.0] - 2026-07-28

**Status:** QA candidate
**Areas:** Project catalog, storage, capture configuration, migration, Repeatable video alignment, Camerae Vision, Figma

### Added

- Added project actions to permanently delete a project or remove only original timelapse frames while preserving the reference image, generated photos, videos, and exports.
- Added a themed project-storage screen for Repeatable and Astro, matching the canonical light and dark examples in Figma.
- Added project-level capture configuration locking so Photo, Timelapse, and Video projects automatically reuse the type and exact settings selected for their first capture.

### Changed

- Automatically discards a newly created temporary project when the user leaves without creating or importing any durable content.
- Standardized every project-list thumbnail as a fixed, orientation-independent image area with the project name over the image and all metadata below it.
- Replaced project completion badges with actual capture totals and added archived-project filtering with reversible archive actions.
- Restored explicit project action menus after thumbnail changes and added tested interface-capability contracts that preserve archive, unarchive, and delete access across layout refactors.
- Added one-time migration for captured legacy projects so historical capture type, camera, format, duration, interval, and Astro stack size become a normalized immutable project configuration.
- Added independent project sorting by last activity or creation date with newest projects first.
- Added the fixed project capture type and configuration summary to project cards and subsequent capture setup.
- Uses the midpoint of the first Repeatable video as the project alignment reference and evaluates five points across every later clip before applying one constant reframe.
- Hides video alignment from the reference clip while preserving playback, sharing, and deletion.

### Fixed

- Restored project-list thumbnails for Astro captures and legacy projects while continuing to prefer an explicit Repeatable reference image.
- Localized the Repeatable capture-empty state, capture count and action, plus the Edit empty state, across all six release languages.
- Improved Repeatable video registration for appearance and contrast changes with SIFT, CLAHE, higher-resolution feature extraction, and temporally consistent confidence recovery.
- Keeps geometrically unstable, low-overlap, extreme-scale, and unsafe-projective Repeatable video matches blocked.

## [9.1.0] - 2026-07-28

**Internal status:** Release candidate

**App Store status:** In Review; not yet publicly available
**Areas:** Repeatable, single-photo capture, contour alignment, catalog, Figma

### Added

- Added single-photo capture to Repeatable with reference-guided framing, one-frame storage planning, and image viewing and sharing in the capture catalog.
- Added a live normal/inverted contrast control to the Repeatable contour-line tool.

### Fixed

- Corrected EXIF-oriented Repeatable references and preserved that orientation in the derived contour-line overlay.

## [9.0.0] - 2026-07-27

**Status:** Approved
**Areas:** Astro Photo, stacking, plate solving, celestial identification, Camerae Vision, QA environment, App Store

### Added

- Added the first offline plate-solving laboratory foundation to Camerae Vision, including gnomonic sky projection, deterministic synthetic star fields, OpenCV star centroid detection, annotated image evidence, and a versioned JSON report.
- Added TDD coverage for celestial projection round trips, synthetic star recovery, negative blank images, and the laboratory report contract.
- Added constrained catalog matching with validated RA/Dec center, camera roll, field of view, plate scale, residuals, confidence, and auditable star correspondences.
- Added conservative rejection tests proving that unrelated point fields do not produce a celestial solution.
- Added reflection-aware constrained matching and conservative offline lost-in-space solving with quad fingerprints.
- Added automatic letterbox detection, compact offline star catalogs, a deterministic catalog generator, and repeatable multi-image performance evidence.
- Added an isolated Objective-C++ plate-solving bridge for future Swift integration without enabling the feature in capture or UI.
- Added Astro Photo as a first-class capture mode with finite 5, 10, 20, or 30-image stacks, defaulting to 10 DNG originals.
- Added a dedicated Astro photo result and celestial-identification editor with independently selectable planet, nebula, and galaxy layers.
- Added an offline 20,000-star Gaia DR3 catalog, principal deep-sky objects, low-precision offline planetary ephemerides, image-space projection, and non-destructive JSON annotation sidecars.
- Added an independently installable `Camerae QA` iOS build using `com.espindola.camerae.qa`.
- Added a dedicated QA-badged application icon derived from the production mark.
- Added build-time Firebase environment selection and fail-closed IPA/archive validation.
- Added TDD contracts that prevent QA builds, Firebase apps, provisioning assets, and App Store archives from crossing environments.
- Added PT-BR App Store screenshot candidates for 6.9-inch iPhone and 13-inch iPad, combining authentic Astro results with Home, Astro, and Repeatable screens captured from the v9 interface.

### Changed

- Separated Astro Photo, Timelapse, and Video configuration contracts so photo stacking no longer depends on a duration-based batch workflow.
- Preserved every Astro Photo original while producing one aligned and stacked result for review, sharing, and optional identification.
- Replaced optional direct development commits with short-lived branches, structured Draft PR selection, required review-ready CI, and documented pull request routing for `develop` and release stabilization.
- Required detailed, non-empty release notes for every Firebase App Distribution publication and documented the enforced QA contract.
- Made Debug builds use the QA identity so local Xcode runs no longer replace the installed App Store application.
- Made Firebase App Distribution archive the dedicated QA scheme and Firebase application by default.
- Expanded Crashlytics symbol uploads to signed QA archives while retaining the separate `qa` release channel.

### Fixed

- Configured the development Team for local QA runs and enabled automatic signing for the QA development identity.

## [8.5.1] - 2026-07-24

**Internal status:** Released

**App Store status:** Approved by Apple and available on the App Store
**Areas:** Repeatable, video alignment, reference images, playback, sharing

### Fixed

- Made every Repeatable recorded video independently eligible for alignment whenever the project has a reference image.
- Aligned recorded videos against the project reference image instead of depending on another video or timeline order.
- Invalidated previously aligned video outputs when the project reference image is replaced.
- Preserved original recorded videos and made the generated aligned MP4 the default playback and sharing artifact.
- Used the reference image visible in the capture catalog when the project summary has not yet persisted that reference.
- Accepted reviewed Repeatable video alignments within the selected safe limits while keeping unsafe geometry blocked and logging each processing stage.
- Prevented an AVFoundation exception by limiting each photo request to the capture output's configured quality capability.
- Expanded aligned-export diagnostics with composition, preset, status, validation, and underlying AVFoundation error codes.
- Fixed portrait aligned exports without forcing landscape geometry, while retaining the 1080p preset for landscape compositions.
- Prevented upscaling by selecting the largest standard 9:16 or 16:9 resolution supported by the oriented source media.
- Applied the selected resolution, frame rate, quality, codec, and bitrate to actual video capture.
- Replaced the portrait-incompatible `AVAssetExportSession` path with controlled MP4 reading, composition, and encoding.
- Preserved 4K resolution in aligned MP4 output when the source media provides enough pixels.
- Prepared the 4K/16:9 camera format before preview starts to prevent reframing when recording begins.
- Enabled standard video stabilization when supported and kept preview and recording stabilization consistent.
- Used the first recorded video's stable frame as the shared geometric reference and cropped to the largest safe rectangle without black borders.
- Registered each Repeatable video from one stable frame at 0.2 seconds and applied that single fixed transform to the complete clip.

## [8.5.0] - 2026-07-23

**Status:** QA candidate
**Areas:** Home, project workflows, settings, localization, accessibility, QA evidence

### Added

- Added deterministic UI evidence for Settings overview, privacy and diagnostics, capture and performance, and storage.
- Expanded each release gallery from 10 to 14 screens.
- Added focused UI approval tests for Home, Repeatable projects, and an opened Repeatable project.

### Changed

- Removed the outer backgrounds, borders, and help affordances from the Home module buttons while retaining themed icon tiles.
- Applied theme accent colors to project-list titles.
- Made the opened Repeatable project title explicitly follow the light navigation-bar color scheme.
- Localized every Settings screen in Portuguese, Spanish, English, French, German, and Russian.
- Applied stable accessibility identifiers to Settings destinations and the complete first-project button.

### Fixed

- Fixed white Repeatable project titles on light backgrounds.
- Fixed iPad UI evidence navigation where the create-project identifier was attached to an inner label instead of the actionable button.

## [8.4.0] - 2026-07-23

**Status:** QA candidate
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
- Made the 12-gallery UI evidence matrix opt-in through `--ui-evidence`; non-UI QA gates skip screenshots by default.
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
| `v8.4.0-qa.1` | 2026-07-23 | Diagnostics, privacy | First Firebase Crashlytics candidate |
| `v8.4.0-qa.2` | 2026-07-23 | Release engineering | Crashlytics candidate with opt-in UI evidence |

[Unreleased]: https://github.com/joeespindola1983/camerae/compare/v8.4.0...develop
[8.4.0]: https://github.com/joeespindola1983/camerae/compare/v8.3.2...v8.4.0
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

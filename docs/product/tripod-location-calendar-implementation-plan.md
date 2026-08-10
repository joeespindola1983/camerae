# Tripod Location Hub, Positions Map, and Capture Calendar

## Purpose

This is the implementation handoff for branch
`codex/tripod-location-hub`. The branch already includes the approved
environment-first Spatial Guidance flow: Camerae maps the fixed environment,
freezes a clean `ARWorldMap`, then asks the user to place and mark the tripod.

The next product version changes the Repeatable information architecture around
three durable questions:

1. **What?** A project defines lens, capture kind, framing, and capture settings.
2. **Where?** A Tripod Location defines the physical place, GPS context, spatial
   map, tripod base/direction, and reference album.
3. **When?** The Capture Calendar combines completed sessions with planned
   recaptures and optional reminders.

The visible Editor home module is temporarily replaced by two library
destinations: **Calendar** and **Positions**. Existing Edit projects and the
`.edit` enum case must remain decodable and must not be deleted.

## Non-negotiable repository workflow

- Figma is the visual source of truth.
- Typed capability policies are the functional source of truth.
- Use red-green-refactor TDD for every product change.
- Do not implement a composed SwiftUI screen before its Figma states and typed
  capability contract exist.
- Views consume normalized current-version models only. Legacy detection and
  migration belong in stores/resolvers.
- Persistent schema changes require current, legacy, empty, malformed, and
  unsupported-newer tests.
- Migrations must be one-time, idempotent, and non-destructive.
- Work only on a short-lived branch derived from `develop`; this branch is
  intentionally derived from the environment-first Spatial Guidance work.
- Keep each phase independently buildable and commit each completed phase.
- Do not stage or modify unrelated localization catalogs or user files.

## Product vocabulary

Use these names consistently:

| Product term | Code term | Meaning |
| --- | --- | --- |
| Posição do tripé | `TripodLocation` | Durable physical placement, not a hardware tripod |
| Revisão espacial | `TripodSpatialRevision` | Immutable saved environment map and tripod coordinates |
| Foto do local | `TripodReferencePhoto` | Context, access, environment, or tripod-placement photo |
| Projeto | `CameraProject` | Lens/capture/framing configuration and its sessions |
| Captura planejada | `ScheduledCapture` | Future recapture associated with a location/project |
| Evento de captura | `CaptureTimelineEvent` | Completed or planned item shown in Calendar |

Do not call Calendar or Positions a `CameraModule`. They are cross-library home
destinations. Keep `CameraModule.edit` for forward/legacy compatibility while
hiding it from the visible home policy.

## Target information architecture

```text
Camerae Home
├── Repeatable
│   └── Recent projects and capture workflow
├── Astro
├── Calendar
│   ├── Completed capture dates
│   └── Planned recaptures
└── Positions
    ├── Map
    └── Position list

Optional organization group
└── Tripod Location
    ├── Current spatial revision
    ├── Previous spatial revisions
    ├── GPS/map context
    ├── Reference album
    └── Projects
        ├── Wide photo project
        ├── Tele photo project
        └── Video/timelapse project
```

Groups remain organizational. A Tripod Location is content inside a group, not
a renamed group and not a third organization level. Projects link to a location
but remain independent project directories.

## Ownership rules

### Tripod Location owns

- Human-readable name and optional notes.
- Optional organization node ID.
- Optional GPS coordinate, horizontal accuracy, timestamp, and cached label.
- Optional manually adjusted map coordinate.
- Hero/reference photo selection.
- Multiple reference photos with semantic roles.
- Current spatial revision ID and immutable revision history.
- Project memberships.
- Created, updated, last-used, and archive metadata.

### Project owns

- Camera lens and zoom.
- Photo, video, or timelapse capture kind.
- Capture settings and hardware lock.
- Project-specific framing/reference image.
- Sessions and captured media.

### Capture session owns

- The location ID used for that capture, when any.
- The spatial revision ID used for navigation, when any.
- The planned-capture ID when launched from a Calendar event.
- Existing geo pose, motion, lens, capture kind, and media metadata.

Never copy a Tripod Location's world map into every project. Resolve it by ID.
New projects created inside a location inherit the relationship, not duplicated
files. Wide/tele/video projects retain independent configurations.

## Proposed domain models

The exact naming may be refined, but preserve the boundaries.

```swift
public struct TripodLocationRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let notes: String?
    public let organizationNodeID: UUID?
    public let coordinate: TripodGeoCoordinate?
    public let heroPhotoID: UUID?
    public let currentRevisionID: UUID?
    public let createdAt: Date
    public let updatedAt: Date
    public let lastUsedAt: Date?
    public let isArchived: Bool
}

public struct TripodGeoCoordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracy: Double?
    public let capturedAt: Date?
    public let source: TripodCoordinateSource
    public let cachedLabel: String?
}

public enum TripodCoordinateSource: String, Codable, Sendable {
    case device
    case manualPin
    case migratedSession
}

public struct TripodLocationProjectMembership: Codable, Equatable, Sendable {
    public let projectID: UUID
    public let locationID: UUID
    public let linkedAt: Date
}

public struct TripodSpatialRevisionRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let locationID: UUID
    public let createdAt: Date
    public let manifestRelativePath: String
    public let status: TripodSpatialRevisionStatus
}

public struct TripodReferencePhotoRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let locationID: UUID
    public let role: TripodReferencePhotoRole
    public let relativePath: String
    public let createdAt: Date
    public let caption: String?
}

public enum TripodReferencePhotoRole: String, Codable, CaseIterable, Sendable {
    case hero
    case environment
    case access
    case tripodPlacement
}
```

The location album may initially allow 12 photos. Keep the limit in a typed
policy, not in SwiftUI geometry.

### Scheduling models

```swift
public struct ScheduledCapture: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let tripodLocationID: UUID?
    public let projectID: UUID?
    public let sourceSessionID: UUID?
    public let title: String
    public let scheduledFor: Date
    public let timeZoneIdentifier: String
    public let isAllDay: Bool
    public let reminderLeadTime: TimeInterval?
    public let notes: String?
    public let status: ScheduledCaptureStatus
    public let fulfilledSessionID: UUID?
    public let createdAt: Date
    public let updatedAt: Date
}

public enum ScheduledCaptureStatus: String, Codable, Sendable {
    case scheduled
    case completed
    case skipped
    case cancelled
}

public enum CaptureTimelineEvent: Identifiable, Equatable, Sendable {
    case completed(CaptureHistoryEvent)
    case planned(ScheduledCapture)
}
```

Version one supports one-off reminders. Recurring rules are explicitly deferred.

## Storage layout

Use library-level storage for location metadata and packages:

```text
Application Support/Camerae/
├── tripod-locations-v1.json
├── scheduled-captures-v1.json
└── capture-timeline-cache-v1.json       # rebuildable cache only

Camerae Tripod Locations/
└── <location-id>/
    ├── location.json
    ├── photos/
    │   └── <photo-id>.jpg
    └── revisions/
        └── <revision-id>/
            ├── manifest.json
            ├── world_map.bin
            └── keyframes/
```

The authoritative capture history remains the project/session manifests. The
timeline cache must be safe to delete and rebuild.

## Typed functional contracts

Add neutral policies before SwiftUI:

- `CameraeHomeDestinationPolicy`
- `TripodLocationCapabilityPolicy`
- `TripodLocationProjectCapabilityPolicy`
- `TripodLocationDeletionPolicy`
- `TripodReferencePhotoCapabilityPolicy`
- `TripodLocationMapPresentationPolicy`
- `CaptureCalendarCapabilityPolicy`
- `ScheduledCaptureCapabilityPolicy`
- `ScheduledCaptureCompletionPolicy`

Minimum contracts:

| State | Required actions |
| --- | --- |
| Home | Open Repeatable, Astro, Calendar, Positions |
| Position without map | Edit, add photo, map environment, create/link project, move, archive |
| Position with map | Navigate, remap, add photo, create/link project, move, archive |
| Position with linked projects | Deletion must require detach/reassign; never cascade silently |
| Calendar day with history | Open capture, project, and position when available |
| Planned capture | Start, reschedule, edit note, cancel/skip |
| Notification denied | Keep event saved and expose notification settings/retry |

## Phase 0 — Figma and decision lock

### Deliverables

Update the canonical Figma library before SwiftUI implementation. Create the
following dark-theme iPhone states, plus iPad variants where the existing
catalog supports iPad:

1. Home with Repeatable, Astro, Calendar, and Positions.
2. Positions map with multiple pins.
3. Positions map with a selected callout.
4. Positions list fallback.
5. Empty Positions state.
6. Position detail with hero photo, mini map, spatial status, and projects.
7. Position detail without GPS.
8. New/Edit Position sheet.
9. Add/reference photo flow.
10. Create Project inside Position sheet.
11. Link existing Project flow.
12. Monthly Calendar with completed/planned indicators.
13. Day agenda with completed and planned cards.
14. Empty Calendar state.
15. Plan Recapture sheet with “in 4 weeks” quick action.
16. Reminder permission denied state.

### Decisions to lock in Figma copy

- User-facing term is **Posição do tripé**.
- Positions root defaults to map but always offers list.
- Repeatable remains the project/capture entry point.
- Calendar and Positions are library destinations, not capture modules.
- Location album and project framing references are visually distinct.

### Gate

Do not start Phase 1 until frame IDs and component IDs are recorded in
`docs/product/interface-capability-contracts.md`.

## Phase 1 — Hide Editor and introduce home destinations

### Expected files

- `ios/Camerae/ProjectStore.swift`
- `ios/Camerae/Next/CameraeNextRootView.swift`
- New neutral home destination/policy file if needed.
- `ios/CameraeIntegrationTests/CameraeNext*Tests.swift`

### TDD first

Write failing tests proving:

1. Visible home destinations are Repeatable, Astro, Calendar, and Positions.
2. Editor is not visible.
3. `CameraModule.edit` still decodes.
4. Existing Edit project records remain loadable and untouched.
5. Calendar and Positions navigation actions are reachable independently of
   tile layout.

### Implementation

- Introduce `CameraeHomeDestination` instead of using
  `CameraModule.allCases` directly for the home.
- Preserve all Editor runtime/storage code.
- Add placeholder Calendar and Positions destinations that use approved Figma
  empty states.

### Acceptance

- No Edit data migration or deletion occurs.
- Home capability tests are layout-independent.
- Existing project catalog tests still pass.

## Phase 2 — Tripod Location domain and catalog

### Expected files

- New `ios/CameraeCore/TripodLocationModels.swift`
- New `ios/CameraeCore/TripodLocationCatalog.swift`
- New `ios/CameraeCoreTests/TripodLocationCatalogTests.swift`
- `ios/Camerae/ProjectStore.swift` or a focused application-level facade.

### TDD first

Cover:

1. Empty catalog creation.
2. Create, rename, archive, unarchive, and update coordinate.
3. Link one location to multiple Repeatable projects.
4. Prevent one Repeatable project from linking to multiple current locations.
5. Reject Astro/Edit membership.
6. Preserve independent project directories.
7. Normalize missing projects and missing organization nodes.
8. Deleting a group returns locations to ungrouped.
9. Deleting a project removes only its membership.
10. Deleting a location with linked projects is blocked until explicit detach
    or reassignment.
11. Current, legacy/unversioned, empty, malformed, and unsupported-newer docs.
12. Atomic writes and cache reload.

### Acceptance

- No SwiftUI imports in CameraeCore.
- The catalog is actor-isolated like `ProjectCatalog`.
- `TripodLocationResolver.normalize` is deterministic and independently tested.

## Phase 3 — Non-destructive migration

### Migration rules

For every Repeatable project:

1. If it has a valid project-local `spatial_reference`, create one candidate
   Tripod Location and one spatial revision.
2. Link that project to the new location.
3. Carry its existing organization node to the location.
4. Derive an optional GPS candidate from the best existing session geo pose.
5. Copy, validate, and reload the new package before marking migration complete.
6. Keep the old project-local reference as rollback data during this version.
7. Projects without references remain under **Sem posição**.

Do not automatically merge copied references from different projects. World-map
hash, GPS distance, and base coordinates may produce a later merge suggestion,
but false merges are worse than duplicates.

### TDD first

Cover:

- One project with reference.
- Multiple projects with distinct references.
- Two copied-looking references remain separate.
- Project without reference.
- Missing/corrupt world map.
- Existing organization membership.
- No GPS and inaccurate GPS.
- Interrupted migration resumes idempotently.
- Running migration twice produces byte-equivalent normalized metadata.
- Unsupported-newer data is preserved and reported, never overwritten.

### Gate

Do not delete legacy reference directories in this branch.

## Phase 4 — Move Spatial Guidance ownership to locations

### Expected files

- `ios/Camerae/SpatialGuidance/SpatialReferenceStore.swift`
- `ios/Camerae/SpatialGuidance/SpatialGuidanceDomain.swift`
- `ios/Camerae/SpatialGuidance/SpatialGuidanceRuntime.swift`
- `ios/Camerae/SpatialGuidance/SpatialGuidanceViews.swift`
- `ios/CameraeIntegrationTests/SpatialGuidanceTests.swift`

### Refactor

- Replace project-directory ownership with a location/revision package resolver.
- Keep a legacy read fallback during migration.
- Remapping creates a new immutable revision and changes
  `currentRevisionID`; it never overwrites the old revision in place.
- Store base/direction coordinates in the revision manifest.
- Keep camera lens, capture kind, and project framing outside the location.
- A capture session records the revision used for navigation.

### TDD first

- New location map save/load.
- Revision creation and current-revision switching.
- Previous revision remains loadable.
- Failed remap leaves current revision unchanged.
- Legacy project reference still loads.
- Projects linked to the same location resolve the same revision without copies.
- Wide and tele configurations remain project-specific.

### Acceptance

- One physical map package can serve multiple projects.
- The environment-first flow remains unchanged visually and functionally.

## Phase 5 — Project creation and quick start inside a position

### Flow

From Position Detail:

1. Tap **Novo projeto**.
2. Enter project name.
3. Choose capture kind and lens using existing configuration components.
4. Create the normal project directory.
5. Atomically add location membership.
6. Open project configuration with the location context already available.

Also support **Vincular projeto existente** and **Mover para outra posição**.

### TDD first

- Create + link is atomic from the user's perspective.
- Failed membership does not silently present a linked project.
- Linking does not copy a world map.
- Project camera settings are independent.
- Moving preserves sessions/media and updates only membership.
- Detaching leaves the project under **Sem posição**.

## Phase 6 — Positions map and detail UI

### Expected files

- New `ios/Camerae/TripodLocations/` feature folder.
- MapKit/CoreLocation adapter separated from neutral domain.
- Capability tests in integration test target.

### Map behavior

- Display one annotation per non-archived location with valid coordinates.
- Selecting a pin shows hero photo, name, project count, last capture, and next
  planned capture.
- Opening the callout navigates to Position Detail.
- Provide map/list toggle.
- List locations without GPS separately.
- Manual pin placement must work without location permission.
- Request location permission only when the user asks to use current location.
- Full-accuracy denial must not block creation.
- Cluster annotations when necessary; clustering is presentation only.

### TDD first

- Annotation presentation for valid coordinate.
- No-coordinate list fallback.
- Permission denied/restricted/not determined/authorized states.
- Manual coordinate source.
- Archived locations hidden from active map.
- Required actions remain reachable in compact/iPad layouts.

### Acceptance

- GPS helps find the area; ARKit remains the precise placement mechanism.
- Coordinates stay local to the Camerae library in version one.

## Phase 7 — Capture Calendar history

### Domain

Build a neutral resolver that merges project/session manifests into
`CaptureHistoryEvent` values. Do not make SwiftUI scan project folders directly.

The rebuildable timeline cache should include only compact metadata:

- Session ID and project ID.
- Location/revision IDs when available.
- Capture kind.
- Creation date.
- Thumbnail reference when available.

### Calendar UI

- Month view with distinguishable completed and planned indicators.
- Day agenda lists completed captures and future plans.
- Filters: All, Repeatable, Astro, Position, Project.
- A completed event can open its capture, project, or position.
- Empty states distinguish no history from active filters with no results.

### TDD first

- Stable day bucketing in the event time zone.
- Daylight-saving boundary dates.
- Multiple capture kinds on one day.
- Missing project/location references degrade gracefully.
- Cache rebuild equals direct manifest resolution.
- Deleting the cache loses no authoritative data.
- Calendar capabilities are independent of cell geometry.

## Phase 8 — Planned recaptures and local reminders

### Core workflow

Offer **Planejar nova captura** from:

- Capture completion.
- Capture detail.
- Project detail.
- Position detail.
- Calendar add action.

Quick choices include tomorrow, one week, two weeks, and four weeks. The user may
choose any date/time and add notes such as “capturar sem flores”.

### Notification architecture

Create a protocol-backed notification coordinator so tests do not call
`UNUserNotificationCenter` directly.

- Persist the event before requesting/scheduling a notification.
- Request notification permission only after the user enables a reminder.
- Notification identifier: `camerae.scheduled-capture.<event-id>`.
- Editing reschedules; cancelling/completing removes the pending notification.
- Permission denial leaves the Calendar event intact.
- Store the intended time zone to avoid silent shifts.

### Planned capture launch

Starting a planned capture passes its event ID through the workflow. A successful
capture completion explicitly marks that event completed and stores the
fulfilled session ID. Do not auto-match unrelated captures by timestamp.

### TDD first

- Create one-off event in four weeks.
- All-day and timed events.
- Notification allowed/denied/not requested.
- Edit and reschedule.
- Cancel and skip.
- Start planned capture and fulfill with a session.
- Failed/abandoned capture keeps event scheduled.
- Deleted project keeps a recoverable position-only event.
- Deleted location requires reassignment or detachment of future events.

## Phase 9 — Integration, accessibility, and release gate

### Integration checks

- Home routes work in compact and iPad layouts.
- VoiceOver labels pins, calendar days, event status, and actions.
- Dynamic Type does not remove required actions.
- Map and Calendar have useful no-permission/offline states.
- Spatial Guidance resolves the selected location before capture.
- New projects use location context without inheriting lens incorrectly.
- Existing projects and Edit data remain intact.

### Required verification

- CameraeCore Tripod Location tests.
- Project catalog and organization tests.
- Spatial Guidance tests.
- Home capability tests.
- Positions capability tests.
- Calendar/scheduling tests.
- Current, legacy, empty, malformed, and unsupported-newer persistence tests.
- iOS arm64 `build-for-testing`.
- Relevant capability-contract tests after every hierarchy change.
- On-device GPS, MapKit, ARKit relocalization, and notification validation.

Known local limitation: the current OpenCV framework may block an x86_64
simulator link. Use the arm64 device build to prove source/test compilation and
record the simulator limitation separately; do not weaken tests to bypass it.

Update `CHANGELOG.md` under `Unreleased` and keep the PR template complete with
release value, validation, migration risk, and rollback.

## MVP completion definition

The first releasable slice is complete when:

1. Editor is hidden but all Edit data remains readable.
2. Home exposes Repeatable, Astro, Calendar, and Positions.
3. A user can create a Tripod Location with optional GPS and multiple photos.
4. A location can own a clean spatial revision and multiple projects.
5. A project created inside a location uses its spatial guide without copying
   the world map.
6. Positions shows map pins and a list fallback.
7. Calendar shows historical captures.
8. A user can schedule a one-off recapture in four weeks.
9. Optional local notification behavior is correct for all permission states.
10. Launching the plan and completing capture marks it fulfilled.
11. Existing project references migrate idempotently with rollback data kept.
12. Figma, typed capabilities, tests, documentation, and on-device validation
    all agree.

## Explicitly out of scope for this version

- Apple Calendar/EventKit synchronization.
- Cloud sync or shared team locations.
- Automatic annual/seasonal recurrence.
- Weather, flowering, or phenology prediction.
- Automatic merging of similar locations.
- Route planning/navigation to the GPS pin.
- Removing legacy Edit data or Editor implementation.
- Deleting project-local spatial references immediately after migration.
- Android implementation before the shared product/domain decisions stabilize.

## Recommended commit sequence

1. `Define home destination capabilities`
2. `Add tripod location domain and catalog`
3. `Migrate project spatial references to locations`
4. `Resolve spatial guidance through location revisions`
5. `Create projects inside tripod locations`
6. `Add tripod positions map and detail`
7. `Add capture calendar history`
8. `Add planned recaptures and reminders`
9. `Complete tripod hub migration and release checks`

Do not collapse these into one commit. If a phase grows too large, split by
domain/store before SwiftUI, while keeping every commit buildable.

## Execution record — 2026-08-05

Status: implemented on `codex/tripod-location-hub` as an exploratory Draft PR.

Canonical Figma file: `c8gsnSu31erYFG3u3QMQgN`, page
`814:1839` (`14 · Tripod Positions & Calendar`). The page contains all sixteen
states defined in Phase 0. Representative roots:

- Home: `814:1840`
- Positions map: `814:1841`
- Position detail: `814:1845`
- Calendar month: `814:1851`
- Four-week recapture: `814:1854`

Implementation decisions:

- The persisted aggregate is `TripodLocationDocument` schema v1.
- One project can belong to at most one Tripod Location; relinking moves it.
- Reference photos and spatial packages live below
  `Application Support/Camerae/TripodLocations/<location-id>`.
- Legacy project spatial packages are copied, never moved or deleted.
- Calendar history is read from real session summaries; future events are
  stored as recapture plans and local notifications.
- Editor remains in the model and runtime but is not exposed by Home.

Automated evidence:

- Generic arm64 application build: passed.
- Generic arm64 `build-for-testing`, including CameraeCore and integration
  capability tests: passed.
- Simulator execution was unavailable in this environment; on-device GPS,
  map interaction, AR relocalization, photo picking, and notification delivery
  remain mandatory QA checks before the Draft PR can be marked ready.

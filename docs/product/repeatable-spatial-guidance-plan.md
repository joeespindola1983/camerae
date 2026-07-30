# Repeatable spatial guidance plan

## Status

- Product name: **Spatial Guidance** in design and code; **Guia espacial**
  in Portuguese user-facing copy.
- Initial module: Repeatable.
- Future module: Astro, enabled by capability policy rather than a separate
  implementation.
- Delivery order: approved Figma flow, short-lived branch, failing tests,
  implementation, automated verification, and on-device Xcode validation.
- This document is the implementation plan. Figma remains the visual source of
  truth, and typed interface-capability policies remain the functional source
  of truth.

## Outcome

Help a person return the phone camera to a previously recorded physical pose.
The first visit saves an ARKit world map and a camera-pose anchor. A later
visit relocalizes into that map, displays a generic ghost tripod and camera
target, and reports the remaining translation and rotation before capture.

The target is the phone and its camera pose, not a photorealistic reconstruction
of the tripod. Tripod geometry is a visual aid.

## MVP scope

The first release provides:

1. Runtime eligibility on supported iPhones.
2. A project-level Spatial Guidance card in Repeatable configuration.
3. A guided first-visit scan around a stationary tripod and static surroundings.
4. Explicit mapping-quality feedback before a map can be saved.
5. A final step in which the phone is mounted and its target pose is recorded.
6. Atomic local persistence of the world map, anchors, manifest, and guide
   images.
7. Later relocalization into the saved map.
8. A generic translucent ghost tripod and phone target.
9. Directional translation and rotation guidance.
10. Explicit `aligned`, `near`, `out of position`, and `low confidence` states.
11. A safe path to continue capture without Spatial Guidance.
12. A safe remap operation that retains the previous usable guide until the
    replacement is validated.

## First-visit flow

1. The compatible Repeatable project shows **Mapear local**.
2. An introduction asks the person to:
   - keep the tripod stationary;
   - walk slowly around it;
   - include the ground and distinctive static surroundings;
   - avoid people, moving vehicles, and rapid camera motion.
3. The app starts world tracking, scene depth, and scene reconstruction.
4. A pure quality evaluator combines:
   - normal camera tracking;
   - suitable world-mapping status;
   - minimum elapsed scan time;
   - angular coverage around the target;
   - detected floor;
   - minimum mapped volume;
   - acceptable thermal state.
5. The app does not enable completion until the quality contract is satisfied.
6. The person mounts the phone in the intended capture orientation.
7. The app records the camera target transform, device, lens, zoom, orientation,
   anchors, and mapping diagnostics.
8. The store writes a candidate bundle, validates it, and publishes it
   atomically.

## Return flow

1. The project shows **Usar guia espacial**.
2. The saved world map becomes the session's initial world map.
3. Saved guide images help the person revisit previously observed viewpoints.
4. The ghost rig stays hidden while tracking is initializing or relocalizing.
5. The ghost appears only after:
   - tracking returns to normal;
   - the saved target anchor is restored;
   - pose stability remains acceptable for a defined interval.
6. The person positions and mounts the tripod.
7. The UI reports horizontal, vertical, and depth displacement plus pitch, roll,
   and yaw guidance.
8. The person can continue when satisfied; the product does not claim
   millimeter precision.

## Eligibility

Eligibility is resolved at runtime and is independent from view geometry.
The policy accepts neutral capability inputs and initially enables only:

- `CameraModule.repeatable`;
- iPhone;
- AR world tracking;
- scene reconstruction with classification;
- scene depth and smoothed scene depth;
- an acceptable resource and thermal budget.

Astro remains disabled in version one even on compatible hardware. A saved
guide opened on incompatible hardware must remain identifiable and must not be
silently deleted or replaced.

Model names are not the primary compatibility contract. Apple capability
checks, resource state, and tested performance define availability.

## Component architecture

The feature must not live inside `RepeatableCameraView`.

### Domain

`SpatialReferenceDomain` owns neutral value types and state:

- feature availability;
- mapping and relocalization phases;
- quality observations and decisions;
- pose delta and confidence;
- persisted manifest model;
- module policy.

It does not import ARKit or SwiftUI.

### Session abstraction

`SpatialSceneSession` is a protocol that publishes:

- tracking state;
- mapping status;
- scene observations;
- restored anchors;
- current camera pose;
- final world-map data;
- cancellation and failure.

`ARKitSpatialSceneSession` is the production adapter. Tests use deterministic
fakes.

### Persistence

`SpatialReferenceStore` owns a versioned project-level bundle:

```text
spatial_reference/
├── manifest.json
├── world_map.bin
├── keyframes/
│   ├── 001.jpg
│   ├── 002.jpg
│   └── ...
└── previous/
```

The version-one manifest records:

- schema version;
- creation date;
- device model;
- lens identifier and zoom;
- capture orientation;
- 4 × 4 target camera transform;
- anchor identifiers;
- world-map filename;
- guide-image filenames;
- mapping-quality evidence.

Guide images use JPEG quality `0.75` and a maximum long edge of `1920` pixels.
Spatial data remains local by default and is excluded from media sharing and
exports unless a future explicit product contract says otherwise.

### Presentation

Reusable presentation is divided into:

- `SpatialGuideCard` for project configuration;
- `SpatialGuideFlowView` for mapping and relocalization;
- `GhostRigRenderer` for tripod and phone targets;
- `SpatialPoseGuidance` for deltas and confidence.

Theme and module availability are injected. Domain and storage types must not
contain `Repeatable` in their names.

## Figma contract

The dedicated `05 · Spatial Guidance` page (`662:2`) owns:

- mapping introduction;
- mapping progress and missing-coverage states;
- mounting and target-pose capture;
- saved-guide state;
- relocalization;
- ghost rig;
- pose correction;
- success, timeout, incompatibility, remap, and recovery.

Reusable project-entry components may live in `Workflow Components` after they
are approved. Live capture helpers may reuse primitives from `Capture
Assistance`. Composed application entry points remain in `App Screens`.

Figma must cover:

- first map;
- active map;
- replacement confirmation;
- portrait mapping;
- portrait and landscape mounted guidance;
- relocalizing;
- low confidence;
- failure and retry;
- incompatible device with a saved guide;
- continue without guide.

No SwiftUI hierarchy work begins before the flow, copy, component states, and
node IDs are approved.

## TDD plan

### Availability policy

Write failing tests for:

- supported Repeatable device is eligible;
- missing LiDAR capabilities is ineligible;
- compatible Astro remains disabled;
- critical thermal state pauses the operation;
- low-power behavior is explicit;
- another device or lens cannot claim high precision;
- a saved incompatible guide remains discoverable.

### State machine

Cover the successful paths:

```text
empty
→ mapping
→ sufficient
→ awaiting mount
→ saving
→ ready

ready
→ relocalizing
→ localized
→ positioning
→ aligned
```

Cover cancellation, excessive motion, insufficient features, tracking loss,
timeout, retry, invalid anchors, and safe fallback to the previous guide.

### Quality evaluator

Use pure inputs to test tracking, world-mapping status, elapsed time, angular
coverage, floor evidence, mapped volume, pose stability, and thermal state.
Unit tests must not require a physical AR session.

### Store and schema

Test:

- current schema round trip;
- empty project;
- malformed or unversioned data;
- unsupported newer schema;
- atomic candidate publication;
- cancellation preserving the previous guide;
- JPEG dimensions and format;
- project deletion removing spatial data;
- normal media export excluding spatial data.

No artificial legacy migration is created without historical evidence. Absence
of a spatial bundle is the valid pre-feature state.

### Interface capabilities

The typed policy must keep these actions reachable when applicable:

- map location;
- use guide;
- review guide images;
- remap;
- retry relocalization;
- continue without guide;
- continue to capture.

It must also prove that Astro does not expose the first release. Capability
tests remain independent from layout and orientation.

### ARKit integration

Fakes simulate map completion, anchor restoration, known pose deltas,
instability, timeout, and failure. The real adapter is validated by compilation
and a physical-device test matrix.

## Delivery slices

1. Domain policies, state machine, codec, and store.
2. Configuration entry and complete flow driven by a fake session.
3. ARKit capability provider and first-visit map persistence.
4. Relocalization, restored anchor, ghost rig, and pose guidance.
5. Diagnostics, accessibility, localization, recovery, and device validation.

Each slice starts with failing tests and leaves the Draft PR buildable.

## Git and verification

After Figma approval:

1. Start from a clean, fast-forwarded `develop`.
2. Create `codex/repeatable-spatial-guide`.
3. Open a Draft PR into `develop`.
4. Add the failing test for the current slice.
5. Implement only enough to pass it.
6. Run relevant capability, domain, persistence, integration, and UI tests.
7. Regenerate the Xcode project if project configuration changes.
8. Run the device-SDK build and compile all affected test targets.
9. Hand the green branch to Xcode for physical-device validation.

## Device validation

The first internal build exposes temporary diagnostics for:

- scene-depth support;
- scene-reconstruction support;
- tracking state;
- mapping status;
- angular and volume coverage;
- thermal state;
- restored-anchor state;
- translation and rotation delta;
- confidence;
- saved-map size.

The manual matrix includes:

- app termination between visits;
- tripod displacement of 10–30 cm;
- near and far scene objects;
- portrait and landscape capture;
- different lighting, including day and night;
- remap cancellation;
- tracking loss and retry;
- temperature, battery, storage, and capture handoff.

## Acceptance criteria

The MVP is ready for product evaluation when:

- approved Figma states and node IDs exist;
- only eligible Repeatable projects expose the active feature;
- a crash or cancellation cannot destroy the last usable guide;
- an app relaunch can restore the saved anchor on a supported device;
- the ghost appears only after trustworthy relocalization;
- translation, rotation, and confidence are explicit;
- capture without the guide still works;
- automated contracts pass;
- the branch builds and runs from Xcode on a supported iPhone.

## Deferred precision work

Version one does not perform independent registration of two dense LiDAR maps.
After physical testing measures real relocalization error, a second phase may
save a decimated static mesh and use geometric registration to validate or
refine ARKit. Flat-floor-only scenes, symmetric environments, appearance
changes, drift, and false confidence must be evaluated before that behavior can
be automatic.

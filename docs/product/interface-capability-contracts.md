# Interface capability contracts

Figma defines how Camerae screens look. It does not, by itself, prove that a
SwiftUI hierarchy still exposes every required product action.

Each composed screen therefore has two complementary sources of truth:

1. Figma Screens define visual hierarchy, themes, spacing, states, and content.
2. Typed capability policies define which user actions must remain reachable.

Layout tests may validate geometry, but they must not replace capability tests.
A thumbnail, card, toolbar, modal, or navigation refactor is incomplete until
both types of contract pass.

## Project capture catalog

Every visible project card, including the featured card, must expose the actions
returned by `ProjectCatalogActionPolicy`.

| Project state | Required actions |
| --- | --- |
| Active Repeatable | Move, Archive, Delete |
| Archived Repeatable | Move, Unarchive, Delete |
| Active Astro | Archive, Delete |
| Archived Astro | Unarchive, Delete |

Additional invariants:

- Delete always requires explicit destructive confirmation.
- Archived projects are absent from Recent and With Captures.
- Archived projects remain recoverable from the Archived filter.
- Archive and unarchive update the catalog without deleting media.
- The actions menu remains available regardless of thumbnail orientation,
  thumbnail size, card hierarchy, or metadata layout.

The executable contract lives in
`CameraeNextProjectCatalogTests.projectCardCapabilities`. UI evidence remains
useful for visual approval, while this test protects the business capability
when the view hierarchy changes.

## Repeatable project organization

Organization is independent of capture type and project media. The catalog has
exactly two organization levels: group and subgroup. A project belongs to at
most one organization node.

Every visible group or subgroup card must expose the actions returned by
`ProjectOrganizationActionPolicy`.

| Organization state | Required actions |
| --- | --- |
| Active | Rename, Archive, Delete organization |
| Archived | Rename, Unarchive, Delete organization |

Additional invariants:

- Root groups appear before ungrouped projects.
- Subgroups appear before projects directly assigned to a group.
- A project can move to a root group, subgroup, or Ungrouped.
- Deleting a group also removes its subgroup organization and returns every
  descendant project to Ungrouped.
- Deleting a subgroup returns its projects to Ungrouped.
- Organization deletion never deletes a project directory, reference, capture,
  video, timelapse, export, or cache.
- Card mosaics show zero to four descendant project thumbnails and use `+N`
  when more projects exist.
- Menus remain reachable independently of mosaic geometry, image orientation,
  compact width, or iPad layout.

The executable contracts live in
`CameraeNextProjectCatalogTests.organizationHierarchy`,
`organizationCapabilities`, and `projectCardCapabilities`. The canonical Figma
component is `Project Group Card`; the paired light/dark iPhone and iPad Screens
are `10A` through `10R`.

## Repeatable capture catalog

Every Repeatable project can contain Photo, Video, and Timelapse captures.
Each visible capture card must expose a layout-independent type presentation:

| Capture type | Required SF Symbol |
| --- | --- |
| Photo | `camera.fill` |
| Video | `video.fill` |
| Timelapse | `timelapse` |

The executable contract lives in
`CameraeNextSessionCatalogTests.captureTypeIcon`. The corresponding light and
dark Figma Screens are `09B` and `09D`.

The first recorded video that contains a usable saved reference frame is the
project's geometric reference. Its capture card must expose playback, sharing,
and deletion, but must not offer alignment against itself.

Every later recorded video with available source media must expose:

- playback using the aligned export when one exists, otherwise the original;
- Process alignment against the project video reference;
- sharing of the default playback artifact;
- deletion through the project capture actions.

A legacy video without a saved reference frame cannot silently become the
geometric reference. The next oldest usable video becomes the reference
instead.

The executable capability contract lives in
`CameraeNextSessionCatalogTests.theReferenceVideoHidesAlignmentWhileLaterVideosRemainAlignable`.
The legacy fallback is protected by
`CameraeNextSessionCatalogTests.legacyVideoWithoutAReferenceFrameNeverBecomesTheAlignmentReference`.
The corresponding Figma Screen is
`05 · Repeatable — Projeto · Capturas · Referência + Alinháveis`.

## Project capture configuration

Every Repeatable project configuration must keep all three capture types
reachable. Changing capture type restores that type's last captured defaults,
which remain editable.

The physical camera and zoom become immutable when the first capture starts.
No subsequent Photo, Video, or Timelapse preset may change them.

The executable contract lives in
`CameraeNextWorkflowConfigurationTests.projectHardwareLockAndCaptureTypeDefaults`
and `projectCaptureKind`. The corresponding Figma components are
`Capture Type Selector`, `Capture Type Badge`, and the `Locked` variants of
`Camera Setup State`; the corresponding light and dark Screens are `09A` and
`09C`.

## Repeatable Spatial Guidance

Spatial Guidance is available only when the typed runtime policy accepts the
module, world tracking, classified scene reconstruction, scene depth,
performance budget, and thermal state. Layout must never be used to infer
eligibility.

An eligible Repeatable project must expose a Tripod tab with these
layout-independent capabilities:

| Project state | Required actions |
| --- | --- |
| No saved guide | Map location |
| Saved guide | Navigate scene, Map again |
| Saved guide on an incompatible device | Keep the guide discoverable, Continue without guide |

The creation flow must keep these actions reachable:

- start capture only after the first usable AR frame and explicit confirmation;
- restart the location from a clean tracking state;
- select and adjust the tripod-base center;
- accept the proposed camera direction or drag its fixed-length handle;
- save only after both points are confirmed;
- cancel without replacing a previously usable guide.

The return flow must keep cancellation and recovery reachable while hiding the
saved guide until relocalization is trustworthy. Once restored, it presents
only the tripod, direction, camera marker, and yellow plumb guide; reconstructed
mesh is not a navigation capability.

The executable contract lives in `SpatialGuidanceTests` and
`CameraeNextSessionCatalogTests`. The current Figma registry begins at
`682:148` on `05 · Spatial Guidance`.

## Change checklist

For every composed-screen change:

1. Identify existing required capabilities before editing the view.
2. Update the Figma Screen for each supported theme and relevant state.
3. Add or update the typed capability policy.
4. Write the failing capability test before changing the SwiftUI hierarchy.
5. Implement the view using the policy rather than duplicating action lists.
6. Run capability tests, relevant domain tests, build validation, and visual
   inspection.

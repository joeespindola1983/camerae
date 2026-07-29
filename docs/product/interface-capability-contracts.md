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
| Active | Archive, Delete |
| Archived | Unarchive, Delete |

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

## Change checklist

For every composed-screen change:

1. Identify existing required capabilities before editing the view.
2. Update the Figma Screen for each supported theme and relevant state.
3. Add or update the typed capability policy.
4. Write the failing capability test before changing the SwiftUI hierarchy.
5. Implement the view using the policy rather than duplicating action lists.
6. Run capability tests, relevant domain tests, build validation, and visual
   inspection.

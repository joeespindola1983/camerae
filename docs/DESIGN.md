# Camerae design

## Canonical Figma file

- File: [Camerae](https://www.figma.com/design/c8gsnSu31erYFG3u3QMQgN/Camerae?node-id=0-1)
- File key: `c8gsnSu31erYFG3u3QMQgN`
- Root node: `0:1`
- Foundations node: `18:2`

Product-interface work updates this existing file. Do not create a parallel
Figma file unless explicitly requested.

Figma is the visual source of truth for hierarchy, layout, themes, states, and
content. Typed interface-capability policies are the functional source of
truth for actions that must remain reachable. SwiftUI implements both
contracts.

## Page map

Page order follows the progression from foundations to reusable UI, domain
specifications, composed application screens, and separate web work.

| Page | ID | Responsibility |
| --- | --- | --- |
| `00 · Cover` | `0:1` | File identity and entry point. |
| `01 · Foundations` | `15:3` | Variables, text styles, effects, spacing, radii, and device dimensions. |
| `02 · Components` | `15:5` | Global components independent from a workflow or feature. |
| `03 · Workflow Components` | `157:2` | Shared configuration, state, and workflow controls. |
| `04 · Capture Assistance` | `213:10` | Live capture HUD, guides, grids, sensors, and capture panels. |
| `05 · Spatial Guidance` | `662:2` | Reserved domain for scene mapping, relocalization, ghost rig, and camera-pose guidance. |
| `06 · Editor Alignment` | `302:2` | Editor and Repeatable post-capture alignment components and states. |
| `07 · Settings Components` | `535:2` | Settings-specific reusable controls. |
| `08 · Astro Photo · Foundations` | `561:2` | Astro Photo domain foundations. |
| `09 · Astro Photo · Components` | `561:3` | Astro Photo domain components. |
| `10 · Astro Photo · Flow` | `561:4` | Astro Photo composed flow and states. |
| `11 · App Screens` | `15:7` | Canonical composed iOS application screens. |
| `12 · Capture Catalog Actions` | `599:2` | Capture-catalog action, cleanup, and destructive-confirmation flows. |
| `90 · Website · Components` | `489:2` | Website-only reusable components; not a SwiftUI source of truth. |
| `91 · Website · Hotsite` | `489:3` | Website-only composed pages. |

Renaming or reordering a page must not mutate its descendants. Component IDs
and screen IDs remain stable when only their owning page's name or position
changes.

### App Screens organization

Current application screens are grouped first by device class and then by
route:

- `iPhone · Current Screens`: 49 route states;
- `iPad · Current Screens` (`742:1389`): the same 49 route states;
- legacy and exploratory frames: separate from both current catalogs.

Every current route code must exist once in each device section. A screen
catalog audit must report no missing route codes, overlapping frames, clipped
frames, or duplicate current screen names. Device sections reuse the same
canonical component instances; they may adapt composition and constrained
content width without forking the component contract.

## Design hierarchy

The expected dependency direction is:

```text
Foundations
→ Components
→ Workflow or domain components
→ App Screens
→ Interface-capability contracts
→ SwiftUI
```

Domain pages can combine documentation, components, and reference flows when a
feature has a lifecycle that would make a general component page ambiguous.
Composed entry points that represent the shipping application still belong in
`11 · App Screens`.

## Component maturity

Figma assets have three maturity states:

- **Current:** approved for new screens and implementation.
- **Legacy:** retained for compatibility or migration evidence; not used by new
  work without an explicit reason.
- **Experimental:** exploratory and not an implementation contract.

Use `/ Legacy` in an asset name only for the legacy state. Experimental work
must live in a clearly named domain or exploration section until approved.
Replacing a legacy component requires a migration decision; page organization
alone never edits, detaches, or deletes its instances.

## Shared feature rule

A feature expected to serve more than one Camerae module uses neutral domain,
store, and component names. Module availability belongs to a typed capability
policy.

For example, the spatial camera-placement feature is `Spatial Guidance`, not
`Repeatable Ghost Tripod`. Repeatable is its first enabled consumer; Astro can
be enabled later without forking the feature. Its implementation plan lives in
[`repeatable-spatial-guidance-plan.md`](product/repeatable-spatial-guidance-plan.md).

## Screen and node registry

This document defines ownership and governance; it does not duplicate every
node in the Figma file. A feature document records its canonical component and
screen node IDs, supported states, capability policy, and corresponding tests.

Existing domain contracts include:

- [`interface-capability-contracts.md`](product/interface-capability-contracts.md)
- [`repeatable-video-alignment-validation-2026-07-29.md`](product/repeatable-video-alignment-validation-2026-07-29.md)
- [`repeatable-spatial-guidance-plan.md`](product/repeatable-spatial-guidance-plan.md)

### Video tutorials

- Reusable component: `Tutorial Video` (`692:104`) on
  `03 · Workflow Components`.
- States: Poster, Playing, Paused, Completed, and Unavailable.
- Editable properties: title and caption visibility. State-specific actions
  and fallback copy remain part of the typed tutorial contract.
- Tutorials explain a workflow before first use, but never replace operational
  state, safety, permission, progress, or recovery feedback.
- Completion is stored per tutorial content version. A completed tutorial is
  skipped on later first-use entry but remains reachable from contextual help.
- The first composed consumer is Spatial Guidance screen
  `CURRENT 02 · First-use Video Tutorial` (`695:158`) on
  `05 · Spatial Guidance`.

### Repeatable project organization

- Reusable component: `Project Card` (`723:132`) on
  `02 · Components`.
- Project-card variants: Repeatable or Astro workflow, each with Hero and Row
  roles. Both roles preserve the production 160-point thumbnail followed by
  information content, with a 244-point minimum card height.
- Project-card information is capture-derived: the first line lists only
  capture kinds that exist with their session counts, the camera used has a
  dedicated emphasized line, and the final line contains weekday, date, and
  time of the newest durable capture without an “Opened” prefix.
- The options control occupies the thumbnail trailing region while the project
  opening affordance occupies the information trailing region. They must never
  share an overlay or hit target. Group-detail screens on iPhone and iPad use
  instances of this same canonical component.
- Reusable component: `Project Group Card` (`647:82`) on
  `02 · Components`.
- Mosaic variants: Empty, 1, 2, 3, 4, and More.
- Editable properties: group name, kind, summary, updated date, and overflow
  count.
- Canonical composed examples: Screens `10A` through `10R` on
  `11 · App Screens`, covering root catalog, group detail, iPhone, iPad, light,
  dark, create/rename, move, action menu, safe deletion, and empty state.
- Deleting an organization is visually and functionally specified to preserve
  every project and media file.
- Reusable component: `Catalog Empty State` (`725:112`) on
  `02 · Components`.
- Empty-state variants: Repeatable or Astro workflow and Projects or Groups
  scope. The typed capability policy decides whether the recovery action is
  reachable; archived-group states intentionally expose no creation action.
- Canonical navigation uses `Navigation Header` (`709:35`), including
  `Catalog Toolbar` and `Catalog Detail Toolbar` (`727:92`) variants.
- First migrated catalog Screens:
  - root catalog `10A` (`650:767`);
  - group detail `10C` (`650:4040`);
  - empty catalog `10Q` (`653:4488`).

## Tokens and styles

The Figma file can contain exploratory and domain-local variables. The
versioned [`camerae.tokens.json`](../design/figma/camerae.tokens.json) is the
curated handoff contract for tokens consumed by production code; it is not
automatically an exhaustive dump of every local Figma variable.

Changes intended for SwiftUI follow the sync process in
[`design/figma/README.md`](../design/figma/README.md). A Figma-only variable
does not become a production contract until it is added to that manifest,
generated artifacts are refreshed, and relevant tests pass.

## Change workflow

For product-interface work:

1. Identify the owning page and existing capabilities.
2. Update the existing canonical Figma file.
3. Keep shared assets in the lowest reusable layer.
4. Record approved node IDs in the feature or capability document.
5. Write the failing capability or presentation test.
6. Implement without duplicating Figma action lists in SwiftUI.
7. Run relevant tests, build validation, and visual inspection.

Page cleanup is intentionally narrower: it may rename, reorder, or create an
empty reserved page, but it must not edit descendant nodes, components,
variants, variables, styles, or screen contents.

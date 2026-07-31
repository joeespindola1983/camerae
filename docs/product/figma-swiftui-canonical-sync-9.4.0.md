# Figma and SwiftUI canonical synchronization — 9.4.0

## Status

- Phase: `P7 · Complete`
- Branch: `codex/figma-swiftui-canonical-sync`
- Target: `9.4.0`
- Figma file: `c8gsnSu31erYFG3u3QMQgN`
- Phase 0 approved on 2026-07-30.

## Objective

Make composed Figma Screens consume canonical components that map directly to
tested SwiftUI components. Changes to navigation, project tabs, cards, badges,
and shared actions must propagate to composed Figma screens and remain
functionally reachable in SwiftUI.

The goal is not to turn every SwiftUI view into a Figma component. The goal is
to canonicalize the repeated structures whose divergence currently makes the
screen catalog unreliable.

## Phase 0 findings

### P0.a — SwiftUI inventory

The production implementation already has reusable types for:

- workflow themes and semantic colors;
- cards, action buttons, section labels, setting rows, camera selectors, and
  camera status;
- capture-planning, camera-setup, and reference states;
- capture-type selection and badges;
- project organization and project-group cards;
- project workspace tabs, including the conditional Tripod tab and capture
  count;
- segmented controls;
- tutorial video states;
- capture assistance, alignment, settings, and Spatial Guidance flows.

Navigation chrome is not centralized. Screens repeatedly declare
`navigationTitle`, inline-title mode, toolbar background, color scheme, and
toolbar items. This is valid SwiftUI composition, but there is no typed
presentation contract shared with the Figma `Screen Header`.

### P0.b — Figma inventory

The canonical file currently contains:

- 15 organized pages;
- 105 local variables in 4 collections;
- 9 text styles and 2 effect styles;
- 58 top-level App Screens;
- 155 component instances inside App Screens.

All local variables have explicit scopes. All variables in `Primitives`,
`Color`, and `Dimensions` have code syntax. Three of the 17 variables in
`Project List Theme` do not.

At discovery time, the `Color` collection exposed one `Default` mode even
though App Screens included explicit Light and Dark examples. The collection
then named `Project List Theme` modeled only `Repeatable` and `Astro`, while
SwiftUI also supported Editor.

The existing global component catalog contains:

- `Device Shell`;
- `Screen Header`;
- `Project Card`;
- `Action Button`;
- `Project Group Card`;
- `Project List Screen`.

The workflow catalog already contains the principal configuration controls and
state cards, plus `Capture Type Selector`, `Capture Type Badge`, and
`Tutorial Video`.

### P0.c — library inventory

The file is subscribed to:

- Apple's `iOS and iPadOS 26`;
- Material 3 Design Kit;
- Simple Design System;
- other Apple platform kits.

Camerae remains the source for product components. Apple's library is suitable
for system chrome and behavior reference. Material and Simple Design System
must not become visual dependencies of the iOS product.

The current Figma library search does not return importable iOS navigation
components for this file, so the synchronization cannot depend on remote
component keys.

## Gap analysis

### Exists in SwiftUI but not as a canonical Figma component

1. `Project Tabs`
   - Configuration, conditional Tripod, and Captures.
   - Tripod availability indicator.
   - Dynamic capture count.
2. `Segmented Control`
   - Used repeatedly in capture configuration.
3. A project-workspace shell that owns:
   - project title;
   - back navigation;
   - project tabs;
   - current tab content.
4. A typed navigation-header presentation shared by screen families.
5. Several production card primitives represented only as compositions or
   feature-local components in Figma.

### Exists in Figma but is not reliably consumed by Screens

1. `Screen Header`
   - Zero instances in `11 · App Screens`.
   - Existing screens draw their navigation/header content directly.
2. `Project List Screen`
   - Only two shared list instances; subsequent catalog states are independent
     frames.
3. `Project Card`
   - Older shared list examples use it, but newer group and project screens
     rely on separate local structures.
4. Workflow controls
   - Configuration screens use some instances, but their surrounding screen
     hierarchy and navigation remain detached.

### Conflicts requiring normalization

1. **Appearance versus workflow**
   - Figma mixes workflow modes and appearance examples.
   - SwiftUI has workflow themes, while Repeatable and Astro currently select
     different default color schemes.
   - Resolution: model `Workflow` and `Appearance` as separate component
     properties. Keep production semantic colors native where appropriate.
2. **Navigation**
   - Figma defines a custom `Screen Header`.
   - SwiftUI principally uses native `NavigationStack` chrome.
   - Resolution: the Figma component represents the native navigation contract;
     SwiftUI keeps native navigation instead of drawing a custom header.
3. **Typography**
   - Figma uses Outfit and DM Mono.
   - SwiftUI references those fonts by name, while the token contract says they
     require bundled licensed files before activation.
   - Resolution: audit bundled fonts before changing typography. Do not
     substitute or activate fonts during component synchronization.
4. **Tokens**
   - Figma has 105 variables; the versioned token manifest is intentionally
     curated and smaller.
   - Resolution: keep the manifest curated. Only variables consumed by SwiftUI
     enter `camerae.tokens.json`.

## Proposed 9.4.0 canonical scope

### Tier 1 — application structure

1. `Navigation Header`
2. `Project Workspace`
3. `Project Tabs`
4. `Screen Background / Content Container`

### Tier 2 — project catalogs

1. `Project Card`
2. `Project Group Card`
3. `Project Catalog Toolbar`
4. `Catalog Empty State`
5. `Capture Type Badge`

### Tier 3 — shared controls

1. `Action Button`
2. `Segmented Control`
3. `Setting Row`
4. `Status Card`
5. `Reference Frame Card`

### Screens to migrate first

1. Repeatable project workspace:
   - Configuration;
   - Tripod;
   - Captures.
2. Repeatable project catalog:
   - root;
   - group detail;
   - empty state.
3. New-project and capture-configuration screens.

Astro and Editor must consume shared components where already compatible, but
full Astro processing, alignment, Settings, and capture HUD screen migrations
are outside the first 9.4.0 slice unless a shared-component change requires
them.

## Phase 1 foundation result

The approved foundation normalization was applied directly to the canonical
Figma file:

- renamed `Project List Theme` to `Workflow Theme` without replacing the
  collection or changing its stable ID;
- added an `Editor` mode using aliases to existing primitive and semantic
  variables;
- retained the existing Repeatable and Astro mode IDs and values;
- completed missing Web and iOS code syntax for capture success, danger, and
  grid-line variables;
- completed missing Web syntax for planet, nebula, and galaxy colors;
- aligned theme-variable iOS syntax with `CameraeNextTheme`.

Validation after the change confirms:

- 4 collections and 105 variables;
- no `ALL_SCOPES` variables;
- no missing Web or iOS syntax;
- no missing values in any collection mode;
- `Workflow Theme` modes are `Repeatable`, `Astro`, and `Editor`.

`Color` intentionally remains a single-mode semantic collection. The current
production contract does not offer a global appearance switch: Repeatable uses
its approved light palette, Astro uses its approved dark palette, and Editor
uses its own dark palette. Light and Dark remain explicit component or Screen
properties where both visual examples are required. Adding global color modes
before production supports them would create a false handoff contract.

## Planned delivery sequence after approval

1. `P1` — normalize only the required token and style foundations.
2. `P2` — preserve the current page map and add component documentation
   structure without deleting historical evidence.
3. `P3` — create or repair one canonical component at a time, with metadata and
   visual validation after each component.
4. `P4` — rebuild the selected Screens from component instances.
5. `P5` — write failing Swift capability and presentation tests.
6. `P6` — refactor SwiftUI to consume the approved presentation contracts.
7. `P7` — run capability tests, integration tests, build validation, and Figma
   audits.

## Canonical component registry

### Project Tabs

- Figma component set: `Project Tabs` (`706:60`)
- Documentation: `Project Tabs / Documentation` (`707:2`)
- Owning page: `02 · Components` (`15:5`)
- SwiftUI mapping:
  - `CameraeNextProjectTabs`
  - `CameraeNextProjectTabPresentation`
- Variant contract:
  - `Layout`: Standard or Spatial
  - `Guide`: Unavailable, Missing, or Saved
  - `Selection`: Configuration, Tripod, or Captures
- Editable text:
  - Configuration label
  - Tripod label
  - Captures label, including the current count

The eight valid variants intentionally omit impossible combinations. A
Standard workspace cannot select Tripod, and Spatial variants distinguish a
missing guide from a saved guide.

### Navigation Header

- Figma component set: `Navigation Header` (`709:35`)
- Documentation: `Navigation Header / Documentation` (`710:2`)
- Owning page: `02 · Components` (`15:5`)
- SwiftUI mapping:
  - native `NavigationStack` title and toolbar composition
  - typed presentation contracts to be introduced under TDD
- Variant contract:
  - Root
  - Catalog Toolbar
  - Detail
  - Detail Action
  - Modal
- Editable text:
  - title
  - leading label
  - trailing label

This component documents the native iOS navigation contract. It does not
authorize replacing `NavigationStack` with a custom-drawn header. The previous
hero-style `Screen Header` was retained as `Screen Header / Legacy` (`24:2`) so
historical evidence remains available without competing with the production
contract.

### Project Workspace Chrome

- Figma component set: `Project Workspace Chrome` (`712:116`)
- Documentation: `Project Workspace Chrome / Documentation` (`713:92`)
- Owning page: `02 · Components` (`15:5`)
- Composed canonical instances:
  - `Navigation Header`
  - `Project Tabs`
- Variant contract:
  - the same eight valid Layout, Guide, and Selection combinations exposed by
    `Project Tabs`
- Nested instance properties:
  - project title
  - tab labels
  - capture count

The nested instances are exposed so Screens can change project-specific text
without detaching either canonical component.

## Phase 4 first screen migration

The first Repeatable workspace family in `11 · App Screens` now consumes
`Project Workspace Chrome`:

- Configuration: `09A · Repeatable — Projeto · Configurar · Spatial · Light`
  (`636:719`)
- Captures: `09B · Repeatable — Projeto · Capturas (3) · Spatial · Light`
  (`636:837`)
- Tripod: `09C · Repeatable — Projeto · Tripé salvo · Spatial · Light`
  (`718:1321`)

All three screens retain the project title, expose the conditional Tripod tab,
show the saved-guide indicator, and use the same capture count. The Tripod
screen reuses the approved saved-guide body from the Spatial Guidance
documentation while replacing its obsolete text-only navigation with canonical
instances.

The former Repeatable Dark screens were renamed as `LEGACY` exploration rather
than migrated. Repeatable has no production Dark appearance contract, so
presenting those frames as current Screens would contradict both SwiftUI and
the normalized Figma theme model.

## Phase 5–6 first SwiftUI integration

The Repeatable workspace now exposes:

- `CameraeNextProjectWorkspaceAction`;
- `CameraeNextProjectWorkspaceCapabilityPolicy`;
- `CameraeNextProjectWorkspacePresentation`;
- tab presentations that retain their typed project section.

The capability tests prove that Configurar and Capturas are always reachable,
that Tripé is exposed on capable devices, and that an already-saved guide
remains reachable if the current device is incompatible. Presentation tests
also prove project-title retention, canonical tab order, saved-guide status,
and capture count without inspecting SwiftUI geometry.

`CameraeNextProjectRuntimeView` and `CameraeNextProjectTabs` consume this
presentation directly. Native `NavigationStack` remains responsible for the
actual iOS navigation chrome.

Validation on 2026-07-30:

- `CameraeNextSessionCatalogTests`: 30 tests passed;
- generic iOS `build-for-testing`: succeeded.

## Catalog canonicalization

The project catalog now has these canonical components:

- `Project Card` (`723:132`), documented by `728:1428`;
- `Project Group Card` (`647:82`);
- `Catalog Empty State` (`725:112`), documented by `728:1441`;
- `Navigation Header` (`709:35`), extended with
  `Catalog Detail Toolbar` (`727:92`).

The former 148-point `Project Card` was retained as `Project Card / Legacy`
(`26:18`). The replacement matches `ProjectListHeroCard` and `ProjectListRow`
with explicit Workflow and Role variants, a 160-point thumbnail, and a
244-point minimum height.

The first catalog Screen slice now consumes canonical instances:

- root catalog `10A` (`650:767`);
- group detail `10C` (`650:4040`);
- group empty state `10Q` (`653:4488`).

SwiftUI now exposes `CameraeNextProjectCatalogCapabilityPolicy` and
`CameraeNextCatalogEmptyStatePresentation`. Tests prove that filter, sort,
group creation, and project creation remain reachable for the applicable
workflow, and that archived groups do not expose an invalid create action.

Validation:

- `CameraeNextProjectCatalogTests`: 13 tests passed.

## Final App Screens audit

`11 · App Screens` is now organized into explicit iPhone and iPad sections,
with legacy explorations kept separate from the current screen catalog.

- iPhone: 49 current route states;
- iPad: 49 corresponding route states;
- missing route codes: none;
- overlapping frames: none;
- clipped frames: none;
- duplicate current screen names: none.

The iPad catalog mirrors the complete iPhone route vocabulary instead of
mixing a partial tablet sample among phone screens. Tablet compositions use
the same canonical components and preserve their native adaptive presentation,
including 620-point primary content widths and 700-point settings content
widths where constrained reading width is appropriate.

The audited iPad section is `iPad · Current Screens` (`742:1389`). Expanding
the Figma catalog to full device parity did not expand the approved SwiftUI
scope: existing native adaptive containers already provide the device
geometry, while the typed capability and presentation policies protect the
shared behavior.

Final validation on 2026-07-30:

- Figma route and layout audit: 49 iPhone states and 49 iPad states passed;
- `CameraeNextProjectCatalogTests`: 13 tests passed;
- `CameraeNextSessionCatalogTests`: 30 tests passed;
- selected test run: 43 tests passed.

## Acceptance criteria

- Changing a canonical project tab, card, badge, or action component updates
  every migrated Figma Screen instance.
- Project title, back navigation, Tripod availability, and capture count are
  visible in the appropriate screen contracts.
- SwiftUI capability tests prove required actions without relying on pixel
  geometry.
- Figma component variants and Swift presentation states use the same finite
  vocabulary.
- No production screen depends on legacy Figma components.
- No existing user project or persistent schema is changed by this work.

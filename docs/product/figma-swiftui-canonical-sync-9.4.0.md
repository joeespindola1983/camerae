# Figma and SwiftUI canonical synchronization — 9.4.0

## Status

- Phase: `P0 · Discovery`
- Branch: `codex/figma-swiftui-canonical-sync`
- Target: `9.4.0`
- Figma file: `c8gsnSu31erYFG3u3QMQgN`
- No Figma or SwiftUI mutation is authorized by this document until the Phase 0
  scope is approved.

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

The `Color` collection exposes one `Default` mode even though App Screens
include explicit Light and Dark examples. `Project List Theme` models workflow
as modes (`Repeatable`, `Astro`), while SwiftUI models workflow separately from
light/dark appearance.

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

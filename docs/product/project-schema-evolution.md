# Project schema evolution

Camerae projects are long-lived documents. A view must not need to know which
app version created a project.

## Boundary

Persistent files are decoded and normalized before they reach SwiftUI:

`legacy files → versioned store/resolver → current project model → view`

SwiftUI consumes only the current model. It may render whether a value is
locked, but it must not inspect old filenames, manifests, schema versions, or
fallback rules.

## Capture configuration

`capture_configuration.json` separates the immutable hardware contract from
editable defaults for each capture type.

- New projects keep camera hardware provisional while the user previews lenses.
  The physical camera lens and zoom become immutable only after the first
  capture produces media; an empty attempt does not establish a contract.
- Photo, Timelapse, and Video each keep an independent editable preset. Starting
  a capture updates only that type's preset and makes it the next preselected
  type.
- Captured legacy projects without the document infer recoverable fields from
  their earliest captured session and persist them once with origin
  `migratedLegacy`.
- Schema 1 and 2 configuration documents migrate idempotently to the current
  profile. Schema 3 profiles infer whether their stored hardware was provisional
  or confirmed from actual captured sessions. Their original configuration
  becomes the matching type preset while deterministic defaults populate the
  other two types.
- Empty legacy projects remain configurable because no capture contract exists.
- Later sessions cannot replace the hardware contract, but may update their own
  capture-type defaults.
- Documents created by a newer unsupported schema fail closed instead of being
  overwritten.

Historical manifests can recover capture kind, camera lens, zoom, observed
duration, approximate interval, source image format, and Astro stack size.
Fields absent from old manifests use deterministic module defaults. Migration
must never claim that an unavailable historical value was measured.

## Required migration tests

Every persistent schema evolution covers:

1. Current-version round trip.
2. Supported older-version decode.
3. One-time idempotent migration.
4. Empty legacy state.
5. Unsupported newer-version rejection.
6. Hardware immutability and per-type default independence after normalization.

## Project organization

Groups are stored in the independent, authoritative
`project-organization-v1.json` document under Camerae Application Support.
Project manifests and media directories are not rewritten merely to organize a
catalog.

- Absence of the organization document is the empty current state. Therefore
  every pre-feature project opens normally in Ungrouped.
- Membership stores only stable project and organization UUIDs.
- The resolver accepts roots and one subgroup level, removes duplicate or
  orphaned nodes, removes memberships for missing projects, and rejects
  cross-module membership before the snapshot reaches SwiftUI.
- Normalization is idempotent and persists the current representation once.
- Unsupported newer schemas fail closed and are not replaced with an empty
  document.
- Deleting an organization removes its logical subtree and memberships only.
  Project manifests, directories, references, captures, videos, timelapses,
  exports, and cache remain untouched.

Because no historical organization file existed before schema 1, there is no
heuristic legacy grouping migration. Inventing groups from project names or
locations would risk incorrect organization. Existing projects intentionally
remain visible in Ungrouped until the user moves them.

The persistence and migration boundary is covered by
`ProjectOrganizationDocumentTests` and `ProjectOrganizationCatalogTests`.

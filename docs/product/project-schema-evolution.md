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

- New captured projects lock the physical camera lens and zoom selected for the
  first capture.
- Photo, Timelapse, and Video each keep an independent editable preset. Starting
  a capture updates only that type's preset and makes it the next preselected
  type.
- Captured legacy projects without the document infer recoverable fields from
  their earliest captured session and persist them once with origin
  `migratedLegacy`.
- Schema 1 and 2 configuration documents migrate idempotently to the schema 3
  profile. Their original configuration becomes the matching type preset while
  deterministic defaults populate the other two types.
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

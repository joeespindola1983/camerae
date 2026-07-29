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

`capture_configuration.json` is the immutable capture contract for a project.

- New captured projects persist the initial configuration with origin
  `initialCapture`.
- Captured legacy projects without the document infer recoverable fields from
  their earliest captured session and persist them once with origin
  `migratedLegacy`.
- Empty legacy projects remain configurable because no capture contract exists.
- Once written, later sessions cannot replace the project configuration.
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
6. Immutability after normalization.

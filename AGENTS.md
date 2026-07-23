# Camerae repository workflow

These rules apply to every code or product change in this repository.

## Development source

- Start all normal development from an up-to-date `develop`.
- Before editing, verify the current branch and synchronize it with `origin/develop` using a fast-forward-only pull.
- Direct commits to `develop` are allowed while the project has a single developer. Pull requests and short-lived `codex/*` branches are optional.
- Never start product development from `main`, `qa`, or `release/*`.
- `main` contains approved production history only.
- `qa` is a deployment target only.
- `release/vX.Y.Z` is used only while version `X.Y.Z` is being stabilized.

## Promotion

- Promote a release candidate to `qa` for Firebase validation and use a `vX.Y.Z-qa.N` tag for that exact candidate.
- Once QA approves a candidate, fast-forward or merge that release commit into `develop` before starting or continuing other product work.
- Stabilization fixes remain on the active `release/*` branch and must be reconciled into both `qa` and `develop` after every subsequent QA approval.
- Once production approves the release, promote the exact approved commit to `main`, create the final annotated `vX.Y.Z` tag, and align `develop` and `qa` to contain that commit.
- Do not rewrite published branch or tag history.

## Verification

- Use TDD for product changes.
- Run the relevant tests before committing.
- Add user-visible and release-process changes to `CHANGELOG.md` under `Unreleased`.
- Before creating a production tag, move the applicable `Unreleased` entries into a dated `X.Y.Z` section with status and affected areas.
- Run `ios/scripts/release-gate.sh` for release validation and publication.
- Before starting the next version, confirm the latest production tag is reachable from `main`, `develop`, and `qa`.

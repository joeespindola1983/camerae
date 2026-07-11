# Camerae GitFlow

Camerae uses a lightweight GitFlow aimed at keeping tester builds and release candidates visible without slowing local iteration.

## Branches

- `main`: integration branch for completed work.
- `qa`: stabilization branch for Firebase App Distribution tester builds.
- `release/*`: release candidate branches, for example `release/v2.1.0`.
- `feature/*` or `codex/*`: short-lived implementation branches.

## Flow

1. Land completed work into `main`.
2. Merge or fast-forward `main` into `qa` when a tester build is needed.
3. Cut `release/vX.Y.Z` from `qa` when QA approves the build.
4. Bump versions and finalize release notes on the release branch.
5. Tag the release as `vX.Y.Z`.
6. Merge the release branch back to `main` and `qa`.

## CI

GitHub Actions runs iOS and Android builds on:

- pushes to `main`, `qa`, and `release/**`;
- pull requests targeting `main`, `qa`, and `release/**`;
- tags matching `v*`;
- manual `workflow_dispatch`.

The iOS workflow runs `pod install` and builds `Camerae.xcworkspace`. Building `Camerae.xcodeproj` directly will miss CocoaPods dependencies and fail in CI.

## App Store Connect Plan

Release branches are the right place for future App Store Connect automation. The upload workflow should be added only after these secrets are configured:

- App Store Connect API key id.
- App Store Connect issuer id.
- App Store Connect private key.
- Distribution certificate.
- Provisioning profile for `com.espindola.camerae`.

Until then, release branches validate archive/build readiness, and Firebase tester distribution remains available through `ios/scripts/distribute-firebase.sh`.

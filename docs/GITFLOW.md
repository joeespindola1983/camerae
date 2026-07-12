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

GitHub Actions runs iOS builds on:

- pushes to `main`, `qa`, and `release/**`;
- pull requests targeting `main`, `qa`, and `release/**`;
- tags matching `v*`;
- manual `workflow_dispatch`.

The iOS workflow runs `pod install` and builds `Camerae.xcworkspace`. Building `Camerae.xcodeproj` directly will miss CocoaPods dependencies and fail in CI.

Android automation is intentionally paused while Camerae is developed and validated on iOS.

## Distribution Automation

Additional iOS distribution workflows are branch-based:

- `qa`: archives the app and distributes the IPA to the Firebase App Distribution `testers` group.
- `release/**`: archives the app and uploads it to App Store Connect.

Required GitHub Actions secrets:

- `APPLE_TEAM_ID`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- `FIREBASE_APP_ID`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_GROUPS`
- `FIREBASE_TOKEN`

The workflows use Xcode automatic signing with the App Store Connect API key. If the first signed archive fails, confirm that the bundle id `com.espindola.camerae` exists in Apple Developer and that the API key has access to manage signing assets.

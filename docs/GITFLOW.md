# Camerae GitFlow

Camerae uses a lightweight GitFlow that separates ongoing integration, tester builds, release stabilization, and published production history.

## Branches

- `main`: immutable line of approved production releases.
- `develop`: integration branch and base for the next version.
- `qa`: environment branch used to generate Firebase App Distribution builds from an active release candidate.
- `release/*`: stabilization branches cut from `develop`, for example `release/v5.0.0`.
- `feature/*` or `codex/*`: short-lived implementation branches.
- `hotfix/*`: urgent production fixes cut from `main`.

## Invariants

- Feature branches start from current `develop` and merge back to `develop`.
- `qa` is a deployment target, never the source branch for features or the next release.
- Release fixes are committed to `release/*`, promoted again to `qa`, and returned to `develop` when the release closes.
- `main`, `qa`, and `develop` must all contain the approved production release before development of the following version proceeds.
- A production tag points to the exact approved release commit.
- Never commit feature work directly to `main` or `qa`.

## Flow

1. Create `feature/*` or `codex/*` from `develop` and merge completed work back to `develop`.
2. Cut `release/vX.Y.Z` from `develop` when the version enters stabilization.
3. Bump versions, finalize release notes, and merge or fast-forward the release candidate into `qa`.
4. Validate the Firebase build generated from `qa`.
5. Apply every stabilization fix to `release/vX.Y.Z`, update `qa`, and repeat validation.
6. After approval, merge the release into `main` and tag that exact commit as `vX.Y.Z`.
7. Merge the approved release back into `develop` and align `qa` with the approved release commit.
8. Verify that the tag is reachable from `main`, `qa`, and `develop` before starting the next version.

QA builds that are not production releases may use prerelease tags such as `vX.Y.Z-qa.N`. Merely setting `MARKETING_VERSION` to `X.Y.Z` on `qa` does not make that commit the final tagged release.

Hotfixes start from `main`, are released and tagged through the same validation gates, and are merged back into both `develop` and `qa`.

If product work is committed directly to `qa`, stop new development, reconcile its history through a release branch, validate it, promote it to `main`, and recreate or update `develop` from the approved release before continuing.

## CI

GitHub Actions runs iOS builds on:

- pushes to `main`, `develop`, `qa`, and `release/**`;
- pull requests targeting `main`, `develop`, `qa`, and `release/**`;
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

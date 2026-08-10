# iOS QA and production environments

Camerae keeps the App Store application and local/tester builds installed as
independent iOS applications.

| Environment | Scheme | Configuration | Bundle ID | Display name | Firebase app |
| --- | --- | --- | --- | --- | --- |
| Local development | `Camerae QA` | `Debug` | `com.espindola.camerae.qa` | Camerae QA | QA |
| Firebase testers | `Camerae QA` | `QA` | `com.espindola.camerae.qa` | Camerae QA | QA |
| App Store/TestFlight | `Camerae` | `Release` | `com.espindola.camerae` | Camerae | Production |

`Debug` intentionally uses the QA identity. Running the project from Xcode must
never replace the application installed from the App Store. QA builds also use a
dedicated icon with a visible `QA` badge; Release retains the unmodified
production icon.

## Firebase configuration

The canonical Firebase App Distribution group for Camerae QA is `testers`.
`ios/scripts/distribute-firebase.sh` uses it by default, and the manual GitHub
workflow declares it explicitly. Override `FIREBASE_GROUPS` only for an
intentional, documented distribution migration.

The repository stores the public Firebase client configuration for each
registered iOS application:

- `ios/Config/Firebase/QA/GoogleService-Info.plist`
- `ios/Config/Firebase/Production/GoogleService-Info.plist`

The `Select Firebase Environment` build phase copies exactly one file into the
application bundle as `GoogleService-Info.plist`. It compares the plist
`BUNDLE_ID` with `PRODUCT_BUNDLE_IDENTIFIER` and fails the build on a mismatch.

Firebase App Distribution additionally inspects the exported IPA and checks its
bundle identifier and Firebase app ID before upload. App Store uploads inspect
the archive and reject a QA bundle.

## Local signing assets

Signing files are local machine assets and must never enter Git.

| Purpose | Profile | Expected behavior |
| --- | --- | --- |
| Run from Xcode | Automatically managed | Xcode selects or creates a development profile for team `V6JPGVRWCS` |
| Firebase App Distribution | Camerae QA Ad Hoc | Distribution profile containing every tester UDID |
| QA TestFlight, if introduced later | Camerae QA App Store | App Store profile; not valid for direct Firebase installation |
| Production | Existing Camerae production profiles | Used only by Release/App Store workflows |

Install downloaded profiles through Xcode or place them in Xcode's local
Provisioning Profiles directory using their profile UUID. Keep certificates,
private keys, `.p8`, `.p12`, and `.mobileprovision` files outside the repository.

The repository supplies the Camerae team and automatic-signing defaults. The
local ignored file `ios/Config/Signing.local.xcconfig` may override them only
when a developer intentionally needs a different team:

```text
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

## Development and QA flow

1. Start a short-lived branch from synchronized `develop`.
2. Add or update tests before implementation.
3. Open a pull request into `develop`.
4. Cut `release/vX.Y.Z` from the approved merge commit.
5. Promote the exact release candidate to `qa` and tag it `vX.Y.Z-qa.N`.
6. Run `ios/scripts/release-gate.sh firebase --publish`.
7. Confirm that Camerae and Camerae QA coexist on a registered iPhone.
8. Validate Crashlytics/Analytics isolation and diagnostics opt-out.
9. Reconcile the approved release commit into `develop`.
10. Promote that exact commit to `main` only after production approval.

Every Firebase publication requires detailed release notes. UI evidence remains
opt-in unless the candidate changes visible interface behavior.

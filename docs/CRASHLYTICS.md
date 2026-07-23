# Firebase Crashlytics

Camerae uses Firebase Crashlytics and Analytics to improve stability and understand aggregate feature usage. Both are controlled by the same in-app privacy settings and can be disabled at any time.

## Collection policy

| Build | Collection | Release channel |
| --- | --- | --- |
| Debug and automated tests | Disabled regardless of the saved preference | `debug` |
| Firebase App Distribution | Enabled by default, with opt-out | `qa` |
| App Store and TestFlight | Enabled by default, with opt-out | `release` |

`FirebaseCrashlyticsCollectionEnabled` and `FIREBASE_ANALYTICS_COLLECTION_ENABLED` remain disabled in `Info.plist`. Camerae applies the saved consent before enabling either SDK. The build policy still prevents Debug and automated tests from reporting even if the visual preference is enabled.

## Data scope

Firebase Crashlytics, Analytics, and their required dependencies can transmit:

- crash stack traces and relevant application state;
- device model and operating-system information;
- application version, build, and release channel;
- Firebase Sessions metadata used to group stability reports;
- the currently selected high-level Camerae module: `app`, `repeatable`, `astro`, or `edit`.
- aggregate application interaction and feature-usage events collected by Firebase Analytics.

Camerae does not attach:

- user IDs, names, email addresses, or account information;
- project names or identifiers;
- filenames, filesystem paths, or free-form error messages;
- photos, videos, thumbnails, reference frames, or processing inputs;
- precise or coarse location;
- camera metadata entered or captured by the user;
- advertising identifiers, advertising personalization, or user-profile properties configured by Camerae.

Only values defined by `CameraeDiagnosticModule` and the fixed application/build keys may be attached to crash reports. Camerae does not call `setUserID`. New Analytics events, user properties, custom crash keys, or logs require a privacy review and tests before release.

## Integration

- Dependencies: `FirebaseCrashlytics` and `FirebaseAnalytics` through the locked CocoaPods workspace.
- Initialization: after `FirebaseApp.configure()` in `CameraeAppDelegate`.
- Debug symbols: the Firebase upload script runs only for Release builds.
- Linkage: the application uses the generated CocoaPods embed-framework phase and must be built from `Camerae.xcworkspace`.
- Privacy manifests: Firebase-provided manifests are embedded through CocoaPods.

The QA archive overrides `CAMERAE_RELEASE_CHANNEL` to `qa`. App Store archives use `release`.

## Verification before QA

1. Run `pod install --deployment`.
2. Run the Crashlytics integration tests.
3. Build the generic iOS device target from `Camerae.xcworkspace`.
4. Inspect the built application and confirm `FirebaseCrashlytics.framework` and its transitive frameworks exist under `Camerae.app/Frameworks`.
5. Create a signed QA archive and confirm the Crashlytics symbol-upload build phase succeeds.
6. Use a controlled Firebase test crash on a QA-only build and relaunch it.
7. Confirm the issue appears symbolicated in Firebase Crashlytics.
8. Confirm no project, media, path, location, or user data appears in its keys, events, or logs.
9. Disable diagnostics in Settings, relaunch, and confirm both collection paths remain disabled.

The controlled test crash must not remain reachable in a production build.

## App Store and public policy

Before releasing the first Crashlytics-enabled version:

- update the public privacy policy to describe Firebase diagnostics;
- update App Store Connect App Privacy answers for the actual data collected by the bundled Firebase targets;
- include crash and diagnostic data used for app functionality;
- review the Firebase data-disclosure documentation again against the locked SDK version;
- declare Analytics and diagnostics according to the data actually collected by the locked Firebase SDK and Camerae configuration.

The App Store privacy answers must describe the released binary, not a previous build or a planned future integration.

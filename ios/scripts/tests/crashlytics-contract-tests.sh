#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

fail() {
  echo "Crashlytics contract failed: $*" >&2
  exit 1
}

rg -q "pod 'FirebaseCrashlytics'" "$IOS_DIR/Podfile" \
  || fail "Podfile must include FirebaseCrashlytics"
rg -q "pod 'FirebaseAnalytics'" "$IOS_DIR/Podfile" \
  || fail "Podfile must include FirebaseAnalytics"

rg -q 'FirebaseCrashlyticsCollectionEnabled: false' "$IOS_DIR/project.yml" \
  || fail "automatic Crashlytics collection must default to disabled"
rg -q 'FIREBASE_ANALYTICS_COLLECTION_ENABLED: false' "$IOS_DIR/project.yml" \
  || fail "automatic Analytics collection must default to disabled"
rg -q 'CameraeCrashlyticsCollectionEnabled: \$\(CAMERAE_CRASHLYTICS_COLLECTION_ENABLED\)' "$IOS_DIR/project.yml" \
  || fail "runtime collection policy must come from the build configuration"
rg -q 'CAMERAE_CRASHLYTICS_COLLECTION_ENABLED = NO' "$IOS_DIR/Config/Debug.xcconfig" \
  || fail "Debug collection must be disabled"
rg -q 'CAMERAE_CRASHLYTICS_COLLECTION_ENABLED = YES' "$IOS_DIR/Config/Release.xcconfig" \
  || fail "Release collection must be enabled"
rg -q 'CAMERAE_RELEASE_CHANNEL=qa' "$IOS_DIR/scripts/distribute-firebase.sh" \
  || fail "Firebase distribution must identify QA reports"
rg -q 'setAnalyticsCollectionEnabled' "$IOS_DIR/Camerae/Diagnostics/CameraeDiagnosticsConsent.swift" \
  || fail "Analytics collection must be controlled by runtime consent"
rg -q 'isCollectionAllowed && state.analyticsEnabled' "$IOS_DIR/Camerae/Diagnostics/CameraeDiagnosticsConsent.swift" \
  || fail "Analytics consent must remain constrained by the build policy"

rg -q 'FirebaseCrashlytics/run' "$IOS_DIR/project.yml" \
  || fail "Release builds must upload dSYM files"
rg -q 'if \[ "\$\{CONFIGURATION\}" = "Release" \]' "$IOS_DIR/project.yml" \
  || fail "dSYM upload must be restricted to Release builds"

if rg -q 'setUserID|setUserId' "$IOS_DIR/Camerae"; then
  fail "Camerae must not attach user identifiers to crash reports"
fi

echo "Crashlytics contract tests passed"

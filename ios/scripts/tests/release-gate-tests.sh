#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/release-gate.sh"
IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT_DIR="$(cd "$IOS_DIR/.." && pwd)"
VERSION="$(awk -F '"' '/MARKETING_VERSION:/ { print $2; exit }' "$IOS_DIR/project.yml")"
BUILD="$(awk -F '"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$IOS_DIR/project.yml")"

expect_contains() {
  local output="$1"
  local expected="$2"
  if [[ "$output" != *"$expected"* ]]; then
    echo "Expected output to contain: $expected" >&2
    echo "$output" >&2
    exit 1
  fi
}

check_plan="$($SCRIPT check --plan)"
expect_contains "$check_plan" "mode: check"
expect_contains "$check_plan" "publish: no"
expect_contains "$check_plan" "git: clean, synchronized commit"
expect_contains "$check_plan" "tests: localization, Crashlytics privacy, architecture, Swift, Camerae Processing, Camerae Vision"
expect_contains "$check_plan" "visual evidence: skipped; enable with --ui-evidence"
expect_contains "$check_plan" "OpenCV XCFramework: pinned 4.13.0, device and simulator slices"

ui_evidence_plan="$($SCRIPT check --plan --ui-evidence)"
expect_contains "$ui_evidence_plan" "visual evidence: enabled; six locales on iPhone and iPad, archived under docs/ui-evidence"

firebase_plan="$($SCRIPT firebase --plan --publish)"
expect_contains "$firebase_plan" "mode: firebase"
expect_contains "$firebase_plan" "required branch: qa"
expect_contains "$firebase_plan" "publish: yes"
expect_contains "$firebase_plan" "destination: Firebase App Distribution"

appstore_plan="$($SCRIPT appstore --plan --publish)"
expect_contains "$appstore_plan" "mode: appstore"
expect_contains "$appstore_plan" "required branch: release/*"
expect_contains "$appstore_plan" "publish: yes"
expect_contains "$appstore_plan" "destination: App Store Connect"

set +e
missing_publish_output="$($SCRIPT firebase --plan 2>&1)"
missing_publish_status=$?
set -e
if [[ $missing_publish_status -eq 0 ]]; then
  echo "Firebase publication must require --publish" >&2
  exit 1
fi
expect_contains "$missing_publish_output" "requires --publish"

if ! rg -q 'ALLOW_PROVISIONING_UPDATES="\$\{ALLOW_PROVISIONING_UPDATES:-0\}"' "$IOS_DIR/scripts/distribute-firebase.sh"; then
  echo "Firebase distribution must disable provisioning updates by default" >&2
  exit 1
fi
if ! rg -q 'CAMERAE_RELEASE_CHANNEL=qa' "$IOS_DIR/scripts/distribute-firebase.sh"; then
  echo "Firebase archives must identify the QA release channel" >&2
  exit 1
fi
if ! rg -q 'ALLOW_PROVISIONING_UPDATES="\$\{ALLOW_PROVISIONING_UPDATES:-0\}"' "$IOS_DIR/scripts/upload-appstore.sh"; then
  echo "App Store upload must disable provisioning updates by default" >&2
  exit 1
fi
if rg -n '^ +"\$\{(provisioning_args|build_settings)\[@\]\}" \\$' "$IOS_DIR/scripts/distribute-firebase.sh"; then
  echo "Firebase distribution must not expand optional empty arrays under set -u" >&2
  exit 1
fi
if rg -n '^  (push|pull_request):' "$ROOT_DIR/.github/workflows"/*.yml; then
  echo "Release workflows must not run automatically" >&2
  exit 1
fi
if ! rg -q 'verify-opencv-xcframework\.sh' "$SCRIPT"; then
  echo "Release gate must verify the pinned OpenCV XCFramework" >&2
  exit 1
fi
if ! rg -q 'CameraeVisionTests' "$IOS_DIR/project.yml"; then
  echo "Camerae scheme must include the CameraeVision bridge tests" >&2
  exit 1
fi
if ! rg -q 'generate-ui-evidence\.sh' "$SCRIPT"; then
  echo "Release gate must generate simulator UI evidence" >&2
  exit 1
fi
if ! rg -q 'localization-tests\.sh' "$SCRIPT"; then
  echo "Release gate must validate localization catalogs" >&2
  exit 1
fi
if ! rg -q 'crashlytics-contract-tests\.sh' "$SCRIPT"; then
  echo "Release gate must validate Crashlytics privacy and build settings" >&2
  exit 1
fi
if ! rg -q 'CHANGELOG\.md' "$SCRIPT"; then
  echo "Release gate must validate the versioned changelog" >&2
  exit 1
fi
if ! rg -q "^## \[$VERSION\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$ROOT_DIR/CHANGELOG.md"; then
  echo "Changelog must contain a dated entry for Camerae $VERSION" >&2
  exit 1
fi
if ! rg -q -- '--archive-tracked' "$SCRIPT"; then
  echo "Release gate must archive UI evidence in the tracked gallery" >&2
  exit 1
fi
if ! rg -q -- '--ui-evidence' "$SCRIPT"; then
  echo "Release gate must expose explicit opt-in UI evidence" >&2
  exit 1
fi
if ! rg -q 'ITSAppUsesNonExemptEncryption: false' "$IOS_DIR/project.yml"; then
  echo "The App Store build must declare that it uses no non-exempt encryption" >&2
  exit 1
fi
if ! rg -q 'Apple Distribution.*iPhone Distribution' "$SCRIPT"; then
  echo "The App Store gate must accept modern and legacy Apple distribution identities" >&2
  exit 1
fi
if [[ "$(rg -c 'UIInterfaceOrientation(LandscapeLeft|LandscapeRight|Portrait|PortraitUpsideDown)' "$IOS_DIR/project.yml")" -lt 4 ]]; then
  echo "The App Store bundle must declare all iPad multitasking orientations" >&2
  exit 1
fi

evidence_plan="$($IOS_DIR/scripts/generate-ui-evidence.sh --plan)"
expect_contains "$evidence_plan" "scheme: CameraeUI"
expect_contains "$evidence_plan" "test: CameraeUIEvidenceTests/testGenerateReleaseEvidence"
expect_contains "$evidence_plan" "artifacts: PNG, manifest.json, index.html"
expect_contains "$evidence_plan" "device profile: iphone"

ipad_evidence_plan="$($IOS_DIR/scripts/generate-ui-evidence.sh --device ipad --plan)"
expect_contains "$ipad_evidence_plan" "device profile: ipad"
expect_contains "$ipad_evidence_plan" "name=iPad Pro 13-inch (M5)"
expect_contains "$ipad_evidence_plan" "v$VERSION-$BUILD-ipad"

tracked_evidence_plan="$($IOS_DIR/scripts/generate-ui-evidence.sh --archive-tracked --plan)"
expect_contains "$tracked_evidence_plan" "tracked gallery:"

german_evidence_plan="$($IOS_DIR/scripts/generate-ui-evidence.sh --locale de --plan)"
expect_contains "$german_evidence_plan" "locale: de (de_DE)"
expect_contains "$german_evidence_plan" "v$VERSION-$BUILD-de"

all_locales_plan="$($IOS_DIR/scripts/generate-ui-evidence.sh --all-locales --plan)"
for locale in pt-BR es en fr de ru; do
  expect_contains "$all_locales_plan" "locale: $locale"
done

all_devices_and_locales_plan="$($IOS_DIR/scripts/generate-ui-evidence.sh --all-devices --all-locales --plan)"
if [[ "$(rg -c '^device profile: iphone$' <<<"$all_devices_and_locales_plan")" -ne 6 ]]; then
  echo "The complete UI evidence matrix must contain six iPhone galleries" >&2
  exit 1
fi
if [[ "$(rg -c '^device profile: ipad$' <<<"$all_devices_and_locales_plan")" -ne 6 ]]; then
  echo "The complete UI evidence matrix must contain six iPad galleries" >&2
  exit 1
fi
for locale in pt-BR es en fr de ru; do
  if [[ "$(rg -c "^locale: $locale " <<<"$all_devices_and_locales_plan")" -ne 2 ]]; then
    echo "The complete UI evidence matrix must contain iPhone and iPad for $locale" >&2
    exit 1
  fi
done

if [[ "$(rg -c -- '--device (iphone|ipad)' "$SCRIPT")" -lt 2 ]] || [[ "$(rg -c -- '--all-locales' "$SCRIPT")" -lt 2 ]]; then
  echo "Release gate must capture both iPhone and iPad UI evidence" >&2
  exit 1
fi

echo "Release gate contract tests passed"

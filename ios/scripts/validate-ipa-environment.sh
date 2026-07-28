#!/usr/bin/env bash
set -euo pipefail

IPA_PATH="${1:?Usage: validate-ipa-environment.sh IPA_PATH EXPECTED_BUNDLE_ID EXPECTED_FIREBASE_APP_ID}"
EXPECTED_BUNDLE_ID="${2:?Usage: validate-ipa-environment.sh IPA_PATH EXPECTED_BUNDLE_ID EXPECTED_FIREBASE_APP_ID}"
EXPECTED_FIREBASE_APP_ID="${3:?Usage: validate-ipa-environment.sh IPA_PATH EXPECTED_BUNDLE_ID EXPECTED_FIREBASE_APP_ID}"

if [[ ! -f "$IPA_PATH" ]]; then
  echo "IPA does not exist: $IPA_PATH" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/camerae-ipa.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
unzip -qq "$IPA_PATH" -d "$TEMP_DIR"

APP_COUNT="$(find "$TEMP_DIR/Payload" -maxdepth 1 -type d -name '*.app' -print | wc -l | tr -d ' ')"
if [[ "$APP_COUNT" -ne 1 ]]; then
  echo "Expected one application bundle in $IPA_PATH, found $APP_COUNT." >&2
  exit 1
fi

APP_BUNDLE="$(find "$TEMP_DIR/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Info.plist")"
if [[ "$ACTUAL_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "IPA bundle mismatch: expected $EXPECTED_BUNDLE_ID, found $ACTUAL_BUNDLE_ID." >&2
  exit 1
fi

FIREBASE_PLIST="$APP_BUNDLE/GoogleService-Info.plist"
if [[ ! -f "$FIREBASE_PLIST" ]]; then
  echo "IPA is missing GoogleService-Info.plist." >&2
  exit 1
fi

FIREBASE_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$FIREBASE_PLIST")"
FIREBASE_APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :GOOGLE_APP_ID' "$FIREBASE_PLIST")"
if [[ "$FIREBASE_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "IPA Firebase bundle mismatch: expected $EXPECTED_BUNDLE_ID, found $FIREBASE_BUNDLE_ID." >&2
  exit 1
fi
if [[ "$FIREBASE_APP_ID" != "$EXPECTED_FIREBASE_APP_ID" ]]; then
  echo "IPA Firebase app mismatch: expected $EXPECTED_FIREBASE_APP_ID, found $FIREBASE_APP_ID." >&2
  exit 1
fi

echo "Validated IPA environment $ACTUAL_BUNDLE_ID with Firebase app $FIREBASE_APP_ID."

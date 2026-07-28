#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_PATH="${1:?Usage: validate-archive-environment.sh ARCHIVE_PATH EXPECTED_BUNDLE_ID}"
EXPECTED_BUNDLE_ID="${2:?Usage: validate-archive-environment.sh ARCHIVE_PATH EXPECTED_BUNDLE_ID}"
APPLICATIONS_DIR="$ARCHIVE_PATH/Products/Applications"

if [[ ! -d "$APPLICATIONS_DIR" ]]; then
  echo "Archive applications directory is missing: $APPLICATIONS_DIR" >&2
  exit 1
fi

APP_COUNT="$(find "$APPLICATIONS_DIR" -maxdepth 1 -type d -name '*.app' -print | wc -l | tr -d ' ')"
if [[ "$APP_COUNT" -ne 1 ]]; then
  echo "Expected one app in $ARCHIVE_PATH, found $APP_COUNT." >&2
  exit 1
fi

APP_BUNDLE="$(find "$APPLICATIONS_DIR" -maxdepth 1 -type d -name '*.app' -print -quit)"
ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Info.plist")"
if [[ "$ACTUAL_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "Archive bundle mismatch: expected $EXPECTED_BUNDLE_ID, found $ACTUAL_BUNDLE_ID." >&2
  exit 1
fi

echo "Validated archive bundle $ACTUAL_BUNDLE_ID."

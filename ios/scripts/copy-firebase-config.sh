#!/usr/bin/env bash
set -euo pipefail

SOURCE_PLIST="${GOOGLE_SERVICE_INFO_PLIST:?GOOGLE_SERVICE_INFO_PLIST is not configured.}"
EXPECTED_BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER:?PRODUCT_BUNDLE_IDENTIFIER is not configured.}"
RESOURCES_DIR="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is missing}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?UNLOCALIZED_RESOURCES_FOLDER_PATH is missing}"
DESTINATION_PLIST="$RESOURCES_DIR/GoogleService-Info.plist"

if [[ ! -f "$SOURCE_PLIST" ]]; then
  echo "Firebase configuration does not exist: $SOURCE_PLIST" >&2
  exit 1
fi

CONFIGURED_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$SOURCE_PLIST")"
if [[ "$CONFIGURED_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "Firebase configuration mismatch: $SOURCE_PLIST targets $CONFIGURED_BUNDLE_ID, build targets $EXPECTED_BUNDLE_ID." >&2
  exit 1
fi

mkdir -p "$RESOURCES_DIR"
install -m 0644 "$SOURCE_PLIST" "$DESTINATION_PLIST"
echo "Embedded Firebase configuration for $EXPECTED_BUNDLE_ID."

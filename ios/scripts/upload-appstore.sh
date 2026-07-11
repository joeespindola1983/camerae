#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

WORKSPACE="$IOS_DIR/Camerae.xcworkspace"
SCHEME="Camerae"
CONFIGURATION="${CONFIGURATION:-Release}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:?Set APPLE_TEAM_ID.}"
APP_STORE_CONNECT_KEY_PATH="${APP_STORE_CONNECT_KEY_PATH:?Set APP_STORE_CONNECT_KEY_PATH.}"
APP_STORE_CONNECT_KEY_ID="${APP_STORE_CONNECT_KEY_ID:?Set APP_STORE_CONNECT_KEY_ID.}"
APP_STORE_CONNECT_ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:?Set APP_STORE_CONNECT_ISSUER_ID.}"
TESTFLIGHT_INTERNAL_ONLY="${TESTFLIGHT_INTERNAL_ONLY:-0}"

BUILD_DIR="$IOS_DIR/build/appstore-connect"
ARCHIVE_PATH="$BUILD_DIR/Camerae.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"

if [[ ! -d "$WORKSPACE" ]]; then
  echo "Missing workspace: $WORKSPACE" >&2
  echo "Run 'pod install' from $IOS_DIR first." >&2
  exit 1
fi

rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR"

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>upload</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$APPLE_TEAM_ID</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>uploadSymbols</key>
  <true/>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
</dict>
</plist>
PLIST

if [[ "$TESTFLIGHT_INTERNAL_ONLY" == "1" ]]; then
  /usr/libexec/PlistBuddy -c "Add :testFlightInternalTestingOnly bool true" "$EXPORT_OPTIONS"
fi

auth_args=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$APP_STORE_CONNECT_KEY_PATH"
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID"
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"
)

xcodebuild archive \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  "${auth_args[@]}" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  "${auth_args[@]}"

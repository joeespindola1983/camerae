#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/distribute-firebase.sh [options]

Options:
  --groups GROUPS           Firebase tester groups, comma-separated.
  --testers EMAILS          Firebase tester emails, comma-separated.
  --release-notes TEXT      Release notes text.
  --release-notes-file FILE Release notes file.
  --export-method METHOD    Xcode export method. Defaults to release-testing.
  --configuration CONFIG    Xcode configuration. Defaults to Release.
  --skip-archive            Reuse the existing exported IPA when present.
  -h, --help                Show this help.

Environment overrides:
  FIREBASE_APP_ID           Defaults to 1:413701042509:ios:b08c2a5a1594459dd20704.
  FIREBASE_PROJECT_NUMBER   Defaults to 413701042509.
  FIREBASE_PROJECT_ID       Defaults to camerae-59c4b.
  FIREBASE_GROUPS           Same as --groups.
  FIREBASE_TESTERS          Same as --testers.
  RELEASE_NOTES             Same as --release-notes.
  RELEASE_NOTES_FILE        Same as --release-notes-file.
  APPLE_TEAM_ID             Apple Developer Team ID for automatic signing.
  APP_STORE_CONNECT_KEY_PATH App Store Connect API private key path for CI signing.
  APP_STORE_CONNECT_KEY_ID   App Store Connect API key ID for CI signing.
  APP_STORE_CONNECT_ISSUER_ID App Store Connect API issuer ID for CI signing.
  ALLOW_PROVISIONING_UPDATES Set to 1 only for an intentional local profile update.
  EXPORT_METHOD             Same as --export-method.
  CONFIGURATION             Same as --configuration.

Examples:
  scripts/distribute-firebase.sh --groups internal --release-notes "Build de teste"
  FIREBASE_TESTERS="ana@example.com,bia@example.com" scripts/distribute-firebase.sh
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

WORKSPACE="$IOS_DIR/Camerae.xcworkspace"
SCHEME="Camerae"
CONFIGURATION="${CONFIGURATION:-Release}"
EXPORT_METHOD="${EXPORT_METHOD:-release-testing}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-0}"
FIREBASE_PROJECT_NUMBER="${FIREBASE_PROJECT_NUMBER:-413701042509}"
FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-camerae-59c4b}"
FIREBASE_APP_ID="${FIREBASE_APP_ID:-1:${FIREBASE_PROJECT_NUMBER}:ios:b08c2a5a1594459dd20704}"
FIREBASE_GROUPS="${FIREBASE_GROUPS:-}"
FIREBASE_TESTERS="${FIREBASE_TESTERS:-}"
RELEASE_NOTES="${RELEASE_NOTES:-}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APP_STORE_CONNECT_KEY_PATH="${APP_STORE_CONNECT_KEY_PATH:-}"
APP_STORE_CONNECT_KEY_ID="${APP_STORE_CONNECT_KEY_ID:-}"
APP_STORE_CONNECT_ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-}"
SKIP_ARCHIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --groups)
      FIREBASE_GROUPS="${2:?Missing value for --groups}"
      shift 2
      ;;
    --testers)
      FIREBASE_TESTERS="${2:?Missing value for --testers}"
      shift 2
      ;;
    --release-notes)
      RELEASE_NOTES="${2:?Missing value for --release-notes}"
      shift 2
      ;;
    --release-notes-file)
      RELEASE_NOTES_FILE="${2:?Missing value for --release-notes-file}"
      shift 2
      ;;
    --export-method)
      EXPORT_METHOD="${2:?Missing value for --export-method}"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="${2:?Missing value for --configuration}"
      shift 2
      ;;
    --skip-archive)
      SKIP_ARCHIVE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$WORKSPACE" ]]; then
  echo "Missing workspace: $WORKSPACE" >&2
  echo "Run 'pod install' from $IOS_DIR first." >&2
  exit 1
fi

if ! command -v firebase >/dev/null 2>&1; then
  echo "Firebase CLI not found. Install it with: npm install -g firebase-tools" >&2
  exit 1
fi

if [[ -z "$FIREBASE_GROUPS" && -z "$FIREBASE_TESTERS" ]]; then
  echo "Set at least one distribution target with --groups or --testers." >&2
  exit 1
fi

BUILD_DIR="$IOS_DIR/build/firebase-distribution"
ARCHIVE_PATH="$BUILD_DIR/Camerae.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
IPA_PATH="$EXPORT_DIR/Camerae.ipa"

mkdir -p "$BUILD_DIR" "$EXPORT_DIR"

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>$EXPORT_METHOD</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>compileBitcode</key>
  <false/>
</dict>
</plist>
PLIST

if [[ -n "$APPLE_TEAM_ID" ]]; then
  /usr/libexec/PlistBuddy -c "Add :teamID string $APPLE_TEAM_ID" "$EXPORT_OPTIONS"
fi

if [[ "$SKIP_ARCHIVE" -eq 0 ]]; then
  rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
  mkdir -p "$EXPORT_DIR"

  provisioning_args=()
  if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    provisioning_args=(-allowProvisioningUpdates)
  fi

  if [[ -n "$APP_STORE_CONNECT_KEY_PATH" || -n "$APP_STORE_CONNECT_KEY_ID" || -n "$APP_STORE_CONNECT_ISSUER_ID" ]]; then
    if [[ -z "$APP_STORE_CONNECT_KEY_PATH" || -z "$APP_STORE_CONNECT_KEY_ID" || -z "$APP_STORE_CONNECT_ISSUER_ID" ]]; then
      echo "Set APP_STORE_CONNECT_KEY_PATH, APP_STORE_CONNECT_KEY_ID, and APP_STORE_CONNECT_ISSUER_ID together." >&2
      exit 1
    fi

    provisioning_args+=(
      -authenticationKeyPath "$APP_STORE_CONNECT_KEY_PATH"
      -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID"
      -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"
    )
  fi

  build_settings=()
  if [[ -n "$APPLE_TEAM_ID" ]]; then
    build_settings+=(DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Automatic)
  fi

  xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    "${provisioning_args[@]}" \
    "${build_settings[@]}"

  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    "${provisioning_args[@]}"
fi

if [[ ! -f "$IPA_PATH" ]]; then
  echo "IPA not found at $IPA_PATH" >&2
  exit 1
fi

firebase_args=(
  appdistribution:distribute "$IPA_PATH"
  --app "$FIREBASE_APP_ID"
  --project "$FIREBASE_PROJECT_ID"
)

if [[ -n "$FIREBASE_GROUPS" ]]; then
  firebase_args+=(--groups "$FIREBASE_GROUPS")
fi

if [[ -n "$FIREBASE_TESTERS" ]]; then
  firebase_args+=(--testers "$FIREBASE_TESTERS")
fi

if [[ -n "$RELEASE_NOTES" ]]; then
  firebase_args+=(--release-notes "$RELEASE_NOTES")
fi

if [[ -n "$RELEASE_NOTES_FILE" ]]; then
  firebase_args+=(--release-notes-file "$RELEASE_NOTES_FILE")
fi

firebase "${firebase_args[@]}"

echo "Distributed $IPA_PATH to Firebase App Distribution app $FIREBASE_APP_ID."

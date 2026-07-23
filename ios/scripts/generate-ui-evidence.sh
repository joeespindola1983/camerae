#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/generate-ui-evidence.sh [--device iphone|ipad|--all-devices] [--locale LOCALE|--all-locales] [--output DIR] [--destination DESTINATION] [--archive-tracked] [--plan]

Generates deterministic simulator screenshots for the principal Camerae SwiftUI screens.
The output contains PNG files, manifest.json, index.html and a ZIP archive.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$IOS_DIR/.." && pwd)"
DEVICE_PROFILE="iphone"
ALL_DEVICES=0
LOCALE="pt-BR"
ALL_LOCALES=0
DESTINATION="${UI_EVIDENCE_DESTINATION:-}"
OUTPUT_DIR=""
ARCHIVE_TRACKED=0
PLAN_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE_PROFILE="${2:?--device requires iphone or ipad}"; shift ;;
    --all-devices) ALL_DEVICES=1 ;;
    --locale) LOCALE="${2:?--locale requires a locale identifier}"; shift ;;
    --all-locales) ALL_LOCALES=1 ;;
    --output) OUTPUT_DIR="${2:?--output requires a directory}"; shift ;;
    --destination) DESTINATION="${2:?--destination requires a value}"; shift ;;
    --archive-tracked) ARCHIVE_TRACKED=1 ;;
    --plan) PLAN_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ "$ALL_DEVICES" -eq 1 || "$ALL_LOCALES" -eq 1 ]]; then
  [[ -z "$OUTPUT_DIR" ]] || { echo "--output cannot be combined with a matrix option" >&2; exit 2; }
  if [[ "$ALL_DEVICES" -eq 1 && -n "$DESTINATION" ]]; then
    echo "--destination cannot be combined with --all-devices because each profile requires its own simulator" >&2
    exit 2
  fi

  devices=("$DEVICE_PROFILE")
  locales=("$LOCALE")
  [[ "$ALL_DEVICES" -eq 0 ]] || devices=(iphone ipad)
  [[ "$ALL_LOCALES" -eq 0 ]] || locales=(pt-BR es en fr de ru)

  for device in "${devices[@]}"; do
    for locale in "${locales[@]}"; do
      args=(--device "$device" --locale "$locale")
      [[ -z "$DESTINATION" ]] || args+=(--destination "$DESTINATION")
      [[ "$ARCHIVE_TRACKED" -eq 0 ]] || args+=(--archive-tracked)
      [[ "$PLAN_ONLY" -eq 0 ]] || args+=(--plan)
      "$0" "${args[@]}"
    done
  done
  exit 0
fi

case "$LOCALE" in
  pt-BR) APPLE_LOCALE="pt_BR" ;;
  es) APPLE_LOCALE="es_ES" ;;
  en) APPLE_LOCALE="en_US" ;;
  fr) APPLE_LOCALE="fr_FR" ;;
  de) APPLE_LOCALE="de_DE" ;;
  ru) APPLE_LOCALE="ru_RU" ;;
  *) echo "Unsupported locale: $LOCALE (expected pt-BR, es, en, fr, de or ru)" >&2; exit 2 ;;
esac

case "$DEVICE_PROFILE" in
  iphone) DEFAULT_DEVICE_NAME="iPhone 17 Pro"; PROFILE_SUFFIX=""; PROFILE_TITLE="iPhone" ;;
  ipad) DEFAULT_DEVICE_NAME="iPad Pro 13-inch (M5)"; PROFILE_SUFFIX="-ipad"; PROFILE_TITLE="iPad" ;;
  *) echo "Unsupported device profile: $DEVICE_PROFILE (expected iphone or ipad)" >&2; exit 2 ;;
esac
if [[ "$LOCALE" != "pt-BR" ]]; then
  PROFILE_SUFFIX="$PROFILE_SUFFIX-$LOCALE"
fi
if [[ -z "$DESTINATION" ]]; then
  DESTINATION="platform=iOS Simulator,name=$DEFAULT_DEVICE_NAME,OS=latest"
fi

version="$(awk -F '"' '/MARKETING_VERSION:/ { print $2; exit }' "$IOS_DIR/project.yml")"
build="$(awk -F '"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$IOS_DIR/project.yml")"
if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$IOS_DIR/build/ui-evidence/v$version-$build$PROFILE_SUFFIX"
fi

if [[ "$OUTPUT_DIR" != /* ]]; then
  OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
fi

echo "scheme: CameraeUI"
echo "test: CameraeUIEvidenceTests/testGenerateReleaseEvidence"
echo "device profile: $DEVICE_PROFILE"
echo "locale: $LOCALE ($APPLE_LOCALE)"
echo "destination: $DESTINATION"
echo "output: $OUTPUT_DIR"
echo "artifacts: PNG, manifest.json, index.html"
if [[ "$ARCHIVE_TRACKED" -eq 1 ]]; then
  echo "tracked gallery: $ROOT_DIR/docs/ui-evidence/v$version-$build$PROFILE_SUFFIX"
fi
[[ "$PLAN_ONLY" -eq 1 ]] && exit 0

for command in xcodebuild xcrun ditto plutil; do
  command -v "$command" >/dev/null 2>&1 || { echo "Missing command: $command" >&2; exit 1; }
done

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
evidence_title="Camerae $version ($build) · Evidências de UI · $PROFILE_TITLE · $LOCALE"
config="$ROOT_DIR/.build/ui-evidence/config.plist"
mkdir -p "$(dirname "$config")"
plutil -create xml1 "$config"
plutil -insert outputDirectory -string "$OUTPUT_DIR" "$config"
plutil -insert title -string "$evidence_title" "$config"
plutil -insert localeIdentifier -string "$LOCALE" "$config"
plutil -insert appleLocale -string "$APPLE_LOCALE" "$config"

# Evidence must start from deterministic empty application storage. Resolve the
# profile's simulator explicitly: before xcodebuild starts there may be no booted
# device, and `simctl uninstall booted` would silently preserve prior projects.
SIMULATOR_UDID="$(xcrun simctl list devices available | awk -v device="$DEFAULT_DEVICE_NAME" '
  index($0, "    " device " (") == 1 {
    for (fieldIndex = 1; fieldIndex <= NF; fieldIndex += 1) {
      value = $fieldIndex
      gsub(/[()]/, "", value)
      if (length(value) == 36 && value ~ /-/) { print value; exit }
    }
  }
')"
[[ -n "$SIMULATOR_UDID" ]] || { echo "Unable to resolve simulator: $DEFAULT_DEVICE_NAME" >&2; exit 1; }
xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b >/dev/null

test_passed=0
for attempt in 1 2 3; do
  xcrun simctl uninstall "$SIMULATOR_UDID" com.espindola.camerae >/dev/null 2>&1 || true
  find "$OUTPUT_DIR" -maxdepth 1 -type f -delete

  if (cd "$IOS_DIR" && xcodebuild test \
    -workspace Camerae.xcworkspace \
    -scheme CameraeUI \
    -destination "$DESTINATION" \
    -derivedDataPath "$ROOT_DIR/.build/ui-evidence" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 180 \
    -maximum-test-execution-time-allowance 300 \
    -only-testing:CameraeUITests/CameraeUIEvidenceTests/testGenerateReleaseEvidence); then
    test_passed=1
    break
  fi

  echo "UI evidence attempt $attempt failed; resetting the app before retrying." >&2
  find "$ROOT_DIR/.build/ui-evidence/Logs/Test" -mindepth 1 -depth -delete 2>/dev/null || true
done
[[ "$test_passed" -eq 1 ]] || { echo "UI evidence failed after 3 attempts" >&2; exit 1; }

# The PNGs and manifest are the durable evidence. XCTest result bundles are
# transient and can exhaust disk space during a 12-profile matrix.
find "$ROOT_DIR/.build/ui-evidence/Logs/Test" -mindepth 1 -depth -delete 2>/dev/null || true

expected=14
actual="$(find "$OUTPUT_DIR" -maxdepth 1 -name '*.png' -type f | wc -l | tr -d ' ')"
[[ "$actual" == "$expected" ]] || { echo "Expected $expected screenshots, found $actual" >&2; exit 1; }
[[ -f "$OUTPUT_DIR/manifest.json" ]] || { echo "Missing manifest.json" >&2; exit 1; }
[[ -f "$OUTPUT_DIR/index.html" ]] || { echo "Missing index.html" >&2; exit 1; }

archive="$IOS_DIR/build/ui-evidence/Camerae-v$version-$build$PROFILE_SUFFIX-ui-evidence.zip"
mkdir -p "$(dirname "$archive")"
ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_DIR" "$archive"

if [[ "$ARCHIVE_TRACKED" -eq 1 ]]; then
  tracked_root="$ROOT_DIR/docs/ui-evidence"
  tracked_dir="$tracked_root/v$version-$build$PROFILE_SUFFIX"
  mkdir -p "$tracked_dir"
  find "$tracked_dir" -maxdepth 1 -type f -delete
  cp "$OUTPUT_DIR"/*.png "$OUTPUT_DIR/manifest.json" "$OUTPUT_DIR/index.html" "$tracked_dir/"

  catalog="$tracked_root/README.md"
  {
    echo '# Camerae UI evidence'
    echo
    echo 'Galerias versionadas das telas principais, geradas pelo release gate no iOS Simulator.'
    echo
    find "$tracked_root" -mindepth 1 -maxdepth 1 -type d -name 'v*' -print \
      | sort -Vr \
      | while read -r gallery; do
          name="$(basename "$gallery")"
          echo "- [$name]($name/index.html)"
        done
  } > "$catalog"
fi

echo
echo "UI evidence generated successfully:"
echo "gallery: $OUTPUT_DIR/index.html"
echo "archive: $archive"
if [[ "$ARCHIVE_TRACKED" -eq 1 ]]; then
  echo "tracked gallery: $tracked_dir/index.html"
fi

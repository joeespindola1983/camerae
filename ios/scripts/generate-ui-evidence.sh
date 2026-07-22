#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/generate-ui-evidence.sh [--output DIR] [--destination DESTINATION] [--archive-tracked] [--plan]

Generates deterministic simulator screenshots for the principal Camerae SwiftUI screens.
The output contains PNG files, manifest.json, index.html and a ZIP archive.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$IOS_DIR/.." && pwd)"
DESTINATION="${UI_EVIDENCE_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"
OUTPUT_DIR=""
ARCHIVE_TRACKED=0
PLAN_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT_DIR="${2:?--output requires a directory}"; shift ;;
    --destination) DESTINATION="${2:?--destination requires a value}"; shift ;;
    --archive-tracked) ARCHIVE_TRACKED=1 ;;
    --plan) PLAN_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

version="$(awk -F '"' '/MARKETING_VERSION:/ { print $2; exit }' "$IOS_DIR/project.yml")"
build="$(awk -F '"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$IOS_DIR/project.yml")"
if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$IOS_DIR/build/ui-evidence/v$version-$build"
fi

if [[ "$OUTPUT_DIR" != /* ]]; then
  OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
fi

echo "scheme: CameraeUI"
echo "test: CameraeUIEvidenceTests/testGenerateReleaseEvidence"
echo "destination: $DESTINATION"
echo "output: $OUTPUT_DIR"
echo "artifacts: PNG, manifest.json, index.html"
if [[ "$ARCHIVE_TRACKED" -eq 1 ]]; then
  echo "tracked gallery: $ROOT_DIR/docs/ui-evidence/v$version-$build"
fi
[[ "$PLAN_ONLY" -eq 1 ]] && exit 0

for command in xcodebuild xcrun ditto plutil; do
  command -v "$command" >/dev/null 2>&1 || { echo "Missing command: $command" >&2; exit 1; }
done

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
evidence_title="Camerae $version ($build) · Evidências de UI"
config="$ROOT_DIR/.build/ui-evidence/config.plist"
mkdir -p "$(dirname "$config")"
plutil -create xml1 "$config"
plutil -insert outputDirectory -string "$OUTPUT_DIR" "$config"
plutil -insert title -string "$evidence_title" "$config"

# Evidence must start from deterministic empty application storage.
xcrun simctl uninstall booted com.espindola.camerae >/dev/null 2>&1 || true

(cd "$IOS_DIR" && xcodebuild test \
  -workspace Camerae.xcworkspace \
  -scheme CameraeUI \
  -destination "$DESTINATION" \
  -derivedDataPath "$ROOT_DIR/.build/ui-evidence" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 300 \
  -only-testing:CameraeUITests/CameraeUIEvidenceTests/testGenerateReleaseEvidence)

expected=10
actual="$(find "$OUTPUT_DIR" -maxdepth 1 -name '*.png' -type f | wc -l | tr -d ' ')"
[[ "$actual" == "$expected" ]] || { echo "Expected $expected screenshots, found $actual" >&2; exit 1; }
[[ -f "$OUTPUT_DIR/manifest.json" ]] || { echo "Missing manifest.json" >&2; exit 1; }
[[ -f "$OUTPUT_DIR/index.html" ]] || { echo "Missing index.html" >&2; exit 1; }

archive="$IOS_DIR/build/ui-evidence/Camerae-v$version-$build-ui-evidence.zip"
mkdir -p "$(dirname "$archive")"
ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_DIR" "$archive"

if [[ "$ARCHIVE_TRACKED" -eq 1 ]]; then
  tracked_root="$ROOT_DIR/docs/ui-evidence"
  tracked_dir="$tracked_root/v$version-$build"
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

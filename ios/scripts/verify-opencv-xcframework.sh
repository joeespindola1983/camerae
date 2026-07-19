#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FRAMEWORK="${1:-$IOS_DIR/Frameworks/opencv2.xcframework}"
PLIST="$FRAMEWORK/Info.plist"
MANIFEST="$IOS_DIR/Frameworks/opencv-xcframework.json"

fail() {
  echo "OpenCV XCFramework verification failed: $*" >&2
  exit 1
}

[[ -f "$PLIST" ]] || fail "missing $PLIST; run scripts/build-opencv-xcframework.sh"
[[ -f "$MANIFEST" ]] || fail "missing version manifest"
rg -q '"opencvVersion": "4\.13\.0"' "$MANIFEST" || fail "manifest version is not 4.13.0"
rg -q '"opencvCommit": "fe38fc608f6acb8b68953438a62305d8318f4fcd"' "$MANIFEST" || \
  fail "manifest commit is not the pinned OpenCV source"

plist_text="$(plutil -convert xml1 -o - "$PLIST")"
[[ "$plist_text" == *"<string>ios-arm64</string>"* ]] || fail "missing iPhoneOS arm64 slice"
[[ "$plist_text" == *"<string>ios-arm64-simulator</string>"* ]] || fail "missing iPhoneSimulator arm64 slice"
[[ "$plist_text" == *"<string>simulator</string>"* ]] || fail "simulator variant is not declared"

for identifier in ios-arm64 ios-arm64-simulator; do
  binary="$FRAMEWORK/$identifier/opencv2.framework/opencv2"
  version_header="$FRAMEWORK/$identifier/opencv2.framework/Headers/core/version.hpp"
  [[ -f "$binary" ]] || fail "missing binary for $identifier"
  [[ "$(lipo -archs "$binary")" == "arm64" ]] || fail "unexpected architectures for $identifier"
  [[ -f "$version_header" ]] || fail "missing OpenCV version header for $identifier"
  rg -q '^#define CV_VERSION_MAJOR +4$' "$version_header" || fail "unexpected OpenCV major version"
  rg -q '^#define CV_VERSION_MINOR +13$' "$version_header" || fail "unexpected OpenCV minor version"
done

echo "OpenCV 4.13.0 XCFramework verified for iPhoneOS arm64 and iPhoneSimulator arm64."

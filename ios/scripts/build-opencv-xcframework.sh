#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENCV_VERSION="4.13.0"
OPENCV_COMMIT="fe38fc608f6acb8b68953438a62305d8318f4fcd"
OUTPUT_DIR="${OPENCV_OUTPUT_DIR:-$IOS_DIR/Frameworks/opencv2.xcframework}"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/camerae-opencv.XXXXXX")"

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

SOURCE_DIR="${OPENCV_SOURCE_DIR:-$TEMP_ROOT/opencv}"
if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  git clone --branch "$OPENCV_VERSION" --depth 1 https://github.com/opencv/opencv.git "$SOURCE_DIR"
fi

actual_commit="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
if [[ "$actual_commit" != "$OPENCV_COMMIT" ]]; then
  echo "OpenCV commit mismatch: expected $OPENCV_COMMIT, found $actual_commit" >&2
  exit 1
fi

BUILD_DIR="$TEMP_ROOT/build"
python3 "$SOURCE_DIR/platforms/apple/build_xcframework.py" \
  --out "$BUILD_DIR" \
  --iphoneos_archs arm64 \
  --iphonesimulator_archs arm64 \
  --build_only_specified_archs \
  --iphoneos_deployment_target 17.0 \
  --without dnn \
  --without gapi \
  --without highgui \
  --without java \
  --without js \
  --without ml \
  --without objdetect \
  --without python3 \
  --without stitching \
  --without ts \
  --without videoio \
  --without objc \
  --disable-swift

mkdir -p "$OUTPUT_DIR"
rsync -a --delete "$BUILD_DIR/opencv2.xcframework/" "$OUTPUT_DIR/"
"$SCRIPT_DIR/verify-opencv-xcframework.sh" "$OUTPUT_DIR"

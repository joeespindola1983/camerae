#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
VISION_DIR="$(dirname -- "$SCRIPT_DIR")"
REPOSITORY_DIR="$(dirname -- "$VISION_DIR")"
BUILD_DIR="${CAMERAE_PLATE_SOLVING_BUILD_DIR:-/tmp/camerae-plate-solving-build}"

cmake -S "$VISION_DIR" -B "$BUILD_DIR" -DBUILD_TESTING=ON
cmake --build "$BUILD_DIR" --target camerae-plate-solve-lab --parallel
"$BUILD_DIR/camerae-plate-solve-lab" "$@"

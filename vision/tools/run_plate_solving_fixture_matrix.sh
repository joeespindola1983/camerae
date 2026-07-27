#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <lab-binary> <output-directory> <image> [image ...]" >&2
  exit 64
fi

lab_binary=$1
output_directory=$2
shift 2

mkdir -p "$output_directory"
summary="$output_directory/summary.tsv"
printf 'fixture\tactive_x\tactive_y\twidth\theight\tstars\tdetection_ms\tbackground_noise\tstatus\n' >"$summary"

for image_path in "$@"; do
  fixture_name=$(basename "$image_path")
  fixture_key=${fixture_name%.*}
  fixture_output="$output_directory/$fixture_key"
  "$lab_binary" --image "$image_path" --output "$fixture_output" >/dev/null
  jq -r --arg fixture "$fixture_name" \
    '[$fixture, .activeRegionX, .activeRegionY, .imageWidth, .imageHeight,
      .detectedStarCount, .detectionMilliseconds, .backgroundNoise, .status]
      | @tsv' \
    "$fixture_output/report.json" >>"$summary"
done

echo "[CameraePlateSolve] fixture-matrix.completed | summary=$summary"

# Camerae Vision

Shared C++ computer-vision domain for Camerae. OpenCV is the initial backend,
while Astro, Repeatable, Timelapse, and future consumers remain outside this
module.

## Desktop build

```sh
cmake -S vision -B .build/vision -DBUILD_TESTING=ON
cmake --build .build/vision
ctest --test-dir .build/vision --output-on-failure
```

The existing alignment CLI remains available as `camerae-alignment-preview`.

## Capture quality evaluator

`AlignmentQualityEvaluator` provides the data-only `CaptureFast` preset for a
future capture-support component. It downsizes input to 640 px, uses ORB with at
most 1200 features, compares similarity and affine transforms, and prefers the
simpler model unless affine materially improves local edge alignment. Reference
features are cached until the reference pixels change.

The fast path does not use SIFT or ECC and does not write images or reports.

## Capture simulation

The desktop simulator applies virtual capture cadence and latest-only
backpressure without sleeping. Only scheduled frames are decoded, using
OpenCV's reduced-resolution decode path:

```sh
.build/vision/camerae-capture-quality-simulator \
  --reference reference.jpg \
  --frames frames/ \
  --capture-fps 30 \
  --analysis-fps 2 \
  --latest-only 1 \
  --report out/capture-quality.json
```

The JSON report contains per-frame decisions and scores, selected models,
latency p50/p95/max, received/analyzed/dropped counters, bounded pending-frame
count, approximate retained image bytes, and decision percentages.

### Initial desktop snapshot

On the local 1000-frame sequence, simulated at 100 capture fps and 2 analysis
fps, the scheduler analyzed 20 frames, dropped 980, and never retained more than
one pending frame. Reduced decoding kept approximate retained image memory near
8.3 MB; measured latency was about 10.3 ms p50, 16.8 ms p95, and 41.9 ms max.
These numbers are a desktop architecture baseline, not a mobile CPU/energy
budget.

For the supplied real pairs, the higher-parallax `IMG_2025/IMG_2026` pair was
classified `review` with similarity, while the lower-parallax
`IMG_2029/IMG_2030` pair was classified `accept` with affine. This matches the
expected distinction between correctable capture and a capture needing caution.

## Optional capture-support contract

`CaptureSupportSettings` identifies the `AlignmentQuality` component, keeps it
disabled by default, and provides conservative (1 Hz), balanced (2 Hz), and
responsive (4 Hz) cadence policies. `AlignmentQualityCaptureSupport` creates
its evaluator lazily on the first enabled evaluation and reuses it afterward.

When disabled, the component returns before inspecting image inputs, creates no
evaluator, and schedules no evaluation. Thread/worker ownership, UI preferences,
and project persistence deliberately remain outside Camerae Vision for the
future application-integration phase.

## Automatic final model selection

`alignImagesAutomatically` runs the final-quality similarity, affine, and
homography candidates and returns their diagnostics with the selected result.
Selection is deliberately conservative: a candidate with a better feasibility
decision wins, while candidates in the same decision band must materially lower
local edge error. Affine requires at least 15% improvement and homography 30%.

The desktop lab exposes this as `--model auto`; explicit model selection remains
available and unchanged. On both supplied real pairs, automatic mode retained
similarity: the higher-parallax pair remained `review`, while the lower-parallax
pair was already `accept` without requiring a more deformable model.

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

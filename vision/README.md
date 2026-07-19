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

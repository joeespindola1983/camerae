# OpenCV XCFramework

`opencv2.xcframework` is generated locally and is intentionally not committed.
Build the pinned Camerae distribution with:

```sh
ios/scripts/build-opencv-xcframework.sh
ios/scripts/verify-opencv-xcframework.sh
```

The source version, commit, modules, and platform slices are fixed in
`opencv-xcframework.json`. Both iPhoneOS arm64 and iPhoneSimulator arm64 are
required so Camerae Vision never uses a simulator stub.

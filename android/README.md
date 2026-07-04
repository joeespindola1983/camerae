# Camerae Android

This is the initial Android scaffold for Camerae.

The iOS app in `../ios` remains the reference implementation for product behavior. Android should use native Android camera and sensor APIs rather than directly mirroring Swift implementation details.

## Intended Stack

- Camera preview and capture: CameraX first, Camera2 where manual controls are required.
- Long exposure capability detection: Camera2 `SENSOR_INFO_EXPOSURE_TIME_RANGE`.
- Repeatable alignment: camera preview overlay, sensors, location, and image similarity.
- Image similarity: OpenCV or Android-native ML/Vision alternatives after the MVP is stable.

## First Milestone

Build a repeatable-alignment MVP:

1. Project list.
2. Capture list inside a project.
3. Live camera preview.
4. Reference-image overlay with opacity.
5. Sensor and GPS capture metadata.

## Build

```sh
./gradlew assembleDebug
```

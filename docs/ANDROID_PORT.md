# Android Port Notes

The Android app should be developed from the iOS product behavior, not as a direct code translation.

## Recommended Order

1. Repeatable project shell.
2. Live camera preview.
3. Reference image overlay.
4. Project and capture persistence.
5. Sensor, orientation, and fine GPS metadata.
6. Visual similarity guides.
7. MP4 export.
8. Astrophotography capture and stacking.

## Camera Notes

Use CameraX for the first preview/capture implementation. Drop into Camera2 when a feature needs explicit hardware capability checks, especially:

- Manual exposure.
- ISO control.
- Long exposure limits.
- Manual focus.

Astrophotography should detect long-exposure support per device. Android devices differ widely here.

## Alignment Notes

The iOS app currently uses Vision homography to estimate visual alignment. Android candidates:

- OpenCV feature matching and homography.
- ML Kit or MediaPipe for selected subject tracking.
- Custom region-based matching for repeatable scenes.

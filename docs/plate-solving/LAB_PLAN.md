# Camerae Plate-Solving Laboratory

Status: Phase 1 implemented

The laboratory is an offline, UI-independent environment for developing Camerae's
future plate-solving capability. It belongs to the shared C++ `camerae_vision`
module so the same algorithm can later run on iOS and Android.

## Current delivery

Phase 1 provides:

- gnomonic projection and inverse projection for celestial coordinates;
- deterministic synthetic star-field generation;
- local-background subtraction and connected-component star detection;
- intensity-weighted star centroids;
- stable JSON report schema;
- an annotated PNG showing every detected candidate;
- native C++ tests and a command-line laboratory.

This phase intentionally reports `detectionCompleted`, never `solved`. A celestial
solution must only be reported after catalog matching and geometric validation
exist. RA, Dec, roll, field of view, and plate scale are therefore not fabricated.

## Run

OpenCV and CMake must be installed on the development machine.

```bash
vision/tools/run_plate_solving_lab.sh \
  --image /absolute/path/to/sky.png \
  --output /tmp/camerae-plate-solving
```

Outputs:

- `detected-stars.png`
- `report.json`

Optional detector controls:

```bash
--max-dimension 1600
--minimum-snr 4.5
```

## Fixture policy

Real photographs belong in `local-fixtures/plate-solving/`, which is ignored by
Git. A fixture may be committed later only after its redistribution rights and
location metadata have been reviewed. Production diagnostics must never include
the image, file path, location, observation time, or celestial coordinates.

## Next phases

1. Define a compact, versioned bright-star catalog format.
2. Build deterministic triangle/quad invariants from catalog stars.
3. Implement constrained matching using approximate field of view and optional
   location/time hints.
4. Implement blind lost-in-space matching.
5. Fit and validate center RA/Dec, roll, field of view, plate scale, and lens
   distortion.
6. Add positive and negative golden fixtures.
7. Add an Objective-C++ bridge only after native accuracy and performance gates
   pass.

## Initial acceptance targets

- no false solution on blank, daylight, or non-sky fixtures;
- at least eight catalog inliers before accepting a solution;
- center error below 0.10 degree on reviewed golden fixtures;
- roll error below 0.30 degree;
- field-of-view error below 2 percent;
- constrained solve target below one second on the reference iPhone;
- no network access during detection or solving.

Targets remain provisional until the real fixture set contains multiple lenses,
orientations, exposure levels, skies, and weather conditions.

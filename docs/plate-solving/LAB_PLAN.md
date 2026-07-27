# Camerae Plate-Solving Laboratory

Status: Native laboratory, conservative lost-in-space solver, compact catalog,
and isolated iOS bridge implemented

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

Phase 2 provides:

- a typed star-catalog contract;
- constrained similarity matching with approximate center and field of view;
- geometric refinement across all accepted correspondences;
- conservative minimum-match and residual policies;
- center RA/Dec, roll, horizontal/vertical FOV, plate scale, RMS residual, and
  confidence;
- auditable catalog-to-image matches in JSON and in the annotated image;
- a negative regression proving that unrelated point fields are not solved.

The current laboratory also provides:

- reflection-aware matching for the parity change between tangent-plane and
  image coordinates;
- quad fingerprints for an offline lost-in-space search;
- automatic removal of uniform near-black letterboxing without cropping a
  valid dark sky;
- a compact `CAMCAT01` catalog format and deterministic Gaia/BSC-compatible CSV
  converter;
- a fixture-matrix runner for repeatable accuracy and performance evidence;
- an Objective-C++ bridge in `CameraeVision`, intentionally not connected to
  camera capture or SwiftUI yet.

Without a catalog the laboratory reports `detectionCompleted`. It reports `solved`
only after catalog matching passes the support and residual policies.

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

To attempt a constrained solve, provide a catalog and approximate pointing:

```bash
vision/tools/run_plate_solving_lab.sh \
  --image /absolute/path/to/sky.png \
  --output /tmp/camerae-plate-solving \
  --catalog /absolute/path/to/bright-stars.csv \
  --approx-ra 266.4051 \
  --approx-dec -28.936175 \
  --approx-fov 60
```

The CSV contract is:

```csv
source_id,ra,dec,phot_g_mean_mag
123456789,266.4168,-29.0078,4.12
```

Coordinates use ICRS degrees and lower magnitude means a brighter source. Gaia
column names are accepted directly. Catalog preparation may access an official
archive, but detection and solving never use the network.

For a lost-in-space attempt, omit the sky center:

```bash
vision/tools/run_plate_solving_lab.sh \
  --image /absolute/path/to/sky.png \
  --output /tmp/camerae-plate-solving \
  --catalog /absolute/path/to/bright-stars.camcat \
  --lost-in-space \
  --approx-fov 70 \
  --minimum-matches 8 \
  --match-tolerance 16
```

Build the compact catalog from an authorized CSV export:

```bash
vision/tools/build_compact_star_catalog.py \
  --input /absolute/path/to/catalog.csv \
  --output /tmp/bright-stars.camcat \
  --maximum-magnitude 7
```

`CAMCAT01` stores a versioned signature, star count, float32 ICRS coordinates
and magnitude, plus a UTF-8 source identifier. The reference 1,170-star BSC5
validation export occupies about 20 KB instead of 47 KB as CSV.

## Fixture policy

Real photographs belong in `local-fixtures/plate-solving/`, which is ignored by
Git. A fixture may be committed later only after its redistribution rights and
location metadata have been reviewed. Production diagnostics must never include
the image, file path, location, observation time, or celestial coordinates.

The current external calibration matrix contains six non-versioned photographs:
two wide Milky Way fields, two portrait/letterboxed fields, and two difficult
low-contrast fields with foreground or sky glow. On the development Mac, all
six produced 572–927 candidates in 20–32 ms after active-region detection.
The solver accepts only reviewed fields with at least eight inliers; difficult
fields remain `notSolved` rather than returning a low-support false coordinate.

Run the same detection matrix without copying images into Git:

```bash
vision/tools/run_plate_solving_fixture_matrix.sh \
  /path/to/camerae-plate-solve-lab \
  /tmp/plate-fixture-matrix \
  /absolute/path/to/fixture-1.png \
  /absolute/path/to/fixture-2.png
```

## Next phases

1. Replace the runtime quad construction with a pre-indexed catalog lookup.
2. Expand constrained matching with optional location/time and lens hints.
3. Fit and validate radial lens distortion.
4. Obtain redistribution clearance for positive and negative golden fixtures.
5. Benchmark on reference iPhone hardware and establish memory/thermal gates.
6. Expose the bridge through a Swift service only after the hardware gates pass.

## Catalog provenance

The temporary real-data validation uses Gaia DR3 queried directly from the
official ESA archive. No downloaded catalog is committed in this phase. Any
catalog distributed with Camerae must carry the official Gaia/DPAC
acknowledgement and release citations:

- <https://gea.esac.esa.int/archive/>
- <https://gea.esac.esa.int/archive/documentation/GDR3/Miscellaneous/sec_credit_and_citation_instructions/>

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

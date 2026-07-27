# Camerae Plate-Solving Laboratory

Status: Phases 1 and 2 implemented

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

## Fixture policy

Real photographs belong in `local-fixtures/plate-solving/`, which is ignored by
Git. A fixture may be committed later only after its redistribution rights and
location metadata have been reviewed. Production diagnostics must never include
the image, file path, location, observation time, or celestial coordinates.

## Next phases

1. Define a compact, versioned binary bright-star catalog format.
2. Build deterministic triangle/quad invariants from catalog stars.
3. Expand constrained matching with optional location/time and lens hints.
4. Implement blind lost-in-space matching.
5. Fit and validate lens
   distortion.
6. Add several positive and negative golden fixtures.
7. Add an Objective-C++ bridge only after native accuracy and performance gates
   pass.

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

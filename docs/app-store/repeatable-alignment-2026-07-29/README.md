# Repeatable video alignment review — 2026-07-29

This review compares the midpoint frame from each of three authentic Repeatable
video pairs at their native 1720 × 1290 resolution.

## Method

- Camerae Vision `camerae-alignment-preview`
- SIFT, automatic least-flexible model selection
- maximum dimension 1720
- maximum 12,000 features
- mutual matching and CLAHE enabled
- RANSAC threshold from the Camerae Vision default
- ECC disabled

The automatic preflight remains deliberately conservative. Dynamic water,
clouds, trees, people, traffic, and major day/night exposure changes count as
local residuals even when the principal framing is visually close.

## Results

| Pair | Selected model | Inliers | Estimated correction | Valid overlap | Local edge error | Preflight |
| --- | --- | ---: | --- | ---: | ---: | --- |
| Statues, day/night | similarity | 4 / 59 | ~29 px left, 49 px down, 2.3° rotation, 0.9% scale | 98.3% | 9.41 px | reject |
| Lagoon, two conditions | similarity | 31 / 170 | ~7 px left, 6 px down, 0.45° rotation, 0.45% scale | 99.9% | 10.27 px | reject |
| Cathedral, day/night | similarity | 9 / 72 | ~9 px left, 7 px down, 0.35° rotation, 0.34% scale | 99.8% | 11.41 px | reject |

## Interpretation

- **Lagoon is the strongest framing result.** The estimated geometric
  correction is tiny. Rejection is driven by moving water, foliage, clouds, and
  low match consistency rather than a large camera displacement.
- **Cathedral is also geometrically close.** The small estimated correction is
  encouraging, but the day/night appearance change leaves too few distributed
  correspondences for automatic acceptance.
- **Statues needs the largest correction.** It is still recognizable as the same
  composition, but the estimated rotation and vertical displacement are
  materially larger than the other two pairs.
- These clips are valid marketing examples of Repeatable guidance. They should
  not be described as automatically aligned output: the current conservative
  quality gate correctly refuses to claim a reliable warp from these
  appearance-changing samples.

Each pair directory contains the full metrics, feasibility preview, 50/50
overlay, and red/cyan diagnostic.

# Repeatable video alignment validation — 2026-07-29

## Purpose

This validation turns the three manually approved Repeatable video experiments
into an executable mobile policy. The source clips remain external test media
and are not committed to the repository.

## Validated pairs

| Pair | Reference | Moving clip | Result with midpoint reference and five samples |
| --- | --- | --- | --- |
| Statues | `video 15.MOV` | `video 14.MOV` | Four stable transforms; one temporal outlier rejected |
| Lagoon | `video 9.MOV` | `video 11.MOV` | Five stable transforms |
| Cathedral | `video 4.MOV` | `video.MOV` | Four stable transforms; one temporal outlier rejected |

The validated pipeline uses:

- the midpoint frame of the first usable video as the fixed project reference;
- moving frames at 10%, 30%, 50%, 70%, and 90% of each later clip;
- SIFT with CLAHE, a 1720-pixel analysis limit, up to 12,000 features, mutual
  matching, and a 2.5-pixel RANSAC threshold;
- translation or similarity transforms only;
- temporal consensus before a contrast- or appearance-related low-confidence
  result can be reviewed and exported;
- one constant transform for the complete clip.

## Confidence policy

Low photometric confidence is not treated as proof of bad geometry. A rejected
sample caused only by feature count, match consistency, coverage, or local
appearance residual may participate in recovery when it has a finite
translation/similarity transform and at least 75% valid region.

At least three samples must agree within the existing transform-spread limit.
Recovery changes the reason to `temporallyConsistentAppearanceChange`; it does
not erase the review state.

The following remain hard blocks:

- insufficient overlap;
- invalid or projective geometry;
- extreme scale;
- excessive crop;
- temporally unstable transforms.

## Regression evidence

`VideoClipAlignmentAnalyzerTests` proves midpoint sampling, five-sample fixed
reference analysis, stable appearance-change recovery, unstable-transform
rejection, and cache invalidation.

`CameraeNextSessionCatalogTests` proves that the reference video cannot align
against itself, later videos retain the action, and legacy videos without a
saved reference frame do not become the project reference.

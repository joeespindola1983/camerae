#include "camerae_vision/automatic_alignment.hpp"

#include <array>
#include <optional>
#include <stdexcept>
#include <utility>

namespace camerae_vision {
namespace {

int decisionRank(AlignmentDecision decision) {
    switch (decision) {
    case AlignmentDecision::Reject:
        return 0;
    case AlignmentDecision::Review:
        return 1;
    case AlignmentDecision::Accept:
        return 2;
    }
    return 0;
}

bool shouldPromote(
    const AlignmentResult& current,
    const AlignmentResult& candidate,
    double localErrorRatio
) {
    const int currentRank = decisionRank(current.feasibility.decision);
    const int candidateRank = decisionRank(candidate.feasibility.decision);
    if (candidateRank != currentRank) {
        return candidateRank > currentRank;
    }
    if (candidateRank == 0) {
        return candidate.feasibility.score > current.feasibility.score;
    }
    return candidate.metrics.edgeAlignmentError <
        current.metrics.edgeAlignmentError * localErrorRatio;
}

} // namespace

AutomaticAlignmentResult alignImagesAutomatically(
    const cv::Mat& reference,
    const cv::Mat& moving,
    const AutomaticAlignmentSettings& settings
) {
    if (settings.affineLocalErrorRatio <= 0.0 || settings.affineLocalErrorRatio >= 1.0 ||
        settings.homographyLocalErrorRatio <= 0.0 || settings.homographyLocalErrorRatio >= 1.0) {
        throw std::invalid_argument("margens de selecao automatica devem estar entre 0 e 1");
    }

    AutomaticAlignmentResult automatic;
    std::optional<AlignmentResult> selected;
    AlignmentMotionModel selectedModel = AlignmentMotionModel::Similarity;
    const std::array<AlignmentMotionModel, 3> models = {
        AlignmentMotionModel::Similarity,
        AlignmentMotionModel::Affine,
        AlignmentMotionModel::Homography
    };

    for (const AlignmentMotionModel model : models) {
        AlignmentSettings modelSettings = settings.alignment;
        modelSettings.motionModel = model;
        AlignmentCandidateSummary summary;
        summary.model = model;
        try {
            AlignmentResult result = alignImages(reference, moving, modelSettings);
            summary.succeeded = true;
            summary.decision = result.feasibility.decision;
            summary.score = result.feasibility.score;
            summary.reprojectionRMSE = result.metrics.reprojectionRMSE;
            summary.edgeAlignmentError = result.metrics.edgeAlignmentError;

            const double promotionRatio = model == AlignmentMotionModel::Affine ?
                settings.affineLocalErrorRatio : settings.homographyLocalErrorRatio;
            if (!selected || shouldPromote(*selected, result, promotionRatio)) {
                selected = std::move(result);
                selectedModel = model;
            }
        } catch (const std::exception& error) {
            summary.failureReason = error.what();
        }
        automatic.candidates.push_back(std::move(summary));
    }

    if (!selected) {
        throw std::runtime_error("nenhum modelo final conseguiu estimar o alinhamento");
    }
    automatic.alignment = std::move(*selected);
    automatic.selectedModel = selectedModel;
    return automatic;
}

} // namespace camerae_vision

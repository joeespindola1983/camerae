#include "camerae_vision/alignment_quality.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <utility>

#include <opencv2/calib3d.hpp>
#include <opencv2/imgproc.hpp>

namespace camerae_vision {
namespace {

constexpr int captureFastMaxDimension = 640;
constexpr int captureFastMaxFeatures = 1200;
constexpr float captureFastMatchRatio = 0.78f;
constexpr double captureFastRansacThreshold = 3.0;
constexpr double affineMaterialImprovementRatio = 0.85;

struct PreparedImage {
    cv::Mat color;
    cv::Mat gray;
};

struct ModelEstimate {
    AlignmentMotionModel model = AlignmentMotionModel::Similarity;
    cv::Mat transform;
    cv::Mat inlierMask;
    int inliers = 0;
    double inlierRatio = 0.0;
    double reprojectionRMSE = std::numeric_limits<double>::infinity();
};

struct ModelGeometry {
    double overlapRatio = 0.0;
    double edgeAlignmentError = std::numeric_limits<double>::infinity();
};

PreparedImage prepareImage(const cv::Mat& input) {
    if (input.empty()) {
        throw std::invalid_argument("imagem vazia no avaliador de alinhamento");
    }

    cv::Mat color;
    if (input.channels() == 3) {
        color = input;
    } else if (input.channels() == 4) {
        cv::cvtColor(input, color, cv::COLOR_BGRA2BGR);
    } else if (input.channels() == 1) {
        cv::cvtColor(input, color, cv::COLOR_GRAY2BGR);
    } else {
        throw std::invalid_argument("formato de imagem nao suportado");
    }

    const int longestSide = std::max(color.cols, color.rows);
    if (longestSide > captureFastMaxDimension) {
        const double scale = static_cast<double>(captureFastMaxDimension) /
            static_cast<double>(longestSide);
        cv::resize(color, color, cv::Size(), scale, scale, cv::INTER_AREA);
    } else {
        color = color.clone();
    }

    cv::Mat gray;
    cv::cvtColor(color, gray, cv::COLOR_BGR2GRAY);
    return {.color = color, .gray = gray};
}

std::uint64_t imageSignature(const cv::Mat& image) {
    constexpr std::uint64_t offset = 1469598103934665603ULL;
    constexpr std::uint64_t prime = 1099511628211ULL;
    std::uint64_t hash = offset;
    const auto add = [&](std::uint8_t value, std::uint64_t& current) {
        current ^= value;
        current *= prime;
    };
    for (int value : {image.rows, image.cols, image.type()}) {
        for (int byte = 0; byte < 4; ++byte) {
            add(static_cast<std::uint8_t>((value >> (byte * 8)) & 0xff), hash);
        }
    }
    for (int row = 0; row < image.rows; ++row) {
        const auto* pixels = image.ptr<std::uint8_t>(row);
        for (std::size_t column = 0; column < image.step[0]; ++column) {
            add(pixels[column], hash);
        }
    }
    return hash;
}

std::vector<cv::DMatch> ratioMatches(
    const cv::Mat& query,
    const cv::Mat& train,
    const cv::BFMatcher& matcher
) {
    std::vector<std::vector<cv::DMatch>> candidates;
    matcher.knnMatch(query, train, candidates, 2);
    std::vector<cv::DMatch> accepted;
    for (const auto& pair : candidates) {
        if (pair.size() >= 2 && pair[0].distance < captureFastMatchRatio * pair[1].distance) {
            accepted.push_back(pair[0]);
        }
    }
    return accepted;
}

std::vector<cv::DMatch> mutualMatches(const cv::Mat& moving, const cv::Mat& reference) {
    const cv::BFMatcher matcher(cv::NORM_HAMMING, false);
    const auto forward = ratioMatches(moving, reference, matcher);
    const auto reverse = ratioMatches(reference, moving, matcher);
    std::vector<int> reverseLookup(reference.rows, -1);
    for (const auto& match : reverse) {
        reverseLookup[match.queryIdx] = match.trainIdx;
    }
    std::vector<cv::DMatch> result;
    for (const auto& match : forward) {
        if (match.trainIdx < static_cast<int>(reverseLookup.size()) &&
            reverseLookup[match.trainIdx] == match.queryIdx) {
            result.push_back(match);
        }
    }
    return result;
}

cv::Mat affineToHomography(const cv::Mat& affine) {
    cv::Mat transform = cv::Mat::eye(3, 3, CV_64F);
    cv::Mat converted;
    affine.convertTo(converted, CV_64F);
    converted.copyTo(transform(cv::Rect(0, 0, 3, 2)));
    return transform;
}

double reprojectionRMSE(
    const std::vector<cv::Point2f>& moving,
    const std::vector<cv::Point2f>& reference,
    const cv::Mat& transform,
    const cv::Mat& inlierMask
) {
    double squaredError = 0.0;
    int count = 0;
    for (int index = 0; index < static_cast<int>(moving.size()); ++index) {
        if (!inlierMask.empty() && inlierMask.at<unsigned char>(index) == 0) {
            continue;
        }
        const double x = moving[index].x;
        const double y = moving[index].y;
        const double projectedX = transform.at<double>(0, 0) * x +
            transform.at<double>(0, 1) * y + transform.at<double>(0, 2);
        const double projectedY = transform.at<double>(1, 0) * x +
            transform.at<double>(1, 1) * y + transform.at<double>(1, 2);
        const double dx = projectedX - reference[index].x;
        const double dy = projectedY - reference[index].y;
        squaredError += dx * dx + dy * dy;
        ++count;
    }
    return count == 0 ? std::numeric_limits<double>::infinity() :
        std::sqrt(squaredError / static_cast<double>(count));
}

ModelEstimate estimateModel(
    AlignmentMotionModel model,
    const std::vector<cv::Point2f>& moving,
    const std::vector<cv::Point2f>& reference
) {
    cv::Mat inlierMask;
    cv::Mat affine;
    if (model == AlignmentMotionModel::Similarity) {
        affine = cv::estimateAffinePartial2D(
            moving, reference, inlierMask, cv::RANSAC, captureFastRansacThreshold, 2000, 0.995, 10
        );
    } else {
        affine = cv::estimateAffine2D(
            moving, reference, inlierMask, cv::RANSAC, captureFastRansacThreshold, 2000, 0.995, 10
        );
    }
    if (affine.empty()) {
        return {.model = model};
    }
    const cv::Mat transform = affineToHomography(affine);
    const int inliers = cv::countNonZero(inlierMask);
    return {
        .model = model,
        .transform = transform,
        .inlierMask = inlierMask,
        .inliers = inliers,
        .inlierRatio = moving.empty() ? 0.0 : static_cast<double>(inliers) / moving.size(),
        .reprojectionRMSE = reprojectionRMSE(moving, reference, transform, inlierMask)
    };
}

double edgeError(const cv::Mat& reference, const cv::Mat& aligned, const cv::Mat& validMask) {
    cv::Mat referenceEdges;
    cv::Mat alignedEdges;
    cv::Canny(reference, referenceEdges, 60, 150);
    cv::Canny(aligned, alignedEdges, 60, 150);
    cv::Mat inverted;
    cv::threshold(alignedEdges, inverted, 0, 255, cv::THRESH_BINARY_INV);
    cv::Mat distance;
    cv::distanceTransform(inverted, distance, cv::DIST_L2, 3);
    cv::Mat sampleMask;
    cv::bitwise_and(referenceEdges, validMask, sampleMask);
    return cv::countNonZero(sampleMask) == 0 ? 20.0 : cv::mean(distance, sampleMask)[0];
}

ModelGeometry evaluateGeometry(
    const cv::Mat& reference,
    const cv::Mat& moving,
    const ModelEstimate& estimate
) {
    if (estimate.transform.empty()) {
        return {};
    }
    cv::Mat validSource(moving.size(), CV_8U, cv::Scalar(255));
    cv::Mat validMask;
    cv::warpPerspective(validSource, validMask, estimate.transform, reference.size(),
                        cv::INTER_NEAREST, cv::BORDER_CONSTANT, cv::Scalar(0));
    cv::Mat aligned;
    cv::warpPerspective(moving, aligned, estimate.transform, reference.size(),
                        cv::INTER_LINEAR, cv::BORDER_CONSTANT, cv::Scalar(0));
    return {
        .overlapRatio = static_cast<double>(cv::countNonZero(validMask)) / validMask.total(),
        .edgeAlignmentError = edgeError(reference, aligned, validMask)
    };
}

} // namespace

AlignmentQualityEvaluator::AlignmentQualityEvaluator(AlignmentQualityPreset preset)
    : preset_(preset) {
    if (preset_ != AlignmentQualityPreset::CaptureFast) {
        throw std::invalid_argument("preset de qualidade desconhecido");
    }
}

CaptureAlignmentQuality AlignmentQualityEvaluator::evaluate(
    const cv::Mat& referenceInput,
    const cv::Mat& movingInput
) {
    const auto started = std::chrono::steady_clock::now();
    const PreparedImage reference = prepareImage(referenceInput);
    PreparedImage moving = prepareImage(movingInput);
    if (moving.color.size() != reference.color.size()) {
        cv::resize(moving.color, moving.color, reference.color.size(), 0.0, 0.0, cv::INTER_AREA);
        cv::cvtColor(moving.color, moving.gray, cv::COLOR_BGR2GRAY);
    }

    const std::uint64_t signature = imageSignature(reference.gray);
    const cv::Ptr<cv::ORB> orb = cv::ORB::create(captureFastMaxFeatures);
    if (!hasReference_ || signature != referenceSignature_) {
        referenceGray_ = reference.gray;
        orb->detectAndCompute(referenceGray_, cv::noArray(), referenceKeypoints_, referenceDescriptors_);
        referenceSignature_ = signature;
        hasReference_ = true;
        ++diagnostics_.referenceFeatureExtractions;
        diagnostics_.estimatedReferenceCacheBytes =
            referenceGray_.total() * referenceGray_.elemSize() +
            referenceDescriptors_.total() * referenceDescriptors_.elemSize() +
            referenceKeypoints_.size() * sizeof(cv::KeyPoint);
    }

    std::vector<cv::KeyPoint> movingKeypoints;
    cv::Mat movingDescriptors;
    orb->detectAndCompute(moving.gray, cv::noArray(), movingKeypoints, movingDescriptors);
    if (referenceDescriptors_.empty() || movingDescriptors.empty()) {
        throw std::runtime_error("descritores insuficientes para avaliar alinhamento");
    }

    const auto matches = mutualMatches(movingDescriptors, referenceDescriptors_);
    if (matches.size() < 6) {
        throw std::runtime_error("correspondencias insuficientes para avaliar alinhamento");
    }
    std::vector<cv::Point2f> movingPoints;
    std::vector<cv::Point2f> referencePoints;
    for (const auto& match : matches) {
        movingPoints.push_back(movingKeypoints[match.queryIdx].pt);
        referencePoints.push_back(referenceKeypoints_[match.trainIdx].pt);
    }

    const ModelEstimate similarity = estimateModel(
        AlignmentMotionModel::Similarity, movingPoints, referencePoints
    );
    const ModelEstimate affine = estimateModel(AlignmentMotionModel::Affine, movingPoints, referencePoints);
    diagnostics_.similarityRMSE = similarity.reprojectionRMSE;
    diagnostics_.affineRMSE = affine.reprojectionRMSE;
    const ModelGeometry similarityGeometry = evaluateGeometry(reference.gray, moving.gray, similarity);
    const ModelGeometry affineGeometry = evaluateGeometry(reference.gray, moving.gray, affine);
    diagnostics_.similarityEdgeAlignmentError = similarityGeometry.edgeAlignmentError;
    diagnostics_.affineEdgeAlignmentError = affineGeometry.edgeAlignmentError;
    if (similarity.transform.empty() && affine.transform.empty()) {
        throw std::runtime_error("nao foi possivel estimar um modelo rapido");
    }
    const ModelEstimate* selected = &similarity;
    const ModelGeometry* selectedGeometry = &similarityGeometry;
    if (similarity.transform.empty() ||
        (!affine.transform.empty() &&
         affineGeometry.edgeAlignmentError <
             similarityGeometry.edgeAlignmentError * affineMaterialImprovementRatio)) {
        selected = &affine;
        selectedGeometry = &affineGeometry;
    }

    const double overlap = selectedGeometry->overlapRatio;
    const double localEdgeError = selectedGeometry->edgeAlignmentError;

    const double a = selected->transform.at<double>(0, 0);
    const double b = selected->transform.at<double>(0, 1);
    const double c = selected->transform.at<double>(1, 0);
    const double d = selected->transform.at<double>(1, 1);
    const double scaleX = std::hypot(a, c);
    const double scaleY = std::hypot(b, d);
    const double areaRatio = std::abs(a * d - b * c);

    CaptureAlignmentQuality quality;
    quality.selectedModel = selected->model;
    quality.transform = selected->transform.clone();
    quality.overlapRatio = overlap;
    quality.reprojectionRMSE = selected->reprojectionRMSE;
    quality.edgeAlignmentError = localEdgeError;
    double score = 1.0;
    bool reject = false;
    const auto hardFailure = [&](bool condition, double penalty, AlignmentReasonCode code,
                                 const std::string& reason) {
        if (condition) {
            reject = true;
            score -= penalty;
            quality.reasonCodes.push_back(code);
            quality.reasons.push_back(reason);
        }
    };
    const auto warning = [&](bool condition, double penalty, AlignmentReasonCode code,
                             const std::string& reason) {
        if (condition) {
            score -= penalty;
            quality.reasonCodes.push_back(code);
            quality.reasons.push_back(reason);
        }
    };
    hardFailure(selected->inliers < 20, 0.55, AlignmentReasonCode::InsufficientInliers,
                "poucos pontos geometricamente consistentes");
    hardFailure(selected->inlierRatio < 0.25, 0.45, AlignmentReasonCode::InconsistentMatches,
                "correspondencias inconsistentes");
    hardFailure(overlap < 0.55, 0.45, AlignmentReasonCode::InsufficientOverlap,
                "menos de 55% da imagem permanece util");
    hardFailure(selected->reprojectionRMSE > 6.0, 0.45,
                AlignmentReasonCode::HighReprojectionError, "erro geometrico muito alto");
    hardFailure(areaRatio < 0.35 || areaRatio > 2.0, 0.55,
                AlignmentReasonCode::ExtremeAreaChange, "mudanca de area extrema");
    hardFailure(std::min(scaleX, scaleY) < 0.35 || std::max(scaleX, scaleY) > 2.5,
                0.55, AlignmentReasonCode::ExtremeEdgeScale, "escala extrema");
    hardFailure(localEdgeError > 8.0, 0.40, AlignmentReasonCode::HighLocalResidual,
                "residuo local muito alto");
    warning(!reject && overlap < 0.80, 0.18, AlignmentReasonCode::LargeCrop,
            "recorte necessario e grande");
    warning(!reject && selected->reprojectionRMSE > 2.0, 0.15,
            AlignmentReasonCode::HighReprojectionError, "erro geometrico acima do ideal");
    warning(!reject && localEdgeError > 3.5, 0.25,
            AlignmentReasonCode::PossibleParallaxOrMotion, "residuo local acima do ideal");
    quality.score = std::clamp(score, 0.0, 1.0);
    quality.decision = reject ? AlignmentDecision::Reject :
        (quality.reasons.empty() && quality.score >= 0.80 ? AlignmentDecision::Accept :
                                                            AlignmentDecision::Review);
    if (quality.decision == AlignmentDecision::Accept) {
        quality.reasonCodes.push_back(AlignmentReasonCode::StableGeometry);
        quality.reasons.push_back("geometria estavel e deformacao dentro dos limites");
    }
    quality.estimatedLatencyMilliseconds = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - started
    ).count();
    return quality;
}

const AlignmentQualityDiagnostics& AlignmentQualityEvaluator::diagnostics() const {
    return diagnostics_;
}

void AlignmentQualityEvaluator::resetReference() {
    hasReference_ = false;
    referenceSignature_ = 0;
    referenceGray_.release();
    referenceKeypoints_.clear();
    referenceDescriptors_.release();
    diagnostics_.estimatedReferenceCacheBytes = 0;
}

} // namespace camerae_vision

#include "camerae_vision/alignment.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <limits>
#include <numeric>
#include <stdexcept>
#include <unordered_map>
#include <vector>

#include <opencv2/calib3d.hpp>
#include <opencv2/features2d.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/video/tracking.hpp>

namespace camerae_vision {
namespace {

struct PreparedPair {
    cv::Mat reference;
    cv::Mat moving;
};

std::string lowercased(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

cv::Mat ensureBGR(const cv::Mat& image) {
    if (image.empty()) {
        throw std::invalid_argument("imagem vazia");
    }
    if (image.channels() == 3) {
        return image;
    }

    cv::Mat converted;
    if (image.channels() == 1) {
        cv::cvtColor(image, converted, cv::COLOR_GRAY2BGR);
    } else if (image.channels() == 4) {
        cv::cvtColor(image, converted, cv::COLOR_BGRA2BGR);
    } else {
        throw std::invalid_argument("formato de imagem nao suportado");
    }
    return converted;
}

cv::Mat resizeToMaxDimension(const cv::Mat& image, int maxDimension) {
    if (maxDimension <= 0 || std::max(image.cols, image.rows) <= maxDimension) {
        return image;
    }

    const double scale = static_cast<double>(maxDimension) /
        static_cast<double>(std::max(image.cols, image.rows));
    cv::Mat resized;
    cv::resize(image, resized, cv::Size(), scale, scale, cv::INTER_AREA);
    return resized;
}

PreparedPair preparePair(const cv::Mat& referenceInput, const cv::Mat& movingInput, int maxDimension) {
    cv::Mat reference = resizeToMaxDimension(ensureBGR(referenceInput), maxDimension);
    cv::Mat moving = resizeToMaxDimension(ensureBGR(movingInput), maxDimension);
    if (moving.size() != reference.size()) {
        cv::resize(moving, moving, reference.size(), 0.0, 0.0, cv::INTER_AREA);
    }
    return {reference, moving};
}

cv::Mat alignmentGray(const cv::Mat& image, bool useCLAHE) {
    cv::Mat gray;
    cv::cvtColor(image, gray, cv::COLOR_BGR2GRAY);
    if (useCLAHE) {
        cv::Ptr<cv::CLAHE> clahe = cv::createCLAHE(2.0, cv::Size(8, 8));
        cv::Mat enhanced;
        clahe->apply(gray, enhanced);
        return enhanced;
    }
    return gray;
}

cv::Ptr<cv::Feature2D> createDetector(const AlignmentSettings& settings, int& matcherNorm) {
    switch (settings.detector) {
    case AlignmentDetector::ORB:
        matcherNorm = cv::NORM_HAMMING;
        return cv::ORB::create(settings.maxFeatures);
    case AlignmentDetector::AKAZE:
        matcherNorm = cv::NORM_HAMMING;
        return cv::AKAZE::create();
    case AlignmentDetector::SIFT:
        matcherNorm = cv::NORM_L2;
        return cv::SIFT::create(settings.maxFeatures);
    }
    throw std::invalid_argument("detector de alinhamento invalido");
}

std::vector<cv::DMatch> ratioMatches(
    const cv::Mat& queryDescriptors,
    const cv::Mat& trainDescriptors,
    int matcherNorm,
    float ratio
) {
    cv::BFMatcher matcher(matcherNorm, false);
    std::vector<std::vector<cv::DMatch>> candidates;
    matcher.knnMatch(queryDescriptors, trainDescriptors, candidates, 2);

    std::vector<cv::DMatch> matches;
    matches.reserve(candidates.size());
    for (const auto& pair : candidates) {
        if (pair.size() >= 2 && pair[0].distance < ratio * pair[1].distance) {
            matches.push_back(pair[0]);
        }
    }
    return matches;
}

std::vector<cv::DMatch> matchDescriptors(
    const cv::Mat& movingDescriptors,
    const cv::Mat& referenceDescriptors,
    int matcherNorm,
    const AlignmentSettings& settings
) {
    auto forward = ratioMatches(
        movingDescriptors,
        referenceDescriptors,
        matcherNorm,
        settings.matchRatio
    );
    if (!settings.mutualMatching) {
        return forward;
    }

    const auto reverse = ratioMatches(
        referenceDescriptors,
        movingDescriptors,
        matcherNorm,
        settings.matchRatio
    );
    std::unordered_map<int, int> reversePairs;
    reversePairs.reserve(reverse.size());
    for (const auto& match : reverse) {
        reversePairs[match.queryIdx] = match.trainIdx;
    }

    forward.erase(
        std::remove_if(forward.begin(), forward.end(), [&](const cv::DMatch& match) {
            const auto reverseMatch = reversePairs.find(match.trainIdx);
            return reverseMatch == reversePairs.end() || reverseMatch->second != match.queryIdx;
        }),
        forward.end()
    );
    return forward;
}

cv::Mat translationFromMatches(
    const std::vector<cv::Point2f>& movingPoints,
    const std::vector<cv::Point2f>& referencePoints,
    double threshold,
    cv::Mat& inlierMask
) {
    std::vector<double> dx;
    std::vector<double> dy;
    dx.reserve(movingPoints.size());
    dy.reserve(movingPoints.size());
    for (std::size_t index = 0; index < movingPoints.size(); ++index) {
        dx.push_back(referencePoints[index].x - movingPoints[index].x);
        dy.push_back(referencePoints[index].y - movingPoints[index].y);
    }

    const auto middleX = dx.begin() + static_cast<std::ptrdiff_t>(dx.size() / 2);
    const auto middleY = dy.begin() + static_cast<std::ptrdiff_t>(dy.size() / 2);
    std::nth_element(dx.begin(), middleX, dx.end());
    std::nth_element(dy.begin(), middleY, dy.end());
    const double translateX = *middleX;
    const double translateY = *middleY;

    inlierMask = cv::Mat::zeros(static_cast<int>(movingPoints.size()), 1, CV_8U);
    for (int index = 0; index < static_cast<int>(movingPoints.size()); ++index) {
        const double residualX = referencePoints[index].x - movingPoints[index].x - translateX;
        const double residualY = referencePoints[index].y - movingPoints[index].y - translateY;
        if (std::hypot(residualX, residualY) <= threshold) {
            inlierMask.at<unsigned char>(index) = 1;
        }
    }

    return (cv::Mat_<double>(3, 3) <<
        1.0, 0.0, translateX,
        0.0, 1.0, translateY,
        0.0, 0.0, 1.0
    );
}

cv::Mat affineToHomography(const cv::Mat& affine) {
    if (affine.empty()) {
        return {};
    }
    cv::Mat affine64;
    affine.convertTo(affine64, CV_64F);
    cv::Mat transform = cv::Mat::eye(3, 3, CV_64F);
    affine64.copyTo(transform(cv::Rect(0, 0, 3, 2)));
    return transform;
}

cv::Mat estimateTransform(
    const std::vector<cv::Point2f>& movingPoints,
    const std::vector<cv::Point2f>& referencePoints,
    const AlignmentSettings& settings,
    cv::Mat& inlierMask
) {
    switch (settings.motionModel) {
    case AlignmentMotionModel::Translation:
        return translationFromMatches(
            movingPoints,
            referencePoints,
            settings.ransacThreshold,
            inlierMask
        );
    case AlignmentMotionModel::Similarity:
        return affineToHomography(cv::estimateAffinePartial2D(
            movingPoints,
            referencePoints,
            inlierMask,
            cv::RANSAC,
            settings.ransacThreshold,
            settings.ransacMaxIterations,
            settings.ransacConfidence,
            10
        ));
    case AlignmentMotionModel::Affine:
        return affineToHomography(cv::estimateAffine2D(
            movingPoints,
            referencePoints,
            inlierMask,
            cv::RANSAC,
            settings.ransacThreshold,
            settings.ransacMaxIterations,
            settings.ransacConfidence,
            10
        ));
    case AlignmentMotionModel::Homography:
        return cv::findHomography(
            movingPoints,
            referencePoints,
            cv::RANSAC,
            settings.ransacThreshold,
            inlierMask,
            settings.ransacMaxIterations,
            settings.ransacConfidence
        );
    }
    return {};
}

int minimumMatchCount(AlignmentMotionModel model) {
    switch (model) {
    case AlignmentMotionModel::Translation:
        return 1;
    case AlignmentMotionModel::Similarity:
        return 2;
    case AlignmentMotionModel::Affine:
        return 3;
    case AlignmentMotionModel::Homography:
        return 4;
    }
    return 4;
}

double reprojectionRMSE(
    const std::vector<cv::Point2f>& movingPoints,
    const std::vector<cv::Point2f>& referencePoints,
    const cv::Mat& transform,
    const cv::Mat& inlierMask
) {
    std::vector<cv::Point2f> projected;
    cv::perspectiveTransform(movingPoints, projected, transform);

    double squaredError = 0.0;
    int count = 0;
    for (int index = 0; index < static_cast<int>(projected.size()); ++index) {
        if (!inlierMask.empty() && inlierMask.at<unsigned char>(index) == 0) {
            continue;
        }
        const double dx = projected[index].x - referencePoints[index].x;
        const double dy = projected[index].y - referencePoints[index].y;
        squaredError += dx * dx + dy * dy;
        ++count;
    }
    return count > 0 ? std::sqrt(squaredError / static_cast<double>(count)) : 0.0;
}

double maskedGrayMAE(const cv::Mat& first, const cv::Mat& second, const cv::Mat& mask) {
    cv::Mat firstGray;
    cv::Mat secondGray;
    cv::cvtColor(first, firstGray, cv::COLOR_BGR2GRAY);
    cv::cvtColor(second, secondGray, cv::COLOR_BGR2GRAY);
    cv::Mat difference;
    cv::absdiff(firstGray, secondGray, difference);
    return cv::mean(difference, mask)[0];
}

double inlierPointCoverage(
    const std::vector<cv::Point2f>& points,
    const cv::Mat& inlierMask,
    const cv::Size& imageSize
) {
    std::vector<cv::Point2f> inliers;
    for (int index = 0; index < static_cast<int>(points.size()); ++index) {
        if (inlierMask.empty() || inlierMask.at<unsigned char>(index) != 0) {
            inliers.push_back(points[index]);
        }
    }
    if (inliers.size() < 3) {
        return 0.0;
    }
    std::vector<cv::Point2f> hull;
    cv::convexHull(inliers, hull);
    const double imageArea = static_cast<double>(imageSize.width) * imageSize.height;
    return imageArea > 0.0 ? std::abs(cv::contourArea(hull)) / imageArea : 0.0;
}

double inlierGridCoverage(
    const std::vector<cv::Point2f>& movingPoints,
    const std::vector<cv::Point2f>& referencePoints,
    const cv::Mat& inlierMask,
    const cv::Size& imageSize
) {
    constexpr int gridColumns = 4;
    constexpr int gridRows = 4;
    std::array<bool, gridColumns * gridRows> occupied{};
    for (int index = 0; index < static_cast<int>(movingPoints.size()); ++index) {
        if (!inlierMask.empty() && inlierMask.at<unsigned char>(index) == 0) {
            continue;
        }
        const cv::Point2f midpoint = (movingPoints[index] + referencePoints[index]) * 0.5f;
        const int column = std::clamp(
            static_cast<int>(midpoint.x * gridColumns / imageSize.width),
            0,
            gridColumns - 1
        );
        const int row = std::clamp(
            static_cast<int>(midpoint.y * gridRows / imageSize.height),
            0,
            gridRows - 1
        );
        occupied[row * gridColumns + column] = true;
    }
    return static_cast<double>(std::count(occupied.begin(), occupied.end(), true)) /
        static_cast<double>(occupied.size());
}

struct ProjectionMetrics {
    double areaRatio = 0.0;
    double minimumEdgeScale = 0.0;
    double maximumEdgeScale = 0.0;
    double maximumCornerDisplacementRatio = 0.0;
    bool convex = false;
};

ProjectionMetrics projectionMetrics(const cv::Mat& transform, const cv::Size& imageSize) {
    const float width = static_cast<float>(imageSize.width);
    const float height = static_cast<float>(imageSize.height);
    const std::vector<cv::Point2f> corners = {
        {0.0f, 0.0f},
        {width, 0.0f},
        {width, height},
        {0.0f, height}
    };
    std::vector<cv::Point2f> projected;
    cv::perspectiveTransform(corners, projected, transform);

    ProjectionMetrics metrics;
    const double sourceArea = static_cast<double>(imageSize.area());
    metrics.areaRatio = sourceArea > 0.0 ? std::abs(cv::contourArea(projected)) / sourceArea : 0.0;
    metrics.convex = cv::isContourConvex(projected);
    metrics.minimumEdgeScale = std::numeric_limits<double>::max();
    metrics.maximumEdgeScale = 0.0;
    const double diagonal = std::hypot(width, height);
    for (int index = 0; index < 4; ++index) {
        const int next = (index + 1) % 4;
        const double sourceLength = cv::norm(corners[next] - corners[index]);
        const double projectedLength = cv::norm(projected[next] - projected[index]);
        const double scale = sourceLength > 0.0 ? projectedLength / sourceLength : 0.0;
        metrics.minimumEdgeScale = std::min(metrics.minimumEdgeScale, scale);
        metrics.maximumEdgeScale = std::max(metrics.maximumEdgeScale, scale);
        metrics.maximumCornerDisplacementRatio = std::max(
            metrics.maximumCornerDisplacementRatio,
            diagonal > 0.0 ? cv::norm(projected[index] - corners[index]) / diagonal : 0.0
        );
    }
    return metrics;
}

double directionalEdgeError(const cv::Mat& sourceEdges, const cv::Mat& targetEdges, const cv::Mat& validMask) {
    cv::Mat invertedTarget;
    cv::bitwise_not(targetEdges, invertedTarget);
    cv::Mat distance;
    cv::distanceTransform(invertedTarget, distance, cv::DIST_L2, 3);
    cv::min(distance, 20.0, distance);

    cv::Mat sampleMask;
    cv::bitwise_and(sourceEdges, validMask, sampleMask);
    if (cv::countNonZero(sampleMask) == 0) {
        return 20.0;
    }
    return cv::mean(distance, sampleMask)[0];
}

double symmetricEdgeAlignmentError(const cv::Mat& reference, const cv::Mat& aligned, const cv::Mat& validMask) {
    cv::Mat referenceGray;
    cv::Mat alignedGray;
    cv::cvtColor(reference, referenceGray, cv::COLOR_BGR2GRAY);
    cv::cvtColor(aligned, alignedGray, cv::COLOR_BGR2GRAY);
    cv::GaussianBlur(referenceGray, referenceGray, cv::Size(5, 5), 1.0);
    cv::GaussianBlur(alignedGray, alignedGray, cv::Size(5, 5), 1.0);

    cv::Mat referenceEdges;
    cv::Mat alignedEdges;
    cv::Canny(referenceGray, referenceEdges, 60, 150);
    cv::Canny(alignedGray, alignedEdges, 60, 150);
    cv::Mat interiorMask;
    cv::erode(
        validMask,
        interiorMask,
        cv::getStructuringElement(cv::MORPH_RECT, cv::Size(11, 11))
    );
    return 0.5 * (
        directionalEdgeError(referenceEdges, alignedEdges, interiorMask) +
        directionalEdgeError(alignedEdges, referenceEdges, interiorMask)
    );
}

AlignmentFeasibility evaluateFeasibility(const AlignmentMetrics& metrics, bool projectionIsConvex) {
    AlignmentFeasibility feasibility;
    double score = 1.0;
    bool reject = false;

    const auto hardFailure = [&](bool condition, double penalty, const std::string& reason) {
        if (condition) {
            reject = true;
            score -= penalty;
            feasibility.reasons.push_back(reason);
        }
    };
    const auto warning = [&](bool condition, double penalty, const std::string& reason) {
        if (condition) {
            score -= penalty;
            feasibility.reasons.push_back(reason);
        }
    };

    hardFailure(metrics.inlierMatches < 20, 0.55, "poucos pontos geometricamente consistentes");
    hardFailure(metrics.inlierRatio < 0.25, 0.45, "a maioria das correspondencias e inconsistente");
    hardFailure(metrics.inlierCoverageRatio < 0.05, 0.45, "pontos concentrados em uma area muito pequena");
    hardFailure(metrics.overlapRatio < 0.55, 0.45, "menos de 55% da imagem permanece util");
    hardFailure(metrics.reprojectionRMSE > 6.0, 0.45, "erro geometrico muito alto");
    hardFailure(!projectionIsConvex, 0.70, "a transformacao dobra ou inverte o quadro");
    hardFailure(metrics.projectedAreaRatio < 0.35 || metrics.projectedAreaRatio > 2.0,
                0.55, "mudanca de area extrema");
    hardFailure(metrics.minimumEdgeScale < 0.35 || metrics.maximumEdgeScale > 2.5,
                0.55, "escala extrema em uma borda");
    hardFailure(metrics.edgeAlignmentError > 8.0, 0.40,
                "residuo local muito alto; possivel paralaxe ou cena movel");

    warning(!reject && metrics.inlierRatio < 0.65, 0.15, "consistencia de matches moderada");
    warning(!reject && metrics.inlierCoverageRatio < 0.20, 0.18,
            "pontos nao cobrem bem o quadro");
    warning(!reject && metrics.inlierGridCoverageRatio < 0.25, 0.12,
            "pontos ausentes em varias regioes do quadro");
    warning(!reject && metrics.overlapRatio < 0.80, 0.18, "recorte necessario e grande");
    warning(!reject && metrics.reprojectionRMSE > 2.0, 0.15, "erro geometrico acima do ideal");
    warning(!reject && (metrics.projectedAreaRatio < 0.70 || metrics.projectedAreaRatio > 1.35),
            0.15, "mudanca de area relevante");
    warning(!reject && (metrics.minimumEdgeScale < 0.70 || metrics.maximumEdgeScale > 1.40),
            0.18, "deformacao de borda perceptivel");
    warning(!reject && metrics.maximumCornerDisplacementRatio > 0.40,
            0.15, "deslocamento de quadro muito grande");
    warning(!reject && metrics.edgeAlignmentError > 3.5, 0.25,
            "residuo local sugere paralaxe, vento ou objetos moveis");

    feasibility.score = std::clamp(score, 0.0, 1.0);
    if (reject) {
        feasibility.decision = AlignmentDecision::Reject;
    } else if (!feasibility.reasons.empty() || feasibility.score < 0.80) {
        feasibility.decision = AlignmentDecision::Review;
    } else {
        feasibility.decision = AlignmentDecision::Accept;
        feasibility.reasons.push_back("geometria estavel e deformacao dentro dos limites");
    }
    return feasibility;
}

double refineECC(
    const cv::Mat& reference,
    const cv::Mat& moving,
    const AlignmentSettings& settings,
    cv::Mat& movingToReference
) {
    cv::Mat referenceGray = alignmentGray(reference, settings.useCLAHE);
    cv::Mat movingGray = alignmentGray(moving, settings.useCLAHE);
    referenceGray.convertTo(referenceGray, CV_32F, 1.0 / 255.0);
    movingGray.convertTo(movingGray, CV_32F, 1.0 / 255.0);

    cv::Mat referenceToMoving = movingToReference.inv();
    int eccMotionModel = cv::MOTION_HOMOGRAPHY;
    bool usesAffineMatrix = false;
    switch (settings.motionModel) {
    case AlignmentMotionModel::Translation:
        eccMotionModel = cv::MOTION_TRANSLATION;
        usesAffineMatrix = true;
        break;
    case AlignmentMotionModel::Similarity:
        eccMotionModel = cv::MOTION_EUCLIDEAN;
        usesAffineMatrix = true;
        break;
    case AlignmentMotionModel::Affine:
        eccMotionModel = cv::MOTION_AFFINE;
        usesAffineMatrix = true;
        break;
    case AlignmentMotionModel::Homography:
        eccMotionModel = cv::MOTION_HOMOGRAPHY;
        break;
    }
    if (usesAffineMatrix) {
        referenceToMoving = referenceToMoving(cv::Rect(0, 0, 3, 2)).clone();
    }
    referenceToMoving.convertTo(referenceToMoving, CV_32F);
    const cv::TermCriteria criteria(
        cv::TermCriteria::COUNT | cv::TermCriteria::EPS,
        settings.eccIterations,
        settings.eccEpsilon
    );
    const double correlation = cv::findTransformECC(
        referenceGray,
        movingGray,
        referenceToMoving,
        eccMotionModel,
        criteria,
        cv::noArray(),
        5
    );
    if (usesAffineMatrix) {
        referenceToMoving = affineToHomography(referenceToMoving);
    }
    movingToReference = referenceToMoving.inv();
    movingToReference.convertTo(movingToReference, CV_64F);
    return correlation;
}

} // namespace

AlignmentResult alignImages(
    const cv::Mat& referenceInput,
    const cv::Mat& movingInput,
    const AlignmentSettings& settings
) {
    if (settings.matchRatio <= 0.0f || settings.matchRatio >= 1.0f) {
        throw std::invalid_argument("matchRatio deve estar entre 0 e 1");
    }

    const PreparedPair images = preparePair(referenceInput, movingInput, settings.maxDimension);
    const cv::Mat referenceGray = alignmentGray(images.reference, settings.useCLAHE);
    const cv::Mat movingGray = alignmentGray(images.moving, settings.useCLAHE);

    int matcherNorm = cv::NORM_HAMMING;
    const cv::Ptr<cv::Feature2D> detector = createDetector(settings, matcherNorm);
    std::vector<cv::KeyPoint> referenceKeypoints;
    std::vector<cv::KeyPoint> movingKeypoints;
    cv::Mat referenceDescriptors;
    cv::Mat movingDescriptors;
    detector->detectAndCompute(referenceGray, cv::noArray(), referenceKeypoints, referenceDescriptors);
    detector->detectAndCompute(movingGray, cv::noArray(), movingKeypoints, movingDescriptors);

    if (referenceDescriptors.empty() || movingDescriptors.empty()) {
        throw std::runtime_error("nao foi possivel extrair descritores suficientes");
    }

    const auto matches = matchDescriptors(
        movingDescriptors,
        referenceDescriptors,
        matcherNorm,
        settings
    );
    if (static_cast<int>(matches.size()) < minimumMatchCount(settings.motionModel)) {
        throw std::runtime_error("correspondencias insuficientes para estimar o modelo geometrico");
    }

    std::vector<cv::Point2f> movingPoints;
    std::vector<cv::Point2f> referencePoints;
    movingPoints.reserve(matches.size());
    referencePoints.reserve(matches.size());
    for (const auto& match : matches) {
        movingPoints.push_back(movingKeypoints[match.queryIdx].pt);
        referencePoints.push_back(referenceKeypoints[match.trainIdx].pt);
    }

    cv::Mat inlierMask;
    cv::Mat transform = estimateTransform(
        movingPoints,
        referencePoints,
        settings,
        inlierMask
    );
    if (transform.empty() || !cv::checkRange(transform)) {
        throw std::runtime_error("nao foi possivel estimar uma transformacao valida");
    }
    transform.convertTo(transform, CV_64F);

    double eccCorrelation = 0.0;
    if (settings.refineWithECC) {
        try {
            eccCorrelation = refineECC(images.reference, images.moving, settings, transform);
        } catch (const cv::Exception&) {
            eccCorrelation = -1.0;
        }
    }

    cv::Mat aligned;
    cv::warpPerspective(
        images.moving,
        aligned,
        transform,
        images.reference.size(),
        cv::INTER_LINEAR,
        cv::BORDER_CONSTANT,
        cv::Scalar::all(0)
    );

    cv::Mat sourceMask(images.moving.size(), CV_8U, cv::Scalar(255));
    cv::Mat validMask;
    cv::warpPerspective(
        sourceMask,
        validMask,
        transform,
        images.reference.size(),
        cv::INTER_NEAREST,
        cv::BORDER_CONSTANT,
        cv::Scalar::all(0)
    );

    const int inlierCount = inlierMask.empty() ? 0 : cv::countNonZero(inlierMask);
    AlignmentMetrics metrics;
    metrics.referenceKeypoints = static_cast<int>(referenceKeypoints.size());
    metrics.movingKeypoints = static_cast<int>(movingKeypoints.size());
    metrics.candidateMatches = static_cast<int>(matches.size());
    metrics.inlierMatches = inlierCount;
    metrics.inlierRatio = matches.empty() ? 0.0 :
        static_cast<double>(inlierCount) / static_cast<double>(matches.size());
    metrics.reprojectionRMSE = reprojectionRMSE(
        movingPoints,
        referencePoints,
        transform,
        inlierMask
    );
    metrics.overlapRatio = static_cast<double>(cv::countNonZero(validMask)) /
        static_cast<double>(validMask.total());
    metrics.grayMAEBefore = maskedGrayMAE(
        images.reference,
        images.moving,
        cv::Mat(images.reference.size(), CV_8U, cv::Scalar(255))
    );
    metrics.grayMAEAfter = maskedGrayMAE(images.reference, aligned, validMask);
    metrics.eccCorrelation = eccCorrelation;
    metrics.inlierCoverageRatio = std::min(
        inlierPointCoverage(movingPoints, inlierMask, images.reference.size()),
        inlierPointCoverage(referencePoints, inlierMask, images.reference.size())
    );
    metrics.inlierGridCoverageRatio = inlierGridCoverage(
        movingPoints,
        referencePoints,
        inlierMask,
        images.reference.size()
    );
    const ProjectionMetrics projection = projectionMetrics(transform, images.reference.size());
    metrics.projectedAreaRatio = projection.areaRatio;
    metrics.minimumEdgeScale = projection.minimumEdgeScale;
    metrics.maximumEdgeScale = projection.maximumEdgeScale;
    metrics.maximumCornerDisplacementRatio = projection.maximumCornerDisplacementRatio;
    metrics.edgeAlignmentError = symmetricEdgeAlignmentError(images.reference, aligned, validMask) *
        (1920.0 / static_cast<double>(std::max(images.reference.cols, images.reference.rows)));
    const AlignmentFeasibility feasibility = evaluateFeasibility(metrics, projection.convex);

    std::vector<char> drawMask(matches.size(), 0);
    for (int index = 0; index < static_cast<int>(matches.size()); ++index) {
        drawMask[index] = inlierMask.empty() ? 1 : inlierMask.at<unsigned char>(index) != 0;
    }
    cv::Mat matchVisualization;
    cv::drawMatches(
        images.moving,
        movingKeypoints,
        images.reference,
        referenceKeypoints,
        matches,
        matchVisualization,
        cv::Scalar(80, 220, 80),
        cv::Scalar(80, 80, 220),
        drawMask,
        cv::DrawMatchesFlags::NOT_DRAW_SINGLE_POINTS
    );

    return {
        .alignedImage = aligned,
        .validMask = validMask,
        .transform = transform,
        .matchVisualization = matchVisualization,
        .metrics = metrics,
        .feasibility = feasibility
    };
}

cv::Mat makeAlignmentOverlay(
    const cv::Mat& referenceInput,
    const cv::Mat& alignedInput,
    const cv::Mat& validMask,
    double movingOpacity
) {
    const cv::Mat reference = ensureBGR(referenceInput);
    const cv::Mat aligned = ensureBGR(alignedInput);
    if (reference.size() != aligned.size() || reference.size() != validMask.size()) {
        throw std::invalid_argument("reference, aligned e mask devem ter o mesmo tamanho");
    }

    const double opacity = std::clamp(movingOpacity, 0.0, 1.0);
    cv::Mat blended;
    cv::addWeighted(reference, 1.0 - opacity, aligned, opacity, 0.0, blended);
    cv::Mat output = reference.clone();
    blended.copyTo(output, validMask);
    return output;
}

cv::Mat makeAlignmentDifference(
    const cv::Mat& referenceInput,
    const cv::Mat& alignedInput,
    const cv::Mat& validMask
) {
    const cv::Mat reference = ensureBGR(referenceInput);
    const cv::Mat aligned = ensureBGR(alignedInput);
    cv::Mat referenceGray;
    cv::Mat alignedGray;
    cv::cvtColor(reference, referenceGray, cv::COLOR_BGR2GRAY);
    cv::cvtColor(aligned, alignedGray, cv::COLOR_BGR2GRAY);
    cv::Mat difference;
    cv::absdiff(referenceGray, alignedGray, difference);
    cv::normalize(difference, difference, 0, 255, cv::NORM_MINMAX, CV_8U, validMask);
    cv::Mat heatmap;
    cv::applyColorMap(difference, heatmap, cv::COLORMAP_TURBO);
    heatmap.setTo(cv::Scalar::all(0), validMask == 0);
    return heatmap;
}

cv::Mat makeAlignmentRedCyan(
    const cv::Mat& referenceInput,
    const cv::Mat& alignedInput,
    const cv::Mat& validMask
) {
    const cv::Mat reference = ensureBGR(referenceInput);
    const cv::Mat aligned = ensureBGR(alignedInput);
    if (reference.size() != aligned.size() || reference.size() != validMask.size()) {
        throw std::invalid_argument("reference, aligned e mask devem ter o mesmo tamanho");
    }

    cv::Mat referenceGray;
    cv::Mat alignedGray;
    cv::cvtColor(reference, referenceGray, cv::COLOR_BGR2GRAY);
    cv::cvtColor(aligned, alignedGray, cv::COLOR_BGR2GRAY);
    cv::normalize(referenceGray, referenceGray, 0, 255, cv::NORM_MINMAX, CV_8U, validMask);
    cv::normalize(alignedGray, alignedGray, 0, 255, cv::NORM_MINMAX, CV_8U, validMask);

    std::vector<cv::Mat> channels = {alignedGray, alignedGray, referenceGray};
    cv::Mat output;
    cv::merge(channels, output);
    output.setTo(cv::Scalar::all(0), validMask == 0);
    return output;
}

AlignmentDetector parseAlignmentDetector(const std::string& value) {
    const auto key = lowercased(value);
    if (key == "orb") {
        return AlignmentDetector::ORB;
    }
    if (key == "akaze") {
        return AlignmentDetector::AKAZE;
    }
    if (key == "sift") {
        return AlignmentDetector::SIFT;
    }
    throw std::invalid_argument("detector invalido: " + value);
}

AlignmentMotionModel parseAlignmentMotionModel(const std::string& value) {
    const auto key = lowercased(value);
    if (key == "translation" || key == "translacao") {
        return AlignmentMotionModel::Translation;
    }
    if (key == "similarity" || key == "similaridade" || key == "rigid") {
        return AlignmentMotionModel::Similarity;
    }
    if (key == "affine" || key == "afim") {
        return AlignmentMotionModel::Affine;
    }
    if (key == "homography" || key == "homografia") {
        return AlignmentMotionModel::Homography;
    }
    throw std::invalid_argument("modelo geometrico invalido: " + value);
}

std::string alignmentDetectorName(AlignmentDetector detector) {
    switch (detector) {
    case AlignmentDetector::ORB:
        return "orb";
    case AlignmentDetector::AKAZE:
        return "akaze";
    case AlignmentDetector::SIFT:
        return "sift";
    }
    return "orb";
}

std::string alignmentMotionModelName(AlignmentMotionModel motionModel) {
    switch (motionModel) {
    case AlignmentMotionModel::Translation:
        return "translation";
    case AlignmentMotionModel::Similarity:
        return "similarity";
    case AlignmentMotionModel::Affine:
        return "affine";
    case AlignmentMotionModel::Homography:
        return "homography";
    }
    return "homography";
}

std::string alignmentDecisionName(AlignmentDecision decision) {
    switch (decision) {
    case AlignmentDecision::Accept:
        return "accept";
    case AlignmentDecision::Review:
        return "review";
    case AlignmentDecision::Reject:
        return "reject";
    }
    return "reject";
}

} // namespace camerae_vision

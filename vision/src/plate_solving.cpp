#include "camerae_vision/plate_solving.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <limits>
#include <random>
#include <sstream>
#include <stdexcept>

#include <opencv2/imgproc.hpp>

namespace camerae_vision::plate_solving {
namespace {

constexpr double pi = 3.14159265358979323846;

double radians(double degrees) {
    return degrees * pi / 180.0;
}

double degrees(double value) {
    return value * 180.0 / pi;
}

double normalizeRightAscension(double value) {
    value = std::fmod(value, 360.0);
    return value < 0.0 ? value + 360.0 : value;
}

int normalizedOddKernel(int requested, int maximumDimension) {
    int kernel = std::max(3, requested);
    if (kernel % 2 == 0) {
        ++kernel;
    }
    const int maximumOdd = maximumDimension % 2 == 0
        ? maximumDimension - 1
        : maximumDimension;
    return std::max(3, std::min(kernel, maximumOdd));
}

std::string escapeJson(const std::string& input) {
    std::ostringstream output;
    for (const char character : input) {
        switch (character) {
        case '"': output << "\\\""; break;
        case '\\': output << "\\\\"; break;
        case '\n': output << "\\n"; break;
        case '\r': output << "\\r"; break;
        case '\t': output << "\\t"; break;
        default:
            if (static_cast<unsigned char>(character) < 0x20) {
                output << "\\u"
                       << std::hex << std::setw(4) << std::setfill('0')
                       << static_cast<int>(static_cast<unsigned char>(character))
                       << std::dec;
            } else {
                output << character;
            }
        }
    }
    return output.str();
}

cv::Mat grayscale8(const cv::Mat& image) {
    cv::Mat gray;
    if (image.channels() == 1) {
        if (image.depth() == CV_8U) {
            gray = image.clone();
        } else {
            image.convertTo(gray, CV_8U);
        }
    } else if (image.channels() == 3) {
        cv::cvtColor(image, gray, cv::COLOR_BGR2GRAY);
    } else if (image.channels() == 4) {
        cv::cvtColor(image, gray, cv::COLOR_BGRA2GRAY);
    } else {
        throw std::invalid_argument("unsupported image channel count");
    }
    return gray;
}

struct ProjectedCatalogStar {
    CatalogStar star;
    cv::Point2d tangent;
};

struct SimilarityTransform {
    double a = 1.0;
    double b = 0.0;
    double translateX = 0.0;
    double translateY = 0.0;

    cv::Point2d apply(const cv::Point2d& point) const {
        return {
            a * point.x - b * point.y + translateX,
            b * point.x + a * point.y + translateY
        };
    }

    cv::Point2d invert(const cv::Point2d& point) const {
        const double denominator = a * a + b * b;
        if (denominator <= std::numeric_limits<double>::epsilon()) {
            throw std::runtime_error("cannot invert a degenerate plate transform");
        }
        const double x = point.x - translateX;
        const double y = point.y - translateY;
        return {
            (a * x + b * y) / denominator,
            (-b * x + a * y) / denominator
        };
    }

    double scale() const {
        return std::hypot(a, b);
    }
};

struct MatchCandidate {
    int catalogIndex = -1;
    int detectionIndex = -1;
    double residual = 0.0;
};

struct EvaluatedTransform {
    SimilarityTransform transform;
    std::vector<MatchCandidate> matches;
    double rootMeanSquareError = std::numeric_limits<double>::infinity();
};

SimilarityTransform transformFromPairs(
    const cv::Point2d& catalogFirst,
    const cv::Point2d& catalogSecond,
    const cv::Point2d& imageFirst,
    const cv::Point2d& imageSecond
) {
    const cv::Point2d catalogDelta = catalogSecond - catalogFirst;
    const cv::Point2d imageDelta = imageSecond - imageFirst;
    const double denominator =
        catalogDelta.x * catalogDelta.x + catalogDelta.y * catalogDelta.y;
    if (denominator <= std::numeric_limits<double>::epsilon()) {
        return {};
    }

    SimilarityTransform transform;
    transform.a =
        (imageDelta.x * catalogDelta.x + imageDelta.y * catalogDelta.y) / denominator;
    transform.b =
        (imageDelta.y * catalogDelta.x - imageDelta.x * catalogDelta.y) / denominator;
    const cv::Point2d transformedFirst = transform.apply(catalogFirst);
    transform.translateX = imageFirst.x - transformedFirst.x;
    transform.translateY = imageFirst.y - transformedFirst.y;
    return transform;
}

EvaluatedTransform evaluateTransform(
    const SimilarityTransform& transform,
    const std::vector<ProjectedCatalogStar>& catalog,
    const std::vector<DetectedStar>& detections,
    double tolerancePixels,
    int imageWidth,
    int imageHeight
) {
    std::vector<MatchCandidate> possible;
    const double toleranceSquared = tolerancePixels * tolerancePixels;

    for (int catalogIndex = 0; catalogIndex < static_cast<int>(catalog.size()); ++catalogIndex) {
        const cv::Point2d predicted = transform.apply(catalog[catalogIndex].tangent);
        if (predicted.x < -tolerancePixels ||
            predicted.y < -tolerancePixels ||
            predicted.x >= imageWidth + tolerancePixels ||
            predicted.y >= imageHeight + tolerancePixels) {
            continue;
        }

        for (int detectionIndex = 0;
             detectionIndex < static_cast<int>(detections.size());
             ++detectionIndex) {
            const double deltaX = predicted.x - detections[detectionIndex].x;
            const double deltaY = predicted.y - detections[detectionIndex].y;
            const double distanceSquared = deltaX * deltaX + deltaY * deltaY;
            if (distanceSquared <= toleranceSquared) {
                possible.push_back({
                    catalogIndex,
                    detectionIndex,
                    std::sqrt(distanceSquared)
                });
            }
        }
    }

    std::sort(possible.begin(), possible.end(), [](const MatchCandidate& lhs,
                                                    const MatchCandidate& rhs) {
        return lhs.residual < rhs.residual;
    });

    std::vector<bool> usedCatalog(catalog.size(), false);
    std::vector<bool> usedDetections(detections.size(), false);
    EvaluatedTransform evaluated;
    evaluated.transform = transform;
    double squaredError = 0.0;

    for (const MatchCandidate& candidate : possible) {
        if (usedCatalog[candidate.catalogIndex] ||
            usedDetections[candidate.detectionIndex]) {
            continue;
        }
        usedCatalog[candidate.catalogIndex] = true;
        usedDetections[candidate.detectionIndex] = true;
        evaluated.matches.push_back(candidate);
        squaredError += candidate.residual * candidate.residual;
    }

    if (!evaluated.matches.empty()) {
        evaluated.rootMeanSquareError =
            std::sqrt(squaredError / evaluated.matches.size());
    }
    return evaluated;
}

SimilarityTransform refineTransform(
    const EvaluatedTransform& evaluated,
    const std::vector<ProjectedCatalogStar>& catalog,
    const std::vector<DetectedStar>& detections
) {
    if (evaluated.matches.size() < 2) {
        return evaluated.transform;
    }

    cv::Point2d catalogMean;
    cv::Point2d imageMean;
    for (const MatchCandidate& match : evaluated.matches) {
        catalogMean += catalog[match.catalogIndex].tangent;
        imageMean += cv::Point2d(
            detections[match.detectionIndex].x,
            detections[match.detectionIndex].y
        );
    }
    catalogMean *= 1.0 / evaluated.matches.size();
    imageMean *= 1.0 / evaluated.matches.size();

    double numeratorA = 0.0;
    double numeratorB = 0.0;
    double denominator = 0.0;
    for (const MatchCandidate& match : evaluated.matches) {
        const cv::Point2d catalogPoint =
            catalog[match.catalogIndex].tangent - catalogMean;
        const cv::Point2d imagePoint = cv::Point2d(
            detections[match.detectionIndex].x,
            detections[match.detectionIndex].y
        ) - imageMean;
        numeratorA +=
            imagePoint.x * catalogPoint.x + imagePoint.y * catalogPoint.y;
        numeratorB +=
            imagePoint.y * catalogPoint.x - imagePoint.x * catalogPoint.y;
        denominator +=
            catalogPoint.x * catalogPoint.x + catalogPoint.y * catalogPoint.y;
    }

    if (denominator <= std::numeric_limits<double>::epsilon()) {
        return evaluated.transform;
    }

    SimilarityTransform refined;
    refined.a = numeratorA / denominator;
    refined.b = numeratorB / denominator;
    const cv::Point2d transformedMean = refined.apply(catalogMean);
    refined.translateX = imageMean.x - transformedMean.x;
    refined.translateY = imageMean.y - transformedMean.y;
    return refined;
}

bool isBetterEvaluation(
    const EvaluatedTransform& candidate,
    const EvaluatedTransform& current
) {
    if (candidate.matches.size() != current.matches.size()) {
        return candidate.matches.size() > current.matches.size();
    }
    return candidate.rootMeanSquareError < current.rootMeanSquareError;
}

} // namespace

TangentPlanePoint projectGnomonic(
    const SkyCoordinate& coordinate,
    const SkyCoordinate& tangentPoint
) {
    const double rightAscension = radians(coordinate.rightAscensionDegrees);
    const double declination = radians(coordinate.declinationDegrees);
    const double centerRightAscension = radians(tangentPoint.rightAscensionDegrees);
    const double centerDeclination = radians(tangentPoint.declinationDegrees);
    const double deltaRightAscension = rightAscension - centerRightAscension;

    const double denominator =
        std::sin(centerDeclination) * std::sin(declination) +
        std::cos(centerDeclination) * std::cos(declination) *
            std::cos(deltaRightAscension);

    if (denominator <= std::numeric_limits<double>::epsilon()) {
        throw std::invalid_argument("coordinate is outside the gnomonic projection hemisphere");
    }

    return {
        std::cos(declination) * std::sin(deltaRightAscension) / denominator,
        (std::cos(centerDeclination) * std::sin(declination) -
         std::sin(centerDeclination) * std::cos(declination) *
             std::cos(deltaRightAscension)) / denominator
    };
}

SkyCoordinate unprojectGnomonic(
    const TangentPlanePoint& point,
    const SkyCoordinate& tangentPoint
) {
    const double centerRightAscension = radians(tangentPoint.rightAscensionDegrees);
    const double centerDeclination = radians(tangentPoint.declinationDegrees);
    const double radius = std::hypot(point.xRadians, point.yRadians);

    if (radius <= std::numeric_limits<double>::epsilon()) {
        return tangentPoint;
    }

    const double angularDistance = std::atan(radius);
    const double sineDistance = std::sin(angularDistance);
    const double cosineDistance = std::cos(angularDistance);

    const double declination = std::asin(
        cosineDistance * std::sin(centerDeclination) +
        point.yRadians * sineDistance * std::cos(centerDeclination) / radius
    );
    const double rightAscension = centerRightAscension + std::atan2(
        point.xRadians * sineDistance,
        radius * std::cos(centerDeclination) * cosineDistance -
            point.yRadians * std::sin(centerDeclination) * sineDistance
    );

    return {
        normalizeRightAscension(degrees(rightAscension)),
        degrees(declination)
    };
}

StarDetectionResult detectStars(
    const cv::Mat& image,
    const StarDetectorSettings& settings
) {
    if (image.empty()) {
        throw std::invalid_argument("star detection requires a non-empty image");
    }
    if (settings.minimumArea < 1 || settings.maximumArea < settings.minimumArea) {
        throw std::invalid_argument("invalid star area range");
    }

    const auto started = std::chrono::steady_clock::now();
    const int originalWidth = image.cols;
    const int originalHeight = image.rows;
    const int longestSide = std::max(originalWidth, originalHeight);
    const double scale = settings.maxDimension > 0 && longestSide > settings.maxDimension
        ? static_cast<double>(settings.maxDimension) / longestSide
        : 1.0;

    cv::Mat gray = grayscale8(image);
    if (scale < 1.0) {
        cv::resize(gray, gray, cv::Size(), scale, scale, cv::INTER_AREA);
    }

    cv::Mat smoothed;
    cv::GaussianBlur(gray, smoothed, cv::Size(3, 3), 0.75);

    cv::Mat background;
    const int kernel = normalizedOddKernel(
        settings.backgroundKernelSize,
        std::min(smoothed.cols, smoothed.rows)
    );
    cv::medianBlur(smoothed, background, kernel);

    cv::Mat residual;
    cv::subtract(smoothed, background, residual);

    cv::Scalar mean;
    cv::Scalar standardDeviation;
    cv::meanStdDev(residual, mean, standardDeviation);
    const double noise = std::max(1.0, standardDeviation[0]);
    const double thresholdValue = mean[0] + settings.minimumSignalToNoise * noise;

    cv::Mat mask;
    cv::threshold(residual, mask, thresholdValue, 255.0, cv::THRESH_BINARY);

    cv::Mat labels;
    cv::Mat statistics;
    cv::Mat centroids;
    const int labelCount = cv::connectedComponentsWithStats(
        mask,
        labels,
        statistics,
        centroids,
        8,
        CV_32S
    );

    std::vector<DetectedStar> stars;
    stars.reserve(std::max(0, labelCount - 1));

    for (int label = 1; label < labelCount; ++label) {
        const int area = statistics.at<int>(label, cv::CC_STAT_AREA);
        if (area < settings.minimumArea || area > settings.maximumArea) {
            continue;
        }

        const int left = statistics.at<int>(label, cv::CC_STAT_LEFT);
        const int top = statistics.at<int>(label, cv::CC_STAT_TOP);
        const int width = statistics.at<int>(label, cv::CC_STAT_WIDTH);
        const int height = statistics.at<int>(label, cv::CC_STAT_HEIGHT);
        const double aspectRatio = static_cast<double>(std::max(width, height)) /
            std::max(1, std::min(width, height));
        if (aspectRatio > 3.5) {
            continue;
        }

        double weightedX = 0.0;
        double weightedY = 0.0;
        double totalFlux = 0.0;
        double peak = 0.0;

        for (int y = top; y < top + height; ++y) {
            for (int x = left; x < left + width; ++x) {
                if (labels.at<int>(y, x) != label) {
                    continue;
                }
                const double value = residual.at<std::uint8_t>(y, x);
                weightedX += x * value;
                weightedY += y * value;
                totalFlux += value;
                peak = std::max(peak, value);
            }
        }

        if (totalFlux <= 0.0) {
            continue;
        }

        stars.push_back({
            weightedX / totalFlux / scale,
            weightedY / totalFlux / scale,
            totalFlux / scale,
            peak / noise,
            std::sqrt(area / pi) / scale
        });
    }

    std::sort(stars.begin(), stars.end(), [](const DetectedStar& lhs, const DetectedStar& rhs) {
        return lhs.flux > rhs.flux;
    });
    if (settings.maximumStars > 0 &&
        stars.size() > static_cast<std::size_t>(settings.maximumStars)) {
        stars.resize(static_cast<std::size_t>(settings.maximumStars));
    }

    const auto finished = std::chrono::steady_clock::now();
    const double elapsed = std::chrono::duration<double, std::milli>(finished - started).count();
    return {originalWidth, originalHeight, elapsed, noise, std::move(stars)};
}

SyntheticStarField makeSyntheticStarField(const SyntheticStarFieldSettings& settings) {
    if (settings.width <= 0 || settings.height <= 0 || settings.starCount < 0) {
        throw std::invalid_argument("invalid synthetic star field settings");
    }

    cv::Mat floating(settings.height, settings.width, CV_32F, cv::Scalar::all(12.0));
    std::mt19937_64 random(settings.seed);
    std::uniform_real_distribution<double> xDistribution(12.0, settings.width - 12.0);
    std::uniform_real_distribution<double> yDistribution(12.0, settings.height - 12.0);
    std::uniform_real_distribution<double> brightnessDistribution(110.0, 235.0);
    std::uniform_real_distribution<double> radiusDistribution(0.8, 1.8);
    std::normal_distribution<double> noiseDistribution(0.0, settings.noiseSigma);

    std::vector<DetectedStar> stars;
    stars.reserve(static_cast<std::size_t>(settings.starCount));

    for (int index = 0; index < settings.starCount; ++index) {
        const double x = xDistribution(random);
        const double y = yDistribution(random);
        const double brightness = brightnessDistribution(random);
        const double radius = radiusDistribution(random);
        cv::circle(
            floating,
            cv::Point(static_cast<int>(std::round(x)), static_cast<int>(std::round(y))),
            std::max(1, static_cast<int>(std::round(radius))),
            cv::Scalar::all(brightness),
            cv::FILLED,
            cv::LINE_AA
        );
        stars.push_back({x, y, brightness, 0.0, radius});
    }

    cv::GaussianBlur(floating, floating, cv::Size(3, 3), 0.65);
    for (int y = 0; y < floating.rows; ++y) {
        float* row = floating.ptr<float>(y);
        for (int x = 0; x < floating.cols; ++x) {
            row[x] = static_cast<float>(std::clamp(
                row[x] + noiseDistribution(random),
                0.0,
                255.0
            ));
        }
    }

    cv::Mat gray;
    floating.convertTo(gray, CV_8U);
    cv::Mat image;
    cv::cvtColor(gray, image, cv::COLOR_GRAY2BGR);
    return {image, std::move(stars)};
}

PlateSolution solveConstrained(const ConstrainedPlateSolveRequest& request) {
    PlateSolution notSolved;
    notSolved.status = PlateSolvingStatus::NotSolved;
    notSolved.message = "No catalog geometry met the constrained solution policy.";

    if (request.imageWidth <= 0 ||
        request.imageHeight <= 0 ||
        request.detectedStars.size() < 2 ||
        request.catalog.size() < 2 ||
        request.approximateHorizontalFieldOfViewDegrees <= 0.0 ||
        request.approximateHorizontalFieldOfViewDegrees >= 179.0 ||
        request.minimumMatches < 2 ||
        request.matchTolerancePixels <= 0.0) {
        notSolved.status = PlateSolvingStatus::InvalidInput;
        notSolved.message = "Invalid constrained plate-solving request.";
        return notSolved;
    }

    std::vector<DetectedStar> detections = request.detectedStars;
    std::sort(detections.begin(), detections.end(), [](const DetectedStar& lhs,
                                                       const DetectedStar& rhs) {
        return lhs.flux > rhs.flux;
    });
    if (request.maximumDetectedStars > 0 &&
        detections.size() > static_cast<std::size_t>(request.maximumDetectedStars)) {
        detections.resize(static_cast<std::size_t>(request.maximumDetectedStars));
    }

    std::vector<CatalogStar> orderedCatalog = request.catalog;
    std::sort(orderedCatalog.begin(), orderedCatalog.end(), [](const CatalogStar& lhs,
                                                               const CatalogStar& rhs) {
        return lhs.magnitude < rhs.magnitude;
    });

    const double approximateHalfFieldRadians =
        radians(request.approximateHorizontalFieldOfViewDegrees * 0.75);
    const double tangentLimit = std::tan(approximateHalfFieldRadians);
    const double verticalTangentLimit =
        tangentLimit * request.imageHeight / request.imageWidth;

    std::vector<ProjectedCatalogStar> catalog;
    catalog.reserve(orderedCatalog.size());
    for (const CatalogStar& star : orderedCatalog) {
        try {
            const TangentPlanePoint point =
                projectGnomonic(star.coordinate, request.approximateCenter);
            if (std::abs(point.xRadians) > tangentLimit ||
                std::abs(point.yRadians) > verticalTangentLimit) {
                continue;
            }
            catalog.push_back({
                star,
                cv::Point2d(point.xRadians, point.yRadians)
            });
        } catch (const std::invalid_argument&) {
            continue;
        }
        if (request.maximumCatalogStars > 0 &&
            catalog.size() >= static_cast<std::size_t>(request.maximumCatalogStars)) {
            break;
        }
    }

    if (catalog.size() < static_cast<std::size_t>(request.minimumMatches) ||
        detections.size() < static_cast<std::size_t>(request.minimumMatches)) {
        notSolved.message = "Not enough visible stars for the requested match policy.";
        return notSolved;
    }

    const double expectedPixelsPerRadian =
        request.imageWidth /
        (2.0 * std::tan(radians(request.approximateHorizontalFieldOfViewDegrees) / 2.0));
    const double minimumScale = expectedPixelsPerRadian * 0.65;
    const double maximumScale = expectedPixelsPerRadian * 1.55;
    EvaluatedTransform best;

    for (int catalogFirst = 0;
         catalogFirst < static_cast<int>(catalog.size()) - 1;
         ++catalogFirst) {
        for (int catalogSecond = catalogFirst + 1;
             catalogSecond < static_cast<int>(catalog.size());
             ++catalogSecond) {
            const double catalogDistance = cv::norm(
                catalog[catalogSecond].tangent - catalog[catalogFirst].tangent
            );
            if (catalogDistance < 0.001) {
                continue;
            }

            for (int detectionFirst = 0;
                 detectionFirst < static_cast<int>(detections.size()) - 1;
                 ++detectionFirst) {
                for (int detectionSecond = detectionFirst + 1;
                     detectionSecond < static_cast<int>(detections.size());
                     ++detectionSecond) {
                    const cv::Point2d firstImage(
                        detections[detectionFirst].x,
                        detections[detectionFirst].y
                    );
                    const cv::Point2d secondImage(
                        detections[detectionSecond].x,
                        detections[detectionSecond].y
                    );
                    const double imageDistance = cv::norm(secondImage - firstImage);
                    const double scale = imageDistance / catalogDistance;
                    if (scale < minimumScale || scale > maximumScale) {
                        continue;
                    }

                    for (int direction = 0; direction < 2; ++direction) {
                        const cv::Point2d& mappedFirst =
                            direction == 0 ? firstImage : secondImage;
                        const cv::Point2d& mappedSecond =
                            direction == 0 ? secondImage : firstImage;
                        const SimilarityTransform hypothesis = transformFromPairs(
                            catalog[catalogFirst].tangent,
                            catalog[catalogSecond].tangent,
                            mappedFirst,
                            mappedSecond
                        );
                        EvaluatedTransform evaluated = evaluateTransform(
                            hypothesis,
                            catalog,
                            detections,
                            request.matchTolerancePixels,
                            request.imageWidth,
                            request.imageHeight
                        );
                        if (isBetterEvaluation(evaluated, best)) {
                            best = std::move(evaluated);
                        }
                    }
                }
            }
        }
    }

    if (best.matches.size() < static_cast<std::size_t>(request.minimumMatches)) {
        return notSolved;
    }

    for (int iteration = 0; iteration < 2; ++iteration) {
        const SimilarityTransform refined = refineTransform(best, catalog, detections);
        best = evaluateTransform(
            refined,
            catalog,
            detections,
            request.matchTolerancePixels,
            request.imageWidth,
            request.imageHeight
        );
    }

    if (best.matches.size() < static_cast<std::size_t>(request.minimumMatches) ||
        best.rootMeanSquareError > request.matchTolerancePixels * 0.65) {
        return notSolved;
    }

    const double scale = best.transform.scale();
    if (scale <= std::numeric_limits<double>::epsilon()) {
        return notSolved;
    }

    const cv::Point2d opticalCenterTangent = best.transform.invert({
        request.imageWidth / 2.0,
        request.imageHeight / 2.0
    });

    PlateSolution solution;
    solution.status = PlateSolvingStatus::Solved;
    solution.center = unprojectGnomonic(
        {opticalCenterTangent.x, opticalCenterTangent.y},
        request.approximateCenter
    );
    solution.rollDegrees = degrees(std::atan2(best.transform.b, best.transform.a));
    solution.horizontalFieldOfViewDegrees =
        degrees(2.0 * std::atan(request.imageWidth / (2.0 * scale)));
    solution.verticalFieldOfViewDegrees =
        degrees(2.0 * std::atan(request.imageHeight / (2.0 * scale)));
    solution.plateScaleArcsecondsPerPixel = degrees(1.0 / scale) * 3600.0;
    solution.rootMeanSquareErrorPixels = best.rootMeanSquareError;
    solution.matchedStars = static_cast<int>(best.matches.size());

    const double matchCoverage = std::min(
        1.0,
        static_cast<double>(solution.matchedStars) /
            std::max(request.minimumMatches, std::min(
                static_cast<int>(catalog.size()),
                static_cast<int>(detections.size())
            ))
    );
    const double residualScore = std::clamp(
        1.0 - solution.rootMeanSquareErrorPixels / request.matchTolerancePixels,
        0.0,
        1.0
    );
    solution.confidence = std::clamp(
        0.72 * matchCoverage + 0.28 * residualScore,
        0.0,
        1.0
    );
    solution.message = "Constrained catalog geometry solved and validated.";

    for (const MatchCandidate& match : best.matches) {
        const cv::Point2d predicted =
            best.transform.apply(catalog[match.catalogIndex].tangent);
        const DetectedStar& detection = detections[match.detectionIndex];
        solution.matches.push_back({
            catalog[match.catalogIndex].star.identifier,
            catalog[match.catalogIndex].star.coordinate,
            detection.x,
            detection.y,
            cv::norm(predicted - cv::Point2d(detection.x, detection.y))
        });
    }
    return solution;
}

std::string plateSolvingStatusName(PlateSolvingStatus status) {
    switch (status) {
    case PlateSolvingStatus::DetectionCompleted: return "detectionCompleted";
    case PlateSolvingStatus::Solved: return "solved";
    case PlateSolvingStatus::NotSolved: return "notSolved";
    case PlateSolvingStatus::InvalidInput: return "invalidInput";
    }
    return "invalidInput";
}

std::string serializeLabReport(const PlateSolvingLabReport& report) {
    std::ostringstream json;
    json << std::fixed << std::setprecision(6)
         << "{\n"
         << "  \"schemaVersion\": " << report.schemaVersion << ",\n"
         << "  \"status\": \"" << plateSolvingStatusName(report.status) << "\",\n"
         << "  \"imagePath\": \"" << escapeJson(report.imagePath) << "\",\n"
         << "  \"imageWidth\": " << report.imageWidth << ",\n"
         << "  \"imageHeight\": " << report.imageHeight << ",\n"
         << "  \"detectedStarCount\": " << report.detectedStarCount << ",\n"
         << "  \"detectionMilliseconds\": " << report.detectionMilliseconds << ",\n"
         << "  \"backgroundNoise\": " << report.backgroundNoise << ",\n"
         << "  \"message\": \"" << escapeJson(report.message) << "\",\n"
         << "  \"brightestStars\": [";

    for (std::size_t index = 0; index < report.brightestStars.size(); ++index) {
        const DetectedStar& star = report.brightestStars[index];
        if (index == 0) {
            json << "\n";
        }
        json << "    {\"x\": " << star.x
             << ", \"y\": " << star.y
             << ", \"flux\": " << star.flux
             << ", \"signalToNoise\": " << star.signalToNoise
             << ", \"radius\": " << star.radius << "}";
        if (index + 1 < report.brightestStars.size()) {
            json << ",";
        }
        json << "\n";
    }
    json << "  ]\n}\n";
    if (report.status == PlateSolvingStatus::Solved) {
        const PlateSolution& solution = report.solution;
        std::ostringstream solved;
        const std::string current = json.str();
        const std::size_t closing = current.rfind("\n}\n");
        solved << current.substr(0, closing)
               << ",\n  \"solution\": {\n"
               << "    \"centerRightAscensionDegrees\": "
               << solution.center.rightAscensionDegrees << ",\n"
               << "    \"centerDeclinationDegrees\": "
               << solution.center.declinationDegrees << ",\n"
               << "    \"rollDegrees\": " << solution.rollDegrees << ",\n"
               << "    \"horizontalFieldOfViewDegrees\": "
               << solution.horizontalFieldOfViewDegrees << ",\n"
               << "    \"verticalFieldOfViewDegrees\": "
               << solution.verticalFieldOfViewDegrees << ",\n"
               << "    \"plateScaleArcsecondsPerPixel\": "
               << solution.plateScaleArcsecondsPerPixel << ",\n"
               << "    \"rootMeanSquareErrorPixels\": "
               << solution.rootMeanSquareErrorPixels << ",\n"
               << "    \"matchedStars\": " << solution.matchedStars << ",\n"
               << "    \"confidence\": " << solution.confidence << ",\n"
               << "    \"matches\": [";
        for (std::size_t index = 0; index < solution.matches.size(); ++index) {
            const PlateStarMatch& match = solution.matches[index];
            solved << (index == 0 ? "\n" : "")
                   << "      {\"catalogIdentifier\": \""
                   << escapeJson(match.catalogIdentifier)
                   << "\", \"rightAscensionDegrees\": "
                   << match.coordinate.rightAscensionDegrees
                   << ", \"declinationDegrees\": "
                   << match.coordinate.declinationDegrees
                   << ", \"imageX\": " << match.imageX
                   << ", \"imageY\": " << match.imageY
                   << ", \"residualPixels\": " << match.residualPixels << "}";
            if (index + 1 < solution.matches.size()) {
                solved << ",";
            }
            solved << "\n";
        }
        solved << "    ]\n  }\n}\n";
        return solved.str();
    }
    return json.str();
}

cv::Mat renderStarDetectionOverlay(
    const cv::Mat& image,
    const StarDetectionResult& detection
) {
    if (image.empty()) {
        throw std::invalid_argument("overlay requires a non-empty image");
    }

    cv::Mat overlay;
    if (image.channels() == 1) {
        cv::cvtColor(image, overlay, cv::COLOR_GRAY2BGR);
    } else if (image.channels() == 4) {
        cv::cvtColor(image, overlay, cv::COLOR_BGRA2BGR);
    } else {
        overlay = image.clone();
    }

    for (std::size_t index = 0; index < detection.stars.size(); ++index) {
        const DetectedStar& star = detection.stars[index];
        const cv::Point center(
            static_cast<int>(std::round(star.x)),
            static_cast<int>(std::round(star.y))
        );
        const int radius = std::max(5, static_cast<int>(std::ceil(star.radius + 4.0)));
        const cv::Scalar color = index < 25
            ? cv::Scalar(0, 220, 255)
            : cv::Scalar(255, 180, 0);
        cv::circle(overlay, center, radius, color, 1, cv::LINE_AA);
    }

    const std::string label =
        "Camerae plate-solving lab | stars: " + std::to_string(detection.stars.size());
    cv::putText(
        overlay,
        label,
        cv::Point(24, 42),
        cv::FONT_HERSHEY_SIMPLEX,
        0.9,
        cv::Scalar(0, 0, 0),
        4,
        cv::LINE_AA
    );
    cv::putText(
        overlay,
        label,
        cv::Point(24, 42),
        cv::FONT_HERSHEY_SIMPLEX,
        0.9,
        cv::Scalar(255, 255, 255),
        1,
        cv::LINE_AA
    );
    return overlay;
}

cv::Mat renderPlateSolutionOverlay(
    const cv::Mat& image,
    const StarDetectionResult& detection,
    const PlateSolution& solution
) {
    cv::Mat overlay = renderStarDetectionOverlay(image, detection);
    if (solution.status != PlateSolvingStatus::Solved) {
        return overlay;
    }

    for (const PlateStarMatch& match : solution.matches) {
        const cv::Point center(
            static_cast<int>(std::round(match.imageX)),
            static_cast<int>(std::round(match.imageY))
        );
        cv::circle(overlay, center, 10, cv::Scalar(80, 255, 80), 2, cv::LINE_AA);
        cv::putText(
            overlay,
            match.catalogIdentifier,
            center + cv::Point(12, -8),
            cv::FONT_HERSHEY_SIMPLEX,
            0.45,
            cv::Scalar(80, 255, 80),
            1,
            cv::LINE_AA
        );
    }

    std::ostringstream label;
    label << std::fixed << std::setprecision(3)
          << "SOLVED | RA " << solution.center.rightAscensionDegrees
          << " Dec " << solution.center.declinationDegrees
          << " Roll " << solution.rollDegrees
          << " Matches " << solution.matchedStars;
    cv::putText(
        overlay,
        label.str(),
        cv::Point(24, 78),
        cv::FONT_HERSHEY_SIMPLEX,
        0.72,
        cv::Scalar(0, 0, 0),
        4,
        cv::LINE_AA
    );
    cv::putText(
        overlay,
        label.str(),
        cv::Point(24, 78),
        cv::FONT_HERSHEY_SIMPLEX,
        0.72,
        cv::Scalar(80, 255, 80),
        1,
        cv::LINE_AA
    );
    return overlay;
}

} // namespace camerae_vision::plate_solving

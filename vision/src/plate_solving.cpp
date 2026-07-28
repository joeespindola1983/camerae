#include "camerae_vision/plate_solving.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstring>
#include <iomanip>
#include <limits>
#include <numeric>
#include <random>
#include <set>
#include <sstream>
#include <stdexcept>
#include <type_traits>

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

template <typename Value>
void appendBinary(std::vector<std::uint8_t>& output, Value value) {
    static_assert(std::is_trivially_copyable_v<Value>);
    const auto* bytes = reinterpret_cast<const std::uint8_t*>(&value);
    output.insert(output.end(), bytes, bytes + sizeof(Value));
}

template <typename Value>
Value readBinary(const std::vector<std::uint8_t>& input, std::size_t& offset) {
    static_assert(std::is_trivially_copyable_v<Value>);
    if (offset + sizeof(Value) > input.size()) {
        throw std::invalid_argument("truncated compact star catalog");
    }
    Value value;
    std::memcpy(&value, input.data() + offset, sizeof(Value));
    offset += sizeof(Value);
    return value;
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
    bool reflected = false;

    cv::Point2d apply(const cv::Point2d& point) const {
        if (reflected) {
            return {
                a * point.x + b * point.y + translateX,
                b * point.x - a * point.y + translateY
            };
        }
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
        if (reflected) {
            return {
                (a * x + b * y) / denominator,
                (b * x - a * y) / denominator
            };
        }
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

struct UnitVector3 {
    double x = 0.0;
    double y = 0.0;
    double z = 0.0;
};

struct QuadFingerprint {
    std::array<double, 5> ratios{};
    double largestEdge = 0.0;
};

struct CatalogQuad {
    std::array<int, 4> indices{};
    QuadFingerprint fingerprint;
    SkyCoordinate center;
};

struct CenterCandidate {
    SkyCoordinate center;
    double fingerprintError = 0.0;
};

UnitVector3 unitVector(const SkyCoordinate& coordinate) {
    const double rightAscension = radians(coordinate.rightAscensionDegrees);
    const double declination = radians(coordinate.declinationDegrees);
    return {
        std::cos(declination) * std::cos(rightAscension),
        std::cos(declination) * std::sin(rightAscension),
        std::sin(declination)
    };
}

SkyCoordinate coordinate(const UnitVector3& input) {
    const double length = std::sqrt(
        input.x * input.x + input.y * input.y + input.z * input.z
    );
    if (length <= std::numeric_limits<double>::epsilon()) {
        return {};
    }
    return {
        normalizeRightAscension(degrees(std::atan2(input.y, input.x))),
        degrees(std::asin(std::clamp(input.z / length, -1.0, 1.0)))
    };
}

double angularDistance(const UnitVector3& lhs, const UnitVector3& rhs) {
    const double chord = std::sqrt(
        (lhs.x - rhs.x) * (lhs.x - rhs.x) +
        (lhs.y - rhs.y) * (lhs.y - rhs.y) +
        (lhs.z - rhs.z) * (lhs.z - rhs.z)
    );
    return 2.0 * std::asin(std::clamp(chord * 0.5, 0.0, 1.0));
}

QuadFingerprint fingerprintFromDistances(std::array<double, 6> distances) {
    std::sort(distances.begin(), distances.end());
    QuadFingerprint fingerprint;
    fingerprint.largestEdge = distances.back();
    if (fingerprint.largestEdge <= std::numeric_limits<double>::epsilon()) {
        return fingerprint;
    }
    for (std::size_t index = 0; index < fingerprint.ratios.size(); ++index) {
        fingerprint.ratios[index] = distances[index] / fingerprint.largestEdge;
    }
    return fingerprint;
}

QuadFingerprint imageQuadFingerprint(
    const std::array<int, 4>& indices,
    const std::vector<DetectedStar>& detections
) {
    std::array<double, 6> distances{};
    std::size_t distanceIndex = 0;
    for (int first = 0; first < 3; ++first) {
        for (int second = first + 1; second < 4; ++second) {
            distances[distanceIndex++] = std::hypot(
                detections[indices[first]].x - detections[indices[second]].x,
                detections[indices[first]].y - detections[indices[second]].y
            );
        }
    }
    return fingerprintFromDistances(distances);
}

QuadFingerprint catalogQuadFingerprint(
    const std::array<int, 4>& indices,
    const std::vector<UnitVector3>& vectors
) {
    std::array<double, 6> distances{};
    std::size_t distanceIndex = 0;
    for (int first = 0; first < 3; ++first) {
        for (int second = first + 1; second < 4; ++second) {
            distances[distanceIndex++] =
                angularDistance(vectors[indices[first]], vectors[indices[second]]);
        }
    }
    return fingerprintFromDistances(distances);
}

double fingerprintError(const QuadFingerprint& lhs, const QuadFingerprint& rhs) {
    double maximum = 0.0;
    for (std::size_t index = 0; index < lhs.ratios.size(); ++index) {
        maximum = std::max(maximum, std::abs(lhs.ratios[index] - rhs.ratios[index]));
    }
    return maximum;
}

SkyCoordinate quadCenter(
    const std::array<int, 4>& indices,
    const std::vector<UnitVector3>& vectors
) {
    UnitVector3 sum;
    for (const int index : indices) {
        sum.x += vectors[index].x;
        sum.y += vectors[index].y;
        sum.z += vectors[index].z;
    }
    return coordinate(sum);
}

std::vector<CatalogQuad> buildCatalogQuads(
    const std::vector<CatalogStar>& catalog,
    int maximumStars,
    int neighborCount,
    double maximumEdgeRadians
) {
    const int starCount = std::min(maximumStars, static_cast<int>(catalog.size()));
    std::vector<UnitVector3> vectors;
    vectors.reserve(starCount);
    for (int index = 0; index < starCount; ++index) {
        vectors.push_back(unitVector(catalog[index].coordinate));
    }

    std::set<std::array<int, 4>> uniquePatterns;
    for (int anchor = 0; anchor < starCount; ++anchor) {
        std::vector<std::pair<double, int>> nearest;
        nearest.reserve(starCount - 1);
        for (int candidate = 0; candidate < starCount; ++candidate) {
            if (candidate == anchor) {
                continue;
            }
            const double distance = angularDistance(vectors[anchor], vectors[candidate]);
            if (distance <= maximumEdgeRadians) {
                nearest.emplace_back(distance, candidate);
            }
        }
        std::sort(nearest.begin(), nearest.end());
        if (nearest.size() > static_cast<std::size_t>(neighborCount)) {
            nearest.resize(static_cast<std::size_t>(neighborCount));
        }

        for (int first = 0; first < static_cast<int>(nearest.size()) - 2; ++first) {
            for (int second = first + 1;
                 second < static_cast<int>(nearest.size()) - 1;
                 ++second) {
                for (int third = second + 1;
                     third < static_cast<int>(nearest.size());
                     ++third) {
                    std::array<int, 4> indices{
                        anchor,
                        nearest[first].second,
                        nearest[second].second,
                        nearest[third].second
                    };
                    std::sort(indices.begin(), indices.end());
                    uniquePatterns.insert(indices);
                }
            }
        }
    }

    std::vector<CatalogQuad> patterns;
    patterns.reserve(uniquePatterns.size());
    for (const std::array<int, 4>& indices : uniquePatterns) {
        const QuadFingerprint fingerprint = catalogQuadFingerprint(indices, vectors);
        if (fingerprint.largestEdge <= 0.0 ||
            fingerprint.largestEdge > maximumEdgeRadians) {
            continue;
        }
        patterns.push_back({
            indices,
            fingerprint,
            quadCenter(indices, vectors)
        });
    }
    return patterns;
}

double skySeparationDegrees(const SkyCoordinate& lhs, const SkyCoordinate& rhs) {
    return degrees(angularDistance(unitVector(lhs), unitVector(rhs)));
}

SimilarityTransform transformFromPairs(
    const cv::Point2d& catalogFirst,
    const cv::Point2d& catalogSecond,
    const cv::Point2d& imageFirst,
    const cv::Point2d& imageSecond,
    bool reflected
) {
    const cv::Point2d catalogDelta = catalogSecond - catalogFirst;
    const cv::Point2d imageDelta = imageSecond - imageFirst;
    const double denominator =
        catalogDelta.x * catalogDelta.x + catalogDelta.y * catalogDelta.y;
    if (denominator <= std::numeric_limits<double>::epsilon()) {
        return {};
    }

    SimilarityTransform transform;
    transform.reflected = reflected;
    if (reflected) {
        transform.a =
            (imageDelta.x * catalogDelta.x -
             imageDelta.y * catalogDelta.y) / denominator;
        transform.b =
            (imageDelta.x * catalogDelta.y +
             imageDelta.y * catalogDelta.x) / denominator;
    } else {
        transform.a =
            (imageDelta.x * catalogDelta.x +
             imageDelta.y * catalogDelta.y) / denominator;
        transform.b =
            (imageDelta.y * catalogDelta.x -
             imageDelta.x * catalogDelta.y) / denominator;
    }
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
    refined.reflected = evaluated.transform.reflected;
    if (refined.reflected) {
        numeratorA = 0.0;
        numeratorB = 0.0;
        for (const MatchCandidate& match : evaluated.matches) {
            const cv::Point2d catalogPoint =
                catalog[match.catalogIndex].tangent - catalogMean;
            const cv::Point2d imagePoint = cv::Point2d(
                detections[match.detectionIndex].x,
                detections[match.detectionIndex].y
            ) - imageMean;
            numeratorA +=
                imagePoint.x * catalogPoint.x - imagePoint.y * catalogPoint.y;
            numeratorB +=
                imagePoint.x * catalogPoint.y + imagePoint.y * catalogPoint.x;
        }
    }
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

std::vector<std::uint8_t> serializeCompactCatalog(
    const std::vector<CatalogStar>& catalog
) {
    constexpr std::array<std::uint8_t, 8> magic{
        'C', 'A', 'M', 'C', 'A', 'T', '0', '1'
    };
    if (catalog.size() > std::numeric_limits<std::uint32_t>::max()) {
        throw std::invalid_argument("compact star catalog is too large");
    }

    std::vector<std::uint8_t> output(magic.begin(), magic.end());
    appendBinary(output, static_cast<std::uint32_t>(catalog.size()));
    for (const CatalogStar& star : catalog) {
        if (star.identifier.size() > std::numeric_limits<std::uint16_t>::max()) {
            throw std::invalid_argument("catalog identifier is too long");
        }
        appendBinary(output, static_cast<float>(star.coordinate.rightAscensionDegrees));
        appendBinary(output, static_cast<float>(star.coordinate.declinationDegrees));
        appendBinary(output, static_cast<float>(star.magnitude));
        appendBinary(output, static_cast<std::uint16_t>(star.identifier.size()));
        output.insert(output.end(), star.identifier.begin(), star.identifier.end());
    }
    return output;
}

std::vector<CatalogStar> deserializeCompactCatalog(
    const std::vector<std::uint8_t>& bytes
) {
    constexpr std::array<std::uint8_t, 8> magic{
        'C', 'A', 'M', 'C', 'A', 'T', '0', '1'
    };
    if (bytes.size() < magic.size() ||
        !std::equal(magic.begin(), magic.end(), bytes.begin())) {
        throw std::invalid_argument("invalid compact star catalog signature");
    }

    std::size_t offset = magic.size();
    const std::uint32_t count = readBinary<std::uint32_t>(bytes, offset);
    if (count > 1'000'000) {
        throw std::invalid_argument("compact star catalog count is unsafe");
    }

    std::vector<CatalogStar> catalog;
    catalog.reserve(count);
    for (std::uint32_t index = 0; index < count; ++index) {
        const float rightAscension = readBinary<float>(bytes, offset);
        const float declination = readBinary<float>(bytes, offset);
        const float magnitude = readBinary<float>(bytes, offset);
        const std::uint16_t identifierLength =
            readBinary<std::uint16_t>(bytes, offset);
        if (offset + identifierLength > bytes.size()) {
            throw std::invalid_argument("truncated compact star identifier");
        }
        const std::string identifier(
            reinterpret_cast<const char*>(bytes.data() + offset),
            identifierLength
        );
        offset += identifierLength;
        catalog.push_back({
            identifier,
            {rightAscension, declination},
            magnitude
        });
    }
    if (offset != bytes.size()) {
        throw std::invalid_argument("compact star catalog has trailing data");
    }
    return catalog;
}

ActiveImageRegion detectActiveImageRegion(
    const cv::Mat& image,
    int nearBlackThreshold,
    double minimumActiveFraction
) {
    if (image.empty()) {
        throw std::invalid_argument("active image region requires a non-empty image");
    }
    if (nearBlackThreshold < 0 || nearBlackThreshold > 255 ||
        minimumActiveFraction <= 0.0 || minimumActiveFraction > 1.0) {
        throw std::invalid_argument("invalid active image region settings");
    }

    const cv::Mat gray = grayscale8(image);
    cv::Mat active;
    cv::threshold(gray, active, nearBlackThreshold, 1.0, cv::THRESH_BINARY);

    cv::Mat columnCounts;
    cv::Mat rowCounts;
    cv::reduce(active, columnCounts, 0, cv::REDUCE_SUM, CV_32S);
    cv::reduce(active, rowCounts, 1, cv::REDUCE_SUM, CV_32S);

    const int minimumColumnPixels = std::max(
        1,
        static_cast<int>(std::ceil(gray.rows * minimumActiveFraction))
    );
    const int minimumRowPixels = std::max(
        1,
        static_cast<int>(std::ceil(gray.cols * minimumActiveFraction))
    );

    int left = 0;
    while (left < gray.cols &&
           columnCounts.at<int>(0, left) < minimumColumnPixels) {
        ++left;
    }
    int right = gray.cols - 1;
    while (right >= left &&
           columnCounts.at<int>(0, right) < minimumColumnPixels) {
        --right;
    }
    int top = 0;
    while (top < gray.rows &&
           rowCounts.at<int>(top, 0) < minimumRowPixels) {
        ++top;
    }
    int bottom = gray.rows - 1;
    while (bottom >= top &&
           rowCounts.at<int>(bottom, 0) < minimumRowPixels) {
        --bottom;
    }

    if (left > right || top > bottom) {
        return {0, 0, gray.cols, gray.rows};
    }
    return {left, top, right - left + 1, bottom - top + 1};
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

                    for (int parity = 0; parity < 2; ++parity) {
                        for (int direction = 0; direction < 2; ++direction) {
                            const cv::Point2d& mappedFirst =
                                direction == 0 ? firstImage : secondImage;
                            const cv::Point2d& mappedSecond =
                                direction == 0 ? secondImage : firstImage;
                            const SimilarityTransform hypothesis = transformFromPairs(
                                catalog[catalogFirst].tangent,
                                catalog[catalogSecond].tangent,
                                mappedFirst,
                                mappedSecond,
                                parity == 1
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
    solution.parityInverted = best.transform.reflected;
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

PlateSolution solveLostInSpace(const LostInSpacePlateSolveRequest& request) {
    PlateSolution notSolved;
    notSolved.status = PlateSolvingStatus::NotSolved;
    notSolved.message = "No quad fingerprint produced a validated celestial solution.";

    if (request.imageWidth <= 0 ||
        request.imageHeight <= 0 ||
        request.approximateHorizontalFieldOfViewDegrees <= 0.0 ||
        request.approximateHorizontalFieldOfViewDegrees >= 179.0 ||
        request.detectedStars.size() <
            static_cast<std::size_t>(std::max(4, request.minimumMatches)) ||
        request.catalog.size() <
            static_cast<std::size_t>(std::max(4, request.minimumMatches)) ||
        request.patternCheckingStars < 4 ||
        request.patternNeighbors < 3 ||
        request.maximumCandidateCenters < 1) {
        notSolved.status = PlateSolvingStatus::InvalidInput;
        notSolved.message = "Invalid lost-in-space plate-solving request.";
        return notSolved;
    }

    std::vector<DetectedStar> detections = request.detectedStars;
    std::sort(detections.begin(), detections.end(), [](const DetectedStar& lhs,
                                                       const DetectedStar& rhs) {
        return lhs.flux > rhs.flux;
    });
    if (detections.size() > static_cast<std::size_t>(request.patternCheckingStars)) {
        detections.resize(static_cast<std::size_t>(request.patternCheckingStars));
    }

    std::vector<CatalogStar> catalog = request.catalog;
    std::sort(catalog.begin(), catalog.end(), [](const CatalogStar& lhs,
                                                 const CatalogStar& rhs) {
        return lhs.magnitude < rhs.magnitude;
    });

    const double maximumPatternEdge = radians(
        request.approximateHorizontalFieldOfViewDegrees *
        (1.0 + request.fieldOfViewToleranceFraction)
    );
    const std::vector<CatalogQuad> catalogQuads = buildCatalogQuads(
        catalog,
        request.catalogPatternStars,
        request.patternNeighbors,
        maximumPatternEdge
    );
    if (catalogQuads.empty()) {
        notSolved.message = "Catalog did not produce quad patterns for the requested FOV.";
        return notSolved;
    }

    std::vector<CenterCandidate> candidates;
    const double tangentHalfField = std::tan(
        radians(request.approximateHorizontalFieldOfViewDegrees) / 2.0
    );

    for (int first = 0; first < static_cast<int>(detections.size()) - 3; ++first) {
        for (int second = first + 1;
             second < static_cast<int>(detections.size()) - 2;
             ++second) {
            for (int third = second + 1;
                 third < static_cast<int>(detections.size()) - 1;
                 ++third) {
                for (int fourth = third + 1;
                     fourth < static_cast<int>(detections.size());
                     ++fourth) {
                    const QuadFingerprint imageFingerprint = imageQuadFingerprint(
                        {first, second, third, fourth},
                        detections
                    );
                    if (imageFingerprint.largestEdge < request.imageWidth * 0.08) {
                        continue;
                    }
                    const double normalizedImageEdge =
                        imageFingerprint.largestEdge / request.imageWidth;
                    const double expectedAngularEdge =
                        2.0 * std::atan(normalizedImageEdge * tangentHalfField);

                    for (const CatalogQuad& catalogQuad : catalogQuads) {
                        const double edgeRatio =
                            catalogQuad.fingerprint.largestEdge /
                            std::max(expectedAngularEdge, 1e-8);
                        if (edgeRatio < 1.0 - request.fieldOfViewToleranceFraction ||
                            edgeRatio > 1.0 + request.fieldOfViewToleranceFraction) {
                            continue;
                        }
                        const double error =
                            fingerprintError(imageFingerprint, catalogQuad.fingerprint);
                        if (error <= request.fingerprintTolerance) {
                            candidates.push_back({catalogQuad.center, error});
                        }
                    }
                }
            }
        }
    }

    std::sort(candidates.begin(), candidates.end(), [](const CenterCandidate& lhs,
                                                       const CenterCandidate& rhs) {
        return lhs.fingerprintError < rhs.fingerprintError;
    });

    std::vector<CenterCandidate> uniqueCandidates;
    for (const CenterCandidate& candidate : candidates) {
        const bool duplicate = std::any_of(
            uniqueCandidates.begin(),
            uniqueCandidates.end(),
            [&](const CenterCandidate& existing) {
                return skySeparationDegrees(candidate.center, existing.center) <
                    request.approximateHorizontalFieldOfViewDegrees * 0.15;
            }
        );
        if (!duplicate) {
            uniqueCandidates.push_back(candidate);
        }
        if (uniqueCandidates.size() >=
            static_cast<std::size_t>(request.maximumCandidateCenters)) {
            break;
        }
    }

    PlateSolution best = notSolved;
    for (const CenterCandidate& candidate : uniqueCandidates) {
        ConstrainedPlateSolveRequest constrained;
        constrained.detectedStars = request.detectedStars;
        constrained.imageWidth = request.imageWidth;
        constrained.imageHeight = request.imageHeight;
        constrained.catalog = catalog;
        constrained.approximateCenter = candidate.center;
        constrained.approximateHorizontalFieldOfViewDegrees =
            request.approximateHorizontalFieldOfViewDegrees;
        constrained.minimumMatches = request.minimumMatches;
        constrained.matchTolerancePixels = request.matchTolerancePixels;
        constrained.maximumDetectedStars = std::max(20, request.patternCheckingStars + 8);
        constrained.maximumCatalogStars = 36;

        PlateSolution solution = solveConstrained(constrained);
        if (solution.status == PlateSolvingStatus::Solved &&
            (best.status != PlateSolvingStatus::Solved ||
             solution.confidence > best.confidence ||
             (solution.confidence == best.confidence &&
              solution.rootMeanSquareErrorPixels <
                  best.rootMeanSquareErrorPixels))) {
            solution.message = "Lost-in-space quad fingerprint solved and validated.";
            best = std::move(solution);
        }
    }
    return best;
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
         << "  \"sourceImageWidth\": " << report.sourceImageWidth << ",\n"
         << "  \"sourceImageHeight\": " << report.sourceImageHeight << ",\n"
         << "  \"activeRegionX\": " << report.activeRegionX << ",\n"
         << "  \"activeRegionY\": " << report.activeRegionY << ",\n"
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
               << "    \"parityInverted\": "
               << (solution.parityInverted ? "true" : "false") << ",\n"
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

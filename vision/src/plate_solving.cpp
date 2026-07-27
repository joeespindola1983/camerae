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

} // namespace camerae_vision::plate_solving

#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include <opencv2/core.hpp>

namespace camerae_vision::plate_solving {

struct SkyCoordinate {
    double rightAscensionDegrees = 0.0;
    double declinationDegrees = 0.0;
};

struct TangentPlanePoint {
    double xRadians = 0.0;
    double yRadians = 0.0;
};

TangentPlanePoint projectGnomonic(
    const SkyCoordinate& coordinate,
    const SkyCoordinate& tangentPoint
);

SkyCoordinate unprojectGnomonic(
    const TangentPlanePoint& point,
    const SkyCoordinate& tangentPoint
);

struct DetectedStar {
    double x = 0.0;
    double y = 0.0;
    double flux = 0.0;
    double signalToNoise = 0.0;
    double radius = 0.0;
};

struct StarDetectorSettings {
    int maxDimension = 1600;
    double minimumSignalToNoise = 4.5;
    int minimumArea = 2;
    int maximumArea = 180;
    int backgroundKernelSize = 31;
    int maximumStars = 1000;
};

struct StarDetectionResult {
    int imageWidth = 0;
    int imageHeight = 0;
    double elapsedMilliseconds = 0.0;
    double backgroundNoise = 0.0;
    std::vector<DetectedStar> stars;
};

StarDetectionResult detectStars(
    const cv::Mat& image,
    const StarDetectorSettings& settings
);

struct SyntheticStarFieldSettings {
    int width = 1280;
    int height = 720;
    int starCount = 100;
    double noiseSigma = 4.0;
    std::uint64_t seed = 1;
};

struct SyntheticStarField {
    cv::Mat image;
    std::vector<DetectedStar> stars;
};

SyntheticStarField makeSyntheticStarField(const SyntheticStarFieldSettings& settings);

enum class PlateSolvingStatus {
    DetectionCompleted,
    Solved,
    NotSolved,
    InvalidInput
};

struct PlateSolvingLabReport {
    int schemaVersion = 1;
    std::string imagePath;
    int imageWidth = 0;
    int imageHeight = 0;
    int detectedStarCount = 0;
    double detectionMilliseconds = 0.0;
    double backgroundNoise = 0.0;
    PlateSolvingStatus status = PlateSolvingStatus::DetectionCompleted;
    std::string message;
    std::vector<DetectedStar> brightestStars;
};

std::string plateSolvingStatusName(PlateSolvingStatus status);
std::string serializeLabReport(const PlateSolvingLabReport& report);
cv::Mat renderStarDetectionOverlay(
    const cv::Mat& image,
    const StarDetectionResult& detection
);

} // namespace camerae_vision::plate_solving

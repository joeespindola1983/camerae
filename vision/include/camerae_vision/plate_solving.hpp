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

struct ActiveImageRegion {
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;
};

ActiveImageRegion detectActiveImageRegion(
    const cv::Mat& image,
    int nearBlackThreshold = 3,
    double minimumActiveFraction = 0.005
);

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

struct CatalogStar {
    std::string identifier;
    SkyCoordinate coordinate;
    double magnitude = 0.0;
};

std::vector<std::uint8_t> serializeCompactCatalog(
    const std::vector<CatalogStar>& catalog
);

std::vector<CatalogStar> deserializeCompactCatalog(
    const std::vector<std::uint8_t>& bytes
);

struct PlateStarMatch {
    std::string catalogIdentifier;
    SkyCoordinate coordinate;
    double imageX = 0.0;
    double imageY = 0.0;
    double residualPixels = 0.0;
};

struct ConstrainedPlateSolveRequest {
    std::vector<DetectedStar> detectedStars;
    int imageWidth = 0;
    int imageHeight = 0;
    std::vector<CatalogStar> catalog;
    SkyCoordinate approximateCenter;
    double approximateHorizontalFieldOfViewDegrees = 0.0;
    int minimumMatches = 8;
    double matchTolerancePixels = 3.0;
    int maximumDetectedStars = 20;
    int maximumCatalogStars = 30;
};

struct PlateSolution {
    PlateSolvingStatus status = PlateSolvingStatus::NotSolved;
    SkyCoordinate center;
    double rollDegrees = 0.0;
    double horizontalFieldOfViewDegrees = 0.0;
    double verticalFieldOfViewDegrees = 0.0;
    double plateScaleArcsecondsPerPixel = 0.0;
    double rootMeanSquareErrorPixels = 0.0;
    int matchedStars = 0;
    double confidence = 0.0;
    bool parityInverted = false;
    std::string message;
    std::vector<PlateStarMatch> matches;
};

PlateSolution solveConstrained(const ConstrainedPlateSolveRequest& request);

struct LostInSpacePlateSolveRequest {
    std::vector<DetectedStar> detectedStars;
    int imageWidth = 0;
    int imageHeight = 0;
    std::vector<CatalogStar> catalog;
    double approximateHorizontalFieldOfViewDegrees = 0.0;
    double fieldOfViewToleranceFraction = 0.35;
    int minimumMatches = 8;
    double matchTolerancePixels = 3.0;
    int patternCheckingStars = 12;
    int catalogPatternStars = 160;
    int patternNeighbors = 9;
    double fingerprintTolerance = 0.012;
    int maximumCandidateCenters = 8;
};

PlateSolution solveLostInSpace(const LostInSpacePlateSolveRequest& request);

struct PlateSolvingLabReport {
    int schemaVersion = 2;
    std::string imagePath;
    int sourceImageWidth = 0;
    int sourceImageHeight = 0;
    int activeRegionX = 0;
    int activeRegionY = 0;
    int imageWidth = 0;
    int imageHeight = 0;
    int detectedStarCount = 0;
    double detectionMilliseconds = 0.0;
    double backgroundNoise = 0.0;
    PlateSolvingStatus status = PlateSolvingStatus::DetectionCompleted;
    std::string message;
    std::vector<DetectedStar> brightestStars;
    PlateSolution solution;
};

std::string plateSolvingStatusName(PlateSolvingStatus status);
std::string serializeLabReport(const PlateSolvingLabReport& report);
cv::Mat renderStarDetectionOverlay(
    const cv::Mat& image,
    const StarDetectionResult& detection
);
cv::Mat renderPlateSolutionOverlay(
    const cv::Mat& image,
    const StarDetectionResult& detection,
    const PlateSolution& solution
);

} // namespace camerae_vision::plate_solving

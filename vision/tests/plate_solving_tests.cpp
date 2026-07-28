#include "camerae_vision/plate_solving.hpp"

#include <cmath>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>

namespace {

void require(bool condition, const std::string& message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

double angularDifference(double lhs, double rhs) {
    double difference = std::fmod(std::abs(lhs - rhs), 360.0);
    return difference > 180.0 ? 360.0 - difference : difference;
}

void testTangentProjectionRoundTrip() {
    using namespace camerae_vision::plate_solving;

    const SkyCoordinate center{266.4051, -28.936175};
    const SkyCoordinate star{267.125, -28.35};
    const TangentPlanePoint projected = projectGnomonic(star, center);
    const SkyCoordinate recovered = unprojectGnomonic(projected, center);

    require(angularDifference(recovered.rightAscensionDegrees, star.rightAscensionDegrees) < 1e-8,
            "gnomonic round trip must preserve right ascension");
    require(std::abs(recovered.declinationDegrees - star.declinationDegrees) < 1e-8,
            "gnomonic round trip must preserve declination");
}

void testSyntheticStarDetection() {
    using namespace camerae_vision::plate_solving;

    SyntheticStarFieldSettings synthetic;
    synthetic.width = 960;
    synthetic.height = 640;
    synthetic.starCount = 80;
    synthetic.noiseSigma = 3.0;
    synthetic.seed = 20260727;

    const SyntheticStarField field = makeSyntheticStarField(synthetic);

    StarDetectorSettings detector;
    detector.maxDimension = 1200;
    detector.minimumSignalToNoise = 4.0;
    detector.minimumArea = 2;
    detector.maximumArea = 140;

    const StarDetectionResult result = detectStars(field.image, detector);

    require(result.stars.size() >= 68,
            "detector must recover at least 85 percent of clean synthetic stars");
    require(result.stars.size() <= 90,
            "detector must avoid excessive false positives");
    require(result.imageWidth == synthetic.width && result.imageHeight == synthetic.height,
            "detector must report original image dimensions");
    require(result.elapsedMilliseconds >= 0.0,
            "detector must report elapsed time");
}

void testBlankImageDoesNotProduceStars() {
    using namespace camerae_vision::plate_solving;

    const cv::Mat blank(480, 640, CV_8UC3, cv::Scalar::all(12));
    const StarDetectionResult result = detectStars(blank, {});
    require(result.stars.empty(), "blank images must not produce star candidates");
}

void testActiveImageRegionRemovesOnlyUniformLetterboxing() {
    using namespace camerae_vision::plate_solving;

    cv::Mat letterboxed(90, 160, CV_8UC3, cv::Scalar::all(0));
    const cv::Rect content(20, 10, 120, 70);
    letterboxed(content).setTo(cv::Scalar(12, 16, 20));
    letterboxed.at<cv::Vec3b>(18, 80) = cv::Vec3b(220, 220, 220);

    const ActiveImageRegion region = detectActiveImageRegion(letterboxed);
    require(region.x == content.x && region.y == content.y,
            "uniform black borders must be removed from the origin");
    require(region.width == content.width && region.height == content.height,
            "uniform black borders must be removed from the extent");

    cv::Mat darkSky(90, 160, CV_8UC3, cv::Scalar::all(4));
    darkSky.at<cv::Vec3b>(45, 80) = cv::Vec3b(220, 220, 220);
    const ActiveImageRegion fullRegion = detectActiveImageRegion(darkSky);
    require(fullRegion.x == 0 && fullRegion.y == 0 &&
            fullRegion.width == darkSky.cols && fullRegion.height == darkSky.rows,
            "a valid dark sky must not be mistaken for letterboxing");
}

void testJsonReportContract() {
    using namespace camerae_vision::plate_solving;

    PlateSolvingLabReport report;
    report.imagePath = "fixture.png";
    report.sourceImageWidth = 800;
    report.sourceImageHeight = 480;
    report.activeRegionX = 80;
    report.imageWidth = 640;
    report.imageHeight = 480;
    report.detectedStarCount = 42;
    report.detectionMilliseconds = 12.5;
    report.status = PlateSolvingStatus::DetectionCompleted;

    const std::string json = serializeLabReport(report);
    require(json.find("\"schemaVersion\": 2") != std::string::npos,
            "report must expose a stable schema version");
    require(json.find("\"sourceImageWidth\": 800") != std::string::npos &&
            json.find("\"activeRegionX\": 80") != std::string::npos,
            "report must expose reproducible active-image cropping");
    require(json.find("\"detectedStarCount\": 42") != std::string::npos,
            "report must expose the detected star count");
    require(json.find("\"status\": \"detectionCompleted\"") != std::string::npos,
            "report must distinguish detection from a solved plate");
}

void testCompactCatalogRoundTripAndRejectsCorruption() {
    using namespace camerae_vision::plate_solving;

    const std::vector<CatalogStar> expected{
        {"gaia-123", {266.4051, -28.936175}, 1.25},
        {"β-centauri", {210.9558, -60.3730}, 0.61}
    };
    const std::vector<std::uint8_t> encoded = serializeCompactCatalog(expected);
    const std::vector<CatalogStar> decoded = deserializeCompactCatalog(encoded);
    require(decoded.size() == expected.size(),
            "compact catalog must preserve its star count");
    require(decoded[0].identifier == expected[0].identifier &&
            std::abs(decoded[0].coordinate.rightAscensionDegrees -
                     expected[0].coordinate.rightAscensionDegrees) < 0.0001 &&
            std::abs(decoded[1].coordinate.declinationDegrees -
                     expected[1].coordinate.declinationDegrees) < 0.0001,
            "compact catalog must preserve identifiers and coordinates");

    std::vector<std::uint8_t> truncated = encoded;
    truncated.pop_back();
    bool rejected = false;
    try {
        (void)deserializeCompactCatalog(truncated);
    } catch (const std::invalid_argument&) {
        rejected = true;
    }
    require(rejected, "truncated compact catalogs must be rejected");
}

std::vector<camerae_vision::plate_solving::CatalogStar> makeCatalogFixture() {
    using namespace camerae_vision::plate_solving;

    const SkyCoordinate center{266.4051, -28.936175};
    std::vector<CatalogStar> catalog;
    catalog.reserve(36);

    int identifier = 1;
    for (int row = -3; row <= 2; ++row) {
        for (int column = -3; column <= 2; ++column) {
            catalog.push_back({
                std::to_string(identifier++),
                {
                    center.rightAscensionDegrees + column * 0.72 + row * 0.08,
                    center.declinationDegrees + row * 0.63 + column * 0.05
                },
                1.0 + identifier * 0.08
            });
        }
    }
    return catalog;
}

void testConstrainedPlateSolve() {
    using namespace camerae_vision::plate_solving;

    const SkyCoordinate approximateCenter{266.4051, -28.936175};
    const std::vector<CatalogStar> catalog = makeCatalogFixture();
    const int imageWidth = 1200;
    const int imageHeight = 800;
    const double pixelsPerRadian = 6200.0;
    const double rotationRadians = 12.0 * 3.14159265358979323846 / 180.0;
    const double cosine = std::cos(rotationRadians);
    const double sine = std::sin(rotationRadians);
    const cv::Point2d translation(615.0, 388.0);

    std::vector<DetectedStar> detections;
    detections.reserve(catalog.size() + 4);
    std::mt19937 random(20260727);
    std::normal_distribution<double> noise(0.0, 0.18);

    for (const CatalogStar& star : catalog) {
        const TangentPlanePoint tangent = projectGnomonic(star.coordinate, approximateCenter);
        const double x = pixelsPerRadian *
            (cosine * tangent.xRadians - sine * tangent.yRadians) + translation.x;
        const double y = pixelsPerRadian *
            (sine * tangent.xRadians + cosine * tangent.yRadians) + translation.y;
        if (x < 10.0 || x >= imageWidth - 10.0 || y < 10.0 || y >= imageHeight - 10.0) {
            continue;
        }
        detections.push_back({
            x + noise(random),
            y + noise(random),
            5000.0 - star.magnitude * 100.0,
            20.0,
            1.5
        });
    }
    detections.push_back({95.0, 710.0, 700.0, 8.0, 1.2});
    detections.push_back({1080.0, 90.0, 650.0, 7.5, 1.0});

    ConstrainedPlateSolveRequest request;
    request.detectedStars = detections;
    request.imageWidth = imageWidth;
    request.imageHeight = imageHeight;
    request.catalog = catalog;
    request.approximateCenter = approximateCenter;
    request.approximateHorizontalFieldOfViewDegrees = 11.0;
    request.minimumMatches = 10;
    request.matchTolerancePixels = 2.0;

    const PlateSolution solution = solveConstrained(request);
    const double centeredX = imageWidth / 2.0 - translation.x;
    const double centeredY = imageHeight / 2.0 - translation.y;
    const TangentPlanePoint expectedCenterTangent{
        (cosine * centeredX + sine * centeredY) / pixelsPerRadian,
        (-sine * centeredX + cosine * centeredY) / pixelsPerRadian
    };
    const SkyCoordinate expectedCenter =
        unprojectGnomonic(expectedCenterTangent, approximateCenter);

    require(solution.status == PlateSolvingStatus::Solved,
            "consistent catalog geometry must produce a solution");
    require(solution.matchedStars >= 20,
            "solver must retain the majority of visible catalog stars");
    require(angularDifference(
                solution.center.rightAscensionDegrees,
                expectedCenter.rightAscensionDegrees) < 0.01,
            "solver must recover center right ascension");
    require(std::abs(solution.center.declinationDegrees -
                     expectedCenter.declinationDegrees) < 0.01,
            "solver must recover center declination");
    require(std::abs(solution.rollDegrees - 12.0) < 0.25,
            "solver must recover camera roll");
    require(solution.rootMeanSquareErrorPixels < 0.6,
            "clean constrained solution must have a low residual");
    require(solution.confidence > 0.75,
            "well-supported geometry must produce high confidence");

    LostInSpacePlateSolveRequest blindRequest;
    blindRequest.detectedStars = detections;
    blindRequest.imageWidth = imageWidth;
    blindRequest.imageHeight = imageHeight;
    blindRequest.catalog = catalog;
    blindRequest.approximateHorizontalFieldOfViewDegrees = 11.0;
    blindRequest.minimumMatches = 10;
    blindRequest.matchTolerancePixels = 2.0;
    blindRequest.patternCheckingStars = 12;

    const PlateSolution blindSolution = solveLostInSpace(blindRequest);
    require(blindSolution.status == PlateSolvingStatus::Solved,
            "quad index must solve without an approximate sky center");
    require(angularDifference(
                blindSolution.center.rightAscensionDegrees,
                expectedCenter.rightAscensionDegrees) < 0.02,
            "lost-in-space solver must recover center right ascension");
    require(std::abs(blindSolution.center.declinationDegrees -
                     expectedCenter.declinationDegrees) < 0.02,
            "lost-in-space solver must recover center declination");
    require(blindSolution.matchedStars >= 20,
            "lost-in-space solution must be supported by the complete field");

    std::vector<DetectedStar> reflectedDetections;
    reflectedDetections.reserve(catalog.size());
    for (const CatalogStar& star : catalog) {
        const TangentPlanePoint tangent =
            projectGnomonic(star.coordinate, approximateCenter);
        const double x = pixelsPerRadian *
            (cosine * tangent.xRadians + sine * tangent.yRadians) + translation.x;
        const double y = pixelsPerRadian *
            (sine * tangent.xRadians - cosine * tangent.yRadians) + translation.y;
        if (x < 10.0 || x >= imageWidth - 10.0 ||
            y < 10.0 || y >= imageHeight - 10.0) {
            continue;
        }
        reflectedDetections.push_back({
            x,
            y,
            5000.0 - star.magnitude * 100.0,
            20.0,
            1.5
        });
    }

    request.detectedStars = reflectedDetections;
    const PlateSolution reflectedSolution = solveConstrained(request);
    require(reflectedSolution.status == PlateSolvingStatus::Solved,
            "image-coordinate parity must be supported");
    require(reflectedSolution.parityInverted,
            "reflected geometry must be reported in the solution");
    require(reflectedSolution.matchedStars >= 20,
            "reflected solution must retain the complete field");
}

void testConstrainedPlateSolveRejectsUnrelatedStars() {
    using namespace camerae_vision::plate_solving;

    std::vector<DetectedStar> unrelated;
    std::mt19937 random(91);
    std::uniform_real_distribution<double> x(0.0, 1200.0);
    std::uniform_real_distribution<double> y(0.0, 800.0);
    for (int index = 0; index < 30; ++index) {
        unrelated.push_back({x(random), y(random), 1000.0 - index, 8.0, 1.0});
    }

    ConstrainedPlateSolveRequest request;
    request.detectedStars = unrelated;
    request.imageWidth = 1200;
    request.imageHeight = 800;
    request.catalog = makeCatalogFixture();
    request.approximateCenter = {266.4051, -28.936175};
    request.approximateHorizontalFieldOfViewDegrees = 11.0;
    request.minimumMatches = 10;
    request.matchTolerancePixels = 2.0;

    const PlateSolution solution = solveConstrained(request);
    require(solution.status == PlateSolvingStatus::NotSolved,
            "unrelated points must never produce a plate solution");

    LostInSpacePlateSolveRequest blindRequest;
    blindRequest.detectedStars = unrelated;
    blindRequest.imageWidth = 1200;
    blindRequest.imageHeight = 800;
    blindRequest.catalog = makeCatalogFixture();
    blindRequest.approximateHorizontalFieldOfViewDegrees = 11.0;
    blindRequest.minimumMatches = 10;
    blindRequest.matchTolerancePixels = 2.0;

    const PlateSolution blindSolution = solveLostInSpace(blindRequest);
    require(blindSolution.status == PlateSolvingStatus::NotSolved,
            "quad index must reject an unrelated lost-in-space field");
}

void testSolvedJsonReportContract() {
    using namespace camerae_vision::plate_solving;

    PlateSolvingLabReport report;
    report.status = PlateSolvingStatus::Solved;
    report.solution.status = PlateSolvingStatus::Solved;
    report.solution.center = {266.4, -28.9};
    report.solution.rollDegrees = 12.0;
    report.solution.horizontalFieldOfViewDegrees = 11.0;
    report.solution.verticalFieldOfViewDegrees = 7.4;
    report.solution.plateScaleArcsecondsPerPixel = 31.5;
    report.solution.rootMeanSquareErrorPixels = 0.3;
    report.solution.matchedStars = 18;
    report.solution.confidence = 0.95;
    report.solution.parityInverted = true;
    report.solution.matches.push_back({
        "gaia-1",
        {266.5, -28.8},
        320.0,
        240.0,
        0.2
    });

    const std::string json = serializeLabReport(report);
    require(json.find("\"centerRightAscensionDegrees\": 266.4") != std::string::npos,
            "solved report must expose center right ascension");
    require(json.find("\"matchedStars\": 18") != std::string::npos,
            "solved report must expose match support");
    require(json.find("\"parityInverted\": true") != std::string::npos,
            "solved report must expose image-coordinate parity");
    require(json.find("\"catalogIdentifier\": \"gaia-1\"") != std::string::npos,
            "solved report must expose auditable catalog matches");
}

} // namespace

int main() {
    try {
        testTangentProjectionRoundTrip();
        testSyntheticStarDetection();
        testBlankImageDoesNotProduceStars();
        testActiveImageRegionRemovesOnlyUniformLetterboxing();
        testJsonReportContract();
        testCompactCatalogRoundTripAndRejectsCorruption();
        testConstrainedPlateSolve();
        testConstrainedPlateSolveRejectsUnrelatedStars();
        testSolvedJsonReportContract();
        std::cout << "camerae_plate_solving_tests passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "camerae_plate_solving_tests failed: " << error.what() << "\n";
        return 1;
    }
}

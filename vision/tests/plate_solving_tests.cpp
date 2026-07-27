#include "camerae_vision/plate_solving.hpp"

#include <cmath>
#include <iostream>
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

void testJsonReportContract() {
    using namespace camerae_vision::plate_solving;

    PlateSolvingLabReport report;
    report.schemaVersion = 1;
    report.imagePath = "fixture.png";
    report.imageWidth = 640;
    report.imageHeight = 480;
    report.detectedStarCount = 42;
    report.detectionMilliseconds = 12.5;
    report.status = PlateSolvingStatus::DetectionCompleted;

    const std::string json = serializeLabReport(report);
    require(json.find("\"schemaVersion\": 1") != std::string::npos,
            "report must expose a stable schema version");
    require(json.find("\"detectedStarCount\": 42") != std::string::npos,
            "report must expose the detected star count");
    require(json.find("\"status\": \"detectionCompleted\"") != std::string::npos,
            "report must distinguish detection from a solved plate");
}

} // namespace

int main() {
    try {
        testTangentProjectionRoundTrip();
        testSyntheticStarDetection();
        testBlankImageDoesNotProduceStars();
        testJsonReportContract();
        std::cout << "camerae_plate_solving_tests passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "camerae_plate_solving_tests failed: " << error.what() << "\n";
        return 1;
    }
}

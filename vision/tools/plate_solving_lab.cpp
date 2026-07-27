#include "camerae_vision/plate_solving.hpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

#include <opencv2/imgcodecs.hpp>

namespace {

struct Arguments {
    std::string imagePath;
    std::string outputDirectory;
    int maxDimension = 1600;
    double minimumSignalToNoise = 4.5;
};

void printUsage() {
    std::cout
        << "Usage: camerae-plate-solve-lab --image <path> --output <directory> "
           "[--max-dimension <pixels>] [--minimum-snr <value>]\n";
}

Arguments parseArguments(int argc, char** argv) {
    Arguments arguments;
    for (int index = 1; index < argc; ++index) {
        const std::string option = argv[index];
        if (option == "--help" || option == "-h") {
            printUsage();
            std::exit(0);
        }
        if (index + 1 >= argc) {
            throw std::invalid_argument("missing value for " + option);
        }
        const std::string value = argv[++index];
        if (option == "--image") {
            arguments.imagePath = value;
        } else if (option == "--output") {
            arguments.outputDirectory = value;
        } else if (option == "--max-dimension") {
            arguments.maxDimension = std::stoi(value);
        } else if (option == "--minimum-snr") {
            arguments.minimumSignalToNoise = std::stod(value);
        } else {
            throw std::invalid_argument("unknown option: " + option);
        }
    }
    if (arguments.imagePath.empty() || arguments.outputDirectory.empty()) {
        throw std::invalid_argument("--image and --output are required");
    }
    return arguments;
}

} // namespace

int main(int argc, char** argv) {
    namespace filesystem = std::filesystem;
    using namespace camerae_vision::plate_solving;

    try {
        const Arguments arguments = parseArguments(argc, argv);
        const cv::Mat image = cv::imread(arguments.imagePath, cv::IMREAD_UNCHANGED);
        if (image.empty()) {
            throw std::runtime_error("could not decode input image");
        }

        StarDetectorSettings settings;
        settings.maxDimension = arguments.maxDimension;
        settings.minimumSignalToNoise = arguments.minimumSignalToNoise;
        const StarDetectionResult detection = detectStars(image, settings);

        filesystem::create_directories(arguments.outputDirectory);
        const filesystem::path output(arguments.outputDirectory);
        const filesystem::path overlayPath = output / "detected-stars.png";
        const filesystem::path reportPath = output / "report.json";

        if (!cv::imwrite(overlayPath.string(), renderStarDetectionOverlay(image, detection))) {
            throw std::runtime_error("could not write detection overlay");
        }

        PlateSolvingLabReport report;
        report.imagePath = arguments.imagePath;
        report.imageWidth = detection.imageWidth;
        report.imageHeight = detection.imageHeight;
        report.detectedStarCount = static_cast<int>(detection.stars.size());
        report.detectionMilliseconds = detection.elapsedMilliseconds;
        report.backgroundNoise = detection.backgroundNoise;
        report.status = PlateSolvingStatus::DetectionCompleted;
        report.message =
            "Star detection completed. Catalog matching is intentionally not claimed yet.";
        const std::size_t reportStarCount = std::min<std::size_t>(100, detection.stars.size());
        report.brightestStars.assign(
            detection.stars.begin(),
            detection.stars.begin() + reportStarCount
        );

        std::ofstream reportFile(reportPath);
        if (!reportFile) {
            throw std::runtime_error("could not write JSON report");
        }
        reportFile << serializeLabReport(report);

        std::cout << "[CameraePlateSolve] detection.completed"
                  << " | stars=" << detection.stars.size()
                  << " durationMs=" << detection.elapsedMilliseconds
                  << " noise=" << detection.backgroundNoise << "\n"
                  << "[CameraePlateSolve] artifact.overlay | path=" << overlayPath << "\n"
                  << "[CameraePlateSolve] artifact.report | path=" << reportPath << "\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "[CameraePlateSolve] process.failed | message=" << error.what() << "\n";
        printUsage();
        return 1;
    }
}

#include "camerae_vision/plate_solving.hpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include <opencv2/imgcodecs.hpp>

namespace {

struct Arguments {
    std::string imagePath;
    std::string outputDirectory;
    int maxDimension = 1600;
    double minimumSignalToNoise = 4.5;
    std::string catalogPath;
    double approximateRightAscension = 0.0;
    double approximateDeclination = 0.0;
    double approximateFieldOfView = 0.0;
    bool hasApproximateRightAscension = false;
    bool hasApproximateDeclination = false;
    bool lostInSpace = false;
    double matchTolerancePixels = 5.0;
    int minimumMatches = 8;
};

void printUsage() {
    std::cout
        << "Usage: camerae-plate-solve-lab --image <path> --output <directory> "
           "[--max-dimension <pixels>] [--minimum-snr <value>] "
           "[--catalog <csv|camcat> --approx-ra <degrees> --approx-dec <degrees> "
           "--approx-fov <degrees>] "
           "[--catalog <csv|camcat> --lost-in-space --approx-fov <degrees>]\n";
}

Arguments parseArguments(int argc, char** argv) {
    Arguments arguments;
    for (int index = 1; index < argc; ++index) {
        const std::string option = argv[index];
        if (option == "--help" || option == "-h") {
            printUsage();
            std::exit(0);
        }
        if (option == "--lost-in-space") {
            arguments.lostInSpace = true;
            continue;
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
        } else if (option == "--catalog") {
            arguments.catalogPath = value;
        } else if (option == "--approx-ra") {
            arguments.approximateRightAscension = std::stod(value);
            arguments.hasApproximateRightAscension = true;
        } else if (option == "--approx-dec") {
            arguments.approximateDeclination = std::stod(value);
            arguments.hasApproximateDeclination = true;
        } else if (option == "--approx-fov") {
            arguments.approximateFieldOfView = std::stod(value);
        } else if (option == "--match-tolerance") {
            arguments.matchTolerancePixels = std::stod(value);
        } else if (option == "--minimum-matches") {
            arguments.minimumMatches = std::stoi(value);
        } else {
            throw std::invalid_argument("unknown option: " + option);
        }
    }
    if (arguments.imagePath.empty() || arguments.outputDirectory.empty()) {
        throw std::invalid_argument("--image and --output are required");
    }
    const bool requestedSolve = !arguments.catalogPath.empty();
    if (requestedSolve && arguments.approximateFieldOfView <= 0.0) {
        throw std::invalid_argument("--catalog requires --approx-fov");
    }
    if (arguments.matchTolerancePixels <= 0.0 || arguments.minimumMatches < 4) {
        throw std::invalid_argument(
            "--match-tolerance must be positive and --minimum-matches at least four"
        );
    }
    if (requestedSolve && !arguments.lostInSpace &&
        (!arguments.hasApproximateRightAscension ||
         !arguments.hasApproximateDeclination)) {
        throw std::invalid_argument(
            "--catalog requires --approx-ra, --approx-dec, and --approx-fov"
        );
    }
    return arguments;
}

std::vector<camerae_vision::plate_solving::CatalogStar> loadCatalog(
    const std::string& path
) {
    using camerae_vision::plate_solving::CatalogStar;
    using camerae_vision::plate_solving::deserializeCompactCatalog;

    if (std::filesystem::path(path).extension() == ".camcat") {
        std::ifstream binary(path, std::ios::binary);
        if (!binary) {
            throw std::runtime_error("could not open catalog: " + path);
        }
        const std::vector<std::uint8_t> bytes{
            std::istreambuf_iterator<char>(binary),
            std::istreambuf_iterator<char>()
        };
        return deserializeCompactCatalog(bytes);
    }

    std::ifstream file(path);
    if (!file) {
        throw std::runtime_error("could not open catalog: " + path);
    }

    std::vector<CatalogStar> catalog;
    std::string line;
    int lineNumber = 0;
    while (std::getline(file, line)) {
        ++lineNumber;
        if (line.empty() || line[0] == '#') {
            continue;
        }

        std::stringstream stream(line);
        std::string identifier;
        std::string rightAscension;
        std::string declination;
        std::string magnitude;
        if (!std::getline(stream, identifier, ',') ||
            !std::getline(stream, rightAscension, ',') ||
            !std::getline(stream, declination, ',') ||
            !std::getline(stream, magnitude, ',')) {
            if (lineNumber == 1 && line.find("rightAscension") != std::string::npos) {
                continue;
            }
            throw std::runtime_error(
                "invalid catalog row at line " + std::to_string(lineNumber)
            );
        }
        if (lineNumber == 1 &&
            (identifier == "source_id" ||
             rightAscension == "ra" ||
             rightAscension.find("rightAscension") != std::string::npos)) {
            continue;
        }
        catalog.push_back({
            identifier,
            {std::stod(rightAscension), std::stod(declination)},
            std::stod(magnitude)
        });
    }
    if (catalog.empty()) {
        throw std::runtime_error("catalog contains no stars");
    }
    return catalog;
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

        const ActiveImageRegion activeRegion = detectActiveImageRegion(image);
        const cv::Mat activeImage = image(cv::Rect(
            activeRegion.x,
            activeRegion.y,
            activeRegion.width,
            activeRegion.height
        )).clone();

        StarDetectorSettings settings;
        settings.maxDimension = arguments.maxDimension;
        settings.minimumSignalToNoise = arguments.minimumSignalToNoise;
        const StarDetectionResult detection = detectStars(activeImage, settings);

        filesystem::create_directories(arguments.outputDirectory);
        const filesystem::path output(arguments.outputDirectory);
        const filesystem::path overlayPath = output / "detected-stars.png";
        const filesystem::path reportPath = output / "report.json";

        PlateSolvingLabReport report;
        report.imagePath = arguments.imagePath;
        report.sourceImageWidth = image.cols;
        report.sourceImageHeight = image.rows;
        report.activeRegionX = activeRegion.x;
        report.activeRegionY = activeRegion.y;
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

        cv::Mat overlay;
        if (!arguments.catalogPath.empty()) {
            const std::vector<CatalogStar> catalog = loadCatalog(arguments.catalogPath);
            PlateSolution solution;
            if (arguments.lostInSpace) {
                LostInSpacePlateSolveRequest solveRequest;
                solveRequest.detectedStars = detection.stars;
                solveRequest.imageWidth = detection.imageWidth;
                solveRequest.imageHeight = detection.imageHeight;
                solveRequest.catalog = catalog;
                solveRequest.approximateHorizontalFieldOfViewDegrees =
                    arguments.approximateFieldOfView;
                solveRequest.matchTolerancePixels = arguments.matchTolerancePixels;
                solveRequest.minimumMatches = arguments.minimumMatches;
                solution = solveLostInSpace(solveRequest);
            } else {
                ConstrainedPlateSolveRequest solveRequest;
                solveRequest.detectedStars = detection.stars;
                solveRequest.imageWidth = detection.imageWidth;
                solveRequest.imageHeight = detection.imageHeight;
                solveRequest.catalog = catalog;
                solveRequest.approximateCenter = {
                    arguments.approximateRightAscension,
                    arguments.approximateDeclination
                };
                solveRequest.approximateHorizontalFieldOfViewDegrees =
                    arguments.approximateFieldOfView;
                solveRequest.matchTolerancePixels = arguments.matchTolerancePixels;
                solveRequest.minimumMatches = arguments.minimumMatches;
                solution = solveConstrained(solveRequest);
            }
            report.status = solution.status;
            report.message = solution.message;
            report.solution = solution;
            overlay = renderPlateSolutionOverlay(activeImage, detection, solution);
            std::cout << "[CameraePlateSolve] solve.completed"
                      << " | status=" << plateSolvingStatusName(solution.status)
                      << " matches=" << solution.matchedStars
                      << " confidence=" << solution.confidence
                      << " rmse=" << solution.rootMeanSquareErrorPixels << "\n";
        } else {
            overlay = renderStarDetectionOverlay(activeImage, detection);
        }

        if (!cv::imwrite(overlayPath.string(), overlay)) {
            throw std::runtime_error("could not write detection overlay");
        }

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

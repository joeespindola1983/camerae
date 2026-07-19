#include "camerae_processing/alignment_processor.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

namespace {

void printUsage() {
    std::cout
        << "camerae-alignment-preview --reference IMAGE --moving IMAGE --output-dir DIR [options]\n\n"
        << "Options:\n"
        << "  --detector orb|akaze|sift\n"
        << "  --model translation|similarity|affine|homography\n"
        << "  --max-dimension N\n"
        << "  --max-features N\n"
        << "  --match-ratio N\n"
        << "  --mutual-matching 0|1\n"
        << "  --clahe 0|1\n"
        << "  --ransac-threshold N\n"
        << "  --ecc 0|1\n"
        << "  --overlay-opacity N\n";
}

std::string requireValue(int& index, int argc, char* argv[]) {
    if (index + 1 >= argc) {
        throw std::invalid_argument(std::string("faltando valor para ") + argv[index]);
    }
    return argv[++index];
}

bool parseBool(const std::string& value) {
    return value == "1" || value == "true" || value == "yes" || value == "on";
}

void requireWrite(const std::filesystem::path& path, const cv::Mat& image) {
    if (!cv::imwrite(path.string(), image)) {
        throw std::runtime_error("nao foi possivel salvar: " + path.string());
    }
}

cv::Mat resizedReference(const cv::Mat& image, const cv::Size& size) {
    cv::Mat output;
    if (image.size() == size) {
        return image;
    }
    cv::resize(image, output, size, 0.0, 0.0, cv::INTER_AREA);
    return output;
}

cv::Mat makeFeasibilityPreview(
    const cv::Mat& overlay,
    const camerae_processing::AlignmentFeasibility& feasibility
) {
    using camerae_processing::AlignmentDecision;
    cv::Mat output = overlay.clone();
    const int bannerHeight = std::max(92, output.rows / 12);
    cv::Scalar color;
    std::string label;
    switch (feasibility.decision) {
    case AlignmentDecision::Accept:
        color = cv::Scalar(50, 145, 45);
        label = "ACEITAR";
        break;
    case AlignmentDecision::Review:
        color = cv::Scalar(20, 170, 230);
        label = "REVISAR";
        break;
    case AlignmentDecision::Reject:
        color = cv::Scalar(45, 45, 210);
        label = "REJEITAR";
        break;
    }
    cv::rectangle(output, cv::Rect(0, 0, output.cols, bannerHeight), color, cv::FILLED);
    const std::string title = "PRE-VOO: " + label + "  score=" +
        cv::format("%.2f", feasibility.score);
    cv::putText(output, title, cv::Point(28, bannerHeight / 2 - 5),
                cv::FONT_HERSHEY_SIMPLEX, 0.85, cv::Scalar::all(255), 2, cv::LINE_AA);
    if (!feasibility.reasons.empty()) {
        cv::putText(output, feasibility.reasons.front(), cv::Point(28, bannerHeight - 18),
                    cv::FONT_HERSHEY_SIMPLEX, 0.54, cv::Scalar::all(255), 1, cv::LINE_AA);
    }
    return output;
}

void writeReport(
    const std::filesystem::path& path,
    const camerae_processing::AlignmentSettings& settings,
    const camerae_processing::AlignmentResult& result
) {
    std::ofstream report(path);
    if (!report) {
        throw std::runtime_error("nao foi possivel salvar relatorio: " + path.string());
    }
    const auto& metrics = result.metrics;
    report << std::fixed << std::setprecision(6)
        << "{\n"
        << "  \"detector\": \"" << camerae_processing::alignmentDetectorName(settings.detector) << "\",\n"
        << "  \"motionModel\": \"" << camerae_processing::alignmentMotionModelName(settings.motionModel) << "\",\n"
        << "  \"referenceKeypoints\": " << metrics.referenceKeypoints << ",\n"
        << "  \"movingKeypoints\": " << metrics.movingKeypoints << ",\n"
        << "  \"candidateMatches\": " << metrics.candidateMatches << ",\n"
        << "  \"inlierMatches\": " << metrics.inlierMatches << ",\n"
        << "  \"inlierRatio\": " << metrics.inlierRatio << ",\n"
        << "  \"reprojectionRMSE\": " << metrics.reprojectionRMSE << ",\n"
        << "  \"overlapRatio\": " << metrics.overlapRatio << ",\n"
        << "  \"grayMAEBefore\": " << metrics.grayMAEBefore << ",\n"
        << "  \"grayMAEAfter\": " << metrics.grayMAEAfter << ",\n"
        << "  \"eccCorrelation\": " << metrics.eccCorrelation << ",\n"
        << "  \"inlierCoverageRatio\": " << metrics.inlierCoverageRatio << ",\n"
        << "  \"inlierGridCoverageRatio\": " << metrics.inlierGridCoverageRatio << ",\n"
        << "  \"projectedAreaRatio\": " << metrics.projectedAreaRatio << ",\n"
        << "  \"minimumEdgeScale\": " << metrics.minimumEdgeScale << ",\n"
        << "  \"maximumEdgeScale\": " << metrics.maximumEdgeScale << ",\n"
        << "  \"maximumCornerDisplacementRatio\": " << metrics.maximumCornerDisplacementRatio << ",\n"
        << "  \"edgeAlignmentError\": " << metrics.edgeAlignmentError << ",\n"
        << "  \"decision\": \""
        << camerae_processing::alignmentDecisionName(result.feasibility.decision) << "\",\n"
        << "  \"feasibilityScore\": " << result.feasibility.score << ",\n"
        << "  \"feasibilityReasons\": [";
    for (std::size_t index = 0; index < result.feasibility.reasons.size(); ++index) {
        report << (index == 0 ? "\n" : ",\n")
            << "    \"" << result.feasibility.reasons[index] << "\"";
    }
    if (!result.feasibility.reasons.empty()) {
        report << "\n  ";
    }
    report << "],\n"
        << "  \"transformMovingToReference\": [\n";
    for (int row = 0; row < result.transform.rows; ++row) {
        report << "    [";
        for (int column = 0; column < result.transform.cols; ++column) {
            if (column > 0) {
                report << ", ";
            }
            report << result.transform.at<double>(row, column);
        }
        report << "]" << (row + 1 < result.transform.rows ? "," : "") << "\n";
    }
    report << "  ]\n}\n";
}

} // namespace

int main(int argc, char* argv[]) {
    using namespace camerae_processing;

    std::filesystem::path referencePath;
    std::filesystem::path movingPath;
    std::filesystem::path outputDirectory = "out/alignment";
    double overlayOpacity = 0.5;
    AlignmentSettings settings;

    try {
        for (int index = 1; index < argc; ++index) {
            const std::string argument = argv[index];
            if (argument == "--help" || argument == "-h") {
                printUsage();
                return EXIT_SUCCESS;
            } else if (argument == "--reference") {
                referencePath = requireValue(index, argc, argv);
            } else if (argument == "--moving") {
                movingPath = requireValue(index, argc, argv);
            } else if (argument == "--output-dir") {
                outputDirectory = requireValue(index, argc, argv);
            } else if (argument == "--detector") {
                settings.detector = parseAlignmentDetector(requireValue(index, argc, argv));
            } else if (argument == "--model") {
                settings.motionModel = parseAlignmentMotionModel(requireValue(index, argc, argv));
            } else if (argument == "--max-dimension") {
                settings.maxDimension = std::stoi(requireValue(index, argc, argv));
            } else if (argument == "--max-features") {
                settings.maxFeatures = std::stoi(requireValue(index, argc, argv));
            } else if (argument == "--match-ratio") {
                settings.matchRatio = std::stof(requireValue(index, argc, argv));
            } else if (argument == "--mutual-matching") {
                settings.mutualMatching = parseBool(requireValue(index, argc, argv));
            } else if (argument == "--clahe") {
                settings.useCLAHE = parseBool(requireValue(index, argc, argv));
            } else if (argument == "--ransac-threshold") {
                settings.ransacThreshold = std::stod(requireValue(index, argc, argv));
            } else if (argument == "--ecc") {
                settings.refineWithECC = parseBool(requireValue(index, argc, argv));
            } else if (argument == "--overlay-opacity") {
                overlayOpacity = std::stod(requireValue(index, argc, argv));
            } else {
                throw std::invalid_argument("argumento desconhecido: " + argument);
            }
        }

        if (referencePath.empty() || movingPath.empty()) {
            printUsage();
            return EXIT_FAILURE;
        }

        const cv::Mat referenceInput = cv::imread(referencePath.string(), cv::IMREAD_COLOR);
        const cv::Mat movingInput = cv::imread(movingPath.string(), cv::IMREAD_COLOR);
        if (referenceInput.empty() || movingInput.empty()) {
            throw std::runtime_error("nao foi possivel ler as imagens de entrada");
        }

        const AlignmentResult result = alignImages(referenceInput, movingInput, settings);
        const cv::Mat reference = resizedReference(referenceInput, result.alignedImage.size());
        std::filesystem::create_directories(outputDirectory);
        requireWrite(outputDirectory / "01_reference.jpg", reference);
        requireWrite(outputDirectory / "02_moving.jpg", resizedReference(movingInput, reference.size()));
        requireWrite(outputDirectory / "03_aligned.jpg", result.alignedImage);
        const cv::Mat overlay = makeAlignmentOverlay(
            reference,
            result.alignedImage,
            result.validMask,
            overlayOpacity
        );
        requireWrite(outputDirectory / "00_feasibility.jpg",
                     makeFeasibilityPreview(overlay, result.feasibility));
        requireWrite(outputDirectory / "04_overlay.jpg", overlay);
        requireWrite(
            outputDirectory / "05_difference_heatmap.jpg",
            makeAlignmentDifference(reference, result.alignedImage, result.validMask)
        );
        requireWrite(
            outputDirectory / "06_red_cyan.jpg",
            makeAlignmentRedCyan(reference, result.alignedImage, result.validMask)
        );
        requireWrite(outputDirectory / "07_inlier_matches.jpg", result.matchVisualization);
        writeReport(outputDirectory / "metrics.json", settings, result);

        std::cout << std::fixed << std::setprecision(3)
            << "detector: " << alignmentDetectorName(settings.detector) << "\n"
            << "modelo: " << alignmentMotionModelName(settings.motionModel) << "\n"
            << "matches: " << result.metrics.inlierMatches << "/"
            << result.metrics.candidateMatches << " inliers\n"
            << "RMSE de reprojecao: " << result.metrics.reprojectionRMSE << " px\n"
            << "MAE antes/depois: " << result.metrics.grayMAEBefore << "/"
            << result.metrics.grayMAEAfter << "\n"
            << "sobreposicao valida: " << result.metrics.overlapRatio * 100.0 << "%\n"
            << "erro local de bordas: " << result.metrics.edgeAlignmentError << " px\n"
            << "pre-voo: " << alignmentDecisionName(result.feasibility.decision)
            << " (score " << result.feasibility.score << ")\n";
        for (const auto& reason : result.feasibility.reasons) {
            std::cout << "  - " << reason << "\n";
        }
        std::cout
            << "output: " << outputDirectory << "\n";
        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        std::cerr << "erro: " << error.what() << "\n";
        return EXIT_FAILURE;
    }
}

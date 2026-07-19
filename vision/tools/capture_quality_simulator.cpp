#include "capture_quality_simulator_support.hpp"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#include <utility>

#include <opencv2/imgcodecs.hpp>

namespace {

using namespace camerae_vision;
using namespace camerae_vision::simulator;

void printUsage() {
    std::cout
        << "camerae-capture-quality-simulator --reference IMAGE --frames DIRECTORY --report FILE [options]\n\n"
        << "Options:\n"
        << "  --analysis-fps N  Analysis cadence; default 2\n"
        << "  --capture-fps N   Simulated source cadence; default 30\n"
        << "  --latest-only 0|1 Keep only the latest pending frame; default 1\n";
}

std::string requireValue(int& index, int argc, char* argv[]) {
    if (index + 1 >= argc) {
        throw std::invalid_argument(std::string("faltando valor para ") + argv[index]);
    }
    return argv[++index];
}

bool parseBool(const std::string& value) {
    if (value == "1" || value == "true" || value == "on") return true;
    if (value == "0" || value == "false" || value == "off") return false;
    throw std::invalid_argument("booleano invalido: " + value);
}

bool supportedImage(const std::filesystem::path& path) {
    std::string extension = path.extension().string();
    std::transform(extension.begin(), extension.end(), extension.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return extension == ".jpg" || extension == ".jpeg" || extension == ".png" ||
        extension == ".tif" || extension == ".tiff" || extension == ".bmp";
}

std::vector<std::filesystem::path> discoverFrames(const std::filesystem::path& directory) {
    if (!std::filesystem::is_directory(directory)) {
        throw std::invalid_argument("diretorio de frames invalido: " + directory.string());
    }
    std::vector<std::filesystem::path> paths;
    for (const auto& entry : std::filesystem::directory_iterator(directory)) {
        if (entry.is_regular_file() && supportedImage(entry.path())) {
            paths.push_back(entry.path());
        }
    }
    std::sort(paths.begin(), paths.end());
    return paths;
}

std::size_t matrixBytes(const cv::Mat& image) {
    return image.total() * image.elemSize();
}

std::size_t approximateRetainedBytes(const cv::Mat& reference, const cv::Mat& moving) {
    const auto reducedBytes = [](const cv::Mat& image) {
        const int longest = std::max(image.cols, image.rows);
        const double scale = longest > 640 ? 640.0 / static_cast<double>(longest) : 1.0;
        const auto pixels = static_cast<std::size_t>(image.cols * scale) *
            static_cast<std::size_t>(image.rows * scale);
        return pixels * 4;
    };
    return matrixBytes(reference) + matrixBytes(moving) +
        reducedBytes(reference) * 2 + reducedBytes(moving);
}

cv::Mat readReducedColor(const std::filesystem::path& path) {
    return cv::imread(path.string(), cv::IMREAD_REDUCED_COLOR_4);
}

} // namespace

int main(int argc, char* argv[]) {
    std::filesystem::path referencePath;
    std::filesystem::path framesDirectory;
    std::filesystem::path reportPath;
    CaptureSimulationSettings settings;

    try {
        for (int index = 1; index < argc; ++index) {
            const std::string argument = argv[index];
            if (argument == "--help" || argument == "-h") {
                printUsage();
                return EXIT_SUCCESS;
            } else if (argument == "--reference") {
                referencePath = requireValue(index, argc, argv);
            } else if (argument == "--frames") {
                framesDirectory = requireValue(index, argc, argv);
            } else if (argument == "--report") {
                reportPath = requireValue(index, argc, argv);
            } else if (argument == "--analysis-fps") {
                settings.analysisFPS = std::stod(requireValue(index, argc, argv));
            } else if (argument == "--capture-fps") {
                settings.captureFPS = std::stod(requireValue(index, argc, argv));
            } else if (argument == "--latest-only") {
                settings.latestOnly = parseBool(requireValue(index, argc, argv));
            } else {
                throw std::invalid_argument("argumento desconhecido: " + argument);
            }
        }
        if (referencePath.empty() || framesDirectory.empty() || reportPath.empty()) {
            printUsage();
            return EXIT_FAILURE;
        }

        const cv::Mat reference = readReducedColor(referencePath);
        if (reference.empty()) {
            throw std::runtime_error("nao foi possivel ler a referencia");
        }
        const auto framePaths = discoverFrames(framesDirectory);
        const CaptureSchedule schedule = buildSchedule(framePaths.size(), settings);
        CaptureSimulationReport report;
        report.receivedFrames = schedule.receivedFrames;
        report.droppedFrames = schedule.droppedFrames;
        report.maximumPendingFrames = schedule.maximumPendingFrames;
        AlignmentQualityEvaluator evaluator;
        LatestOnlyWorkerClock workerClock;

        for (const std::size_t sourceIndex : schedule.frameIndices) {
            const double frameTimestamp = static_cast<double>(sourceIndex) / settings.captureFPS;
            if (settings.latestOnly && !workerClock.canStart(frameTimestamp)) {
                ++report.droppedFrames;
                continue;
            }
            const auto& path = framePaths[sourceIndex];
            const cv::Mat moving = readReducedColor(path);
            if (moving.empty()) {
                throw std::runtime_error("nao foi possivel ler frame: " + path.string());
            }
            report.peakRetainedBytes = std::max(
                report.peakRetainedBytes, approximateRetainedBytes(reference, moving)
            );
            CaptureSimulationFrameResult frame;
            frame.sourceIndex = sourceIndex;
            frame.sourcePath = path.string();
            const auto started = std::chrono::steady_clock::now();
            try {
                const auto quality = evaluator.evaluate(reference, moving);
                frame.decision = quality.decision;
                frame.score = quality.score;
                frame.overlapRatio = quality.overlapRatio;
                frame.reprojectionRMSE = quality.reprojectionRMSE;
                frame.edgeAlignmentError = quality.edgeAlignmentError;
                frame.latencyMilliseconds = quality.estimatedLatencyMilliseconds;
                frame.selectedModel = quality.selectedModel;
                frame.reasons = quality.reasons;
            } catch (const std::exception& error) {
                frame.decision = AlignmentDecision::Reject;
                frame.reasons.push_back(std::string("falha na analise: ") + error.what());
                frame.latencyMilliseconds = std::chrono::duration<double, std::milli>(
                    std::chrono::steady_clock::now() - started
                ).count();
            }
            workerClock.didStart(frameTimestamp, frame.latencyMilliseconds);
            report.frames.push_back(std::move(frame));
        }
        finalizeReport(report);
        if (!reportPath.parent_path().empty()) {
            std::filesystem::create_directories(reportPath.parent_path());
        }
        std::ofstream output(reportPath);
        if (!output) {
            throw std::runtime_error("nao foi possivel criar relatorio");
        }
        output << reportJSON(report);
        std::cout << "recebidos=" << report.receivedFrames
                  << " analisados=" << report.analyzedFrames
                  << " descartados=" << report.droppedFrames
                  << " p95=" << report.latency.p95Milliseconds << "ms\n"
                  << "report: " << reportPath << "\n";
        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        std::cerr << "erro: " << error.what() << "\n";
        return EXIT_FAILURE;
    }
}

#include "camerae_processing/astro_processor.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

void printUsage() {
    std::cout
        << "camerae-astro-preview --input FRAMES_DIR --output out/preview.jpg [options]\n\n"
        << "Options:\n"
        << "  --profile natural|milkyway|strong\n"
        << "  --stack N\n"
        << "  --start-frame N\n"
        << "  --max-frames N\n"
        << "  --max-dimension N\n"
        << "  --align 0|1\n"
        << "  --denoise 0|1\n"
        << "  --denoise-strength N\n"
        << "  --denoise-color-strength N\n"
        << "  --contrast N\n"
        << "  --brightness N\n"
        << "  --saturation N\n"
        << "  --gamma N\n";
}

std::string requireValue(int& index, int argc, char* argv[]) {
    if (index + 1 >= argc) {
        throw std::invalid_argument(std::string("faltando valor para ") + argv[index]);
    }
    index += 1;
    return argv[index];
}

bool parseBool(const std::string& value) {
    return value == "1" || value == "true" || value == "yes" || value == "on";
}

} // namespace

int main(int argc, char* argv[]) {
    using namespace camerae_processing;

    std::filesystem::path inputDirectory;
    std::filesystem::path outputPath = "out/astro_preview.jpg";
    auto profile = AstroProfile::Natural;
    AstroSettings settings = presetSettings(profile);

    try {
        for (int index = 1; index < argc; ++index) {
            const std::string arg = argv[index];

            if (arg == "--help" || arg == "-h") {
                printUsage();
                return EXIT_SUCCESS;
            } else if (arg == "--input") {
                inputDirectory = requireValue(index, argc, argv);
            } else if (arg == "--output") {
                outputPath = requireValue(index, argc, argv);
            } else if (arg == "--profile") {
                profile = parseProfile(requireValue(index, argc, argv));
                const int stackSize = settings.stackSize;
                const int startFrame = settings.startFrame;
                const int maxFrames = settings.maxFrames;
                const int maxDimension = settings.maxDimension;
                settings = presetSettings(profile);
                settings.stackSize = stackSize;
                settings.startFrame = startFrame;
                settings.maxFrames = maxFrames;
                settings.maxDimension = maxDimension;
            } else if (arg == "--stack") {
                settings.stackSize = std::stoi(requireValue(index, argc, argv));
            } else if (arg == "--start-frame") {
                settings.startFrame = std::stoi(requireValue(index, argc, argv));
            } else if (arg == "--max-frames") {
                settings.maxFrames = std::stoi(requireValue(index, argc, argv));
            } else if (arg == "--max-dimension") {
                settings.maxDimension = std::stoi(requireValue(index, argc, argv));
            } else if (arg == "--align") {
                settings.alignStars = parseBool(requireValue(index, argc, argv));
            } else if (arg == "--denoise") {
                settings.denoise = parseBool(requireValue(index, argc, argv));
            } else if (arg == "--denoise-strength") {
                settings.denoiseStrength = std::stof(requireValue(index, argc, argv));
            } else if (arg == "--denoise-color-strength") {
                settings.denoiseColorStrength = std::stof(requireValue(index, argc, argv));
            } else if (arg == "--contrast") {
                settings.contrast = std::stof(requireValue(index, argc, argv));
            } else if (arg == "--brightness") {
                settings.brightness = std::stof(requireValue(index, argc, argv));
            } else if (arg == "--saturation") {
                settings.saturation = std::stof(requireValue(index, argc, argv));
            } else if (arg == "--gamma") {
                settings.gamma = std::stof(requireValue(index, argc, argv));
            } else {
                throw std::invalid_argument("argumento desconhecido: " + arg);
            }
        }

        if (inputDirectory.empty()) {
            printUsage();
            return EXIT_FAILURE;
        }

        const auto result = renderAstroPreview(inputDirectory, outputPath, settings);
        std::cout << "frames encontrados: " << result.discoveredFrames << "\n";
        std::cout << "frames usados: " << result.usedFrames << "\n";
        std::cout << "output: " << result.outputPath << "\n";
        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        std::cerr << "erro: " << error.what() << "\n";
        return EXIT_FAILURE;
    }
}

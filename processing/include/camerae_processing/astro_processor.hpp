#pragma once

#include <filesystem>
#include <string>
#include <vector>

namespace camerae_processing {

enum class AstroProfile {
    Natural,
    MilkyWay,
    Strong
};

struct AstroSettings {
    int stackSize = 10;
    int startFrame = 1;
    int maxFrames = 0;
    int maxDimension = 1920;
    bool alignStars = false;
    bool denoise = false;
    float denoiseStrength = 6.0f;
    float denoiseColorStrength = 6.0f;
    int denoiseTemplateWindow = 7;
    int denoiseSearchWindow = 21;
    float contrast = 1.06f;
    float brightness = 0.0f;
    float saturation = 1.04f;
    float gamma = 1.0f;
};

struct AstroResult {
    int discoveredFrames = 0;
    int usedFrames = 0;
    std::filesystem::path outputPath;
};

AstroSettings presetSettings(AstroProfile profile);
AstroProfile parseProfile(const std::string& value);
std::string profileName(AstroProfile profile);

std::vector<std::filesystem::path> listFramePaths(const std::filesystem::path& directory);

AstroResult renderAstroPreview(
    const std::filesystem::path& inputDirectory,
    const std::filesystem::path& outputPath,
    const AstroSettings& settings
);

} // namespace camerae_processing

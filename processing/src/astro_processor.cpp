#include "camerae_processing/astro_processor.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <stdexcept>

#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/photo.hpp>

namespace camerae_processing {
namespace {

std::string lowercased(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

bool isSupportedImage(const std::filesystem::path& path) {
    const auto extension = lowercased(path.extension().string());
    return extension == ".jpg" || extension == ".jpeg" || extension == ".png" || extension == ".tif" || extension == ".tiff";
}

cv::Mat resizeToMaxDimension(const cv::Mat& image, int maxDimension) {
    if (maxDimension <= 0) {
        return image;
    }

    const int longestSide = std::max(image.cols, image.rows);
    if (longestSide <= maxDimension) {
        return image;
    }

    const double scale = static_cast<double>(maxDimension) / static_cast<double>(longestSide);
    cv::Mat resized;
    cv::resize(image, resized, cv::Size(), scale, scale, cv::INTER_AREA);
    return resized;
}

cv::Mat grayscaleFloatForAlignment(const cv::Mat& image) {
    cv::Mat gray;
    cv::cvtColor(image, gray, cv::COLOR_BGR2GRAY);

    const int longestSide = std::max(gray.cols, gray.rows);
    if (longestSide > 768) {
        const double scale = 768.0 / static_cast<double>(longestSide);
        cv::resize(gray, gray, cv::Size(), scale, scale, cv::INTER_AREA);
    }

    cv::Mat gray32;
    gray.convertTo(gray32, CV_32F, 1.0 / 255.0);
    cv::GaussianBlur(gray32, gray32, cv::Size(3, 3), 0);
    return gray32;
}

cv::Mat alignToReference(const cv::Mat& image, const cv::Mat& reference) {
    cv::Mat referenceGray = grayscaleFloatForAlignment(reference);
    cv::Mat imageGray = grayscaleFloatForAlignment(image);

    if (referenceGray.size() != imageGray.size()) {
        cv::resize(imageGray, imageGray, referenceGray.size(), 0, 0, cv::INTER_AREA);
    }

    cv::Mat window;
    cv::createHanningWindow(window, referenceGray.size(), CV_32F);
    const cv::Point2d shift = cv::phaseCorrelate(referenceGray, imageGray, window);

    const double scaleX = static_cast<double>(image.cols) / static_cast<double>(imageGray.cols);
    const double scaleY = static_cast<double>(image.rows) / static_cast<double>(imageGray.rows);
    cv::Mat transform = (cv::Mat_<double>(2, 3) << 1, 0, -shift.x * scaleX, 0, 1, -shift.y * scaleY);

    cv::Mat aligned;
    cv::warpAffine(image, aligned, transform, image.size(), cv::INTER_LINEAR, cv::BORDER_REFLECT);
    return aligned;
}

cv::Mat applySaturation(const cv::Mat& image, float saturation) {
    if (std::abs(saturation - 1.0f) < 0.001f) {
        return image;
    }

    cv::Mat hsv;
    cv::cvtColor(image, hsv, cv::COLOR_BGR2HSV);
    std::vector<cv::Mat> channels;
    cv::split(hsv, channels);
    channels[1].convertTo(channels[1], channels[1].type(), saturation, 0);
    cv::merge(channels, hsv);

    cv::Mat output;
    cv::cvtColor(hsv, output, cv::COLOR_HSV2BGR);
    return output;
}

cv::Mat applyGamma(const cv::Mat& image, float gamma) {
    if (gamma <= 0.0f || std::abs(gamma - 1.0f) < 0.001f) {
        return image;
    }

    cv::Mat lut(1, 256, CV_8U);
    for (int index = 0; index < 256; ++index) {
        const float normalized = static_cast<float>(index) / 255.0f;
        lut.at<unsigned char>(index) = static_cast<unsigned char>(
            std::clamp(std::pow(normalized, gamma) * 255.0f, 0.0f, 255.0f)
        );
    }

    cv::Mat output;
    cv::LUT(image, lut, output);
    return output;
}

cv::Mat postProcess(const cv::Mat& image, const AstroSettings& settings) {
    cv::Mat output;
    image.convertTo(output, -1, settings.contrast, settings.brightness * 255.0f);
    output = applySaturation(output, settings.saturation);
    output = applyGamma(output, settings.gamma);

    if (settings.denoise) {
        cv::Mat denoised;
        cv::fastNlMeansDenoisingColored(
            output,
            denoised,
            settings.denoiseStrength,
            settings.denoiseColorStrength,
            settings.denoiseTemplateWindow,
            settings.denoiseSearchWindow
        );
        output = denoised;
    }

    return output;
}

} // namespace

AstroSettings presetSettings(AstroProfile profile) {
    AstroSettings settings;

    switch (profile) {
    case AstroProfile::Natural:
        settings.alignStars = false;
        settings.denoise = false;
        settings.contrast = 1.06f;
        settings.saturation = 1.04f;
        settings.gamma = 1.0f;
        break;
    case AstroProfile::MilkyWay:
        settings.alignStars = true;
        settings.denoise = true;
        settings.denoiseStrength = 5.0f;
        settings.denoiseColorStrength = 5.0f;
        settings.contrast = 1.12f;
        settings.saturation = 1.10f;
        settings.gamma = 0.92f;
        break;
    case AstroProfile::Strong:
        settings.alignStars = true;
        settings.denoise = true;
        settings.denoiseStrength = 7.0f;
        settings.denoiseColorStrength = 7.0f;
        settings.contrast = 1.20f;
        settings.saturation = 1.18f;
        settings.gamma = 0.86f;
        break;
    }

    return settings;
}

AstroProfile parseProfile(const std::string& value) {
    const auto key = lowercased(value);
    if (key == "natural") {
        return AstroProfile::Natural;
    }
    if (key == "milkyway" || key == "milky-way" || key == "via-lactea" || key == "vialactea") {
        return AstroProfile::MilkyWay;
    }
    if (key == "strong" || key == "forte") {
        return AstroProfile::Strong;
    }

    throw std::invalid_argument("perfil astro invalido: " + value);
}

std::string profileName(AstroProfile profile) {
    switch (profile) {
    case AstroProfile::Natural:
        return "natural";
    case AstroProfile::MilkyWay:
        return "milkyway";
    case AstroProfile::Strong:
        return "strong";
    }
    return "natural";
}

std::vector<std::filesystem::path> listFramePaths(const std::filesystem::path& directory) {
    if (!std::filesystem::is_directory(directory)) {
        throw std::invalid_argument("input nao e uma pasta: " + directory.string());
    }

    std::vector<std::filesystem::path> frames;
    for (const auto& entry : std::filesystem::directory_iterator(directory)) {
        if (entry.is_regular_file() && isSupportedImage(entry.path())) {
            frames.push_back(entry.path());
        }
    }

    std::sort(frames.begin(), frames.end());
    return frames;
}

AstroResult renderAstroPreview(
    const std::filesystem::path& inputDirectory,
    const std::filesystem::path& outputPath,
    const AstroSettings& settings
) {
    const auto frames = listFramePaths(inputDirectory);
    if (frames.empty()) {
        throw std::runtime_error("nenhum frame encontrado");
    }

    const int startIndex = std::max(settings.startFrame - 1, 0);
    if (startIndex >= static_cast<int>(frames.size())) {
        throw std::runtime_error("start-frame esta alem do numero de frames");
    }

    const int requestedCount = settings.maxFrames > 0 ? settings.maxFrames : settings.stackSize;
    const int availableCount = static_cast<int>(frames.size()) - startIndex;
    const int usedCount = std::min(std::max(requestedCount, 1), availableCount);

    cv::Mat reference = cv::imread(frames[startIndex].string(), cv::IMREAD_COLOR);
    if (reference.empty()) {
        throw std::runtime_error("nao foi possivel ler frame: " + frames[startIndex].string());
    }
    reference = resizeToMaxDimension(reference, settings.maxDimension);

    cv::Mat accumulator = cv::Mat::zeros(reference.size(), CV_32FC3);
    for (int index = 0; index < usedCount; ++index) {
        cv::Mat frame = cv::imread(frames[startIndex + index].string(), cv::IMREAD_COLOR);
        if (frame.empty()) {
            continue;
        }

        frame = resizeToMaxDimension(frame, settings.maxDimension);
        if (frame.size() != reference.size()) {
            cv::resize(frame, frame, reference.size(), 0, 0, cv::INTER_AREA);
        }

        if (settings.alignStars && index > 0) {
            frame = alignToReference(frame, reference);
        }

        cv::Mat frame32;
        frame.convertTo(frame32, CV_32FC3, 1.0 / 255.0);
        accumulator += frame32;
    }

    accumulator /= static_cast<float>(usedCount);
    cv::Mat averaged;
    accumulator.convertTo(averaged, CV_8UC3, 255.0);
    averaged = postProcess(averaged, settings);

    std::filesystem::create_directories(outputPath.parent_path());
    if (!cv::imwrite(outputPath.string(), averaged)) {
        throw std::runtime_error("nao foi possivel gravar output: " + outputPath.string());
    }

    return AstroResult{
        .discoveredFrames = static_cast<int>(frames.size()),
        .usedFrames = usedCount,
        .outputPath = outputPath
    };
}

} // namespace camerae_processing

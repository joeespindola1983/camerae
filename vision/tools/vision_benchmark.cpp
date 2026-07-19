#include "vision_benchmark_support.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

int main(int argc, char* argv[]) {
    std::size_t iterations = 20;
    std::filesystem::path reportPath;
    try {
        for (int index = 1; index < argc; ++index) {
            const std::string argument = argv[index];
            if (argument == "--iterations" && index + 1 < argc) {
                iterations = static_cast<std::size_t>(std::stoul(argv[++index]));
            } else if (argument == "--report" && index + 1 < argc) {
                reportPath = argv[++index];
            } else if (argument == "--help" || argument == "-h") {
                std::cout << "camerae-vision-benchmark [--iterations N] [--report FILE]\n";
                return EXIT_SUCCESS;
            } else {
                throw std::invalid_argument("argumento desconhecido ou incompleto: " + argument);
            }
        }
        const auto report = camerae_vision::benchmark::runSyntheticBenchmark(iterations);
        const std::string json = camerae_vision::benchmark::benchmarkJSON(report);
        if (reportPath.empty()) {
            std::cout << json;
        } else {
            if (!reportPath.parent_path().empty()) {
                std::filesystem::create_directories(reportPath.parent_path());
            }
            std::ofstream output(reportPath);
            if (!output) throw std::runtime_error("nao foi possivel criar relatorio");
            output << json;
            std::cout << "report: " << reportPath << "\n";
        }
        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        std::cerr << "erro: " << error.what() << "\n";
        return EXIT_FAILURE;
    }
}

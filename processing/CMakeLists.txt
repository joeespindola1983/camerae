cmake_minimum_required(VERSION 3.20)

project(camerae_processing LANGUAGES CXX)

include(CTest)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(OpenCV REQUIRED COMPONENTS calib3d core features2d imgcodecs imgproc photo video)

add_library(camerae_processing
    src/alignment_processor.cpp
    src/astro_processor.cpp
)

target_include_directories(camerae_processing
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${OpenCV_INCLUDE_DIRS}
)

target_link_libraries(camerae_processing
    PUBLIC
        ${OpenCV_LIBS}
)

add_executable(camerae-astro-preview
    tools/astro_preview.cpp
)

target_link_libraries(camerae-astro-preview
    PRIVATE
        camerae_processing
)

add_executable(camerae-alignment-preview
    tools/alignment_preview.cpp
)

target_link_libraries(camerae-alignment-preview
    PRIVATE
        camerae_processing
)

if(BUILD_TESTING)
    add_executable(camerae_processing_tests
        tests/alignment_processor_tests.cpp
        tests/astro_processor_tests.cpp
    )

    target_link_libraries(camerae_processing_tests
        PRIVATE
            camerae_processing
    )

    add_test(NAME camerae_processing_tests COMMAND camerae_processing_tests)
endif()

cmake_minimum_required(VERSION 3.20)

project(camerae_processing LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(OpenCV REQUIRED COMPONENTS core imgcodecs imgproc photo)

add_library(camerae_processing
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

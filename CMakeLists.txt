cmake_minimum_required(VERSION 3.12)
project(QDTS_SC VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# SuperCollider plugin API
set(SC_PATH "" CACHE PATH "Path to SuperCollider source")

if(NOT SC_PATH)
    message(FATAL_ERROR "SC_PATH not set. Please provide path to SuperCollider source with -DSC_PATH=/path/to/supercollider")
endif()

# Include SuperCollider plugin headers
include_directories(
    ${SC_PATH}/include/plugin_interface
    ${SC_PATH}/include/common
    ${SC_PATH}/common
)

# Platform-specific settings
if(APPLE)
    set(CMAKE_SHARED_MODULE_SUFFIX ".scx")
elseif(WIN32)
    set(CMAKE_SHARED_MODULE_SUFFIX ".scx")
else()
    set(CMAKE_SHARED_MODULE_SUFFIX ".so")
endif()

# Build the QDTSSolver plugin
add_library(QDTSSolver MODULE
    plugins/QDTSSolver/QDTSSolver.cpp
)

# Set output directory
set_target_properties(QDTSSolver PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/plugins"
    PREFIX ""
)

# Build the NQDTSSolver plugin (neural network solver)
add_library(NQDTSSolver MODULE
    plugins/NQDTSSolver/NQDTSSolver.cpp
    plugins/NQDTSSolver/nqdts_weights_data.c
)

target_include_directories(NQDTSSolver PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/plugins/NQDTSSolver
)

set_target_properties(NQDTSSolver PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/plugins"
    PREFIX ""
)

# Installation
install(TARGETS QDTSSolver NQDTSSolver
    LIBRARY DESTINATION "lib/SuperCollider/plugins"
)

install(DIRECTORY sc-classes/
    DESTINATION "share/SuperCollider/Extensions/QDTS_SC"
    FILES_MATCHING PATTERN "*.sc"
)

message(STATUS "QDTS_SC - Quadratic Distortion Tone Spectra for SuperCollider")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "SC_PATH: ${SC_PATH}")

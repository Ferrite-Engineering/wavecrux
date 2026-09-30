# CMakeLists.txt — cross-platform build for the WaveCrux 1-Wire
# decoder demonstrator plugin.
#
# Linux / macOS:
#   cmake -S . -B build
#   cmake --build build
#
# Windows (MSVC, from a Developer PowerShell):
#   cmake -S . -B build
#   cmake --build build --config Release
#
# Windows (MinGW):
#   cmake -S . -B build -G "MinGW Makefiles"
#   cmake --build build
#
# The produced shared library is named:
#   * Linux:   libwavecrux_onewire.so
#   * macOS:   libwavecrux_onewire.dylib
#   * Windows: wavecrux_onewire.dll  (no `lib` prefix on Windows by
#              convention; the WaveCrux loader scans for both forms)

cmake_minimum_required(VERSION 3.13)
project(wavecrux_onewire C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_library(wavecrux_onewire SHARED onewire_decoder.c)

# The header is two levels above this file, alongside the rest of the
# wavecrux open-core source tree.
target_include_directories(wavecrux_onewire PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../../include")

if(MSVC)
    target_compile_options(wavecrux_onewire PRIVATE /W4 /permissive-)
else()
    target_compile_options(wavecrux_onewire PRIVATE
        -Wall -Wextra -O2 -fPIC)
endif()

# Force the lib prefix on Linux / macOS for filesystem consistency
# with WaveCrux's loader scan; Windows uses no prefix.
set_target_properties(wavecrux_onewire PROPERTIES
    OUTPUT_NAME "wavecrux_onewire")
if(NOT WIN32)
    set_target_properties(wavecrux_onewire PROPERTIES PREFIX "lib")
endif()

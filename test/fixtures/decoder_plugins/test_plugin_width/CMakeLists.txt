cmake_minimum_required(VERSION 3.13)
project(test_width C)

set(CMAKE_C_STANDARD 11)

# The header is two levels above this fixture directory, alongside
# wavecrux_decoder.h's home in the open-core repo.
add_library(test_width SHARED test_plugin.c)
target_include_directories(test_width PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../include)

# Prefix-stripped naming so the produced file is libtest_width.so /
# .dylib / test_width.dll, matching what the loader scans for.
set_target_properties(test_width PROPERTIES PREFIX "lib")
if(WIN32)
    set_target_properties(test_width PROPERTIES PREFIX "")
endif()

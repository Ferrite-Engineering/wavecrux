cmake_minimum_required(VERSION 3.13)
project(test_lifecycle C)

set(CMAKE_C_STANDARD 11)

# The header is two levels above this fixture directory, alongside
# wavecrux_decoder.h's home in the open-core repo.
add_library(test_lifecycle SHARED test_plugin.c)
target_include_directories(test_lifecycle PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../include)

# Prefix-stripped naming so the produced file is libtest_lifecycle.so /
# .dylib / test_lifecycle.dll, matching what the loader scans for.
set_target_properties(test_lifecycle PROPERTIES PREFIX "lib")
if(WIN32)
    set_target_properties(test_lifecycle PROPERTIES PREFIX "")
endif()

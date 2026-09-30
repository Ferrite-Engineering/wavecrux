cmake_minimum_required(VERSION 3.13)
project(test_config C)

set(CMAKE_C_STANDARD 11)

# The header is two levels above this fixture directory, alongside
# wavecrux_decoder.h's home in the open-core repo.
add_library(test_config SHARED test_plugin.c)
target_include_directories(test_config PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../include)

# Prefix-stripped naming so the produced file is libtest_config.so /
# .dylib / test_config.dll, matching what the loader scans for.
set_target_properties(test_config PROPERTIES PREFIX "lib")
if(WIN32)
    set_target_properties(test_config PROPERTIES PREFIX "")
endif()

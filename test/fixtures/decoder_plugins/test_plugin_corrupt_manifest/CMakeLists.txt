cmake_minimum_required(VERSION 3.13)
project(test_corrupt_manifest C)

set(CMAKE_C_STANDARD 11)

add_library(test_corrupt_manifest SHARED test_plugin.c)
target_include_directories(test_corrupt_manifest PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../include)

set_target_properties(test_corrupt_manifest PROPERTIES PREFIX "lib")
if(WIN32)
    set_target_properties(test_corrupt_manifest PROPERTIES PREFIX "")
endif()

cmake_minimum_required(VERSION 3.13)
project(test_missing_symbol C)

set(CMAKE_C_STANDARD 11)

add_library(test_missing_symbol SHARED test_plugin.c)
target_include_directories(test_missing_symbol PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../include)

set_target_properties(test_missing_symbol PROPERTIES PREFIX "lib")
if(WIN32)
    set_target_properties(test_missing_symbol PROPERTIES PREFIX "")
endif()

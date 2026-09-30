cmake_minimum_required(VERSION 3.13)
project(test_abi_mismatch C)

set(CMAKE_C_STANDARD 11)

add_library(test_abi_mismatch SHARED test_plugin.c)
target_include_directories(test_abi_mismatch PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../include)

set_target_properties(test_abi_mismatch PROPERTIES PREFIX "lib")
if(WIN32)
    set_target_properties(test_abi_mismatch PROPERTIES PREFIX "")
endif()

cmake_minimum_required(VERSION 3.15)

project(json_example)

add_subdirectory(deps/json)

add_executable(json_example
    src/main.cpp
)

target_include_directories(json_example PRIVATE
    deps/json/single_include
)

target_compile_options(json_example PRIVATE
    -std=c++17
    -D_HAS_EXCEPTIONS=1
)


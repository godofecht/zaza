cmake_minimum_required(VERSION 3.15)

project(cmake_net)

add_subdirectory(deps/zlib)
add_subdirectory(deps/mbedtls)
add_subdirectory(deps/curl)

add_executable(cmake_net
    examples/cmake_net/src/main.cpp
)

target_include_directories(cmake_net PRIVATE
    zig-out/deps/include
)

target_compile_options(cmake_net PRIVATE
    -std=c++17
)


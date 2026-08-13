# A plain CMake project that consumes a Zaza-built library through find_package.
# Nothing here knows the library was built by Zaza: it finds package_math the
# same way it would find any installed CMake package, links the imported target
# package_math::package_math, and gets the include dir and library for free.
#
# Point CMake at the Zaza install prefix:
#   cmake -S . -B build -DCMAKE_PREFIX_PATH=/path/to/zaza/zig-out
#   cmake --build build
cmake_minimum_required(VERSION 3.15)
project(zaza_cmake_consumer CXX)

# Requests 1.0; the Zaza-exported package is 1.2.0, so the generated
# ConfigVersion.cmake reports it as compatible.
find_package(package_math 1.0 REQUIRED)

add_executable(cmake_consumer main.cpp)
target_link_libraries(cmake_consumer PRIVATE package_math::package_math)

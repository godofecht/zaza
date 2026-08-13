# A pre-existing CMake component, left as-is. Zaza builds this subtree with
# CMake and links the result into the Zaza top-level build.
cmake_minimum_required(VERSION 3.15)
project(mathlib C)

add_library(mathlib STATIC src/mathlib.c)
target_include_directories(mathlib PUBLIC include)

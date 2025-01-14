cmake_minimum_required(VERSION 3.15)
project(json_example CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add nlohmann/json
add_subdirectory(deps/json) 
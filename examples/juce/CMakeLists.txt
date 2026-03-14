cmake_minimum_required(VERSION 3.15)

project(JuceExample VERSION 1.0.0)
include(FetchContent)
set(FETCHCONTENT_QUIET OFF)
set(FETCHCONTENT_UPDATES_DISCONNECTED ON)
if (DEFINED JUCE_SOURCE_DIR)
    set(FETCHCONTENT_SOURCE_DIR_JUCE "${JUCE_SOURCE_DIR}")
elseif (EXISTS "${CMAKE_CURRENT_LIST_DIR}/deps/juce/CMakeLists.txt")
    set(FETCHCONTENT_SOURCE_DIR_JUCE "${CMAKE_CURRENT_LIST_DIR}/deps/juce")
endif()
set(JUCE_GIT_TAG "7.0.9")
FetchContent_Declare(juce
    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
    GIT_TAG ${JUCE_GIT_TAG}
)
FetchContent_MakeAvailable(juce)

juce_add_gui_app(JuceExample
    PRODUCT_NAME "JuceExample"
    COMPANY_NAME "Example"
    VERSION "1.0.0"
)

target_sources(JuceExample PRIVATE
    src/main.cpp
)

target_link_libraries(JuceExample PRIVATE
    juce::juce_core
    juce::juce_data_structures
    juce::juce_events
    juce::juce_graphics
    juce::juce_gui_basics
)

target_compile_features(JuceExample PRIVATE cxx_std_17)

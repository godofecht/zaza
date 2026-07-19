cmake_minimum_required(VERSION 3.15)

project(ZazaJuce VERSION 1.0.0)
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

juce_add_gui_app(ZazaJuce
    PRODUCT_NAME "ZazaJuce"
    COMPANY_NAME "Zaza"
    VERSION "1.0.0"
)

target_sources(ZazaJuce PRIVATE
    src/main.cpp
)

target_link_libraries(ZazaJuce PRIVATE
    juce::juce_core
    juce::juce_data_structures
    juce::juce_events
    juce::juce_graphics
    juce::juce_gui_basics
    juce::juce_audio_basics
    juce::juce_audio_devices
    juce::juce_audio_formats
    juce::juce_audio_processors
    juce::juce_audio_utils
)

target_compile_features(ZazaJuce PRIVATE cxx_std_17)

cmake_minimum_required(VERSION 3.15)

project(JuceExample VERSION 1.0.0)
add_subdirectory(deps/juce)

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

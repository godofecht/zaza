const std = @import("std");
const testing = std.testing;
const cpp = @import("cpp_example");

test "zaza-juce config has correct name and company" {
    const zaza_juce = @import("zaza_juce");
    const config = zaza_juce.app_config;

    try testing.expectEqualStrings("ZazaJuce", config.name);
    try testing.expectEqualStrings("Zaza", config.company);
    try testing.expectEqualStrings("1.0.0", config.version);
    try testing.expectEqualStrings("JUCE audio synth example built with Zaza", config.description);
}

test "zaza-juce config has audio modules" {
    const zaza_juce = @import("zaza_juce");
    const config = zaza_juce.app_config;

    // Must have audio modules beyond the basic GUI ones
    const required_modules = [_][]const u8{
        "juce_core",
        "juce_audio_basics",
        "juce_audio_devices",
        "juce_audio_formats",
        "juce_audio_processors",
        "juce_audio_utils",
    };

    for (required_modules) |required| {
        var found = false;
        for (config.modules) |module| {
            if (std.mem.eql(u8, module, required)) {
                found = true;
                break;
            }
        }
        try testing.expect(found);
    }
}

test "zaza-juce config points to correct cmake root" {
    const zaza_juce = @import("zaza_juce");
    const config = zaza_juce.app_config;

    try testing.expectEqualStrings("examples/zaza-juce", config.cmake_root);
}

test "zaza-juce config has source files" {
    const zaza_juce = @import("zaza_juce");
    const config = zaza_juce.app_config;

    try testing.expectEqual(@as(usize, 1), config.sources.len);
    try testing.expectEqualStrings("src/main.cpp", config.sources[0]);
}

test "zaza-juce config uses JUCE 7.0.9" {
    const zaza_juce = @import("zaza_juce");
    const config = zaza_juce.app_config;

    try testing.expect(config.juce_git_tag != null);
    try testing.expectEqualStrings("7.0.9", config.juce_git_tag.?);
}

test "zaza-juce has more modules than base juce example" {
    const zaza_juce = @import("zaza_juce");
    const config = zaza_juce.app_config;

    // The base JUCE example only has 5 GUI modules; zaza-juce adds 5 audio modules
    try testing.expect(config.modules.len > 5);
    try testing.expectEqual(@as(usize, 10), config.modules.len);
}

test "JUCEApplication builder configures from zaza-juce config" {
    const zaza_juce = @import("zaza_juce");
    const config = zaza_juce.app_config;

    // Verify the config struct is well-formed for JUCEApplication.JuceConfig
    try testing.expect(config.name.len > 0);
    try testing.expect(config.company.len > 0);
    try testing.expect(config.version.len > 0);
    try testing.expect(config.sources.len > 0);
    try testing.expect(config.modules.len > 0);
}

test "zaza-juce CMakeLists.txt exists and references correct target" {
    const cmake_content = @embedFile("../examples/zaza-juce/CMakeLists.txt");

    // Verify it references ZazaJuce target
    try testing.expect(std.mem.indexOf(u8, cmake_content, "project(ZazaJuce") != null);
    try testing.expect(std.mem.indexOf(u8, cmake_content, "juce_add_gui_app(ZazaJuce") != null);
    try testing.expect(std.mem.indexOf(u8, cmake_content, "target_sources(ZazaJuce") != null);
    try testing.expect(std.mem.indexOf(u8, cmake_content, "target_link_libraries(ZazaJuce") != null);

    // Verify audio modules are linked
    try testing.expect(std.mem.indexOf(u8, cmake_content, "juce::juce_audio_basics") != null);
    try testing.expect(std.mem.indexOf(u8, cmake_content, "juce::juce_audio_devices") != null);
    try testing.expect(std.mem.indexOf(u8, cmake_content, "juce::juce_audio_utils") != null);
}

test "zaza-juce main.cpp exists and has correct application class" {
    const main_content = @embedFile("../examples/zaza-juce/src/main.cpp");

    // Verify it uses ZazaJuceApplication
    try testing.expect(std.mem.indexOf(u8, main_content, "ZazaJuceApplication") != null);
    try testing.expect(std.mem.indexOf(u8, main_content, "START_JUCE_APPLICATION(ZazaJuceApplication)") != null);

    // Verify it has synth components
    try testing.expect(std.mem.indexOf(u8, main_content, "SineWaveVoice") != null);
    try testing.expect(std.mem.indexOf(u8, main_content, "SynthComponent") != null);
    try testing.expect(std.mem.indexOf(u8, main_content, "MidiKeyboardComponent") != null);

    // Verify branding
    try testing.expect(std.mem.indexOf(u8, main_content, "Zaza Synth") != null);
}

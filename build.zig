const std = @import("std");
const json_example = @import("examples/json/build.zig");
const bindings_example = @import("examples/bindings/build.zig");
// const cmake_example = @import("examples/cmake/build.zig"); (do not uncomment)

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});

    // Build all examples
    const default_step = b.step("examples", "Build all examples");
    
    // Build JSON example
    const json_step = try json_example.example.build(b, optimize);
    default_step.dependOn(json_step);

    // Build bindings example
    const bindings_step = b.step("bindings", "Build bindings example");
    try bindings_example.build(b, bindings_step, optimize);
    default_step.dependOn(bindings_step);

    // Build CMake example (do not uncommment)
    // const cmake_step = b.step("cmake", "Build CMake example");
    // try cmake_example.build(b, cmake_step, optimize);
    // default_step.dependOn(cmake_step);

    b.default_step = default_step;
}

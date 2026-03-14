const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    // Performance benchmark executable
    const benchmark_exe = b.addExecutable(.{
        .name = "performance_benchmark",
        .root_source_file = b.path("benchmarks/performance_benchmark.zig"),
        .target = b.host,
    });
    
    // Add JSON dependency for benchmarks
    benchmark_exe.addIncludePath(.{ .cwd_relative = "deps/json/single_include" });
    
    // Install benchmark executable
    b.installArtifact(benchmark_exe);
    
    // Create benchmark run step
    const run_benchmark = b.addRunArtifact(benchmark_exe);
    run_benchmark.step.dependOn(&b.getInstallStep());
    
    const benchmark_step = b.step("benchmark", "Run performance benchmarks");
    benchmark_step.dependOn(&run_benchmark.step);
    
    // Create memory benchmark
    const memory_benchmark = b.addExecutable(.{
        .name = "memory_benchmark",
        .root_source_file = b.path("benchmarks/memory_benchmark.zig"),
        .target = b.host,
    });
    
    b.installArtifact(memory_benchmark);
    
    const run_memory = b.addRunArtifact(memory_benchmark);
    run_memory.step.dependOn(&b.getInstallStep());
    
    const memory_step = b.step("memory", "Run memory usage benchmarks");
    memory_step.dependOn(&run_memory.step);
    
    // Create scalability benchmark
    const scalability_benchmark = b.addExecutable(.{
        .name = "scalability_benchmark",
        .root_source_file = b.path("benchmarks/scalability_benchmark.zig"),
        .target = b.host,
    });
    
    b.installArtifact(scalability_benchmark);
    
    const run_scalability = b.addRunArtifact(scalability_benchmark);
    run_scalability.step.dependOn(&b.getInstallStep());
    
    const scalability_step = b.step("scalability", "Run scalability benchmarks");
    scalability_step.dependOn(&run_scalability.step);
    
    // Create comprehensive benchmark suite
    const all_benchmarks = b.step("benchmarks", "Run all benchmarks");
    all_benchmarks.dependOn(&benchmark_step);
    all_benchmarks.dependOn(&memory_step);
    all_benchmarks.dependOn(&scalability_step);
    
    // Add benchmark comparison with CMake
    const cmake_comparison = b.addExecutable(.{
        .name = "cmake_comparison",
        .root_source_file = b.path("benchmarks/cmake_comparison.zig"),
        .target = b.host,
    });
    
    b.installArtifact(cmake_comparison);
    
    const run_comparison = b.addRunArtifact(cmake_comparison);
    run_comparison.step.dependOn(&b.getInstallStep());
    
    const comparison_step = b.step("compare", "Compare Zaza performance with CMake");
    comparison_step.dependOn(&run_comparison.step);
}

const std = @import("std");
const Graph = @import("build_graph.zig").Graph;
const Node = @import("build_graph.zig").Node;

var install_artifact: ?*std.Build.Step.Compile = null;
var build_artifact: ?*std.Build.Step.Compile = null;

fn logMessage(step: *std.Build.Step, _: *std.Progress.Node) anyerror!void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\x1b[33m=== {s} ===\x1b[0m\n", .{step.name});
}

fn logBuildCpp(step: *std.Build.Step, _: *std.Progress.Node) anyerror!void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\x1b[33m=== {s} ===\x1b[0m\n", .{step.name});
    if (build_artifact) |artifact| {
        try stdout.print("Building {s}\n", .{artifact.out_filename});
    }
}

fn logInstall(step: *std.Build.Step, _: *std.Progress.Node) anyerror!void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\x1b[33m=== {s} ===\x1b[0m\n", .{step.name});
    if (install_artifact) |artifact| {
        try stdout.print("Installing to zig-out/bin/{s}\n", .{artifact.out_filename});
    }
}

pub const BuildManager = struct {
    graph: Graph,
    b: *std.Build,
    
    pub fn init(b: *std.Build) BuildManager {
        b.verbose = false;  // Disable Zig's progress reporting
        return .{
            .graph = Graph.init(b.allocator),
            .b = b,
        };
    }
    
    pub fn deinit(self: *BuildManager) void {
        self.graph.deinit();
    }
    
    pub fn createStep(self: *BuildManager, name: []const u8, log_message: ?[]const u8) !*Node {
        const node = try self.graph.addNode(name);
        if (log_message) |msg| {
            node.message = try self.b.allocator.dupe(u8, msg);
            const step = self.b.step(msg, "Build step");
            step.makeFn = logMessage;
            node.log_step = step;
        }
        return node;
    }

    pub fn addInstallCommand(self: *BuildManager, node: *Node, artifact: *std.Build.Step.Compile) !void {
        const install = self.b.addInstallArtifact(artifact, .{});
        install_artifact = artifact;
        if (node.log_step) |log| {
            log.makeFn = logInstall;
            log.dependOn(&install.step);
        }
        node.cmd_step = &install.step;
    }
    
    pub fn addDependency(self: *BuildManager, from: *Node, to: *Node) !void {
        try self.graph.addEdge(from, to);
        if (to.log_step) |to_log| {
            if (from.cmd_step) |from_cmd| {
                to_log.dependOn(from_cmd);
            }
        }
        if (to.cmd_step) |to_cmd| {
            if (from.cmd_step) |from_cmd| {
                to_cmd.dependOn(from_cmd);
            }
        }
    }
    
    pub fn getFinalStep(self: *BuildManager) !*std.Build.Step {
        const sorted = try self.graph.topologicalSort();
        defer sorted.deinit();
        
        const final_step = self.b.step("build", "Complete build process");
        for (sorted.items) |node| {
            if (node.log_step) |step| {
                final_step.dependOn(step);
            }
            if (node.cmd_step) |step| {
                final_step.dependOn(step);
            }
        }
        return final_step;
    }

    pub fn addBuildCommand(_: *BuildManager, node: *Node, artifact: *std.Build.Step.Compile) !void {
        build_artifact = artifact;
        artifact.step.name = "";  // Make the step name empty to suppress default output
        if (node.log_step) |log| {
            log.makeFn = logBuildCpp;
            log.dependOn(&artifact.step);
        }
        node.cmd_step = &artifact.step;
    }
};
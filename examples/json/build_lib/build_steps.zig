const std = @import("std");
const Graph = @import("build_graph.zig").Graph;
const Node = @import("build_graph.zig").Node;

fn logMessage(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n\x1b[1;36m=== {s} ===\x1b[0m\n", .{step.name});

    // Explain what common commands do
    if (std.mem.startsWith(u8, step.name, "build_")) {
        try stdout.print("\x1b[90mCompiling C++ code with the following settings:\x1b[0m\n", .{});
        try stdout.print("  - Compiler: Zig C++ compiler\n", .{});
        try stdout.print("  - Standard: C++17\n", .{});
        try stdout.print("  - Exceptions: Enabled\n", .{});
        try stdout.print("  - RTTI: Enabled\n", .{});
        try stdout.print("  - Sanitizers: Undefined behavior disabled\n", .{});
    } else if (std.mem.startsWith(u8, step.name, "install_")) {
        try stdout.print("\x1b[90mInstalling built artifacts to zig-out/bin\x1b[0m\n", .{});
    }

    _ = options;
}

fn logCommand(cmd: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    
    // Add context based on the command
    if (cmd.len > 0) {
        if (std.mem.eql(u8, cmd[0], "cmake")) {
            try stdout.print("\n\x1b[1;36mConfiguring CMake build...\x1b[0m\n", .{});
        } else if (std.mem.eql(u8, cmd[0], "zig")) {
            if (cmd.len > 1 and std.mem.eql(u8, cmd[1], "build-exe")) {
                try stdout.print("\n\x1b[1;36mCompiling...\x1b[0m\n", .{});
            }
        }
    }

    // Print the full command in gray
    try stdout.print("\x1b[90m", .{});
    for (cmd, 0..) |arg, i| {
        if (i > 0) try stdout.print(" ", .{});
        try stdout.print("{s}", .{arg});
    }
    try stdout.print("\x1b[0m\n\n", .{});
}

pub const BuildManager = struct {
    b: *std.Build,
    allocator: std.mem.Allocator,
    steps: std.ArrayList(*Node),
    graph: *Graph,

    pub fn init(b: *std.Build) BuildManager {
        const graph = b.allocator.create(Graph) catch unreachable;
        graph.* = Graph.init(b.allocator);
        return .{
            .b = b,
            .allocator = b.allocator,
            .steps = std.ArrayList(*Node).init(b.allocator),
            .graph = graph,
        };
    }

    pub fn deinit(self: *BuildManager) void {
        self.steps.deinit();
        self.graph.deinit();
        self.allocator.destroy(self.graph);
    }

    pub fn createStep(self: *BuildManager, name: []const u8, description: []const u8) !*Node {
        _ = description;
        const step = try self.b.allocator.create(std.Build.Step);
        step.* = std.Build.Step.init(.{
            .id = .custom,
            .name = name,
            .owner = self.b,
            .makeFn = logMessage,
        });

        const node = try self.graph.addNode(name);
        try self.steps.append(node);
        node.cmd_step = step;

        return node;
    }

    pub fn addDependency(self: *BuildManager, from: *Node, to: *Node) !void {
        try self.graph.addEdge(from, to);
        if (from.cmd_step) |step_from| {
            if (to.cmd_step) |step_to| {
                step_from.dependencies.append(step_to) catch unreachable;
            }
        }
    }

    pub fn addBuildCommand(_: *BuildManager, node: *Node, compile_step: *std.Build.Step.Compile) !void {
        if (node.cmd_step) |step| {
            step.dependencies.append(&compile_step.step) catch unreachable;
        }
    }

    pub fn getFinalStep(self: *BuildManager) !*std.Build.Step {
        const final_step = try self.b.allocator.create(std.Build.Step);
        final_step.* = std.Build.Step.init(.{
            .id = .custom,
            .name = "build-all",
            .owner = self.b,
            .makeFn = struct {
                fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
                    _ = options;
                    const stdout = std.io.getStdOut().writer();
                    try stdout.print("\n\x1b[1;32m=== Build Complete ===\x1b[0m\n", .{});
                    try stdout.print("Executables installed to: \x1b[1mzig-out/bin\x1b[0m\n\n", .{});
                    _ = step;
                }
            }.make,
        });

        for (self.steps.items) |node| {
            if (node.cmd_step) |step| {
                final_step.dependencies.append(step) catch unreachable;
            }
        }

        return final_step;
    }
};
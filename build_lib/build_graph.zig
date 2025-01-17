const std = @import("std");

pub const Node = struct {
    id: u32,
    name: []const u8,
    message: ?[]const u8,
    step: ?*std.Build.Step,
    log_step: ?*std.Build.Step = null,  // for logging
    cmd_step: ?*std.Build.Step = null,  // for the command
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, id: u32, name: []const u8) !*Node {
        const self = try allocator.create(Node);
        self.* = .{
            .id = id,
            .name = try allocator.dupe(u8, name),
            .message = null,
            .step = null,
            .allocator = allocator,
        };
        return self;
    }
    
    pub fn deinit(self: *Node) void {
        self.allocator.free(self.name);
        if (self.message) |msg| {
            self.allocator.free(msg);
        }
        self.allocator.destroy(self);
    }
};

pub const Edge = struct {
    from: *Node,
    to: *Node,
};

pub const Graph = struct {
    nodes: std.ArrayList(*Node),
    edges: std.ArrayList(Edge),
    allocator: std.mem.Allocator,
    next_id: u32,
    
    pub fn init(allocator: std.mem.Allocator) Graph {
        return .{
            .nodes = std.ArrayList(*Node).init(allocator),
            .edges = std.ArrayList(Edge).init(allocator),
            .allocator = allocator,
            .next_id = 0,
        };
    }
    
    pub fn deinit(self: *Graph) void {
        for (self.nodes.items) |node| {
            node.deinit();
        }
        self.nodes.deinit();
        self.edges.deinit();
    }
    
    pub fn addNode(self: *Graph, name: []const u8) !*Node {
        const node = try Node.init(self.allocator, self.next_id, name);
        self.next_id += 1;
        try self.nodes.append(node);
        return node;
    }
    
    pub fn addEdge(self: *Graph, from: *Node, to: *Node) !void {
        try self.edges.append(.{ .from = from, .to = to });
    }
    
    pub fn getDependencies(self: *Graph, node: *Node) !std.ArrayList(*Node) {
        var deps = std.ArrayList(*Node).init(self.allocator);
        for (self.edges.items) |edge| {
            if (edge.to == node) {
                try deps.append(edge.from);
            }
        }
        return deps;
    }
    
    pub fn getDependents(self: *Graph, node: *Node) !std.ArrayList(*Node) {
        var deps = std.ArrayList(*Node).init(self.allocator);
        for (self.edges.items) |edge| {
            if (edge.from == node) {
                try deps.append(edge.to);
            }
        }
        return deps;
    }
    
    pub fn topologicalSort(self: *Graph) !std.ArrayList(*Node) {
        var sorted = std.ArrayList(*Node).init(self.allocator);
        var visited = std.AutoHashMap(*Node, void).init(self.allocator);
        defer visited.deinit();
        
        for (self.nodes.items) |node| {
            if (!visited.contains(node)) {
                try self.visit(node, &visited, &sorted);
            }
        }
        
        return sorted;
    }
    
    fn visit(self: *Graph, node: *Node, visited: *std.AutoHashMap(*Node, void), sorted: *std.ArrayList(*Node)) !void {
        try visited.put(node, {});
        
        const deps = try self.getDependencies(node);
        defer deps.deinit();
        
        for (deps.items) |dep| {
            if (!visited.contains(dep)) {
                try self.visit(dep, visited, sorted);
            }
        }
        
        try sorted.append(node);
    }
}; 
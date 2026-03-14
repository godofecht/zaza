const std = @import("std");
const testing = std.testing;
const graph_mod = @import("build_graph");

test "empty graph has no nodes" {
    var g = graph_mod.Graph.init(testing.allocator);
    defer g.deinit();

    try testing.expectEqual(@as(usize, 0), g.nodes.items.len);
    try testing.expectEqual(@as(usize, 0), g.edges.items.len);
}

test "addNode creates nodes with incrementing ids" {
    var g = graph_mod.Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addNode("compile");
    const b = try g.addNode("link");
    const c = try g.addNode("install");

    try testing.expectEqual(@as(u32, 0), a.id);
    try testing.expectEqual(@as(u32, 1), b.id);
    try testing.expectEqual(@as(u32, 2), c.id);
    try testing.expectEqual(@as(usize, 3), g.nodes.items.len);
    try testing.expectEqualStrings("compile", a.name);
    try testing.expectEqualStrings("link", b.name);
    try testing.expectEqualStrings("install", c.name);
}

test "addEdge creates directed edges" {
    var g = graph_mod.Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addNode("a");
    const b = try g.addNode("b");
    try g.addEdge(a, b);

    try testing.expectEqual(@as(usize, 1), g.edges.items.len);
    try testing.expect(g.edges.items[0].from == a);
    try testing.expect(g.edges.items[0].to == b);
}

test "getDependencies returns upstream nodes" {
    var g = graph_mod.Graph.init(testing.allocator);
    defer g.deinit();

    const compile = try g.addNode("compile");
    const link = try g.addNode("link");
    const install = try g.addNode("install");

    // compile -> link -> install
    try g.addEdge(compile, link);
    try g.addEdge(link, install);

    // link depends on compile
    var link_deps = try g.getDependencies(link);
    defer link_deps.deinit();
    try testing.expectEqual(@as(usize, 1), link_deps.items.len);
    try testing.expect(link_deps.items[0] == compile);

    // install depends on link
    var install_deps = try g.getDependencies(install);
    defer install_deps.deinit();
    try testing.expectEqual(@as(usize, 1), install_deps.items.len);
    try testing.expect(install_deps.items[0] == link);

    // compile has no dependencies
    var compile_deps = try g.getDependencies(compile);
    defer compile_deps.deinit();
    try testing.expectEqual(@as(usize, 0), compile_deps.items.len);
}

test "getDependents returns downstream nodes" {
    var g = graph_mod.Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addNode("a");
    const b = try g.addNode("b");
    const c = try g.addNode("c");

    try g.addEdge(a, b);
    try g.addEdge(a, c);

    var dependents = try g.getDependents(a);
    defer dependents.deinit();
    try testing.expectEqual(@as(usize, 2), dependents.items.len);
}

test "topologicalSort returns valid ordering for linear chain" {
    var g = graph_mod.Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addNode("a");
    const b = try g.addNode("b");
    const c = try g.addNode("c");

    // a -> b -> c
    try g.addEdge(a, b);
    try g.addEdge(b, c);

    var sorted = try g.topologicalSort();
    defer sorted.deinit();

    try testing.expectEqual(@as(usize, 3), sorted.items.len);

    // a must come before b, b must come before c
    var a_idx: usize = 0;
    var b_idx: usize = 0;
    var c_idx: usize = 0;
    for (sorted.items, 0..) |node, i| {
        if (node == a) a_idx = i;
        if (node == b) b_idx = i;
        if (node == c) c_idx = i;
    }
    try testing.expect(a_idx < b_idx);
    try testing.expect(b_idx < c_idx);
}

test "topologicalSort handles diamond dependency" {
    var g = graph_mod.Graph.init(testing.allocator);
    defer g.deinit();

    //     a
    //    / \
    //   b   c
    //    \ /
    //     d
    const a = try g.addNode("a");
    const b = try g.addNode("b");
    const c = try g.addNode("c");
    const d = try g.addNode("d");

    try g.addEdge(a, b);
    try g.addEdge(a, c);
    try g.addEdge(b, d);
    try g.addEdge(c, d);

    var sorted = try g.topologicalSort();
    defer sorted.deinit();

    try testing.expectEqual(@as(usize, 4), sorted.items.len);

    // a must come before b and c; b and c must come before d
    var a_idx: usize = 0;
    var b_idx: usize = 0;
    var c_idx: usize = 0;
    var d_idx: usize = 0;
    for (sorted.items, 0..) |node, i| {
        if (node == a) a_idx = i;
        if (node == b) b_idx = i;
        if (node == c) c_idx = i;
        if (node == d) d_idx = i;
    }
    try testing.expect(a_idx < b_idx);
    try testing.expect(a_idx < c_idx);
    try testing.expect(b_idx < d_idx);
    try testing.expect(c_idx < d_idx);
}

test "topologicalSort handles disconnected nodes" {
    var g = graph_mod.Graph.init(testing.allocator);
    defer g.deinit();

    _ = try g.addNode("isolated_a");
    _ = try g.addNode("isolated_b");
    _ = try g.addNode("isolated_c");

    var sorted = try g.topologicalSort();
    defer sorted.deinit();

    try testing.expectEqual(@as(usize, 3), sorted.items.len);
}

test "multiple dependencies on single node" {
    var g = graph_mod.Graph.init(testing.allocator);
    defer g.deinit();

    const fmt = try g.addNode("fmt");
    const zlib = try g.addNode("zlib");
    const ssl = try g.addNode("ssl");
    const app = try g.addNode("app");

    try g.addEdge(fmt, app);
    try g.addEdge(zlib, app);
    try g.addEdge(ssl, app);

    var app_deps = try g.getDependencies(app);
    defer app_deps.deinit();
    try testing.expectEqual(@as(usize, 3), app_deps.items.len);
}

test "node starts with null optional fields" {
    var g = graph_mod.Graph.init(testing.allocator);
    defer g.deinit();

    const n = try g.addNode("test_node");
    try testing.expect(n.message == null);
    try testing.expect(n.step == null);
    try testing.expect(n.log_step == null);
    try testing.expect(n.cmd_step == null);
}

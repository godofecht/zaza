const std = @import("std");
const testing = std.testing;
const deps = @import("dependencies");

test "Dependency struct only" {
    const dep = deps.Dependency{
        .url = "https://github.com/example/test.git",
        .rev = "v1.0.0",
        .name = "test_dep",
    };
    
    try testing.expect(std.mem.eql(u8, dep.url, "https://github.com/example/test.git"));
    try testing.expect(std.mem.eql(u8, dep.rev, "v1.0.0"));
    try testing.expect(std.mem.eql(u8, dep.name, "test_dep"));
}

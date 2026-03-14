const std = @import("std");
const testing = std.testing;
const deps = @import("dependencies");

test "import only" {
    try testing.expect(true);
}

test "Dependency struct from import" {
    const dep = deps.Dependency{
        .url = "https://github.com/example/test.git",
        .rev = "v1.0.0",
        .name = "test_dep",
    };
    
    try testing.expect(std.mem.eql(u8, dep.url, "https://github.com/example/test.git"));
}

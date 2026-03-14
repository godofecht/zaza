const std = @import("std");
const cpp = @import("cpp_example.zig");
const builtin = @import("builtin");

const Port = 3000;

pub fn startServer(allocator: std.mem.Allocator, example: cpp.CppExample) !void {
    const address = try std.net.Address.parseIp("127.0.0.1", Port);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    std.debug.print("Server listening on http://127.0.0.1:{d}\n", .{Port});

    while (true) {
        const conn = try server.accept();
        defer conn.stream.close();

        var buf: [4096]u8 = undefined;
        const n = try conn.stream.read(&buf);
        const request = buf[0..n];

        if (std.mem.indexOf(u8, request, "POST /save") != null) {
            // Find the JSON payload
            if (std.mem.indexOf(u8, request, "\r\n\r\n")) |i| {
                const json = request[i + 4..];
                try saveConfig(allocator, json);
                
                // Send success response
                const response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\"}";
                _ = try conn.stream.write(response);
            }
        } else {
            // Serve the HTML page
            const response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n";
            _ = try conn.stream.write(response);
            try viewBuildConfig(example, conn.stream.writer());
        }
    }
}

fn saveConfig(allocator: std.mem.Allocator, json_str: []const u8) !void {
    // Parse the JSON
    var tree = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer tree.deinit();

    const root = try getObject(tree.value);

    // Generate the new build.zig content
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try buf.writer().writeAll(
        \\const std = @import("std");
        \\const cpp = @import("build_lib/cpp_example.zig");
        \\
        \\pub const example = cpp.CppExample{
        \\
    );

    // Write name and description
    try buf.writer().print("    .name = \"{s}\",\n", .{try getString(root.get("name").?)});
    try buf.writer().print("    .description = \"{s}\",\n", .{try getString(root.get("description").?)});

    // Write source files
    try buf.writer().writeAll("    .source_files = &.{");
    for (try getArray(root.get("source_files").?)) |src| {
        try buf.writer().print("\"{s}\",", .{try getString(src)});
    }
    try buf.writer().writeAll("},\n");

    // Write include dirs
    try buf.writer().writeAll("    .include_dirs = &.{");
    for (try getArray(root.get("include_dirs").?)) |dir| {
        try buf.writer().print("\"{s}\",", .{try getString(dir)});
    }
    try buf.writer().writeAll("},\n");

    // Write cpp flags
    try buf.writer().writeAll("    .cpp_flags = &.{");
    for (try getArray(root.get("cpp_flags").?)) |flag| {
        try buf.writer().print("\"{s}\",", .{try getString(flag)});
    }
    try buf.writer().writeAll("},\n");

    // Write dependencies
    try buf.writer().writeAll("    .deps = &.{\n");
    for (try getArray(root.get("dependencies").?)) |dep_val| {
        const dep = try getObject(dep_val);
        try buf.writer().print("        .{{ .name = \"{s}\", .url = \"{s}\", .type = .{s} }},\n", 
            .{
                try getString(dep.get("name").?),
                try getString(dep.get("url").?),
                try getString(dep.get("build_system").?),
            });
    }
    try buf.writer().writeAll("    },\n");

    // Write build systems
    try buf.writer().print("    .deps_build_system = .{s},\n", .{try getString(root.get("deps_build_system").?)});
    try buf.writer().print("    .main_build_system = .{s},\n", .{try getString(root.get("main_build_system").?)});

    // Write C++ standard
    try buf.writer().print("    .cpp_std = \"{s}\",\n", .{try getString(root.get("cpp_std").?)});

    // Close the struct
    try buf.writer().writeAll("};\n\n");

    // Add the build function
    try buf.writer().writeAll(
        \\pub fn build(b: *std.Build) !void {
        \\    const exe = try example.build(b);
        \\
        \\    const run_cmd = b.addRunArtifact(exe);
        \\    const run_step = b.step("run", "Run the example");
        \\    run_step.dependOn(&run_cmd.step);
        \\}
        \\
    );

    // Write the new build.zig
    try std.fs.cwd().writeFile(.{ .sub_path = "build.zig", .data = buf.items });
}

fn getString(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |s| s,
        else => error.ExpectedString,
    };
}

fn getArray(value: std.json.Value) ![]const std.json.Value {
    return switch (value) {
        .array => |a| a.items,
        else => error.ExpectedArray,
    };
}

fn getObject(value: std.json.Value) !std.json.ObjectMap {
    return switch (value) {
        .object => |o| o,
        else => error.ExpectedObject,
    };
}

pub fn viewBuildConfig(example: cpp.CppExample, writer: anytype) !void {
    try writer.writeAll(
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>Build Configuration Editor</title>
        \\    <style>
        \\        body {
        \\            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        \\            max-width: 800px;
        \\            margin: 2rem auto;
        \\            padding: 0 1rem;
        \\            background: #f5f5f5;
        \\        }
        \\        .card {
        \\            background: white;
        \\            border-radius: 8px;
        \\            padding: 1rem;
        \\            margin: 1rem 0;
        \\            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        \\        }
        \\        h1, h2 { color: #333; }
        \\        h2 { margin-top: 0; }
        \\        .tag {
        \\            display: inline-block;
        \\            padding: 0.25rem 0.5rem;
        \\            border-radius: 4px;
        \\            margin: 0.25rem;
        \\            font-size: 0.9rem;
        \\        }
        \\        .tag.build-system { background: #ffd700; }
        \\        .tag.cpp-std { background: #90ee90; }
        \\        .tag.config { background: #ff69b4; }
        \\        .tag.dep { background: #87ceeb; }
        \\        .tag.flag { background: #dda0dd; }
        \\        ul { list-style-type: none; padding-left: 0; }
        \\        li { margin: 0.5rem 0; }
        \\        input[type="text"], select {
        \\            width: 100%;
        \\            padding: 8px;
        \\            margin: 4px 0;
        \\            border: 1px solid #ddd;
        \\            border-radius: 4px;
        \\        }
        \\        .btn {
        \\            background: #4CAF50;
        \\            color: white;
        \\            padding: 8px 16px;
        \\            border: none;
        \\            border-radius: 4px;
        \\            cursor: pointer;
        \\            margin: 4px;
        \\        }
        \\        .btn:hover {
        \\            background: #45a049;
        \\        }
        \\        .btn.remove {
        \\            background: #f44336;
        \\        }
        \\        .btn.remove:hover {
        \\            background: #da190b;
        \\        }
        \\        .btn.add {
        \\            background: #2196F3;
        \\        }
        \\        .btn.add:hover {
        \\            background: #0b7dda;
        \\        }
        \\        #status {
        \\            position: fixed;
        \\            top: 20px;
        \\            right: 20px;
        \\            padding: 1rem;
        \\            border-radius: 4px;
        \\            display: none;
        \\        }
        \\        #status.success {
        \\            background: #4CAF50;
        \\            color: white;
        \\            display: block;
        \\        }
        \\        #status.error {
        \\            background: #f44336;
        \\            color: white;
        \\            display: block;
        \\        }
        \\    </style>
        \\    <script>
        \\        function addItem(listId) {
        \\            const list = document.getElementById(listId);
        \\            const newItem = document.createElement('li');
        \\            newItem.innerHTML = `
        \\                <input type="text" value="">
        \\                <button class="btn remove" onclick="this.parentElement.remove()">Remove</button>
        \\            `;
        \\            list.appendChild(newItem);
        \\        }
        \\
        \\        function addDependency() {
        \\            const list = document.getElementById('dependencies');
        \\            const newItem = document.createElement('li');
        \\            newItem.innerHTML = `
        \\                <input type="text" placeholder="Name" style="width: 30%">
        \\                <input type="text" placeholder="URL" style="width: 50%">
        \\                <select style="width: 15%">
        \\                    <option value="Zig">Zig</option>
        \\                    <option value="CMake">CMake</option>
        \\                </select>
        \\                <button class="btn remove" onclick="this.parentElement.remove()">Remove</button>
        \\            `;
        \\            list.appendChild(newItem);
        \\        }
        \\
        \\        function showStatus(message, isError) {
        \\            const status = document.getElementById('status');
        \\            status.textContent = message;
        \\            status.className = isError ? 'error' : 'success';
        \\            setTimeout(() => status.className = '', 3000);
        \\        }
        \\
        \\        async function saveBuildConfig() {
        \\            const config = {
        \\                name: document.getElementById('project-name').value,
        \\                description: document.getElementById('project-description').value,
        \\                cpp_std: document.getElementById('cpp-std').value,
        \\                main_build_system: document.getElementById('main-build-system').value,
        \\                deps_build_system: document.getElementById('deps-build-system').value,
        \\                source_files: Array.from(document.getElementById('source-files').getElementsByTagName('input')).map(i => i.value).filter(Boolean),
        \\                include_dirs: Array.from(document.getElementById('include-dirs').getElementsByTagName('input')).map(i => i.value).filter(Boolean),
        \\                cpp_flags: Array.from(document.getElementById('cpp-flags').getElementsByTagName('input')).map(i => i.value).filter(Boolean),
        \\                dependencies: Array.from(document.getElementById('dependencies').getElementsByTagName('li')).map(li => {
        \\                    const inputs = li.getElementsByTagName('input');
        \\                    const select = li.getElementsByTagName('select')[0];
        \\                    return {
        \\                        name: inputs[0].value,
        \\                        url: inputs[1].value,
        \\                        build_system: select ? select.value : 'Zig'
        \\                    };
        \\                }).filter(d => d.name && d.url)
        \\            };
        \\
        \\            try {
        \\                const response = await fetch('/save', {
        \\                    method: 'POST',
        \\                    headers: {
        \\                        'Content-Type': 'application/json',
        \\                    },
        \\                    body: JSON.stringify(config)
        \\                });
        \\
        \\                if (response.ok) {
        \\                    showStatus('Configuration saved successfully!', false);
        \\                } else {
        \\                    showStatus('Error saving configuration', true);
        \\                }
        \\            } catch (error) {
        \\                showStatus('Error: ' + error.message, true);
        \\            }
        \\        }
        \\    </script>
        \\</head>
        \\<body>
        \\    <div id="status"></div>
        \\    <h1>Build Configuration Editor</h1>
        \\
    );

    // Project Info
    try writer.print(
        \\    <div class="card">
        \\        <h2>Project Information</h2>
        \\        <label>Name:</label>
        \\        <input type="text" id="project-name" value="{s}">
        \\        <label>Description:</label>
        \\        <input type="text" id="project-description" value="{s}">
        \\    </div>
        \\
    , .{ example.name, example.description });

    // Build Systems
    try writer.print(
        \\    <div class="card">
        \\        <h2>Build Systems</h2>
        \\        <label>Main Build System:</label>
        \\        <select id="main-build-system">
        \\            <option value="Zig" {s}>Zig</option>
        \\            <option value="CMake" {s}>CMake</option>
        \\        </select>
        \\        <label>Dependencies Build System:</label>
        \\        <select id="deps-build-system">
        \\            <option value="Zig" {s}>Zig</option>
        \\            <option value="CMake" {s}>CMake</option>
        \\        </select>
        \\    </div>
        \\
    , .{
        if (example.main_build_system == .Zig) "selected" else "",
        if (example.main_build_system == .CMake) "selected" else "",
        if (example.deps_build_system == .Zig) "selected" else "",
        if (example.deps_build_system == .CMake) "selected" else "",
    });

    // C++ Standard
    try writer.print(
        \\    <div class="card">
        \\        <h2>C++ Standard</h2>
        \\        <select id="cpp-std">
        \\            <option value="11" {s}>C++11</option>
        \\            <option value="14" {s}>C++14</option>
        \\            <option value="17" {s}>C++17</option>
        \\            <option value="20" {s}>C++20</option>
        \\            <option value="23" {s}>C++23</option>
        \\        </select>
        \\    </div>
        \\
    , .{
        if (std.mem.eql(u8, example.cpp_std orelse "17", "11")) "selected" else "",
        if (std.mem.eql(u8, example.cpp_std orelse "17", "14")) "selected" else "",
        if (std.mem.eql(u8, example.cpp_std orelse "17", "17")) "selected" else "",
        if (std.mem.eql(u8, example.cpp_std orelse "17", "20")) "selected" else "",
        if (std.mem.eql(u8, example.cpp_std orelse "17", "23")) "selected" else "",
    });

    // Source Files
    try writer.writeAll(
        \\    <div class="card">
        \\        <h2>Source Files</h2>
        \\        <ul id="source-files">
        \\
    );
    for (example.source_files) |src| {
        try writer.print(
            \\            <li>
            \\                <input type="text" value="{s}">
            \\                <button class="btn remove" onclick="this.parentElement.remove()">Remove</button>
            \\            </li>
            \\
        , .{src});
    }
    try writer.writeAll(
        \\        </ul>
        \\        <button class="btn add" onclick="addItem('source-files')">Add Source File</button>
        \\    </div>
        \\
    );

    // Include Directories
    try writer.writeAll(
        \\    <div class="card">
        \\        <h2>Include Directories</h2>
        \\        <ul id="include-dirs">
        \\
    );
    for (example.include_dirs) |dir| {
        try writer.print(
            \\            <li>
            \\                <input type="text" value="{s}">
            \\                <button class="btn remove" onclick="this.parentElement.remove()">Remove</button>
            \\            </li>
            \\
        , .{dir});
    }
    try writer.writeAll(
        \\        </ul>
        \\        <button class="btn add" onclick="addItem('include-dirs')">Add Include Directory</button>
        \\    </div>
        \\
    );

    // Dependencies
    try writer.writeAll(
        \\    <div class="card">
        \\        <h2>Dependencies</h2>
        \\        <ul id="dependencies">
        \\
    );
    for (example.deps) |dep| {
        try writer.print(
            \\            <li>
            \\                <input type="text" value="{s}" style="width: 30%" placeholder="Name">
            \\                <input type="text" value="{s}" style="width: 50%" placeholder="URL">
            \\                <select style="width: 15%">
            \\                    <option value="Zig" {s}>Zig</option>
            \\                    <option value="CMake" {s}>CMake</option>
            \\                </select>
            \\                <button class="btn remove" onclick="this.parentElement.remove()">Remove</button>
            \\            </li>
            \\
        , .{
            dep.name,
            dep.url,
            if (dep.type orelse example.deps_build_system == .Zig) "selected" else "",
            if (dep.type orelse example.deps_build_system == .CMake) "selected" else "",
        });
    }
    try writer.writeAll(
        \\        </ul>
        \\        <button class="btn add" onclick="addDependency()">Add Dependency</button>
        \\    </div>
        \\
    );

    // Compiler Flags
    try writer.writeAll(
        \\    <div class="card">
        \\        <h2>Compiler Flags</h2>
        \\        <ul id="cpp-flags">
        \\
    );
    for (example.cpp_flags) |flag| {
        try writer.print(
            \\            <li>
            \\                <input type="text" value="{s}">
            \\                <button class="btn remove" onclick="this.parentElement.remove()">Remove</button>
            \\            </li>
            \\
        , .{flag});
    }
    try writer.writeAll(
        \\        </ul>
        \\        <button class="btn add" onclick="addItem('cpp-flags')">Add Compiler Flag</button>
        \\    </div>
        \\
        \\    <div class="card" style="text-align: center;">
        \\        <button class="btn" onclick="saveBuildConfig()" style="font-size: 1.2em;">Save Configuration</button>
        \\    </div>
        \\</body>
        \\</html>
        \\
    );
} 
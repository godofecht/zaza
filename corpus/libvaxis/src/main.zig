// Downstream Zig consumer of libvaxis. It calls vaxis.gwidth.gwidth, which
// resolves grapheme display widths through the Unicode data that vaxis's build
// generates at compile time via its `uucode` dependency. Correct widths here
// mean the whole build — vaxis, zigimg, and the generated Unicode table — came
// through the Zig build graph and works.
const std = @import("std");
const vaxis = @import("vaxis");

pub fn main() !void {
    const m: vaxis.gwidth.Method = .unicode;
    const ascii = vaxis.gwidth.gwidth("a", m); //            -> 1
    const wide = vaxis.gwidth.gwidth("\u{4e16}", m); // 世   -> 2 (East Asian wide)
    const combining = vaxis.gwidth.gwidth("e\u{0301}", m); // é (e + U+0301) -> 1

    std.debug.print(
        "zaza+vaxis slice: gwidth ascii={d} wide={d} combining={d}\n",
        .{ ascii, wide, combining },
    );
    if (ascii != 1 or wide != 2 or combining != 1) return error.UnexpectedWidth;
    std.debug.print("zaza+vaxis slice: generated Unicode table OK\n", .{});
}

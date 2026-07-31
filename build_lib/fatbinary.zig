// A toolchain-pure writer and reader for macOS universal (fat) binaries.
//
// A universal binary is several single-arch Mach-O artifacts concatenated
// behind a small fat header, so one file runs natively on Intel and Apple
// Silicon. This is what `lipo -create` produces. Doing it here keeps the build
// free of a dependency on Apple's `lipo` or the Xcode command line tools, and
// works the same on any host that can cross-compile the slices.
//
// Layout (all header fields big-endian, regardless of host byte order):
//
//   fat_header      magic (0xCAFEBABE), nfat_arch
//   fat_arch[n]     cputype, cpusubtype, offset, size, align  (5 x u32)
//   ... padding to each slice's alignment ...
//   slice bytes[n]
//
// See zaza#38. This is the combine step; building both slices and wiring it
// into the install stage is the remaining work.

const std = @import("std");

pub const FAT_MAGIC: u32 = 0xCAFEBABE;

// Mach-O cpu types. The 64-bit ABI bit is OR'd into the base type.
pub const CPU_ARCH_ABI64: u32 = 0x01000000;
pub const CPU_TYPE_X86_64: u32 = 7 | CPU_ARCH_ABI64; // 0x01000007
pub const CPU_TYPE_ARM64: u32 = 12 | CPU_ARCH_ABI64; // 0x0100000C

pub const CPU_SUBTYPE_X86_64_ALL: u32 = 3;
pub const CPU_SUBTYPE_ARM64_ALL: u32 = 0;

pub const header_size: usize = 8; // magic + nfat_arch
pub const arch_entry_size: usize = 20; // five u32 fields

pub const Arch = enum {
    x86_64,
    aarch64,

    pub fn cpuType(self: Arch) u32 {
        return switch (self) {
            .x86_64 => CPU_TYPE_X86_64,
            .aarch64 => CPU_TYPE_ARM64,
        };
    }

    pub fn cpuSubtype(self: Arch) u32 {
        return switch (self) {
            .x86_64 => CPU_SUBTYPE_X86_64_ALL,
            .aarch64 => CPU_SUBTYPE_ARM64_ALL,
        };
    }

    // Slice alignment as a power of two. These match the values `lipo` picks:
    // 2^12 for x86_64, 2^14 for arm64 (16 KB pages).
    pub fn alignPow2(self: Arch) u32 {
        return switch (self) {
            .x86_64 => 12,
            .aarch64 => 14,
        };
    }

    // Recover an Arch from a Mach-O (cputype, cpusubtype) pair, ignoring the
    // capability bits some subtypes carry in their high byte. Null if unknown.
    pub fn fromCpu(cputype: u32, cpusubtype: u32) ?Arch {
        _ = cpusubtype;
        return switch (cputype) {
            CPU_TYPE_X86_64 => .x86_64,
            CPU_TYPE_ARM64 => .aarch64,
            else => null,
        };
    }
};

pub const Slice = struct {
    arch: Arch,
    bytes: []const u8,
};

fn alignForward(offset: usize, pow2: u32) usize {
    const a: usize = @as(usize, 1) << @intCast(pow2);
    return (offset + a - 1) & ~(a - 1);
}

// Total byte length the fat binary will occupy for `slices`.
fn layoutSize(slices: []const Slice) usize {
    var offset = header_size + arch_entry_size * slices.len;
    for (slices) |s| {
        offset = alignForward(offset, s.arch.alignPow2());
        offset += s.bytes.len;
    }
    return offset;
}

fn putU32(buf: []u8, at: usize, value: u32) void {
    std.mem.writeInt(u32, buf[at..][0..4], value, .big);
}

fn getU32(buf: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, buf[at..][0..4], .big);
}

pub const WriteError = error{ NoSlices, DuplicateArch };

// Build the universal binary for `slices` into a freshly allocated buffer the
// caller owns. Slices are emitted in the given order, each at its arch's
// alignment. A fat file with a single arch is valid.
pub fn build(allocator: std.mem.Allocator, slices: []const Slice) (WriteError || std.mem.Allocator.Error)![]u8 {
    if (slices.len == 0) return error.NoSlices;
    // The fat table keys on arch; two slices of the same arch are ambiguous.
    for (slices, 0..) |a, i| {
        for (slices[i + 1 ..]) |b| {
            if (a.arch == b.arch) return error.DuplicateArch;
        }
    }

    const total = layoutSize(slices);
    const buf = try allocator.alloc(u8, total);
    @memset(buf, 0);

    putU32(buf, 0, FAT_MAGIC);
    putU32(buf, 4, @intCast(slices.len));

    var data_offset = header_size + arch_entry_size * slices.len;
    for (slices, 0..) |s, i| {
        data_offset = alignForward(data_offset, s.arch.alignPow2());

        const entry = header_size + arch_entry_size * i;
        putU32(buf, entry + 0, s.arch.cpuType());
        putU32(buf, entry + 4, s.arch.cpuSubtype());
        putU32(buf, entry + 8, @intCast(data_offset));
        putU32(buf, entry + 12, @intCast(s.bytes.len));
        putU32(buf, entry + 16, s.arch.alignPow2());

        @memcpy(buf[data_offset .. data_offset + s.bytes.len], s.bytes);
        data_offset += s.bytes.len;
    }

    return buf;
}

pub const ParsedSlice = struct {
    arch: ?Arch,
    cputype: u32,
    cpusubtype: u32,
    offset: u32,
    @"align": u32,
    bytes: []const u8, // borrows from the input buffer
};

pub const ParseError = error{ TooShort, BadMagic, TruncatedTable, SliceOutOfRange };

pub const Parsed = struct {
    slices: []ParsedSlice,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Parsed) void {
        self.allocator.free(self.slices);
    }
};

// Read a fat binary. The returned slice byte spans borrow from `data`, so keep
// `data` alive for the lifetime of the result. Call deinit to free the table.
pub fn parse(allocator: std.mem.Allocator, data: []const u8) (ParseError || std.mem.Allocator.Error)!Parsed {
    if (data.len < header_size) return error.TooShort;
    if (getU32(data, 0) != FAT_MAGIC) return error.BadMagic;

    const n = getU32(data, 4);
    const table_end = header_size + arch_entry_size * @as(usize, n);
    if (data.len < table_end) return error.TruncatedTable;

    const out = try allocator.alloc(ParsedSlice, n);
    errdefer allocator.free(out);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const entry = header_size + arch_entry_size * i;
        const cputype = getU32(data, entry + 0);
        const cpusubtype = getU32(data, entry + 4);
        const offset = getU32(data, entry + 8);
        const size = getU32(data, entry + 12);
        const alignment = getU32(data, entry + 16);

        const start: usize = offset;
        const end: usize = start + size;
        if (end > data.len) return error.SliceOutOfRange;

        out[i] = .{
            .arch = Arch.fromCpu(cputype, cpusubtype),
            .cputype = cputype,
            .cpusubtype = cpusubtype,
            .offset = offset,
            .@"align" = alignment,
            .bytes = data[start..end],
        };
    }

    return .{ .slices = out, .allocator = allocator };
}

// --- tests -----------------------------------------------------------------

const testing = std.testing;

test "build then parse round-trips two arches" {
    const x86 = "x86_64 slice bytes, arbitrary length here";
    const arm = "aarch64 slice, a different length entirely!!";

    const fat = try build(testing.allocator, &.{
        .{ .arch = .x86_64, .bytes = x86 },
        .{ .arch = .aarch64, .bytes = arm },
    });
    defer testing.allocator.free(fat);

    var parsed = try parse(testing.allocator, fat);
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 2), parsed.slices.len);

    try testing.expectEqual(Arch.x86_64, parsed.slices[0].arch.?);
    try testing.expectEqualStrings(x86, parsed.slices[0].bytes);

    try testing.expectEqual(Arch.aarch64, parsed.slices[1].arch.?);
    try testing.expectEqualStrings(arm, parsed.slices[1].bytes);
}

test "header is big-endian FAT_MAGIC with the arch count" {
    const fat = try build(testing.allocator, &.{
        .{ .arch = .x86_64, .bytes = "a" },
        .{ .arch = .aarch64, .bytes = "b" },
    });
    defer testing.allocator.free(fat);

    // 0xCAFEBABE laid out big-endian, then nfat_arch = 2.
    try testing.expectEqualSlices(u8, &.{ 0xCA, 0xFE, 0xBA, 0xBE }, fat[0..4]);
    try testing.expectEqual(@as(u32, 2), getU32(fat, 4));
}

test "each slice sits at its arch alignment and carries the right cpu type" {
    const fat = try build(testing.allocator, &.{
        .{ .arch = .x86_64, .bytes = "intel" },
        .{ .arch = .aarch64, .bytes = "apple" },
    });
    defer testing.allocator.free(fat);

    var parsed = try parse(testing.allocator, fat);
    defer parsed.deinit();

    const x = parsed.slices[0];
    try testing.expectEqual(CPU_TYPE_X86_64, x.cputype);
    try testing.expectEqual(@as(u32, 12), x.@"align");
    try testing.expectEqual(@as(u32, 0), x.offset % (@as(u32, 1) << 12));

    const a = parsed.slices[1];
    try testing.expectEqual(CPU_TYPE_ARM64, a.cputype);
    try testing.expectEqual(@as(u32, 14), a.@"align");
    try testing.expectEqual(@as(u32, 0), a.offset % (@as(u32, 1) << 14));
}

test "a single-arch fat binary is valid" {
    const fat = try build(testing.allocator, &.{
        .{ .arch = .aarch64, .bytes = "only one slice" },
    });
    defer testing.allocator.free(fat);

    var parsed = try parse(testing.allocator, fat);
    defer parsed.deinit();
    try testing.expectEqual(@as(usize, 1), parsed.slices.len);
    try testing.expectEqualStrings("only one slice", parsed.slices[0].bytes);
}

test "build rejects empty and duplicate-arch input" {
    try testing.expectError(error.NoSlices, build(testing.allocator, &.{}));
    try testing.expectError(error.DuplicateArch, build(testing.allocator, &.{
        .{ .arch = .x86_64, .bytes = "one" },
        .{ .arch = .x86_64, .bytes = "two" },
    }));
}

test "parse rejects short input, bad magic, and out-of-range slices" {
    try testing.expectError(error.TooShort, parse(testing.allocator, &.{ 1, 2, 3 }));

    var not_fat = [_]u8{0} ** 8;
    try testing.expectError(error.BadMagic, parse(testing.allocator, &not_fat));

    // Claim one arch whose slice runs past the end of the buffer.
    var truncated = [_]u8{0} ** (header_size + arch_entry_size);
    putU32(&truncated, 0, FAT_MAGIC);
    putU32(&truncated, 4, 1);
    putU32(&truncated, header_size + 8, 9999); // offset far past the end
    putU32(&truncated, header_size + 12, 16); // size
    try testing.expectError(error.SliceOutOfRange, parse(testing.allocator, &truncated));
}

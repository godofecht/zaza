const std = @import("std");

pub const Calculator = opaque {
    const Self = @This();

    pub fn create() !*Self {
        return @ptrCast(cpp_create());
    }

    pub fn destroy(self: *Self) void {
        cpp_destroy(@ptrCast(self));
    }

    pub fn add(self: *Self, a: i32, b: i32) i32 {
        return cpp_add(@ptrCast(self), a, b);
    }

    pub fn subtract(self: *Self, a: i32, b: i32) i32 {
        return cpp_subtract(@ptrCast(self), a, b);
    }

    pub fn multiply(self: *Self, a: i32, b: i32) i32 {
        return cpp_multiply(@ptrCast(self), a, b);
    }

    pub fn divide(self: *Self, a: i32, b: i32) f64 {
        return cpp_divide(@ptrCast(self), a, b);
    }
};

extern "c" fn cpp_create() ?*anyopaque;
extern "c" fn cpp_destroy(ptr: *anyopaque) void;
extern "c" fn cpp_add(ptr: *anyopaque, a: i32, b: i32) i32;
extern "c" fn cpp_subtract(ptr: *anyopaque, a: i32, b: i32) i32;
extern "c" fn cpp_multiply(ptr: *anyopaque, a: i32, b: i32) i32;
extern "c" fn cpp_divide(ptr: *anyopaque, a: i32, b: i32) f64; 
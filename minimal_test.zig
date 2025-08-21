const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // This should work according to the standard library examples
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    std.debug.print("Success!\n", .{});
}
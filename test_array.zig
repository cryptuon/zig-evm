const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test ArrayList initialization
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    std.debug.print("ArrayList test successful\n", .{});
}
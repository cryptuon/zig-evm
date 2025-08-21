const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Use the unmanaged approach
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    // Append elements (note we need to pass the allocator)
    try list.append(allocator, 42);
    try list.append(allocator, 100);

    std.debug.print("Success! List length: {d}\n", .{list.items.len});
}
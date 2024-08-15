const std = @import("std");

// EVM Memory implementation
pub const Memory = struct {
    data: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Memory {
        return Memory{
            .data = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn store(self: *Memory, offset: usize, value: []const u8) !void {
        try self.data.replaceRange(offset, value.len, value);
    }

    pub fn load(self: Memory, offset: usize, len: usize) []const u8 {
        return self.data.items[offset .. offset + len];
    }

    // Add more memory operations as needed
};

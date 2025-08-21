const std = @import("std");

pub const BigInt = @import("bigint.zig").BigInt;

// EVM Stack implementation
pub const Stack = struct {
    items: std.ArrayListUnmanaged(BigInt),

    pub fn init(allocator: std.mem.Allocator) Stack {
        _ = allocator; // Suppress unused parameter warning
        return Stack{
            .items = .{},
        };
    }

    pub fn deinit(self: *Stack, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
    }

    pub fn push(self: *Stack, allocator: std.mem.Allocator, value: BigInt) !void {
        // Check stack limit (1024 items)
        if (self.items.items.len >= 1024) {
            return error.StackOverflow;
        }
        try self.items.append(allocator, value);
    }

    pub fn pop(self: *Stack) ?BigInt {
        if (self.items.items.len == 0) {
            return null;
        }
        return self.items.pop();
    }

    // Add more stack operations as needed
};

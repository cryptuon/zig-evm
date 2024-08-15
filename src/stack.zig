const std = @import("std");

pub const BigInt = @import("bigint.zig").BigInt;

// EVM Stack implementation
pub const Stack = struct {
    items: std.ArrayList(BigInt),

    pub fn init(allocator: std.mem.Allocator) Stack {
        return Stack{
            .items = std.ArrayList(BigInt).init(allocator),
        };
    }

    pub fn push(self: *Stack, value: BigInt) !void {
        try self.items.append(value);
    }

    pub fn pop(self: *Stack) ?BigInt {
        return self.items.popOrNull();
    }

    // Add more stack operations as needed
};

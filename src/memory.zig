const std = @import("std");

// EVM Memory implementation
pub const Memory = struct {
    data: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator) Memory {
        _ = allocator; // Suppress unused parameter warning
        return Memory{
            .data = .{},
        };
    }

    pub fn deinit(self: *Memory, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
    }

    pub fn store(self: *Memory, allocator: std.mem.Allocator, offset: usize, value: []const u8) !void {
        // Ensure memory is large enough
        const required_size = offset + value.len;
        if (required_size > self.data.items.len) {
            try self.data.resize(allocator, required_size);
        }
        
        // Copy value to memory
        for (value, 0..) |byte, i| {
            self.data.items[offset + i] = byte;
        }
    }

    pub fn load(self: *Memory, allocator: std.mem.Allocator, offset: usize, len: usize) ![]const u8 {
        // Ensure memory is large enough
        const required_size = offset + len;
        if (required_size > self.data.items.len) {
            const old_len = self.data.items.len;
            try self.data.resize(allocator, required_size);
            // Initialize new memory to zero
            for (self.data.items[old_len..]) |*byte| {
                byte.* = 0;
            }
        }

        return self.data.items[offset .. offset + len];
    }

    pub fn loadWord(self: *Memory, allocator: std.mem.Allocator, offset: usize) ![]const u8 {
        // Load a 32-byte word from memory
        return self.load(allocator, offset, 32);
    }

    pub fn storeByte(self: *Memory, allocator: std.mem.Allocator, offset: usize, value: u8) !void {
        // Ensure memory is large enough
        const required_size = offset + 1;
        if (required_size > self.data.items.len) {
            const old_len = self.data.items.len;
            try self.data.resize(allocator, required_size);
            // Initialize new memory to zero
            for (self.data.items[old_len..]) |*byte| {
                byte.* = 0;
            }
        }

        self.data.items[offset] = value;
    }

    pub fn size(self: *Memory) usize {
        return self.data.items.len;
    }
};

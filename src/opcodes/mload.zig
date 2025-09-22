// File: src/opcodes/mload.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.MLOAD),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.stack.pop()) |offset_bigint| {
        // Convert BigInt offset to usize (only use least significant word for simplicity)
        const offset = @as(usize, @intCast(offset_bigint.data[0]));

        // Load 32 bytes from memory
        const word_bytes = try evm.memory.loadWord(evm.allocator, offset);

        // Convert bytes to BigInt (big-endian)
        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        for (0..32) |i| {
            const byte_val = word_bytes[i];
            const word_idx = i / 8; // Which u64 word (0-3)
            const byte_idx = i % 8; // Which byte within the word (0-7)

            // Shift byte into correct position (big-endian)
            const shift = @as(u6, @intCast(56 - (byte_idx * 8)));
            result.data[word_idx] |= @as(u64, byte_val) << shift;
        }

        try evm.stack.push(evm.allocator, result);
    } else return error.StackUnderflow;
}
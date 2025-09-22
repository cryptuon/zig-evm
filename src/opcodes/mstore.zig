// File: src/opcodes/mstore.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.MSTORE),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.stack.pop()) |offset_bigint| {
        if (evm.stack.pop()) |value_bigint| {
            // Convert BigInt offset to usize
            const offset = @as(usize, @intCast(offset_bigint.data[0]));

            // Convert BigInt value to 32 bytes (big-endian)
            var word_bytes: [32]u8 = undefined;
            for (0..32) |i| {
                const word_idx = i / 8; // Which u64 word (0-3)
                const byte_idx = i % 8; // Which byte within the word (0-7)

                // Extract byte from correct position (big-endian)
                const shift = @as(u6, @intCast(56 - (byte_idx * 8)));
                word_bytes[i] = @as(u8, @truncate(value_bigint.data[word_idx] >> shift));
            }

            // Store 32 bytes to memory
            try evm.memory.store(evm.allocator, offset, &word_bytes);
        } else return error.StackUnderflow;
    } else return error.StackUnderflow;
}
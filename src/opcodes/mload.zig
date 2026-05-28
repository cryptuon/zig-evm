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

        // Load 32 bytes from memory and interpret big-endian (matches fromBytes
        // used elsewhere, and MSTORE's layout).
        const word_bytes = try evm.memory.loadWord(evm.allocator, offset);
        var buf: [32]u8 = undefined;
        @memcpy(&buf, word_bytes[0..32]);
        try evm.stack.push(evm.allocator, BigInt.fromBytes(buf));
    } else return error.StackUnderflow;
}
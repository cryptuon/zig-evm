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
            const offset = @as(usize, @intCast(offset_bigint.data[0]));
            // Canonical big-endian 32-byte word (matches toBytes used elsewhere).
            const word_bytes = value_bigint.toBytes();
            try evm.memory.store(evm.allocator, offset, &word_bytes);
        } else return error.StackUnderflow;
    } else return error.StackUnderflow;
}
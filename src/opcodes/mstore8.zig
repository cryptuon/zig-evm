// File: src/opcodes/mstore8.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.MSTORE8),
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

            // Extract least significant byte from value
            const byte_value = @as(u8, @truncate(value_bigint.data[0]));

            // Store single byte to memory
            try evm.memory.storeByte(evm.allocator, offset, byte_value);
        } else return error.StackUnderflow;
    } else return error.StackUnderflow;
}
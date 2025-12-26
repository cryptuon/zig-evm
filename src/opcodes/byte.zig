// File: src/opcodes/byte.zig
// BYTE (0x1a): Extract a byte from a 256-bit word
// Stack: i, x -> byte
// Returns the i-th byte of x (0 = most significant, 31 = least significant)
// Returns 0 if i >= 32

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.BYTE),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    const i = evm.stack.pop() orelse return error.StackUnderflow;
    const x = evm.stack.pop() orelse return error.StackUnderflow;

    // Use BigInt's getByte method
    const result = x.getByte(i);
    try evm.stack.push(evm.allocator, result);
}

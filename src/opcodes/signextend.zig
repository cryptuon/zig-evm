// File: src/opcodes/signextend.zig
// SIGNEXTEND (0x0b): Sign extend a value
// Stack: b, x -> result
// Sign-extends x from (b+1) bytes to 32 bytes
// The sign bit is at position (b+1)*8-1 counting from LSB

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.SIGNEXTEND),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    const b = evm.stack.pop() orelse return error.StackUnderflow;
    const x = evm.stack.pop() orelse return error.StackUnderflow;

    // Use BigInt's signExtend method
    const result = x.signExtend(b);
    try evm.stack.push(evm.allocator, result);
}

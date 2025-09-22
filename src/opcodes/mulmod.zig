// File: src/opcodes/mulmod.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.MULMOD),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.stack.pop()) |n| {
        if (evm.stack.pop()) |b| {
            if (evm.stack.pop()) |a| {
                // Check for modulo by zero
                if (n.isZero()) {
                    try evm.stack.push(evm.allocator, BigInt.init(0));
                } else {
                    // (a * b) % n
                    const product = a.mul(b);
                    const result = product.mod(n);
                    try evm.stack.push(evm.allocator, result);
                }
            } else return error.StackUnderflow;
        } else return error.StackUnderflow;
    } else return error.StackUnderflow;
}
// File: src/opcodes/smod.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.SMOD),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.stack.pop()) |b| {
        if (evm.stack.pop()) |a| {
            // Check for modulo by zero
            if (b.isZero()) {
                try evm.stack.push(evm.allocator, BigInt.init(0));
            } else {
                // Simplified signed modulo - handle basic cases
                if (a.fitsInU64() and b.fitsInU64()) {
                    const a_signed = @as(i64, @bitCast(a.data[0]));
                    const b_signed = @as(i64, @bitCast(b.data[0]));
                    const result = @rem(a_signed, b_signed);
                    try evm.stack.push(evm.allocator, BigInt.init(@as(u64, @bitCast(result))));
                } else {
                    // For larger numbers, fallback to unsigned modulo
                    try evm.stack.push(evm.allocator, a.mod(b));
                }
            }
        } else return error.StackUnderflow;
    } else return error.StackUnderflow;
}
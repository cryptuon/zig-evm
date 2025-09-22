// File: src/opcodes/div.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.DIV),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.stack.pop()) |b| {
        if (evm.stack.pop()) |a| {
            // Check for division by zero
            if (b.isZero()) {
                try evm.stack.push(evm.allocator, BigInt.init(0));
            } else {
                try evm.stack.push(evm.allocator, a.div(b));
            }
        } else return error.StackUnderflow;
    } else return error.StackUnderflow;
}
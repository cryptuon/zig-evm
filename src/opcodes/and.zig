// File: src/opcodes/and.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.AND),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.stack.pop()) |b| {
        if (evm.stack.pop()) |a| {
            try evm.stack.push(evm.allocator, a.bitwiseAnd(b));
        } else return error.StackUnderflow;
    } else return error.StackUnderflow;
}
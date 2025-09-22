// File: src/opcodes/dup1.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.DUP1),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Duplicate the top stack item
    if (evm.stack.items.items.len > 0) {
        const value = evm.stack.items.items[evm.stack.items.items.len - 1];
        try evm.stack.push(evm.allocator, value);
    } else return error.StackUnderflow;
}